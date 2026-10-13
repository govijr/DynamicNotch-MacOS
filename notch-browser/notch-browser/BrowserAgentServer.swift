import Darwin
import Foundation

@MainActor
final class BrowserAgentServer {
    private var source: DispatchSourceRead?
    private let controller: BrowserAgentController
    private(set) var startupError: String?

    init(controller: BrowserAgentController) { self.controller = controller }

    func start() {
        guard source == nil else { return }
        do {
            let path = BrowserAgentSocket.path
            let directory = (path as NSString).deletingLastPathComponent
            if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw BrowserAgentSocket.systemError() }
            var info = stat()
            guard lstat(directory, &info) == 0,
                  info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR,
                  info.st_mode & 0o077 == 0 else {
                throw BrowserAgentError(code: "unsafe_endpoint", message: "The agent socket directory must belong to you and have permissions 0700.")
            }
            let lock = Darwin.open(directory + "/control.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard lock >= 0 else { throw BrowserAgentSocket.systemError() }
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
                Darwin.close(lock)
                throw BrowserAgentError(code: "app_already_connected", message: "Another Notch Browser instance owns the agent connection.")
            }
            var keepLock = false
            defer { if !keepLock { Darwin.close(lock) } }
            let listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard listener >= 0 else { throw BrowserAgentSocket.systemError() }
            var keepListener = false
            defer { if !keepListener { Darwin.close(listener) } }
            BrowserAgentSocket.configure(listener)
            _ = fcntl(listener, F_SETFL, O_NONBLOCK)
            // Only the lock owner can remove a stale socket left by a crash.
            unlink(path)
            var address = try BrowserAgentSocket.address(path)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { throw BrowserAgentSocket.systemError() }
            guard chmod(path, 0o600) == 0, listen(listener, 16) == 0 else {
                unlink(path)
                throw BrowserAgentSocket.systemError()
            }
            let queue = DispatchQueue(label: "notch-browser.agent.accept", qos: .userInitiated)
            let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
            let clients = DispatchSemaphore(value: 16)
            source.setEventHandler { [weak self] in
                while true {
                    let client = Darwin.accept(listener, nil, nil)
                    guard client >= 0 else { break }
                    var uid: uid_t = 0, gid: gid_t = 0
                    guard getpeereid(client, &uid, &gid) == 0, uid == getuid(), clients.wait(timeout: .now()) == .success else {
                        Darwin.close(client)
                        continue
                    }
                    BrowserAgentSocket.configure(client)
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let request = try BrowserAgentSocket.readMessage(client)
                            Task { @MainActor [weak self] in
                                let response = await self?.controller.handle(request) ?? Data("{\"ok\":false,\"error\":{\"code\":\"app_closed\",\"message\":\"Notch Browser closed.\"}}".utf8)
                                DispatchQueue.global(qos: .userInitiated).async {
                                    defer { Darwin.close(client); clients.signal() }
                                    try? BrowserAgentSocket.writeMessage(response, to: client)
                                }
                            }
                        } catch {
                            Darwin.close(client)
                            clients.signal()
                        }
                    }
                }
            }
            source.setCancelHandler {
                Darwin.close(listener)
                unlink(path)
                Darwin.close(lock)
            }
            self.source = source
            keepListener = true
            keepLock = true
            startupError = nil
            source.resume()
        } catch {
            startupError = (error as? BrowserAgentError)?.message ?? error.localizedDescription
        }
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
