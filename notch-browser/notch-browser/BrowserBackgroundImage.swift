import Foundation
import ImageIO
import UniformTypeIdentifiers

enum BrowserBackgroundImageError: LocalizedError {
    case unavailableDesktopPicture
    case invalidDesktopPicture

    var errorDescription: String? {
        switch self {
        case .unavailableDesktopPicture:
            "Download this wallpaper in System Settings → Wallpaper, then choose it here."
        case .invalidDesktopPicture:
            "This desktop picture couldn’t be opened. Try another picture."
        }
    }
}

enum BrowserBackgroundImage {
    nonisolated static let desktopPicturesDirectory = URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true)
    nonisolated static let desktopAssetDirectories = [
        URL(fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_DesktopPicture", isDirectory: true),
        URL(fileURLWithPath: "/Library/AssetsV2/com_apple_MobileAsset_DesktopPicture", isDirectory: true)
    ]

    static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.image]
        if let desktopPicture = UTType(filenameExtension: "madesktop") { types.append(desktopPicture) }
        return types
    }

    nonisolated static func prepare(from url: URL, destination: URL) throws -> Data {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        let imageURL = try resolvedImageURL(from: url)
        // Decode at the display size off the main thread, including HEIC
        // desktop pictures, instead of allocating their full resolution.
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let output = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(encoder, image, [
            kCGImageDestinationLossyCompressionQuality: 0.88,
            kCGImageDestinationBackgroundColor: CGColor(gray: 0, alpha: 1)
        ] as CFDictionary)
        guard CGImageDestinationFinalize(encoder) else { throw CocoaError(.fileWriteUnknown) }
        let data = output as Data
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return data
    }

    nonisolated static func resolvedImageURL(
        from url: URL,
        assetDirectories: [URL] = desktopAssetDirectories
    ) throws -> URL {
        guard url.pathExtension.lowercased() == "madesktop" else { return url }
        guard let descriptor = try propertyList(at: url),
              let identifier = descriptor["mobileAssetID"] as? String,
              !identifier.isEmpty,
              identifier != ".", identifier != "..",
              !identifier.contains("/"), !identifier.contains("\\") else {
            throw BrowserBackgroundImageError.invalidDesktopPicture
        }

        // Resolve installed assets by their metadata, not the tiny thumbnail
        // advertised by the descriptor. Keep a durable copy of the actual image.
        let files = FileManager.default
        for directory in assetDirectories {
            guard let assets = try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for asset in assets.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where asset.pathExtension == "asset" {
                guard let info = try? propertyList(at: asset.appendingPathComponent("Info.plist")),
                      let properties = info["MobileAssetProperties"] as? [String: Any],
                      properties["DesktopPictureID"] as? String == identifier else { continue }
                let dataDirectory = asset.appendingPathComponent("AssetData", isDirectory: true)
                for ext in ["heic", "jpg", "jpeg", "png", "tiff"] {
                    let candidate = dataDirectory.appendingPathComponent(identifier).appendingPathExtension(ext)
                    if files.isReadableFile(atPath: candidate.path) { return candidate }
                }
            }
        }
        throw BrowserBackgroundImageError.unavailableDesktopPicture
    }

    nonisolated private static func propertyList(at url: URL) throws -> [String: Any]? {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1_048_576 else { return nil }
        return try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
    }
}
