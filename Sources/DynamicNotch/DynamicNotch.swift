import AppKit
import SwiftUI

private let dynamicNotchEdgeRailWidth: CGFloat = 5
private let dynamicNotchAttachedEdgeRailWidth: CGFloat = 3

/// The edge where a dynamic notch window is attached.
public enum DynamicNotchDirection: String, CaseIterable, Identifiable, Sendable {
    case top
    case bottom
    case left
    case right

    public var id: Self { self }
}

/// Alignment along the screen edge that owns the notch.
///
/// `start` is the left side of a horizontal edge and the top of a vertical
/// edge. `end` is the right side of a horizontal edge and the bottom of a
/// vertical edge.
public enum DynamicNotchEdgeAlignment: String, CaseIterable, Identifiable, Sendable {
    case start
    case center
    case end

    public var id: Self { self }
}

/// The screen placement of a dynamic notch window.
public enum DynamicNotchPlacement: Equatable, Sendable {
    /// Attaches the notch to an edge and positions it along that edge.
    /// Positive offsets move toward `end` (right or bottom).
    case edge(
        DynamicNotchDirection,
        alignment: DynamicNotchEdgeAlignment = .center,
        offset: CGFloat = 0
    )

    public var direction: DynamicNotchDirection {
        switch self {
        case let .edge(direction, _, _):
            return direction
        }
    }
}

/// The current presentation style of a dynamic notch window.
public enum DynamicNotchPresentationMode: String, CaseIterable, Identifiable, Sendable {
    case compact
    case expanded

    public var id: Self { self }
}

/// The geometry needed to create a dynamic notch surface.
public struct DynamicNotchConfiguration: Equatable, Sendable {
    public var direction: DynamicNotchDirection
    public var width: CGFloat
    public var height: CGFloat
    public var shoulderRadius: CGFloat
    public var cornerRadius: CGFloat
    /// The transparent layout rail on the edge where the notch is attached.
    /// Top and bottom notches default to a 3pt rail; side notches do not add
    /// another rail because their existing vertical rails already protect the
    /// exposed shoulders.
    public var attachedEdgeRail: CGFloat

    public init(
        direction: DynamicNotchDirection = .top,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat? = nil,
        shoulderRadius: CGFloat? = nil,
        attachedEdgeRail: CGFloat? = nil
    ) {
        self.direction = direction
        self.width = Self.validDimension(width)
        self.height = Self.validDimension(height)

        let maximumCornerRadius = min(self.width, self.height) / 2
        let maximumShoulderRadius = min(self.width, self.height) / 4
        let defaultCornerRadius = min(24, maximumCornerRadius)
        let defaultShoulderRadius = min(30, maximumShoulderRadius)
        self.cornerRadius = min(
            max(0, cornerRadius ?? defaultCornerRadius),
            maximumCornerRadius
        )
        self.shoulderRadius = min(
            max(0, shoulderRadius ?? (cornerRadius ?? defaultShoulderRadius)),
            maximumShoulderRadius
        )

        let defaultAttachedEdgeRail: CGFloat
        switch direction {
        case .top, .bottom:
            defaultAttachedEdgeRail = dynamicNotchAttachedEdgeRailWidth
        case .left, .right:
            defaultAttachedEdgeRail = 0
        }
        let maximumRail: CGFloat
        switch direction {
        case .top, .bottom:
            maximumRail = max(0, self.height - 1)
        case .left, .right:
            maximumRail = max(0, self.width - 1)
        }
        self.attachedEdgeRail = min(
            Self.validRail(attachedEdgeRail ?? defaultAttachedEdgeRail),
            maximumRail
        )
    }

    private static func validDimension(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        return max(1, value)
    }

    private static func validRail(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}

enum DynamicNotchContentGeometry {
    static func curveSafeInsets(
        for configuration: DynamicNotchConfiguration
    ) -> EdgeInsets {
        // Keep the rectangular content boundary inside both the inward
        // shoulder and the rounded exposed corner. The attached-edge rail owns
        // vertical placement for top/bottom notches, so no opposite-side
        // padding is introduced here.
        let alongEdgeInset = configuration.shoulderRadius + configuration.cornerRadius

        switch configuration.direction {
        case .top, .bottom:
            return EdgeInsets(
                top: 0,
                leading: alongEdgeInset,
                bottom: 0,
                trailing: alongEdgeInset
            )
        case .left, .right:
            return EdgeInsets(
                top: alongEdgeInset,
                leading: 0,
                bottom: alongEdgeInset,
                trailing: 0
            )
        }
    }
}

enum DynamicNotchSafeAreaResolver {
    static func attachedEdgeRail(
        for direction: DynamicNotchDirection,
        override: CGFloat?,
        safeAreaInsets: NSEdgeInsets
    ) -> CGFloat {
        if let override {
            guard override.isFinite else { return 0 }
            return max(0, override)
        }

        switch direction {
        case .top:
            return max(dynamicNotchAttachedEdgeRailWidth, safeAreaInsets.top)
        case .bottom:
            return max(dynamicNotchAttachedEdgeRailWidth, safeAreaInsets.bottom)
        case .left, .right:
            return 0
        }
    }

