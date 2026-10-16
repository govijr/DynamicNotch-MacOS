import AppKit
import WebKit
import UniformTypeIdentifiers

@MainActor
final class BrowserNavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    private weak var browserModel: BrowserModel?
    private let downloads: BrowserDownloads
    init(browser: BrowserModel, downloads: BrowserDownloads? = nil) {
        browserModel = browser
        self.downloads = downloads ?? .shared
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(BrowserDownloads.policy(for: navigationAction))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(BrowserDownloads.policy(for: navigationResponse))
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
        guard let browser = browserModel else { completionHandler(); return }
        browser.pageInteraction.add(kind: .alert, message: message, origin: BrowserPageInteraction.origin(frame)) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let browser = browserModel else { completionHandler(false); return }
        browser.pageInteraction.add(kind: .confirm, message: message, origin: BrowserPageInteraction.origin(frame)) { completionHandler($0.accepted) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard let browser = browserModel else { completionHandler(nil); return }
        browser.pageInteraction.add(kind: .prompt, message: prompt, origin: BrowserPageInteraction.origin(frame), defaultText: defaultText) {
            completionHandler($0.accepted ? $0.text : nil)
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        guard let browser = browserModel else { completionHandler(nil); return }
        var configurePanel: ((NSOpenPanel) -> Void)?
        if let file = browserModel?.lookupUploadFile, FileManager.default.fileExists(atPath: file.path),
           let url = frame.request.url, url.scheme == "https",
           (url.host == "www.google.com" && url.path == "/imghp" || url.host == "lens.google.com") {
            configurePanel = { panel in
                panel.directoryURL = file.deletingLastPathComponent()
                panel.allowedContentTypes = [.image]
                panel.message = "Choose Lookup.png to search the prepared image with Google Lens."
            }
        }
        browser.pageInteraction.handleFilePicker(parameters: parameters, frame: frame, configurePanel: configurePanel, completion: completionHandler)
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard let browser = browserModel else { decisionHandler(.deny); return }
        let resource: String
        switch type {
        case .camera: resource = "camera"
        case .microphone: resource = "microphone"
        case .cameraAndMicrophone: resource = "camera and microphone"
        @unknown default: decisionHandler(.deny); return
        }
        browser.pageInteraction.add(kind: .permission, message: "Allow this website to use your \(resource)?",
                                    origin: BrowserPageInteraction.origin(frame)) { decisionHandler($0.accepted ? .grant : .deny) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func prepare(_ download: WKDownload, from webView: WKWebView) {
        browserModel?.didBeginDownload()
        downloads.receive(download, from: webView)
    }

}
