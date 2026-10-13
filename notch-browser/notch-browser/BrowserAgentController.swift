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
                "error": ["code": "result_too_large", "message": "The result exceeded 1 MB. Reduce snapshot limits or return a smaller value from eval."]])) ?? Data()
        }
        return encoded
    }

    private func execute(_ command: String, args: [String], request: [String: Any], session: String) async throws -> [String: Any] {
        if command == "status" {
            return ["app": "Notch Browser", "protocolVersion": 1, "engine": "WebKit", "unlocked": isUnlocked(),
                    "paused": activity.isPaused, "busy": inFlight != nil,
                    "activeSession": activity.session as Any? ?? NSNull(),
                    "capabilities": ["tabs", "snapshot", "text", "click", "fill", "select", "check", "uncheck", "press", "scroll", "wait", "screenshot", "eval", "local-html", "presentation"]]
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
        if command == "wait" { return try await wait(args, browser: browser, timeout: timeout, generation: generation) }
        guard !browser.isEmpty else { throw BrowserAgentError(code: "empty_tab", message: "Navigate this tab to a page first.") }
        try await waitForReady(browser, timeout: timeout, generation: generation)
        try activity.check(generation)
        var values: [String: Any] = [:]
        switch command {
        case "snapshot":
            guard args.isEmpty else { throw usage("snapshot") }
            values = ["snapshotId": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), "limit": request["limit"] as? Int ?? 250, "maxChars": request["maxChars"] as? Int ?? 12000]
        case "text":
            guard args.isEmpty else { throw usage("text") }
            values = ["maxChars": request["maxChars"] as? Int ?? 16000]
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
            let result = try await BrowserAgentDOM.evaluate("return await (" + args[0] + ");", arguments: [:], in: webView, world: .page, timeout: timeout)
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
        var result = try await BrowserAgentDOM.run(command, arguments: values, in: webView)
        try activity.check(generation)
        result["tabId"] = browser.id.uuidString
        result["session"] = session
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
            guard tabs.tabs.contains(where: { $0.id == browser.id }) else { throw BrowserAgentError(code: "tab_gone", message: "The tab closed during the command.") }
            if let error = browser.errorMessage { throw BrowserAgentError(code: "navigation_failed", message: error) }
            if !browser.isLoading && !webView.isLoading {
                let state = try await BrowserAgentDOM.run("ready", arguments: ["documentEpoch": browser.documentEpoch.uuidString], in: webView)
                if state["ready"] as? Bool == true { return }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        throw BrowserAgentError(code: "timeout", message: "The page did not become ready within \(timeout) ms. The tab remains open; inspect it or wait again.")
    }

    private func wait(_ args: [String], browser: BrowserModel, timeout: Int, generation: Int) async throws -> [String: Any] {
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
                let result = try await BrowserAgentDOM.run("exists", arguments: ["selector": args[1], "documentEpoch": browser.documentEpoch.uuidString], in: webView)
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
