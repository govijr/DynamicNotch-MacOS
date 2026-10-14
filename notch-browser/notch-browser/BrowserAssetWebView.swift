import AppKit
import UniformTypeIdentifiers
import WebKit

/// WebKit handles image file promises and website upload zones natively.
/// Option-drag adds file promises for media and asset links without taking over
/// a site's ordinary dragging, text selection, or video controls.
@MainActor
final class BrowserAssetWebView: WKWebView {
    var downloads: BrowserDownloads = .shared
    var onPresentationChange: ((Bool) -> Void)?
    private var mouseDownPoint: NSPoint?
    private var lookupID = UUID()
    private var isLookingUpAsset = false
    private var dragAsset: BrowserDragAsset?
    private var assetDragSource: BrowserAssetDragSource?
    private var contextAssets: [String: String] = [:]

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        installContextCapture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installContextCapture()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onPresentationChange?(window != nil)
    }

    private func installContextCapture() {
        let controller = configuration.userContentController
        let world = BrowserAssetContextBridge.world
        controller.removeScriptMessageHandler(forName: "notchAssetContext", contentWorld: world)
        controller.add(BrowserAssetContextBridge.shared, contentWorld: world, name: "notchAssetContext")
        if !controller.userScripts.contains(where: { $0.source == Self.contextCapture }) {
            controller.addUserScript(WKUserScript(source: Self.contextCapture, injectionTime: .atDocumentStart,
                                                 forMainFrameOnly: false, in: world))
        }
    }

    fileprivate func captureContext(_ assets: [String: String]) {
        contextAssets = assets
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        let point = convert(event.locationInWindow, from: nil)
        for item in menu.items {
            let kind: String
            switch item.identifier?.rawValue {
            case "WKMenuItemIdentifierDownloadImage": kind = "image"
            case "WKMenuItemIdentifierDownloadLinkedFile": kind = "link"
            case "WKMenuItemIdentifierDownloadMedia": kind = "media"
            default: continue
            }
            // Use AppKit's public menu hook to route the action through the
            // public WKWebView download API. Other context actions stay native.
            item.target = self
            item.action = #selector(downloadContextAsset(_:))
            item.representedObject = BrowserContextDownload(
                kind: kind, url: contextAssets[kind].flatMap(URL.init(string:)),
                point: NSPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
            )
        }
    }

    @objc private func downloadContextAsset(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? BrowserContextDownload else { return }
        if let url = context.url ?? contextAssets[context.kind].flatMap(URL.init(string:)), Self.supportsAssetURL(url) {
            downloads.start(url, using: self)
            return
        }
        // The isolated capture normally supplies the original target, including
        // cross-origin frames. Hit testing also supports already loaded pages.
        callAsyncJavaScript(Self.contextLookup,
                            arguments: ["x": context.point.x, "y": context.point.y, "kind": context.kind],
                            in: nil, in: BrowserAssetContextBridge.world) { [weak self] result in
            guard let self else { return }
            if case .success(let value) = result, let raw = value as? String,
               let url = URL(string: raw), Self.supportsAssetURL(url) {
                self.downloads.start(url, using: self)
            } else {
                self.downloads.reportFailure(filename: "Download",
                    message: "This webpage did not provide a downloadable file for the selected item.")
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        contextAssets = [:]
        super.rightMouseDown(with: event)
    }

    private static func supportsAssetURL(_ url: URL) -> Bool {
        ["http", "https", "blob", "data", "file"].contains(url.scheme?.lowercased() ?? "")
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { contextAssets = [:] }
        lookupID = UUID()
        dragAsset = nil
        isLookingUpAsset = false
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.option), let point = mouseDownPoint {
            let currentLookup = lookupID
            isLookingUpAsset = true
            callAsyncJavaScript(Self.assetLookup,
                                arguments: ["x": point.x, "y": isFlipped ? point.y : bounds.height - point.y],
                                in: nil, in: WKContentWorld.world(name: "NotchBrowserAssetDrag")) {
                [weak self] result in
                guard let self, self.lookupID == currentLookup else { return }
                self.isLookingUpAsset = false
                if case .success(let value) = result, let values = value as? [String: String] {
                    self.dragAsset = BrowserDragAsset(values)
                }
            }
            // A page with blocked JavaScript must not swallow a drag forever.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, self.lookupID == currentLookup else { return }
                self.isLookingUpAsset = false
            }
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard event.modifierFlags.contains(.option), let start = mouseDownPoint else {
            super.mouseDragged(with: event)
            return
        }
        if assetDragSource != nil || isLookingUpAsset { return }
        guard let asset = dragAsset else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= 5 else { return }

        let source = BrowserAssetDragSource(asset: asset, webView: self, downloads: downloads) { [weak self] in
            self?.assetDragSource = nil
            self?.resetAssetLookup()
        }
        assetDragSource = source
        let provider = NSFilePromiseProvider(fileType: asset.fileType.identifier, delegate: source)
        // AppKit's delegate is weak; the pasteboard must own the provider until
        // the receiver has requested and completed the promised file.
        provider.userInfo = source
        let item = NSDraggingItem(pasteboardWriter: provider)
        let preview = NSWorkspace.shared.icon(for: asset.fileType)
        item.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), contents: preview)
        let session = beginDraggingSession(with: [item], event: event, source: source)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        resetAssetLookup()
        super.mouseUp(with: event)
    }

    private func resetAssetLookup() {
        lookupID = UUID()
        mouseDownPoint = nil
        dragAsset = nil
        isLookingUpAsset = false
    }

    private static let assetLookup = """
        const target = document.elementFromPoint(x, y);
        // Images retain WebKit's native image data and file-promise behavior.
        if (!target || target.closest('img, input, textarea, [contenteditable="true"]')) return null;
        const media = target.closest('video, audio');
        if (media) {
            const url = media.currentSrc || media.src;
            if (!url) return null;
            const source = Array.from(media.querySelectorAll('source')).find(s => s.src === url);
            return { url, name: '', type: source?.type || media.getAttribute('type') || '', kind: media.localName };
        }
        const link = target.closest('a[href]');
        if (!link) return null;
        const extension = new URL(link.href, document.baseURI).pathname.split('.').pop().toLowerCase();
        if (!link.hasAttribute('download') && !/^(png|jpe?g|gif|webp|svg|avif|heic|mp4|mov|m4v|webm|mp3|m4a|wav|ogg|pdf|zip|json|csv|txt|woff2?|ttf|otf)$/.test(extension)) return null;
        return { url: link.href, name: link.getAttribute('download') || '', type: link.type || '', kind: 'asset' };
        """

    private static let contextCapture = """
        document.addEventListener('contextmenu', event => {
            if (!event.isTrusted) return;
            const target = event.target instanceof Element ? event.target : event.target?.parentElement;
            const image = target?.closest('img');
            const media = target?.closest('video, audio');
            const link = target?.closest('a[href]');
            window.webkit.messageHandlers.notchAssetContext.postMessage({
                image: image?.currentSrc || image?.src || '',
                media: media?.currentSrc || media?.src || '',
                link: link?.href || ''
            });
        }, true);
        """

    private static let contextLookup = """
        const target = document.elementFromPoint(x, y);
        if (kind === 'image') { const image = target?.closest('img'); return image?.currentSrc || image?.src || null; }
        if (kind === 'media') { const media = target?.closest('video, audio'); return media?.currentSrc || media?.src || null; }
        return target?.closest('a[href]')?.href || null;
        """
}

