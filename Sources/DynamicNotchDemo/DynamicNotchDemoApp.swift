import AppKit
import Combine
import DynamicNotch
import SwiftUI

@main
struct DynamicNotchDemoApp: App {
    @StateObject private var model: DemoModel

    init() {
        _model = StateObject(wrappedValue: DemoModel())
    }

    var body: some Scene {
        WindowGroup("DynamicNotch Demo") {
            DemoView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
private final class DemoModel: ObservableObject {
    @Published var selectedVariant: DemoVariant = .topCompact

    let notchController = DynamicNotchWindowController()

    func select(_ variant: DemoVariant) {
        selectedVariant = variant
    }

    func showSelected() {
        show(selectedVariant)
    }

    func show(_ variant: DemoVariant) {
        selectedVariant = variant

        switch variant {
        case .topCompact:
            notchController.showCompact(
                width: variant.width,
                background: variant.background,
                contentInsets: variant.contentInsets
            ) {
                DemoCompactLeading()
            } trailing: {
                DemoCompactTrailing()
            }

        default:
            notchController.show(
                placement: .edge(
                    variant.direction,
                    alignment: .center,
                    offset: 0
                ),
                width: variant.width,
                height: variant.height,
                background: variant.background,
                contentInsets: variant.contentInsets
            ) {
                DemoNotchContent(variant: variant)
            }
        }
    }

    func hide() {
        notchController.hide()
    }
}

private enum DemoVariant: String, CaseIterable, Identifiable {
    case topCompact
    case topRecording
    case bottomPlayback
    case leftBuild
    case rightApproval

    var id: Self { self }

    var title: String {
        switch self {
        case .topCompact:
            "Top · Compact"
        case .topRecording:
            "Top · Expanded"
        case .bottomPlayback:
            "Bottom · Playback"
        case .leftBuild:
            "Left · Build progress"
        case .rightApproval:
            "Right · Approval"
        }
    }

    var detail: String {
        switch self {
        case .topCompact:
            "Leading/trailing camera-safe regions"
        case .topRecording:
            "Expanded camera-safe status"
        case .bottomPlayback:
            "Bottom-attached media control"
        case .leftBuild:
            "Vertical progress surface"
        case .rightApproval:
            "Vertical action surface"
        }
    }

    var direction: DynamicNotchDirection {
        switch self {
        case .topCompact, .topRecording:
            .top
        case .bottomPlayback:
            .bottom
        case .leftBuild:
            .left
        case .rightApproval:
            .right
        }
    }

    var width: CGFloat {
        switch self {
        case .topCompact:
            400
        case .topRecording:
            360
        case .bottomPlayback:
            360
        case .leftBuild:
            360
        case .rightApproval:
            360
        }
    }

    var height: CGFloat {
        switch self {
        case .topCompact:
            max(
                NSStatusBar.system.thickness,
                NSScreen.main?.safeAreaInsets.top ?? 0
            )
        case .topRecording:
            56
        case .bottomPlayback:
            56
        case .leftBuild:
            484
        case .rightApproval:
            484
        }
    }

    var background: Color {
        switch self {
        case .topCompact, .topRecording:
            .black
        case .bottomPlayback:
            .black
        case .leftBuild:
            .black
        case .rightApproval:
            .black
        }
    }

    var accent: Color {
        switch self {
        case .topCompact, .topRecording:
            .white
        case .bottomPlayback:
            .white
        case .leftBuild:
            .white
        case .rightApproval:
            .white
        }
    }

    var contentInsets: EdgeInsets {
        if self == .topCompact {
            return EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)
        }

        switch direction {
        case .top, .bottom:
            return EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18)
        case .left, .right:
            return EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16)
        }
    }
}

