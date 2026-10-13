import Combine
import Foundation

@MainActor
final class TerminalTabsModel: ObservableObject {
    @Published private(set) var tabs: [TerminalModel]
    @Published private(set) var selectedTabID: UUID

    init() {
        let firstTab = TerminalModel(title: "~")
        tabs = [firstTab]
        selectedTabID = firstTab.id
    }

    var selectedTab: TerminalModel {
        tabs.first(where: { $0.id == selectedTabID }) ?? tabs[0]
    }

    @discardableResult
    func addTab() -> TerminalModel {
        let tab = TerminalModel(title: nextTabTitle())
        tabs.append(tab)
        selectedTabID = tab.id
        return tab
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func closeSelectedTab() {
        closeTab(selectedTabID)
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }

        let wasSelected = selectedTabID == id
        let closingTab = tabs.remove(at: index)
        closingTab.stop()

        guard wasSelected, !tabs.isEmpty else { return }
        selectedTabID = tabs[min(index, tabs.count - 1)].id
    }

    func stopAll() {
        tabs.forEach { $0.stop() }
    }

    private func nextTabTitle() -> String {
        let baseTitle = "~"
        let existingTitles = Set(tabs.map(\.title))
        guard existingTitles.contains(baseTitle) else { return baseTitle }

        var suffix = 2
        while existingTitles.contains(baseTitle + " " + String(suffix)) {
            suffix += 1
        }
        return baseTitle + " " + String(suffix)
    }
}
