import AppKit
import GhosttyTerminal

@MainActor
final class NotchTerminalView: TerminalView {
    private var localKeyMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }

        guard window != nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else {
                return event
            }
            guard event.window == nil || event.window === window else {
                return event
            }
            guard window.firstResponder !== self else {
                return event
            }

            // Restore focus only from the panel/hosting view, never from an
            // editable control (such as a future search field).
            guard !(window.firstResponder is NSTextView),
                  !(window.firstResponder is NSControl),
                  window.makeFirstResponder(self)
            else { return event }

            // SwiftUI's hosting panel can consume the first key before the
            // terminal becomes first responder. Replay that key once; the
            // following key-up/flags events continue through AppKit normally.
            guard event.type == .keyDown else { return event }
            self.keyDown(with: event)
            return nil
        }
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    override func keyDown(with event: NSEvent) {
        if routeEditingShortcut(for: event) {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           routeEditingShortcut(for: event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func routeEditingShortcut(for event: NSEvent) -> Bool {
        // macOS uses Command+A for select-all. Shift+A remains an ordinary
        // uppercase character and continues through Ghostty's key translator.
        guard window?.firstResponder === self,
              event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command
        else { return false }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a":
            return performBindingAction("select_all")
        case "c":
            return copySelectedTextToPasteboard()
        case "v":
            // Use Ghostty's paste path to retain bracketed-paste handling.
            if let text = NSPasteboard.general.string(forType: .string) {
                return paste(text: text)
            }
            return false
        default:
            return false
        }
    }
}
