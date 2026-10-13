import CommonCrypto
import Foundation
import Security
import SQLite3
import WebKit

struct BrowserCookieRecord: Codable, Equatable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresAt: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool

    nonisolated init(
        name: String,
        value: String,
        domain: String,
        path: String,
        expiresAt: Date?,
        isSecure: Bool,
        isHTTPOnly: Bool
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresAt = expiresAt
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }

    nonisolated init?(cookie: HTTPCookie) {
        guard !cookie.name.isEmpty,
              !cookie.domain.isEmpty,
              !cookie.path.isEmpty
        else { return nil }

        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expiresAt = cookie.expiresDate
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .version: 0
        ]

        if let expiresAt {
            properties[.expires] = expiresAt
        }

        if isSecure {
            properties[.secure] = "TRUE"
        }

        if isHTTPOnly {
            properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
        }

        return HTTPCookie(properties: properties)
    }

    var storageKey: String {
        "\(domain)|\(path)|\(name)"
    }
}

struct BrowserChromeProfile: Equatable, Identifiable, Sendable {
    let id: String
    let browserName: String
    let profileName: String
    let cookieDatabaseURL: URL

    var displayName: String {
        "\(browserName) · \(profileName)"
    }
}

struct BrowserCookieImportResult: Sendable {
    let importedCount: Int
    let skippedCount: Int
}

enum BrowserSessionError: LocalizedError {
    case chromeCookieDatabase
    case sqlite(String)
    case chromeSafeStorage(OSStatus)
    case encryptedCookie
    case noImportableCookies
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .chromeCookieDatabase:
            "Chrome's profile could not be read automatically. Close Chrome completely, then try again."
        case let .sqlite(message):
            "Chrome cookies could not be read: \(message)"
        case .chromeSafeStorage:
            "macOS did not allow access to Chrome Safe Storage. Open Chrome once, then try importing again."
        case .encryptedCookie:
            "Chrome uses an encryption format this app could not read."
        case .noImportableCookies:
            "No usable cookies were found in that Chrome profile."
        case .keychain:
            "The saved browser session could not be accessed from the macOS Keychain."
        }
    }
}

@MainActor
final class BrowserSessionStore {
    let websiteDataStore: WKWebsiteDataStore

    init(websiteDataStore: WKWebsiteDataStore) {
        self.websiteDataStore = websiteDataStore
    }

    static func discoverChromeProfiles() -> [BrowserChromeProfile] {
        ChromeCookieImporter.discoverProfiles()
    }

    func restoreSavedCookies() async throws -> Int {
        // WebKit's persistent store remains available when a legacy backup
        // cannot be read silently. Startup must never wait on a password dialog.
        let savedData = try await Task.detached(priority: .utility) {
            try BrowserKeychainAccess.perform(allowInteraction: false) {
                try BrowserSessionKeychain.load()
            }
        }.value
        guard let data = savedData else { return 0 }
        let records = try JSONDecoder().decode([BrowserCookieRecord].self, from: data)
        guard !records.isEmpty else { return 0 }

        let existingKeys = Set(await allCookies().compactMap(BrowserCookieRecord.init).map(\.storageKey))
        let recordsToRestore = records.filter { !existingKeys.contains($0.storageKey) }
        return await setCookies(recordsToRestore)
    }

    func saveCookies(allowInteraction: Bool = false) async throws -> Int {
        let records = await allCookies().compactMap(BrowserCookieRecord.init)
        let data = try JSONEncoder().encode(records)
        try await Task.detached(priority: .utility) {
            try BrowserKeychainAccess.perform(allowInteraction: allowInteraction) {
                try BrowserSessionKeychain.save(data)
            }
        }.value
        return records.count
    }

    func importChromeCookies(from url: URL) async throws -> BrowserCookieImportResult {
        let result = try await Task.detached(priority: .userInitiated) {
            try ChromeCookieImporter.read(from: url)
        }.value

        let importedCount = await setCookies(result.records)
        return BrowserCookieImportResult(
            importedCount: importedCount,
            skippedCount: result.skippedCount
        )
    }

    func forgetSavedCookies() {
        try? BrowserKeychainAccess.perform(allowInteraction: true) {
            BrowserSessionKeychain.remove()
        }
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func setCookies(_ records: [BrowserCookieRecord]) async -> Int {
        var importedCount = 0

        for record in records {
            guard let cookie = record.cookie else { continue }

            await withCheckedContinuation { continuation in
                websiteDataStore.httpCookieStore.setCookie(cookie) {
                    continuation.resume()
                }
            }
            importedCount += 1
        }

        return importedCount
    }
}

private enum BrowserSessionKeychain {
    private nonisolated static let account = "cookie-snapshot"

