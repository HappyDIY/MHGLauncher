import CryptoKit
import Foundation

enum RuntimeManifestDownload {
    static func load(from url: URL, environment: [String: String]) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let sources = RuntimeMirrorCatalog.sources(
            for: url.deletingLastPathComponent(), environment: environment
        )
        for source in sources {
            guard let manifest = try? await data(from: source.assetURL(named: url.lastPathComponent)),
                  let signature = try? await data(from: source.assetURL(named: "\(url.lastPathComponent).sig")),
                  RuntimeManifestVerifier.isValid(manifest, signature: signature) else { continue }
            return manifest
        }
        throw RuntimeInstallError.invalidManifest
    }

    private static func data(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw URLError(.badServerResponse)
        }
        return data
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
