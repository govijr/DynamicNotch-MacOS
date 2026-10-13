import AppKit
import DynamicNotch
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let library = BrowserLibrary.shared
    private let license = PolarLicenseModel.shared
    private let tabs: BrowserTabsModel
    let agentActivity = BrowserAgentActivity()
    private var agentController: BrowserAgentController!
    private var agentServer: BrowserAgentServer!
    private var windowController: NotchBrowserWindowController!
    private var isPreviewingOnboarding = false
    private var isShowingImportOnboarding = false
    private var wasAgentPausedBeforePreview = false

    private var hasBrowserAccess: Bool {
        license.isUnlocked && library.hasCompletedImportOnboarding
            && !isPreviewingOnboarding && !isShowingImportOnboarding
    }

    override init() {
        tabs = BrowserTabsModel(library: library)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = NotchBrowserWindowController(
            tabs: tabs, library: library, activity: agentActivity,
            onOpen: { [weak self] in self?.showBrowser() }
        )
        agentController = BrowserAgentController(
            tabs: tabs, activity: agentActivity,
            isUnlocked: { [weak self] in self?.hasBrowserAccess == true },
            expand: { [weak self] in self?.showBrowser() },
            collapse: { [weak self] in self?.windowController.showCompact() }
        )
        agentServer = BrowserAgentServer(controller: agentController)
        agentServer.start()
        windowController.showCompact(animated: false)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-onboarding") {
            previewOnboarding()
            return
        }
        #endif
        Task { @MainActor [weak self] in
            guard let self else { return }
            await license.restoreAndValidate()
            guard !isPreviewingOnboarding else { return }
            if license.isUnlocked {
                if library.hasCompletedImportOnboarding {
                    windowController.showCompact(animated: false)
                } else {
                    showImportOnboarding()
                }
            } else {
                showLicenseOnboarding(afterDelay: true)
            }
        }
    }

    func showBrowser() {
        guard !isShowingImportOnboarding else { return }
        if license.isUnlocked && !isPreviewingOnboarding && !library.hasCompletedImportOnboarding {
            showImportOnboarding()
            return
        }
        guard hasBrowserAccess else {
            showLicenseOnboarding()
            return
        }
        windowController.showExpanded()
    }

    func newTab() {
        guard !isShowingImportOnboarding else { return }
        if license.isUnlocked && !isPreviewingOnboarding && !library.hasCompletedImportOnboarding {
            showImportOnboarding()
            return
        }
        guard hasBrowserAccess else {
            showLicenseOnboarding()
            return
        }
        tabs.addTab()
        windowController.showExpanded()
    }

    func closeTab() {
        guard hasBrowserAccess else { return }
        tabs.closeTab(tabs.activeTabID)
    }

    func goBack() {
        guard hasBrowserAccess else { return }
        tabs.activeBrowser.goBack()
    }

    func goForward() {
        guard hasBrowserAccess else { return }
        tabs.activeBrowser.goForward()
    }

    func reloadPage() {
        guard hasBrowserAccess else { return }
        tabs.activeBrowser.reload()
    }

    func showLicenseOnboarding(afterDelay: Bool = false) {
        guard !isShowingImportOnboarding else { return }
        windowController.showOnboarding(
            license: license,
            isPreview: isPreviewingOnboarding,
            afterDelay: afterDelay,
            onUnlocked: { [weak self] in
                self?.showImportOnboarding()
            },
            onExitPreview: { [weak self] in self?.endOnboardingPreview() }
        )
    }

    func showImportOnboarding() {
        guard license.isUnlocked || isPreviewingOnboarding else {
            showLicenseOnboarding()
            return
        }
        guard !isShowingImportOnboarding else { return }
        isShowingImportOnboarding = true
        windowController.showImportOnboarding(
            isPreview: isPreviewingOnboarding,
            onContinue: { [weak self] in
                guard let self else { return }
                if isPreviewingOnboarding {
                    endOnboardingPreview()
                } else {
                    library.completeImportOnboarding()
                    isShowingImportOnboarding = false
                    windowController.showExpanded()
                }
            },
            onExitPreview: { [weak self] in self?.endOnboardingPreview() }
        )
    }

    #if DEBUG
    func previewOnboarding() {
        if !isPreviewingOnboarding { wasAgentPausedBeforePreview = agentActivity.isPaused }
        agentActivity.stop()
        isPreviewingOnboarding = true
        isShowingImportOnboarding = false
        windowController.showCompact()
        showLicenseOnboarding(afterDelay: true)
    }
    #endif

    private func endOnboardingPreview() {
        isPreviewingOnboarding = false
        isShowingImportOnboarding = false
        if !wasAgentPausedBeforePreview { agentActivity.resume() }
        windowController.showCompact()
        Task { @MainActor [weak self] in
            guard let self else { return }
            // A launch-time preview never loads or changes the stored license.
            // Restore the real entitlement only once the preview has ended.
            if !license.isUnlocked { await license.restoreAndValidate() }
            guard !isPreviewingOnboarding else { return }
            if !license.isUnlocked { showLicenseOnboarding() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        agentServer?.stop()
    }

    var agentConnectionError: String? { agentServer?.startupError }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard tabs.tabs.contains(where: { $0.webView != nil }) else { return .terminateNow }

        Task { @MainActor [weak self] in
            await self?.library.saveSessionAndWait(updateStatus: false)
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Coordinates the browser content with the reusable physical-notch window.
/// The package owns placement, shape clipping, safe-area rails, and click-away
/// hit testing; this type only switches between the compact and expanded UI.
@MainActor
final class NotchBrowserWindowController {
    private let tabs: BrowserTabsModel
    private let library: BrowserLibrary
    private let activity: BrowserAgentActivity
    private let onOpen: () -> Void
    private let notchController = DynamicNotchWindowController()
    private var isExpanded = false
    private var isShowingOnboarding = false
    private var onboardingTask: Task<Void, Never>?
    private var expandedHeight: CGFloat?
    private struct ResizeContext {
        let screen: NSScreen?
        let startHeight: CGFloat
        let heightRange: ClosedRange<CGFloat>
    }
    private var resizeContext: ResizeContext?

    init(tabs: BrowserTabsModel, library: BrowserLibrary, activity: BrowserAgentActivity,
         onOpen: @escaping () -> Void) {
        self.tabs = tabs
        self.library = library
        self.activity = activity
        self.onOpen = onOpen
        notchController.onDismiss = { [weak self] in
            self?.restoreCompactSurfaceIfNeeded()
        }
        notchController.onWillDismiss = { [weak self] in
            guard let self, self.isExpanded else { return }
            self.tabs.activeBrowser.captureVisiblePage()
        }
        notchController.onOutsideClick = { [weak self] in
            guard let self, self.isExpanded else { return false }
            self.showCompact()
            return true
        }
    }

    func showCompact(animated: Bool = true) {
        onboardingTask?.cancel()
        isShowingOnboarding = false
        if isExpanded && notchController.isVisible {
            tabs.activeBrowser.captureVisiblePage()
        }
        isExpanded = false
        resizeContext = nil
        notchController.dismissalPolicy = .manual

        let screen = NSScreen.main ?? NSScreen.screens.first
        let sizing = NotchBrowserSizing.resolved(for: screen)
        let expand: () -> Void = { [weak self] in
            guard let self, !self.isShowingOnboarding else { return }
            self.onOpen()
        }

        notchController.show(
            direction: .top,
            width: sizing.surfaceWidth,
            height: sizing.compactHeight,
            cornerRadius: sizing.cornerRadius,
            shoulderRadius: sizing.shoulderRadius,
            attachedEdgeRail: 0,
            background: .black,
            contentInsets: EdgeInsets(
                top: 0,
                leading: 0,
                bottom: 0,
                trailing: 0
            ),
            screen: screen,
            animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ) {
            CompactBrowserSurface(activity: self.activity, onExpand: expand)
        }
    }

    func showExpanded(animated: Bool = true) {
        onboardingTask?.cancel()
        isShowingOnboarding = false
        guard !isExpanded else { return }
        isExpanded = true
        // Install click-away handling after the opening hover/click has
        // finished. The compact hover target and expanded surface share one
        // panel; registering the monitor synchronously can treat the opening
        // interaction as an outside click and immediately collapse it.
        notchController.dismissalPolicy = .manual

        let screen = NSScreen.main ?? NSScreen.screens.first
        let sizing = NotchBrowserSizing.resolved(
            for: screen,
            expandedHeightOverride: expandedHeight
        )
        expandedHeight = sizing.expandedHeight
        renderExpanded(sizing: sizing, on: screen,
                       animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isExpanded else { return }
            self.notchController.dismissalPolicy = .clickOutside
        }
    }

    func showOnboarding(
        license: PolarLicenseModel,
        isPreview: Bool,
        afterDelay: Bool,
        onUnlocked: @escaping () -> Void,
        onExitPreview: @escaping () -> Void
    ) {
        guard !isShowingOnboarding else { return }
        if isExpanded { tabs.activeBrowser.captureVisiblePage() }
        isExpanded = false
        isShowingOnboarding = true
        resizeContext = nil
        // Keep the first-launch field available when the pointer leaves the notch.
        notchController.dismissalPolicy = .manual
        onboardingTask?.cancel()
        onboardingTask = Task { @MainActor [weak self] in
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if afterDelay && !reduceMotion {
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            guard let self, !Task.isCancelled, self.isShowingOnboarding else { return }
            let screen = NSScreen.main ?? NSScreen.screens.first
            let sizing = NotchBrowserSizing.resolved(
                for: screen,
                expandedHeightOverride: self.expandedHeight
            )
            self.expandedHeight = sizing.expandedHeight
            let presentationID = UUID()
            self.notchController.show(
                direction: .top,
                width: sizing.expandedWidth,
                height: sizing.expandedHeight,
                cornerRadius: sizing.expandedCornerRadius,
                shoulderRadius: sizing.expandedShoulderRadius,
                attachedEdgeRail: nil,
                background: .black,
                screen: screen,
                animated: !reduceMotion
            ) {
                LicenseOnboardingView(
                    license: license, isPreview: isPreview,
                    onUnlocked: onUnlocked, onExitPreview: onExitPreview
                )
                .id(presentationID)
            }
        }
    }

    private func restoreCompactSurfaceIfNeeded() {
        guard isExpanded else { return }
        showCompact(animated: false)
    }

    func showImportOnboarding(
        isPreview: Bool,
        onContinue: @escaping () -> Void,
        onExitPreview: @escaping () -> Void
    ) {
        onboardingTask?.cancel()
        if isExpanded { tabs.activeBrowser.captureVisiblePage() }
        isExpanded = false
        isShowingOnboarding = true
        resizeContext = nil
        notchController.dismissalPolicy = .manual
        let screen = NSScreen.main ?? NSScreen.screens.first
        let sizing = NotchBrowserSizing.resolved(for: screen, expandedHeightOverride: expandedHeight)
        expandedHeight = sizing.expandedHeight
        let presentationID = UUID()
        notchController.show(
            direction: .top,
            width: sizing.expandedWidth,
            height: sizing.expandedHeight,
            cornerRadius: sizing.expandedCornerRadius,
            shoulderRadius: sizing.expandedShoulderRadius,
            attachedEdgeRail: nil,
            background: .black,
            screen: screen,
            animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ) {
            BrowserSessionImportView(
                library: self.library, isPreview: isPreview,
                onContinue: onContinue, onExitPreview: onExitPreview
            )
            .id(presentationID)
        }
    }

    private func renderExpanded(
        sizing: NotchBrowserSizing,
        on screen: NSScreen?,
        animated: Bool
    ) {
        let tabs = tabs
        let library = library
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
            background: .black,
            bodyBackground: AnyView(BrowserTabsBackground(tabs: tabs, library: library)),
            contentInsets: EdgeInsets(),
            screen: screen,
            animated: animated
        ) {
            BrowserTabsView(
                tabs: tabs,
                library: library,
                activity: self.activity,
                onCollapse: collapse,
                onResize: resize,
                onResizeEnded: resizeEnded
            )
        }
    }

    private func resizeExpanded(by translation: CGFloat) {
        guard isExpanded else { return }

        if resizeContext == nil {
            let screen = NSScreen.main ?? NSScreen.screens.first
            let sizing = NotchBrowserSizing.resolved(for: screen, expandedHeightOverride: expandedHeight)
            resizeContext = ResizeContext(
                screen: screen,
                startHeight: sizing.expandedHeight,
                heightRange: sizing.expandedHeightRange
            )
        }
        guard let resizeContext else { return }
        let scale = resizeContext.screen?.backingScaleFactor ?? 1
        let requestedHeight = ((resizeContext.startHeight + translation) * scale).rounded() / scale
        let height = min(max(requestedHeight, resizeContext.heightRange.lowerBound), resizeContext.heightRange.upperBound)
        guard height != expandedHeight else { return }
        expandedHeight = height
        notchController.resize(
            height: height,
            screen: resizeContext.screen,
            animated: false
        )
    }

    private func finishResize(by translation: CGFloat) {
        resizeExpanded(by: translation)

        if let expandedHeight {
            UserDefaults.standard.set(
                Double(expandedHeight),
                forKey: NotchBrowserSizing.expandedHeightDefaultsKey
            )
        }

        resizeContext = nil
    }

}
