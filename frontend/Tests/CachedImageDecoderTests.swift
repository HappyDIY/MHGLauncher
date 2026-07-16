import AppKit
import Testing
@testable import MHGLauncher

@Suite("图片降采样")
struct CachedImageDecoderTests {
    @Test("按显示尺寸解码大图")
    func downsamplesLargeImage() throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 800,
            pixelsHigh: 400,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let image = try #require(CachedImageDecoder.decode(data, maxPixelDimension: 200))
        let representation = try #require(image.representations.first)

        #expect(representation.pixelsWide == 200)
        #expect(representation.pixelsHigh == 100)
    }
}
