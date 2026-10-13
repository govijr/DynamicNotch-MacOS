import AppKit
import DynamicNotch
import SwiftUI

@MainActor
final class NotchTerminalWindowController {
    private let workspace: TerminalTabsModel
    private let notchController = DynamicNotchWindowController()
    private var isExpanded = false
    private var expandedHeight: CGFloat?
    private var resizeGestureStartHeight: CGFloat?

    init(workspace: TerminalTabsModel) {
        self.workspace = workspace
        notchController.onDismiss = { [weak self] in
            self?.restoreCompactSurfaceIfNeeded()
        }
    }

    func showCompact(animated: Bool = true) {
        isExpanded = false
        notchController.dismissalPolicy = .manual

        let screen = NSScreen.main ?? NSScreen.screens.first
        let sizing = NotchTerminalSizing.resolved(for: screen)
        let expand: () -> Void = { [weak self] in
            self?.showExpanded()
        }

        notchController.show(
            direction: .top,
            width: sizing.surfaceWidth,
            height: sizing.compactHeight,
            cornerRadius: sizing.cornerRadius,
            shoulderRadius: sizing.shoulderRadius,
            attachedEdgeRail: 0,
            background: NotchTerminalPalette.background,
            contentInsets: EdgeInsets(),
            screen: screen,
            animated: animated
        ) {
            CompactTerminalSurface(workspace: self.workspace, onExpand: expand)
        }
    }

    func showExpanded(animated: Bool = true) {
        isExpanded = true
        notchController.dismissalPolicy = .manual

        let screen = NSScreen.main ?? NSScreen.screens.first
        let sizing = NotchTerminalSizing.resolved(
            for: screen,
            expandedHeightOverride: expandedHeight
        )
        expandedHeight = sizing.expandedHeight
        renderExpanded(sizing: sizing, on: screen, animated: animated)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isExpanded else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.workspace.selectedTab.focusIfPossible()
            self.notchController.dismissalPolicy = .clickOutside
        }
    }

    private func restoreCompactSurfaceIfNeeded() {
        guard isExpanded else { return }
        showCompact(animated: false)
    }

    private func renderExpanded(
        sizing: NotchTerminalSizing,
        on screen: NSScreen?,
        animated: Bool
    ) {
        let collapse: () -> Void = { [weak self] in
            self?.showCompact()
        }
        let resize: (CGFloat) -> Void = { [weak self] translation in
            self?.resizeExpanded(by: translation)
        }
        let resizeEnded: (CGFloat) -> Void = { [weak self] translation in
            self?.finishResize(by: translation)
        }

        notchController.show(
            direction: .top,
            width: sizing.expandedWidth,
            height: sizing.expandedHeight,
            cornerRadius: sizing.expandedCornerRadius,
            shoulderRadius: sizing.expandedShoulderRadius,
            attachedEdgeRail: nil,
            background: NotchTerminalPalette.background,
            contentInsets: EdgeInsets(),
            screen: screen,
            animated: animated
        ) {
            TerminalContentView(
                workspace: self.workspace,
                onCollapse: collapse,
                onResize: resize,
                onResizeEnded: resizeEnded
            )
        }
    }

    private func resizeExpanded(by translation: CGFloat) {
        guard isExpanded else { return }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let currentSizing = NotchTerminalSizing.resolved(
            for: screen,
            expandedHeightOverride: expandedHeight
        )
        let startHeight = resizeGestureStartHeight ?? currentSizing.expandedHeight
        resizeGestureStartHeight = startHeight

        let sizing = NotchTerminalSizing.resolved(
            for: screen,
            expandedHeightOverride: startHeight + translation
        )
        expandedHeight = sizing.expandedHeight
        notchController.resize(
            height: sizing.expandedHeight,
            cornerRadius: sizing.expandedCornerRadius,
            shoulderRadius: sizing.expandedShoulderRadius,
            screen: screen,
            animated: false
        )
    }

    private func finishResize(by translation: CGFloat) {
        resizeExpanded(by: translation)

        if let expandedHeight {
            UserDefaults.standard.set(
                Double(expandedHeight),
                forKey: NotchTerminalSizing.expandedHeightDefaultsKey
            )
        }
        resizeGestureStartHeight = nil
    }
}
