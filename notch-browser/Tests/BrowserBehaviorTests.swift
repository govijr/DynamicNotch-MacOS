import AppKit
import WebKit

@main
struct BrowserBehaviorTests {
    @MainActor private static var checks = 0

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await run()
                print("\(checks) browser behavior checks passed")
                exit(0)
            } catch {
                print("FAIL after \(checks) checks: \(error.localizedDescription)")
                exit(1)
            }
        }
        app.run()
    }

    @MainActor private static func run() async throws {
        for query in ["weather", "swift", "hello world", "hello\tworld", "person@example.com", "javascript:alert(1)", "1.2.3.999"] {
            try expect(BrowserAddressInput.webURL(from: query) == nil, "\(query) is a search")
        }
        for (input, expected) in [
            ("example.com/path?q=a#section", "https://example.com/path?q=a#section"),
            ("http://intranet/path", "http://intranet/path"),
            ("localhost:3000/path", "http://localhost:3000/path"),
            ("demo.localhost:8080", "http://demo.localhost:8080"),
            ("127.0.0.1:8769", "http://127.0.0.1:8769"),
            ("[::1]:8080/path", "http://[::1]:8080/path"),
            ("https://localhost:8443", "https://localhost:8443"),
            ("  www.example.com  ", "https://www.example.com")
        ] {
            try expect(BrowserAddressInput.webURL(from: input)?.absoluteString == expected, "Address: \(input)")
        }

        let library = BrowserLibrary()
        let browser = BrowserModel(library: library, startsEmpty: true)
        defer { browser.close() }
        browser.addressText = "weather"
        browser.submitAddress()
        browser.stopLoading()
        try expect(browser.requestedURL?.host == "duckduckgo.com"
                   && URLComponents(url: browser.requestedURL!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "weather",
                   "Submitting a single word uses the selected search engine")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notch-behavior-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("first.html")
        let second = folder.appendingPathComponent("second.html")
        try "<title>First fixture</title><input id='field'>".write(to: first, atomically: true, encoding: .utf8)
        try "<title>Second fixture</title>".write(to: second, atomically: true, encoding: .utf8)

        let gate = RestoreGate()
        let waitingLibrary = BrowserLibrary()
        waitingLibrary.restoreHandler = { await gate.wait() }
        let waiting = BrowserModel(library: waitingLibrary, startsEmpty: true)
        defer { waiting.close() }
        waiting.navigate(to: first)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = waiting.webView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await wait("entering session restoration") { gate.isWaiting }
        waiting.reload() // The toolbar uses this same action for Stop.
        try expect(!waiting.isLoading, "Stop clears loading while session restoration is pending")
        gate.release()
        try await Task.sleep(nanoseconds: 80_000_000)
        try expect(waiting.webView?.url == nil, "A cancelled queued load never starts after restoration")
        waiting.reload()
        do {
            try await wait("retrying a stopped first load") { waiting.currentURL == first && waiting.webView?.title == "First fixture" && !waiting.isLoading }
        } catch {
            print("Retry state: \(waiting.pageTitle), \(String(describing: waiting.webView?.url)), WebKit title=\(String(describing: waiting.webView?.title)), loading=\(waiting.isLoading)/\(String(describing: waiting.webView?.isLoading)), error=\(String(describing: waiting.errorMessage))")
            throw error
        }
        try expect(waiting.currentURL == first, "Reload retries a first navigation stopped before submission")

        let redirectGate = RestoreGate()
        let redirectLibrary = BrowserLibrary()
        redirectLibrary.restoreHandler = { await redirectGate.wait() }
        let redirect = BrowserModel(library: redirectLibrary, startsEmpty: true)
        defer { redirect.close() }
        redirect.navigate(to: first)
        try await wait("entering replaced session restoration") { redirectGate.isWaiting }
        redirect.navigate(to: second)
        redirectGate.release()
        try await wait("loading the replacement address") { redirect.currentURL == second && redirect.webView?.title == "Second fixture" && !redirect.isLoading }
        try expect(redirect.currentURL == second && redirect.webView?.canGoBack == false,
                   "A newer address replaces a pending first navigation")

        let suite = "NotchBrowser.SnapshotTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONSerialization.data(withJSONObject: ["urls": [NSNull()], "activeIndex": 0]), forKey: "notchBrowser.openTabs.v1")
        let tabs = BrowserTabsModel(library: BrowserLibrary(), defaults: defaults)
        defer { tabs.tabs.forEach { $0.close() } }
        var captured: [BrowserModel] = []
        for _ in 0..<4 {
            let tab = tabs.newTab(select: false)
            captured.append(tab)
            tab.navigate(to: first)
            window.contentView = tab.webView
            window.setContentSize(NSSize(width: 1600, height: 900))
            try await wait("loading a screenshot fixture") { tab.webView?.title == "First fixture" && !tab.isLoading }
            tab.captureVisiblePage()
            try await wait("capturing a bounded screenshot") { tab.lastPageSnapshot != nil }
            try expect(max(tab.lastPageSnapshot!.size.width, tab.lastPageSnapshot!.size.height) <= 721,
                       "Cached screenshots cap their longest side")
        }
        try expect(tabs.tabs.filter { $0.lastPageSnapshot != nil }.count <= BrowserTabsModel.snapshotCountLimit,
                   "Screenshot cache has a count budget")
        try expect(tabs.tabs.reduce(0) { $0 + $1.snapshotMemoryCost } <= BrowserTabsModel.snapshotByteLimit,
                   "Screenshot cache has a byte budget")
        try expect(captured[0].lastPageSnapshot == nil, "Older inactive screenshots are released first")
        let presented = captured.last!
        if #available(macOS 14, *) {
            print("Measured WebKit inactive policy: \(presented.webView!.configuration.preferences.inactiveSchedulingPolicy.rawValue) (0=suspend)")
        }
        _ = try await presented.webView!.evaluateJavaScript("document.getElementById('field').value='Preserved form'")
        window.contentView = NSView()
        let revealStart = Date()
        window.contentView = presented.webView
        try await wait("rendering the reattached page") { presented.isPresentationReady }
        print("Local page presentation readiness: \(Int(Date().timeIntervalSince(revealStart) * 1000)) ms")
        let value = try await presented.webView!.evaluateJavaScript("document.getElementById('field').value") as? String
        try expect(value == "Preserved form", "Reattaching the live tab preserves form state")
        presented.captureVisiblePage()
        presented.navigate(to: second)
        try expect(presented.lastPageSnapshot == nil, "Navigation immediately removes the previous document's screenshot")
        try await wait("loading after snapshot invalidation") { presented.webView?.title == "Second fixture" && !presented.isLoading }
        try expect(presented.lastPageSnapshot == nil, "An old in-flight capture cannot restore a stale screenshot")

        _ = try await presented.webView!.evaluateJavaScript("document.title='Updated live title'; history.pushState({}, '', '#updated')")
        try await wait("observing a title and same-document URL change") {
            presented.pageTitle == "Updated live title" && presented.currentURL?.fragment == "updated"
        }
        try expect(presented.addressText.hasSuffix("#updated") && presented.canGoBack,
                   "Same-document navigation updates the address and navigation controls")
        tabs.persistSession()
        let saved = try JSONSerialization.jsonObject(with: defaults.data(forKey: "notchBrowser.openTabs.v1")!) as! [String: Any]
        let savedTabs = saved["tabs"] as! [[String: Any]]
        try expect(savedTabs.last?["title"] as? String == "Updated live title", "Sessions persist live titles alongside URLs")

        defaults.set(try JSONSerialization.data(withJSONObject: ["tabs": [
            ["url": "https://example.com/one", "title": "Saved first title"],
            ["url": "https://example.com/two", "title": "Saved second title"]
        ], "activeIndex": 1]), forKey: "notchBrowser.openTabs.v1")
        let restored = BrowserTabsModel(library: BrowserLibrary(), defaults: defaults)
        try expect(restored.tabs.map(\.pageTitle) == ["Saved first title", "Saved second title"]
                   && restored.activeBrowser.requestedURL?.path == "/two", "Restored tabs immediately show saved titles and selection")
        try expect(restored.tabs.allSatisfy { $0.webView == nil }, "Title restoration does not eagerly load web views")
        defaults.set(try JSONSerialization.data(withJSONObject: ["urls": ["https://example.com/legacy", NSNull()], "activeIndex": 0]),
                     forKey: "notchBrowser.openTabs.v1")
        let legacy = BrowserTabsModel(library: BrowserLibrary(), defaults: defaults)
        try expect(legacy.tabs.count == 2 && legacy.activeBrowser.requestedURL?.path == "/legacy"
                   && legacy.activeBrowser.pageTitle == "example.com" && legacy.tabs[1].isEmpty,
                   "Legacy URL-only sessions migrate without losing tabs")
    }

    @MainActor private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw NSError(domain: "BrowserBehaviorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        checks += 1
    }

    @MainActor private static func wait(_ description: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition() {
            guard Date() < deadline else { throw NSError(domain: "BrowserBehaviorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out: " + description] ) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

@MainActor
private final class RestoreGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    var isWaiting: Bool { continuation != nil }
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
