import CLibgit2
import Foundation

private final class GitTransferLimit {
    let maximumBytes: Int

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }
}

private let gitTransferProgress: git_indexer_progress_cb = { progress, payload in
    guard let progress, let payload else { return -1 }
    let limit = Unmanaged<GitTransferLimit>.fromOpaque(payload).takeUnretainedValue()
    return progress.pointee.received_bytes <= limit.maximumBytes ? 0 : -7
}

actor LibGitRepository {
    private let fileManager = FileManager.default

    init() {
        git_libgit2_init()
    }

    deinit {
        git_libgit2_shutdown()
    }

    func shallowClone(from remoteURL: URL, to destination: URL, maximumBytes: Int) throws -> String {
        guard remoteURL.scheme?.lowercased() == "https",
              remoteURL.host?.nonempty != nil,
              remoteURL.user == nil,
              remoteURL.password == nil,
              remoteURL.port == nil,
              maximumBytes > 0,
              maximumBytes <= 384 * 1024 * 1024 else {
            throw LauncherCoreError(code: "metadata_mirror_insecure", message: "资料镜像必须使用无凭据的 HTTPS 地址")
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw LauncherCoreError(code: "metadata_destination_exists", message: "资料暂存目录已存在")
        }
        try PrivateFilesystem.ensureDirectory(destination.deletingLastPathComponent())

        var options = git_clone_options()
        guard git_clone_options_init(&options, UInt32(GIT_CLONE_OPTIONS_VERSION)) == 0 else {
            throw gitError(code: "metadata_clone_failed", fallback: "无法初始化资料仓库")
        }
        options.fetch_opts.depth = 1
        options.fetch_opts.follow_redirects = GIT_REMOTE_REDIRECT_NONE
        let limit = GitTransferLimit(maximumBytes: maximumBytes)
        options.fetch_opts.callbacks.transfer_progress = gitTransferProgress
        options.fetch_opts.callbacks.payload = Unmanaged.passUnretained(limit).toOpaque()

        var repository: OpaquePointer?
        let result = "main".withCString { branch in
            options.checkout_branch = branch
            return remoteURL.absoluteString.withCString { remote in
                destination.path.withCString { local in
                    git_clone(&repository, remote, local, &options)
                }
            }
        }
        guard result == 0, let repository else {
            try? fileManager.removeItem(at: destination)
            if result == -7 {
                throw LauncherCoreError(code: "metadata_download_too_large", message: "资料下载量超过限制")
            }
            throw gitError(code: "metadata_clone_failed", fallback: "资料仓库下载失败")
        }
        defer { git_repository_free(repository) }

        var head: OpaquePointer?
        guard git_repository_head(&head, repository) == 0, let head else {
            throw gitError(code: "metadata_clone_failed", fallback: "资料仓库 main 分支无效")
        }
        defer { git_reference_free(head) }
        guard let oid = git_reference_target(head), let text = git_oid_tostr_s(oid) else {
            throw LauncherCoreError(code: "metadata_clone_failed", message: "资料仓库提交标识无效")
        }
        let value = String(cString: text)
        guard value.range(of: "^[a-f0-9]{40,64}$", options: .regularExpression) != nil else {
            throw LauncherCoreError(code: "metadata_clone_failed", message: "资料仓库提交标识无效")
        }
        return value
    }

    private func gitError(code: String, fallback: String) -> LauncherCoreError {
        guard let value = git_error_last(), let message = value.pointee.message else {
            return LauncherCoreError(code: code, message: fallback)
        }
        let sanitized = String(cString: message)
            .replacingOccurrences(of: #"https?://\S+"#, with: "[远端地址]", options: .regularExpression)
        return LauncherCoreError(code: code, message: String(sanitized.prefix(300)).nonempty ?? fallback)
    }
}
