import AppKit
import Combine
import Foundation
import WebKit

enum BrowserSearchEngine: String, CaseIterable, Codable, Identifiable {
    case duckDuckGo
    case google
    case bing
    case brave

    var id: String { rawValue }

    var name: String {
        switch self {
        case .duckDuckGo:
            "DuckDuckGo"
        case .google:
            "Google"
        case .bing:
            "Bing"
        case .brave:
            "Brave Search"
        }
    }

    var homepageURL: URL {
        switch self {
        case .duckDuckGo:
            URL(string: "https://duckduckgo.com")!
        case .google:
            URL(string: "https://www.google.com")!
        case .bing:
            URL(string: "https://www.bing.com")!
        case .brave:
            URL(string: "https://search.brave.com")!
        }
    }

    func searchURL(for query: String) -> URL? {
        var components = URLComponents(
            url: homepageURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

struct BrowserBookmark: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    let urlString: String
    let createdAt: Date

    var url: URL? {
        URL(string: urlString)
    }
}

struct BrowserHistoryEntry: Codable, Equatable, Identifiable {
    var id: String { urlString }
    let title: String
    let urlString: String
    let visitedAt: Date
    var url: URL? { URL(string: urlString) }
}

enum BrowserStartBackground: String, CaseIterable, Identifiable {
    case midnight, plum, graphite, none, custom
    var id: String { rawValue }
    var name: String {
        switch self {
        case .midnight: "Midnight"
        case .plum: "Plum"
        case .graphite: "Graphite"
        case .none: "Solid"
        case .custom: "Your photo"
        }
    }
}

@MainActor
final class BrowserLibrary: ObservableObject {
    static let shared = BrowserLibrary()

    let websiteDataStore: WKWebsiteDataStore
    private let cookieStore: WKHTTPCookieStore

    @Published var searchEngine: BrowserSearchEngine {
        didSet {
            defaults.set(searchEngine.rawValue, forKey: Self.searchEngineKey)
        }
    }

    @Published private(set) var bookmarks: [BrowserBookmark]
    @Published private(set) var recentlyVisited: [BrowserHistoryEntry]
    @Published var startBackground: BrowserStartBackground {
        didSet { defaults.set(startBackground.rawValue, forKey: Self.startBackgroundKey) }
    }
    @Published private(set) var customBackgroundImage: NSImage?
    @Published private(set) var isImportingBackground = false
    @Published private(set) var lastVisitedURL: URL?
    @Published private(set) var isRestoringSession = false
    @Published private(set) var isImportingSession = false
    @Published private(set) var sessionStatus: String?
    @Published private(set) var chromeProfiles: [BrowserChromeProfile] = []
    @Published private(set) var hasCompletedImportOnboarding: Bool

    private let defaults: UserDefaults
    private let sessionStore: BrowserSessionStore
    private var sessionRestoreTask: Task<Void, Never>?
    private var pendingSessionSave: Task<Void, Never>?
    private var activeSessionSave: Task<Void, Never>?
    private var activeSessionSaveID: UUID?
    private var cookieObserver: BrowserCookieObserver?
    private var cookieRevision = 0
    private var savedCookieRevision = 0
    private var automaticSessionBackupEnabled = true

    private static let searchEngineKey = "notchBrowser.searchEngine"
    private static let bookmarksKey = "notchBrowser.bookmarks"
    private static let lastVisitedURLKey = "notchBrowser.lastVisitedURL"
    private static let historyKey = "notchBrowser.recentlyVisited.v1"
    private static let startBackgroundKey = "notchBrowser.startBackground.v1"
    private static let importOnboardingKey = "notchBrowser.importOnboarding.completed.v1"
    private let backgroundFileURL: URL

    init(defaults: UserDefaults = .standard, backgroundFileURL: URL? = nil,
         websiteDataStore suppliedStore: WKWebsiteDataStore? = nil, cookieBackup: BrowserCookieBackup = .keychain) {
        self.defaults = defaults
        hasCompletedImportOnboarding = defaults.bool(forKey: Self.importOnboardingKey)
        self.backgroundFileURL = backgroundFileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBrowser/start-page-background.jpg")
        startBackground = BrowserStartBackground(rawValue: defaults.string(forKey: Self.startBackgroundKey) ?? "") ?? .midnight
        if let data = try? Data(contentsOf: self.backgroundFileURL) {
            customBackgroundImage = NSImage(data: data)
        }
        if let data = defaults.data(forKey: Self.historyKey),
           let entries = try? JSONDecoder().decode([BrowserHistoryEntry].self, from: data) {
            recentlyVisited = Array(entries.filter { $0.url.map(Self.isWebURL) == true }.prefix(50))
        } else {
            recentlyVisited = []
        }

        let websiteDataStore = suppliedStore ?? WKWebsiteDataStore.default()
        self.websiteDataStore = websiteDataStore
        self.cookieStore = websiteDataStore.httpCookieStore
        self.sessionStore = BrowserSessionStore(websiteDataStore: websiteDataStore, backup: cookieBackup)

        let storedSearchEngine = defaults.string(forKey: Self.searchEngineKey)
        searchEngine = BrowserSearchEngine(rawValue: storedSearchEngine ?? "") ?? .duckDuckGo

        if let data = defaults.data(forKey: Self.bookmarksKey),
           let storedBookmarks = try? JSONDecoder().decode([BrowserBookmark].self, from: data) {
            bookmarks = storedBookmarks
        } else {
            bookmarks = []
        }

        if let lastVisitedURLString = defaults.string(forKey: Self.lastVisitedURLKey) {
            lastVisitedURL = URL(string: lastVisitedURLString)
        } else {
            lastVisitedURL = nil
        }
        let observer = BrowserCookieObserver { [weak self] in self?.scheduleSessionSave() }
        cookieObserver = observer
        cookieStore.add(observer)
    }

    deinit {
        if let cookieObserver {
            let store = cookieStore
            Task { @MainActor in store.remove(cookieObserver) }
        }
    }

    func recordLastVisitedURL(_ url: URL) {
        guard Self.isWebURL(url) else { return }

        let normalizedURL = Self.normalizedURLString(for: url)
        guard lastVisitedURL?.absoluteString != normalizedURL else { return }

        lastVisitedURL = URL(string: normalizedURL)
        defaults.set(normalizedURL, forKey: Self.lastVisitedURLKey)
    }

    func recordVisit(url: URL, title: String) {
        guard Self.isWebURL(url) else { return }
        let normalizedURL = Self.normalizedURLString(for: url)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        recentlyVisited.removeAll { $0.urlString == normalizedURL }
        recentlyVisited.insert(BrowserHistoryEntry(
            title: cleanTitle.isEmpty ? (url.host ?? "Website") : cleanTitle,
            urlString: normalizedURL, visitedAt: Date()
        ), at: 0)
        recentlyVisited = Array(recentlyVisited.prefix(50))
        persistHistory()
    }

    func clearRecentVisits() {
        recentlyVisited = []
        persistHistory()
    }

    func removeRecentVisit(_ entry: BrowserHistoryEntry) {
        recentlyVisited.removeAll { $0.id == entry.id }
        persistHistory()
    }

    @discardableResult
    func saveBookmark(title: String, url: URL, replacing id: UUID? = nil) -> Bool {
        guard Self.isWebURL(url) else { return false }
        let normalizedURL = Self.normalizedURLString(for: url)
        guard !bookmarks.contains(where: { $0.urlString == normalizedURL && $0.id != id }) else { return false }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = BrowserBookmark(id: id ?? UUID(), title: cleanTitle.isEmpty ? (url.host ?? "Website") : cleanTitle,
                                       urlString: normalizedURL, createdAt: Date())
        if let id, let index = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks[index] = bookmark
        } else {
            bookmarks.append(bookmark)
        }
        persistBookmarks()
        return true
    }

    func setCustomBackground(from url: URL) async throws {
        guard !isImportingBackground else { return }
        isImportingBackground = true
        defer { isImportingBackground = false }
        let destination = backgroundFileURL
        let data = try await Task.detached(priority: .userInitiated) {
            try BrowserBackgroundImage.prepare(from: url, destination: destination)
        }.value
        guard let image = NSImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        customBackgroundImage = image
        startBackground = .custom
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(recentlyVisited) else { return }
        defaults.set(data, forKey: Self.historyKey)
    }

    func isBookmarked(url: URL?) -> Bool {
        guard let url else { return false }
        let normalizedURL = Self.normalizedURLString(for: url)
        return bookmarks.contains { $0.urlString == normalizedURL }
    }

    @discardableResult
    func toggleBookmark(url: URL?, title: String) -> Bool {
        guard let url, Self.isWebURL(url) else { return false }

        let normalizedURL = Self.normalizedURLString(for: url)
        if let index = bookmarks.firstIndex(where: { $0.urlString == normalizedURL }) {
            bookmarks.remove(at: index)
            persistBookmarks()
            return false
        }

        let fallbackTitle = url.host ?? "Bookmarked page"
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        bookmarks.append(
            BrowserBookmark(
                id: UUID(),
                title: cleanTitle.isEmpty || cleanTitle == "Ready when you are"
                    ? fallbackTitle
                    : cleanTitle,
                urlString: normalizedURL,
                createdAt: Date()
            )
        )
        persistBookmarks()
        return true
    }

    func removeBookmark(url: URL?) {
        guard let url else { return }
        let normalizedURL = Self.normalizedURLString(for: url)
        let originalCount = bookmarks.count
        bookmarks.removeAll { $0.urlString == normalizedURL }
        if bookmarks.count != originalCount {
            persistBookmarks()
        }
    }

    func restoreSessionIfNeeded() async {
        if let sessionRestoreTask {
            await sessionRestoreTask.value
            return
        }

        let sessionRestoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            isRestoringSession = true

            do {
                let restoredCount = try await sessionStore.restoreSavedCookies()
                if restoredCount > 0 {
                    sessionStatus = "Restored \(restoredCount) saved session cookies"
                }
            } catch {
                sessionStatus = "Saved session could not be restored"
            }

            isRestoringSession = false
            if cookieRevision != savedCookieRevision { queueSessionSave() }
        }

        self.sessionRestoreTask = sessionRestoreTask
        await sessionRestoreTask.value
    }

