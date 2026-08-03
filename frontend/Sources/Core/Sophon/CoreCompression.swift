import CryptoKit
import CxxHash
import CZstd
import Foundation

enum CoreHash {
    static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func xxHash64(_ data: Data) -> String {
        let value = data.withUnsafeBytes { buffer in
            XXH64(buffer.baseAddress, buffer.count, 0)
        }
        return String(format: "%016llx", value)
    }

    static func xxHash64(file url: URL) throws -> String {
        guard let state = XXH64_createState(), XXH64_reset(state, 0) == XXH_OK else {
            throw LauncherCoreError(code: "hash_initialization_failed", message: "文件校验初始化失败")
        }
        defer { XXH64_freeState(state) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            let result = data.withUnsafeBytes { XXH64_update(state, $0.baseAddress, $0.count) }
            guard result == XXH_OK else {
                throw LauncherCoreError(code: "hash_failed", message: "文件校验失败")
            }
        }
        return String(format: "%016llx", XXH64_digest(state))
    }
}

enum Zstandard {
    static func decompress(_ source: Data, maximumBytes: Int = 256 * 1024 * 1024) throws -> Data {
        guard maximumBytes > 0 else { throw tooLarge() }
        let declared = source.withUnsafeBytes { buffer in
            ZSTD_getFrameContentSize(buffer.baseAddress, buffer.count)
        }
        if declared == ZSTD_CONTENTSIZE_ERROR { throw invalid() }
        if declared != ZSTD_CONTENTSIZE_UNKNOWN, declared > UInt64(maximumBytes) { throw tooLarge() }
        let capacity = declared == ZSTD_CONTENTSIZE_UNKNOWN ? maximumBytes : max(1, Int(declared))
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            source.withUnsafeBytes { input in
                ZSTD_decompress(destination.baseAddress, destination.count, input.baseAddress, input.count)
            }
        }
        guard ZSTD_isError(written) == 0 else { throw invalid() }
        guard written <= maximumBytes else { throw tooLarge() }
        output.removeSubrange(written..<output.count)
        return output
    }

    private static func invalid() -> LauncherCoreError {
        LauncherCoreError(code: "sophon_manifest_invalid", message: "Sophon 清单解压失败")
    }

    private static func tooLarge() -> LauncherCoreError {
        LauncherCoreError(code: "sophon_manifest_too_large", message: "Sophon 清单解压结果超过大小限制")
    }
}
