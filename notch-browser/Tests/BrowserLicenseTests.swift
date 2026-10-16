import AppKit
import Foundation

@main
struct BrowserLicenseTests {
    @MainActor private static var checks = 0
    private static let organization = "00000000-0000-0000-0000-000000000001"
    private static let benefit = "00000000-0000-0000-0000-000000000002"

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await run()
                print("\(checks) isolated license checks passed")
                exit(0)
            } catch {
                print("FAIL: \(error.localizedDescription)")
                exit(1)
            }
        }
        app.run()
    }

    @MainActor private static func run() async throws {
        let suite = "NotchBrowser.LicenseTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = PolarLicenseConfiguration(organizationID: organization, benefitID: benefit,
                                               checkoutURL: URL(string: "https://example.invalid/checkout")!)
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [FixtureLicenseProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        let stamp = "notchBrowser.license.lastValidatedAt"
        let fingerprint = "notchBrowser.license.lastValidatedFingerprint"
        let memory = MemoryLicenseCredentials(key: "cached-fixture-key")
        memory.loadDelay = 0.10
        defaults.set(Date().addingTimeInterval(-3600).timeIntervalSince1970, forKey: stamp)
        FixtureLicenseProtocol.configure(["cached-fixture-key": response(delay: 0.3)])
        let license = PolarLicenseModel(configuration: config, defaults: defaults, credentials: memory.store, session: session)
        var uiTicked = false
        let tick = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000)
            uiTicked = true
        }
        await license.restoreAndValidate()
        await tick.value
        try expect(uiTicked && memory.allReadsOffMain, "Credential restoration leaves the UI actor responsive")
        try expect(license.isUnlocked && license.isRevalidating && !license.isValidating,
                   "A recent cached license unlocks before the delayed network reply")
        try await wait("background success") { !license.isRevalidating }
        try expect(defaults.string(forKey: fingerprint) != nil, "Successful validation binds the cache to its key and product")

        FixtureLicenseProtocol.configure(["cached-fixture-key": response(status: 503, delay: 0.1)])
        await license.restoreAndValidate()
        try await wait("offline grace") { !license.isRevalidating }
        try expect(license.isUnlocked, "Network failure retains a recent verified license")
        defaults.set(Date().addingTimeInterval(-73 * 3600).timeIntervalSince1970, forKey: stamp)
        await license.restoreAndValidate()
        try expect(!license.isUnlocked, "An expired offline cache cannot unlock")
        defaults.set(Date().addingTimeInterval(3600).timeIntervalSince1970, forKey: stamp)
        await license.restoreAndValidate()
        try expect(!license.isUnlocked, "A future validation timestamp cannot unlock")

        defaults.set(Date().addingTimeInterval(-3600).timeIntervalSince1970, forKey: stamp)
        defaults.removeObject(forKey: fingerprint)
        FixtureLicenseProtocol.configure(["cached-fixture-key": response(status: 404, delay: 0.1)])
        var revocations = 0
        license.onAccessRevoked = { revocations += 1 }
        await license.restoreAndValidate()
        try expect(license.isUnlocked, "Legacy timestamp-only caches keep the existing grace policy")
        try await wait("background revocation") { !license.isRevalidating }
        try expect(!license.isUnlocked && memory.key == nil && revocations == 1,
                   "A confirmed invalid background result revokes access and removes the matching key")

        memory.key = "wrong-product-fixture"
        defaults.set(Date().timeIntervalSince1970, forKey: stamp)
        FixtureLicenseProtocol.configure(["wrong-product-fixture": response(benefit: "00000000-0000-0000-0000-000000000003", delay: 0.1)])
        await license.restoreAndValidate()
        try await wait("wrong-product rejection") { !license.isRevalidating }
        try expect(!license.isUnlocked && memory.key == nil, "A wrong-product response cannot retain cached access")

        FixtureLicenseProtocol.configure(["fresh-fixture-key": response()])
        try expect(await license.activate("fresh-fixture-key") && memory.key == "fresh-fixture-key" && memory.allWritesOffMain,
                   "Activation saves a valid key off the UI thread")
        memory.key = "different-fixture-key"
        FixtureLicenseProtocol.configure(["different-fixture-key": response(status: 503)])
        await license.restoreAndValidate()
        try expect(!license.isUnlocked, "A cache fingerprint for another key cannot grant offline access")

        memory.key = "old-fixture-key"
        defaults.removeObject(forKey: fingerprint)
        defaults.set(Date().timeIntervalSince1970, forKey: stamp)
        FixtureLicenseProtocol.configure(["old-fixture-key": response(status: 404, delay: 0.4), "new-fixture-key": response(delay: 0.05)])
        await license.restoreAndValidate()
        try expect(await license.activate("new-fixture-key"), "A new activation can replace an outstanding background check")
        try await Task.sleep(nanoseconds: 500_000_000)
        try expect(license.isUnlocked && memory.key == "new-fixture-key", "An older check cannot revoke or overwrite a newly activated key")

        memory.key = "near-expiry-fixture"
        defaults.removeObject(forKey: fingerprint)
        defaults.set(Date().addingTimeInterval(-72 * 3600 + 0.4).timeIntervalSince1970, forKey: stamp)
        FixtureLicenseProtocol.configure(["near-expiry-fixture": response(status: 503, delay: 1), "bad-entry-fixture": response(status: 404)])
        await license.restoreAndValidate()
        try expect(license.isUnlocked, "A near-expiry cached license uses only its remaining grace")
        try expect(!(await license.activate("bad-entry-fixture")), "Invalid manual activation does not replace the stored entitlement")
        try await wait("strict grace expiration") { !license.isUnlocked }
        try expect(!license.isUnlocked, "Trying another key cannot extend the original offline grace")
    }

    private static func response(status: Int = 200, benefit: String = benefit, delay: TimeInterval = 0) -> FixtureLicenseResponse {
        FixtureLicenseResponse(status: status, data: try! JSONSerialization.data(withJSONObject: [
            "organization_id": organization, "benefit_id": benefit, "status": "granted"
        ]), delay: delay)
    }
    @MainActor private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw NSError(domain: "BrowserLicenseTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        checks += 1
    }
    @MainActor private static func wait(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { throw NSError(domain: "BrowserLicenseTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out: " + message]) }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private struct FixtureLicenseResponse: Sendable { let status: Int; let data: Data; let delay: TimeInterval }
