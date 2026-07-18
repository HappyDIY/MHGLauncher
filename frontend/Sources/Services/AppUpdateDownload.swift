import CryptoKit
import Foundation

enum AppUpdateDownload {
    private static let maximumSize: Int64 = 4 * 1024 * 1024 * 1024

    static func download(_ manifest: AppUpdateManifest) async throws -> URL {
        guard manifest.downloadUrl.scheme == "https", manifest.downloadUrl.user == nil,
              manifest.downloadUrl.password == nil, manifest.size > 0, manifest.size <= maximumSize else {
            throw URLError(.unsupportedURL)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3_600
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: manifest.downloadUrl)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              http.url?.scheme == "https",
              http.expectedContentLength <= 0 || http.expectedContentLength == manifest.size else {
            throw URLError(.badServerResponse)
        }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? -1
        guard size == manifest.size, try sha256(of: temporary) == manifest.sha256.lowercased() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let destination = try destination(for: manifest)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func destination(for manifest: AppUpdateManifest) throws -> URL {
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let ext = manifest.downloadUrl.pathExtension.lowercased()
        guard ["dmg", "pkg", "zip"].contains(ext) else { throw URLError(.unsupportedURL) }
        let preferred = directory.appending(path: "MHGLauncher-\(manifest.version).\(ext)")
        if !FileManager.default.fileExists(atPath: preferred.path) { return preferred }
        if (try? sha256(of: preferred)) == manifest.sha256.lowercased() { return preferred }
        return directory.appending(path: "MHGLauncher-\(manifest.version)-\(UUID().uuidString.prefix(8)).\(ext)")
    }
}
