import AppKit
import ImageIO

enum CachedImageDecoder {
    private static let maximumSourceDimension = 32_768
    private static let maximumSourcePixels = 64 * 1024 * 1024

    static func decode(_ data: Data, maxPixelDimension: Int?) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0,
              width <= maximumSourceDimension, height <= maximumSourceDimension,
              width <= maximumSourcePixels / height else {
            return nil
        }

        let image: CGImage?
        if let maxPixelDimension, maxPixelDimension > 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
                kCGImageSourceShouldCacheImmediately: true
            ]
            image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            )
        } else {
            // NSImage(data:) 会把解压推迟到首次绘制，导致主线程在滚动首帧解码。
            // 在加载任务中立即生成 CGImage，把这笔开销留在视图更新之外。
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                options as CFDictionary
            )
        }
        guard let image else { return nil }
        let representation = NSBitmapImageRep(cgImage: image)
        let result = NSImage(size: NSSize(width: image.width, height: image.height))
        result.addRepresentation(representation)
        return result
    }
}