    static func compactHeight(
        override: CGFloat?,
        statusBarThickness: CGFloat,
        safeAreaInsets: NSEdgeInsets
    ) -> CGFloat {
        if let override {
            guard override.isFinite else { return 1 }
            return max(1, override)
        }

        return max(1, statusBarThickness, safeAreaInsets.top)
    }

    static func compactCenterGap(
        override: CGFloat?,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?
    ) -> CGFloat {
        if let override {
            guard override.isFinite else { return 0 }
            return max(0, override)
        }

        guard
            let auxiliaryTopLeftArea,
            let auxiliaryTopRightArea
        else {
            return 0
        }

        return max(0, auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX)
    }
}

enum DynamicNotchWindowGeometry {
    static func frame(
        for configuration: DynamicNotchConfiguration,
        placement: DynamicNotchPlacement,
        in screenFrame: CGRect
    ) -> CGRect {
        switch placement {
        case let .edge(direction, alignment, offset):
            switch direction {
            case .top, .bottom:
                let available = max(0, screenFrame.width - configuration.width)
                let distanceFromStart = clampedDistance(
                    available: available,
                    alignment: alignment,
                    offset: offset
                )
                return CGRect(
                    x: screenFrame.minX + distanceFromStart,
                    y: direction == .top
                        ? screenFrame.maxY - configuration.height
                        : screenFrame.minY,
                    width: configuration.width,
                    height: configuration.height
                )

            case .left, .right:
                let available = max(0, screenFrame.height - configuration.height)
                let distanceFromTop = clampedDistance(
                    available: available,
                    alignment: alignment,
                    offset: offset
                )
                return CGRect(
                    x: direction == .left
                        ? screenFrame.minX
                        : screenFrame.maxX - configuration.width,
                    y: screenFrame.maxY - configuration.height - distanceFromTop,
                    width: configuration.width,
                    height: configuration.height
                )
            }
        }
    }

    private static func clampedDistance(
        available: CGFloat,
        alignment: DynamicNotchEdgeAlignment,
        offset: CGFloat
    ) -> CGFloat {
        let base: CGFloat
        switch alignment {
        case .start:
            base = 0
        case .center:
            base = available / 2
        case .end:
            base = available
        }

        let finiteOffset = offset.isFinite ? offset : 0
        return min(max(0, base + finiteOffset), available)
    }
}

/// A notch silhouette with an edge-attached outer lip, curved shoulder
/// transitions, and a rounded exposed edge. This is also used by the window
/// controller for hit testing.
public struct DynamicNotchShape: Shape {
    public var direction: DynamicNotchDirection
    public var shoulderRadius: CGFloat
    public var cornerRadius: CGFloat

    public init(
        direction: DynamicNotchDirection = .top,
        cornerRadius: CGFloat,
        shoulderRadius: CGFloat? = nil
    ) {
        self.direction = direction
        self.shoulderRadius = max(0, shoulderRadius ?? cornerRadius)
        self.cornerRadius = max(0, cornerRadius)
    }

    public var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }

        let canonicalWidth: CGFloat
        let canonicalHeight: CGFloat
        switch direction {
        case .top, .bottom:
            canonicalWidth = rect.width
            canonicalHeight = rect.height
        case .left, .right:
            // The canonical path is top-attached. For side directions, its
            // along-edge and inward dimensions are swapped before transforming
            // it into the destination rectangle.
            canonicalWidth = rect.height
            canonicalHeight = rect.width
        }

        let shoulder = min(
            shoulderRadius,
            canonicalWidth / 4,
            canonicalHeight / 4
        )
        let exposed = min(
            cornerRadius,
            canonicalWidth / 4,
            canonicalHeight / 2
        )

