import AppKit
import SwiftUI
import WebKit

// The harness uses the production controller, transport, DOM bridge, and tab
// lifecycle with an ephemeral data store. It never reads real login cookies,
// license keys, or the user's saved browsing session.
@MainActor
final class HarnessDelegate: NSObject, NSApplicationDelegate {
    var tabs: BrowserTabsModel!
    let activity = BrowserAgentActivity()
    var server: BrowserAgentServer!
    var controller: BrowserAgentController!
    var window: NSWindow!
    var unlocked = true
    var timer: Timer?
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOTCH_BROWSER_TEST_DIR"]!)
    let suite = "NotchBrowser.AgentTests.\(UUID().uuidString)"
    var defaults: UserDefaults!

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(try! JSONSerialization.data(withJSONObject: ["urls": [NSNull()], "activeIndex": 0]), forKey: "notchBrowser.openTabs.v1")
        tabs = BrowserTabsModel(library: .shared, defaults: defaults)
        window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1024, height: 720), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Notch Browser agent test"
        window.isReleasedWhenClosed = false
        controller = BrowserAgentController(tabs: tabs, activity: activity, isUnlocked: { [weak self] in self?.unlocked == true },
            expand: { [weak self] in
                guard let self else { return }
                window.contentView = tabs.activeBrowser.ensureWebView()
                window.makeKeyAndOrderFront(nil)
            },
            collapse: { [weak self] in
                self?.window.contentView = NSView()
                self?.window.orderOut(nil)
            })
        server = BrowserAgentServer(controller: controller)
        server.start()
        let state: [String: Any] = ["ready": server.startupError == nil, "error": server.startupError ?? ""]
        try! JSONSerialization.data(withJSONObject: state).write(to: root.appendingPathComponent("ready.json"))
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.readControl() }
        }
    }

    func readControl() {
        let url = root.appendingPathComponent("control.txt")
        guard let command = try? String(contentsOf: url, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: url)
        switch command {
        case "pause": activity.stop()
        case "resume": activity.resume()
        case "locked": unlocked = false
        case "unlocked": unlocked = true
        case "shutdown": NSApplication.shared.terminate(nil)
        default: break
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
        defaults.removePersistentDomain(forName: suite)
    }
}

@main
struct Harness {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = HarnessDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
