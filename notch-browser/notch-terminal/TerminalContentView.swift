import AppKit
import SwiftUI

struct TerminalContentView: View {
    @ObservedObject var workspace: TerminalTabsModel
    let onCollapse: () -> Void
    let onResize: (CGFloat) -> Void
    let onResizeEnded: (CGFloat) -> Void

    private var terminal: TerminalModel {
        workspace.selectedTab
    }

    var body: some View {
        VStack(spacing: 0) {
            terminalTabsRow
            terminalToolbar
            GhosttyTerminalView(model: terminal)
                .id(terminal.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NotchTerminalPalette.background)
        }
        .foregroundStyle(NotchTerminalPalette.foreground)
        .background(NotchTerminalPalette.background)
        .overlay(alignment: .bottom) {
            TerminalResizeHandle(
                onResize: onResize,
                onResizeEnded: onResizeEnded
            )
                .padding(.bottom, 4)
        }
        .onChange(of: workspace.selectedTabID) { _, _ in
            // Wait for SwiftUI to attach the newly selected NSView before
            // requesting focus, otherwise the first keystroke can be lost.
            DispatchQueue.main.async {
                workspace.selectedTab.focusIfPossible()
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                workspace.selectedTab.focusIfPossible()
            }
        }
    }

    private var terminalTabsRow: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(workspace.tabs) { tab in
                        TerminalTabItem(
                            terminal: tab,
                            isSelected: tab.id == workspace.selectedTabID,
                            canClose: workspace.tabs.count > 1,
                            onSelect: { workspace.selectTab(tab.id) },
                            onClose: { workspace.closeTab(tab.id) }
                        )
                    }
                }
            }

            Button(action: { workspace.addTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(NotchTerminalPalette.foreground.opacity(0.78))
            .help("New terminal tab")
            .accessibilityLabel("New terminal tab")
            .padding(.trailing, 7)
        }
        .frame(height: 34)
        .background(NotchTerminalPalette.background.opacity(0.98))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotchTerminalPalette.foreground.opacity(0.11))
                .frame(height: 1)
        }
    }

    private var terminalToolbar: some View {
        HStack(spacing: 8) {
            TerminalDirectoryPickerButton(terminal: terminal)

            Spacer()

            Text(terminal.statusText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(NotchTerminalPalette.foreground.opacity(0.48))

            Button(action: onCollapse) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Collapse terminal")
            .accessibilityLabel("Collapse terminal")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(NotchTerminalPalette.background)
    }
}

private struct TerminalTabItem: View {
    @ObservedObject var terminal: TerminalModel
    let isSelected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    private let tabWidth: CGFloat = 220

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(
                            terminal.isRunning
                                ? NotchTerminalPalette.accent
                                : NotchTerminalPalette.foreground.opacity(0.38)
                        )
                        .frame(width: 6, height: 6)

                    Text(terminal.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(
                            NotchTerminalPalette.foreground.opacity(isSelected ? 0.94 : 0.62)
                        )
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .padding(.trailing, canClose ? 36 : 12)
                .frame(width: tabWidth, height: 34, alignment: .leading)
            }
            .buttonStyle(.plain)

            if canClose && (isSelected || isHovering) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(NotchTerminalPalette.foreground.opacity(0.48))
                .help("Close \(terminal.title)")
                .accessibilityLabel("Close \(terminal.title)")
                .padding(.trailing, 8)
            }
        }
        .background(
            (isSelected
                ? NotchTerminalPalette.foreground.opacity(0.105)
                : (isHovering ? NotchTerminalPalette.foreground.opacity(0.065) : .clear))
        )
        .frame(width: tabWidth, height: 34, alignment: .leading)
        .overlay {
            Rectangle()
                .stroke(
                    NotchTerminalPalette.foreground.opacity(isSelected ? 0.28 : 0.14),
                    lineWidth: 1
                )
        }
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(NotchTerminalPalette.accent)
                    .frame(height: 2)
            }
        }
        .onHover { isHovering = $0 }
    }
}

struct CompactTerminalSurface: View {
    @ObservedObject var workspace: TerminalTabsModel
    let onExpand: () -> Void

    private var terminal: TerminalModel {
        workspace.selectedTab
    }

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .medium))

                Circle()
                    .fill(
                        terminal.isRunning
                            ? NotchTerminalPalette.accent
                            : NotchTerminalPalette.foreground.opacity(0.42)
                    )
                    .frame(width: 6, height: 6)

                Text(terminal.title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))

                Spacer(minLength: 4)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(NotchTerminalPalette.foreground)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel("Notch terminal, \(workspace.tabs.count) tabs")
        .accessibilityHint("Click to open the terminal")
        .help("Open terminal")
    }
}

private struct TerminalResizeHandle: View {
    let onResize: (CGFloat) -> Void
    let onResizeEnded: (CGFloat) -> Void

    var body: some View {
        Capsule()
            .fill(NotchTerminalPalette.accent.opacity(0.72))
            .frame(width: 42, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        onResize(value.translation.height)
                    }
                    .onEnded { value in
                        onResizeEnded(value.translation.height)
                    }
            )
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .accessibilityLabel("Resize terminal")
            .accessibilityHint("Drag vertically to change the terminal height")
            .help("Drag to resize terminal")
    }
}