        let canonicalPath = Self.topPath(
            in: CGRect(x: 0, y: 0, width: canonicalWidth, height: canonicalHeight),
            shoulder: shoulder,
            exposed: exposed
        )

        switch direction {
        case .top:
            return canonicalPath.applying(
                CGAffineTransform(translationX: rect.minX, y: rect.minY)
            )
        case .bottom:
            return canonicalPath.applying(
                CGAffineTransform(
                    a: 1,
                    b: 0,
                    c: 0,
                    d: -1,
                    tx: rect.minX,
                    ty: rect.maxY
                )
            )
        case .left:
            return canonicalPath.applying(
                CGAffineTransform(
                    a: 0,
                    b: 1,
                    c: 1,
                    d: 0,
                    tx: rect.minX,
                    ty: rect.minY
                )
            )
        case .right:
            return canonicalPath.applying(
                CGAffineTransform(
                    a: 0,
                    b: 1,
                    c: -1,
                    d: 0,
                    tx: rect.maxX,
                    ty: rect.minY
                )
            )
        }
    }

    /// The attached edge is the widest part of the surface. Each side curves
    /// inward into the narrower body before the exposed bottom corners begin.
    private static func topPath(
        in rect: CGRect,
        shoulder: CGFloat,
        exposed: CGFloat
    ) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder),
            control: CGPoint(x: rect.minX + shoulder, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - exposed))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulder + exposed, y: rect.maxY),
            control: CGPoint(x: rect.minX + shoulder, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - shoulder - exposed, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - exposed),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + shoulder))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }

}

/// A reusable SwiftUI notch surface.
///
/// Use this directly when your app already owns the containing window. For an
/// always-on-top edge window, use ``DynamicNotchWindowController`` instead.
public struct DynamicNotch<Content: View>: View {
    private let configuration: DynamicNotchConfiguration
    private let background: Color
    private let contentInsets: EdgeInsets
    private let content: () -> Content

    public init(
        direction: DynamicNotchDirection = .top,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat? = nil,
        shoulderRadius: CGFloat? = nil,
        attachedEdgeRail: CGFloat? = nil,
        background: Color = .black,
        contentInsets: EdgeInsets = EdgeInsets(),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.configuration = DynamicNotchConfiguration(
            direction: direction,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            shoulderRadius: shoulderRadius,
            attachedEdgeRail: attachedEdgeRail
        )
        self.background = background
        self.contentInsets = contentInsets
        self.content = content
    }

    public var body: some View {
        let shape = DynamicNotchShape(
            direction: configuration.direction,
            cornerRadius: configuration.cornerRadius,
            shoulderRadius: configuration.shoulderRadius
        )

        ZStack {
            shape.fill(background)

            contentBoundary
        }
        .frame(width: configuration.width, height: configuration.height)
        .clipShape(shape)
        .contentShape(shape)
    }

    /// The content cannot use the full outer rectangle: at the shoulder
    /// transitions that rectangle includes pixels outside the notch body.
    /// Keep the body finite and reserve fixed rails so intrinsic SwiftUI views
    /// cannot negotiate an ideal width past the curve.
    @ViewBuilder
    private var contentBoundary: some View {
        Group {
            switch configuration.direction {
            case .top:
                VStack(spacing: 0) {
                    attachedEdgeRail
                    horizontalContentBoundary(height: horizontalBodyHeight)
                }
            case .bottom:
                VStack(spacing: 0) {
                    horizontalContentBoundary(height: horizontalBodyHeight)
                    attachedEdgeRail
                }
            case .left, .right:
                VStack(spacing: 0) {
                    edgeRail
                        .frame(width: interiorWidth, height: dynamicNotchEdgeRailWidth)

                    contentBody(width: interiorWidth, height: sideBodyHeight)

                    edgeRail
                        .frame(width: interiorWidth, height: dynamicNotchEdgeRailWidth)
                }
            }
        }
        .frame(width: interiorWidth, height: interiorHeight, alignment: .topLeading)
        .padding(curveSafeInsets)
        .frame(
            width: configuration.width,
            height: configuration.height,
            alignment: .topLeading
        )
        .clipped()
    }

