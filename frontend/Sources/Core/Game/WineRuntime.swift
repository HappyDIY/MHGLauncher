import Darwin
import Foundation

struct WineRuntimePaths: Sendable {
    let root: URL
    let wine: URL
    let wineboot: URL
    let wineserver: URL
    let windowProbe: URL
    let winemetal: URL
    let dnsGate: URL
    let mhypbase: URL

    init(root: URL) throws {
        self.root = root
        wine = root.appending(path: "wine/bin/wine")
        wineboot = root.appending(path: "wine/bin/wineboot")
        wineserver = root.appending(path: "wine/bin/wineserver")
        windowProbe = root.appending(path: "bin/mhg-window-probe")
        winemetal = root.appending(path: "wine/lib/wine/x86_64-windows/winemetal.dll")
        dnsGate = root.appending(path: "lib/libmhg_dns_gate.dylib")
        mhypbase = root.appending(path: "assets/mhypbase.dll")
        for file in [wine, wineserver, windowProbe, winemetal, dnsGate, mhypbase] {
            guard GameFilesystem.regularFile(file) else {
                throw LauncherCoreError(code: "game_runtime_missing", message: "游戏运行时不完整：\(file.lastPathComponent)")
            }
        }
        guard GameFilesystem.regularFile(wineboot) || Self.isWinebootLink(wineboot, under: root) else {
            throw LauncherCoreError(code: "game_runtime_missing", message: "游戏运行时不完整：\(wineboot.lastPathComponent)")
        }
    }

