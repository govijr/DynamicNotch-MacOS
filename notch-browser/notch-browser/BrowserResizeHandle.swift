import AppKit
import SwiftUI

enum BrowserResizeCorner {
    case bottomLeft
    case bottomRight

    func translation(from start: CGPoint, to current: CGPoint) -> CGSize {
        let horizontalDirection: CGFloat = self == .bottomLeft ? -1 : 1
        // The notch stays centered, so each side moves half the width change.
        return CGSize(
            width: (current.x - start.x) * horizontalDirection * 2,
            height: start.y - current.y
        )
    }

    var accessibilityLabel: String {
        self == .bottomLeft ? "Resize browser from bottom left" : "Resize browser from bottom right"
    }

    var cursor: NSCursor {
        if #available(macOS 15.0, *) {
            return .frameResize(
                position: self == .bottomLeft ? .bottomLeft : .bottomRight,
                directions: .all
            )
        }
        return self == .bottomLeft ? Self.leftCursor : Self.rightCursor
    }

    private static let leftCursor = diagonalCursor(rising: true)
    private static let rightCursor = diagonalCursor(rising: false)

    private static func diagonalCursor(rising: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            let path = NSBezierPath()
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: x, y: rising ? y : 20 - y)
            }
            path.move(to: point(4, 4))
            path.line(to: point(16, 16))
            path.move(to: point(4, 10))
            path.line(to: point(4, 4))
            path.line(to: point(10, 4))
            path.move(to: point(10, 16))
            path.line(to: point(16, 16))
            path.line(to: point(16, 10))
            path.lineJoinStyle = .round
            NSColor.white.setStroke()
            path.lineWidth = 4
            path.stroke()
            NSColor.black.setStroke()
            path.lineWidth = 2
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 10, y: 10))
    }
}

struct BrowserResizeHandle: View {
    let corner: BrowserResizeCorner
    let foreground: Color
    let onResize: (CGSize) -> Void
    let onResizeEnded: (CGSize) -> Void

    var body: some View {
        BrowserResizeDragTarget(
            corner: corner,
            color: NSColor(foreground).withAlphaComponent(0.56),
            onResize: onResize,
            onResizeEnded: onResizeEnded
        )
        .frame(width: 28, height: 28)
    }
}

private struct BrowserResizeDragTarget: NSViewRepresentable {
    let corner: BrowserResizeCorner
    let color: NSColor
    let onResize: (CGSize) -> Void
    let onResizeEnded: (CGSize) -> Void

    func makeNSView(context: Context) -> BrowserResizeGripView {
        let view = BrowserResizeGripView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: BrowserResizeGripView, context: Context) {
        view.corner = corner
        view.color = color
        view.onResize = onResize
        view.onResizeEnded = onResizeEnded
    }
}

private final class BrowserResizeGripView: NSView {
    var corner: BrowserResizeCorner = .bottomRight {
        didSet {
            setAccessibilityLabel(corner.accessibilityLabel)
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }
    var color: NSColor = .white { didSet { needsDisplay = true } }
    var onResize: ((CGSize) -> Void)?
    var onResizeEnded: ((CGSize) -> Void)?
    private var startScreenPoint: CGPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel(corner.accessibilityLabel)
        setAccessibilityHelp("Drag horizontally or vertically to change the browser width and height")
        toolTip = "Drag to resize browser"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: corner.cursor)
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setStroke()
        let grip = NSBezierPath()
        grip.lineWidth = 1.8
        grip.lineCapStyle = .round
        for (index, length) in [CGFloat(12), 6].enumerated() {
            let startX = corner == .bottomLeft ? 22 - length : 6 + length
            let endX: CGFloat = corner == .bottomLeft ? 22 : 6
            let endY = CGFloat(10 + index * 6)
            grip.move(to: NSPoint(x: startX, y: endY + length))
            grip.line(to: NSPoint(x: endX, y: endY))
        }
        grip.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        startScreenPoint = screenPoint(for: event)
        onResize?(.zero)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startScreenPoint else { return }
        // The grip and window origin move during resizing. Screen coordinates
        // keep the original drag anchor independent of those layout changes.
        onResize?(corner.translation(from: startScreenPoint, to: screenPoint(for: event)))
    }

    override func mouseUp(with event: NSEvent) {
        guard let startScreenPoint else { return }
        self.startScreenPoint = nil
        onResizeEnded?(corner.translation(from: startScreenPoint, to: screenPoint(for: event)))
    }

    private func screenPoint(for event: NSEvent) -> CGPoint {
        // Use this event's position rather than sampling a later cursor position.
        // Converting to screen space keeps the anchor stable as the window moves.
        (event.window ?? window)?.convertPoint(toScreen: event.locationInWindow)
            ?? NSEvent.mouseLocation
    }
}
