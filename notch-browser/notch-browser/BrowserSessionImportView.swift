import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ImportBrowser: String, CaseIterable {
    case chrome = "Chrome", safari = "Safari"
    var bundleID: String { self == .chrome ? "com.google.Chrome" : "com.apple.Safari" }
    var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(named: NSImage.networkName) ?? BrowserAppIcon.image
    }
}

struct BrowserSessionImportView: View {
    @ObservedObject var library: BrowserLibrary
    let isPreview: Bool
    let onContinue: () -> Void
    let onExitPreview: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var source = ImportBrowser.chrome
    @State private var selectedProfileID: String?
    @State private var importBookmarks = true
    @State private var importCookies = true
    @State private var isChoosingExport = false
    @State private var isBusy = false
    @State private var didImport = false
    @State private var statusMessage: String?
    @State private var isRevealed = false
    @State private var importTask: Task<Void, Never>?

    private var selectedProfile: BrowserChromeProfile? {
        library.chromeProfiles.first { $0.id == selectedProfileID } ?? library.chromeProfiles.first
    }
    private var canImport: Bool {
        !isBusy && !library.isImportingSession && !didImport
            && (source == .safari || (isPreview || selectedProfile != nil) && (importBookmarks || importCookies))
    }

    var body: some View {
        VStack(spacing: 18) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(nsImage: BrowserAppIcon.image)
                            .resizable().scaledToFit().frame(width: 40, height: 40)
                            .accessibilityHidden(true)
                        Text("Bring your browser with you")
                            .font(.system(size: 23, weight: .semibold))
                        Text("Import your favorites and start feeling at home.")
                            .font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                    }

                    HStack(spacing: 10) {
                        ForEach(ImportBrowser.allCases, id: \.self) { browser in
                            Button {
                                source = browser
                                didImport = false
                                statusMessage = nil
                            } label: {
                                HStack(spacing: 10) {
                                    Image(nsImage: browser.icon).resizable().scaledToFit().frame(width: 28, height: 28)
                                    Text(browser.rawValue).font(.system(size: 13, weight: .medium))
                                    Spacer(minLength: 0)
                                    if source == browser { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                                }
                                .padding(12)
                                .background(.white.opacity(source == browser ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 12))
                                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(source == browser ? 0.3 : 0.1)) }
                            }
                            .disabled(isBusy)
                            .accessibilityLabel("Import from \(browser.rawValue)")
                        }
                    }

                    if source == .chrome {
                        chromeOptions
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bring over your Safari bookmarks.")
                                .font(.system(size: 13, weight: .medium))
                            Text("In Safari, choose File → Export Browsing Data to File and select Bookmarks. Then choose the exported ZIP here. Older Safari versions can export a bookmarks HTML file.")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("You’ll sign in to your websites again.")
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(didImport ? Color.white.opacity(0.65) : Color(red: 1, green: 0.55, blue: 0.5))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(spacing: 12) {
                Button(action: didImport ? onContinue : beginImport) {
                    HStack(spacing: 8) {
                        if isBusy { ProgressView().controlSize(.small).tint(.white) }
                        Text(didImport ? "Start browsing" : isBusy ? "Importing…" : source == .chrome ? "Import from Chrome" : "Choose Safari export…")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(Color(red: 0.22, green: 0.44, blue: 0.96).opacity(canImport || didImport || isBusy ? 1 : 0.45),
                                in: RoundedRectangle(cornerRadius: 11))
                }
                .disabled(!didImport && !canImport || isBusy)

                Button(didImport ? "Import from another browser" : "Skip for now") {
                    if didImport {
                        didImport = false
                        statusMessage = nil
                    } else { onContinue() }
                }
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                .disabled(isBusy || library.isImportingSession)

                if isPreview {
                    HStack(spacing: 8) {
                        Text("Debug preview · No browser data is read or saved")
                        Button("Exit", action: onExitPreview).disabled(isBusy)
                    }
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 480, maxHeight: 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .preferredColorScheme(.dark)
        .background(.black)
        .opacity(isRevealed ? 1 : 0)
        .task {
            if !isPreview {
                library.refreshChromeProfiles()
                selectedProfileID = library.chromeProfiles.first?.id
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { isRevealed = true }
        }
        .fileImporter(isPresented: $isChoosingExport, allowedContentTypes: [.html, .zip], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importSafari(url) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { statusMessage = error.localizedDescription }
            }
        }
        .onDisappear { importTask?.cancel() }
    }

    private var chromeOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isPreview {
                Text("Chrome · Preview profile").font(.system(size: 12))
            } else if let selectedProfile {
                Menu {
                    ForEach(library.chromeProfiles) { profile in
                        Button(profile.displayName) { selectedProfileID = profile.id }
                    }
                } label: {
                    Text(selectedProfile.displayName).font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }
                .menuIndicator(.hidden)
                .disabled(isBusy)
            } else {
                HStack {
                    Text("No Chrome profiles found").font(.system(size: 12))
                    Spacer()
                    Button("Refresh") { library.refreshChromeProfiles() }
                        .font(.system(size: 12)).foregroundStyle(.blue)
                }
            }
            Toggle("Bookmarks", isOn: $importBookmarks)
            Toggle("Cookies · Keep supported websites signed in", isOn: $importCookies)
            Text("Close Chrome before importing. Some websites may ask you to sign in again.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .toggleStyle(.checkbox)
        .disabled(isBusy)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func beginImport() {
        guard canImport else { return }
        if isPreview {
            isBusy = true
            importTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 650_000_000)
                guard !Task.isCancelled else { return }
                isBusy = false
                didImport = true
                statusMessage = "Preview complete. No browser data was imported."
            }
        } else if source == .safari {
            isChoosingExport = true
        } else if let selectedProfile {
            isBusy = true
            importTask = Task { @MainActor in
                let success = await library.importChromeData(from: selectedProfile, bookmarks: importBookmarks, cookies: importCookies)
                guard !Task.isCancelled else { return }
                isBusy = false
                didImport = success
                statusMessage = library.sessionStatus
            }
        }
    }

    private func importSafari(_ url: URL) {
        isBusy = true
        importTask = Task { @MainActor in
            let success = await library.importSafariBookmarks(from: url)
            guard !Task.isCancelled else { return }
            isBusy = false
            didImport = success
            statusMessage = library.sessionStatus
        }
    }
}
