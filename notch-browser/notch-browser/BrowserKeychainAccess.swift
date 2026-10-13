import Foundation
import Security

/// Serializes our Keychain calls because the legacy macOS interaction setting
/// is process-wide. Query-level authentication options do not suppress legacy
/// login-Keychain access dialogs (see Security.framework's SecItem.h).
enum BrowserKeychainAccess {
    private nonisolated static let queue = DispatchQueue(label: "com.govi.notch-browser.keychain")

    nonisolated static func perform<T>(allowInteraction: Bool, _ operation: () throws -> T) throws -> T {
        try queue.sync {
            var previouslyAllowed = DarwinBoolean(true)
            let readStatus = SecKeychainGetUserInteractionAllowed(&previouslyAllowed)
            guard readStatus == errSecSuccess else { throw AccessError(status: readStatus) }
            // Respect interaction disabled by our caller or the environment.
            let setStatus = SecKeychainSetUserInteractionAllowed(allowInteraction && previouslyAllowed.boolValue)
            guard setStatus == errSecSuccess else { throw AccessError(status: setStatus) }
            defer { SecKeychainSetUserInteractionAllowed(previouslyAllowed.boolValue) }
            return try operation()
        }
    }

    private struct AccessError: Error {
        let status: OSStatus
    }
}
