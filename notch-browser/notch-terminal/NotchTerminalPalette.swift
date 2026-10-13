import GhosttyTerminal
import SwiftUI

enum NotchTerminalPalette {
    static let backgroundHex = "050505"
    static let foregroundHex = "FFFFFF"
    static let accentHex = "19AAD8"

    static let background = Color(
        red: 5.0 / 255.0,
        green: 5.0 / 255.0,
        blue: 5.0 / 255.0
    )
    static let foreground = Color.white
    static let accent = Color(
        red: 25.0 / 255.0,
        green: 170.0 / 255.0,
        blue: 216.0 / 255.0
    )

    static let terminalConfiguration = TerminalConfiguration(
        startingFrom: .default
    ) { builder in
        builder.withBackground(backgroundHex)
        builder.withForeground(foregroundHex)
        builder.withBoldColor(foregroundHex)
        builder.withCursorColor(accentHex)
        builder.withCursorText(backgroundHex)
        builder.withSelectionBackground(accentHex)
        builder.withSelectionForeground(foregroundHex)
        builder.withBackgroundOpacity(1)

        // Keep command output intentionally within the same three-color system.
        let palette: [String] = [
            "#050505", "#19AAD8", "#19AAD8", "#FFFFFF",
            "#19AAD8", "#19AAD8", "#19AAD8", "#FFFFFF",
            "#050505", "#19AAD8", "#19AAD8", "#FFFFFF",
            "#19AAD8", "#19AAD8", "#19AAD8", "#FFFFFF",
        ]
        for (index, color) in palette.enumerated() {
            builder.withPalette(index, color: color)
        }
    }
}
