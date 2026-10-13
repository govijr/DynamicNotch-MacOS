import Darwin
import Foundation

/// The same small wire layer is compiled into the app and standalone CLI.
/// The endpoint is a private Unix socket; no HTTP port or page-facing native
/// message handler is opened.
enum BrowserAgentSocket {
    nonisolated static let maxMessageBytes = 1_048_576

    nonisolated static var path: String {
        ProcessInfo.processInfo.environment["NOTCH_BROWSER_SOCKET"] ?? "/tmp/notch-browser-\(getuid())/control.sock"
    }

    nonisolated static func address(_ path: String) throws -> sockaddr_un {
        var value = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: value.sun_path) else {
            throw NSError(domain: "NotchBrowserSocket", code: 1, userInfo: [NSLocalizedDescriptionKey: "The control socket path is too long."])
        }
        value.sun_family = sa_family_t(AF_UNIX)
        value.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &value.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return value
    }

    nonisolated static func connect(_ path: String) throws -> Int32 {
        var address = try self.address(path)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw systemError() }
        configure(fd)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { Darwin.close(fd); throw systemError() }
        return fd
    }

    nonisolated static func configure(_ fd: Int32, timeout: Int = 35) {
        // macOS can inherit O_NONBLOCK from the listening socket on accept.
        // Client I/O runs off the main thread and uses bounded blocking reads.
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) }
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        var interval = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout.size(ofValue: interval)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &interval, socklen_t(MemoryLayout.size(ofValue: interval)))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    nonisolated static func readMessage(_ fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while data.count <= maxMessageBytes {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw systemError()
            }
            guard count > 0 else { throw NSError(domain: "NotchBrowserSocket", code: 2, userInfo: [NSLocalizedDescriptionKey: "The app closed the connection before replying."]) }
            let chunk = buffer.prefix(count)
            if let newline = chunk.firstIndex(of: 10) {
                data.append(contentsOf: chunk.prefix(newline))
                guard data.count <= maxMessageBytes else { break }
                return data
            }
            data.append(contentsOf: chunk)
        }
        throw NSError(domain: "NotchBrowserSocket", code: 3, userInfo: [NSLocalizedDescriptionKey: "The control message exceeded 1 MB."])
    }

    nonisolated static func writeMessage(_ data: Data, to fd: Int32) throws {
        guard data.count <= maxMessageBytes else { throw NSError(domain: "NotchBrowserSocket", code: 3, userInfo: [NSLocalizedDescriptionKey: "The control message exceeded 1 MB."]) }
        var message = data
        message.append(10)
        try message.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw systemError()
                }
                guard count > 0 else { throw systemError() }
                offset += count
            }
        }
    }

    nonisolated static func systemError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
    }
}
