import AppKit
import SwiftUI

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.apiClient) private var client
    @State private var image: NSImage?
    @State private var loading = false

    init(
        url: URL?,
        contentMode: ContentMode = .fit,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if loading {
                ProgressView().controlSize(.small)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            loading = true
            defer { loading = false }
            do {
                let data: Data
                if url.scheme == nil, let client {
                    data = try await client.download(url.relativeString)
                } else {
                    data = try await URLSession.shared.data(from: url).0
                }
                image = NSImage(data: data)
            } catch {
                image = nil
            }
        }
    }
}
