import AppKit
import SwiftUI

@MainActor
struct BrowserDownloadsButton: View {
    @ObservedObject private var downloads = BrowserDownloads.shared
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: downloads.activeCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
                .frame(width: 24, height: 24)
                .overlay(alignment: .topTrailing) {
                    if downloads.activeCount > 0 {
                        Text("\(downloads.activeCount)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(2)
                            .background(Color.white, in: Circle())
                            .foregroundStyle(.black)
                    }
                }
        }
        .help("Downloads")
        .accessibilityLabel("Downloads")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            BrowserDownloadsList(downloads: downloads)
        }
    }
}

@MainActor
private struct BrowserDownloadsList: View {
    @ObservedObject var downloads: BrowserDownloads

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                if downloads.items.contains(where: { $0.state != .downloading }) {
                    Button("Clear") { downloads.clearFinished() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Clear completed transfers from this list")
                }
            }
            if downloads.items.isEmpty {
                Text("Downloaded files appear here.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(downloads.items) { item in
                            BrowserDownloadRow(item: item, onCancel: { downloads.cancel(item.id) })
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            Divider()
            Button("Open Downloads Folder") {
                let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                NSWorkspace.shared.open(directory)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 320)
    }
}

@MainActor
private struct BrowserDownloadRow: View {
    let item: BrowserDownload
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let destination = item.destination {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: destination.path))
                        .resizable()
                        .onDrag { NSItemProvider(contentsOf: destination) ?? NSItemProvider() }
                        .help("Drag this file to Finder or another app")
                } else {
                    Image(systemName: item.state == .failed ? "exclamationmark.triangle" : "doc")
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename).lineLimit(1).truncationMode(.middle)
                if item.state == .downloading {
                    ProgressView(value: item.totalBytes > 0 ? item.fractionCompleted : nil)
                        .progressViewStyle(.linear)
                    Text(item.totalBytes > 0
                         ? "\(bytes(item.receivedBytes)) of \(bytes(item.totalBytes))"
                         : "Downloading…")
                        .foregroundStyle(.secondary)
                } else {
                    Text(item.error ?? (item.state == .cancelled ? "Cancelled" : "Complete"))
                        .foregroundStyle(item.state == .failed ? .red : .secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.state == .downloading {
                Button(action: onCancel) { Image(systemName: "xmark.circle") }
                    .help("Cancel download")
                    .accessibilityLabel("Cancel download")
            } else if let destination = item.destination {
                Button { NSWorkspace.shared.activateFileViewerSelecting([destination]) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
            }
        }
        .buttonStyle(.plain)
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
