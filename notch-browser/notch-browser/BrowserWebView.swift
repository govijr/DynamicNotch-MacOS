import SwiftUI
import WebKit

/// Presentation reuses the model's web view. Navigation and delegates survive
/// tab switches and compact mode, and are also available to the local CLI.
struct BrowserWebView: NSViewRepresentable {
    @ObservedObject var browser: BrowserModel

    func makeNSView(context: Context) -> WKWebView {
        browser.ensureWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        browser.updateNavigationState(from: webView)
    }
}
