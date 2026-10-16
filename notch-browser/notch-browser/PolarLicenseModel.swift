import Combine
import CryptoKit
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

    init(organizationID: String, benefitID: String, checkoutURL: URL) {
        self.organizationID = organizationID
        self.benefitID = benefitID
        self.checkoutURL = checkoutURL
    }

    var isConfigured: Bool {
        UUID(uuidString: organizationID) != nil
            && UUID(uuidString: benefitID) != nil
            && checkoutURL != nil
    }
}

struct LicenseCredentialStore: Sendable {
    let load: @Sendable () -> String?
    let save: @Sendable (String) throws -> Void
    let remove: @Sendable (String) -> Void
    static let keychain = LicenseCredentialStore(load: { LicenseKeychain.load() },
                                                save: { try LicenseKeychain.save($0) },
                                                remove: { LicenseKeychain.remove(expectedKey: $0) })
}

private actor LicenseCredentialWorker {
    private let store: LicenseCredentialStore
    private var generation = 0
    init(store: LicenseCredentialStore) { self.store = store }
    func load() -> String? { store.load() }
    func save(_ key: String, generation: Int) throws {
        guard generation >= self.generation else { throw CancellationError() }
        self.generation = generation
        try store.save(key)
    }
    func remove(_ key: String, generation: Int) {
        guard generation >= self.generation else { return }
        self.generation = generation
        store.remove(key)
    }
}

@MainActor
final class PolarLicenseModel: ObservableObject {
    static let shared = PolarLicenseModel()

    @Published private(set) var isUnlocked = false
    @Published private(set) var isValidating = false
    @Published private(set) var isRevalidating = false
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false

    let configuration: PolarLicenseConfiguration

    private let defaults: UserDefaults
    private let gracePeriod: TimeInterval = 72 * 60 * 60
    private let lastValidatedKey = "notchBrowser.license.lastValidatedAt"
    private let lastValidatedFingerprintKey = "notchBrowser.license.lastValidatedFingerprint"
    private let credentials: LicenseCredentialWorker
    private let session: URLSession
    private let now: @Sendable () -> Date
    private var validationGeneration = 0
    private var backgroundValidation: Task<Void, Never>?
    private var graceExpirationTask: Task<Void, Never>?
    private var cachedAccessKey: String?
    var onAccessRevoked: (() -> Void)?

    init(configuration: PolarLicenseConfiguration? = nil,
         defaults: UserDefaults = .standard, credentials: LicenseCredentialStore = .keychain,
         session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration ?? PolarLicenseConfiguration()
        self.defaults = defaults
        self.credentials = LicenseCredentialWorker(store: credentials)
        self.session = session
        self.now = now
    }

    func restoreAndValidate() async {
        let generation = beginValidation()
        isValidating = true
        guard configuration.isConfigured else {
            isUnlocked = false
            message = "Polar setup is incomplete for this build."
            messageIsError = true
            isValidating = false
            return
        }

        let savedKey = await credentials.load()
        guard generation == validationGeneration else { return }
        guard let savedKey else {
            isUnlocked = false
            isValidating = false
            cachedAccessKey = nil
            graceExpirationTask?.cancel()
            message = nil
            messageIsError = false
            return
        }
        if isRecentlyValidated(savedKey) {
            cachedAccessKey = savedKey
            isUnlocked = true
            isValidating = false
            isRevalidating = true
            message = "Your recent license check is valid. Checking in the background…"
            messageIsError = false
            scheduleGraceExpiration(for: savedKey, generation: generation)
            backgroundValidation = Task { @MainActor [weak self] in
                _ = await self?.validate(savedKey, saveAfterSuccess: false, allowOfflineGrace: true,
                                         generation: generation, background: true)
            }
        } else {
            _ = await validate(savedKey, saveAfterSuccess: false, allowOfflineGrace: true, generation: generation)
        }
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
        return await validate(key, saveAfterSuccess: true, allowOfflineGrace: false, generation: beginValidation())
    }

    private func beginValidation() -> Int {
        validationGeneration += 1
        backgroundValidation?.cancel()
        backgroundValidation = nil
        graceExpirationTask?.cancel()
        graceExpirationTask = nil
        isRevalidating = false
        if let cachedAccessKey, isRecentlyValidated(cachedAccessKey) {
            scheduleGraceExpiration(for: cachedAccessKey, generation: validationGeneration)
        }
        return validationGeneration
    }

