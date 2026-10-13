import Combine
import Foundation
import SwiftUI

@MainActor
final class BrowserAgentActivity: ObservableObject {
    @Published private(set) var session: String?
    @Published private(set) var isPaused = false
    private var expiry: Task<Void, Never>?
    private(set) var generation = 0
    var onStop: (() -> Void)?

    func begin(session: String) throws -> Int {
        guard !isPaused else {
            throw BrowserAgentError(code: "agent_paused", message: "Agent control is paused. Resume it in the Notch Browser menu or activity indicator.")
        }
        expiry?.cancel()
        self.session = session
        return generation
    }

    func finish() {
        expiry?.cancel()
        expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            self?.session = nil
        }
    }

    func done(session: String) {
        guard self.session == session else { return }
        expiry?.cancel()
        self.session = nil
    }

    func stop() {
        generation += 1
        expiry?.cancel()
        session = nil
        isPaused = true
        onStop?()
    }

    func resume() {
        isPaused = false
    }

    func check(_ generation: Int) throws {
        guard !isPaused, generation == self.generation else {
            throw BrowserAgentError(code: "agent_paused", message: "You stopped agent control in Notch Browser.")
        }
    }
}

struct BrowserAgentActivityView: View {
    @ObservedObject var activity: BrowserAgentActivity
    var compact = false

    var body: some View {
        Group {
            if activity.session != nil || activity.isPaused {
                if compact {
                    activityDot
                        .help(activity.isPaused ? "Agent paused" : "Agent working")
                        .accessibilityLabel(activity.isPaused ? "Agent paused" : "Agent working")
                        .allowsHitTesting(false)
                } else {
                    HStack(spacing: 7) {
                        activityDot
                        Text(activity.isPaused ? "Agent paused" : "Agent working")
                            .font(.system(size: 11, weight: .medium))
                        Button {
                            if activity.isPaused {
                                activity.resume()
                            } else {
                                activity.stop()
                            }
                        } label: {
                            Text(activity.isPaused ? "Resume" : "Stop")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 5)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(activity.isPaused ? "Resume agent control" : "Stop agent control")
                        .help(activity.isPaused ? "Resume agent control" : "Stop agent control")
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        Capsule().fill(Color(red: 0, green: 0, blue: 0, opacity: 0.9))
                    }
                }
            }
        }
    }

    private var activityDot: some View {
        Circle()
            .fill(activity.isPaused ? Color.orange : Color.green)
            .frame(width: 6, height: 6)
    }
}