private final class BrowserContextDownload {
    let kind: String
    let url: URL?
    let point: NSPoint
    init(kind: String, url: URL?, point: NSPoint) {
        self.kind = kind
        self.url = url
        self.point = point
    }
}

@MainActor
private final class BrowserAssetContextBridge: NSObject, WKScriptMessageHandler {
    static let shared = BrowserAssetContextBridge()
    static let world = WKContentWorld.world(name: "NotchBrowserAssetContext")
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let view = message.webView as? BrowserAssetWebView, let assets = message.body as? [String: String] else { return }
        view.captureContext(assets)
    }
}

struct BrowserDragAsset {
    let url: URL
    let filename: String
    let fileType: UTType

    init?(_ values: [String: String]) {
        guard let raw = values["url"], let url = URL(string: raw),
              ["http", "https", "blob", "data", "file"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        self.url = url
        let hint = values["name"].flatMap { $0.isEmpty ? nil : $0 }
        let mimeType = values["type"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (url.scheme == "data" ? raw.dropFirst(5).split(separator: ";").first.map(String.init) : nil)
        let pathName = ["http", "https", "file"].contains(url.scheme ?? "") ? url.lastPathComponent : ""
        let name = hint ?? (pathName.isEmpty ? (values["kind"] ?? "asset") : pathName)
        var filename = BrowserDownloadFiles.filename(name, mimeType: mimeType)
        let type = mimeType.flatMap { UTType(mimeType: $0) }
            ?? UTType(filenameExtension: (filename as NSString).pathExtension) ?? .data
        fileType = type.conforms(to: .data) ? type : .data
        if (filename as NSString).pathExtension.isEmpty {
            filename += "." + (fileType.preferredFilenameExtension ?? "bin")
        }
        self.filename = filename
    }
}

@MainActor
private final class BrowserAssetDragSource: NSObject, NSDraggingSource, NSFilePromiseProviderDelegate {
    private let asset: BrowserDragAsset
    private let webView: WKWebView
    private let onEnd: () -> Void
    private let downloads: BrowserDownloads
    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "NotchBrowserAssetPromise"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(asset: BrowserDragAsset, webView: WKWebView, downloads: BrowserDownloads, onEnd: @escaping () -> Void) {
        self.asset = asset
        self.webView = webView
        self.onEnd = onEnd
        self.downloads = downloads
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onEnd()
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        asset.filename
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        promiseQueue
    }

    nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                                        completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            downloads.export(asset.url, using: webView, to: url, completion: completionHandler)
        }
    }
}

@MainActor
enum BrowserAssetDrop {
    static func receive(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) -> Bool {
        let supported = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }
        guard !supported.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in supported {
                let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ? UTType.fileURL : .url
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { value, _ in
                        let url: URL?
                        if let value = value as? URL { url = value }
                        else if let value = value as? Data { url = URL(dataRepresentation: value, relativeTo: nil) }
                        else if let value = value as? String { url = URL(string: value) }
                        else { url = nil }
                        continuation.resume(returning: url)
                    }
                }
                guard let url else { continue }
                if url.isFileURL {
                    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else { continue }
                } else {
                    guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { continue }
                }
                urls.append(url)
            }
            completion(urls)
        }
        return true
    }
}