    private func horizontalContentBoundary(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            edgeRail
                .frame(width: dynamicNotchEdgeRailWidth, height: height)

            contentBody(width: horizontalBodyWidth, height: height)

            edgeRail
                .frame(width: dynamicNotchEdgeRailWidth, height: height)
        }
        .frame(width: interiorWidth, height: height, alignment: .center)
    }

    private var attachedEdgeRail: some View {
        Color.clear
            .frame(width: interiorWidth, height: configuration.attachedEdgeRail)
    }

    private var edgeRail: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func contentBody(width: CGFloat, height: CGFloat) -> some View {
        let contentWidth = max(
            1,
            width - contentInsets.leading - contentInsets.trailing
        )
        let contentHeight = max(
            1,
            height - contentInsets.top - contentInsets.bottom
        )

        return content()
            .frame(width: contentWidth, height: contentHeight, alignment: .center)
            .padding(contentInsets)
            .frame(width: width, height: height, alignment: .center)
            .clipped()
    }

    private var interiorWidth: CGFloat {
        max(
            1,
            configuration.width - curveSafeInsets.leading - curveSafeInsets.trailing
        )
    }

    private var interiorHeight: CGFloat {
        max(
            1,
            configuration.height - curveSafeInsets.top - curveSafeInsets.bottom
        )
    }

    private var horizontalBodyWidth: CGFloat {
        max(1, interiorWidth - (dynamicNotchEdgeRailWidth * 2))
    }

    private var horizontalBodyHeight: CGFloat {
        max(1, interiorHeight - configuration.attachedEdgeRail)
    }

    private var sideBodyHeight: CGFloat {
        max(1, interiorHeight - (dynamicNotchEdgeRailWidth * 2))
    }

    /// The body starts after the inward shoulder curves and stays clear of the
    /// rounded exposed edge. The values are directional because side notches
    /// need vertical protection while top/bottom notches need horizontal
    /// protection.
    private var curveSafeInsets: EdgeInsets {
        DynamicNotchContentGeometry.curveSafeInsets(for: configuration)
    }
}

/// An iOS Dynamic Island-style compact surface with content on both sides of
/// the physical camera notch.
///
/// The surface remains one continuous shape. `centerGap` reserves layout space
/// for the camera housing without introducing a transparent cutout.
public struct DynamicNotchCompact<Leading: View, Trailing: View>: View {
    private let configuration: DynamicNotchConfiguration
    private let centerGap: CGFloat
    private let background: Color
    private let contentInsets: EdgeInsets
    private let leading: () -> Leading
    private let trailing: () -> Trailing

    public init(
        direction: DynamicNotchDirection = .top,
        width: CGFloat,
        height: CGFloat,
        centerGap: CGFloat,
        cornerRadius: CGFloat? = nil,
        shoulderRadius: CGFloat? = nil,
        background: Color = .black,
        contentInsets: EdgeInsets = EdgeInsets(),
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.configuration = DynamicNotchConfiguration(
            direction: direction,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            shoulderRadius: shoulderRadius,
            attachedEdgeRail: 0
        )
        self.centerGap = centerGap.isFinite ? max(0, centerGap) : 0
        self.background = background
        self.contentInsets = contentInsets
        self.leading = leading
        self.trailing = trailing
    }

    public var body: some View {
        let shape = DynamicNotchShape(
            direction: configuration.direction,
            cornerRadius: configuration.cornerRadius,
            shoulderRadius: configuration.shoulderRadius
        )

        ZStack {
            shape.fill(background)

            HStack(spacing: 0) {
                leading()
                    .frame(
                        width: sideLaneWidth,
                        height: contentHeight,
                        alignment: .trailing
                    )
                    .clipped()

                Color.clear
                    .frame(width: resolvedCenterGap, height: contentHeight)

                trailing()
                    .frame(
                        width: sideLaneWidth,
                        height: contentHeight,
                        alignment: .leading
                    )
                    .clipped()
            }
            .frame(width: contentWidth, height: contentHeight)
            .padding(contentInsets)
            .frame(
                width: contentFrameWidth,
                height: configuration.height,
                alignment: .center
            )
        }
        .frame(width: configuration.width, height: configuration.height)
        .clipShape(shape)
        .contentShape(shape)
    }

    private var outerHorizontalInset: CGFloat {
        configuration.shoulderRadius
            + configuration.cornerRadius
            + dynamicNotchEdgeRailWidth
    }

    private var contentWidth: CGFloat {
        max(
            1,
            contentFrameWidth
                - contentInsets.leading
                - contentInsets.trailing
        )
    }

    private var contentFrameWidth: CGFloat {
        max(1, configuration.width - (outerHorizontalInset * 2))
    }

    private var contentHeight: CGFloat {
        max(
            1,
            configuration.height - contentInsets.top - contentInsets.bottom
        )
    }

