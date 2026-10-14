import AppKit
import Combine
import DynamicNotch
import SwiftUI
import UniformTypeIdentifiers

struct BrowserTabsView: View {
    @ObservedObject var tabs: BrowserTabsModel
    @ObservedObject var library: BrowserLibrary
    @ObservedObject var activity: BrowserAgentActivity
    @ObservedObject var appearance: BrowserSurfaceAppearance
    let onCollapse: () -> Void
    let onResize: (CGSize) -> Void
    let onResizeEnded: (CGSize) -> Void

    var body: some View {
        ContentView(
            browser: tabs.activeBrowser,
            tabs: tabs,
            library: library,
            activity: activity,
            appearance: appearance,
            onCollapse: onCollapse,
            onResize: onResize,
            onResizeEnded: onResizeEnded
        )
        .id(tabs.activeTabID)
    }
}

@MainActor
final class BrowserSurfaceAppearance: ObservableObject {
    @Published private(set) var backgroundOpacity: Double = 0

    func setExpanded(_ expanded: Bool, animated: Bool) {
        let animation: Animation? = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeInOut(duration: 0.30) : nil
        withAnimation(animation) {
            backgroundOpacity = expanded ? 1 : 0
        }
    }
}

/// The start-page image covers the whole notch, including the screen edge.
/// Its opacity fades during collapse while the existing surface is retained.
struct BrowserTabsBackground: View {
    @ObservedObject var tabs: BrowserTabsModel
    @ObservedObject var library: BrowserLibrary
    @ObservedObject var appearance: BrowserSurfaceAppearance

    var body: some View {
        BrowserSurfaceBackground(browser: tabs.activeBrowser, library: library)
            .opacity(appearance.backgroundOpacity)
    }
}

private struct BrowserSurfaceBackground: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var library: BrowserLibrary

    var body: some View {
        if browser.isEmpty {
            StartPageBackground(selection: library.startBackground, customImage: library.customBackgroundImage)
        } else {
            Color.black
        }
    }
}

