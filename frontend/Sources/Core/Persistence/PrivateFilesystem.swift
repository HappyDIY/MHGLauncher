import Darwin
import Foundation

enum PrivateFilesystem {
    private static let processUmask: mode_t = 0o077

    static func configureProcessUmask() {
        _ = umask(processUmask)
    }

    static func ensureDirectory(_ url: URL) throws {
        let manager = FileManager.default
        try rejectSymbolicLinks(in: url)
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFDIR else {
                throw LauncherCoreError(code: "unsafe_data_path", message: "托管目录必须是普通目录")
            }
        } else if errno == ENOENT {
            try manager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try rejectSymbolicLinks(in: url)
        } else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
        if url.standardizedFileURL.path != "/" {
            guard chmod(url.path, 0o700) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
            }
        }
    }

    static func requireRegularFileIfPresent(_ url: URL) throws {
        try rejectSymbolicLinks(in: url)
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            guard errno == ENOENT else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
            }
            return
        }
        guard info.st_mode & S_IFMT == S_IFREG else {
            throw LauncherCoreError(code: "unsafe_file_path", message: "数据库路径必须是普通文件")
        }
    }

    static func setPrivateFilePermissions(_ url: URL) throws {
        try requireRegularFileIfPresent(url)
        guard chmod(url.path, 0o600) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
    }

    static func removeDirectoryIfPresent(_ url: URL) throws {
        try rejectSymbolicLinks(in: url)
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            guard errno == ENOENT else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
            }
            return
        }
        guard info.st_mode & S_IFMT == S_IFDIR else {
            throw LauncherCoreError(code: "unsafe_file_path", message: "待删除路径必须是普通目录")
        }
        try rejectSymbolicLinksRecursively(in: url)
        try FileManager.default.removeItem(at: url)
    }

    static func removeRegularFileIfPresent(_ url: URL) throws {
        try requireRegularFileIfPresent(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func rejectSymbolicLinks(in url: URL) throws {
        let components = url.standardizedFileURL.pathComponents
        var current = URL(filePath: "/")
        for component in components.dropFirst() {
            current.append(path: component)
            var info = stat()
            guard lstat(current.path, &info) == 0 else {
                guard errno == ENOENT else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
                }
                break
            }
            guard info.st_mode & S_IFMT != S_IFLNK else {
                throw LauncherCoreError(code: "unsafe_file_path", message: "文件路径不能包含符号链接")
            }
        }
    }

    static func rejectSymbolicLinksRecursively(in url: URL) throws {
        try rejectSymbolicLinks(in: url)
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR else { return }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else {
            throw LauncherCoreError(code: "unsafe_file_path", message: "无法读取文件目录")
        }
        while let entry = enumerator.nextObject() as? URL {
            var entryInfo = stat()
            guard lstat(entry.path, &entryInfo) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
            }
            let mode = entryInfo.st_mode & S_IFMT
            guard mode != S_IFLNK else {
                throw LauncherCoreError(code: "unsafe_file_path", message: "文件路径不能包含符号链接")
            }
            guard mode == S_IFDIR || mode == S_IFREG else {
                throw LauncherCoreError(code: "unsafe_file_path", message: "文件路径不能包含特殊文件")
            }
        }
    }
}
