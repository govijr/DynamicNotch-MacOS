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

    private struct SavedSession: Codable {
        var urls: [String?]
        var activeIndex: Int
    }

    var activeBrowser: BrowserModel {
        tabs.first { $0.id == activeTabID } ?? tabs[0]
    }

    init(library: BrowserLibrary, defaults: UserDefaults = .standard) {
        self.library = library
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.sessionKey),
           let saved = try? JSONDecoder().decode(SavedSession.self, from: data),
           !saved.urls.isEmpty {
            let restoredTabs = saved.urls.map { urlString in
                let url = urlString.flatMap { URL(string: $0) }.flatMap(Self.validWebURL)
                return BrowserModel(
                    library: library,
                    startsEmpty: url == nil,
                    initialURL: url
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
            self?.persistSession()
        }
    }

    private func persistSession() {
        let saved = SavedSession(
            urls: tabs.map { $0.requestedURL?.absoluteString },
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