private struct DemoView: View {
    @ObservedObject var model: DemoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DynamicNotch")
                    .font(.system(size: 24, weight: .bold))
                Text("Choose a geometry variant, preview it here, then show it at the screen edge.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            preview

            VStack(alignment: .leading, spacing: 10) {
                Text("TEST VARIANTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                ForEach(DemoVariant.allCases) { variant in
                    variantButton(variant)
                }
            }

            HStack {
                Button("Show selected") {
                    model.showSelected()
                }
                .keyboardShortcut(.defaultAction)

                Button("Hide") {
                    model.hide()
                }

                Spacer()

                Text(model.selectedVariant.direction.rawValue.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 470)
        .onAppear {
            if !model.notchController.isVisible {
                model.showSelected()
            }
        }
        .onDisappear {
            model.hide()
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LIVE PREVIEW")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                selectedPreviewSurface
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var selectedPreviewSurface: some View {
        if model.selectedVariant == .topCompact {
            DynamicNotchCompact(
                width: model.selectedVariant.width,
                height: model.selectedVariant.height,
                centerGap: previewCompactCenterGap,
                background: model.selectedVariant.background,
                contentInsets: model.selectedVariant.contentInsets
            ) {
                DemoCompactLeading()
            } trailing: {
                DemoCompactTrailing()
            }
        } else {
            DynamicNotch(
                direction: model.selectedVariant.direction,
                width: model.selectedVariant.width,
                height: model.selectedVariant.height,
                attachedEdgeRail: previewAttachedEdgeRail,
                background: model.selectedVariant.background,
                contentInsets: model.selectedVariant.contentInsets
            ) {
                DemoNotchContent(variant: model.selectedVariant)
            }
        }
    }

    private var previewCompactCenterGap: CGFloat {
        guard
            let screen = NSScreen.main,
            let leftArea = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea
        else {
            return 0
        }

        return max(0, rightArea.minX - leftArea.maxX)
    }

    private var previewAttachedEdgeRail: CGFloat? {
        switch model.selectedVariant.direction {
        case .top:
            return max(3, NSScreen.main?.safeAreaInsets.top ?? 0)
        case .bottom:
            return 3
        case .left, .right:
            return nil
        }
    }

    private func variantButton(_ variant: DemoVariant) -> some View {
        Button {
            model.select(variant)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(variant.accent)
                    .frame(width: 9, height: 9)

                VStack(alignment: .leading, spacing: 3) {
                    Text(variant.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(variant.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(variant.width)) × \(Int(variant.height))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                model.selectedVariant == variant
                    ? variant.accent.opacity(0.14)
                    : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        model.selectedVariant == variant
                            ? variant.accent.opacity(0.55)
                            : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

@ViewBuilder
private func DemoNotchContent(variant: DemoVariant) -> some View {
    switch variant {
    case .topCompact:
        EmptyView()

    case .topRecording:
        HStack(spacing: 10) {
            Circle()
                .fill(variant.accent)
                .frame(width: 9, height: 9)
            Text("Recording")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Text("00:42")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)

    case .bottomPlayback:
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(variant.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Midnight City")
                    .font(.system(size: 13, weight: .semibold))
                Text("M83 · Playing")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 8)
            Image(systemName: "pause.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(variant.accent)
        }
        .foregroundStyle(.white)

    case .leftBuild:
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "hammer.fill")
                    .foregroundStyle(variant.accent)
                Text("Building project")
                    .font(.system(size: 13, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("DynamicNotchDemo")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.62))
                ProgressView(value: 0.68)
                    .tint(variant.accent)
                Text("68% · Compiling Swift files")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)

    case .rightApproval:
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(variant.accent)
                Text("Approval required")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("Allow the build script to continue?")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Button("Deny") {}
                    .buttonStyle(.bordered)
                Spacer()
                Button("Allow") {}
                    .buttonStyle(.borderedProminent)
                    .tint(variant.accent)
            }
        }
        .foregroundStyle(.white)
    }
}

private func DemoCompactLeading() -> some View {
    HStack(spacing: 6) {
        Circle()
            .fill(.green)
            .frame(width: 7, height: 7)
        Text("Live")
            .font(.system(size: 11, weight: .semibold))
    }
    .foregroundStyle(.white)
    .padding(.trailing, 8)
}

private func DemoCompactTrailing() -> some View {
    HStack(spacing: 7) {
        Image(systemName: "waveform")
            .font(.system(size: 10, weight: .semibold))
        Text("00:42")
            .font(.system(size: 10, design: .monospaced))
    }
    .foregroundStyle(.white.opacity(0.78))
    .padding(.leading, 8)
}
