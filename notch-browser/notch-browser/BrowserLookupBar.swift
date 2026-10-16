import SwiftUI

struct BrowserLookupBar: View {
    @ObservedObject var lookup: BrowserLookupCoordinator
    let isPinned: Bool
    let onTogglePin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                if lookup.image != nil {
                    Label("Google Lens", systemImage: "camera.viewfinder")
                        .font(.system(size: 12, weight: .medium))
                        .fixedSize()
                } else {
                    Menu {
                        ForEach(BrowserLookupDestination.allCases) { destination in
                            Button(destination.title) { lookup.selectDestination(destination) }
                        }
                    } label: {
                        Label(lookup.destination.title, systemImage: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(lookup.query.isEmpty)
                }

                Text(lookup.image.map { "\($0.width) × \($0.height)" } ?? (lookup.query.isEmpty ? "Quick lookup" : lookup.query))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button { lookup.keepAsTab() } label: { Image(systemName: "plus.square") }
                    .help("Keep as a regular tab")
                    .accessibilityLabel("Keep lookup as a tab")
                    .disabled(lookup.image != nil && (!lookup.hasStartedImageSearch || lookup.isSearchingImage))
                Button(action: onTogglePin) { Image(systemName: isPinned ? "pin.fill" : "pin") }
                    .help(isPinned ? "Unpin browser" : "Pin browser open")
                    .accessibilityLabel(isPinned ? "Unpin browser" : "Pin browser open")
                Button { lookup.openInDefaultBrowser() } label: { Image(systemName: "arrow.up.forward.app") }
                    .help("Open in your default browser")
                    .accessibilityLabel("Open lookup in default browser")
                    .disabled(lookup.image != nil && (!lookup.hasStartedImageSearch || lookup.isSearchingImage))
                Button { lookup.onDismiss?(true) } label: { Image(systemName: "xmark") }
                    .help("Close lookup and return to your app (Esc)")
                    .accessibilityLabel("Close lookup and return to app")
            }
            if let message = lookup.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
            }
            if let image = lookup.image, lookup.hasStartedImageSearch {
                HStack(spacing: 8) {
                    Image(nsImage: image.image).resizable().scaledToFit().frame(width: 32, height: 32)
                        .onDrag { NSItemProvider(contentsOf: image.fileURL)! }
                        .accessibilityLabel("Drag this image into Google Lens")
                    Text("Drag into Lens if needed").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    if lookup.message != nil, !lookup.isSearchingImage {
                        Button("Try Again") { lookup.searchImage() }.font(.system(size: 11))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color.black)
    }
}

struct BrowserLookupImagePreview: View {
    @ObservedObject var lookup: BrowserLookupCoordinator
    let image: BrowserLookupImage
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            Image(nsImage: image.image)
                .resizable().scaledToFit()
                .frame(maxWidth: 420, maxHeight: 260)
                .onDrag { NSItemProvider(contentsOf: image.fileURL)! }
                .accessibilityLabel("Image prepared for Google Lens")
            Button("Search with Google Lens") { lookup.searchImage() }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            Text("This image is sent to Google when you search.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 12)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