private final class FixtureLicenseProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var responses: [String: FixtureLicenseResponse] = [:]
    private var work: DispatchWorkItem?
    static func configure(_ responses: [String: FixtureLicenseResponse]) { lock.withLock { self.responses = responses } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                body.append(contentsOf: bytes.prefix(count))
            }
        }
        let key = (try? JSONSerialization.jsonObject(with: body) as? [String: String])?["key"] ?? ""
        let reply = Self.lock.withLock { Self.responses[key] }
            ?? FixtureLicenseResponse(status: 503, data: Data(), delay: 0)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        self.work = work
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: work)
    }
    override func stopLoading() { work?.cancel() }
}

private final class MemoryLicenseCredentials: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private var offMainReads = true
    private var offMainWrites = true
    var loadDelay: TimeInterval = 0
    init(key: String?) { value = key }
    var key: String? { get { lock.withLock { value } } set { lock.withLock { value = newValue } } }
    var allReadsOffMain: Bool { lock.withLock { offMainReads } }
    var allWritesOffMain: Bool { lock.withLock { offMainWrites } }
    var store: LicenseCredentialStore {
        LicenseCredentialStore(load: {
            if self.loadDelay > 0 { Thread.sleep(forTimeInterval: self.loadDelay) }
            return self.lock.withLock { self.offMainReads = self.offMainReads && !Thread.isMainThread; return self.value }
        }, save: { key in
            self.lock.withLock { self.offMainWrites = self.offMainWrites && !Thread.isMainThread; self.value = key }
        }, remove: { key in self.lock.withLock { if self.value == key { self.value = nil } } })
    }
}
