import AppKit
import SwiftUI

struct BrowserResizeHandle: View {
    let foreground: Color
    let onResize: (CGFloat) -> Void
    let onResizeEnded: (CGFloat) -> Void

    var body: some View {
        BrowserResizeDragTarget(
            color: NSColor(foreground).withAlphaComponent(0.56),
            onResize: onResize,
            onResizeEnded: onResizeEnded
        )
        .frame(maxWidth: .infinity)
        .frame(height: 26)
    }
}

private struct BrowserResizeDragTarget: NSViewRepresentable {
    let color: NSColor
    let onResize: (CGFloat) -> Void
    let onResizeEnded: (CGFloat) -> Void

    func makeNSView(context: Context) -> BrowserResizeGripView {
        let view = BrowserResizeGripView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: BrowserResizeGripView, context: Context) {
        view.color = color
        view.onResize = onResize
        view.onResizeEnded = onResizeEnded
    }
}

private final class BrowserResizeGripView: NSView {
    var color: NSColor = .white { didSet { needsDisplay = true } }
    var onResize: ((CGFloat) -> Void)?
    var onResizeEnded: ((CGFloat) -> Void)?
    private var startScreenY: CGFloat?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Resize browser")
        setAccessibilityHelp("Drag vertically to change the browser height")
        toolTip = "Drag to resize browser"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: (bounds.width - 42) / 2, y: (bounds.height - 4) / 2, width: 42, height: 4),
            xRadius: 2,
            yRadius: 2
        ).fill()
    }

    override func mouseDown(with event: NSEvent) {
        startScreenY = NSEvent.mouseLocation.y
        onResize?(0)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startScreenY else { return }
        // The grip and window origin move during resizing. Screen coordinates
        // keep the original drag anchor independent of those layout changes.
        onResize?(startScreenY - NSEvent.mouseLocation.y)
    }

    override func mouseUp(with event: NSEvent) {
        guard let startScreenY else { return }
        self.startScreenY = nil
        onResizeEnded?(startScreenY - NSEvent.mouseLocation.y)
    }
}
