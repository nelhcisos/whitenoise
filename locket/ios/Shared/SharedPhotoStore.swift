import Foundation
import ImageIO
import UniformTypeIdentifiers
import WidgetKit

/// The latest friend's photo, as shown by the home-screen widget.
struct WidgetPhoto: Codable, Equatable {
    var photoId: String
    var authorName: String
    var caption: String?
    var createdAt: Date
    var myStars: Int
    var mine: [ReactionKind]
    var canReact: Bool
}

/// Files in the app group container. Written by the app and by the
/// notification extension (the moment a push arrives), read by the widget.
enum SharedPhotoStore {
    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID)
    }

    static var imageURL: URL? { directory?.appendingPathComponent("widget-photo.jpg") }
    private static var metaURL: URL? { directory?.appendingPathComponent("widget-photo.json") }

    static func load() -> WidgetPhoto? {
        guard let metaURL, let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? JSONDecoder().decode(WidgetPhoto.self, from: data)
    }

    static func save(_ photo: WidgetPhoto, imageData: Data) {
        guard let imageURL, let thumbnail = thumbnail(imageData) else { return }
        try? thumbnail.write(to: imageURL, options: .atomic)
        saveMeta(photo)
    }

    static func saveMeta(_ photo: WidgetPhoto) {
        guard let metaURL, let data = try? JSONEncoder().encode(photo) else { return }
        try? data.write(to: metaURL, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func update(photoId: String, rating: MyRating) {
        guard var photo = load(), photo.photoId == photoId,
              photo.mine != rating.mine || photo.myStars != rating.myStars
        else { return }
        photo.mine = rating.mine
        photo.myStars = rating.myStars
        saveMeta(photo)
    }

    static func clear() {
        for url in [imageURL, metaURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Widgets refuse to render large images, so keep a small copy.
    private static func thumbnail(_ data: Data, maxPixel: Int = 800) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
