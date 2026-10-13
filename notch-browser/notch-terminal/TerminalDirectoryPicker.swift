import AppKit
import SwiftUI

struct TerminalDirectoryPickerButton: View {
    @ObservedObject var terminal: TerminalModel
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))

                Text(terminal.directoryLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.68)
            }
            .foregroundStyle(NotchTerminalPalette.foreground.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(NotchTerminalPalette.foreground.opacity(0.055))
            .overlay {
                Rectangle()
                    .stroke(NotchTerminalPalette.foreground.opacity(0.16), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            TerminalDirectoryPicker(terminal: terminal)
                .presentationCornerRadius(0)
                .presentationBackground(NotchTerminalPalette.background)
        }
        .help("Change working directory")
        .accessibilityLabel("Working directory \(terminal.directoryLabel)")
        .accessibilityHint("Opens a directory picker")
    }
}

private struct TerminalDirectoryPicker: View {
    @ObservedObject var terminal: TerminalModel
    @Environment(\.dismiss) private var dismiss

    @State private var browsingPath: String
    @State private var searchQuery = ""
    @State private var directories: [DirectoryEntry] = []
    @FocusState private var searchFieldIsFocused: Bool

    init(terminal: TerminalModel) {
        self.terminal = terminal
        _browsingPath = State(initialValue: terminal.workingDirectory)
    }

    private var filteredDirectories: [DirectoryEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return directories }
        return directories.filter { entry in
            entry.name.localizedCaseInsensitiveContains(query)
        }
    }

    private var parentPath: String? {
        let url = URL(fileURLWithPath: browsingPath).standardizedFileURL
        let parent = url.deletingLastPathComponent().path
        return parent == browsingPath ? nil : parent
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NotchTerminalPalette.accent)

                Text(browsingPath)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .foregroundStyle(NotchTerminalPalette.foreground.opacity(0.88))
            .padding(.horizontal, 13)
            .padding(.top, 12)
            .padding(.bottom, 9)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchTerminalPalette.foreground.opacity(0.48))

                TextField("Search directories…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($searchFieldIsFocused)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(NotchTerminalPalette.foreground.opacity(0.055))
            .overlay {
                Rectangle()
                    .stroke(NotchTerminalPalette.foreground.opacity(0.14), lineWidth: 1)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 1) {
                    if let parentPath {
                        directoryRow(
                            title: ".. (Parent Directory)",
                            path: parentPath,
                            systemImage: "arrow.up"
                        )
                    }

                    ForEach(filteredDirectories) { directory in
                        directoryRow(
                            title: directory.name,
                            path: directory.path,
                            systemImage: "folder"
                        )
                    }

                    if filteredDirectories.isEmpty && parentPath == nil {
                        Text("No directories found")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(NotchTerminalPalette.foreground.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .scrollIndicators(.visible)
        }
        .frame(width: 350, height: 280)
        .padding(.top, 1)
        .background(NotchTerminalPalette.background)
        .foregroundStyle(NotchTerminalPalette.foreground)
        .overlay {
            Rectangle()
                .stroke(NotchTerminalPalette.foreground.opacity(0.18), lineWidth: 1)
        }
        .onAppear {
            loadDirectories()
            DispatchQueue.main.async {
                searchFieldIsFocused = true
            }
        }
    }

    private func directoryRow(
        title: String,
        path: String,
        systemImage: String
    ) -> some View {
        Button {
            chooseDirectory(path)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 17)

                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .foregroundStyle(NotchTerminalPalette.foreground.opacity(0.78))
            .padding(.horizontal, 8)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func chooseDirectory(_ path: String) {
        terminal.changeDirectory(to: path)
        dismiss()
    }

    private func loadDirectories() {
        let directoryURL = URL(fileURLWithPath: browsingPath, isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        )) ?? []

        directories = entries.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true else {
                return nil
            }
            return DirectoryEntry(name: url.lastPathComponent, path: url.path)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct DirectoryEntry: Identifiable {
    let name: String
    let path: String

    var id: String { path }
}
