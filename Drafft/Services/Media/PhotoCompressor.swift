import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo ready to upload: JPEG bytes, final pixel size and its ThumbHash.
struct PreparedPhoto: Sendable {
    let data: Data
    let width: Int
    let height: Int
    let thumbHash: String?

    var contentType: String { "image/jpeg" }
}

enum MediaPreparationError: Error, Equatable {
    case unreadableImage
    case encodingFailed
    case unreadableVideo
    case noVideoTrack
    case exportFailed(String)
}

/// Photos are resized and re-encoded on the phone before upload.
///
/// - 2048 px on the long edge: sharp on a full-width 3× screen, ~0.5–1 MB instead of 3–12 MB.
/// - JPEG: decodes fastest when scrolling, and every CDN transform accepts it.
/// - Metadata is dropped (EXIF, GPS, camera): only pixels leave the phone.
/// - Orientation is applied to the pixels, so every viewer shows it upright.
enum PhotoCompressor {
    static let maxPixelSize = 2048
    static let quality = 0.8

    /// Runs on a background thread (explicitly, whatever the caller's actor), since decoding and
    /// encoding take tens of milliseconds.
    static func prepare(_ data: Data, maxPixelSize: Int = maxPixelSize, quality: Double = quality) async throws -> PreparedPhoto {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { throw MediaPreparationError.unreadableImage }
            return try prepare(source, maxPixelSize: maxPixelSize, quality: quality)
        }.value
    }

    static func prepare(fileAt url: URL, maxPixelSize: Int = maxPixelSize, quality: Double = quality) async throws -> PreparedPhoto {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { throw MediaPreparationError.unreadableImage }
            return try prepare(source, maxPixelSize: maxPixelSize, quality: quality)
        }.value
    }

    /// A photo just picked, as a file on this phone: at most 2048 px, upright, without metadata.
    /// Everything that shows or sends it then reads this copy, never the camera's 24–48 MP original.
    /// Nil if it can't be read.
    static func savePicked(_ data: Data) async -> String? {
        guard let photo = try? await prepare(data) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> String? in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("photo-\(UUID().uuidString).jpg")
            return (try? photo.data.write(to: url, options: .atomic)) != nil ? url.path : nil
        }.value
    }

    /// Encodes an already decoded image (a video poster frame, for instance).
    static func prepare(_ image: CGImage, quality: Double = quality) throws -> PreparedPhoto {
        PreparedPhoto(data: try jpeg(image, quality: quality), width: image.width, height: image.height,
                      thumbHash: ThumbHash.base64(for: image))
    }

    private static func prepare(_ source: CGImageSource, maxPixelSize: Int, quality: Double) throws -> PreparedPhoto {
        // The thumbnail API decodes straight at the target size (never the full 48 MP bitmap) and
        // applies the EXIF orientation. `Always` so it ignores a small embedded preview.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw MediaPreparationError.unreadableImage }
        return try prepare(image, quality: quality)
    }

    private static func jpeg(_ image: CGImage, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw MediaPreparationError.encodingFailed }
        // No source properties are copied: EXIF and GPS never make it into the file.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MediaPreparationError.encodingFailed }
        return output as Data
    }
}
