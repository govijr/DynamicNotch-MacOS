import AppKit
import Combine
import DynamicNotch
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let library = BrowserLibrary.shared
    private let license = PolarLicenseModel.shared
    private let tabs: BrowserTabsModel
    let lookup: BrowserLookupCoordinator
    let agentActivity = BrowserAgentActivity()
    private var agentController: BrowserAgentController!
    private var agentServer: BrowserAgentServer!
    private var windowController: NotchBrowserWindowController!
    private var isPreviewingOnboarding = false
    private var isShowingImportOnboarding = false
    private var wasAgentPausedBeforePreview = false
    private var agentSessionObservation: AnyCancellable?
    private var isRestoringAccess = true

    private var hasBrowserAccess: Bool {
        license.isUnlocked && library.hasCompletedImportOnboarding
            && !isPreviewingOnboarding && !isShowingImportOnboarding
    }

    override init() {
        tabs = BrowserTabsModel(library: library)
        lookup = BrowserLookupCoordinator(tabs: tabs, library: library)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = NotchBrowserWindowController(
            tabs: tabs, library: library, activity: agentActivity, lookup: lookup,
            onOpen: { [weak self] in self?.showBrowser() }
        )
        lookup.onRequest = { [weak self] in self?.presentRequestedLookup() }
        lookup.onDismiss = { [weak self] restoreFocus in self?.windowController.showCompact(restoreLookupFocus: restoreFocus) }
        lookup.start()
        agentController = BrowserAgentController(
            tabs: tabs, activity: agentActivity,
            isUnlocked: { [weak self] in self?.hasBrowserAccess == true },
            expand: { [weak self] in self?.showBrowser() },
            collapse: { [weak self] in self?.windowController.showCompact() }
        )
        agentServer = BrowserAgentServer(controller: agentController)
        agentServer.start()
        license.onAccessRevoked = { [weak self] in
            guard let self, !self.isPreviewingOnboarding else { return }
            self.tabs.tabs.forEach { $0.pageInteraction.cancelAll() }
            self.agentActivity.stop()
            self.isShowingImportOnboarding = false
            self.showLicenseOnboarding()
        }
        agentSessionObservation = agentActivity.$session.sink { [weak self] session in
            self?.library.setSessionActivity(.agent, active: session != nil)
        }
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
            isRestoringAccess = false
            guard !isPreviewingOnboarding else { return }
            if lookup.hasPendingRequest, hasBrowserAccess { presentRequestedLookup(); return }
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

    private func presentRequestedLookup() {
        guard !isRestoringAccess else { return }
        guard hasBrowserAccess else { showBrowser(); return }
        lookup.presentPending()
        windowController.showExpanded()
        windowController.focusForLookup()
    }

    func searchScreenRegion() {
        guard hasBrowserAccess else { showBrowser(); return }
        lookup.captureScreenRegion { windowController.showCompact(animated: false) }
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
        tabs.activeBrowser.focusAddress()
    }

    func closeTab() {
        guard hasBrowserAccess else { return }
        if tabs.isShowingLookup { windowController.showCompact(restoreLookupFocus: true); return }
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

    func focusAddress() {
        guard hasBrowserAccess else { return }
        tabs.isChromeVisible = true
        windowController.showExpanded()
        tabs.activeBrowser.focusAddress()
    }

    func showFind() {
        guard hasBrowserAccess else { return }
        tabs.isChromeVisible = true
        windowController.showExpanded()
        tabs.activeBrowser.showFind()
    }

    func reopenClosedTab() {
        guard hasBrowserAccess, tabs.reopenClosedTab() else { return }
        windowController.showExpanded()
    }

    func selectAdjacentTab(backwards: Bool = false) {
        guard hasBrowserAccess else { return }
        tabs.selectAdjacentTab(backwards: backwards)
        windowController.showExpanded()
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
                    guard license.isUnlocked else {
                        isShowingImportOnboarding = false
                        showLicenseOnboarding()
                        return
                    }
                    library.completeImportOnboarding()
                    isShowingImportOnboarding = false
                    if lookup.hasPendingRequest { presentRequestedLookup() }
                    else { windowController.showExpanded() }
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
            isRestoringAccess = false
            guard !isPreviewingOnboarding else { return }
            if !license.isUnlocked { showLicenseOnboarding() }
            else if lookup.hasPendingRequest { presentRequestedLookup() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        lookup.stop()
        agentServer?.stop()
    }

    var agentConnectionError: String? { agentServer?.startupError }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        tabs.persistSession()
        guard tabs.tabs.contains(where: { $0.webView != nil }) else { return .terminateNow }

        Task { @MainActor [weak self] in
            await self?.library.saveSessionAndWait(updateStatus: false, forceRead: true)
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
    private let lookup: BrowserLookupCoordinator
    private let onOpen: () -> Void
    private let notchController = DynamicNotchWindowController()
    private let surfaceAppearance = BrowserSurfaceAppearance()
    private var isExpanded = false
    private var isShowingOnboarding = false
    private var onboardingTask: Task<Void, Never>?
    private var expandedScreen: NSScreen?
    private var expandedWidth: CGFloat?
    private var expandedHeight: CGFloat?
    private struct ResizeContext {
        let screen: NSScreen?
        let startSize: CGSize
        let scale: CGFloat
        let widthRange: ClosedRange<CGFloat>
        let heightRange: ClosedRange<CGFloat>
    }
    private var resizeContext: ResizeContext?

    init(tabs: BrowserTabsModel, library: BrowserLibrary, activity: BrowserAgentActivity, lookup: BrowserLookupCoordinator,
         onOpen: @escaping () -> Void) {
        self.tabs = tabs
        self.library = library
        self.activity = activity
        self.lookup = lookup
        self.onOpen = onOpen
        notchController.onDismiss = { [weak self] in
            self?.restoreCompactSurfaceIfNeeded()
        }
        notchController.onWillDismiss = { [weak self] in
            guard let self, self.isExpanded else { return }
            self.tabs.activeBrowser.captureVisiblePage()
        }
        notchController.onOutsideClick = { [weak self] in
            guard let self, self.isExpanded, !self.surfaceAppearance.isPinned else { return false }
            self.showCompact()
            return true
        }
    }

    func showCompact(animated: Bool = true, restoreLookupFocus: Bool = false) {
        library.setSessionActivity(.surface, active: false)
        onboardingTask?.cancel()
        isShowingOnboarding = false
        if isExpanded && notchController.isVisible {
            tabs.activeBrowser.captureVisiblePage()
        }
        isExpanded = false
        surfaceAppearance.setPinned(false)
        surfaceAppearance.setExpanded(false, animated: animated)
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
        notchController.setKeyboardFocus(false)
        lookup.end(restoreFocus: restoreLookupFocus)
    }

    func focusForLookup() {
        guard isExpanded, !isShowingOnboarding else { return }
        notchController.setKeyboardFocus(true)
    }

    func showExpanded(animated: Bool = true) {
        onboardingTask?.cancel()
        isShowingOnboarding = false
        guard !isExpanded else { return }
        isExpanded = true
        library.setSessionActivity(.surface, active: true)
        surfaceAppearance.setExpanded(true, animated: animated)
        // Install click-away handling after the opening hover/click has
        // finished. The compact hover target and expanded surface share one
        // panel; registering the monitor synchronously can treat the opening
        // interaction as an outside click and immediately collapse it.
        notchController.dismissalPolicy = .manual

        let screen = NSScreen.main ?? NSScreen.screens.first
        let sizing = NotchBrowserSizing.resolved(
            for: screen,
            expandedWidthOverride: expandedWidth,
            expandedHeightOverride: expandedHeight
        )
        expandedScreen = screen
        expandedWidth = sizing.expandedWidth
        expandedHeight = sizing.expandedHeight
        renderExpanded(sizing: sizing, on: screen,
                       animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isExpanded else { return }
            self.updateDismissalPolicy()
        }
    }

    private func togglePinned() {
        guard isExpanded, !isShowingOnboarding else { return }
        surfaceAppearance.setPinned(!surfaceAppearance.isPinned)
        updateDismissalPolicy()
    }

    private func updateDismissalPolicy() {
        notchController.dismissalPolicy = isExpanded && !surfaceAppearance.isPinned ? .clickOutside : .manual
    }

    func showOnboarding(
        license: PolarLicenseModel,
        isPreview: Bool,
        afterDelay: Bool,
        onUnlocked: @escaping () -> Void,
        onExitPreview: @escaping () -> Void
    ) {
        lookup.end(restoreFocus: false)
        guard !isShowingOnboarding else { return }
        library.setSessionActivity(.surface, active: false)
        if isExpanded { tabs.activeBrowser.captureVisiblePage() }
        isExpanded = false
        surfaceAppearance.setPinned(false)
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
                expandedWidthOverride: self.expandedWidth,
                expandedHeightOverride: self.expandedHeight
            )
            self.expandedWidth = sizing.expandedWidth
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
        lookup.end(restoreFocus: false)
        library.setSessionActivity(.surface, active: false)
        onboardingTask?.cancel()
        if isExpanded { tabs.activeBrowser.captureVisiblePage() }
        isExpanded = false
        surfaceAppearance.setPinned(false)
        isShowingOnboarding = true
        resizeContext = nil
        notchController.dismissalPolicy = .manual
        let screen = NSScreen.main ?? NSScreen.screens.first
        let sizing = NotchBrowserSizing.resolved(
            for: screen,
            expandedWidthOverride: expandedWidth,
            expandedHeightOverride: expandedHeight
        )
        expandedWidth = sizing.expandedWidth
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
            self?.showCompact(restoreLookupFocus: true)
        }
        let resize: (CGSize) -> Void = { [weak self] translation in
            self?.resizeExpanded(by: translation)
        }
        let resizeEnded: (CGSize) -> Void = { [weak self] translation in
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
            bodyBackground: AnyView(BrowserTabsBackground(
                tabs: tabs, library: library, appearance: surfaceAppearance
            )),
            contentInsets: EdgeInsets(),
            screen: screen,
            animated: animated
        ) {
            BrowserTabsView(
                tabs: tabs,
                library: library,
                activity: self.activity,
                appearance: self.surfaceAppearance,
                lookup: self.lookup,
                onCollapse: collapse,
                onTogglePin: { [weak self] in self?.togglePinned() },
                onResize: resize,
                onResizeEnded: resizeEnded
            )
        }
    }

    private func resizeExpanded(by translation: CGSize) {
        guard isExpanded else { return }

        if resizeContext == nil {
            let screen = expandedScreen ?? NSScreen.main ?? NSScreen.screens.first
            let sizing = NotchBrowserSizing.resolved(
                for: screen,
                expandedWidthOverride: expandedWidth,
                expandedHeightOverride: expandedHeight
            )
            resizeContext = ResizeContext(
                screen: screen,
                startSize: CGSize(width: sizing.expandedWidth, height: sizing.expandedHeight),
                scale: screen?.backingScaleFactor ?? 1,
                widthRange: sizing.expandedWidthRange,
                heightRange: sizing.expandedHeightRange
            )
        }
        guard let resizeContext else { return }
        let scale = resizeContext.scale
        let requestedWidth = ((resizeContext.startSize.width + translation.width) * scale).rounded() / scale
        let requestedHeight = ((resizeContext.startSize.height + translation.height) * scale).rounded() / scale
        let width = min(max(requestedWidth, resizeContext.widthRange.lowerBound), resizeContext.widthRange.upperBound)
        let height = min(max(requestedHeight, resizeContext.heightRange.lowerBound), resizeContext.heightRange.upperBound)
        guard width != expandedWidth || height != expandedHeight else { return }
        expandedWidth = width
        expandedHeight = height
        notchController.resize(
            width: width,
            height: height,
            screen: resizeContext.screen,
            animated: false
        )
    }

    private func finishResize(by translation: CGSize) {
        resizeExpanded(by: translation)

        if let expandedWidth {
            UserDefaults.standard.set(
                Double(expandedWidth),
                forKey: NotchBrowserSizing.expandedWidthDefaultsKey
            )
        }
        if let expandedHeight {
            UserDefaults.standard.set(
                Double(expandedHeight),
                forKey: NotchBrowserSizing.expandedHeightDefaultsKey
            )
        }

        resizeContext = nil
    }

}
