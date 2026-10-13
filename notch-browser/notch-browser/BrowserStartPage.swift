import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BrowserStartPage: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var library: BrowserLibrary
    @State private var isEditingBackground = false
    @State private var isEditingFavorite = false
    @State private var favoriteToEdit: BrowserBookmark?
    @State private var isChoosingBackgroundImage = false
    @State private var backgroundImageError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    searchField
                        .padding(.bottom, 4)

                    VStack(alignment: .leading, spacing: 18) {
                        sectionHeader("Favorites") {
                            Button { editFavorite(nil) } label: {
                                Image(systemName: "plus")
                                    .frame(width: 26, height: 26)
                            }
                            .help("Add favorite")
                            .accessibilityLabel("Add favorite")
                        }
                        if library.bookmarks.isEmpty {
                            emptySection(symbol: "star", title: "Your favorite places, one click away.",
                                         detail: "Save a page with the star in the address bar, or add one here.")
                                .onTapGesture { editFavorite(nil) }
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70, maximum: 84), spacing: 14)],
                                      alignment: .leading, spacing: 20) {
                                ForEach(library.bookmarks) { bookmark in
                                    Button {
                                        if let url = bookmark.url { browser.navigate(to: url) }
                                    } label: {
                                        VStack(spacing: 9) {
                                            StartPageSiteIcon(url: bookmark.url, title: bookmark.title, size: 62)
                                            Text(bookmark.title)
                                                .font(.system(size: 11, weight: .medium))
                                                .lineLimit(2)
                                                .multilineTextAlignment(.center)
                                                .frame(height: 30, alignment: .top)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .help(bookmark.urlString)
                                    .contextMenu {
                                        Button("Edit Favorite…") { editFavorite(bookmark) }
                                        Button("Remove Favorite", role: .destructive) { library.removeBookmark(url: bookmark.url) }
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 15) {
                        sectionHeader("Recently Visited") {
                            if !library.recentlyVisited.isEmpty {
                                Button("Clear All", action: library.clearRecentVisits)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                        if library.recentlyVisited.isEmpty {
                            emptySection(symbol: "clock", title: "Pick up where you left off.",
                                         detail: "Pages you visit will appear here.")
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                                ForEach(library.recentlyVisited.prefix(8)) { entry in
                                    Button {
                                        if let url = entry.url { browser.navigate(to: url) }
                                    } label: {
                                        HStack(spacing: 11) {
                                            StartPageSiteIcon(url: entry.url, title: entry.title, size: 32)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(entry.title)
                                                    .font(.system(size: 12, weight: .medium))
                                                    .lineLimit(1)
                                                Text(entry.url?.host?.replacingOccurrences(of: "www.", with: "") ?? "Website")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.white.opacity(0.5))
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(11)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                                        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)) }
                                        .contentShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                    .help(entry.urlString)
                                    .contextMenu {
                                        Button("Add to Favorites") {
                                            if let url = entry.url { library.saveBookmark(title: entry.title, url: url) }
                                        }
                                        .disabled(library.isBookmarked(url: entry.url))
                                        Button("Remove from Recently Visited", role: .destructive) { library.removeRecentVisit(entry) }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 700)
                .padding(.horizontal, 36)
                .padding(.top, 30)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity)
            }

            HStack {
                Spacer()
                Button { isEditingBackground.toggle() } label: {
                    HStack(spacing: 6) {
                        if library.isImportingBackground {
                            ProgressView().controlSize(.mini)
                            Text("Setting Background…")
                        } else {
                            Label("Edit", systemImage: "slider.horizontal.3")
                        }
                    }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.14), in: Capsule())
                        .overlay { Capsule().strokeBorder(.white.opacity(0.12)) }
                }
                .help("Customize start page background")
                .accessibilityLabel("Customize start page background")
                .disabled(library.isImportingBackground)
                .popover(isPresented: $isEditingBackground, arrowEdge: .bottom) {
                    StartPageBackgroundPicker(library: library) {
                        isEditingBackground = false
                        isChoosingBackgroundImage = true
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 26)
            .padding(.top, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .background {
            StartPageImagePicker(library: library, isPresented: $isChoosingBackgroundImage, errorMessage: $backgroundImageError)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .alert("Couldn’t Set Background", isPresented: Binding(
            get: { backgroundImageError != nil },
            set: { if !$0 { backgroundImageError = nil } }
        )) {
            Button("OK", role: .cancel) { backgroundImageError = nil }
        } message: {
            Text(backgroundImageError ?? "Try another image.")
        }
        .popover(isPresented: $isEditingFavorite) {
            StartPageFavoriteEditor(library: library, bookmark: favoriteToEdit) {
                isEditingFavorite = false
            }
            .id(favoriteToEdit?.id)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
            BrowserAddressField(text: $browser.addressText, font: .systemFont(ofSize: 14), textColor: .white,
                                placeholder: "Search or enter a URL", onSubmit: browser.submitAddress)
                .frame(height: 25)
        }
        .padding(.horizontal, 17)
        .frame(height: 44)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.16)) }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader<Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title).font(.system(size: 20, weight: .bold))
            Spacer()
            accessory()
        }
    }

    private func emptySection(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)) }
    }

    private func editFavorite(_ bookmark: BrowserBookmark?) {
        favoriteToEdit = bookmark
        isEditingFavorite = true
    }
}

