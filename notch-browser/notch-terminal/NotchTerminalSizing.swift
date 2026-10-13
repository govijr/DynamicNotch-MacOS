import AppKit

struct NotchTerminalSizing {
    static let expandedHeightDefaultsKey = "notchTerminal.expandedHeight"
    static let minimumExpandedHeight: CGFloat = 360
    static let maximumExpandedHeight: CGFloat = 760

    let surfaceWidth: CGFloat
    let expandedWidth: CGFloat
    let compactHeight: CGFloat
    let expandedHeight: CGFloat
    let expandedHeightRange: ClosedRange<CGFloat>
    let expandedCornerRadius: CGFloat
    let expandedShoulderRadius: CGFloat
    let cornerRadius: CGFloat
    let shoulderRadius: CGFloat

    static func resolved(
        for screen: NSScreen?,
        expandedHeightOverride: CGFloat? = nil
    ) -> Self {
        let display = screen ?? NSScreen.main ?? NSScreen.screens.first
        let frame = display?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = display?.visibleFrame ?? frame
        let safeAreaTop = max(
            display?.safeAreaInsets.top ?? 0,
            NSStatusBar.system.thickness
        )
        let physicalNotchGap = Self.physicalNotchGap(for: display)
        let widthFromNotch = physicalNotchGap > 0
            ? physicalNotchGap + 48
            : 240
        let widthLimit = max(380, frame.width - 80)
        let surfaceWidth = min(max(240, widthFromNotch), widthLimit)
        let expandedWidth = min(
            max(surfaceWidth, frame.width * 0.70),
            widthLimit
        )

        let referenceNotchHeight: CGFloat
        if physicalNotchGap >= 205 {
            referenceNotchHeight = 38
        } else if physicalNotchGap > 0 {
            referenceNotchHeight = 32
        } else {
            referenceNotchHeight = min(max(safeAreaTop, 32), 38)
        }

        let compactHeight = referenceNotchHeight
        let defaultExpandedHeight = min(620, max(560, visibleFrame.height - 64))
        let maximumExpandedHeight = min(
            Self.maximumExpandedHeight,
            max(Self.minimumExpandedHeight, visibleFrame.height - 64)
        )
        let minimumExpandedHeight = min(
            Self.minimumExpandedHeight,
            maximumExpandedHeight
        )
        let expandedHeightRange = minimumExpandedHeight...maximumExpandedHeight
        let storedExpandedHeight = UserDefaults.standard
            .object(forKey: Self.expandedHeightDefaultsKey) as? Double
        let requestedExpandedHeight = expandedHeightOverride
            ?? CGFloat(storedExpandedHeight ?? Double(defaultExpandedHeight))
        let expandedHeight = min(
            max(requestedExpandedHeight, expandedHeightRange.lowerBound),
            expandedHeightRange.upperBound
        )

        return Self(
            surfaceWidth: surfaceWidth,
            expandedWidth: expandedWidth,
            compactHeight: compactHeight,
            expandedHeight: expandedHeight,
            expandedHeightRange: expandedHeightRange,
            expandedCornerRadius: min(42, expandedHeight / 2),
            expandedShoulderRadius: min(42, expandedHeight / 4),
            cornerRadius: compactHeight / 2,
            shoulderRadius: compactHeight / 2
        )
    }

    private static func physicalNotchGap(for screen: NSScreen?) -> CGFloat {
        guard
            let leftArea = screen?.auxiliaryTopLeftArea,
            let rightArea = screen?.auxiliaryTopRightArea
        else {
            return 0
        }

        return max(0, rightArea.minX - leftArea.maxX)
    }
}
