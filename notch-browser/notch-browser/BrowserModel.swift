import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class BrowserModel: ObservableObject {
    let id = UUID()
    static var desktopSafariUserAgent: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X \(version.majorVersion)_\(version.minorVersion)_\(version.patchVersion)) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(version.majorVersion).\(version.minorVersion) Safari/605.1.15"
    }

    @Published var addressText: String
    @Published private(set) var pageTitle = "Ready when you are"
    @Published private(set) var currentURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastPageSnapshot: NSImage?
    @Published private(set) var isPresentationReady = false
    @Published private(set) var isEmpty: Bool
    @Published private(set) var addressFocusRequest: UUID?
    @Published private(set) var findFocusRequest: UUID?
    @Published private(set) var isFindVisible = false
    @Published var findQuery = "" { didSet { scheduleFind() } }
    @Published private(set) var findMatchFound: Bool?
    private(set) var isEditingAddress = false

    private(set) var requestedURL: URL?
    private(set) var navigationRequestID = UUID()
    private(set) var documentEpoch = UUID()
    let agentFrames = BrowserAgentFrameRegistry()
    let pageInteraction = BrowserPageInteraction()
    // Keep the WebKit view alive while the compact surface is shown. The
    // expanded SwiftUI hierarchy is intentionally removed in compact mode,
    // but the browsing session must continue to own its page, history, scroll
    // position, and in-page form state.
    private(set) var webView: WKWebView?
    private var navigationDelegate: BrowserNavigationDelegate?
    private var navigationObservations: [NSKeyValueObservation] = []
    private var pendingNavigation: Task<Void, Never>?
    private var submittedRequestID: UUID?
    private var snapshotCaptureID: UUID?
    private var presentationID = UUID()
    private(set) var snapshotMemoryCost = 0
    private(set) var snapshotCapturedAt: Date?
    private var findTask: Task<Void, Never>?
    private var findRequestID = UUID()

    private let library: BrowserLibrary
    var onSessionChange: (() -> Void)?
    var onCreateWebView: ((WKWebViewConfiguration, URL?) -> WKWebView)?
    var lookupUploadFile: URL?
    var onSnapshotChange: (() -> Void)?

    var websiteDataStore: WKWebsiteDataStore {
        library.websiteDataStore
    }

    init(library: BrowserLibrary? = nil, startsEmpty: Bool = false, initialURL: URL? = nil,
         restoredTitle: String? = nil) {
        let library = library ?? BrowserLibrary.shared
        self.library = library

        let startURL = startsEmpty ? nil : (initialURL ?? library.lastVisitedURL ?? library.searchEngine.homepageURL)
        isEmpty = startsEmpty
        addressText = startURL?.absoluteString ?? ""
        requestedURL = startURL
        let title = restoredTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        pageTitle = startsEmpty ? "New Tab" : (title.flatMap { $0.isEmpty ? nil : $0 } ?? startURL?.host ?? "Ready when you are")
    }

    @discardableResult
    func ensureWebView(configuration suppliedConfiguration: WKWebViewConfiguration? = nil) -> WKWebView {
        if let webView { return webView }
        let configuration = suppliedConfiguration ?? WKWebViewConfiguration()
        if suppliedConfiguration == nil { configuration.websiteDataStore = websiteDataStore }
        BrowserAgentDOM.install(in: configuration)
        let webView = BrowserAssetWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 720), configuration: configuration)
        BrowserAgentFrames.shared.attach(agentFrames, to: webView)
        pageInteraction.webView = webView
        webView.customUserAgent = Self.desktopSafariUserAgent
        let delegate = BrowserNavigationDelegate(browser: self)
        navigationDelegate = delegate
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = .black
        webView.onPresentationChange = { [weak self] attached in
            if attached {
                self?.prepareForPresentation()
                self?.pageInteraction.presentPending()
            } else {
                self?.presentationID = UUID()
                self?.isPresentationReady = false
            }
        }
        self.webView = webView
        observeNavigation(in: webView)
        // WebKit starts popup navigation itself, using the supplied configuration.
        if suppliedConfiguration == nil { loadRequestedPage() }
        return webView
    }

    private func loadRequestedPage() {
        guard let webView, let requestedURL, submittedRequestID != navigationRequestID else { return }
        submittedRequestID = navigationRequestID
        let requestID = navigationRequestID
        pendingNavigation?.cancel()
        pendingNavigation = Task { @MainActor [weak self, weak webView] in
            guard let self else { return }
            await restoreSessionIfNeeded()
            guard !Task.isCancelled, self.navigationRequestID == requestID, let webView else { return }
            self.pendingNavigation = nil
            self.didStartLoading()
            if requestedURL.isFileURL {
                webView.loadFileURL(requestedURL, allowingReadAccessTo: requestedURL.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: requestedURL))
            }
        }
    }

    func close() {
        agentFrames.reset()
        pageInteraction.cancelAll()
        findTask?.cancel()
        findRequestID = UUID()
        stopLoading()
        discardPageSnapshot()
        (webView as? BrowserAssetWebView)?.onPresentationChange = nil
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        navigationDelegate = nil
        navigationObservations.removeAll()
        webView = nil
        onSessionChange = nil
        onSnapshotChange = nil
    }

    func stopLoading() {
        pageInteraction.cancelUpload()
        pendingNavigation?.cancel()
        pendingNavigation = nil
        submittedRequestID = nil
        webView?.stopLoading()
        isLoading = false
    }

    func captureVisiblePage() {
        guard snapshotCaptureID == nil, !isLoading, let webView, webView.window != nil,
              webView.bounds.width > 0, webView.bounds.height > 0 else { return }
        let captureID = UUID()
        let epoch = documentEpoch
        snapshotCaptureID = captureID
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        let longestSide = max(webView.bounds.width, webView.bounds.height)
        configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width * min(1, 720 / longestSide)))
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            Task { @MainActor [weak self] in
                guard let self, self.snapshotCaptureID == captureID else { return }
                self.snapshotCaptureID = nil
                guard let image, self.documentEpoch == epoch else { return }
                self.snapshotMemoryCost = image.representations.reduce(0) {
                    $0 + max(1, $1.pixelsWide) * max(1, $1.pixelsHigh) * 4
                }
                self.snapshotCapturedAt = Date()
                self.lastPageSnapshot = image
                self.onSnapshotChange?()
            }
        }
    }

    func discardPageSnapshot() {
        snapshotCaptureID = nil
        snapshotMemoryCost = 0
        snapshotCapturedAt = nil
        lastPageSnapshot = nil
    }

    /// A tiny capture after screen updates confirms that the reattached view
    /// has rendered. The SwiftUI surface supplies a short fallback on failure.
    func prepareForPresentation() {
        presentationID = UUID()
        let presentation = presentationID
        let epoch = documentEpoch
        isPresentationReady = false
        guard let webView, webView.window != nil else { return }
        guard lastPageSnapshot != nil else {
            isPresentationReady = true
            return
        }
        DispatchQueue.main.async { [weak self, weak webView] in
            guard let self, let webView, self.presentationID == presentation,
                  webView.window != nil, webView.bounds.width > 0, webView.bounds.height > 0 else { return }
            webView.layoutSubtreeIfNeeded()
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = true
            configuration.snapshotWidth = 16
            webView.takeSnapshot(with: configuration) { [weak self, weak webView] image, _ in
                guard image != nil else { return }
                Task { @MainActor [weak self, weak webView] in
                    guard let self, webView?.window != nil,
                          self.presentationID == presentation, self.documentEpoch == epoch else { return }
                    self.isPresentationReady = true
                }
            }
        }
    }

    func restoreSessionIfNeeded() async {
        await library.restoreSessionIfNeeded()
    }

    func scheduleSessionSave() {
        library.scheduleSessionSave()
    }

    func saveSessionAndWait() async {
        await library.saveSessionAndWait(updateStatus: false)
    }

    func submitAddress() {
        let input = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isEditingAddress = false

        if let url = BrowserAddressInput.webURL(from: input) {
            navigate(to: url)
            return
        }

        if let searchURL = library.searchEngine.searchURL(for: input) {
            navigate(to: searchURL)
        }
    }

    func navigate(to url: URL) {
        discardPageSnapshot()
        requestedURL = url
        if !isEditingAddress { addressText = url.absoluteString }
        errorMessage = nil
        navigationRequestID = UUID()
        isEmpty = false
        isLoading = true
        ensureWebView()
        loadRequestedPage()
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        guard !isEmpty else { return }
        if isLoading {
            stopLoading()
        } else if let webView, webView.url != nil, webView.url == requestedURL {
            webView.reload()
        } else {
            // Retry the requested address even when an older page is still
            // displayed after a stopped or failed navigation.
            navigationRequestID = UUID()
            ensureWebView()
            loadRequestedPage()
        }
    }

    func didStartLoading() {
        agentFrames.reset()
        pageInteraction.cancelAll()
        findTask?.cancel()
        findRequestID = UUID()
        findMatchFound = nil
        discardPageSnapshot()
        presentationID = UUID()
        documentEpoch = UUID()
        isLoading = true
        errorMessage = nil
    }

    func didBeginDownload() {
        isLoading = false
        // A download leaves the currently displayed page and its address intact.
        if let url = webView?.url {
            currentURL = url
            requestedURL = url
            if !isEditingAddress { addressText = url.absoluteString }
        }
    }

    func didCommitNavigation(url: URL?) {
        if let url {
            currentURL = url
            if !isEditingAddress { addressText = url.absoluteString }
            requestedURL = url
            isEmpty = false
            library.recordLastVisitedURL(url)
            onSessionChange?()
        }
    }

    func didFinishLoading(webView: WKWebView) {
        isLoading = false
        currentURL = webView.url

        if let url = webView.url {
            if !isEditingAddress { addressText = url.absoluteString }
            requestedURL = url
            library.recordLastVisitedURL(url)
        }

        if let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            pageTitle = title
        } else {
            pageTitle = webView.url?.host ?? "Ready when you are"
        }

        if let url = webView.url {
            library.recordVisit(url: url, title: pageTitle)
        }

        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        onSessionChange?()
        if isFindVisible && !findQuery.isEmpty { findNext() }
    }

    func didFailLoading(_ error: Error) {
        isLoading = false
        if (error as NSError).code != NSURLErrorCancelled {
            errorMessage = error.localizedDescription
        }
    }

    func updateNavigationState(from webView: WKWebView) {
        let nextCanGoBack = webView.canGoBack
        let nextCanGoForward = webView.canGoForward

        if canGoBack != nextCanGoBack {
            canGoBack = nextCanGoBack
        }

        if canGoForward != nextCanGoForward {
            canGoForward = nextCanGoForward
        }
    }

    private func observeNavigation(in webView: WKWebView) {
        let changed: (WKWebView) -> Void = { [weak self] webView in
            // KVO can run inside WebKit/SwiftUI layout. Publish on the next
            // actor turn instead of changing observable state during layout.
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView, self.webView === webView else { return }
                self.refreshMetadata(from: webView)
            }
        }
        navigationObservations = [
            webView.observe(\.title, options: [.new]) { view, _ in changed(view) },
            webView.observe(\.url, options: [.new]) { view, _ in changed(view) },
            webView.observe(\.canGoBack, options: [.new]) { view, _ in changed(view) },
            webView.observe(\.canGoForward, options: [.new]) { view, _ in changed(view) }
        ]
    }

    private func refreshMetadata(from webView: WKWebView) {
        updateNavigationState(from: webView)
        var changed = false
        if let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty, pageTitle != title {
            pageTitle = title
            changed = true
        }
        // Full navigations use the commit/finish callbacks. This path handles
        // history.pushState/replaceState and avoids overwriting a queued URL.
        if !isLoading, !webView.isLoading, let url = webView.url, currentURL != url {
            discardPageSnapshot()
            presentationID = UUID()
            currentURL = url
            requestedURL = url
            if !isEditingAddress { addressText = url.absoluteString }
            library.recordLastVisitedURL(url)
            changed = true
        }
        if changed {
            if !isLoading, currentURL == webView.url, let url = currentURL {
                library.recordVisit(url: url, title: pageTitle)
            }
            onSessionChange?()
        }
    }

    func focusAddress() { addressFocusRequest = UUID() }
    func consumeAddressFocus() { addressFocusRequest = nil }
    func consumeFindFocus() { findFocusRequest = nil }
    func beginAddressEditing() { isEditingAddress = true }
    func endAddressEditing() {
        isEditingAddress = false
        if let url = requestedURL { addressText = url.absoluteString }
    }
    func cancelAddressEditing() {
        endAddressEditing()
        addressText = requestedURL?.absoluteString ?? ""
        webView?.window?.makeFirstResponder(webView)
    }

    func showFind() {
        guard !isEmpty else { focusAddress(); return }
        isFindVisible = true
        findFocusRequest = UUID()
        if !findQuery.isEmpty { findNext() }
    }

    func hideFind() {
        findTask?.cancel()
        findRequestID = UUID()
        isFindVisible = false
        findMatchFound = nil
        webView?.find("", configuration: WKFindConfiguration()) { _ in }
        webView?.window?.makeFirstResponder(webView)
    }

    private func scheduleFind() {
        findTask?.cancel()
        findRequestID = UUID()
        findMatchFound = nil
        guard isFindVisible else { return }
        if findQuery.isEmpty {
            webView?.find("", configuration: WKFindConfiguration()) { _ in }
            return
        }
        findTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.findNext()
        }
    }

    func findNext(backwards: Bool = false) {
        findTask?.cancel()
        guard !findQuery.isEmpty, let webView else { return }
        findRequestID = UUID()
        let requestID = findRequestID
        let epoch = documentEpoch
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        webView.find(findQuery, configuration: configuration) { [weak self, weak webView] result in
            guard let self, let webView, self.webView === webView,
                  self.findRequestID == requestID, self.documentEpoch == epoch else { return }
            self.findMatchFound = result.matchFound
        }
    }

}
