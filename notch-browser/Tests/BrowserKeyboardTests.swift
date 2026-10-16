import AppKit
import SwiftUI

@main
struct BrowserKeyboardTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await run()
                print("4 native address-focus checks passed")
                exit(0)
            } catch {
                print("FAIL: \(error.localizedDescription)")
                exit(1)
            }
        }
        app.run()
    }

    @MainActor private static func run() async throws {
        let browser = BrowserModel(library: BrowserLibrary(), startsEmpty: true)
        browser.addressText = "Retained new-tab query"
        browser.focusAddress() // Requested before the field has a window.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: AddressFocusProbe(browser: browser))
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); browser.close() }
        let deadline = Date().addingTimeInterval(5)
        while browser.addressFocusRequest != nil {
            hosting.layoutSubtreeIfNeeded()
            guard Date() < deadline else { throw failure("Address focus was not delivered after attachment") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let field = findField(in: hosting), let editor = field.currentEditor() as? NSTextView,
              window.firstResponder === editor else { throw failure("The address is not the first responder") }
        guard editor.selectedRange().length == browser.addressText.utf16.count else { throw failure("Focus did not select the entire address") }
        guard browser.addressFocusRequest == nil else { throw failure("Handled focus requests must be consumed") }
        window.makeFirstResponder(nil)
        guard browser.addressText == "Retained new-tab query" else { throw failure("Losing focus erased the new-tab query") }
        window.contentView = NSHostingView(rootView: AddressFocusProbe(browser: browser))
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 80_000_000)
        guard findField(in: window.contentView!)?.currentEditor() == nil else { throw failure("A recreated field replayed an old focus request") }
    }

    private static func findField(in view: NSView) -> BrowserAddressNSTextField? {
        if let field = view as? BrowserAddressNSTextField { return field }
        return view.subviews.lazy.compactMap { findField(in: $0) }.first
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "BrowserKeyboardTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private struct AddressFocusProbe: View {
    @ObservedObject var browser: BrowserModel
    var body: some View {
        BrowserAddressField(text: $browser.addressText, font: .systemFont(ofSize: 14), textColor: .white,
                            placeholder: "Search", onSubmit: browser.submitAddress,
                            focusRequest: browser.addressFocusRequest, onFocusHandled: browser.consumeAddressFocus,
                            onBeginEditing: browser.beginAddressEditing, onEndEditing: browser.endAddressEditing)
            .padding(20)
    }
}
