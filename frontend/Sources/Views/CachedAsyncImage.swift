import AppKit
import SwiftUI

// 内存级图片缓存与并发下载协调器，避免滚动复用时的重复下载与解码。
actor ImageMemoryCache {
    static let shared = ImageMemoryCache()
    // NSCache 自身线程安全，标记 nonisolated 以支持视图 init 阶段同步读取，
    // 避免滚动复用时每个 cell 都为已缓存图片支付一次 actor 往返。
    nonisolated(unsafe) let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    init() { cache.countLimit = 256 }

    nonisolated func cachedImage(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func image(forKey key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    func load(forKey key: String, fetch: @escaping @Sendable () async -> NSImage?) async -> NSImage? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let existing = inFlight[key] { return await existing.value }
        let task = Task { await fetch() }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { cache.setObject(result, forKey: key as NSString) }
        return result
    }
}

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let contentMode: ContentMode
    let accessibilityLabel: String?
    let maxPixelDimension: Int?
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.apiClient) private var client
    @State private var image: NSImage?
    @State private var loading = false

    init(
        url: URL?,
        contentMode: ContentMode = .fit,
        accessibilityLabel: String? = nil,
        maxPixelDimension: Int? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.accessibilityLabel = accessibilityLabel
        self.maxPixelDimension = maxPixelDimension
        self.placeholder = placeholder
        // 滚动复用时，若图片已在内存缓存，直接同步命中，首帧即显示，
        // 省去 actor 往返与 nil→image 的额外一帧及过渡动画。
        if let url {
            let location = url.scheme == nil ? url.relativeString : url.absoluteString
            let key = maxPixelDimension.map { "\(location)#max-pixels=\($0)" } ?? location
            _image = State(initialValue: ImageMemoryCache.shared.cachedImage(forKey: key))
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .motionTransition(.content)
            } else if loading {
                ProgressView()
                    .controlSize(.small)
                    .motionTransition(.content)
            } else {
                placeholder().motionTransition(.content)
            }
        }
        .accessibilityHidden(accessibilityLabel == nil)
        .accessibilityLabel(accessibilityLabel ?? "")
        .motionAnimation(.content, value: phase)
        .task(id: url) {
            // 先查内存缓存，命中则直接展示，避免滚动复用时的重复下载与解码。
            if let url, let cached = await ImageMemoryCache.shared.image(forKey: cacheKey(for: url)) {
                image = cached
                loading = false
                return
            }
            guard let url else { return }
            loading = true
            let key = cacheKey(for: url)
            let pixelDimension = maxPixelDimension
            let result = await ImageMemoryCache.shared.load(forKey: key) { [client, pixelDimension] () -> NSImage? in
                do {
                    let data: Data
                    if url.scheme == nil, let client {
                        data = try await client.download(url.relativeString)
                    } else {
                        data = try await URLSession.shared.data(from: url).0
                    }
                    return CachedImageDecoder.decode(
                        data,
                        maxPixelDimension: pixelDimension
                    )
                } catch {
                    return nil
                }
            }
            image = result
            loading = false
        }
    }

    // 统一缓存键：相对路径与绝对 URL 均稳定。
    private func cacheKey(for url: URL) -> String {
        let location = url.scheme == nil ? url.relativeString : url.absoluteString
        return maxPixelDimension.map { "\(location)#max-pixels=\($0)" } ?? location
    }

    private var phase: Int {
        if image != nil { return 2 }
        return loading ? 1 : 0
    }
}
