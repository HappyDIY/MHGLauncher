import Darwin
import Foundation

enum PrivateFilesystem {
    private static let processUmask: mode_t = 0o077

    static func configureProcessUmask() {
        _ = umask(processUmask)
    }

    static func ensureDirectory(_ url: URL) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else {
                throw LauncherCoreError(code: "unsafe_data_path", message: "托管目录必须是普通目录")
            }
        } else {
            try manager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        guard chmod(url.path, 0o700) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
    }

    static func requireRegularFileIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else {
            throw LauncherCoreError(code: "unsafe_file_path", message: "数据库路径必须是普通文件")
        }
    }

    static func setPrivateFilePermissions(_ url: URL) throws {
        guard chmod(url.path, 0o600) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
    }
}
