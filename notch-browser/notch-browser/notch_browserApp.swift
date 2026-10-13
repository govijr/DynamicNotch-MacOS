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
