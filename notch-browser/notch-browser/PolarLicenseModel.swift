import Combine
import Foundation
import Security

struct PolarLicenseConfiguration {
    let organizationID: String
    let benefitID: String
    let checkoutURL: URL?

    init(bundle: Bundle = .main) {
        organizationID = bundle.object(forInfoDictionaryKey: "NotchBrowserPolarOrganizationID") as? String ?? ""
        benefitID = bundle.object(forInfoDictionaryKey: "NotchBrowserPolarBenefitID") as? String ?? ""
        let checkoutString = bundle.object(forInfoDictionaryKey: "NotchBrowserPolarCheckoutURL") as? String ?? ""
        checkoutURL = URL(string: checkoutString).flatMap {
            $0.scheme?.lowercased() == "https" ? $0 : nil
        }
    }

    var isConfigured: Bool {
        UUID(uuidString: organizationID) != nil
            && UUID(uuidString: benefitID) != nil
            && checkoutURL != nil
    }
}

@MainActor
final class PolarLicenseModel: ObservableObject {
    static let shared = PolarLicenseModel()

    @Published private(set) var isUnlocked = false
    @Published private(set) var isValidating = false
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false

    let configuration: PolarLicenseConfiguration

    private let defaults: UserDefaults
    private let gracePeriod: TimeInterval = 72 * 60 * 60
    private let lastValidatedKey = "notchBrowser.license.lastValidatedAt"

    init(configuration: PolarLicenseConfiguration? = nil,
         defaults: UserDefaults = .standard) {
        self.configuration = configuration ?? PolarLicenseConfiguration()
        self.defaults = defaults
    }

    func restoreAndValidate() async {
        guard configuration.isConfigured else {
            isUnlocked = false
            message = "Polar setup is incomplete for this build."
            messageIsError = true
            return
        }

        guard let savedKey = LicenseKeychain.load() else {
            isUnlocked = false
            return
        }
        _ = await validate(savedKey, saveAfterSuccess: false, allowOfflineGrace: true)
    }

    func activate(_ enteredKey: String) async -> Bool {
        let key = enteredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            message = "Enter the license key from your Polar purchase."
            messageIsError = true
            return false
        }
        guard configuration.isConfigured else {
            message = "Polar setup is incomplete for this build."
            messageIsError = true
            return false
        }
        return await validate(key, saveAfterSuccess: true, allowOfflineGrace: false)
    }

    private func validate(_ key: String, saveAfterSuccess: Bool, allowOfflineGrace: Bool) async -> Bool {
        isValidating = true
        message = "Checking your license…"
        messageIsError = false
        defer { isValidating = false }

        do {
            try await validateWithPolar(key)
            if saveAfterSuccess {
                do {
                    try LicenseKeychain.save(key)
                } catch {
                    message = "License is valid, but it could not be saved to Keychain. Try again."
                    messageIsError = true
                    return false
                }
            }
            defaults.set(Date().timeIntervalSince1970, forKey: lastValidatedKey)
            isUnlocked = true
            message = "License verified. You’re all set."
            messageIsError = false
            return true
        } catch PolarValidationError.invalidKey {
            if !saveAfterSuccess {
                isUnlocked = false
                LicenseKeychain.remove()
                defaults.removeObject(forKey: lastValidatedKey)
            }
            message = "That key isn’t active for Notch Browser. Check the key and try again."
            messageIsError = true
            return false
        } catch PolarValidationError.wrongBenefit {
            if !saveAfterSuccess {
                isUnlocked = false
                LicenseKeychain.remove()
                defaults.removeObject(forKey: lastValidatedKey)
            }
            message = "This key is for a different product. Use the Notch Browser key from your Polar purchases."
            messageIsError = true
            return false
        } catch {
            let lastSuccess = defaults.double(forKey: lastValidatedKey)
            let age = Date().timeIntervalSince1970 - lastSuccess
            if allowOfflineGrace, lastSuccess > 0, age >= 0, age <= gracePeriod {
                isUnlocked = true
                message = "We couldn’t reach Polar. Your recent license check is still valid; reconnect within 72 hours."
                messageIsError = false
                return true
            } else {
                if !saveAfterSuccess { isUnlocked = false }
                message = "We couldn’t reach Polar. Connect to the internet and try again."
                messageIsError = true
                return false
            }
        }
    }

    private func validateWithPolar(_ key: String) async throws {
        struct Response: Decodable {
            let organizationId: String
            let benefitId: String
            let status: String
        }

        var request = URLRequest(
            url: URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/validate")!
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "key": key,
            "organization_id": configuration.organizationID,
            "benefit_id": configuration.benefitID
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PolarValidationError.serviceUnavailable
        }
        if httpResponse.statusCode == 404 {
            throw PolarValidationError.invalidKey
        }
        guard httpResponse.statusCode == 200 else {
            throw PolarValidationError.serviceUnavailable
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let keyResponse = try decoder.decode(Response.self, from: data)
        guard keyResponse.organizationId.lowercased() == configuration.organizationID.lowercased(),
              keyResponse.benefitId.lowercased() == configuration.benefitID.lowercased()
        else { throw PolarValidationError.wrongBenefit }
        guard keyResponse.status == "granted" else {
            throw PolarValidationError.invalidKey
        }
    }
}

private enum PolarValidationError: Error {
    case invalidKey
    case wrongBenefit
    case serviceUnavailable
}

private enum LicenseKeychain {
    private static let account = "polar-license-key"
    private static var service: String {
        "\(Bundle.main.bundleIdentifier ?? "com.govi.app.notch-browser").license"
    }

    static func load() -> String? {
        try? BrowserKeychainAccess.perform(allowInteraction: true) { loadValue() }
    }

    private static func loadValue() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) throws {
        try BrowserKeychainAccess.perform(allowInteraction: true) { try saveValue(key) }
    }

    private static func saveValue(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(key.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw LicenseKeychainError(status) }
        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw LicenseKeychainError(addStatus) }
    }

    static func remove() {
        try? BrowserKeychainAccess.perform(allowInteraction: true) { removeValue() }
    }

    private static func removeValue() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct LicenseKeychainError: Error {
    let status: OSStatus
    init(_ status: OSStatus) { self.status = status }
}
