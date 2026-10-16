import AppKit
import Foundation
import WebKit

/// Owns WebKit completions until the user or an explicit CLI command responds.
/// Browser permission grants are available only through the native user UI.
@MainActor
final class BrowserPageInteraction {
    enum Kind: String { case alert, confirm, prompt, filePicker = "file-picker", permission }
    struct Response {
        var accepted = false
        var text: String?
        var files: [URL]?
    }
    private final class Pending {
        let id = UUID().uuidString
        let kind: Kind
        let message: String
        let origin: String
        let defaultText: String?
        let multiple: Bool
        let completion: (Response) -> Void
        var sheet: NSWindow?
        var field: NSTextField?
        var configureFilePanel: ((NSOpenPanel) -> Void)?
        init(kind: Kind, message: String, origin: String, defaultText: String?, multiple: Bool,
             completion: @escaping (Response) -> Void) {
            self.kind = kind; self.message = message; self.origin = origin
            self.defaultText = defaultText; self.multiple = multiple; self.completion = completion
        }
        var description: [String: Any] {
            ["id": id, "kind": kind.rawValue, "message": String(message.prefix(4000)), "origin": origin,
             "defaultText": defaultText as Any? ?? NSNull(), "allowsMultiple": multiple,
             "requiresUser": kind == .permission, "canRespondViaCLI": kind != .permission]
        }
    }
    private struct Upload {
        let files: [URL]
        let frameURL: String
        let mainFrame: Bool
    }
    weak var webView: WKWebView?
    private var pending: [Pending] = []
    private var upload: Upload?
    private(set) var uploadResult: Result<[URL], BrowserAgentError>?
    var dialogs: [[String: Any]] { pending.map(\.description) }
    var hasPending: Bool { !pending.isEmpty }
    var blockingError: BrowserAgentError? {
        guard let first = pending.first else { return nil }
        return BrowserAgentError(code: first.kind == .permission ? "human_required" : "dialog_pending",
            message: first.kind == .permission
                ? "A website permission request needs the user. Run handoff to show it; the CLI cannot grant permission."
                : "The page opened a \(first.kind.rawValue) dialog. Run dialogs, then respond using its ID.")
    }

    func add(kind: Kind, message: String, origin: String, defaultText: String? = nil, multiple: Bool = false,
             configureFilePanel: ((NSOpenPanel) -> Void)? = nil,
             completion: @escaping (Response) -> Void) {
        guard pending.count < 8 else { completion(Response()); return }
        let request = Pending(kind: kind, message: message, origin: origin, defaultText: defaultText,
                              multiple: multiple, completion: completion)
        request.configureFilePanel = configureFilePanel
        pending.append(request)
        presentPending()
    }

    func presentPending() {
        guard let first = pending.first, first.sheet == nil, let window = webView?.window,
              window.isVisible, window.attachedSheet == nil else { return }
        if first.kind == .filePicker {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = first.multiple
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            first.configureFilePanel?(panel)
            first.sheet = panel
            panel.beginSheetModal(for: window) { [weak self, weak first] response in
                guard let self, let first else { return }
                self.complete(first.id, with: Response(accepted: response == .OK, files: response == .OK ? panel.urls : nil))
            }
        } else {
            let alert = NSAlert()
            alert.messageText = first.origin.isEmpty ? "Website" : first.origin
            alert.informativeText = first.message
            alert.addButton(withTitle: first.kind == .permission ? "Don’t Allow" : "OK")
            if first.kind != .alert { alert.addButton(withTitle: first.kind == .permission ? "Allow" : "Cancel") }
            if first.kind == .permission {
                alert.buttons[0].keyEquivalent = "\r"
                alert.buttons[1].keyEquivalent = ""
            }
            if first.kind == .prompt {
                let field = NSTextField(string: first.defaultText ?? "")
                field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
                alert.accessoryView = field
                first.field = field
            }
            first.sheet = alert.window
            alert.beginSheetModal(for: window) { [weak self, weak first] response in
                guard let self, let first else { return }
                let accepted = response == (first.kind == .permission ? .alertSecondButtonReturn : .alertFirstButtonReturn)
                self.complete(first.id, with: Response(accepted: accepted, text: accepted ? first.field?.stringValue : nil))
            }
        }
    }

