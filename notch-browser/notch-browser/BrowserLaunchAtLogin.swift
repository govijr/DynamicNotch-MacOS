import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class BrowserLaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    private let service = SMAppService.mainApp

    init() {
        refresh()
    }

    func refresh() {
        let status = service.status
        // A pending approval is still a requested login item, so keep the
        // toggle on and let the user cancel it or finish approval in Settings.
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        defer {
            refresh()
            isUpdating = false
        }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = "Couldn’t change Launch at Login: \(error.localizedDescription)"
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

struct BrowserLaunchAtLoginMenu: View {
    @StateObject private var login = BrowserLaunchAtLogin()

    var body: some View {
        Group {
            Toggle("Launch at Login", isOn: Binding(
                get: { login.isEnabled },
                set: { login.setEnabled($0) }
            ))
            .disabled(login.isUpdating)

            if login.needsApproval {
                Text("Allow Notch Browser in Login Items")
                Button("Open Login Items Settings…", action: login.openLoginItemsSettings)
            } else if let error = login.errorMessage {
                Text(error)
                Button("Open Login Items Settings…", action: login.openLoginItemsSettings)
            }
        }
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
        }
    }
}
