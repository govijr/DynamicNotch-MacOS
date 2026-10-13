import AppKit

@MainActor
enum BrowserAppIcon {
    static let image = NSImage(named: "AppIcon")
        ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    // Give the status item a native menu-bar size without resizing the
    // shared image used by the onboarding screen.
    static let menuBarImage: NSImage = {
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: rect)
            return true
        }
        icon.isTemplate = false
        return icon
    }()
}
