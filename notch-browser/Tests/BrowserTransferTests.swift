import AppKit
import WebKit

/// Run with TransferServer.py. These exercise real WKDownload instances against
/// a local server; they do not read the user's browser data or license.
@main
struct BrowserTransferTests {
    @MainActor private static var checks = 0

    @MainActor static func main() {
        _ = NSApplication.shared
        Task { @MainActor in
            do {
                try await run()
                print("\(checks) browser transfer checks passed")
                exit(0)
            } catch {
                print("FAIL: \(error.localizedDescription)")
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    @MainActor private static func run() async throws {
        let base = URL(string: ProcessInfo.processInfo.environment["NOTCH_TRANSFER_TEST_URL"] ?? "http://127.0.0.1:8769")!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notch-transfer-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try expect(BrowserDownloadFiles.filename("../../.hidden.png") == "hidden.png", "Filenames cannot escape the destination")
        try expect(BrowserDownloadFiles.filename("C:\\unsafe\\asset:one.png") == "asset-one.png", "Windows separators and colons are sanitized")
        try expect(BrowserDownloadFiles.filename("..", mimeType: "image/png") == "download.png", "Empty filenames receive a useful extension")
        let longName = BrowserDownloadFiles.filename(String(repeating: "🙂", count: 100) + ".png")
        try expect(longName.utf8.count <= 240 && longName.hasSuffix(".png"), "Long Unicode filenames keep their extension within filesystem limits")
        try expect(BrowserDragAsset(["url": "javascript:alert(1)"]) == nil, "Asset exports reject executable URLs")
        let movie = BrowserDragAsset(["url": "https://example.com/movie.mp4", "kind": "video"])
        try expect(movie?.filename == "movie.mp4" && movie?.fileType.conforms(to: .movie) == true, "Video promises advertise a movie file")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        var webView: WKWebView? = BrowserAssetWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 600), configuration: configuration)
        let downloads = BrowserDownloads(directory: folder)
        (webView as! BrowserAssetWebView).downloads = downloads
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = webView
        let delegate = TransferNavigationDelegate(downloads: downloads)
        webView!.navigationDelegate = delegate
        webView!.load(URLRequest(url: base))
        try await wait { delegate.loaded }
        let (image, _) = try await URLSession.shared.data(from: base.appendingPathComponent("transfer.png"))
        let sentinel = Data("existing file".utf8)
        let existing = folder.appendingPathComponent("notch-check.png")
        try sentinel.write(to: existing)

        let first = try await click("download", webView: webView!, downloads: downloads)
        try expect(first.state == .finished && first.filename == "notch-check (1).png", "Download attributes save without overwriting an existing file")
        try expect(try Data(contentsOf: existing) == sentinel, "Existing download bytes remain unchanged")
        try expect(try contents(first) == image, "Downloaded image bytes match the original")
        try expect(webView!.url == base || webView!.url?.absoluteString == base.absoluteString + "/", "Downloading leaves the displayed page intact")

        let coordinates = try await webView!.evaluateJavaScript("""
            (() => { const r = document.getElementById('image').getBoundingClientRect();
            return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()
            """) as! [String: Double]
        let viewPoint = NSPoint(x: coordinates["x"]!, y: webView!.isFlipped ? coordinates["y"]! : webView!.bounds.height - coordinates["y"]!)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: webView!.convert(viewPoint, to: nil),
                                      modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                      context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
        let menu = NSMenu()
        let imageAction = NSMenuItem(title: "Download Image", action: nil, keyEquivalent: "")
        imageAction.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierDownloadImage")
        menu.addItem(imageAction)
        (webView as! BrowserAssetWebView).willOpenMenu(menu, with: event)
        try expect(imageAction.target === webView && imageAction.action != nil, "Native context download menu actions route to the browser")
        let contextCount = downloads.items.count
        menu.performActionForItem(at: 0)
        try await wait { downloads.items.count > contextCount && downloads.items[0].state != .downloading }
        try expect(try contents(downloads.items[0]) == image, "The native Download Image action writes the original image bytes")

        let attachment = try await click("attachment", webView: webView!, downloads: downloads)
        try expect(attachment.state == .finished && attachment.filename == "notch-attachment.png", "Displayable image attachments become downloads")
        let unsupported = try await click("unsupported", webView: webView!, downloads: downloads)
        try expect(unsupported.state == .finished && unsupported.filename == "notch-archive.bin", "Unsupported response types become downloads")
        let blob = try await click("blob", webView: webView!, downloads: downloads)
        try expect(try contents(blob) == Data("Notch Browser blob fixture\n".utf8), "Blob downloads keep their bytes and filename")
        let data = try await click("data", webView: webView!, downloads: downloads)
        try expect(try contents(data) == image, "Data URL image downloads keep their bytes")
        let protected = try await click("protected", webView: webView!, downloads: downloads)
        try expect(try contents(protected) == Data("Notch Browser transfer fixture\n".utf8), "Downloads retain the page's authentication cookie")

        let promised = folder.appendingPathComponent("promised.png")
        let exportError: Error? = await withCheckedContinuation { continuation in
            downloads.export(base.appendingPathComponent("transfer.png"), using: webView!, to: promised) {
                continuation.resume(returning: $0)
            }
        }
        try expect(exportError == nil && (try Data(contentsOf: promised)) == image, "File-promise exports deliver the original image to the requested destination")
        let protectedPromise = folder.appendingPathComponent("promised-protected.txt")
        let protectedError: Error? = await withCheckedContinuation { continuation in
            downloads.export(base.appendingPathComponent("redirect"), using: webView!, to: protectedPromise) {
                continuation.resume(returning: $0)
            }
        }
        try expect(protectedError == nil && (try Data(contentsOf: protectedPromise)) == Data("Notch Browser transfer fixture\n".utf8), "File promises retain cookies across redirects")

        let count = downloads.items.count
        try await javascript("document.getElementById('slow').click()", in: webView!)
        try await wait { downloads.items.count > count && downloads.items[0].receivedBytes > 0 }
        let cancelled = downloads.items[0]
        downloads.cancel(cancelled.id)
        try await wait { !FileManager.default.fileExists(atPath: FileManager.default.temporaryDirectory.appendingPathComponent("notch-transfer-" + cancelled.id.uuidString).path) }
        try expect(downloads.items.first(where: { $0.id == cancelled.id })?.state == .cancelled, "Cancellation records a terminal state")
        try expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("notch-slow.bin").path), "Cancelled transfers never appear as completed files")

