import SwiftUI
import AppKit
import Sparkle

@main
struct NotchBrowserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let updaterController: SPUStandardUpdaterController

    init() {
        #if DEBUG
        let startAutomatically = false
        #else
        let startAutomatically = true
        #endif
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startAutomatically,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra {
            Button("Show Browser") {
                appDelegate.showBrowser()
            }

            BrowserLookupMenu(lookup: appDelegate.lookup)
            Button("Search Screen Region with Lens…") { appDelegate.searchScreenRegion() }

            Divider()

            BrowserAgentMenu(activity: appDelegate.agentActivity)

            if let error = appDelegate.agentConnectionError {
                Text(error)
            }

            Button("Enter License Key…") {
                appDelegate.showLicenseOnboarding()
            }

            Button("Import Browser Data…") {
                appDelegate.showImportOnboarding()
            }

            Divider()
            BrowserLaunchAtLoginMenu()

            CheckForUpdatesMenuItem(updater: updaterController.updater)

            #if DEBUG
            Divider()
            Button("Debug: Preview Onboarding") {
                appDelegate.previewOnboarding()
            }
            #endif

            Divider()

            Button("Quit Notch Browser") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(nsImage: BrowserAppIcon.menuBarImage)
                .renderingMode(.original)
                .accessibilityLabel("Notch Browser")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CheckForUpdatesCommands(updater: updaterController.updater)

            CommandGroup(after: .appSettings) {
                BrowserLaunchAtLoginMenu()
            }

            CommandMenu("Browser") {
                Button("New Tab") { appDelegate.newTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Close Tab") { appDelegate.closeTab() }
                    .keyboardShortcut("w", modifiers: .command)
                Button("Reopen Closed Tab") { appDelegate.reopenClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Focus Address") { appDelegate.focusAddress() }
                    .keyboardShortcut("l", modifiers: .command)
                Button("Find in Page…") { appDelegate.showFind() }
                    .keyboardShortcut("f", modifiers: .command)
                Divider()
                BrowserLookupMenu(lookup: appDelegate.lookup)
                Button("Search Screen Region with Lens…") { appDelegate.searchScreenRegion() }
                Divider()
                Button("Next Tab") { appDelegate.selectAdjacentTab() }
                    .keyboardShortcut(.tab, modifiers: .control)
                Button("Previous Tab") { appDelegate.selectAdjacentTab(backwards: true) }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])
                Divider()
                Button("Go Back") { appDelegate.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Go Forward") { appDelegate.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Reload Page") { appDelegate.reloadPage() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

private struct BrowserLookupMenu: View {
    @ObservedObject var lookup: BrowserLookupCoordinator
    var body: some View {
        Button("Look Up Clipboard") { lookup.lookUpClipboard() }
            .keyboardShortcut(.space, modifiers: [.control, .shift])
        Toggle("Enable Clipboard Shortcut", isOn: Binding(
            get: { lookup.isShortcutEnabled }, set: { lookup.setShortcutEnabled($0) }
        ))
        if let error = lookup.shortcutError { Text(error).font(.caption) }
    }
}

private struct BrowserAgentMenu: View {
    @ObservedObject var activity: BrowserAgentActivity

    var body: some View {
        if activity.isPaused {
            Button("Resume Agent Control") { activity.resume() }
        } else {
            Button("Stop Agent Control") { activity.stop() }
        }
    }
}
