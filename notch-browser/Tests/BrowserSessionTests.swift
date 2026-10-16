import AppKit
import WebKit

@main
struct BrowserSessionTests {
    @MainActor private static var checks = 0
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await run()
                print("\(checks) browser session checks passed")
                exit(0)
            } catch {
                print("FAIL: \(error.localizedDescription)")
                exit(1)
            }
        }
        app.run()
    }

    @MainActor private static func run() async throws {
        let searchDestinations: [(BrowserSearchEngine, String)] = [
            (.duckDuckGo, "https://duckduckgo.com?q=hello"),
            (.google, "https://www.google.com/search?q=hello"),
            (.bing, "https://www.bing.com/search?q=hello"),
            (.brave, "https://search.brave.com/search?q=hello")
        ]
        for (engine, destination) in searchDestinations {
            try expect(engine.searchURL(for: "hello")?.absoluteString == destination,
                       "\(engine.name) opens search results directly")
            let query = "C++ & café #1? / weather in New York"
            let url = engine.searchURL(for: query)!
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            // Search providers decode '+' as a space, unlike URLComponents.
            let decoded = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding
            try expect(decoded == "q=" + query && components.fragment == nil && components.queryItems?.count == 1,
                       "\(engine.name) preserves punctuation, spaces and Unicode in the query")
        }

        let webData = WKWebsiteDataStore.nonPersistent()
        let saved = [record("auth", "old"), record("session", "saved"), record("persistent", "stale", expires: Date().addingTimeInterval(3600))]
        let memory = MemoryCookieBackup(data: try JSONEncoder().encode(saved))
        let store = BrowserSessionStore(websiteDataStore: webData, backup: memory.backup)
        await set(record("auth", "current").cookie!, in: webData)
        try expect(try await store.restoreSavedCookies() == 1, "Only missing session cookies are restored")
        let restored = await cookies(in: webData)
        try expect(restored.first { $0.name == "auth" }?.value == "current", "The current WebKit cookie wins over an older backup")
        try expect(!restored.contains { $0.name == "persistent" }, "Backups cannot resurrect deleted persistent cookies")
        try expect(try await store.saveCookies() == 2, "Backups contain only session cookies")
        _ = try await store.saveCookies()
        try expect(memory.writeCount == 1, "An unchanged backup does not write again")
        try expect(memory.allWritesOffMainThread, "Backup serialization/storage runs off the UI thread")
        let auth = restored.first { $0.name == "auth" }!
        await withCheckedContinuation { continuation in webData.httpCookieStore.delete(auth) { continuation.resume() } }
        _ = try await store.saveCookies()
        let afterLogout = try JSONDecoder().decode([BrowserCookieRecord].self, from: memory.data!)
        try expect(!afterLogout.contains { $0.name == "auth" }, "Deleted session cookies disappear from the next backup")
        try await store.forgetSavedCookies()
        try expect(memory.data == nil, "Forgetting removes the extra backup")

        let suite = "NotchBrowser.CookieObserverTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let observedData = WKWebsiteDataStore.nonPersistent()
        let observedBackup = MemoryCookieBackup()
        let library = BrowserLibrary(defaults: defaults, backgroundFileURL: folder.appendingPathComponent("background.jpg"),
                                     websiteDataStore: observedData, cookieBackup: observedBackup.backup, cookieBackupWatchInterval: 0.1)
        await library.restoreSessionIfNeeded()
        let fixture = URL(string: ProcessInfo.processInfo.environment["NOTCH_SESSION_TEST_URL"]!)!
        let browser = BrowserModel(library: library, startsEmpty: true)
        defer { browser.close() }
        library.searchEngine = .google
        for query in ["hello", "weather tomorrow", "C++ & café"] {
            browser.addressText = query
            browser.submitAddress()
            let submitted = browser.requestedURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            try expect(submitted?.host == "www.google.com" && submitted?.path == "/search"
                       && submitted?.queryItems == [URLQueryItem(name: "q", value: query)],
                       "Submitting '\(query)' navigates directly to Google results")
            // Check the real submission path without sending fixture queries out.
            browser.stopLoading()
        }
        browser.navigate(to: fixture)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = browser.webView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await wait("local website") { browser.pageTitle == "Cookie observer fixture" && !browser.isLoading }
        library.setSessionActivity(.surface, active: true)
        _ = try await browser.webView!.evaluateJavaScript("for(let i=0;i<5;i++) document.cookie='burst='+i+';path=/;SameSite=Strict'")
        try await wait("coalesced cookie-change backup") { observedBackup.writeCount == 1 }
        let burst = try JSONDecoder().decode([BrowserCookieRecord].self, from: observedBackup.data!)
        try expect(burst.first?.value == "4", "A cookie-change burst saves the final value once")

        for _ in 0..<3 {
            browser.navigate(to: fixture)
            try await wait("local navigation") { browser.pageTitle == "Cookie observer fixture" && !browser.isLoading }
        }
        try await Task.sleep(nanoseconds: 1_200_000_000)
        try expect(observedBackup.writeCount == 1, "Navigation without cookie changes performs no backup writes")
        library.saveSessionNow()
        try await wait("explicit session save") { observedBackup.writeCount == 2 }
        try expect(observedBackup.lastAllowedInteraction, "An explicit save keeps the interactive Keychain policy")
        _ = try await browser.webView!.evaluateJavaScript("document.cookie='burst=after-manual-save;path=/;SameSite=Strict'")
        do {
            try await wait("automatic save after a manual save") { observedBackup.writeCount == 3 }
        } catch {
            print("Backup count=\(observedBackup.writeCount), latest=\(String(data: observedBackup.data ?? Data(), encoding: .utf8) ?? ""), cookie values=\(await cookies(in: observedData).map(\.value))")
            throw error
        }
        try expect(!observedBackup.lastAllowedInteraction, "Automatic saves stay noninteractive")
        _ = try await browser.webView!.evaluateJavaScript("document.cookie='burst=pending-forget;path=/;SameSite=Strict'")
        library.forgetSavedSession()
        try await wait("forgetting a queued backup") { library.sessionStatus == "Saved session forgotten" }
        try await Task.sleep(nanoseconds: 1_200_000_000)
        try expect(observedBackup.data == nil, "A queued automatic save cannot recreate a forgotten backup")
    }

    private static func record(_ name: String, _ value: String, expires: Date? = nil) -> BrowserCookieRecord {
        BrowserCookieRecord(name: name, value: value, domain: "fixture.test", path: "/", expiresAt: expires,
                            isSecure: true, isHTTPOnly: true)
    }
    @MainActor private static func set(_ cookie: HTTPCookie, in store: WKWebsiteDataStore) async {
        await withCheckedContinuation { continuation in store.httpCookieStore.setCookie(cookie) { continuation.resume() } }
    }
    @MainActor private static func cookies(in store: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) } }
    }
    @MainActor private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw NSError(domain: "BrowserSessionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        checks += 1
    }
    @MainActor private static func wait(_ message: String, timeout: Double = 8, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { throw NSError(domain: "BrowserSessionTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out: " + message]) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private final class MemoryCookieBackup: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data?
    private var writes = 0
    private var offMain = true
    private var allowedInteraction = false
    init(data: Data? = nil) { bytes = data }
    var data: Data? { lock.withLock { bytes } }
    var writeCount: Int { lock.withLock { writes } }
    var allWritesOffMainThread: Bool { lock.withLock { offMain } }
    var lastAllowedInteraction: Bool { lock.withLock { allowedInteraction } }
    var backup: BrowserCookieBackup {
        BrowserCookieBackup(load: { self.data }, save: { data, interaction in
            self.lock.withLock {
                self.bytes = data
                self.writes += 1
                self.offMain = self.offMain && !Thread.isMainThread
                self.allowedInteraction = interaction
            }
        }, remove: { self.lock.withLock { self.bytes = nil } })
    }
}
