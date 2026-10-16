import AppKit
import Carbon
import Combine
import WebKit

@MainActor
final class BrowserLookupCoordinator: NSObject, ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var query = ""
    @Published private(set) var destination = BrowserLookupDestination.search
    @Published private(set) var message: String?
    @Published private(set) var image: BrowserLookupImage?
    @Published private(set) var isSearchingImage = false
    @Published private(set) var hasStartedImageSearch = false
    @Published private(set) var isShortcutEnabled: Bool
    @Published private(set) var shortcutError: String?
    var onRequest: (() -> Void)?
    var onDismiss: ((Bool) -> Void)?
    private let tabs: BrowserTabsModel
    private let search: (String) -> URL?
    private let defaults: UserDefaults
    private let clipboard: NSPasteboard
    private enum Request { case text(String, BrowserLookupDestination), image(BrowserLookupImage), message(String) }
    private var pending: Request?
    private var origin: NSRunningApplication?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var escapeMonitor: Any?
    private var tabObservation: AnyCancellable?
    private var lensTask: Task<Void, Never>?
    private var captureProcess: Process?
    private var presentationID = UUID()
    private var isStopped = false
    private static let shortcutKey = "notchBrowser.lookupShortcutEnabled"

    var hasPendingRequest: Bool { pending != nil }

    init(tabs: BrowserTabsModel, library: BrowserLibrary, defaults: UserDefaults = .standard,
         clipboard: NSPasteboard = .general, search: ((String) -> URL?)? = nil) {
        self.tabs = tabs
        self.search = search ?? { library.searchEngine.searchURL(for: $0) }
        self.defaults = defaults
        self.clipboard = clipboard
        isShortcutEnabled = defaults.object(forKey: Self.shortcutKey) as? Bool ?? true
        super.init()
        tabObservation = tabs.$activeTabID.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPresented, !self.tabs.isShowingLookup else { return }
                self.end(restoreFocus: false)
            }
        }
    }

    func start() {
        isStopped = false
        NSApplication.shared.servicesProvider = self
        NSUpdateDynamicServices()
        updateShortcut()
    }

    func stop() {
        isStopped = true
        lensTask?.cancel()
        BrowserLensHandoff.cancel(in: tabs.tabs.first(where: { $0.id == tabs.lookupTabID })?.webView)
        if captureProcess?.isRunning == true { captureProcess?.terminate() }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        hotKey = nil; hotKeyHandler = nil
        removeEscapeMonitor()
    }

    func setShortcutEnabled(_ enabled: Bool) {
        isShortcutEnabled = enabled
        defaults.set(enabled, forKey: Self.shortcutKey)
        updateShortcut()
    }

    private func updateShortcut() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        hotKey = nil; hotKeyHandler = nil; shortcutError = nil
        guard isShortcutEnabled else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                id.signature == 0x4E4F5443, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            let coordinator = Unmanaged<BrowserLookupCoordinator>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in coordinator.lookUpClipboard() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        guard installed == noErr else { shortcutError = "Clipboard shortcut is unavailable. Use the menu or Services."; return }
        let registered = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | shiftKey),
            EventHotKeyID(signature: 0x4E4F5443, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if registered != noErr {
            shortcutError = "Control–Shift–Space is already in use. Use the menu or Services."
            if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
            hotKeyHandler = nil
        }
    }

    func lookUpClipboard() {
        do {
            if let image = try BrowserLookupImage.fromPasteboard(clipboard) { enqueue(.image(image)) }
            else { enqueue(.text(try BrowserLookupDestination.validatedText(clipboard.string(forType: .string)), .search)) }
        }
        catch { enqueue(.message(error.localizedDescription)) }
    }

    @objc func searchInNotch(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        receive(pasteboard, destination: .search, error: error)
    }

    @objc func translateInNotch(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        receive(pasteboard, destination: .translate, error: error)
    }

    @objc func searchImageInNotch(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        do {
            guard let image = try BrowserLookupImage.fromPasteboard(pasteboard) else { throw BrowserLookupError.invalidImage }
            enqueue(.image(image))
        } catch let failure { error.pointee = failure.localizedDescription as NSString }
    }

    private func receive(_ pasteboard: NSPasteboard, destination: BrowserLookupDestination,
                         error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        do { enqueue(.text(try BrowserLookupDestination.validatedText(pasteboard.string(forType: .string)), destination)) }
        catch let failure { error.pointee = failure.localizedDescription as NSString }
    }

    private func enqueue(_ request: Request, captureOrigin: Bool = true) {
        if captureOrigin, let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            origin = app
        }
        pending = request
        onRequest?()
    }

    func presentPending() {
        guard let pending else { return }
        self.pending = nil
        lensTask?.cancel()
        BrowserLensHandoff.cancel(in: tabs.tabs.first(where: { $0.id == tabs.lookupTabID })?.webView)
        tabs.tabs.first(where: { $0.id == tabs.lookupTabID })?.lookupUploadFile = nil
        presentationID = UUID()
        image = nil; isSearchingImage = false; hasStartedImageSearch = false
        isPresented = true
        switch pending {
        case .text(let text, let destination):
            query = text; self.destination = destination; message = nil
            let browser = tabs.beginLookup()
            if let url = destination.url(for: text, search: search) { browser.navigate(to: url) }
        case .message(let text):
            query = ""; message = text; destination = .search
            _ = tabs.beginLookup(reset: true)
        case .image(let image):
            query = ""; message = nil; self.image = image
            let browser = tabs.beginLookup(reset: true)
            browser.stopLoading()
            browser.lookupUploadFile = image.fileURL
        }
        installEscapeMonitor()
    }

    func selectDestination(_ destination: BrowserLookupDestination) {
        guard isPresented, tabs.isShowingLookup, !query.isEmpty else { return }
        self.destination = destination
        if let url = destination.url(for: query, search: search) { tabs.activeBrowser.navigate(to: url) }
    }

    func searchImage() {
        guard isPresented, tabs.isShowingLookup, let image, !isSearchingImage else { return }
        let browser = tabs.activeBrowser
        let id = presentationID
        isSearchingImage = true
        hasStartedImageSearch = true
        message = "Opening Google Lens…"
        browser.navigate(to: BrowserLensHandoff.startURL)
        let webView = browser.ensureWebView()
        lensTask?.cancel()
        lensTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let readyDeadline = Date().addingTimeInterval(15)
                while browser.isLoading || webView.isLoading || !BrowserLensHandoff.isUploadPage(webView.url) {
                    try Task.checkCancellation()
                    guard Date() < readyDeadline else { throw URLError(.timedOut) }
                    if let error = browser.errorMessage { throw NSError(domain: "NotchLookup", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                guard !Task.isCancelled, id == self.presentationID, self.tabs.isShowingLookup else { return }
                let status = try await BrowserLensHandoff.submit(image, in: webView, requestID: id)
                guard !Task.isCancelled, id == self.presentationID else { return }
                if status == "submitted" {
                    self.message = "Searching with Google Lens…"
                    let resultDeadline = Date().addingTimeInterval(15)
                    while !BrowserLensHandoff.isResultsPage(webView.url) {
                        try Task.checkCancellation()
                        guard Date() < resultDeadline else { throw URLError(.timedOut) }
                        try await Task.sleep(nanoseconds: 150_000_000)
                    }
                    self.message = nil
                } else {
                    self.message = "Open Google’s image search, then drag the image below into its upload area."
                }
            } catch {
                guard !Task.isCancelled, id == self.presentationID else { return }
                self.message = "If Lens hasn’t opened your results, drag the image below into Google’s upload area."
            }
            guard !Task.isCancelled, id == self.presentationID else { return }
            self.isSearchingImage = false
        }
    }

    func captureScreenRegion(hideBrowser: () -> Void) {
        guard captureProcess == nil else { return }
        let current = NSWorkspace.shared.frontmostApplication
        let source = current?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? origin : current
        hideBrowser()
        if let source, source.processIdentifier != ProcessInfo.processInfo.processIdentifier { origin = source }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notch-capture-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = directory.appendingPathComponent("Selection.png")
            let process = Process()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-s", "-x", file.path]
            process.standardError = errors
            captureProcess = process
            process.terminationHandler = { [weak self] process in
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                Task { @MainActor [weak self] in
                    defer { try? FileManager.default.removeItem(at: directory) }
                    guard let self, !self.isStopped else { return }
                    self.captureProcess = nil
                    if FileManager.default.fileExists(atPath: file.path) {
                        do { self.enqueue(.image(try BrowserLookupImage.fromFile(file)), captureOrigin: false) }
                        catch { self.enqueue(.message(error.localizedDescription), captureOrigin: false) }
                    } else if process.terminationStatus != 0 && !errorData.isEmpty {
                        self.enqueue(.message("Screen capture wasn’t available. Allow Screen Recording for Notch Browser in System Settings, or copy an image instead."), captureOrigin: false)
                    }
                }
            }
            try process.run()
        } catch {
            captureProcess = nil
            try? FileManager.default.removeItem(at: directory)
            enqueue(.message("Screen capture couldn’t start. Try copying an image instead."))
        }
    }

    func keepAsTab() {
        guard tabs.isShowingLookup else { return }
        tabs.activeBrowser.lookupUploadFile = nil
        tabs.keepLookup()
        clearPresentation(restoreFocus: false)
    }

    func openInDefaultBrowser() {
        guard tabs.isShowingLookup, let url = tabs.activeBrowser.currentURL ?? tabs.activeBrowser.requestedURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        if NSWorkspace.shared.open(url) { onDismiss?(false) }
    }

    func end(restoreFocus: Bool) {
        guard isPresented else { return }
        BrowserLensHandoff.cancel(in: tabs.tabs.first(where: { $0.id == tabs.lookupTabID })?.webView)
        tabs.endLookup()
        clearPresentation(restoreFocus: restoreFocus)
    }

    private func clearPresentation(restoreFocus: Bool) {
        let app = origin
        presentationID = UUID()
        lensTask?.cancel(); lensTask = nil
        if tabs.isShowingLookup { tabs.activeBrowser.lookupUploadFile = nil }
        image = nil; isSearchingImage = false; hasStartedImageSearch = false
        isPresented = false; query = ""; message = nil; origin = nil
        removeEscapeMonitor()
        if restoreFocus, let app, !app.isTerminated { app.activate(options: []) }
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.tabs.isShowingLookup,
                  !self.tabs.activeBrowser.isFindVisible,
                  let window = event.window, window.attachedSheet == nil, window.sheetParent == nil else { return event }
            if let pageWindow = self.tabs.activeBrowser.webView?.window {
                guard pageWindow === window else { return event }
            } else if !(window is NSPanel) { return event }
            self.onDismiss?(true)
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }
}
