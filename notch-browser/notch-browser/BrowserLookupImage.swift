import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Private, short-lived handoff storage. Never changes the user's clipboard.
final class BrowserLookupImage {
    let data: Data
    let fileURL: URL
    let width: Int
    let height: Int
    var image: NSImage { NSImage(data: data)! }
    private let directory: URL
    static let inputByteLimit = 25 * 1024 * 1024

    init(data: Data) throws {
        guard data.count <= Self.inputByteLimit else { throw BrowserLookupError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw BrowserLookupError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw BrowserLookupError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BrowserLookupError.invalidImage }
        self.data = output as Data
        width = image.width; height = image.height
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("notch-lookup-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("Lookup.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do { try self.data.write(to: fileURL, options: .atomic) }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    static func fromFile(_ url: URL) throws -> BrowserLookupImage {
        guard url.isFileURL else { throw BrowserLookupError.invalidImage }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= inputByteLimit else { throw BrowserLookupError.imageTooLarge }
        return try BrowserLookupImage(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func fromPasteboard(_ pasteboard: NSPasteboard) throws -> BrowserLookupImage? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type) { return try BrowserLookupImage(data: data) }
        }
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        let legacy = (pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String])?.map { URL(fileURLWithPath: $0) }
        if let file = (files ?? legacy)?.first,
           let type = UTType(filenameExtension: file.pathExtension), type.conforms(to: .image) {
            return try fromFile(file)
        }
        return nil
    }
}
