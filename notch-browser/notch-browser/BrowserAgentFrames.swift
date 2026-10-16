import Foundation
import WebKit

/// Only the isolated agent content world can register frames. The shared router
/// also works when WebKit reuses a content controller for a popup configuration.
@MainActor
final class BrowserAgentFrames: NSObject, WKScriptMessageHandler {
    static let shared = BrowserAgentFrames()
    static let handlerName = "notchAgentFrames"
    private let registries = NSMapTable<WKWebView, BrowserAgentFrameRegistry>.weakToWeakObjects()

    func attach(_ registry: BrowserAgentFrameRegistry, to webView: WKWebView) {
        registries.setObject(registry, forKey: webView)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView, let registry = registries.object(forKey: webView),
              let body = message.body as? [String: String], let documentID = body["documentId"], documentID.count <= 128 else { return }
        registry.receive(body, frame: message.frameInfo)
    }
}

@MainActor
final class BrowserAgentFrameRegistry {
    struct Target {
        let frame: WKFrameInfo?
        let documentID: String?
    }
    private struct Entry {
        let frame: WKFrameInfo
        let documentID: String
        var title: String
        var url: String
        let order: Int
    }
    private var entries: [String: Entry] = [:]
    private var mainDocumentID: String?
    private var sequence = 0

    func reset() { entries.removeAll(); mainDocumentID = nil }

    fileprivate func receive(_ body: [String: String], frame: WKFrameInfo) {
        guard let documentID = body["documentId"] else { return }
        let id = frame.isMainFrame ? "main" : "f" + documentID
        if body["event"] == "remove" {
            if entries[id]?.documentID == documentID { entries.removeValue(forKey: id) }
            return
        }
        if frame.isMainFrame {
            if let mainDocumentID, mainDocumentID != documentID { entries.removeAll() }
            mainDocumentID = documentID
        }
        guard entries[id] != nil || entries.count < 64 else { return }
        sequence += 1
        entries[id] = Entry(frame: frame, documentID: documentID, title: String((body["title"] ?? "").prefix(2000)),
                            url: String((body["url"] ?? "").prefix(8192)), order: entries[id]?.order ?? sequence)
    }

    func target(_ id: String?) throws -> Target {
        guard let id, id != "main" else { return Target(frame: nil, documentID: nil) }
        guard let entry = entries[id], !entry.frame.isMainFrame else {
            throw BrowserAgentError(code: "frame_gone", message: "That frame is no longer registered. Run frames again and use a current ID.")
        }
        return Target(frame: entry.frame, documentID: entry.documentID)
    }

    func list(in webView: WKWebView, epoch: UUID, timeout: Int) async throws -> [[String: Any]] {
        let main = try await BrowserAgentDOM.run("identify", arguments: ["documentEpoch": epoch.uuidString], in: webView)
        var result: [[String: Any]] = [["id": "main", "title": main["title"] ?? "", "url": main["url"] ?? "", "main": true]]
        let deadline = Date().addingTimeInterval(Double(timeout) / 1000)
        for (id, entry) in entries.sorted(by: { $0.value.order < $1.value.order }) where !entry.frame.isMainFrame {
            guard Date() < deadline else { break }
            do {
                let identity = try await BrowserAgentDOM.run("identify", arguments: ["documentEpoch": epoch.uuidString,
                    "frameDocumentId": entry.documentID], in: webView, frame: entry.frame,
                    timeout: max(100, min(1000, Int(deadline.timeIntervalSinceNow * 1000))))
                result.append(["id": id, "title": identity["title"] ?? entry.title, "url": identity["url"] ?? entry.url,
                               "main": false, "origin": entry.frame.securityOrigin.host])
            } catch let error as BrowserAgentError where error.code == "frame_gone" {
                entries.removeValue(forKey: id)
            } catch {
                result.append(["id": id, "title": entry.title, "url": entry.url, "main": false, "unavailable": true])
            }
        }
        return result
    }
}
