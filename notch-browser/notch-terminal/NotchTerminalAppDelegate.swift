import AppKit
import SwiftUI

@MainActor
final class NotchTerminalAppDelegate: NSObject, NSApplicationDelegate {
    private let workspace = TerminalTabsModel()
    private var windowController: NotchTerminalWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = NotchTerminalWindowController(workspace: workspace)
        windowController.showCompact(animated: false)
    }

    func showTerminal() {
        windowController.showExpanded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        workspace.stopAll()
        return .terminateNow
    }
}
