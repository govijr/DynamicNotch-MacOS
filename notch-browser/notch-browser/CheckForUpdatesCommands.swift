import Combine
import Sparkle
import SwiftUI

@MainActor
private final class UpdateAvailability: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesMenuItem: View {
    @StateObject private var availability: UpdateAvailability
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _availability = StateObject(wrappedValue: UpdateAvailability(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!availability.canCheckForUpdates)
    }
}

struct CheckForUpdatesCommands: Commands {
    let updater: SPUUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesMenuItem(updater: updater)
        }
    }
}
