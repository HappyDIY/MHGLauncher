import CryptoKit
import Foundation

enum RuntimeManifestDownload {
    private static let manifestLimit = 1024 * 1024
    private static let signatureLimit = 128

    // 解码运行时清单：将 DecodingError 归一为 invalidManifest，
    // 避免随 macOS 版本变化的本地化解码错误直接展示给用户。
    static func decode(_ data: Data) throws -> RuntimeManifest {
        do {
            return try JSONDecoder().decode(RuntimeManifest.self, from: data)
        } catch is DecodingError {
            throw RuntimeInstallError.invalidManifest
        }
    }

    static func load(from url: URL, environment: [String: String]) async throws -> Data {
        if url.isFileURL { return try localData(from: url, limit: manifestLimit) }
        let mirrors = RuntimeMirrorCatalog.sources(
            for: url.deletingLastPathComponent(), environment: environment
        )
        let official = RuntimeDownloadSource(id: "manifest", baseURL: url.deletingLastPathComponent())
        let sources = [official] + mirrors.filter { $0.baseURL != official.baseURL }
        for source in sources {
            do {
                let manifest = try await data(
                    from: source.assetURL(named: url.lastPathComponent), limit: manifestLimit
                )
                let signature = try await data(
                    from: source.assetURL(named: "\(url.lastPathComponent).sig"),
                    limit: signatureLimit
                )
                if RuntimeManifestVerifier.isValid(manifest, signature: signature) {
                    return manifest
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch {
                continue
            }
        }
        throw RuntimeInstallError.invalidManifest
    }

    private static func data(from url: URL, limit: Int) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw URLError(.badServerResponse)
        }
        if response.expectedContentLength > Int64(limit) {
            throw URLError(.dataLengthExceedsMaximum)
        }
        var data = Data()
        data.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    private static func localData(from url: URL, limit: Int) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? limit + 1
        guard size <= limit else { throw URLError(.dataLengthExceedsMaximum) }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}

enum RuntimeManifestVerifier {
    private static let bundledPublicKey = Data(base64Encoded: "DvswOM/iIXbp+jB12AmqWUqU/gYv7xG7RYWu7dIa+Sk=")!

    static func isValid(_ manifest: Data, signature: Data, publicKey: Data = bundledPublicKey) -> Bool {
        guard signature.count == 64, let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        return key.isValidSignature(signature, for: manifest)
    }
}