    private var resolvedCenterGap: CGFloat {
        min(centerGap, contentWidth)
    }

    private var sideLaneWidth: CGFloat {
        max(0, (contentWidth - resolvedCenterGap) / 2)
    }
}

@MainActor
public final class DynamicNotchWindowController: NSObject {
    private var panel: DynamicNotchPanel?
    private var contentView: DynamicNotchWindowContentView?
    private var hostingView: NSHostingView<AnyView>?
    private var hideGeneration = 0

    public private(set) var isVisible = false
    public private(set) var configuration: DynamicNotchConfiguration?
    public private(set) var placement: DynamicNotchPlacement?
    public private(set) var presentationMode: DynamicNotchPresentationMode?

    public override init() {
        super.init()
    }

    /// Presents the supplied SwiftUI content at the requested screen edge.
    /// Calling `show` again updates both the content and the window geometry.
    public func show<Content: View>(
        direction: DynamicNotchDirection = .top,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat? = nil,
        shoulderRadius: CGFloat? = nil,
        attachedEdgeRail: CGFloat? = nil,
        background: Color = .black,
        contentInsets: EdgeInsets = EdgeInsets(),
        screen: NSScreen? = nil,
        animated: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        show(
            placement: .edge(direction),
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            shoulderRadius: shoulderRadius,
            attachedEdgeRail: attachedEdgeRail,
            background: background,
            contentInsets: contentInsets,
            screen: screen,
            animated: animated,
            content: content
        )
    }

    /// Presents content at an aligned position along a screen edge. When
    /// `attachedEdgeRail` is nil, the selected screen's safe area is reserved
    /// automatically on top and bottom edges.
    public func show<Content: View>(
        placement: DynamicNotchPlacement,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat? = nil,
        shoulderRadius: CGFloat? = nil,
        attachedEdgeRail: CGFloat? = nil,
        background: Color = .black,
        contentInsets: EdgeInsets = EdgeInsets(),
        screen: NSScreen? = nil,
        animated: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        let targetScreen = resolvedScreen(screen)
        let resolvedRail = DynamicNotchSafeAreaResolver.attachedEdgeRail(
            for: placement.direction,
            override: attachedEdgeRail,
            safeAreaInsets: targetScreen?.safeAreaInsets ?? NSEdgeInsets()
        )
        let nextConfiguration = DynamicNotchConfiguration(
            direction: placement.direction,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            shoulderRadius: shoulderRadius,
            attachedEdgeRail: resolvedRail
        )
        let rootView = DynamicNotch(
            direction: nextConfiguration.direction,
            width: nextConfiguration.width,
            height: nextConfiguration.height,
            cornerRadius: nextConfiguration.cornerRadius,
            shoulderRadius: nextConfiguration.shoulderRadius,
            attachedEdgeRail: nextConfiguration.attachedEdgeRail,
            background: background,
            contentInsets: contentInsets,
            content: content
        )

        presentationMode = .expanded
        present(
            rootView: AnyView(rootView),
            configuration: nextConfiguration,
            placement: placement,
            screen: targetScreen,
            animated: animated
        )
    }

    /// Presents a compact top notch with separate leading and trailing regions
    /// around the physical camera housing. The height and center gap are read
    /// from the selected screen unless explicitly overridden.
    public func showCompact<Leading: View, Trailing: View>(
        width: CGFloat,
        height: CGFloat? = nil,
        centerGap: CGFloat? = nil,
        cornerRadius: CGFloat? = nil,
        shoulderRadius: CGFloat? = nil,
        background: Color = .black,
        contentInsets: EdgeInsets = EdgeInsets(),
        screen: NSScreen? = nil,
        animated: Bool = true,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        let targetScreen = resolvedScreen(screen)
        let safeAreaInsets = targetScreen?.safeAreaInsets ?? NSEdgeInsets()
        let resolvedHeight = DynamicNotchSafeAreaResolver.compactHeight(
            override: height,
            statusBarThickness: NSStatusBar.system.thickness,
            safeAreaInsets: safeAreaInsets
        )
        let resolvedCenterGap = DynamicNotchSafeAreaResolver.compactCenterGap(
            override: centerGap,
            auxiliaryTopLeftArea: targetScreen?.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: targetScreen?.auxiliaryTopRightArea
        )
        let compactPlacement = DynamicNotchPlacement.edge(.top)
        let nextConfiguration = DynamicNotchConfiguration(
            direction: .top,
            width: width,
            height: resolvedHeight,
            cornerRadius: cornerRadius,
            shoulderRadius: shoulderRadius,
            attachedEdgeRail: 0
        )
        let rootView = DynamicNotchCompact(
            direction: .top,
            width: nextConfiguration.width,
            height: nextConfiguration.height,
            centerGap: resolvedCenterGap,
            cornerRadius: nextConfiguration.cornerRadius,
            shoulderRadius: nextConfiguration.shoulderRadius,
            background: background,
            contentInsets: contentInsets,
            leading: leading,
            trailing: trailing
        )

        presentationMode = .compact
        present(
            rootView: AnyView(rootView),
            configuration: nextConfiguration,
            placement: compactPlacement,
            screen: targetScreen,
            animated: animated
        )
    }

