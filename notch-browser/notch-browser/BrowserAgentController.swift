import AppKit
import Foundation
import WebKit

@MainActor
final class BrowserAgentController {
    let activity: BrowserAgentActivity
    private let tabs: BrowserTabsModel
    private let isUnlocked: () -> Bool
    private let expand: () -> Void
    private let collapse: () -> Void
    private var bindings: [String: UUID] = [:]
    private var inFlight: UUID?
    private var inFlightTab: BrowserModel?

    init(tabs: BrowserTabsModel, activity: BrowserAgentActivity,
         isUnlocked: @escaping () -> Bool, expand: @escaping () -> Void, collapse: @escaping () -> Void) {
        self.tabs = tabs
        self.activity = activity
        self.isUnlocked = isUnlocked
        self.expand = expand
        self.collapse = collapse
        activity.onStop = { [weak self] in self?.inFlightTab?.stopLoading() }
    }

    func handle(_ data: Data) async -> Data {
        var requestID: Any = NSNull()
        var response: [String: Any]
        do {
            guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let command = request["command"] as? String,
                  let args = request["args"] as? [String] else {
                throw BrowserAgentError(code: "invalid_request", message: "Expected a JSON request with command and string args.")
            }
            requestID = request["id"] as? String ?? NSNull()
            guard request["protocolVersion"] as? Int == 1 else {
                throw BrowserAgentError(code: "protocol_mismatch", message: "This app supports agent protocol version 1.")
            }
            let session = request["session"] as? String ?? "default"
            guard !session.isEmpty, session.utf8.count <= 128 else {
                throw BrowserAgentError(code: "invalid_session", message: "Session names must contain 1–128 bytes.")
            }
            let result = try await execute(command, args: args, request: request, session: session)
            response = ["ok": true, "data": result]
        } catch let error as BrowserAgentError {
            response = ["ok": false, "error": ["code": error.code, "message": error.message]]
        } catch {
            response = ["ok": false, "error": ["code": "action_failed", "message": error.localizedDescription]]
        }
        response["id"] = requestID
        response["protocolVersion"] = 1
        let encoded = (try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])) ?? Data()
        if encoded.count > BrowserAgentSocket.maxMessageBytes {
            return (try? JSONSerialization.data(withJSONObject: ["id": requestID, "protocolVersion": 1, "ok": false,
                "error": ["code": "result_too_large", "message": "The result exceeded 1 MB. Reduce --limit or --max-chars, narrow extract to a selector, or return a smaller value from eval."]])) ?? Data()
        }
        return encoded
    }

    private func execute(_ command: String, args: [String], request: [String: Any], session: String) async throws -> [String: Any] {
        if command == "status" {
            return ["app": "Notch Browser", "protocolVersion": 1, "engine": "WebKit", "unlocked": isUnlocked(),
                    "paused": activity.isPaused, "busy": inFlight != nil,
                    "activeSession": activity.session as Any? ?? NSNull(),
                    "capabilities": ["tabs", "frames", "snapshot", "text", "extract", "media-frame", "upload", "dialogs", "blockers", "handoff", "click", "fill", "select", "check", "uncheck", "press", "scroll", "wait", "screenshot", "eval", "local-html", "presentation"]]
        }
        if command == "done" {
            guard inFlight == nil else { throw BrowserAgentError(code: "busy", message: "Wait for the running command to finish before calling done.") }
            activity.done(session: session)
            return ["done": true, "session": session]
        }
        guard isUnlocked() else {
            throw BrowserAgentError(code: "license_required", message: "Activate Notch Browser in the app before using agent commands.")
        }
        guard inFlight == nil else {
            throw BrowserAgentError(code: "busy", message: "Another command is running. Wait for it to finish and retry.")
        }
        let generation = try activity.begin(session: session)
        let operation = UUID()
        inFlight = operation
        defer {
            inFlight = nil
            inFlightTab = nil
            activity.finish()
        }
        let timeout = min(max(request["timeoutMs"] as? Int ?? 10000, 100), 30000)
        if command == "ls" { return ["tabs": tabs.tabs.map(describe), "session": session] }
        if command == "expand" { expand(); return ["expanded": true] }
        if command == "collapse" { collapse(); return ["expanded": false] }
        if command == "open" || command == "new-tab" {
            guard args.count == (command == "open" ? 1 : 0) || (command == "new-tab" && args.count == 1) else { throw usage("open <url-or-file> | new-tab [url-or-file]") }
            let url = try args.first.map(parseURL)
            let browser = tabs.newTab(select: request["follow"] as? Bool != false)
            bindings[session] = browser.id
            inFlightTab = browser
            if let url {
                browser.navigate(to: url)
                try await waitForReady(browser, timeout: timeout, generation: generation)
            }
            if request["follow"] as? Bool != false { expand() }
            return describe(browser)
        }
        if command == "tab" {
            guard args.count == 1, let id = UUID(uuidString: args[0]), let browser = tabs.tabs.first(where: { $0.id == id }) else { throw usage("tab <tab-id>") }
            bindings[session] = id
            tabs.selectTab(id)
            if request["follow"] as? Bool == true { expand() }
            return describe(browser)
        }
        let browser = try target(request: request, session: session)
        inFlightTab = browser
        if request["follow"] as? Bool == true { tabs.selectTab(browser.id); expand() }
        let frameID = request["frameId"] as? String
        if frameID != nil && frameID != "main", ["close", "navigate", "back", "forward", "reload", "screenshot", "frames", "dialogs", "dialog", "choose-files", "handoff"].contains(command) {
            throw BrowserAgentError(code: "unsupported_in_frame", message: "This command targets the whole tab. Omit --frame; use frame page actions for embedded content.")
        }
        if command == "close" {
            tabs.closeTab(browser.id)
            return ["closed": browser.id.uuidString]
        }
        if command == "navigate" {
            guard args.count == 1 else { throw usage("navigate <url-or-file>") }
            browser.navigate(to: try parseURL(args[0]))
            try await waitForReady(browser, timeout: timeout, generation: generation)
            return describe(browser)
        }
        if command == "dialogs" {
            guard args.isEmpty else { throw usage("dialogs") }
            return ["tabId": browser.id.uuidString, "dialogs": browser.pageInteraction.dialogs]
        }
        if command == "dialog" {
            guard (2...3).contains(args.count), ["accept", "dismiss"].contains(args[1]) else {
                throw usage("dialog <dialog-id> accept|dismiss [prompt-text]")
            }
            try browser.pageInteraction.respond(id: args[0], accept: args[1] == "accept", text: args.count == 3 ? args[2] : nil)
            return ["tabId": browser.id.uuidString, "dialogId": args[0], "answered": true]
        }
        if command == "choose-files" {
            guard args.count >= 2 else { throw usage("choose-files <dialog-id> <absolute-file>…") }
            let files = try browser.pageInteraction.chooseFiles(id: args[0], paths: Array(args.dropFirst()))
            return ["tabId": browser.id.uuidString, "dialogId": args[0], "files": files.map(\.lastPathComponent)]
        }
        if command == "handoff" {
            guard args.isEmpty else { throw usage("handoff") }
            tabs.selectTab(browser.id)
            expand()
            browser.pageInteraction.presentPending()
            activity.stop()
            return ["tabId": browser.id.uuidString, "paused": true, "requiresUser": true,
                    "dialogs": browser.pageInteraction.dialogs, "message": "Browser shown. Complete the manual step, then use Resume in the app."]
        }
        if command == "blockers" {
            guard args.isEmpty else { throw usage("blockers") }
            if browser.pageInteraction.hasPending {
                return ["tabId": browser.id.uuidString, "dialogs": browser.pageInteraction.dialogs,
                        "blockers": [], "limitations": ["Page script inspection waits until the native dialog is answered."]]
            }
            let target = try browser.agentFrames.target(frameID)
            var values: [String: Any] = ["documentEpoch": browser.documentEpoch.uuidString]
            if let id = target.documentID { values["frameDocumentId"] = id }
            var state = try await BrowserAgentDOM.run("challenge-state", arguments: values, in: browser.ensureWebView(), frame: target.frame)
            state["tabId"] = browser.id.uuidString
            state["frameId"] = frameID ?? "main"
            state["dialogs"] = browser.pageInteraction.dialogs
            state["limitations"] = ["Verification detection is best effort. macOS-owned permission dialogs require user interaction and are not enumerated by this command."]
            return state
        }
        let webView = browser.ensureWebView()
        if command == "back" || command == "forward" || command == "reload" {
            guard args.isEmpty else { throw usage("\(command)") }
            if command == "back" {
                guard webView.canGoBack else { throw BrowserAgentError(code: "no_history", message: "This tab has no previous page.") }
                browser.didStartLoading(); webView.goBack()
            } else if command == "forward" {
                guard webView.canGoForward else { throw BrowserAgentError(code: "no_history", message: "This tab has no next page.") }
                browser.didStartLoading(); webView.goForward()
            } else { browser.didStartLoading(); webView.reload() }
            try await waitForReady(browser, timeout: timeout, generation: generation)
            return describe(browser)
        }
        if command == "wait" { return try await wait(args, browser: browser, frameID: frameID, timeout: timeout, generation: generation) }
        guard !browser.isEmpty else { throw BrowserAgentError(code: "empty_tab", message: "Navigate this tab to a page first.") }
        try await waitForReady(browser, timeout: timeout, generation: generation)
        try activity.check(generation)
        if command == "frames" {
            guard args.isEmpty else { throw usage("frames") }
            let frames = try await browser.agentFrames.list(in: webView, epoch: browser.documentEpoch, timeout: timeout)
            try activity.check(generation)
            return ["tabId": browser.id.uuidString, "frames": frames]
        }
        let frameTarget = try browser.agentFrames.target(frameID)
        var values: [String: Any] = [:]
        switch command {
        case "snapshot":
            guard args.isEmpty else { throw usage("snapshot") }
            values = ["snapshotId": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), "limit": request["limit"] as? Int ?? 250, "maxChars": request["maxChars"] as? Int ?? 12000]
        case "text":
            guard args.isEmpty else { throw usage("text") }
            values = ["maxChars": request["maxChars"] as? Int ?? 16000]
        case "extract":
            guard args.count <= 1 else { throw usage("extract [css-selector]") }
            values = ["extractionId": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                      "limit": request["limit"] as? Int ?? 50, "maxChars": request["maxChars"] as? Int ?? 12000]
            if let selector = args.first { values["selector"] = selector }
        case "upload":
            guard args.count >= 2 else { throw usage("upload <file-input-ref> <absolute-file>…") }
            var values: [String: Any] = ["ref": args[0], "documentEpoch": browser.documentEpoch.uuidString]
            if let id = frameTarget.documentID { values["frameDocumentId"] = id }
            let info = try await BrowserAgentDOM.run("file-info", arguments: values, in: webView, frame: frameTarget.frame)
            guard let frameURL = info["url"] as? String else { throw BrowserAgentError(code: "frame_gone", message: "Take a fresh snapshot of the upload frame.") }
            let paths = Array(args.dropFirst())
            guard info["multiple"] as? Bool == true || paths.count == 1 else {
                throw BrowserAgentError(code: "invalid_argument", message: "This file input accepts only one file.")
            }
            try browser.pageInteraction.planUpload(paths: paths, frameURL: frameURL, mainFrame: frameTarget.frame?.isMainFrame ?? true)
            defer { browser.pageInteraction.cancelUpload() }
            _ = try await BrowserAgentDOM.run("upload-trigger", arguments: values, in: webView, frame: frameTarget.frame,
                                              interruption: { browser.pageInteraction.blockingError })
            let deadline = Date().addingTimeInterval(Double(min(timeout, 3000)) / 1000)
            while browser.pageInteraction.uploadResult == nil {
                try activity.check(generation)
                if let error = browser.pageInteraction.blockingError { throw error }
                guard Date() < deadline else {
                    throw BrowserAgentError(code: "file_picker_unavailable", message: "The site did not open its file picker. No files were supplied. Try its upload button, then dialogs and choose-files.")
                }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            let files = try browser.pageInteraction.uploadResult!.get()
            try activity.check(generation)
            return ["tabId": browser.id.uuidString, "frameId": frameID ?? "main", "files": files.map(\.lastPathComponent), "inputMode": "native-file-picker"]
        case "media-frame":
            guard args.count == 2, args[1].hasPrefix("/"), args[1].lowercased().hasSuffix(".png") else {
                throw usage("media-frame <media-ref> <absolute-output.png>")
            }
            let epoch = browser.documentEpoch
            var values: [String: Any] = ["ref": args[0], "documentEpoch": epoch.uuidString]
            if let documentID = frameTarget.documentID { values["frameDocumentId"] = documentID }
            var frame = try await BrowserAgentDOM.run("media-frame", arguments: values, in: webView, frame: frameTarget.frame)
            try activity.check(generation)
            guard epoch == browser.documentEpoch else {
                throw BrowserAgentError(code: "stale_ref", message: "The page navigated during capture. Run extract again.")
            }
            guard let encoded = frame.removeValue(forKey: "png") as? String, let png = Data(base64Encoded: encoded) else {
                throw BrowserAgentError(code: "frame_unavailable", message: "The video frame could not be encoded as PNG.")
            }
            do { try png.write(to: URL(fileURLWithPath: args[1]), options: .atomic) }
            catch { throw BrowserAgentError(code: "file_write_failed", message: "Could not save the video frame: \(error.localizedDescription)") }
            frame["path"] = args[1]
            frame["tabId"] = browser.id.uuidString
            frame["session"] = session
            return frame
        case "click", "check", "uncheck":
            guard args.count == 1 else { throw usage("\(command) <ref>") }
            values = ["ref": args[0]]
        case "fill", "select":
            guard args.count == 2 else { throw usage("\(command) <ref> <value>") }
            values = ["ref": args[0], "value": args[1]]
        case "press":
            guard args.count == 2 else { throw usage("press <ref> <key>") }
            values = ["ref": args[0], "key": args[1]]
        case "scroll":
            guard (1...3).contains(args.count) else { throw usage("scroll <direction> [pixels] [ref]") }
            let amount = args.count > 1 ? Int(args[1]) : 500
            guard let amount, amount > 0 else { throw usage("scroll <direction> [positive-pixels] [ref]") }
            values = ["direction": args[0], "amount": amount]
            if args.count > 2 { values["ref"] = args[2] }
        case "eval":
            guard args.count == 1 else { throw usage("eval <javascript-expression>") }
            var challengeArgs: [String: Any] = ["documentEpoch": browser.documentEpoch.uuidString]
            if let id = frameTarget.documentID { challengeArgs["frameDocumentId"] = id }
            let challenge = try await BrowserAgentDOM.run("challenge-state", arguments: challengeArgs, in: webView, frame: frameTarget.frame)
            guard challenge["challengeDocument"] as? Bool != true else {
                throw BrowserAgentError(code: "human_required", message: "Human-verification documents require the user. Run handoff.")
            }
            if let documentID = frameTarget.documentID {
                _ = try await BrowserAgentDOM.run("identify", arguments: ["frameDocumentId": documentID,
                    "documentEpoch": browser.documentEpoch.uuidString], in: webView, frame: frameTarget.frame)
            }
            let result = try await BrowserAgentDOM.evaluate("return await (" + args[0] + ");", arguments: [:], in: webView, world: .page, frame: frameTarget.frame, timeout: timeout,
                                                           interruption: { browser.pageInteraction.blockingError })
            try activity.check(generation)
            let resultObject: Any = result ?? NSNull()
            guard JSONSerialization.isValidJSONObject(["result": resultObject]) else {
                throw BrowserAgentError(code: "unserializable_result", message: "Return a JSON-compatible value from eval.")
            }
            return ["tabId": browser.id.uuidString, "result": resultObject]
        case "screenshot":
            guard args.count == 1 else { throw usage("screenshot <output.png>") }
            return try await screenshot(webView, browser: browser, path: args[0], generation: generation)
        default:
            throw BrowserAgentError(code: "unsupported_command", message: "Unknown command: \(command). Run notch-browser help.")
        }
        values["documentEpoch"] = browser.documentEpoch.uuidString
        if let documentID = frameTarget.documentID { values["frameDocumentId"] = documentID }
        var result = try await BrowserAgentDOM.run(command, arguments: values, in: webView, frame: frameTarget.frame,
                                                  interruption: { browser.pageInteraction.blockingError })
        try activity.check(generation)
        result["tabId"] = browser.id.uuidString
        result["session"] = session
        result["frameId"] = frameID ?? "main"
        return result
    }

    private func target(request: [String: Any], session: String) throws -> BrowserModel {
        if let supplied = request["tabId"] as? String {
            guard let id = UUID(uuidString: supplied), let browser = tabs.tabs.first(where: { $0.id == id }) else {
                throw BrowserAgentError(code: "tab_gone", message: "That tab does not exist. Run ls and select an existing tab.")
            }
            bindings[session] = id
            return browser
        }
        if let id = bindings[session] {
            guard let browser = tabs.tabs.first(where: { $0.id == id }) else {
                throw BrowserAgentError(code: "tab_gone", message: "Your session's tab was closed. Use --tab with an existing tab, or open a new one.")
            }
            return browser
        }
        let browser = tabs.activeBrowser
        bindings[session] = browser.id
        return browser
    }

    private func describe(_ browser: BrowserModel) -> [String: Any] {
        ["id": browser.id.uuidString, "title": browser.isEmpty ? "New Tab" : browser.pageTitle,
         "url": browser.currentURL?.absoluteString ?? browser.requestedURL?.absoluteString ?? "",
         "active": browser.id == tabs.activeTabID, "loading": browser.isLoading, "empty": browser.isEmpty,
         "error": browser.errorMessage as Any? ?? NSNull(),
         "canGoBack": browser.canGoBack, "canGoForward": browser.canGoForward]
    }

    private func parseURL(_ value: String) throws -> URL {
        if let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return url }
        if value.hasPrefix("file://"), let url = URL(string: value), url.isFileURL { return try localFile(url) }
        if value.hasPrefix("/") { return try localFile(URL(fileURLWithPath: value)) }
        throw BrowserAgentError(code: "invalid_url", message: "Use a full http/https URL or an absolute path to an HTML file.")
    }

    private func localFile(_ url: URL) throws -> URL {
        guard ["html", "htm"].contains(url.pathExtension.lowercased()), FileManager.default.isReadableFile(atPath: url.path) else {
            throw BrowserAgentError(code: "invalid_file", message: "Use a readable .html or .htm file.")
        }
        return url.standardizedFileURL
    }

    private func waitForReady(_ browser: BrowserModel, timeout: Int, generation: Int) async throws {
        let deadline = Date().addingTimeInterval(Double(timeout) / 1000)
        let webView = browser.ensureWebView()
        repeat {
            try activity.check(generation)
            if let error = browser.pageInteraction.blockingError { throw error }
            guard tabs.tabs.contains(where: { $0.id == browser.id }) else { throw BrowserAgentError(code: "tab_gone", message: "The tab closed during the command.") }
            if let error = browser.errorMessage { throw BrowserAgentError(code: "navigation_failed", message: error) }
            if !browser.isLoading && !webView.isLoading {
                let state = try await BrowserAgentDOM.run("ready", arguments: ["documentEpoch": browser.documentEpoch.uuidString], in: webView,
                                                           interruption: { browser.pageInteraction.blockingError })
                if state["ready"] as? Bool == true { return }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        throw BrowserAgentError(code: "timeout", message: "The page did not become ready within \(timeout) ms. The tab remains open; inspect it or wait again.")
    }

    private func wait(_ args: [String], browser: BrowserModel, frameID: String?, timeout: Int, generation: Int) async throws -> [String: Any] {
        if args == ["dialog"] {
            guard frameID == nil || frameID == "main" else {
                throw BrowserAgentError(code: "unsupported_in_frame", message: "Dialogs belong to the tab. Omit --frame when waiting for a dialog.")
            }
            let deadline = Date().addingTimeInterval(Double(timeout) / 1000)
            repeat {
                try activity.check(generation)
                guard tabs.tabs.contains(where: { $0.id == browser.id }) else { throw BrowserAgentError(code: "tab_gone", message: "The tab closed while waiting for a dialog.") }
                if browser.pageInteraction.hasPending { return ["tabId": browser.id.uuidString, "dialogs": browser.pageInteraction.dialogs] }
                try await Task.sleep(nanoseconds: 25_000_000)
            } while Date() < deadline
            throw BrowserAgentError(code: "timeout", message: "No dialog appeared within \(timeout) ms.")
        }
        let frameTarget = try browser.agentFrames.target(frameID)
        if frameTarget.frame != nil {
            guard args.isEmpty || args == ["ready"] || (args.count == 2 && ["selector", "url"].contains(args[0])) else {
                throw usage("wait [ready | selector <css> | url <substring>]")
            }
            let deadline = Date().addingTimeInterval(Double(timeout) / 1000)
            repeat {
                try activity.check(generation)
                if let error = browser.pageInteraction.blockingError { throw error }
                var values: [String: Any] = ["documentEpoch": browser.documentEpoch.uuidString, "frameDocumentId": frameTarget.documentID ?? ""]
                let selector = args.first == "selector"
                if selector { values["selector"] = args[1] }
                let state = try await BrowserAgentDOM.run(selector ? "exists" : "ready", arguments: values,
                                                         in: browser.ensureWebView(), frame: frameTarget.frame,
                                                         interruption: { browser.pageInteraction.blockingError })
                let matched = selector ? state["found"] as? Bool == true : args.first == "url"
                    ? (state["url"] as? String)?.contains(args[1]) == true : state["ready"] as? Bool == true
                if matched { return ["tabId": browser.id.uuidString, "frameId": frameID ?? "main", "matched": true] }
                try await Task.sleep(nanoseconds: 100_000_000)
            } while Date() < deadline
            throw BrowserAgentError(code: "timeout", message: "The frame wait condition did not match within \(timeout) ms.")
        }
        if args.isEmpty || args == ["ready"] {
            try await waitForReady(browser, timeout: timeout, generation: generation)
            return ["tabId": browser.id.uuidString, "ready": true]
        }
        guard args.count == 2, ["selector", "url"].contains(args[0]) else { throw usage("wait [ready | selector <css> | url <substring>]") }
        let deadline = Date().addingTimeInterval(Double(timeout) / 1000)
        let webView = browser.ensureWebView()
        repeat {
            try activity.check(generation)
            guard tabs.tabs.contains(where: { $0.id == browser.id }) else { throw BrowserAgentError(code: "tab_gone", message: "The tab closed while waiting.") }
            let matches: Bool
            if args[0] == "url" {
                matches = webView.url?.absoluteString.contains(args[1]) == true
            } else {
                let result = try await BrowserAgentDOM.run("exists", arguments: ["selector": args[1], "documentEpoch": browser.documentEpoch.uuidString], in: webView,
                                                            interruption: { browser.pageInteraction.blockingError })
                matches = result["found"] as? Bool == true
            }
            if matches { return ["tabId": browser.id.uuidString, "matched": true] }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        throw BrowserAgentError(code: "timeout", message: "The wait condition did not match within \(timeout) ms.")
    }

    private func screenshot(_ webView: WKWebView, browser: BrowserModel, path: String, generation: Int) async throws -> [String: Any] {
        guard path.hasPrefix("/"), path.lowercased().hasSuffix(".png") else { throw usage("screenshot <absolute-output.png>") }
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, error in
                if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? BrowserAgentError(code: "screenshot_failed", message: "WebKit could not capture the tab.")) }
            }
        }
        try activity.check(generation)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw BrowserAgentError(code: "screenshot_failed", message: "The tab could not be converted to a PNG.")
        }
        try png.write(to: URL(fileURLWithPath: path), options: .atomic)
        return ["tabId": browser.id.uuidString, "path": path, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh]
    }

    private func usage(_ message: String) -> BrowserAgentError {
        BrowserAgentError(code: "invalid_argument", message: "Usage: notch-browser action -- \(message)")
    }
}
