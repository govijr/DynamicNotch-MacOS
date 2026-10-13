import AppKit
import Combine
import GhosttyTerminal
import SwiftUI

@MainActor
final class TerminalModel: ObservableObject, Identifiable {
    @Published private(set) var isRunning = false
    @Published private(set) var exitCode: Int32?
    @Published private(set) var title: String
    @Published private(set) var workingDirectory: String

    let id = UUID()
    let terminalView: TerminalView

    private let pty: LocalPTYSession
    private let session: InMemoryTerminalSession
    private let controller: TerminalController
    private var hasMounted = false

    init(title: String = "~") {
        let directory = FileManager.default.homeDirectoryForCurrentUser.path
        let pty = LocalPTYSession(workingDirectory: directory)
        let session = InMemoryTerminalSession(
            write: { data in
                pty.write(data)
            },
            resize: { viewport in
                pty.resize(to: viewport)
            }
        )
        let controller = TerminalController(
            configuration: NotchTerminalPalette.terminalConfiguration,
            theme: TerminalTheme()
        )
        let view = NotchTerminalView(frame: .zero)

        self.title = title
        workingDirectory = directory
        self.pty = pty
        self.session = session
        self.controller = controller
        terminalView = view

        view.controller = controller
        view.configuration = TerminalSurfaceOptions(
            backend: .inMemory(session),
            fontSize: 14,
            workingDirectory: directory
        )

        pty.onOutput = { data in
            session.receive(data)
        }
        pty.onExit = { [weak self] code in
            Task { @MainActor [weak self] in
                self?.handleExit(code)
            }
        }
    }

    func mountIfNeeded() {
        // A terminal view can be detached while another tab is selected. Keep
        // the Ghostty surface visible when this model is mounted again.
        terminalView.setSurfaceVisible(true)
        guard !hasMounted else { return }
        hasMounted = true
        waitForWindowThenStart()
    }

    func stop() {
        pty.stop()
    }

    func changeDirectory(to directory: String) {
        var isDirectory: ObjCBool = false
        let standardizedDirectory = URL(fileURLWithPath: directory)
            .standardizedFileURL
            .path

        guard FileManager.default.fileExists(
            atPath: standardizedDirectory,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return
        }

        guard standardizedDirectory != workingDirectory else { return }

        workingDirectory = standardizedDirectory
        title = title(for: standardizedDirectory)

        let command = "cd -- \(shellQuote(standardizedDirectory))\n"
        pty.write(Data(command.utf8))
    }

    var directoryLabel: String {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        return workingDirectory == homeDirectory ? "~" : workingDirectory
    }

    var statusText: String {
        if isRunning { return "local" }
        if let exitCode { return "exited \(exitCode)" }
        return "stopped"
    }

    func focusIfPossible() {
        guard let window = terminalView.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        _ = terminalView.acquireProgrammaticFocus()
    }

    private func waitForWindowThenStart() {
        guard terminalView.window != nil else {
            DispatchQueue.main.async { [weak self] in
                self?.waitForWindowThenStart()
            }
            return
        }

        guard !isRunning else { return }
        focusIfPossible()
        isRunning = pty.start()
    }

    private func handleExit(_ code: Int32?) {
        isRunning = false
        exitCode = code
    }

    private func title(for directory: String) -> String {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        guard directory != homeDirectory else { return "~" }

        let lastComponent = URL(fileURLWithPath: directory).lastPathComponent
        return lastComponent.isEmpty ? directory : lastComponent
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct GhosttyTerminalView: NSViewRepresentable {
    @ObservedObject var model: TerminalModel

    func makeNSView(context: Context) -> TerminalView {
        model.mountIfNeeded()
        return model.terminalView
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        model.mountIfNeeded()
    }
}
