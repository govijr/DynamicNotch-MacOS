import Foundation
import WebKit

@MainActor
final class BrowserLibrary {
    static let shared = BrowserLibrary()
    let websiteDataStore = WKWebsiteDataStore.nonPersistent()
    var lastVisitedURL: URL? { nil }
    let searchEngine = FixtureSearchEngine()
    var restoreHandler: (() async -> Void)?
    func restoreSessionIfNeeded() async { await restoreHandler?() }
    func scheduleSessionSave() {}
    func saveSessionAndWait(updateStatus: Bool) async {}
    func recordLastVisitedURL(_ url: URL) {}
    func recordVisit(url: URL, title: String) {}
}

struct FixtureSearchEngine {
    var homepageURL: URL { URL(string: "about:blank")! }
    func searchURL(for query: String) -> URL? {
        var parts = URLComponents(string: "https://duckduckgo.com")!
        parts.queryItems = [URLQueryItem(name: "q", value: query)]
        return parts.url
    }
}
