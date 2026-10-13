import AppKit
import SwiftUI

/// An AppKit-backed address field keeps Return handling local to the browser
/// address bar. This matters inside the nonactivating notch panel: the web
/// page remains free to handle Return in its own inputs.
struct BrowserAddressField: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let textColor: NSColor
    let placeholder: String
    let onSubmit: () -> Void

    private var attributedPlaceholder: NSAttributedString {
        NSAttributedString(string: placeholder, attributes: [
            .font: font,
            .foregroundColor: textColor.withAlphaComponent(0.6)
        ])
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> BrowserAddressNSTextField {
        let field = BrowserAddressNSTextField()
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingMiddle
        field.placeholderAttributedString = attributedPlaceholder
        field.stringValue = text
        field.font = font
        field.textColor = textColor
        field.alignment = .left
        field.setAccessibilityLabel("Address")
        field.setAccessibilityIdentifier("notch-browser-address")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: BrowserAddressNSTextField, context: Context) {
        context.coordinator.parent = self

        if field.stringValue != text {
            field.stringValue = text
        }

        field.font = font
        field.textColor = textColor
        field.placeholderAttributedString = attributedPlaceholder
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: BrowserAddressField

        init(_ parent: BrowserAddressField) {
            self.parent = parent
        }

        @objc func submit(_ sender: NSTextField) {
            parent.onSubmit()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            let selectorName = NSStringFromSelector(commandSelector)
            guard selectorName == "insertNewline:"
                || selectorName == "insertNewlineIgnoringFieldEditor:"
            else {
                return false
            }

            parent.onSubmit()
            return true
        }
    }
}

final class BrowserAddressNSTextField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
