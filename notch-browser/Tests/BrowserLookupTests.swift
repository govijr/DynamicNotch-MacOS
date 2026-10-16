import AppKit
import Carbon
import WebKit

@main
struct BrowserLookupTests {
    @MainActor private static var checks = 0
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            if let path = ProcessInfo.processInfo.environment["NOTCH_LOOKUP_HOTKEY_FIXTURE"] {
                do { try await hotkeyFixture(at: URL(fileURLWithPath: path)); exit(0) }
                catch { print("Hotkey fixture failed: \(error)"); exit(1) }
            }
            do { try await run(); print("\(checks) lookup checks passed"); exit(0) }
            catch { print("FAIL after \(checks) checks: \(error.localizedDescription)"); exit(1) }
        }
        app.run()
    }

    @MainActor private static func run() async throws {
        let infoURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NotchBrowser-Info.plist")
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as! [String: Any]
        let services = info["NSServices"] as! [[String: Any]]
        try expect(services.count == 3 && services.allSatisfy { $0["NSRequiredContext"] is [String: Any] },
                   "Services declare their context so macOS presents them by default")
        try expect(services.first(where: { $0["NSMessage"] as? String == "searchImageInNotch" })?["NSSendFileTypes"] as? [String] == ["public.image"],
                   "Finder offers image lookup only for image files")
        let suite = "NotchBrowser.LookupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONSerialization.data(withJSONObject: ["urls": [NSNull()], "activeIndex": 0]), forKey: "notchBrowser.openTabs.v1")
        let library = BrowserLibrary()
        let tabs = BrowserTabsModel(library: library, defaults: defaults)
        let original = tabs.activeBrowser
        original.addressText = "Retained work"
        tabs.isChromeVisible = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory); tabs.tabs.forEach { $0.close() } }
        let page = directory.appendingPathComponent("lookup.html")
        try "<html><head><title>Lookup fixture</title></head><body><p>Lookup result</p></body></html>".write(to: page, atomically: true, encoding: .utf8)
        var searched = [String]()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let lookup = BrowserLookupCoordinator(tabs: tabs, library: library, defaults: defaults, clipboard: pasteboard, search: { text in
            searched.append(text); return page
        })
        defer { lookup.stop() }
        var requests = 0
        lookup.onRequest = { requests += 1 }
        pasteboard.setString("  macOS & Swift + ✓  ", forType: .string)
        let clipboardRevision = pasteboard.changeCount
        var serviceError: NSString?
        lookup.searchInNotch(pasteboard, userData: nil, error: &serviceError)
        try expect(serviceError == nil && requests == 1 && lookup.hasPendingRequest, "Services enqueue the supplied selection")
        try expect(!lookup.isPresented && tabs.tabs.count == 1, "Queued requests wait for the app's access gate")
        lookup.presentPending()
        try expect(lookup.isPresented && tabs.isShowingLookup && tabs.tabs.count == 2, "A request opens one temporary tab")
        try expect(searched == ["macOS & Swift + ✓"], "Search receives literal text without URL guessing")
        try expect(pasteboard.changeCount == clipboardRevision, "Selection lookup leaves its pasteboard unchanged")
        let temporary = tabs.activeBrowser
        lookup.selectDestination(.define)
        try expect(searched.last == "define macOS & Swift + ✓", "Definition uses the selected search engine")
        lookup.selectDestination(.documentation)
        try expect(searched.last == "macOS & Swift + ✓ site:developer.mozilla.org", "Documentation scopes the query")
        lookup.searchInNotch(pasteboard, userData: nil, error: &serviceError)
        lookup.presentPending()
        try expect(tabs.tabs.count == 2 && tabs.activeBrowser === temporary, "Repeated lookups reuse their temporary tab")
        tabs.persistSession()
        let saved = try JSONSerialization.jsonObject(with: defaults.data(forKey: "notchBrowser.openTabs.v1")!) as! [String: Any]
        try expect((saved["tabs"] as? [[String: Any]])?.count == 1 && saved["activeIndex"] as? Int == 0, "Temporary lookup tabs are excluded from restoration")
        lookup.end(restoreFocus: false)
        try expect(tabs.tabs.count == 1 && tabs.activeBrowser === original && original.addressText == "Retained work", "Dismissal restores the original tab without replacing its model")
        try expect(!tabs.isChromeVisible && !tabs.reopenClosedTab(), "Dismissal restores chrome and does not add a closed tab")

        lookup.searchInNotch(pasteboard, userData: nil, error: &serviceError)
        lookup.presentPending()
        lookup.keepAsTab()
        try expect(!lookup.isPresented && tabs.lookupTabID == nil && tabs.tabs.count == 2, "Keep promotes the result to a regular tab")
        tabs.persistSession()
        let kept = try JSONSerialization.jsonObject(with: defaults.data(forKey: "notchBrowser.openTabs.v1")!) as! [String: Any]
        try expect((kept["tabs"] as? [[String: Any]])?.count == 2, "Kept lookup participates in session restoration")

        lookup.searchInNotch(pasteboard, userData: nil, error: &serviceError)
        lookup.presentPending()
        tabs.selectTab(original.id)
        try await Task.sleep(nanoseconds: 50_000_000)
        try expect(!lookup.isPresented && tabs.tabs.count == 2 && tabs.activeBrowser === original, "Switching to another tab cleans up without changing that selection")

        let text = "a & b + c / 日本語? #fragment"
        let translated = BrowserLookupDestination.translate.url(for: text, language: "fr", search: { _ in nil })!
        let values = URLComponents(url: translated, resolvingAgainstBaseURL: false)!.queryItems!
        try expect(translated.host == "translate.google.com" && values.first(where: { $0.name == "text" })?.value == text, "Translation encodes literal punctuation and Unicode")
        try expect(values.first(where: { $0.name == "tl" })?.value == "fr", "Translation uses the destination language")
        do { _ = try BrowserLookupDestination.validatedText(" \n "); throw failure("Empty text was accepted") }
        catch BrowserLookupError.emptyClipboard { checks += 1 }
        do { _ = try BrowserLookupDestination.validatedText(String(repeating: "x", count: 4001)); throw failure("Oversized selection was accepted") }
        catch BrowserLookupError.tooMuchText { checks += 1 }
        pasteboard.clearContents()
        lookup.searchInNotch(pasteboard, userData: nil, error: &serviceError)
        try expect(serviceError != nil && !lookup.hasPendingRequest, "Invalid Services data returns an error without a navigation")

        lookup.translateInNotch({ pasteboard.setString("hello", forType: .string); return pasteboard }(), userData: nil, error: &serviceError)
        try expect(lookup.hasPendingRequest, "Translate has an explicit Services entry point")
        // No external translation request is sent by this test.

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 1000,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = bitmap.representation(using: .png, properties: [:])!
        var prepared: BrowserLookupImage? = try BrowserLookupImage(data: png)
        let preparedURL = prepared!.fileURL
        try expect(prepared!.width == 1600 && prepared!.height == 800, "Image handoff bounds decoded dimensions")
        try expect(FileManager.default.fileExists(atPath: preparedURL.path), "Prepared image has a local drag/upload file")
        let permissions = try FileManager.default.attributesOfItem(atPath: preparedURL.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        try expect(permissions?.intValue == 0o700, "Prepared images live in a private directory")
        prepared = nil
        try expect(!FileManager.default.fileExists(atPath: preparedURL.path), "Releasing an image removes its temporary storage")
        do { _ = try BrowserLookupImage(data: Data("not an image".utf8)); throw failure("Invalid image accepted") }
        catch BrowserLookupError.invalidImage { checks += 1 }
        pasteboard.clearContents(); pasteboard.setData(png, forType: .png)
        let imageRevision = pasteboard.changeCount
        lookup.searchImageInNotch(pasteboard, userData: nil, error: &serviceError)
        lookup.presentPending()
        let imageFile = lookup.image!.fileURL
        try expect(lookup.image != nil && !lookup.hasStartedImageSearch && !lookup.isSearchingImage, "Image requests stop at preview until the user chooses Lens")
        try expect(pasteboard.changeCount == imageRevision, "Image lookup preserves the original pasteboard")
        lookup.end(restoreFocus: false)
        try expect(!FileManager.default.fileExists(atPath: imageFile.path), "Dismissing image preview cleans up prepared files")
        lookup.lookUpClipboard(); lookup.presentPending()
        try expect(lookup.image != nil && !lookup.hasStartedImageSearch, "Clipboard images also stop at the local preview")
        lookup.end(restoreFocus: false)

        try expect(BrowserLensHandoff.isUploadPage(URL(string: "https://www.google.com/imghp?hl=en")), "Lens allows the actual Google image-search page")
        for value in ["http://www.google.com/imghp", "https://www.google.com.evil.test/imghp", "https://example.com/imghp", "https://www.google.com/search"] {
            try expect(!BrowserLensHandoff.isUploadPage(URL(string: value)), "Lens refuses unapproved upload origins and pages")
        }
        let uploadPage = directory.appendingPathComponent("upload.html")
        try #"""
        <html><body><button aria-label="Search by image" onclick="openUpload()">Lens</button>
        <script>function openUpload(){const input=document.createElement('input');input.type='file';input.name='encoded_image';
        input.onchange=()=>{document.body.dataset.uploadName=input.files[0].name;document.body.dataset.uploadSize=input.files[0].size};document.body.append(input)}</script>
        </body></html>
        """#.write(to: uploadPage, atomically: true, encoding: .utf8)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 400), configuration: WKWebViewConfiguration())
        view.loadFileURL(uploadPage, allowingReadAccessTo: directory)
        let deadline = Date().addingTimeInterval(5)
        while view.isLoading || view.url != uploadPage {
            guard Date() < deadline else { throw failure("Upload fixture did not load") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let wrongOrigin = try await BrowserAgentDOM.evaluate(BrowserLensHandoff.uploadScript,
            arguments: ["encoded": png.base64EncodedString(), "filename": "Synthetic.png", "expectedOrigin": "https://www.google.com", "expectedPath": "/imghp", "requestID": "wrong-origin"], in: view, world: BrowserLensHandoff.world) as! [String: Any]
        try expect(wrongOrigin["status"] as? String == "wrong_page", "Origin is checked again inside the upload script")
        let correctOrigin = URLComponents(url: uploadPage, resolvingAgainstBaseURL: false)!
        let pageOrigin = try await BrowserAgentDOM.evaluate("return location.origin;", arguments: [:], in: view, world: .page) as! String
        let result = try await BrowserAgentDOM.evaluate(BrowserLensHandoff.uploadScript,
            arguments: ["encoded": png.base64EncodedString(), "filename": "Synthetic.png", "expectedOrigin": pageOrigin, "expectedPath": correctOrigin.percentEncodedPath.removingPercentEncoding!, "requestID": "fixture"], in: view, world: BrowserLensHandoff.world) as! [String: Any]
        try expect(result["status"] as? String == "submitted", "Lens handoff opens the public upload control and dispatches a file: \(result)")
        let uploaded = try await BrowserAgentDOM.evaluate("return {...document.body.dataset};", arguments: [:], in: view, world: .page) as! [String: String]
        try expect(uploaded["uploadName"] == "Synthetic.png" && Int(uploaded["uploadSize"] ?? "") == png.count, "The page receives the intended file across content worlds")

        // Dismissing while Google is creating its input must prevent a late upload.
        _ = try await BrowserAgentDOM.evaluate("document.querySelector('input').remove(); document.body.removeAttribute('data-upload-name'); document.body.removeAttribute('data-upload-size'); document.querySelector('button').onclick = () => setTimeout(openUpload, 300); return true;", arguments: [:], in: view, world: .page)
        let delayedUpload = Task { @MainActor in
            try await BrowserAgentDOM.evaluate(BrowserLensHandoff.uploadScript,
                arguments: ["encoded": png.base64EncodedString(), "filename": "Cancelled.png", "expectedOrigin": pageOrigin, "expectedPath": correctOrigin.percentEncodedPath.removingPercentEncoding!, "requestID": "cancelled"], in: view, world: BrowserLensHandoff.world)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        BrowserLensHandoff.cancel(in: view)
        let cancelled = try await delayedUpload.value as! [String: Any]
        try await Task.sleep(nanoseconds: 350_000_000)
        let lateFile = try await BrowserAgentDOM.evaluate("return document.body.dataset.uploadName || '';", arguments: [:], in: view, world: .page) as! String
        try expect(cancelled["status"] as? String != "submitted" && lateFile.isEmpty, "Cancelling the handoff prevents a delayed file upload")

        pasteboard.clearContents(); pasteboard.setString("clipboard query", forType: .string)
        lookup.lookUpClipboard(); lookup.presentPending()
        try expect(lookup.query == "clipboard query" && searched.last == "clipboard query", "Clipboard action uses supplied text without changing the clipboard")
        lookup.end(restoreFocus: false)
        pasteboard.clearContents()
        lookup.lookUpClipboard(); lookup.presentPending()
        try expect(lookup.message != nil && tabs.activeBrowser.isEmpty, "An empty clipboard gives a local explanation without searching")
        lookup.end(restoreFocus: false)

        // Exercise the installed Carbon event handler with the same event that
        // WindowServer sends, using the private pasteboard and a local page.
        pasteboard.setString("keyboard callback", forType: .string)
        lookup.start()
        try expect(lookup.shortcutError == nil, "The global shortcut registers without Accessibility permission")
        var event: EventRef?
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(),
                          EventAttributes(kEventAttributeUserEvent), &event) == noErr, let event else { throw failure("Could not create hotkey fixture event") }
        defer { ReleaseEvent(event) }
        var hotKeyID = EventHotKeyID(signature: 0x4E4F5443, id: 1)
        let requestsBeforeKey = requests
        let parameterStatus = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &hotKeyID)
        try expect(parameterStatus == noErr && SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr, "The installed hotkey handler accepts its Carbon event")
        try await Task.sleep(nanoseconds: 50_000_000)
        lookup.presentPending()
        try expect(requests == requestsBeforeKey + 1 && lookup.query == "keyboard callback", "The hotkey callback opens the supplied clipboard request")
        lookup.end(restoreFocus: false)

        lookup.searchInNotch(pasteboard, userData: nil, error: &serviceError)
        lookup.presentPending()
        let returnTabs = tabs.tabs.filter { $0.id != tabs.lookupTabID }
        returnTabs.forEach { tabs.closeTab($0.id) }
        lookup.end(restoreFocus: false)
        try expect(tabs.tabs.count == 1 && tabs.activeBrowser.isEmpty && tabs.lookupTabID == nil,
                   "Closing all original tabs during lookup still leaves a valid blank tab on dismissal")
    }

    /// A separate, disposable process lets native QA press the real global
    /// shortcut while using a private fixture clipboard, never the user's.
    @MainActor private static func hotkeyFixture(at root: URL) async throws {
        let suite = "NotchLookup.Hotkey.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = BrowserLibrary()
        let tabs = BrowserTabsModel(library: library, defaults: defaults)
        let clipboard = NSPasteboard.withUniqueName()
        clipboard.setString("Synthetic keyboard lookup", forType: .string)
        let page = root.appendingPathComponent("page.html")
        try "<html><body>Keyboard lookup fixture</body></html>".write(to: page, atomically: true, encoding: .utf8)
        let coordinator = BrowserLookupCoordinator(tabs: tabs, library: library, defaults: defaults, clipboard: clipboard, search: { _ in page })
        coordinator.onRequest = {
            coordinator.presentPending()
            try! coordinator.query.write(to: root.appendingPathComponent("received.txt"), atomically: true, encoding: .utf8)
        }
        coordinator.start()
        defer { coordinator.stop(); clipboard.releaseGlobally(); tabs.tabs.forEach { $0.close() } }
        try JSONSerialization.data(withJSONObject: ["registered": coordinator.shortcutError == nil]).write(to: root.appendingPathComponent("ready.json"))
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("stop").path) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        coordinator.onRequest = nil
    }

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw failure(message) }; checks += 1
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "BrowserLookupTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