    func scheduleSessionSave() {
        cookieRevision += 1
        print("Cookie test revision \(cookieRevision), saved \(savedCookieRevision), queued \(pendingSessionSave != nil), restoring \(isRestoringSession)")
        queueSessionSave()
    }

    private func queueSessionSave() {
        guard automaticSessionBackupEnabled, !isRestoringSession, pendingSessionSave == nil else { return }
        pendingSessionSave = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.pendingSessionSave = nil
            await self.saveSessionAndWait(updateStatus: false)
        }
    }

    func saveSessionNow() {
        automaticSessionBackupEnabled = true
        pendingSessionSave?.cancel()
        pendingSessionSave = nil
        Task { @MainActor [weak self] in
            await self?.saveSessionAndWait(updateStatus: true)
        }
    }

    func saveSessionAndWait(updateStatus: Bool) async {
        print("Cookie test save \(updateStatus), revision \(cookieRevision), saved \(savedCookieRevision), active \(activeSessionSave != nil)")
        if let activeSessionSave {
            await activeSessionSave.value
            if !updateStatus && cookieRevision == savedCookieRevision { return }
        }
        guard updateStatus || cookieRevision != savedCookieRevision else { return }
        let revision = cookieRevision
        let saveID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let cookieCount = try await sessionStore.saveCookies(allowInteraction: updateStatus)
                savedCookieRevision = max(savedCookieRevision, revision)
                if updateStatus {
                    sessionStatus = cookieCount > 0 ? "Session saved securely" : "No session cookies to save yet"
                }
            } catch {
                if updateStatus { sessionStatus = "Session could not be saved" }
            }
        }
        activeSessionSave = task
        activeSessionSaveID = saveID
        await task.value
        if activeSessionSaveID == saveID {
            activeSessionSave = nil
            activeSessionSaveID = nil
        }
    }

    func refreshChromeProfiles() {
        chromeProfiles = BrowserSessionStore.discoverChromeProfiles()
    }

    func completeImportOnboarding() {
        hasCompletedImportOnboarding = true
        defaults.set(true, forKey: Self.importOnboardingKey)
    }

    func importChromeData(from profile: BrowserChromeProfile, bookmarks includeBookmarks: Bool,
                          cookies includeCookies: Bool) async -> Bool {
        guard !isImportingSession, includeBookmarks || includeCookies else { return false }
        isImportingSession = true
        sessionStatus = "Importing from \(profile.profileName)…"
        defer { isImportingSession = false }
        var summaries: [String] = []
        var didImport = false
        if includeBookmarks {
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    try BrowserBookmarkImporter.chrome(from: profile.cookieDatabaseURL)
                }.value
                let count = mergeBookmarks(imported)
                summaries.append(count > 0 ? "Imported \(count) bookmarks." : "Bookmarks are already available.")
                didImport = true
            } catch {
                summaries.append("Bookmarks: \(error.localizedDescription)")
            }
        }
        if includeCookies {
            automaticSessionBackupEnabled = true
            do {
                await restoreSessionIfNeeded()
                let result = try await sessionStore.importChromeCookies(from: profile.cookieDatabaseURL)
                _ = try await sessionStore.saveCookies(allowInteraction: true)
                summaries.append("Imported \(result.importedCount) cookies.")
                if result.skippedCount > 0 { summaries.append("\(result.skippedCount) cookies could not be read.") }
                didImport = true
            } catch { summaries.append("Cookies: \(error.localizedDescription)") }
        }
        sessionStatus = summaries.joined(separator: " ")
        return didImport
    }

    func importSafariBookmarks(from url: URL) async -> Bool {
        guard !isImportingSession else { return false }
        isImportingSession = true
        sessionStatus = "Importing Safari bookmarks…"
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
            isImportingSession = false
        }
        do {
            let imported = try await Task.detached(priority: .userInitiated) {
                try BrowserBookmarkImporter.safariExport(from: url)
            }.value
            let count = mergeBookmarks(imported)
            sessionStatus = count > 0 ? "Imported \(count) Safari bookmarks." : "Safari bookmarks are already available."
            return true
        } catch {
            sessionStatus = error.localizedDescription
            return false
        }
    }

    private func mergeBookmarks(_ imported: [ImportedBrowserBookmark]) -> Int {
        var existing = Set(bookmarks.map(\.urlString))
        var added = 0
        for bookmark in imported {
            guard Self.isWebURL(bookmark.url) else { continue }
            let urlString = Self.normalizedURLString(for: bookmark.url)
            guard existing.insert(urlString).inserted else { continue }
            let title = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
            bookmarks.append(.init(id: UUID(), title: title.isEmpty ? bookmark.url.host ?? "Website" : title,
                                   urlString: urlString, createdAt: Date()))
            added += 1
        }
        if added > 0 { persistBookmarks() }
        return added
    }

    func forgetSavedSession() {
        automaticSessionBackupEnabled = false
        pendingSessionSave?.cancel()
        pendingSessionSave = nil
        activeSessionSave?.cancel()
        activeSessionSave = nil
        activeSessionSaveID = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await sessionStore.forgetSavedCookies()
                savedCookieRevision = cookieRevision
                sessionStatus = "Saved session forgotten"
            } catch { sessionStatus = "Saved session could not be forgotten" }
        }
    }

    private func persistBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: Self.bookmarksKey)
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private static func normalizedURLString(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }
}

private final class BrowserCookieObserver: NSObject, WKHTTPCookieStoreObserver {
    private let onChange: @MainActor () -> Void
    init(onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in self?.onChange() }
    }
}