    private func isRecentlyValidated(_ key: String) -> Bool {
        let lastSuccess = defaults.double(forKey: lastValidatedKey)
        let age = now().timeIntervalSince1970 - lastSuccess
        let savedFingerprint = defaults.string(forKey: lastValidatedFingerprintKey)
        // Existing installations have a timestamp but no fingerprint yet.
        return lastSuccess > 0 && age >= 0 && age <= gracePeriod
            && (savedFingerprint == nil || savedFingerprint == fingerprint(key))
    }

    private func fingerprint(_ key: String) -> String {
        let identity = configuration.organizationID + ":" + configuration.benefitID + ":" + key
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func scheduleGraceExpiration(for key: String, generation: Int) {
        let age = now().timeIntervalSince1970 - defaults.double(forKey: lastValidatedKey)
        let remaining = max(0, gracePeriod - age)
        graceExpirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled, let self, self.isUnlocked, self.validationGeneration == generation,
                  !self.isRecentlyValidated(key) else { return }
            self.isUnlocked = false
            self.cachedAccessKey = nil
            self.message = "Your offline license check has expired. Connect to the internet and try again."
            self.messageIsError = true
            self.onAccessRevoked?()
        }
    }

    private func validate(_ key: String, saveAfterSuccess: Bool, allowOfflineGrace: Bool,
                          generation: Int, background: Bool = false) async -> Bool {
        guard generation == validationGeneration, !Task.isCancelled else { return false }
        isValidating = !background
        isRevalidating = background
        if !background { message = "Checking your license…" }
        messageIsError = false
        defer {
            if generation == validationGeneration {
                isValidating = false
                isRevalidating = false
            }
        }

        do {
            try await validateWithPolar(key)
            guard generation == validationGeneration, !Task.isCancelled else { return false }
            if saveAfterSuccess {
                do {
                    try await credentials.save(key, generation: generation)
                    guard generation == validationGeneration else { return false }
                } catch {
                    guard generation == validationGeneration, !Task.isCancelled else { return false }
                    message = "License is valid, but it could not be saved to Keychain. Try again."
                    messageIsError = true
                    return false
                }
            }
            graceExpirationTask?.cancel()
            cachedAccessKey = nil
            defaults.set(now().timeIntervalSince1970, forKey: lastValidatedKey)
            defaults.set(fingerprint(key), forKey: lastValidatedFingerprintKey)
            isUnlocked = true
            message = "License verified. You’re all set."
            messageIsError = false
            return true
        } catch PolarValidationError.invalidKey {
            guard generation == validationGeneration, !Task.isCancelled else { return false }
            if !saveAfterSuccess {
                let wasUnlocked = isUnlocked
                isUnlocked = false
                cachedAccessKey = nil
                graceExpirationTask?.cancel()
                defaults.removeObject(forKey: lastValidatedKey)
                defaults.removeObject(forKey: lastValidatedFingerprintKey)
                if wasUnlocked { onAccessRevoked?() }
                await credentials.remove(key, generation: generation)
                guard generation == validationGeneration else { return false }
            }
            message = "That key isn’t active for Notch Browser. Check the key and try again."
            messageIsError = true
            return false
        } catch PolarValidationError.wrongBenefit {
            guard generation == validationGeneration, !Task.isCancelled else { return false }
            if !saveAfterSuccess {
                let wasUnlocked = isUnlocked
                isUnlocked = false
                cachedAccessKey = nil
                graceExpirationTask?.cancel()
                defaults.removeObject(forKey: lastValidatedKey)
                defaults.removeObject(forKey: lastValidatedFingerprintKey)
                if wasUnlocked { onAccessRevoked?() }
                await credentials.remove(key, generation: generation)
                guard generation == validationGeneration else { return false }
            }
            message = "This key is for a different product. Use the Notch Browser key from your Polar purchases."
            messageIsError = true
            return false
        } catch {
            guard generation == validationGeneration, !Task.isCancelled else { return false }
            if allowOfflineGrace, isRecentlyValidated(key) {
                cachedAccessKey = key
                scheduleGraceExpiration(for: key, generation: generation)
                isUnlocked = true
                message = "We couldn’t reach Polar. Your recent license check remains valid until its offline grace expires."
                messageIsError = false
                return true
            } else {
                if !saveAfterSuccess {
                    let wasUnlocked = isUnlocked
                    isUnlocked = false
                    cachedAccessKey = nil
                    graceExpirationTask?.cancel()
                    if wasUnlocked { onAccessRevoked?() }
                }
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

        let (data, response) = try await session.data(for: request)
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
        try? BrowserKeychainAccess.perform(allowInteraction: false) { loadValue() }
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

    static func remove(expectedKey: String) {
        try? BrowserKeychainAccess.perform(allowInteraction: false) {
            if loadValue() == expectedKey { removeValue() }
        }
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
