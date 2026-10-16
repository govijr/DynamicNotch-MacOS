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
    var focusRequest: UUID? = nil
    var accessibilityLabel = "Address"
    var accessibilityIdentifier = "notch-browser-address"
    var resignOnSubmit = true
    var onFocusHandled: () -> Void = {}
    var onBeginEditing: () -> Void = {}
    var onEndEditing: () -> Void = {}
    var onCancel: (() -> Void)? = nil

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
        field.setAccessibilityLabel(accessibilityLabel)
        field.setAccessibilityIdentifier(accessibilityIdentifier)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.onAttach = { [weak field, weak coordinator = context.coordinator] in
            if let field { coordinator?.applyFocus(to: field) }
        }
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
        context.coordinator.applyFocus(to: field)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: BrowserAddressField
        private var handledFocusRequest: UUID?

        init(_ parent: BrowserAddressField) {
            self.parent = parent
        }

        @objc func submit(_ sender: NSTextField) {
            parent.onSubmit()
            if parent.resignOnSubmit { sender.window?.makeFirstResponder(nil) }
        }

        func applyFocus(to field: NSTextField) {
            guard let request = parent.focusRequest, request != handledFocusRequest, let window = field.window else { return }
            handledFocusRequest = request
            DispatchQueue.main.async { [weak self, weak field] in
                guard let field, field.window === window else { return }
                window.makeKey()
                guard window.makeFirstResponder(field) else { return }
                field.selectText(nil)
                self?.parent.onFocusHandled()
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) { parent.onBeginEditing() }
        func controlTextDidEndEditing(_ notification: Notification) { parent.onEndEditing() }

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
            if selectorName == "cancelOperation:", let onCancel = parent.onCancel {
                onCancel()
                return true
            }
            guard selectorName == "insertNewline:"
                || selectorName == "insertNewlineIgnoringFieldEditor:"
            else {
                return false
            }

            parent.onSubmit()
            if parent.resignOnSubmit { control.window?.makeFirstResponder(nil) }
            return true
        }
    }
}

final class BrowserAddressNSTextField: NSTextField {
    var onAttach: (() -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onAttach?() }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