struct StartPageBackground: View {
    let selection: BrowserStartBackground
    let customImage: NSImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.035, green: 0.045, blue: 0.065)
                if selection == .custom, let customImage {
                    Image(nsImage: customImage).resizable().scaledToFill()
                } else if selection != .none {
                    Image("StartPageWallpaper").resizable().scaledToFill()
                        .hueRotation(.degrees(selection == .plum ? 65 : 0))
                        .saturation(selection == .graphite ? 0 : 1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay(Color.black.opacity(selection == .custom ? 0.25 : 0))
            .overlay {
                LinearGradient(colors: [.black.opacity(0.12), .black.opacity(selection == .custom ? 0.6 : 0.26)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StartPageSiteIcon: View {
    let url: URL?
    let title: String
    let size: CGFloat
    @State private var image: NSImage?
    private static let cache = NSCache<NSURL, NSImage>()

    private var iconURL: URL? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/favicon.ico"
        components?.query = nil
        components?.fragment = nil
        components?.user = nil
        components?.password = nil
        return components?.url
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(.white.opacity(0.13))
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(width: size * 0.64, height: size * 0.64)
            } else {
                Text(String((url?.host?.replacingOccurrences(of: "www.", with: "") ?? title).prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .overlay { RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(.white.opacity(0.13)) }
        .accessibilityHidden(true)
        .task(id: iconURL) {
            image = nil
            guard let iconURL else { return }
            if let cached = Self.cache.object(forKey: iconURL as NSURL) { image = cached; return }
            var request = URLRequest(url: iconURL)
            request.timeoutInterval = 6
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= 1_000_000, let loaded = NSImage(data: data) else { return }
            Self.cache.setObject(loaded, forKey: iconURL as NSURL)
            image = loaded
        }
    }
}

private struct StartPageBackgroundPicker: View {
    @ObservedObject var library: BrowserLibrary
    let onChooseImage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Background Image").font(.system(size: 15, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(BrowserStartBackground.allCases.filter { $0 != .custom || library.customBackgroundImage != nil }) { background in
                    Button { library.startBackground = background } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            StartPageBackground(selection: background, customImage: library.customBackgroundImage)
                                .frame(height: 66)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9)
                                        .strokeBorder(library.startBackground == background ? .white : .white.opacity(0.15),
                                                      lineWidth: library.startBackground == background ? 2 : 1)
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    if library.startBackground == background {
                                        Image(systemName: "checkmark.circle.fill").padding(6).shadow(radius: 3)
                                    }
                                }
                            Text(background.name).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("\(background.name) background")
                    .accessibilityAddTraits(library.startBackground == background ? .isSelected : [])
                }
            }
            Button(action: onChooseImage) {
                Label("Choose Your Own Image…", systemImage: "photo.badge.plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .padding(20)
        .frame(width: 300)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

}

// Keep file selection owned by the start page, rather than the transient
// wallpaper popover, and attach it to the exact window that hosts this view.
private struct StartPageImagePicker: NSViewRepresentable {
    let library: BrowserLibrary
    @Binding var isPresented: Bool
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.presentIfNeeded(in: window)
        }
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.presentIfNeeded(in: view.window)
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
        view.onWindowChange = nil
        coordinator.panel?.cancel(nil)
    }

    final class AnchorView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    final class Coordinator {
        var parent: StartPageImagePicker
        var panel: NSOpenPanel?
        private var isScheduled = false

        init(_ parent: StartPageImagePicker) { self.parent = parent }

        func presentIfNeeded(in window: NSWindow?) {
            guard parent.isPresented, panel == nil, !isScheduled, let window else { return }
            isScheduled = true
            // Allow the wallpaper popover to close before activating the app
            // and transferring keyboard focus to the file sheet.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self else { return }
                isScheduled = false
                guard parent.isPresented, let window, window.isVisible else { return }
                let panel = NSOpenPanel()
                self.panel = panel
                panel.title = "Choose a Start Page Background"
                panel.allowedContentTypes = [.image]
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.level = window.level
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                panel.beginSheetModal(for: window) { [weak self] response in
                    guard let self else { return }
                    self.panel = nil
                    parent.isPresented = false
                    guard response == .OK, let url = panel.url else { return }
                    Task { @MainActor in
                        do {
                            try await self.parent.library.setCustomBackground(from: url)
                            self.parent.errorMessage = nil
                        } catch {
                            self.parent.errorMessage = "This image couldn’t be opened. Try another photo."
                        }
                    }
                }
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }
}

private struct StartPageFavoriteEditor: View {
    @ObservedObject var library: BrowserLibrary
    let bookmark: BrowserBookmark?
    let onDone: () -> Void
    @State private var title = ""
    @State private var address = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(bookmark == nil ? "Add Favorite" : "Edit Favorite").font(.system(size: 16, weight: .semibold))
            TextField("Name", text: $title).textFieldStyle(.roundedBorder)
            TextField("Website URL", text: $address).textFieldStyle(.roundedBorder).onSubmit(save)
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel", action: onDone)
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .preferredColorScheme(.dark)
        .onAppear {
            title = bookmark?.title ?? ""
            address = bookmark?.urlString ?? ""
        }
    }

    private func save() {
        let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = input.contains("://") ? input : "https://\(input)"
        guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, !input.contains(where: { $0.isWhitespace }) else {
            errorMessage = "Enter a valid website URL."
            return
        }
        guard library.saveBookmark(title: title, url: url, replacing: bookmark?.id) else {
            errorMessage = "This page is already in your favorites."
            return
        }
        onDone()
    }
}
