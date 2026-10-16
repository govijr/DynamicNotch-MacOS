import Foundation
import WebKit

@MainActor
enum BrowserLensHandoff {
    static let world = WKContentWorld.world(name: "NotchBrowserLookup")
    static let startURL = URL(string: "https://www.google.com/imghp?hl=en")!
    static func isUploadPage(_ url: URL?) -> Bool {
        url?.scheme == "https" && url?.host == "www.google.com" && url?.path == "/imghp"
    }
    static func isResultsPage(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https" else { return false }
        if url.host == "lens.google.com" { return url.path == "/search" }
        return url.host == "www.google.com" && url.path == "/search"
    }

    static func cancel(in webView: WKWebView?) {
        webView?.callAsyncJavaScript("globalThis.__notchLensUploadID = null;", arguments: [:], in: nil, in: world) { _ in }
    }

    static func submit(_ image: BrowserLookupImage, in webView: WKWebView, requestID: UUID) async throws -> String {
        guard isUploadPage(webView.url) else { return "wrong_page" }
        let result = try await BrowserAgentDOM.evaluate(uploadScript, arguments: [
            "encoded": image.data.base64EncodedString(), "filename": image.fileURL.lastPathComponent,
            "expectedOrigin": "https://www.google.com", "expectedPath": "/imghp", "requestID": requestID.uuidString
        ], in: webView, world: world)
        return (result as? [String: Any])?["status"] as? String ?? "unavailable"
    }

    /// Uses the website's public upload input, with an origin check in the
    /// same script as the handoff. No private Google endpoint or browser API.
    static let uploadScript = #"""
    globalThis.__notchLensUploadID = requestID;
    const correctPage = () => location.origin === expectedOrigin && location.pathname === expectedPath
      && globalThis.__notchLensUploadID === requestID;
    if (!correctPage()) return {status:'wrong_page'};
    let input = document.querySelector('input[type="file"][name="encoded_image"]');
    if (!input) {
      const camera = document.querySelector('[aria-label="Search by image"]');
      if (!camera) return {status:'unavailable'};
      camera.click();
      for (let attempt = 0; attempt < 50 && !input; attempt++) {
        await new Promise(resolve => setTimeout(resolve, 100));
        if (!correctPage()) return {status:'wrong_page'};
        input = document.querySelector('input[type="file"][name="encoded_image"]');
      }
    }
    if (!input || !correctPage()) return {status:'unavailable'};
    const binary = atob(encoded), bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    const transfer = new DataTransfer();
    transfer.items.add(new File([bytes], filename, {type:'image/png'}));
    input.files = transfer.files;
    input.dispatchEvent(new Event('change', {bubbles:true}));
    return {status:'submitted'};
    """#
}
