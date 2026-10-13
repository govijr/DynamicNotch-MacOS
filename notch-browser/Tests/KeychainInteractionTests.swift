import Foundation
import Security

// Tests only the interaction policy in this process; no user Keychain items
// are read, changed, or deleted. Compile with BrowserKeychainAccess.swift.
@main
struct KeychainInteractionTests {
    private enum FixtureError: Error { case expected }

    static func main() throws {
        let original = try interactionAllowed()
        defer { SecKeychainSetUserInteractionAllowed(original) }
        SecKeychainSetUserInteractionAllowed(true)

        try BrowserKeychainAccess.perform(allowInteraction: false) {
            try expect(try !interactionAllowed(), "Automatic operations cannot open a permission dialog")
        }
        try expect(try interactionAllowed(), "The original policy is restored after success")

        do {
            try BrowserKeychainAccess.perform(allowInteraction: false) { throw FixtureError.expected }
        } catch FixtureError.expected {}
        try expect(try interactionAllowed(), "The original policy is restored after failure")

        SecKeychainSetUserInteractionAllowed(false)
        try BrowserKeychainAccess.perform(allowInteraction: true) {
            try expect(try !interactionAllowed(), "An explicit operation respects a caller that disabled interaction")
        }
        try expect(try !interactionAllowed(), "A disabled policy remains disabled afterward")
        SecKeychainSetUserInteractionAllowed(true)

        let group = DispatchGroup()
        let failures = FailureCount()
        for index in 0..<40 {
            DispatchQueue.global().async(group: group) {
                let allowed = index.isMultiple(of: 2)
                do {
                    try BrowserKeychainAccess.perform(allowInteraction: allowed) {
                        Thread.sleep(forTimeInterval: 0.001)
                        if try interactionAllowed() != allowed { failures.record() }
                    }
                } catch { failures.record() }
            }
        }
        group.wait()
        try expect(failures.value == 0, "Concurrent background and explicit operations keep their own policy")
        try expect(try interactionAllowed(), "Concurrent operations restore the process policy")
        print("7 Keychain interaction checks passed")
    }

    private static func interactionAllowed() throws -> Bool {
        var allowed = DarwinBoolean(false)
        let status = SecKeychainGetUserInteractionAllowed(&allowed)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return allowed.boolValue
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw NSError(domain: "KeychainInteractionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private final class FailureCount: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        func record() { lock.lock(); defer { lock.unlock() }; count += 1 }
    }
}
