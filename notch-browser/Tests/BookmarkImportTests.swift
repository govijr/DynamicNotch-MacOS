import Foundation

// Run with BrowserBookmarkImporter.swift using swiftc. All data is synthetic.
@main
struct BookmarkImportTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let html = #"""
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p><DT><H3>Favorites</H3><DL><p>
        <DT><A HREF="https://example.com/?a=1&amp;b=2">News &amp; Caf&#233; &#x1F680;</A>
        <DT><A href='https://apple.com'><b>Apple</b></A>
        <DT><A HREF="javascript:alert(1)">Unsafe</A>
        <DT><A HREF="file:///private/secret">Local file</A>
        </DL></DL>
        """#
        let htmlData = Data(html.utf8)
        let parsed = try BrowserBookmarkImporter.html(htmlData)
        try expect(parsed.count == 2, "HTML imports only website links")
        try expect(parsed[0].title == "News & Café 🚀", "HTML entities and Unicode decode correctly")
        try expect(parsed[0].url.absoluteString == "https://example.com/?a=1&b=2", "URL entities decode correctly")
        try expect(parsed[1].title == "Apple", "Formatting tags are stripped from titles")

        let chrome = Data(#"{"roots":{"bookmark_bar":{"children":[{"type":"folder","children":[{"type":"url","name":"Example","url":"https://example.com"},{"type":"url","name":"Unsafe","url":"javascript:alert(1)"}]}]},"other":{"children":[{"type":"url","name":"Apple","url":"https://apple.com"}]}}}"#.utf8)
        let chromeParsed = try BrowserBookmarkImporter.chromeJSON(chrome)
        try expect(chromeParsed.count == 2, "Nested Chrome folders import with unsafe URLs excluded")
        try chrome.write(to: directory.appendingPathComponent("Bookmarks"))
        let fromProfile = try BrowserBookmarkImporter.chrome(from: directory.appendingPathComponent("Cookies"))
        try expect(fromProfile == chromeParsed, "Chrome profile path resolves to its Bookmarks file")
        let fromNetwork = try BrowserBookmarkImporter.chrome(from: directory.appendingPathComponent("Network/Cookies"))
        try expect(fromNetwork == chromeParsed, "Chrome Network/Cookies path resolves to its Bookmarks file")

        let exportedHTML = directory.appendingPathComponent("Marcadores.html")
        try htmlData.write(to: exportedHTML)
        let fromHTML = try BrowserBookmarkImporter.safariExport(from: exportedHTML)
        try expect(fromHTML == parsed, "Safari HTML export imports")
        try Data("Synthetic password placeholder".utf8).write(to: directory.appendingPathComponent("Passwords.csv"))
        let archive = directory.appendingPathComponent("Safari.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = directory
        zip.arguments = ["-q", archive.path, "Marcadores.html", "Passwords.csv"]
        zip.standardOutput = FileHandle.nullDevice
        zip.standardError = FileHandle.nullDevice
        try zip.run()
        zip.waitUntilExit()
        try expect(zip.terminationStatus == 0, "Safari ZIP fixture created")
        let fromZIP = try BrowserBookmarkImporter.safariExport(from: archive)
        try expect(fromZIP == parsed, "Safari ZIP imports localized bookmark filename and ignores other data")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        try expect(Set(files) == Set(["Bookmarks", "Marcadores.html", "Passwords.csv", "Safari.zip"]), "ZIP import extracts no files")

        try expectFailure("Corrupt JSON is rejected") { _ = try BrowserBookmarkImporter.chromeJSON(Data("broken".utf8)) }
        try expectFailure("Exports with no bookmarks are rejected") { _ = try BrowserBookmarkImporter.html(Data("<html></html>".utf8)) }
        try expectFailure("Oversized exports are rejected") { _ = try BrowserBookmarkImporter.html(Data(repeating: 65, count: 20 * 1024 * 1024 + 1)) }
        print("14 bookmark import checks passed (synthetic data only).")
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "BookmarkImportTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func expectFailure(_ message: String, _ body: () throws -> Void) throws {
        do { try body() } catch { return }
        try expect(false, message)
    }
}
