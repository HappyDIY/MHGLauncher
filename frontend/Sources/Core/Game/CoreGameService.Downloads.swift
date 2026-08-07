import Foundation

extension CoreGameService {
    func download(
        _ chunk: SophonChunk,
        cache: URL? = nil,
        id: String,
        control: GameJobControl
    ) async throws -> Data {
        guard chunk.size > 0, chunk.size <= 256 * 1024 * 1024 else {
            throw LauncherCoreError(code: "sophon_chunk_invalid", message: "Sophon 分块大小无效")
        }
        guard let cache else {
            let transport = URLSessionHTTPTransport()
            let payload = try await transport.send(
                URLRequest(url: chunk.url, timeoutInterval: 60),
                policy: .sophon,
                maximumBytes: Int(chunk.size)
            )
            try await control.checkpoint()
            guard (200..<300).contains(payload.statusCode), Int64(payload.data.count) == chunk.size,
                  CoreHash.xxHash64(payload.data)
                    == chunk.name.split(separator: "_", maxSplits: 1).first.map(String.init)?.lowercased() else {
                throw LauncherCoreError(code: "sophon_chunk_invalid", message: "\(chunk.name) 分块校验失败")
            }
            try await throttle(bytes: Int64(payload.data.count), control: control)
            return payload.data
        }

        let target = try GameFilesystem.safeTarget(root: cache, relativePath: chunk.name)
        try GameFilesystem.ensureParent(of: target)
        try PrivateFilesystem.rejectSymbolicLinks(in: target)
        let expectedHash = chunk.name.split(separator: "_", maxSplits: 1).first.map(String.init)?.lowercased()
        if GameFilesystem.regularFile(target),
           (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(chunk.size),
           (try? CoreHash.xxHash64(file: target)) == expectedHash {
            return try Data(contentsOf: target, options: [.mappedIfSafe])
        }

        let partial = URL(filePath: target.path + ".part")
        try PrivateFilesystem.rejectSymbolicLinks(in: partial)
        var offset = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if !GameFilesystem.regularFile(partial) || offset > chunk.size {
            try? PrivateFilesystem.removeRegularFileIfPresent(partial)
            offset = 0
        }
        if offset == chunk.size {
            if (try? CoreHash.xxHash64(file: partial)) == expectedHash {
                if FileManager.default.fileExists(atPath: target.path) {
                    guard GameFilesystem.regularFile(target) else {
                        throw LauncherCoreError(code: "sophon_target_invalid", message: "\(chunk.name) 缓存路径无效")
                    }
                    _ = try FileManager.default.replaceItemAt(target, withItemAt: partial)
                } else {
                    try FileManager.default.moveItem(at: partial, to: target)
                }
                try PrivateFilesystem.setPrivateFilePermissions(target)
                return try Data(contentsOf: target, options: [.mappedIfSafe])
            }
            try? PrivateFilesystem.removeRegularFileIfPresent(partial)
            offset = 0
        }
        var failures = 0
        while offset < chunk.size {
            try await control.checkpoint()
            do {
                var request = URLRequest(url: chunk.url, timeoutInterval: 120)
                if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil
                configuration.httpCookieStorage = nil
                configuration.httpShouldSetCookies = false
                configuration.timeoutIntervalForRequest = 120
                configuration.timeoutIntervalForResource = 3_600
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let (bytes, response) = try await session.bytes(
                    for: request,
                    delegate: ValidatingRedirectDelegate(policy: .sophon)
                )
                guard let http = response as? HTTPURLResponse,
                      (http.url.map { HTTPSHostPolicy.sophon.allows($0) } ?? false) else {
                    throw LauncherCoreError(code: "sophon_chunk_invalid", message: "\(chunk.name) 分块响应地址无效")
                }
                if offset > 0 {
                    guard http.statusCode == 206,
                          Self.validByteRange(
                              http.value(forHTTPHeaderField: "Content-Range"),
                              offset: offset,
                              expectedSize: chunk.size
                          ) else {
                        try? PrivateFilesystem.removeRegularFileIfPresent(partial)
                        offset = 0
                        continue
                    }
                } else {
                    guard (200..<300).contains(http.statusCode) else {
                        throw LauncherCoreError(code: "sophon_chunk_invalid", message: "\(chunk.name) 分块下载失败")
                    }
                }
                let remaining = chunk.size - offset
                guard http.expectedContentLength <= 0 || http.expectedContentLength <= remaining else {
                    throw LauncherCoreError(code: "sophon_chunk_too_large", message: "\(chunk.name) 分块超过大小限制")
                }
                guard FileManager.default.fileExists(atPath: partial.path) || FileManager.default.createFile(
                    atPath: partial.path, contents: nil, attributes: [.posixPermissions: 0o600]
                ) else {
                    throw LauncherCoreError(code: "sophon_storage_failed", message: "无法创建分块临时文件")
                }
                let output = try FileHandle(forWritingTo: partial)
                defer { try? output.close() }
                try output.seekToEnd()
                var received = offset
                var buffer = Data()
                for try await byte in bytes {
                    try await control.checkpoint()
                    buffer.append(byte)
                    guard received <= chunk.size - Int64(buffer.count) else {
                        throw LauncherCoreError(code: "sophon_chunk_too_large", message: "\(chunk.name) 分块超过大小限制")
                    }
                    if buffer.count >= 1024 * 1024 {
                        try await throttle(bytes: Int64(buffer.count), control: control)
                        try output.write(contentsOf: buffer)
                        received += Int64(buffer.count)
                        buffer.removeAll(keepingCapacity: true)
                    }
                }
                if !buffer.isEmpty {
                    try await throttle(bytes: Int64(buffer.count), control: control)
                    try output.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                }
                try output.synchronize()
                try output.close()
                guard received == chunk.size else {
                    throw LauncherCoreError(code: "sophon_chunk_incomplete", message: "\(chunk.name) 分块下载未完成")
                }
                guard try CoreHash.xxHash64(file: partial) == expectedHash else {
                    try PrivateFilesystem.removeRegularFileIfPresent(partial)
                    offset = 0
                    throw LauncherCoreError(code: "sophon_chunk_invalid", message: "\(chunk.name) 分块校验失败")
                }
                if FileManager.default.fileExists(atPath: target.path) {
                    guard GameFilesystem.regularFile(target) else {
                        throw LauncherCoreError(code: "sophon_target_invalid", message: "\(chunk.name) 缓存路径无效")
                    }
                    _ = try FileManager.default.replaceItemAt(target, withItemAt: partial)
                } else {
                    try FileManager.default.moveItem(at: partial, to: target)
                }
                try PrivateFilesystem.setPrivateFilePermissions(target)
                return try Data(contentsOf: target, options: [.mappedIfSafe])
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as LauncherCoreError where error.code == "sophon_chunk_incomplete" {
                failures += 1
                guard failures <= 5 else { throw error }
                offset = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                try await waitForDownloadRetry(control, attempt: failures)
            } catch {
                failures += 1
                guard failures <= 5 else { throw error }
                offset = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                if offset >= chunk.size {
                    try? PrivateFilesystem.removeRegularFileIfPresent(partial)
                    offset = 0
                }
                try await waitForDownloadRetry(control, attempt: failures)
            }
        }
        throw LauncherCoreError(code: "sophon_chunk_invalid", message: "\(chunk.name) 分块下载失败")
    }

    func downloadPatch(
        _ patch: SophonPatch,
        to destination: URL,
        control: GameJobControl
    ) async throws {
        guard HTTPSHostPolicy.sophon.allows(patch.url) else {
            throw LauncherCoreError(code: "sophon_patch_invalid", message: "增量补丁下载地址不受信任")
        }
        guard patch.fileSize > 0, patch.fileSize <= 2 * 1024 * 1024 * 1024 else {
            throw LauncherCoreError(code: "sophon_patch_too_large", message: "增量补丁大小超过限制")
        }
        try GameFilesystem.ensureParent(of: destination)
        try PrivateFilesystem.rejectSymbolicLinks(in: destination)
        let partial = URL(filePath: destination.path + ".part")
        try PrivateFilesystem.rejectSymbolicLinks(in: partial)
        var offset = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if !GameFilesystem.regularFile(partial) || offset > patch.fileSize {
            try? PrivateFilesystem.removeRegularFileIfPresent(partial)
            offset = 0
        }
        let expectedHash = patch.id.split(separator: "_", maxSplits: 1).first.map(String.init)?.lowercased()
        if offset == patch.fileSize {
            if (try? CoreHash.xxHash64(file: partial)) == expectedHash {
                if FileManager.default.fileExists(atPath: destination.path) {
                    guard GameFilesystem.regularFile(destination) else {
                        throw LauncherCoreError(code: "sophon_target_invalid", message: "增量补丁缓存路径无效")
                    }
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: partial)
                } else {
                    try FileManager.default.moveItem(at: partial, to: destination)
                }
                try PrivateFilesystem.setPrivateFilePermissions(destination)
                return
            } else {
                try? PrivateFilesystem.removeRegularFileIfPresent(partial)
                offset = 0
            }
        }
        var failures = 0
        while offset < patch.fileSize {
            try await control.checkpoint()
            do {
                var request = URLRequest(url: patch.url, timeoutInterval: 120)
                if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil
                configuration.httpCookieStorage = nil
                configuration.httpShouldSetCookies = false
                configuration.timeoutIntervalForRequest = 120
                configuration.timeoutIntervalForResource = 3_600
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let (bytes, response) = try await session.bytes(
                    for: request,
                    delegate: ValidatingRedirectDelegate(policy: .sophon)
                )
                guard let http = response as? HTTPURLResponse,
                      (http.url.map { HTTPSHostPolicy.sophon.allows($0) } ?? false) else {
                    throw LauncherCoreError(code: "sophon_patch_invalid", message: "增量补丁响应地址无效")
                }
                if offset > 0 {
                    guard http.statusCode == 206,
                          Self.validByteRange(
                              http.value(forHTTPHeaderField: "Content-Range"),
                              offset: offset,
                              expectedSize: patch.fileSize
                          ) else {
                        try? PrivateFilesystem.removeRegularFileIfPresent(partial)
                        offset = 0
                        continue
                    }
                } else {
                    guard (200..<300).contains(http.statusCode) else {
                        throw LauncherCoreError(code: "sophon_patch_invalid", message: "增量补丁下载失败")
                    }
                }
                let remaining = patch.fileSize - offset
                guard http.expectedContentLength <= 0 || http.expectedContentLength <= remaining else {
                    throw LauncherCoreError(code: "sophon_patch_too_large", message: "增量补丁超过大小限制")
                }
                guard FileManager.default.fileExists(atPath: partial.path) || FileManager.default.createFile(
                    atPath: partial.path, contents: nil, attributes: [.posixPermissions: 0o600]
                ) else {
                    throw LauncherCoreError(code: "sophon_storage_failed", message: "无法创建增量补丁临时文件")
                }
                let output = try FileHandle(forWritingTo: partial)
                defer { try? output.close() }
                try output.seekToEnd()
                var received = offset
                var buffer = Data()
                for try await byte in bytes {
                    try await control.checkpoint()
                    buffer.append(byte)
                    guard received <= patch.fileSize - Int64(buffer.count) else {
                        throw LauncherCoreError(code: "sophon_patch_too_large", message: "增量补丁超过大小限制")
                    }
                    if buffer.count >= 1024 * 1024 {
                        try await throttle(bytes: Int64(buffer.count), control: control)
                        try output.write(contentsOf: buffer)
                        received += Int64(buffer.count)
                        buffer.removeAll(keepingCapacity: true)
                    }
                }
                if !buffer.isEmpty {
                    try await throttle(bytes: Int64(buffer.count), control: control)
                    try output.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                }
                try output.synchronize()
                try output.close()
                guard received == patch.fileSize else {
                    throw LauncherCoreError(code: "sophon_patch_incomplete", message: "增量补丁下载未完成")
                }
                guard try CoreHash.xxHash64(file: partial) == expectedHash else {
                    try PrivateFilesystem.removeRegularFileIfPresent(partial)
                    offset = 0
                    throw LauncherCoreError(code: "sophon_patch_invalid", message: "增量补丁校验失败")
                }
                if FileManager.default.fileExists(atPath: destination.path) {
                    guard GameFilesystem.regularFile(destination) else {
                        throw LauncherCoreError(code: "sophon_target_invalid", message: "增量补丁缓存路径无效")
                    }
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: partial)
                } else {
                    try FileManager.default.moveItem(at: partial, to: destination)
                }
                try PrivateFilesystem.setPrivateFilePermissions(destination)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as LauncherCoreError where error.code == "sophon_patch_incomplete" {
                failures += 1
                guard failures <= 5 else { throw error }
                offset = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                try await waitForDownloadRetry(control, attempt: failures)
            } catch {
                failures += 1
                guard failures <= 5 else { throw error }
                offset = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                if offset >= patch.fileSize {
                    try? PrivateFilesystem.removeRegularFileIfPresent(partial)
                    offset = 0
                }
                try await waitForDownloadRetry(control, attempt: failures)
            }
        }
        throw LauncherCoreError(code: "sophon_patch_invalid", message: "增量补丁下载失败")
    }
}