        let failure = try await click("failure", webView: webView!, downloads: downloads)
        try expect(failure.state == .failed && failure.error?.isEmpty == false && failure.destination == nil, "Interrupted responses produce a visible failure and no completed file")

        let incoming = folder.appendingPathComponent("incoming.png")
        try image.write(to: incoming)
        let providers = [NSItemProvider(contentsOf: incoming)!]
        var dropped: [URL]?
        let accepted = BrowserAssetDrop.receive(providers) { dropped = $0 }
        try await wait { dropped != nil }
        try expect(accepted && dropped == [incoming], "New-tab drops read real file URLs")

        let beforeClosing = downloads.items.count
        try await javascript("document.getElementById('slow').click()", in: webView!)
        try await wait { downloads.items.count > beforeClosing && downloads.items[0].receivedBytes > 0 }
        let detachedID = downloads.items[0].id
        webView!.stopLoading()
        webView!.navigationDelegate = nil
        window.contentView = nil
        webView = nil
        try await wait { downloads.items.first(where: { $0.id == detachedID })?.state != .downloading }
        let detached = downloads.items.first { $0.id == detachedID }!
        try expect(detached.state == .finished && (try contents(detached)).count == 2 * 1024 * 1024, "Downloads finish after the originating view is detached and closed")
        try expect(downloads.activeCount == 0, "All transfers release their active state")
        downloads.clearFinished()
        try expect(downloads.items.isEmpty, "Clearing history leaves no stale transfers")
        try expect(try Data(contentsOf: existing) == sentinel, "Clearing history never deletes saved files")
    }

    @MainActor private static func click(_ id: String, webView: WKWebView, downloads: BrowserDownloads) async throws -> BrowserDownload {
        let count = downloads.items.count
        try await javascript("document.getElementById('\(id)').click()", in: webView)
        try await wait { downloads.items.count > count && downloads.items[0].state != .downloading }
        return downloads.items[0]
    }

    @MainActor private static func javascript(_ script: String, in webView: WKWebView) async throws {
        _ = try await webView.evaluateJavaScript(script)
    }

    @MainActor private static func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition() {
            guard Date() < deadline else { throw NSError(domain: "BrowserTransferTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for a real WebKit transfer"] ) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private static func contents(_ item: BrowserDownload) throws -> Data {
        guard let destination = item.destination else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: destination)
    }

    @MainActor private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NSError(domain: "BrowserTransferTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        checks += 1
    }
}

@MainActor
private final class TransferNavigationDelegate: NSObject, WKNavigationDelegate {
    let downloads: BrowserDownloads
    var loaded = false
    init(downloads: BrowserDownloads) { self.downloads = downloads }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(BrowserDownloads.policy(for: navigationAction))
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(BrowserDownloads.policy(for: navigationResponse))
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        downloads.receive(download, from: webView)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        downloads.receive(download, from: webView)
    }
}