    private func present(
        rootView: AnyView,
        configuration nextConfiguration: DynamicNotchConfiguration,
        placement: DynamicNotchPlacement,
        screen: NSScreen?,
        animated: Bool
    ) {
        configuration = nextConfiguration
        self.placement = placement
        hideGeneration &+= 1

        let panel = makePanelIfNeeded()

        let surface = contentView ?? DynamicNotchWindowContentView(
            shape: DynamicNotchShape(
                direction: nextConfiguration.direction,
                cornerRadius: nextConfiguration.cornerRadius,
                shoulderRadius: nextConfiguration.shoulderRadius
            )
        )

        if contentView == nil {
            panel.contentView = surface
            contentView = surface
        } else {
            surface.updateShape(
                direction: nextConfiguration.direction,
                cornerRadius: nextConfiguration.cornerRadius,
                shoulderRadius: nextConfiguration.shoulderRadius
            )
        }

        if let hostingView {
            hostingView.rootView = AnyView(rootView)
        } else {
            let newHostingView = NSHostingView(rootView: AnyView(rootView))
            newHostingView.sizingOptions = []
            newHostingView.autoresizingMask = []
            newHostingView.wantsLayer = true
            newHostingView.layer?.backgroundColor = NSColor.clear.cgColor
            surface.installHostingView(newHostingView)
            hostingView = newHostingView
        }

        let targetFrame = DynamicNotchWindowGeometry.frame(
            for: nextConfiguration,
            placement: placement,
            in: screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        )
        setFrame(targetFrame, on: panel, animated: animated && isVisible)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        isVisible = true
    }

    private func resolvedScreen(_ screen: NSScreen?) -> NSScreen? {
        screen ?? NSScreen.main ?? panel?.screen ?? NSScreen.screens.first
    }

    /// Removes the notch window. The controller remains reusable.
    public func hide(animated: Bool = true) {
        guard let panel else {
            isVisible = false
            return
        }

        hideGeneration &+= 1
        let generation = hideGeneration

        guard animated, panel.isVisible else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            isVisible = false
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                guard let self, let panel, self.hideGeneration == generation else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                self.isVisible = false
            }
        }
    }

    private func makePanelIfNeeded() -> DynamicNotchPanel {
        if let panel { return panel }

        let panel = DynamicNotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        self.panel = panel
        return panel
    }

    private func setFrame(_ targetFrame: NSRect, on panel: NSPanel, animated: Bool) {
        guard animated, panel.isVisible else {
            panel.setFrame(targetFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }
}

private final class DynamicNotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class DynamicNotchWindowContentView: NSView {
    private var shape: DynamicNotchShape
    private var shapePath: CGPath?
    private var hostingClipView: DynamicNotchHostingClipView?

    init(shape: DynamicNotchShape) {
        self.shape = shape
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func updateShape(
        direction: DynamicNotchDirection,
        cornerRadius: CGFloat,
        shoulderRadius: CGFloat
    ) {
        shape = DynamicNotchShape(
            direction: direction,
            cornerRadius: cornerRadius,
            shoulderRadius: shoulderRadius
        )
        updateShapePath()
        needsLayout = true
    }

    func installHostingView(_ view: NSView) {
        let clipView = DynamicNotchHostingClipView(hostingView: view)
        hostingClipView = clipView
        addSubview(clipView)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        updateShapePath()
        hostingClipView?.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard shapePath?.contains(point) != false else { return nil }
        return super.hitTest(point)
    }

    private func updateShapePath() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        shapePath = shape.path(in: bounds).cgPath
    }
}

private final class DynamicNotchHostingClipView: NSView {
    private let hostingView: NSView

    init(hostingView: NSView) {
        self.hostingView = hostingView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        addSubview(hostingView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }
}
