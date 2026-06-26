import Foundation

struct RuntimeDownloadSource: Equatable, Sendable, Identifiable {
    let id: String
    let baseURL: URL

    func assetURL(named file: String) -> URL {
        baseURL.appending(path: file)
    }
}

enum RuntimeMirrorCatalog {
    static func sources(for assetBaseURL: URL, environment: [String: String]) -> [RuntimeDownloadSource] {
        guard isOfficialRelease(assetBaseURL) else {
            return [RuntimeDownloadSource(id: "manifest", baseURL: assetBaseURL)]
        }
        let mirrors = [
            "https://gh-proxy.com/",
            "https://github.boki.moe/",
            "https://ghproxy.imciel.com/",
            "https://ghproxy.net/",
            "https://ghfast.top/"
        ]
        let configured = environment["MHG_RELEASE_MIRRORS"]?
            .split(separator: ",")
            .map(String.init) ?? []
        let prefixes = mirrors + configured
        let official = RuntimeDownloadSource(id: "github", baseURL: assetBaseURL)
        let sources = prefixes.enumerated().compactMap { item -> RuntimeDownloadSource? in
            let (index, prefix) = item
            guard let url = URL(string: prefix + assetBaseURL.absoluteString) else { return nil }
            return RuntimeDownloadSource(id: "mirror-\(index)", baseURL: url)
        }
        return unique([official] + sources)
    }

    private static func isOfficialRelease(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix("/HappyDIY/MHGLauncher/releases/download/")
    }

    private static func unique(_ sources: [RuntimeDownloadSource]) -> [RuntimeDownloadSource] {
        var seen = Set<URL>()
        return sources.filter { seen.insert($0.baseURL).inserted }
    }
}

enum RuntimeMirrorBenchmarker {
    private static let sampleBytes = 512 * 1024

    static func ranked(_ sources: [RuntimeDownloadSource], probeFile: String?) async -> [RuntimeDownloadSource] {
        guard let probeFile, sources.count > 1 else { return sources }
        let results = await withTaskGroup(of: RuntimeMirrorSample?.self) { group in
            for source in sources where !source.baseURL.isFileURL {
                group.addTask { await sample(source, file: probeFile) }
            }
            var values: [RuntimeMirrorSample] = []
            for await result in group {
                if let result { values.append(result) }
            }
            return values
        }
        let measured = results.sorted { $0.bytesPerSecond > $1.bytesPerSecond }.map(\.source)
        let unmeasured = sources.filter { source in !measured.contains(source) }
        return measured + unmeasured
    }

    private static func sample(_ source: RuntimeDownloadSource, file: String) async -> RuntimeMirrorSample? {
        var request = URLRequest(url: source.assetURL(named: file))
        request.setValue("bytes=0-\(sampleBytes - 1)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 5
        let started = Date()
        do {
            let (stream, response) = try await URLSession.mirrorBenchmark.bytes(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                  response.mimeType != "text/html" else { return nil }
            var received = 0
            for try await _ in stream {
                received += 1
                if received >= sampleBytes { break }
            }
            guard received > 0 else { return nil }
            let duration = max(Date().timeIntervalSince(started), 0.001)
            return RuntimeMirrorSample(source: source, bytesPerSecond: Double(received) / duration)
        } catch {
            return nil
        }
    }
}

private struct RuntimeMirrorSample: Sendable {
    let source: RuntimeDownloadSource
    let bytesPerSecond: Double
}

private extension URLSession {
    static let mirrorBenchmark: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        return URLSession(configuration: configuration)
    }()
}
