import Foundation
import ImageIO
import UniformTypeIdentifiers

// Standalone import fixture. All writes go to a disposable directory;
// system desktop pictures are only read and no app preferences are changed.
@main
struct BackgroundImageTests {
    static func main() throws {
        let files = FileManager.default
        let fixture = files.temporaryDirectory.appendingPathComponent("notch-background-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: fixture) }

        let photo = fixture.appendingPathComponent("photo.png")
        try writePhoto(to: photo, width: 3200, height: 1600)
        try expect(try BrowserBackgroundImage.resolvedImageURL(from: photo) == photo,
                   "Regular images keep their original source")

        let assets = fixture.appendingPathComponent("DesktopAssets", isDirectory: true)
        let asset = assets.appendingPathComponent("wallpaper.asset", isDirectory: true)
        let dataDirectory = asset.appendingPathComponent("AssetData", isDirectory: true)
        try files.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let fullImage = dataDirectory.appendingPathComponent("Test Wallpaper.png")
        try files.copyItem(at: photo, to: fullImage)
        try writePlist(["MobileAssetProperties": ["DesktopPictureID": "Test Wallpaper"]],
                       to: asset.appendingPathComponent("Info.plist"))
        let descriptor = fixture.appendingPathComponent("Test Wallpaper.madesktop")
        try writePlist(["mobileAssetID": "Test Wallpaper", "thumbnailPath": "unused-thumbnail.png"], to: descriptor)
        try expect(try BrowserBackgroundImage.resolvedImageURL(from: descriptor, assetDirectories: [assets]).resolvingSymlinksInPath()
                   == fullImage.resolvingSymlinksInPath(),
                   "Desktop picture references use the full installed image")

        let destination = fixture.appendingPathComponent("Saved/background.jpg")
        let saved = try BrowserBackgroundImage.prepare(from: photo, destination: destination)
        try expect(saved == Data(contentsOf: destination), "The returned image matches the persisted image")
        let dimensions = try imageDimensions(at: destination)
        try expect(dimensions.width == 2400 && dimensions.height == 1200,
                   "Large photos are downsampled while preserving their aspect ratio")

        let malformed = fixture.appendingPathComponent("Invalid.madesktop")
        try writePlist(["mobileAssetID": "../outside"], to: malformed)
        do {
            _ = try BrowserBackgroundImage.resolvedImageURL(from: malformed, assetDirectories: [assets])
            throw failure("Invalid desktop picture references must fail")
        } catch BrowserBackgroundImageError.invalidDesktopPicture {}

        try writePlist(["mobileAssetID": "Not Downloaded", "thumbnailPath": photo.path], to: malformed)
        do {
            _ = try BrowserBackgroundImage.resolvedImageURL(from: malformed, assetDirectories: [assets])
            throw failure("An unavailable wallpaper must not silently use its thumbnail")
        } catch BrowserBackgroundImageError.unavailableDesktopPicture {}

        let invalidPhoto = fixture.appendingPathComponent("broken.png")
        try Data("invalid image".utf8).write(to: invalidPhoto)
        do {
            _ = try BrowserBackgroundImage.prepare(from: invalidPhoto, destination: destination)
            throw failure("Invalid image imports must fail")
        } catch let error as CocoaError {
            try expect(error.code == .fileReadCorruptFile, "Invalid images report a read error")
        }
        try expect(try Data(contentsOf: destination) == saved, "Failed imports leave the previous image intact")

        let systemHEIC = BrowserBackgroundImage.desktopPicturesDirectory.appendingPathComponent("Sonoma.heic")
        if files.isReadableFile(atPath: systemHEIC.path) {
            _ = try BrowserBackgroundImage.prepare(from: systemHEIC, destination: fixture.appendingPathComponent("system-heic.jpg"))
            print("Real macOS HEIC import passed")
        }
        let systemReference = BrowserBackgroundImage.desktopPicturesDirectory.appendingPathComponent("Big Sur Graphic.madesktop")
        if files.isReadableFile(atPath: systemReference.path) {
            do {
                let actualImage = try BrowserBackgroundImage.resolvedImageURL(from: systemReference)
                try expect(!actualImage.path.contains(".thumbnails"), "System references resolve to full-resolution assets")
                _ = try BrowserBackgroundImage.prepare(from: systemReference, destination: fixture.appendingPathComponent("system-reference.jpg"))
                print("Real installed macOS desktop picture import passed")
            } catch BrowserBackgroundImageError.unavailableDesktopPicture {
                print("System wallpaper is not downloaded; unavailable-picture behavior passed")
            }
        }
        print("Background import, limits, persistence, and failure checks passed")
    }

    private static func writePlist(_ value: [String: Any], to url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: url)
    }

    private static func writePhoto(to url: URL, width: Int, height: Int) throws {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw failure("Could not make a fixture image")
        }
        context.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let encoder = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw failure("Could not encode a fixture image")
        }
        CGImageDestinationAddImage(encoder, image, nil)
        try expect(CGImageDestinationFinalize(encoder), "Fixture image is valid")
    }

    private static func imageDimensions(at url: URL) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw failure("Could not read fixture image dimensions")
        }
        return (width, height)
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw failure(message) }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "BackgroundImageTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
