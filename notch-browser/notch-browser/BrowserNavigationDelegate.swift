import AppKit
import WebKit

@MainActor
final class BrowserNavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private weak var browserModel: BrowserModel?
    private var downloadWebViews: [ObjectIdentifier: WKWebView] = [:]
    init(browser: BrowserModel) {
        browserModel = browser
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        let browser = browserModel
        browser?.didStartLoading()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        let url = webView.url
        let browser = browserModel
        browser?.didCommitNavigation(url: url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        let browser = browserModel
        browser?.didFinishLoading(webView: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        let browser = browserModel
        browser?.didFailLoading(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        let browser = browserModel
        browser?.didFailLoading(error)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        return browserModel?.onCreateWebView?(configuration, navigationAction.request.url)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        prepare(download, from: webView)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        prepare(download, from: webView)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        presentJavaScriptDialog(in: webView, title: frame.request.url?.host ?? "Website", message: message) { _ in
            completionHandler()
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        presentJavaScriptDialog(in: webView, title: frame.request.url?.host ?? "Website", message: message) {
            completionHandler($0)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Website"
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        guard let window = webView.window else {
            completionHandler(nil)
            return
        }
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard let window = webView.window else {
            completionHandler(nil)
            return
        }
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let finish: (URL?) -> Void = { [weak self] destination in
            self?.downloadWebViews.removeValue(forKey: ObjectIdentifier(download))
            completionHandler(destination)
        }

        if let window = downloadWebViews[ObjectIdentifier(download)]?.window {
            panel.beginSheetModal(for: window) { response in
                finish(response == .OK ? panel.url : nil)
            }
        } else if panel.runModal() == .OK {
            finish(panel.url)
        } else {
            finish(nil)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadWebViews.removeValue(forKey: ObjectIdentifier(download))
    }

    func downloadDidFinish(_ download: WKDownload) {
        downloadWebViews.removeValue(forKey: ObjectIdentifier(download))
    }

    private func prepare(_ download: WKDownload, from webView: WKWebView) {
        downloadWebViews[ObjectIdentifier(download)] = webView
        download.delegate = self
    }

    private func presentJavaScriptDialog(in webView: WKWebView, title: String,
                                         message: String, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard let window = webView.window else {
            completion(false)
            return
        }
        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }

}