struct ContentView: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var tabs: BrowserTabsModel
    @ObservedObject var library: BrowserLibrary
    @ObservedObject var activity: BrowserAgentActivity
    @ObservedObject var appearance: BrowserSurfaceAppearance
    @Environment(\.dynamicNotchSafeContentInsets) private var safeContentInsets
    let onCollapse: () -> Void
    let onResize: (CGSize) -> Void
    let onResizeEnded: (CGSize) -> Void
    @State private var isRevealed = false
    @State private var isPageSnapshotVisible = true
    @State private var snapshotRevealTask: Task<Void, Never>?

    private var isChromeVisible: Bool { tabs.isChromeVisible }
    private var isEmbeddedPage: Bool { !isChromeVisible && !browser.isEmpty }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if isChromeVisible {
                    VStack(spacing: 0) {
                        tabStrip
                        if browser.isEmpty {
                            newTabPage
                        } else {
                            browserToolbar
                            errorBanner
                            browserPage
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    Group {
                        if browser.isEmpty {
                            newTabPage
                        } else {
                            browserPage
                        }
                    }
                    .transition(.opacity)
                }
            }

            if !isChromeVisible {
                HStack(spacing: 8) {
                    BrowserAgentActivityView(activity: activity)
                        .fixedSize()

                    Button(action: showBrowserChrome) {
                        Image(systemName: "eye")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
                    .help("Show browser controls")
                    .accessibilityLabel("Show browser controls")
                }
                .padding(.top, 5 + (isEmbeddedPage ? safeContentInsets.top : 0))
                .padding(.trailing, 5 + (isEmbeddedPage ? safeContentInsets.trailing : 0))
                .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .opacity(isRevealed ? appearance.backgroundOpacity : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.24), value: isChromeVisible)
        .overlay(alignment: .bottomLeading) {
            BrowserResizeHandle(
                corner: .bottomLeft,
                foreground: .white,
                onResize: onResize,
                onResizeEnded: onResizeEnded
            )
            .shadow(color: .black.opacity(isEmbeddedPage ? 0.45 : 0), radius: 1)
            .padding(.leading, isEmbeddedPage ? safeContentInsets.leading : 0)
            .padding(.bottom, 4)
        }
        .overlay(alignment: .bottomTrailing) {
            BrowserResizeHandle(
                corner: .bottomRight,
                foreground: .white,
                onResize: onResize,
                onResizeEnded: onResizeEnded
            )
            .shadow(color: .black.opacity(isEmbeddedPage ? 0.45 : 0), radius: 1)
            .padding(.trailing, isEmbeddedPage ? safeContentInsets.trailing : 0)
            .padding(.bottom, 4)
        }
        .dynamicNotchEdgeToEdgeContent(isEmbeddedPage)
        .onAppear {
            withAnimation(.easeOut(duration: 0.18)) {
                isRevealed = true
            }
            browser.prepareForPresentation()
            snapshotRevealTask?.cancel()
            snapshotRevealTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                revealLivePage()
            }
        }
        .onReceive(browser.$isPresentationReady) { ready in
            if ready && isRevealed { revealLivePage() }
        }
        .onDisappear {
            snapshotRevealTask?.cancel()
        }
    }

    private func revealLivePage() {
        snapshotRevealTask?.cancel()
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.10)) {
            isPageSnapshotVisible = false
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabs.tabs, id: \.id) { tab in
                            BrowserTabItem(
                                browser: tab,
                                isActive: tab.id == tabs.activeTabID,
                                onSelect: { tabs.selectTab(tab.id) },
                                onClose: { tabs.closeTab(tab.id) }
                            )
                            .id(tab.id)
                        }

                        Button(action: tabs.addTab) {
                            Image(systemName: "plus")
                                .frame(width: 28, height: 29)
                        }
                        .help("New tab")
                        .accessibilityLabel("New tab")
                        .id("new-tab")
                    }
                }
                .onAppear { revealActiveTab(using: proxy) }
                .onChange(of: tabs.tabs.count) { _ in revealActiveTab(using: proxy) }
            }

            Button(action: toggleBrowserChrome) {
                Image(systemName: "eye.slash")
                    .frame(width: 24, height: 24)
            }
            .help("Hide browser controls")
            .accessibilityLabel("Hide browser controls")

            BrowserDownloadsButton()

            Button(action: onCollapse) {
                Image(systemName: "chevron.up")
                    .frame(width: 24, height: 24)
            }
            .help("Collapse browser")
            .accessibilityLabel("Collapse browser")

            BrowserAgentActivityView(activity: activity)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(browser.isEmpty ? 0.18 : 1))
    }

    private func revealActiveTab(using proxy: ScrollViewProxy) {
        if tabs.activeTabID == tabs.tabs.last?.id {
            proxy.scrollTo("new-tab", anchor: .trailing)
        } else {
            proxy.scrollTo(tabs.activeTabID, anchor: .trailing)
        }
    }

    private var newTabPage: some View {
        BrowserStartPage(browser: browser, library: library)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL, .url], isTargeted: nil) { providers in
            BrowserAssetDrop.receive(providers) { urls in
                for (index, url) in urls.enumerated() {
                    let target = index == 0 ? browser : tabs.newTab(select: false)
                    target.navigate(to: url)
                }
            }
        }
    }

    private var browserPage: some View {
        ZStack {
            BrowserWebView(browser: browser)
            if isPageSnapshotVisible, let snapshot = browser.lastPageSnapshot {
                GeometryReader { geometry in
                    Image(nsImage: snapshot)
                        .resizable()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage = browser.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
        }
    }

    private func showBrowserChrome() {
        withAnimation(.easeInOut(duration: 0.24)) {
            tabs.isChromeVisible = true
        }
    }

    private func toggleBrowserChrome() {
        withAnimation(.easeInOut(duration: 0.24)) {
            tabs.isChromeVisible.toggle()
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 7) {
            Button(action: browser.goBack) {
                Image(systemName: "chevron.backward")
            }
            .disabled(!browser.canGoBack)

            Button(action: browser.goForward) {
                Image(systemName: "chevron.forward")
            }
            .disabled(!browser.canGoForward)

            Button(action: browser.reload) {
                Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
            }

            BrowserAddressField(
                text: $browser.addressText,
                font: .systemFont(ofSize: 12),
                textColor: .white,
                placeholder: "Search \(library.searchEngine.name) or enter a URL",
                onSubmit: browser.submitAddress
            )
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.black, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))

            bookmarkButton
            bookmarksMenu

        }
        .buttonStyle(.borderless)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    private var bookmarkButton: some View {
        Button(action: toggleCurrentBookmark) {
            Image(systemName: library.isBookmarked(url: browser.currentURL) ? "star.fill" : "star")
        }
        .disabled(browser.currentURL == nil)
        .help(library.isBookmarked(url: browser.currentURL) ? "Remove bookmark" : "Bookmark page")
        .accessibilityLabel(library.isBookmarked(url: browser.currentURL) ? "Remove bookmark" : "Bookmark page")
    }

    private var bookmarksMenu: some View {
        Menu {
            if library.bookmarks.isEmpty {
                Text("No bookmarks yet")
            } else {
                ForEach(library.bookmarks) { bookmark in
                    Button {
                        if let url = bookmark.url {
                            browser.navigate(to: url)
                        }
                    } label: {
                        Label(bookmark.title, systemImage: "bookmark")
                    }
                }

                Divider()

                Button("Remove Current Page", role: .destructive) {
                    library.removeBookmark(url: browser.currentURL)
                }
                .disabled(!library.isBookmarked(url: browser.currentURL))
            }
        } label: {
            Image(systemName: "book")
        }
        .menuIndicator(.hidden)
        .help("Bookmarks")
        .accessibilityLabel("Bookmarks")
    }

    private func toggleCurrentBookmark() {
        library.toggleBookmark(url: browser.currentURL, title: browser.pageTitle)
    }
}

private struct BrowserTabItem: View {
    @ObservedObject var browser: BrowserModel
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                Text(browser.isEmpty ? "New Tab" : browser.pageTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(browser.isEmpty ? "New Tab" : browser.pageTitle)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .help("Close tab")
            .accessibilityLabel("Close tab")
        }
        .buttonStyle(.plain)
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(width: 150, height: 29)
        .background(
            Color.white.opacity(isActive ? 0.16 : 0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

/// The compact hover target reserves the camera area and shows only a small
/// trailing activity dot while an agent is working or paused.
struct CompactBrowserSurface: View {
    @ObservedObject var activity: BrowserAgentActivity
    let onExpand: () -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                BrowserAgentActivityView(activity: activity, compact: true)
                    .padding(.trailing, 10)
            }
            .onHover { isHovering in
                if isHovering {
                    onExpand()
                }
            }
            .accessibilityLabel("Hover to open browser")
    }

}