    private nonisolated static var service: String {
        "\(Bundle.main.bundleIdentifier ?? "com.govi.app.notch-browser").session"
    }

    nonisolated static func load() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw BrowserSessionError.keychain(status) }
        return result as? Data
    }

    nonisolated static func save(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw BrowserSessionError.keychain(updateStatus)
        }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw BrowserSessionError.keychain(addStatus)
        }

        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw BrowserSessionError.keychain(retryStatus)
            }
        }
    }

    nonisolated static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct ChromeCookieImporter {
    private nonisolated static let chromeEpochOffset: TimeInterval = 11_644_473_600

    nonisolated static func discoverProfiles() -> [BrowserChromeProfile] {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let roots = [
            ("Google Chrome", applicationSupport.appendingPathComponent("Google/Chrome", isDirectory: true)),
            ("Google Chrome Beta", applicationSupport.appendingPathComponent("Google/Chrome Beta", isDirectory: true)),
            ("Google Chrome Dev", applicationSupport.appendingPathComponent("Google/Chrome Dev", isDirectory: true)),
            ("Google Chrome Canary", applicationSupport.appendingPathComponent("Google/Chrome Canary", isDirectory: true))
        ]

        return roots.flatMap { browserName, rootURL in
            profileDirectories(in: rootURL).compactMap { profileURL in
                let cookieURL = profileURL.appendingPathComponent("Cookies")
                guard FileManager.default.isReadableFile(atPath: cookieURL.path) else { return nil }

                let profileKey = profileURL.lastPathComponent
                let profileName = profileDisplayName(
                    rootURL: rootURL,
                    profileKey: profileKey
                ) ?? (profileKey == "Default" ? "Default" : profileKey)

                return BrowserChromeProfile(
                    id: "\(browserName):\(profileKey)",
                    browserName: browserName,
                    profileName: profileName,
                    cookieDatabaseURL: cookieURL
                )
            }
        }
    }

    nonisolated static func read(from sourceURL: URL) throws -> (records: [BrowserCookieRecord], skippedCount: Int) {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-browser-chrome-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
        } catch {
            throw BrowserSessionError.chromeCookieDatabase
        }

        var database: OpaquePointer?
        let openStatus = sqlite3_open_v2(
            temporaryURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard openStatus == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown database error"
            if let database { sqlite3_close(database) }
            throw BrowserSessionError.sqlite(message)
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT host_key, name, path, expires_utc, is_secure, is_httponly, value, encrypted_value
        FROM cookies
        """

        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard prepareStatus == SQLITE_OK, let statement else {
            throw BrowserSessionError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        let databaseVersion = readDatabaseVersion(database)

        var chromeKey: Data?
        var keyError: Error?
        var records: [BrowserCookieRecord] = []
        var skippedCount = 0
        let now = Date()

        while sqlite3_step(statement) == SQLITE_ROW {
            let domain = text(from: statement, column: 0)
            let name = text(from: statement, column: 1)
            let path = text(from: statement, column: 2)
            let expiresUTC = sqlite3_column_int64(statement, 3)
            let isSecure = sqlite3_column_int(statement, 4) != 0
            let isHTTPOnly = sqlite3_column_int(statement, 5) != 0
            let plainValue = text(from: statement, column: 6)
            let encryptedValue = data(from: statement, column: 7)

            let expiresAt: Date?
            if expiresUTC > 0 {
                expiresAt = Date(
                    timeIntervalSince1970: Double(expiresUTC) / 1_000_000 - chromeEpochOffset
                )
                if let expiresAt, expiresAt <= now { continue }
            } else {
                expiresAt = nil
            }

            let value: String
            if !plainValue.isEmpty {
                value = plainValue
            } else if encryptedValue.count > 3 {
                do {
                    if chromeKey == nil {
                        chromeKey = try BrowserKeychainAccess.perform(allowInteraction: true) {
                            try loadChromeKey()
                        }
                    }
                    guard let chromeKey else {
                        skippedCount += 1
                        continue
                    }
                    value = try decrypt(
                        encryptedValue,
                        with: chromeKey,
                        domain: domain,
                        hasDomainHash: databaseVersion >= 24
                    )
                } catch {
                    keyError = keyError ?? error
                    skippedCount += 1
                    continue
                }
            } else {
                if !encryptedValue.isEmpty { skippedCount += 1 }
                continue
            }

            guard !domain.isEmpty, !name.isEmpty, !path.isEmpty else {
                skippedCount += 1
                continue
            }
            records.append(
                BrowserCookieRecord(
                    name: name,
                    value: value,
                    domain: domain,
                    path: path,
                    expiresAt: expiresAt,
                    isSecure: isSecure,
                    isHTTPOnly: isHTTPOnly
                )
            )
        }

        if records.isEmpty, let keyError {
            throw keyError
        }
        guard !records.isEmpty else { throw BrowserSessionError.noImportableCookies }
        return (records, skippedCount)
    }

    private nonisolated static func readDatabaseVersion(_ database: OpaquePointer) -> Int {
        var statement: OpaquePointer?
        let query = "SELECT value FROM meta WHERE key = 'version' LIMIT 1"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(text(from: statement, column: 0)) ?? 0
    }

    private nonisolated static func profileDirectories(in rootURL: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { url in
                let name = url.lastPathComponent
                return name == "Default" || name.hasPrefix("Profile ")
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private nonisolated static func profileDisplayName(
        rootURL: URL,
        profileKey: String
    ) -> String? {
        let localStateURL = rootURL.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localStateURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any],
              let info = infoCache[profileKey] as? [String: Any]
        else { return nil }

        return (info["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (info["gaia_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (info["user_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func text(from statement: OpaquePointer?, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private nonisolated static func data(from statement: OpaquePointer?, column: Int32) -> Data {
        let length = Int(sqlite3_column_bytes(statement, column))
        guard length > 0, let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: length)
    }

    private nonisolated static func loadChromeKey() throws -> Data {
        let queries: [[String: Any]] = [
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "Chrome Safe Storage",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ],
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "Chrome Safe Storage",
                kSecAttrAccount as String: "Chrome",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
        ]

        var lastStatus: OSStatus = errSecItemNotFound
        for query in queries {
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data, !data.isEmpty {
                return data
            }
            lastStatus = status
        }

        throw BrowserSessionError.chromeSafeStorage(lastStatus)
    }

    private nonisolated static func decrypt(
        _ encryptedValue: Data,
        with password: Data,
        domain: String,
        hasDomainHash: Bool
    ) throws -> String {
        guard encryptedValue.count > 3,
              encryptedValue.prefix(3) == Data("v10".utf8)
                || encryptedValue.prefix(3) == Data("v11".utf8)
        else { throw BrowserSessionError.encryptedCookie }

        let salt = Data("saltysalt".utf8)
        var key = Data(repeating: 0, count: kCCKeySizeAES128)
        let keyLength = key.count
        let derivationStatus = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: CChar.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        guard derivationStatus == kCCSuccess else { throw BrowserSessionError.encryptedCookie }

        let ciphertext = Data(encryptedValue.dropFirst(3))
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var decrypted = Data(repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        let decryptedCapacity = decrypted.count
        var decryptedLength = 0

        let decryptStatus = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                ciphertext.withUnsafeBytes { ciphertextBytes in
                    decrypted.withUnsafeMutableBytes { decryptedBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            ciphertextBytes.baseAddress,
                            ciphertext.count,
                            decryptedBytes.baseAddress,
                            decryptedCapacity,
                            &decryptedLength
                        )
                    }
                }
            }
        }
        guard decryptStatus == CCCryptorStatus(kCCSuccess) else {
            throw BrowserSessionError.encryptedCookie
        }

        decrypted.removeSubrange(decryptedLength..<decrypted.count)

        let hash = domainHash(domain)
        let hasHashPrefix = decrypted.starts(with: hash)
        if hasDomainHash {
            guard hasHashPrefix else { throw BrowserSessionError.encryptedCookie }
            decrypted.removeFirst(hash.count)
        } else if hasHashPrefix {
            decrypted.removeFirst(hash.count)
        }

        guard let value = String(data: decrypted, encoding: .utf8) else {
            throw BrowserSessionError.encryptedCookie
        }
        return value
    }

    private nonisolated static func domainHash(_ domain: String) -> Data {
        let bytes = Array(domain.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        bytes.withUnsafeBytes { input in
            digest.withUnsafeMutableBufferPointer { output in
                _ = CC_SHA256(input.baseAddress, CC_LONG(bytes.count), output.baseAddress)
            }
        }
        return Data(digest)
    }
}
