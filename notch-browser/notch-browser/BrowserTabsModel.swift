import Combine
import Foundation
import WebKit

@MainActor
final class BrowserTabsModel: ObservableObject {
    @Published private(set) var tabs: [BrowserModel]
    @Published private(set) var activeTabID: UUID
    @Published var isChromeVisible = true

    private let library: BrowserLibrary
    private let defaults: UserDefaults
    private static let sessionKey = "notchBrowser.openTabs.v1"
    static let snapshotCountLimit = 3
    static let snapshotByteLimit = 16 * 1024 * 1024
    private var pendingSessionPersistence: Task<Void, Never>?

    private struct SavedTab: Codable {
        var url: String?
        var title: String?
    }
    private struct SavedSession: Codable {
        var tabs: [SavedTab]
        var activeIndex: Int

        private enum CodingKeys: String, CodingKey { case tabs, urls, activeIndex }
        init(tabs: [SavedTab], activeIndex: Int) {
            self.tabs = tabs
            self.activeIndex = activeIndex
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            activeIndex = try values.decode(Int.self, forKey: .activeIndex)
            if let tabs = try values.decodeIfPresent([SavedTab].self, forKey: .tabs) {
                self.tabs = tabs
            } else {
                // Preserve ordered tabs from the original URL-only session.
                tabs = try values.decode([String?].self, forKey: .urls).map { SavedTab(url: $0, title: nil) }
            }
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(tabs, forKey: .tabs)
            try values.encode(activeIndex, forKey: .activeIndex)
        }
    }

    var activeBrowser: BrowserModel {
        tabs.first { $0.id == activeTabID } ?? tabs[0]
    }

    init(library: BrowserLibrary, defaults: UserDefaults = .standard) {
        self.library = library
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.sessionKey),
           let saved = try? JSONDecoder().decode(SavedSession.self, from: data),
           !saved.tabs.isEmpty {
            let restoredTabs = saved.tabs.map { savedTab in
                let url = savedTab.url.flatMap { URL(string: $0) }.flatMap(Self.validWebURL)
                return BrowserModel(
                    library: library,
                    startsEmpty: url == nil,
                    initialURL: url,
                    restoredTitle: savedTab.title
                )
            }
            tabs = restoredTabs
            activeTabID = restoredTabs[min(max(saved.activeIndex, 0), restoredTabs.count - 1)].id
        } else if defaults.data(forKey: Self.sessionKey) != nil {
            let emptyTab = BrowserModel(library: library, startsEmpty: true)
            tabs = [emptyTab]
            activeTabID = emptyTab.id
        } else {
            let firstTab = BrowserModel(library: library)
            tabs = [firstTab]
            activeTabID = firstTab.id
        }

        tabs.forEach(attachSessionPersistence)
    }

    func addTab() {
        _ = newTab()
    }

    @discardableResult
    func newTab(select: Bool = true) -> BrowserModel {
        activeBrowser.captureVisiblePage()
        let tab = BrowserModel(library: library, startsEmpty: true)
        tabs.append(tab)
        if select { activeTabID = tab.id }
        attachSessionPersistence(tab)
        persistSession()
        return tab
    }

    func createPopupTab(configuration: WKWebViewConfiguration) -> WKWebView {
        activeBrowser.captureVisiblePage()
        let tab = BrowserModel(library: library, startsEmpty: true)
        attachSessionPersistence(tab)
        let webView = tab.ensureWebView(configuration: configuration)
        tabs.append(tab)
        activeTabID = tab.id
        persistSession()
        return webView
    }

    func selectTab(_ id: UUID) {
        guard id != activeTabID, tabs.contains(where: { $0.id == id }) else { return }
        activeBrowser.captureVisiblePage()
        activeTabID = id
        persistSession()
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].close()
        if tabs.count == 1 {
            let tab = BrowserModel(library: library, startsEmpty: true)
            tabs = [tab]
            activeTabID = tab.id
            attachSessionPersistence(tab)
            persistSession()
            return
        }

        if id == activeTabID {
            let nextIndex = index == tabs.count - 1 ? index - 1 : index + 1
            activeTabID = tabs[nextIndex].id
        }
        tabs.remove(at: index)
        persistSession()
    }

    private func attachSessionPersistence(_ browser: BrowserModel) {
        browser.onCreateWebView = { [weak self] configuration, _ in
            guard let self else { return WKWebView(frame: .zero, configuration: configuration) }
            return self.createPopupTab(configuration: configuration)
        }
        browser.onSessionChange = { [weak self] in
            self?.scheduleSessionPersistence()
        }
        browser.onSnapshotChange = { [weak self] in
            self?.trimPageSnapshots()
        }
    }

    private func trimPageSnapshots() {
        let snapshots = tabs.filter { $0.lastPageSnapshot != nil }.sorted {
            if ($0.id == activeTabID) != ($1.id == activeTabID) { return $0.id == activeTabID }
            return ($0.snapshotCapturedAt ?? .distantPast) > ($1.snapshotCapturedAt ?? .distantPast)
        }
        var count = 0
        var bytes = 0
        for browser in snapshots {
            if count < Self.snapshotCountLimit && bytes + browser.snapshotMemoryCost <= Self.snapshotByteLimit {
                count += 1
                bytes += browser.snapshotMemoryCost
            } else {
                browser.discardPageSnapshot()
            }
        }
    }

    private func scheduleSessionPersistence() {
        guard pendingSessionPersistence == nil else { return }
        pendingSessionPersistence = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self, !Task.isCancelled else { return }
            self.pendingSessionPersistence = nil
            self.persistSession()
        }
    }

    func persistSession() {
        pendingSessionPersistence?.cancel()
        pendingSessionPersistence = nil
        let saved = SavedSession(
            tabs: tabs.map { SavedTab(url: $0.requestedURL?.absoluteString, title: $0.isEmpty ? nil : $0.pageTitle) },
            activeIndex: tabs.firstIndex { $0.id == activeTabID } ?? 0
        )
        guard let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: Self.sessionKey)
    }

    private static func validWebURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil
        else { return nil }
        return url
    }
}
