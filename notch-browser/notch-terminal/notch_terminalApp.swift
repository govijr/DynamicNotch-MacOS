import AppKit
import SwiftUI

@main
struct NotchTerminalApp: App {
    @NSApplicationDelegateAdaptor(NotchTerminalAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        MenuBarExtra("Notch Terminal", systemImage: "terminal") {
            Button("Show Terminal") {
                appDelegate.showTerminal()
            }

            Divider()

            Button("Quit Notch Terminal") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
