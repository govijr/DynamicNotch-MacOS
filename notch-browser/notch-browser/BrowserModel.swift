import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class BrowserModel: ObservableObject {
    let id = UUID()
    static var desktopSafariUserAgent: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X \(version.majorVersion)_\(version.minorVersion)_\(version.patchVersion)) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(version.majorVersion).\(version.minorVersion) Safari/605.1.15"
    }

    @Published var addressText: String
    @Published private(set) var pageTitle = "Ready when you are"
    @Published private(set) var currentURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastPageSnapshot: NSImage?
    @Published private(set) var isEmpty: Bool

    private(set) var requestedURL: URL?
    private(set) var navigationRequestID = UUID()
    private(set) var documentEpoch = UUID()
    // Keep the WebKit view alive while the compact surface is shown. The
    // expanded SwiftUI hierarchy is intentionally removed in compact mode,
    // but the browsing session must continue to own its page, history, scroll
    // position, and in-page form state.
    private(set) var webView: WKWebView?
    private var navigationDelegate: BrowserNavigationDelegate?
    private var pendingNavigation: Task<Void, Never>?
    private var submittedRequestID: UUID?

    private let library: BrowserLibrary
    var onSessionChange: (() -> Void)?
    var onCreateWebView: ((WKWebViewConfiguration, URL?) -> WKWebView)?

    var websiteDataStore: WKWebsiteDataStore {
        library.websiteDataStore
    }

    init(library: BrowserLibrary? = nil, startsEmpty: Bool = false, initialURL: URL? = nil) {
        let library = library ?? BrowserLibrary.shared
        self.library = library

        let startURL = startsEmpty ? nil : (initialURL ?? library.lastVisitedURL ?? library.searchEngine.homepageURL)
        isEmpty = startsEmpty
        addressText = startURL?.absoluteString ?? ""
        requestedURL = startURL
    }

    @discardableResult
    func ensureWebView(configuration suppliedConfiguration: WKWebViewConfiguration? = nil) -> WKWebView {
        if let webView { return webView }
        let configuration = suppliedConfiguration ?? WKWebViewConfiguration()
        if suppliedConfiguration == nil { configuration.websiteDataStore = websiteDataStore }
        BrowserAgentDOM.install(in: configuration)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 720), configuration: configuration)
        webView.customUserAgent = Self.desktopSafariUserAgent
        let delegate = BrowserNavigationDelegate(browser: self)
        navigationDelegate = delegate
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = .black
        self.webView = webView
        // WebKit starts popup navigation itself, using the supplied configuration.
        if suppliedConfiguration == nil { loadRequestedPage() }
        return webView
    }

    private func loadRequestedPage() {
        guard let webView, let requestedURL, submittedRequestID != navigationRequestID else { return }
        submittedRequestID = navigationRequestID
        let requestID = navigationRequestID
        pendingNavigation?.cancel()
        pendingNavigation = Task { @MainActor [weak self, weak webView] in
            guard let self else { return }
            await restoreSessionIfNeeded()
            guard !Task.isCancelled, self.navigationRequestID == requestID, let webView else { return }
            self.didStartLoading()
            if requestedURL.isFileURL {
                webView.loadFileURL(requestedURL, allowingReadAccessTo: requestedURL.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: requestedURL))
            }
        }
    }

    func close() {
        stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
    }

    func stopLoading() {
        pendingNavigation?.cancel()
        webView?.stopLoading()
        isLoading = false
    }

    func captureVisiblePage() {
        guard let webView, webView.bounds.width > 0, webView.bounds.height > 0 else { return }
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let image else { return }
            Task { @MainActor [weak self] in
                self?.lastPageSnapshot = image
            }
        }
    }

    func restoreSessionIfNeeded() async {
        await library.restoreSessionIfNeeded()
    }

    func scheduleSessionSave() {
        library.scheduleSessionSave()
    }

    func saveSessionAndWait() async {
        await library.saveSessionAndWait(updateStatus: false)
    }

    func submitAddress() {
        let input = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        if let explicitURL = URL(string: input),
           let scheme = explicitURL.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           explicitURL.host != nil {
            navigate(to: explicitURL)
            return
        }

        if !input.contains(" "),
           let directURL = URL(string: "https://\(input)"),
           directURL.host != nil {
            navigate(to: directURL)
            return
        }

        if let searchURL = library.searchEngine.searchURL(for: input) {
            navigate(to: searchURL)
        }
    }

    func navigate(to url: URL) {
        requestedURL = url
        addressText = url.absoluteString
        errorMessage = nil
        navigationRequestID = UUID()
        isEmpty = false
        isLoading = true
        ensureWebView()
        loadRequestedPage()
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        if isLoading {
            webView?.stopLoading()
        } else {
            webView?.reload()
        }
    }

    func didStartLoading() {
        documentEpoch = UUID()
        isLoading = true
        errorMessage = nil
    }

    func didCommitNavigation(url: URL?) {
        if let url {
            currentURL = url
            addressText = url.absoluteString
            requestedURL = url
            isEmpty = false
            library.recordLastVisitedURL(url)
            scheduleSessionSave()
            onSessionChange?()
        }
    }

    func didFinishLoading(webView: WKWebView) {
        isLoading = false
        currentURL = webView.url

        if let url = webView.url {
            addressText = url.absoluteString
            requestedURL = url
            library.recordLastVisitedURL(url)
        }

        if let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            pageTitle = title
        } else {
            pageTitle = webView.url?.host ?? "Ready when you are"
        }

        if let url = webView.url {
            library.recordVisit(url: url, title: pageTitle)
        }

        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        scheduleSessionSave()
        onSessionChange?()
    }

    func didFailLoading(_ error: Error) {
        isLoading = false
        if (error as NSError).code != NSURLErrorCancelled {
            errorMessage = error.localizedDescription
        }
    }

    func updateNavigationState(from webView: WKWebView) {
        let nextCanGoBack = webView.canGoBack
        let nextCanGoForward = webView.canGoForward

        if canGoBack != nextCanGoBack {
            canGoBack = nextCanGoBack
        }

        if canGoForward != nextCanGoForward {
            canGoForward = nextCanGoForward
        }
    }

}
