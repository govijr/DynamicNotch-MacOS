import AppKit

// Standalone fixture: compile with BrowserResizeHandle.swift and
// NotchBrowserSizing.swift. Its executable has its own preferences domain.
@main
struct CornerResizeTests {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let start = CGPoint(x: 400, y: 700)
        try expect(
            BrowserResizeCorner.bottomLeft.translation(from: start, to: CGPoint(x: 360, y: 675))
                == CGSize(width: 80, height: 25),
            "The left corner follows an outward diagonal drag while the center stays fixed"
        )
        try expect(
            BrowserResizeCorner.bottomRight.translation(from: start, to: CGPoint(x: 440, y: 675))
                == CGSize(width: 80, height: 25),
            "Both corners grow by the same amount for matching outward drags"
        )
        try expect(
            BrowserResizeCorner.bottomRight.translation(from: start, to: CGPoint(x: 365, y: 700))
                == CGSize(width: -70, height: 0),
            "Horizontal dragging can shrink width without changing height"
        )
        try expect(
            BrowserResizeCorner.bottomLeft.translation(from: start, to: CGPoint(x: 400, y: 750))
                == CGSize(width: 0, height: -50),
            "Vertical dragging still works from either corner"
        )

        let defaults = UserDefaults.standard
        let widthKey = NotchBrowserSizing.expandedWidthDefaultsKey
        let originalWidth = defaults.object(forKey: widthKey)
        defer {
            if let originalWidth { defaults.set(originalWidth, forKey: widthKey) }
            else { defaults.removeObject(forKey: widthKey) }
        }
        defaults.removeObject(forKey: widthKey)
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let baseline = NotchBrowserSizing.resolved(for: screen, expandedHeightOverride: 500)
        try expect(
            baseline.expandedWidth == min(max(baseline.surfaceWidth, frame.width * 0.70), max(380, frame.width - 80)),
            "Without a saved width the existing default width is preserved"
        )
        let smallest = NotchBrowserSizing.resolved(
            for: screen, expandedWidthOverride: 1, expandedHeightOverride: 1
        )
        try expect(
            smallest.expandedWidth == smallest.expandedWidthRange.lowerBound
                && smallest.expandedHeight == smallest.expandedHeightRange.lowerBound,
            "Both dimensions stop at usable minimum sizes"
        )
        let largest = NotchBrowserSizing.resolved(
            for: screen, expandedWidthOverride: 10_000, expandedHeightOverride: 10_000
        )
        try expect(
            largest.expandedWidth == largest.expandedWidthRange.upperBound
                && largest.expandedHeight == largest.expandedHeightRange.upperBound,
            "Both dimensions stay within the display limits"
        )
        let savedWidth = (baseline.expandedWidthRange.lowerBound + baseline.expandedWidthRange.upperBound) / 2
        defaults.set(Double(savedWidth), forKey: widthKey)
        let restored = NotchBrowserSizing.resolved(for: screen, expandedHeightOverride: 500)
        try expect(restored.expandedWidth == savedWidth, "A subsequent presentation restores the saved width")
        let overridden = NotchBrowserSizing.resolved(
            for: screen, expandedWidthOverride: baseline.expandedWidth, expandedHeightOverride: 500
        )
        try expect(overridden.expandedWidth == baseline.expandedWidth, "The live width takes precedence over saved preferences")
        try expect(
            restored.surfaceWidth == baseline.surfaceWidth && restored.compactHeight == baseline.compactHeight,
            "Resizing the browser leaves the compact notch measurements unchanged"
        )
        print("10 corner resize checks passed")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw NSError(domain: "CornerResizeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