    private static func isWinebootLink(_ url: URL, under root: URL) -> Bool {
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/"),
              (try? PrivateFilesystem.rejectSymbolicLinks(in: url.deletingLastPathComponent())) != nil,
              (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == "wine" else {
            return false
        }
        var linkInfo = stat()
        var targetInfo = stat()
        let target = url.deletingLastPathComponent().appending(path: "wine")
        return lstat(url.path, &linkInfo) == 0
            && linkInfo.st_mode & S_IFMT == S_IFLNK
            && lstat(target.path, &targetInfo) == 0
            && targetInfo.st_mode & S_IFMT == S_IFREG
    }

    func environment(
        prefix: URL,
        session: URL,
        profile: GamePerformanceProfile,
        metalHUD: Bool,
        networkDebug: Bool,
        wineLog: Bool,
        framePacing: Int
    ) throws -> [String: String] {
        let base = ProcessInfo.processInfo.environment
        let allowed = ["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "TMP", "TEMP",
                       "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "__CF_USER_TEXT_ENCODING"]
        var result = Dictionary(uniqueKeysWithValues: allowed.compactMap { key in base[key].map { (key, $0) } })
        let gate = session.appending(path: "dns-gate")
        try GameFilesystem.writePrivate(Data("\(getpid())".utf8), to: gate)
        result.merge([
            "LANG": "zh_CN.UTF-8", "LANGUAGE": "zh_CN:zh", "LC_ALL": "zh_CN.UTF-8",
            "LC_MESSAGES": "zh_CN.UTF-8", "WINEPREFIX": prefix.path, "WINEARCH": "win64",
            "WINEDEBUG": wineLog ? "fixme-all" : "-all", "WINEDLLOVERRIDES": "winedbg.exe=d",
            "WINEMSYNC": profile == .optimized ? "1" : "0",
            "WINEESYNC": profile == .compatibility ? "1" : "0",
            "DYLD_INSERT_LIBRARIES": dnsGate.path, "MHG_DNS_GATE_FILE": gate.path,
            "MHG_DNS_GATE_HOSTS": "dispatchcnglobal.yuanshen.com,dispatchosglobal.yuanshen.com",
            "MHG_DNS_GATE_OWNER_PID": "\(getpid())", "MTL_HUD_ENABLED": metalHUD ? "1" : "0",
            "DXMT_LOG_LEVEL": metalHUD ? "info" : "warn", "DXMT_LOG_PATH": session.appending(path: "dxmt").path,
            "DXMT_SHADER_CACHE_PATH": FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Caches/MHGLauncher/dxmt/YuanShen.exe").path,
            "DXMT_CONFIG": framePacing > 0 ? "d3d11.preferredMaxFrameRate=\(framePacing);" : ""
        ], uniquingKeysWith: { _, new in new })
        if networkDebug {
            try GameFilesystem.writePrivate(Data(), to: session.appending(path: "dns.log"))
            result["MHG_DNS_LOG_FILE"] = session.appending(path: "dns.log").path
        }
        return result
    }
}

actor WinePrefixManager {
    private let runner: any CoreProcessRunning

    init(runner: any CoreProcessRunning = FoundationProcessRunner()) {
        self.runner = runner
    }

    func prepare(paths: WineRuntimePaths, dataDirectory: URL, profile: GamePerformanceProfile) async throws -> URL {
        let prefix = dataDirectory.appending(path: "wineprefix")
        try PrivateFilesystem.ensureDirectory(prefix)
        let environment = prefixEnvironment(prefix: prefix, profile: profile)
        let marker = prefix.appending(path: ".mhglauncher-wine-runtime")
        let identity = paths.wine.path + "\n"
        let ready = GameFilesystem.regularFile(marker)
            && ((try? marker.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) <= 1024
            && (try? String(contentsOf: marker, encoding: .utf8)) == identity
        try await stopServer(paths: paths, prefix: prefix)
        if !ready {
            let rosetta = try await runner.run(CoreProcessRequest(
                executable: URL(filePath: "/usr/bin/arch"), arguments: ["-x86_64", "/usr/bin/true"],
                workingDirectory: nil, environment: environment, logURL: nil
            ))
            guard rosetta == 0 else {
                throw LauncherCoreError(code: "rosetta_missing", message: "请先安装 Rosetta 2 后再启动 Wine")
            }
            let status = try await runner.run(CoreProcessRequest(
                executable: paths.wineboot, arguments: ["--init"], workingDirectory: nil,
                environment: environment.merging(["WINEDLLOVERRIDES": "mscoree,mshtml="], uniquingKeysWith: { _, n in n }),
                logURL: nil
            ))
            guard status == 0 else {
                throw LauncherCoreError(code: "wineprefix_init_failed", message: "Wine 运行环境初始化失败")
            }
            try GameFilesystem.writePrivate(Data(identity.utf8), to: marker)
        }
        try await configureLocale(wine: paths.wine, environment: environment)
        try await configureRetina(wine: paths.wine, environment: environment)
        try await configureGameLanguage(wine: paths.wine, environment: environment)
        try await stopServer(paths: paths, prefix: prefix)
        let system32 = prefix.appending(path: "drive_c/windows/system32")
        try PrivateFilesystem.ensureDirectory(system32)
        let destination = system32.appending(path: "winemetal.dll")
        try PrivateFilesystem.rejectSymbolicLinks(in: destination)
        try PrivateFilesystem.removeRegularFileIfPresent(destination)
        try FileManager.default.copyItem(at: paths.winemetal, to: destination)
        try PrivateFilesystem.setPrivateFilePermissions(destination)
        return prefix
    }

    func environment(prefix: URL, profile: GamePerformanceProfile) -> [String: String] {
        prefixEnvironment(prefix: prefix, profile: profile)
    }

    func stopServer(paths: WineRuntimePaths, prefix: URL) async throws {
        let environment = prefixEnvironment(prefix: prefix, profile: .optimized)
        let stop = try await runner.run(CoreProcessRequest(
            executable: paths.wineserver, arguments: ["-k"], workingDirectory: nil,
            environment: environment, logURL: nil
        ))
        guard stop == 0 || stop == 1 else {
            throw LauncherCoreError(code: "wine_server_stop_failed", message: "Wine 服务未能在期限内确认退出")
        }
        let wait = try await runner.run(CoreProcessRequest(
            executable: paths.wineserver, arguments: ["-w"], workingDirectory: nil,
            environment: environment, logURL: nil
        ))
        guard wait == 0 else {
            throw LauncherCoreError(code: "wine_server_stop_failed", message: "Wine 服务未能在期限内确认退出")
        }
    }

    private func configureLocale(wine: URL, environment: [String: String]) async throws {
        let values = [
            ("HKCU\\Control Panel\\International", "LocaleName", "REG_SZ", "zh-CN"),
            ("HKCU\\Control Panel\\International", "Locale", "REG_SZ", "00000804"),
            ("HKCU\\Control Panel\\Desktop", "PreferredUILanguages", "REG_MULTI_SZ", "zh-CN"),
            ("HKCU\\Control Panel\\International\\User Profile", "Languages", "REG_MULTI_SZ", "zh-Hans-CN"),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language", "Default", "REG_SZ", "0804"),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language", "InstallLanguage", "REG_SZ", "0804"),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage", "ACP", "REG_SZ", "936"),
            ("HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage", "OEMCP", "REG_SZ", "936")
        ]
        for (key, name, type, value) in values {
            try await runRegistry(
                wine: wine, arguments: ["reg", "add", key, "/v", name, "/t", type, "/d", value, "/f"],
                environment: environment, code: "wine_locale_failed", message: "Wine 中文环境配置失败"
            )
        }
    }

    private func configureRetina(wine: URL, environment: [String: String]) async throws {
        try await runRegistry(
            wine: wine,
            arguments: ["reg", "add", "HKCU\\Software\\Wine\\Mac Driver", "/v", "RetinaMode", "/t", "REG_SZ", "/d", "Y", "/f"],
            environment: environment, code: "wine_retina_failed", message: "Wine 高分辨率模式配置失败"
        )
    }

    private func configureGameLanguage(wine: URL, environment: [String: String]) async throws {
        for root in ["HKCU\\Software\\miHoYo\\原神", "HKCU\\Software\\miHoYo\\Genshin Impact"] {
            try await runRegistry(
                wine: wine,
                arguments: ["reg", "add", root, "/v", "LanguageSettings_LocalAudioLanguage_h882585060", "/t", "REG_DWORD", "/d", "2", "/f"],
                environment: environment, code: "wine_language_failed", message: "游戏中文语言配置失败"
            )
        }
    }

    private func runRegistry(
        wine: URL,
        arguments: [String],
        environment: [String: String],
        code: String,
        message: String
    ) async throws {
        let status = try await runner.run(CoreProcessRequest(
            executable: wine, arguments: arguments, workingDirectory: nil,
            environment: environment, logURL: nil
        ))
        guard status == 0 else { throw LauncherCoreError(code: code, message: message) }
    }

    private func prefixEnvironment(prefix: URL, profile: GamePerformanceProfile) -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        let allowed = ["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "TMP", "TEMP", "__CF_USER_TEXT_ENCODING"]
        var result = Dictionary(uniqueKeysWithValues: allowed.compactMap { key in source[key].map { (key, $0) } })
        result.merge([
            "LANG": "zh_CN.UTF-8", "LANGUAGE": "zh_CN:zh", "LC_ALL": "zh_CN.UTF-8",
            "WINEPREFIX": prefix.path, "WINEARCH": "win64", "WINEDEBUG": "-all",
            "WINEDLLOVERRIDES": "winedbg.exe=d", "WINEMSYNC": profile == .optimized ? "1" : "0",
            "WINEESYNC": profile == .compatibility ? "1" : "0"
        ], uniquingKeysWith: { _, new in new })
        return result
    }
}
