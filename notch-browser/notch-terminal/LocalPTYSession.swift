import Darwin
import Foundation
import GhosttyTerminal

/// Owns the real local shell behind the embedded Ghostty surface.
///
/// Ghostty renders and interprets terminal bytes. This type only owns the
/// macOS pseudo-terminal and keeps that process alive independently of the
/// notch presentation.
final class LocalPTYSession: @unchecked Sendable {
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(
        label: "com.govi.notch-terminal.pty",
        qos: .userInitiated
    )
    private let workingDirectory: String

    private var masterFileDescriptor: Int32 = -1
    private var childProcessID: pid_t = -1
    private var readSource: DispatchSourceRead?
    private var didFinish = false

    var onOutput: ((Data) -> Void)?
    var onExit: ((Int32?) -> Void)?

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    @discardableResult
    func start() -> Bool {
        lock.lock()
        guard childProcessID == -1 else {
            lock.unlock()
            return true
        }

        var master: Int32 = -1
        var size = winsize(
            ws_row: 24,
            ws_col: 96,
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        let child = forkpty(&master, nil, nil, &size)

        guard child >= 0 else {
            lock.unlock()
            return false
        }

        if child == 0 {
            launchShellInChild()
        }

        masterFileDescriptor = master
        childProcessID = child
        didFinish = false
        lock.unlock()

        let currentFlags = fcntl(master, F_GETFL)
        if currentFlags >= 0 {
            _ = fcntl(master, F_SETFL, currentFlags | O_NONBLOCK)
        }

        let source = DispatchSource.makeReadSource(
            fileDescriptor: master,
            queue: ioQueue
        )
        source.setEventHandler { [weak self] in
            self?.readAvailableOutput()
        }
        source.setCancelHandler {
            close(master)
        }
        readSource = source
        source.resume()
        return true
    }

    nonisolated func write(_ data: Data) {
        guard !data.isEmpty else { return }

        ioQueue.async { [weak self] in
            self?.writeOnQueue(data)
        }
    }

    nonisolated func resize(to viewport: InMemoryTerminalViewport) {
        let columns = UInt16(clamping: Int(viewport.columns))
        let rows = UInt16(clamping: Int(viewport.rows))
        guard columns > 0, rows > 0 else { return }

        ioQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let descriptor = self.masterFileDescriptor
            self.lock.unlock()

            guard descriptor >= 0 else { return }
            var size = winsize(
                ws_row: rows,
                ws_col: columns,
                ws_xpixel: 0,
                ws_ypixel: 0
            )
            _ = ioctl(descriptor, TIOCSWINSZ, &size)
        }
    }

    func stop() {
        lock.lock()
        let child = childProcessID
        let source = readSource
        lock.unlock()

        if child > 0 {
            _ = kill(child, SIGTERM)
        }
        source?.cancel()
    }

    private func launchShellInChild() -> Never {
        let environment = ProcessInfo.processInfo.environment
        let shell = environment["SHELL"] ?? "/bin/zsh"

        _ = workingDirectory.withCString { path in
            chdir(path)
        }
        _ = shell.withCString { path in
            setenv("SHELL", path, 1)
        }
        // Ghostty ships its own terminfo entry with the embedded surface. Make
        // it visible to the child shell so zsh/readline can resolve keys such
        // as forward-delete instead of treating ESC sequences as text. Keep a
        // stock macOS fallback for a package build that omits the resource.
        if let terminfoPath = GhosttyRuntimeResources.terminfoDirectoryURL?.path {
            setenv("TERMINFO", terminfoPath, 1)
            setenv("TERM", "xterm-ghostty", 1)
        } else {
            setenv("TERM", "xterm-256color", 1)
        }
        setenv("COLORTERM", "truecolor", 1)
        setenv("TERM_PROGRAM", "Ghostty", 1)
        setenv("TERM_PROGRAM_VERSION", "notch-terminal", 1)

        shell.withCString { path in
            var arguments: [UnsafeMutablePointer<CChar>?] = [
                strdup(shell),
                strdup("-l"),
                strdup("-i"),
                nil,
            ]
            _ = arguments.withUnsafeMutableBufferPointer { buffer in
                execv(path, buffer.baseAddress)
            }
        }
        _exit(127)
    }

    private func writeOnQueue(_ data: Data) {
        lock.lock()
        let descriptor = masterFileDescriptor
        lock.unlock()

        guard descriptor >= 0 else { return }

        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }

            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )

                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
    }

    private func readAvailableOutput() {
        lock.lock()
        let descriptor = masterFileDescriptor
        lock.unlock()

        guard descriptor >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return -1 }
                return Darwin.read(descriptor, baseAddress, rawBuffer.count)
            }

            if count > 0 {
                onOutput?(Data(buffer[0..<count]))
                continue
            }

            if count < 0, errno == EINTR {
                continue
            }

            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }

                if errno == EIO {
                    handlePotentialPTYHangup()
                    return
                }
            }

            finish(exitStatus: nil)
            return
        }
    }

    private func handlePotentialPTYHangup() {
        lock.lock()
        let child = childProcessID
        lock.unlock()

        guard child > 0 else {
            finish(exitStatus: nil)
            return
        }

        // Darwin can report EIO briefly between forkpty and the shell opening
        // the slave side. Confirm that the child really exited before ending
        // the session, otherwise the first keystrokes are sent to a closed
        // descriptor and the UI is left showing a dead cursor.
        var status: Int32 = 0
        let result = waitpid(child, &status, WNOHANG)
        if result < 0, errno == EINTR {
            ioQueue.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
                self?.readAvailableOutput()
            }
            return
        }
        if result == 0 {
            ioQueue.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
                self?.readAvailableOutput()
            }
            return
        }

        let exitStatus: Int32?
        if result == child, (status & 0x7f) == 0 {
            exitStatus = (status >> 8) & 0xff
        } else {
            exitStatus = nil
        }
        finish(exitStatus: exitStatus)
    }

    private func finish(exitStatus: Int32?) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let child = childProcessID
        childProcessID = -1
        masterFileDescriptor = -1
        let callback = onExit
        lock.unlock()

        readSource?.cancel()

        var status: Int32 = 0
        var resolvedStatus = exitStatus
        if resolvedStatus == nil, child > 0 {
            let result = waitpid(child, &status, 0)
            if result == child, (status & 0x7f) == 0 {
                resolvedStatus = (status >> 8) & 0xff
            }
        }

        callback?(resolvedStatus)
    }
}
