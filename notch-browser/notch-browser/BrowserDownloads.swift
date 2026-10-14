import AppKit
import Combine
import UniformTypeIdentifiers
import WebKit

enum BrowserDownloadFiles {
    static func filename(_ suggestion: String, mimeType: String? = nil) -> String {
        let leaf = (suggestion.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        var name = leaf.components(separatedBy: .controlCharacters).joined()
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "download" }
        if (name as NSString).pathExtension.isEmpty,
           let mimeType, let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension {
            name += "." + ext
        }
        let ext = (name as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : "." + String(ext.prefix(20))
        var stem = (name as NSString).deletingPathExtension
        while (stem + suffix).utf8.count > 240 { stem.removeLast() }
        return stem + suffix
    }

    /// Moving into place keeps incomplete transfers out of the destination and
    /// never replaces an existing file, including another simultaneous download.
    static func commit(_ source: URL, to directory: URL, filename: String) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = self.filename(filename)
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for index in 0..<10_000 {
            let candidate = index == 0 ? name : stem + " (\(index))" + (ext.isEmpty ? "" : "." + ext)
            let destination = directory.appendingPathComponent(candidate)
            do {
                try manager.moveItem(at: source, to: destination)
                return destination
            } catch {
                guard manager.fileExists(atPath: destination.path) else { throw error }
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

struct BrowserDownload: Identifiable {
    enum State { case downloading, finished, failed, cancelled }
    let id = UUID()
    var filename: String
    var state: State = .downloading
    var fractionCompleted: Double = 0
    var receivedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var destination: URL?
    var error: String?
}

/// App-owned downloads outlive the originating tab and compact presentation.
@MainActor
final class BrowserDownloads: NSObject, ObservableObject, WKDownloadDelegate {
    static let shared = BrowserDownloads()
    @Published private(set) var items: [BrowserDownload] = []
    var activeCount: Int { items.filter { $0.state == .downloading }.count }

    private let directory: URL
    private var active: [ObjectIdentifier: Transfer] = [:]

    private final class Transfer {
        let id: UUID
        let download: WKDownload
        let webView: WKWebView
        let promisedDestination: URL?
        let completion: ((Error?) -> Void)?
        var observation: NSKeyValueObservation?
        var stagingDirectory: URL?
        var stagedFile: URL?

        init(id: UUID, download: WKDownload, webView: WKWebView,
             destination: URL?, completion: ((Error?) -> Void)?) {
            self.id = id
            self.download = download
            self.webView = webView
            promisedDestination = destination
            self.completion = completion
        }
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        super.init()
    }

    func receive(_ download: WKDownload, from webView: WKWebView,
                 destination: URL? = nil, filename: String? = nil,
                 completion: ((Error?) -> Void)? = nil) {
        let item = BrowserDownload(filename: filename ?? download.originalRequest?.url?.lastPathComponent ?? "download")
        items.insert(item, at: 0)
        let transfer = Transfer(id: item.id, download: download, webView: webView,
                                destination: destination, completion: completion)
        active[ObjectIdentifier(download)] = transfer
        transfer.observation = download.progress.observe(\.fractionCompleted, options: [.initial, .new]) {
            [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            let received = progress.completedUnitCount
            let total = progress.totalUnitCount
            Task { @MainActor [weak self] in
                self?.update(item.id) {
                    guard $0.state == .downloading else { return }
                    $0.fractionCompleted = fraction
                    $0.receivedBytes = received
                    $0.totalBytes = total
                }
            }
        }
        download.delegate = self
    }

    func export(_ asset: URL, using webView: WKWebView, to destination: URL,
                completion: @escaping (Error?) -> Void) {
        // WebKit retains the page's cookies and understands blob/data URLs.
        webView.startDownload(using: URLRequest(url: asset)) { [self] download in
            receive(download, from: webView, destination: destination,
                    filename: destination.lastPathComponent, completion: completion)
        }
    }

    func start(_ asset: URL, using webView: WKWebView) {
        webView.startDownload(using: URLRequest(url: asset)) { [self] download in
            receive(download, from: webView)
        }
    }

    func reportFailure(filename: String, message: String) {
        var item = BrowserDownload(filename: filename)
        item.state = .failed
        item.error = message
        items.insert(item, at: 0)
    }

    static func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        action.shouldPerformDownload ? .download : .allow
    }

    static func policy(for response: WKNavigationResponse) -> WKNavigationResponsePolicy {
        let disposition = (response.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?
            .split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !response.canShowMIMEType || disposition == "attachment" ? .download : .allow
    }

    func cancel(_ id: UUID) {
        guard let transfer = active.values.first(where: { $0.id == id }) else { return }
        update(id) { $0.state = .cancelled }
        active.removeValue(forKey: ObjectIdentifier(transfer.download))
        transfer.observation = nil
        transfer.download.cancel { [self] _ in
            cleanUp(transfer)
            transfer.completion?(CocoaError(.userCancelled))
        }
    }

    func clearFinished() {
        items.removeAll { $0.state != .downloading }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let transfer = active[ObjectIdentifier(download)] else {
            completionHandler(nil)
            return
        }
        do {
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw NSError(domain: "BrowserDownloads", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "The server returned HTTP \(http.statusCode)."])
            }
            let name = transfer.promisedDestination?.lastPathComponent
                ?? BrowserDownloadFiles.filename(suggestedFilename, mimeType: response.mimeType)
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("notch-transfer-" + transfer.id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            transfer.stagingDirectory = staging
            transfer.stagedFile = staging.appendingPathComponent(name)
            update(transfer.id) { $0.filename = name }
            completionHandler(transfer.stagedFile)
        } catch {
            finish(transfer, error: error)
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let transfer = active[ObjectIdentifier(download)], let staged = transfer.stagedFile else { return }
        do {
            let destination: URL
            if let promised = transfer.promisedDestination {
                try FileManager.default.moveItem(at: staged, to: promised)
                destination = promised
            } else {
                destination = try BrowserDownloadFiles.commit(staged, to: directory, filename: staged.lastPathComponent)
            }
            update(transfer.id) {
                $0.destination = destination
                $0.filename = destination.lastPathComponent
                $0.fractionCompleted = 1
            }
            finish(transfer, error: nil)
        } catch {
            finish(transfer, error: error)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let transfer = active[ObjectIdentifier(download)] else { return }
        finish(transfer, error: error)
    }

    private func finish(_ transfer: Transfer, error: Error?) {
        active.removeValue(forKey: ObjectIdentifier(transfer.download))
        transfer.observation = nil
        update(transfer.id) {
            $0.state = error == nil ? .finished : .failed
            $0.error = error?.localizedDescription
        }
        cleanUp(transfer)
        transfer.completion?(error)
    }

    private func cleanUp(_ transfer: Transfer) {
        if let staging = transfer.stagingDirectory { try? FileManager.default.removeItem(at: staging) }
    }

    private func update(_ id: UUID, _ change: (inout BrowserDownload) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }
}
