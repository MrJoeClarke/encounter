//
//  ImageProcessing.swift
//  encounter
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An imported image ready to store: a size-limited original and a small thumbnail.
struct PreparedImage: Sendable {
    let imageData: Data
    let thumbnailData: Data
}

/// Decoding, downscaling and thumbnailing with ImageIO. Free of UI and model types so it can run off the main actor.
nonisolated enum ImageProcessing {
    /// Originals larger than this on their longest side are downscaled on import.
    static let maxOriginalDimension = 4096
    static let thumbnailDimension = 256

    /// Runs on the concurrent pool, so large images never block the UI.
    @concurrent
    static func prepare(_ data: Data) async -> PreparedImage? {
        prepareSynchronously(data)
    }

    /// Reads a file the user picked, handling the security-scoped access that sandboxed apps need.
    @concurrent
    static func loadData(from url: URL) async -> Data? {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }
        return try? Data(contentsOf: url)
    }

    /// Returns nil if the data isn't a decodable image.
    /// Originals within the size limit are kept byte-for-byte. Larger ones are downscaled and re-encoded
    /// (PNG if they have transparency, otherwise JPEG).
    static func prepareSynchronously(
        _ data: Data,
        maxDimension: Int = maxOriginalDimension,
        thumbnailDimension: Int = thumbnailDimension
    ) -> PreparedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }

        let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
        let longestSide = max(width, height)

        guard let thumbnail = scaledImage(from: source, maxPixelSize: min(thumbnailDimension, longestSide)),
              let thumbnailData = encode(thumbnail, hasAlpha: hasAlpha)
        else { return nil }

        guard longestSide > maxDimension else {
            return PreparedImage(imageData: data, thumbnailData: thumbnailData)
        }
        guard let reduced = scaledImage(from: source, maxPixelSize: maxDimension),
              let reducedData = encode(reduced, hasAlpha: hasAlpha)
        else { return nil }
        return PreparedImage(imageData: reducedData, thumbnailData: thumbnailData)
    }

    /// A file extension matching the encoded format ("jpeg", "png", "heic" and so on), or "img" if unknown.
    static func fileExtension(for data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier),
              let fileExtension = type.preferredFilenameExtension
        else { return "img" }
        return fileExtension
    }

    /// The pixel size of encoded image data, or nil if it can't be read.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    // The transform option applies EXIF orientation, so photos taken in portrait come out upright.
    private static func scaledImage(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encode(_ image: CGImage, hasAlpha: Bool) -> Data? {
        let type = hasAlpha ? UTType.png : UTType.jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
