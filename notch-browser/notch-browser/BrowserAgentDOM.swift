import Foundation
import WebKit

struct BrowserAgentError: Error {
    let code: String
    let message: String
}

@MainActor
enum BrowserAgentDOM {
    static let world = WKContentWorld.world(name: "NotchBrowserAgent")
    private static let source = Bundle.main.url(forResource: "BrowserAgentBridge", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    static func install(in configuration: WKWebViewConfiguration) {
        guard let source else { return }
        configuration.userContentController.removeScriptMessageHandler(forName: BrowserAgentFrames.handlerName, contentWorld: world)
        configuration.userContentController.add(BrowserAgentFrames.shared, contentWorld: world, name: BrowserAgentFrames.handlerName)
        guard !configuration.userContentController.userScripts.contains(where: { $0.source == source && !$0.isForMainFrameOnly }) else { return }
        configuration.userContentController.addUserScript(WKUserScript(
            source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world
        ))
    }

    static func run(_ command: String, arguments: [String: Any] = [:], in webView: WKWebView,
                    frame: WKFrameInfo? = nil, timeout: Int = 10000,
                    interruption: (() -> BrowserAgentError?)? = nil) async throws -> [String: Any] {
        guard let source else {
            throw BrowserAgentError(code: "bridge_unavailable", message: "The app is missing its agent bridge resource. Rebuild Notch Browser.")
        }
        let result = try await evaluate(
            source + "\nreturn globalThis.__notchAgent.run(command, args);",
            arguments: ["command": command, "args": arguments], in: webView, world: world,
            frame: frame, timeout: timeout, interruption: interruption
        )
        guard let envelope = result as? [String: Any] else {
            throw BrowserAgentError(code: "invalid_page_result", message: "The page returned an invalid action result.")
        }
        if envelope["ok"] as? Bool != true {
            let error = envelope["error"] as? [String: String] ?? [:]
            throw BrowserAgentError(code: error["code"] ?? "page_action_failed", message: error["message"] ?? "The page action failed.")
        }
        return envelope["data"] as? [String: Any] ?? [:]
    }

    /// Cancelling Swift's async overlay cannot interrupt a page's JavaScript.
    /// Bound the native wait so a blocked script cannot hold the CLI forever.
    static func evaluate(_ script: String, arguments: [String: Any], in webView: WKWebView,
                         world: WKContentWorld, frame: WKFrameInfo? = nil, timeout: Int = 10000,
                         interruption: (() -> BrowserAgentError?)? = nil) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            var completed = false
            let timer = Task { @MainActor in
                let deadline = Date().addingTimeInterval(Double(timeout) / 1000)
                repeat {
                    try? await Task.sleep(nanoseconds: 25_000_000)
                    guard !Task.isCancelled, !completed else { return }
                    if let error = interruption?() {
                        completed = true
                        continuation.resume(throwing: error)
                        return
                    }
                } while Date() < deadline
                completed = true
                continuation.resume(throwing: BrowserAgentError(code: "javascript_timeout", message: "The page's JavaScript did not respond. Close the tab if it remains unresponsive."))
            }
            webView.callAsyncJavaScript(script, arguments: arguments, in: frame, in: world) { result in
                guard !completed else { return }
                completed = true
                timer.cancel()
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error):
                    if frame != nil, (error as NSError).domain == WKErrorDomain,
                       (error as NSError).code == WKError.Code.javaScriptInvalidFrameTarget.rawValue {
                        continuation.resume(throwing: BrowserAgentError(code: "frame_gone", message: "The frame navigated or was removed. Run frames again."))
                    } else { continuation.resume(throwing: error) }
                }
            }
        }
    }
}
