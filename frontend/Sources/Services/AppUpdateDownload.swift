import CryptoKit
import Foundation

enum AppUpdateDownload {
    private static let maximumSize: Int64 = 4 * 1024 * 1024 * 1024

    static func download(_ manifest: AppUpdateManifest) async throws -> URL {
        guard manifest.version.utf8.count <= 128,
              manifest.version.range(
                  of: #"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$"#,
                  options: .regularExpression
              ) != nil,
              manifest.downloadUrl.scheme?.lowercased() == "https",
              manifest.downloadUrl.user == nil, manifest.downloadUrl.password == nil,
              manifest.downloadUrl.port == nil || manifest.downloadUrl.port == 443,
              manifest.downloadUrl.fragment == nil, manifest.downloadUrl.host?.isEmpty == false,
              manifest.sha256.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil,
              manifest.size > 0, manifest.size <= maximumSize else {
            throw URLError(.unsupportedURL)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3_600
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let delegate = UpdateRedirectDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let temporary = downloads.appending(path: ".MHGLauncher-\(UUID().uuidString).part")
        try PrivateFilesystem.rejectSymbolicLinks(in: temporary)
        guard FileManager.default.createFile(
            atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]
        ) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? PrivateFilesystem.removeRegularFileIfPresent(temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        let (bytes, response) = try await session.bytes(
            for: URLRequest(url: manifest.downloadUrl, timeoutInterval: 30), delegate: delegate
        )
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              UpdateRedirectDelegate.valid(http.url),
              http.expectedContentLength <= 0 || http.expectedContentLength <= manifest.size else {
            throw URLError(.badServerResponse)
        }
        var count: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(1024 * 1024)
        for try await byte in bytes {
            guard count < manifest.size else { throw URLError(.dataLengthExceedsMaximum) }
            buffer.append(byte)
            count += 1
            if buffer.count >= 1024 * 1024 {
                try output.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty { try output.write(contentsOf: buffer) }
        try output.synchronize()
        guard count == manifest.size, try sha256(of: temporary) == manifest.sha256.lowercased() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let destination = try destination(for: manifest)
        try PrivateFilesystem.rejectSymbolicLinks(in: destination)
        if GameFilesystem.regularFile(destination) {
            let values = try? destination.resourceValues(forKeys: [.fileSizeKey])
            guard Int64(values?.fileSize ?? -1) == manifest.size,
                  (try? sha256(of: destination)) == manifest.sha256.lowercased() else {
                throw CocoaError(.fileWriteFileExists)
            }
            return destination
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    static func sha256(of url: URL) throws -> String {
        guard GameFilesystem.regularFile(url) else { throw CocoaError(.fileReadNoSuchFile) }
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
        try PrivateFilesystem.rejectSymbolicLinks(in: preferred)
        if !FileManager.default.fileExists(atPath: preferred.path) { return preferred }
        if GameFilesystem.regularFile(preferred), (try? sha256(of: preferred)) == manifest.sha256.lowercased() {
            return preferred
        }
        let value = directory.appending(path: "MHGLauncher-\(manifest.version)-\(UUID().uuidString.prefix(8)).\(ext)")
        try PrivateFilesystem.rejectSymbolicLinks(in: value)
        return value
    }
}

private final class UpdateRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var redirects = 0

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard redirects < 3, Self.valid(request.url) else {
            completionHandler(nil)
            return
        }
        redirects += 1
        completionHandler(request)
    }

    static func valid(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443) && url.fragment == nil
            && url.host?.isEmpty == false
    }
}
