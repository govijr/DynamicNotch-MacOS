import Foundation

struct ImportedBrowserBookmark: Equatable, Sendable {
    let title: String
    let url: URL
}

enum BrowserBookmarkImportError: LocalizedError {
    case unreadable, noBookmarks, tooLarge
    var errorDescription: String? {
        switch self {
        case .unreadable: "That bookmark file could not be read. Choose a browser bookmark export and try again."
        case .noBookmarks: "No website bookmarks were found in that export."
        case .tooLarge: "That export is too large. Export just your bookmarks and try again."
        }
    }
}

/// Reads bookmark data only; exported pages are never loaded or executed.
nonisolated enum BrowserBookmarkImporter {
    private static let maximumBytes = 20 * 1024 * 1024

    static func chrome(from cookieDatabaseURL: URL) throws -> [ImportedBrowserBookmark] {
        var directory = cookieDatabaseURL.deletingLastPathComponent()
        if directory.lastPathComponent == "Network" { directory.deleteLastPathComponent() }
        let data = try boundedData(from: directory.appendingPathComponent("Bookmarks"))
        return try chromeJSON(data)
    }

    static func chromeJSON(_ data: Data) throws -> [ImportedBrowserBookmark] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { throw BrowserBookmarkImportError.unreadable }
        var bookmarks: [ImportedBrowserBookmark] = []
        func visit(_ node: [String: Any], depth: Int) {
            guard depth < 64 else { return }
            if let rawURL = node["url"] as? String, let url = webURL(rawURL) {
                bookmarks.append(.init(title: node["name"] as? String ?? url.host ?? "Website", url: url))
            }
            for child in node["children"] as? [[String: Any]] ?? [] { visit(child, depth: depth + 1) }
        }
        for key in roots.keys.sorted() {
            if let node = roots[key] as? [String: Any] { visit(node, depth: 0) }
        }
        guard !bookmarks.isEmpty else { throw BrowserBookmarkImportError.noBookmarks }
        return bookmarks
    }

    static func safariExport(from url: URL) throws -> [ImportedBrowserBookmark] {
        if url.pathExtension.lowercased() != "zip" { return try html(boundedData(from: url)) }
        let listing = try unzip(["-Z1", url.path])
        guard let names = String(data: listing, encoding: .utf8) else { throw BrowserBookmarkImportError.unreadable }
        let htmlNames = names.split(separator: "\n").map(String.init).filter {
            ($0.lowercased().hasSuffix(".html") || $0.lowercased().hasSuffix(".htm"))
                && !$0.hasPrefix("__MACOSX/") && !$0.contains(where: { "*?[".contains($0) })
        }
        var bookmarks: [ImportedBrowserBookmark] = []
        for name in htmlNames {
            let data = try unzip(["-p", url.path, name])
            if let parsed = try? html(data) { bookmarks.append(contentsOf: parsed) }
        }
        guard !bookmarks.isEmpty else { throw BrowserBookmarkImportError.noBookmarks }
        return bookmarks
    }

    static func html(_ data: Data) throws -> [ImportedBrowserBookmark] {
        guard data.count <= maximumBytes else { throw BrowserBookmarkImportError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw BrowserBookmarkImportError.unreadable
        }
        let anchors = try NSRegularExpression(pattern: #"(?is)<a\b([^>]*)>(.*?)</a\s*>"#)
        let href = try NSRegularExpression(pattern: #"(?is)\bhref\s*=\s*["'](.*?)["']"#)
        let textRange = NSRange(text.startIndex..., in: text)
        let bookmarks = anchors.matches(in: text, range: textRange).compactMap { match -> ImportedBrowserBookmark? in
            guard let attributesRange = Range(match.range(at: 1), in: text),
                  let titleRange = Range(match.range(at: 2), in: text) else { return nil }
            let attributes = String(text[attributesRange])
            guard let link = href.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
                  let linkRange = Range(link.range(at: 1), in: attributes),
                  let url = webURL(decodeEntities(String(attributes[linkRange]))) else { return nil }
            let title = decodeEntities(String(text[titleRange]).replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression))
            return .init(title: title, url: url)
        }
        guard !bookmarks.isEmpty else { throw BrowserBookmarkImportError.noBookmarks }
        return bookmarks
    }

    private static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    private static func decodeEntities(_ string: String) -> String {
        var result = string
        if let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) {
            for match in regex.matches(in: string, range: NSRange(string.startIndex..., in: string)).reversed() {
                guard let digitsRange = Range(match.range(at: 1), in: string),
                      let fullRange = Range(match.range, in: result) else { continue }
                let digits = String(string[digitsRange])
                let value = digits.hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                if let value, let scalar = UnicodeScalar(value) { result.replaceSubrange(fullRange, with: String(scalar)) }
            }
        }
        for (entity, replacement) in [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    private static func boundedData(from url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw BrowserBookmarkImportError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else { throw BrowserBookmarkImportError.tooLarge }
        return data
    }

    private static func unzip(_ arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
            data.append(chunk)
            if data.count > maximumBytes {
                process.terminate()
                try? output.fileHandleForReading.close()
                process.waitUntilExit()
                throw BrowserBookmarkImportError.tooLarge
            }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw BrowserBookmarkImportError.unreadable }
        return data
    }
}
