import AppKit
import ImageIO

enum CachedImageDecoder {
    static func decode(_ data: Data, maxPixelDimension: Int?) -> NSImage? {
        guard let maxPixelDimension, maxPixelDimension > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return NSImage(data: data)
        }
        let representation = NSBitmapImageRep(cgImage: image)
        let result = NSImage(size: NSSize(width: image.width, height: image.height))
        result.addRepresentation(representation)
        return result
    }
}