    func respond(id: String, accept: Bool, text: String?) throws {
        guard let request = pending.first(where: { $0.id == id }) else { throw missingDialog() }
        guard request.kind != .permission else {
            throw BrowserAgentError(code: "human_required", message: "Only the user can answer a website permission request. Run handoff.")
        }
        guard request.kind != .filePicker || !accept else {
            throw BrowserAgentError(code: "invalid_argument", message: "Use choose-files <dialog-id> <absolute-path>… to answer a file picker.")
        }
        guard text == nil || request.kind == .prompt else {
            throw BrowserAgentError(code: "invalid_argument", message: "Text is accepted only for prompt dialogs.")
        }
        complete(id, with: Response(accepted: accept, text: accept ? text ?? request.defaultText ?? "" : nil))
    }

    func chooseFiles(id: String, paths: [String]) throws -> [URL] {
        guard let request = pending.first(where: { $0.id == id }) else { throw missingDialog() }
        guard request.kind == .filePicker else {
            throw BrowserAgentError(code: "invalid_argument", message: "That dialog is not a file picker.")
        }
        let files = try Self.validatedFiles(paths)
        guard request.multiple || files.count == 1 else {
            throw BrowserAgentError(code: "invalid_argument", message: "This file input accepts only one file.")
        }
        complete(id, with: Response(accepted: true, files: files))
        return files
    }

    func planUpload(paths: [String], frameURL: String, mainFrame: Bool) throws {
        if let blockingError { throw blockingError }
        uploadResult = nil
        upload = Upload(files: try Self.validatedFiles(paths), frameURL: frameURL, mainFrame: mainFrame)
    }

    func handleFilePicker(parameters: WKOpenPanelParameters, frame: WKFrameInfo,
                          configurePanel: ((NSOpenPanel) -> Void)? = nil, completion: @escaping ([URL]?) -> Void) {
        guard let upload else {
            add(kind: .filePicker, message: "Choose files to upload", origin: Self.origin(frame),
                multiple: parameters.allowsMultipleSelection, configureFilePanel: configurePanel) { completion($0.files) }
            return
        }
        self.upload = nil
        guard upload.mainFrame == frame.isMainFrame, upload.frameURL == frame.request.url?.absoluteString else {
            uploadResult = .failure(BrowserAgentError(code: "upload_target_changed", message: "A different frame opened the file picker. No files were supplied; take a fresh snapshot."))
            completion(nil)
            return
        }
        guard parameters.allowsMultipleSelection || upload.files.count == 1 else {
            uploadResult = .failure(BrowserAgentError(code: "invalid_argument", message: "This file input accepts only one file."))
            completion(nil)
            return
        }
        uploadResult = .success(upload.files)
        completion(upload.files)
    }

    func cancelUpload() { upload = nil; uploadResult = nil }

    func cancelAll() {
        cancelUpload()
        let requests = pending
        pending.removeAll()
        for request in requests {
            closeSheet(request)
            request.completion(Response())
        }
    }

    static func validatedFiles(_ paths: [String]) throws -> [URL] {
        guard !paths.isEmpty, paths.count <= 100 else {
            throw BrowserAgentError(code: "invalid_argument", message: "Choose between 1 and 100 explicit local file paths.")
        }
        return try paths.map { path in
            guard path.hasPrefix("/"), !path.contains("\0") else {
                throw BrowserAgentError(code: "invalid_file", message: "Use absolute local file paths, not URLs or directories.")
            }
            let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            guard FileManager.default.isReadableFile(atPath: url.path),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                throw BrowserAgentError(code: "invalid_file", message: "The selected path is not a readable regular file: \(path)")
            }
            return url
        }
    }

    static func origin(_ frame: WKFrameInfo) -> String {
        let origin = frame.securityOrigin
        if origin.host.isEmpty { return frame.request.url?.host ?? "Website" }
        return origin.protocol + "://" + origin.host + (origin.port == 0 ? "" : ":\(origin.port)")
    }

    private func missingDialog() -> BrowserAgentError {
        BrowserAgentError(code: "dialog_gone", message: "That dialog was answered or closed. Run dialogs for current IDs.")
    }

    private func complete(_ id: String, with response: Response) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let request = pending.remove(at: index)
        closeSheet(request)
        request.completion(response)
        DispatchQueue.main.async { [weak self] in self?.presentPending() }
    }

    private func closeSheet(_ request: Pending) {
        if let sheet = request.sheet {
            if let parent = sheet.sheetParent { parent.endSheet(sheet, returnCode: .cancel) }
            sheet.orderOut(nil)
            request.sheet = nil
        }
    }
}
