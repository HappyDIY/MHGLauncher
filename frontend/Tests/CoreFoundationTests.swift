import Foundation
import CryptoKit
import GRDB
import Testing
@testable import MHGLauncher

@Suite("Swift Core 基础设施", .serialized)
struct CoreFoundationTests {
    @Test("固定 zstd 与 xxHash 样本可解码校验")
    func fixedCompressionSamples() throws {
        let compressed = try #require(Data(base64Encoded:
            "KLUv/QRY+QAATUhHTGF1bmNoZXItU29waG9uLWZpeGVkLXNhbXBsZez4Ch4="
        ))
        let expected = Data("MHGLauncher-Sophon-fixed-sample".utf8)
        #expect(try Zstandard.decompress(compressed) == expected)
        #expect(CoreHash.xxHash64(expected) == "df990a3f1e0af8ec")
        #expect(CoreHash.md5(expected) == "46b1df74ffea9995dde5c17e0cbcaf38")
        #expect(throws: LauncherCoreError.self) {
            _ = try Zstandard.decompress(compressed, maximumBytes: expected.count - 1)
        }
        #expect(throws: LauncherCoreError.self) {
            _ = try Zstandard.decompress(compressed.dropLast())
        }
    }

    @Test("Sophon 清单拒绝逃逸路径并保护 mhypbase")
    func validatesSophonPaths() throws {
        #expect(!SophonValidation.safePath("../YuanShen.exe"))
        #expect(!SophonValidation.safePath("a//b"))
        #expect(SophonValidation.safePath("GenshinImpact_Data/data.unity3d"))
        let protected = GameBuild(
            version: "5.8.0",
            deprecatedFiles: ["YuanShen_Data/Plugins/mhypbase.dll"]
        )
        #expect(try SophonValidation.validate(protected).deprecatedFiles.isEmpty)
    }

    @Test("DS 签名与 RSA 登录加密使用固定协议")
    func signingAndEncryption() throws {
        let signature = MiHoYoSigning.sign(
            .prod,
            now: Date(timeIntervalSince1970: 1_700_000_000),
            random: Data([0, 1, 2, 3, 4, 5])
        )
        #expect(signature == "1700000000,012345,31f5bee240702e99af19e3a829623b43")
        let encrypted = try #require(Data(base64Encoded: MiHoYoSigning.encryptPassport("+86")))
        #expect(encrypted.count == 128)
    }

    @Test("生产 Core 可在不启动 Node 的情况下完成初始化")
    @MainActor
    func initializesProductionCoreWithoutNetwork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "mhg-core-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let host = LauncherCoreHost(
            environment: ["MHG_DATA_DIR": root.path],
            keychain: MemoryKeychainStore()
        )
        await host.start()
        #expect(host.state == .ready)
        #expect(host.client != nil)
        await host.stop()
        #expect(host.state == .stopped)
    }

    @Test("新数据库采用 v9 且权限为 0600")
    func createsPrivateVersionNineDatabase() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "mhg-core-db-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "mhglauncher.db")
        let database = try CoreDatabase(configuration: .init(databaseURL: url))
        let version = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations")
        }
        #expect(version == 9)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
        try await database.close()
    }

    @Test("既有数据库接管前生成只读业务兼容备份")
    func createsTakeoverBackup() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "mhg-core-backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try PrivateFilesystem.ensureDirectory(root)
        let url = root.appending(path: "mhglauncher.db")
        let legacy = try DatabaseQueue(path: url.path)
        try await legacy.write { db in
            try db.execute(sql: "CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO schema_migrations VALUES(1)")
            try db.execute(sql: "CREATE TABLE account(selected INTEGER NOT NULL DEFAULT 0,aid TEXT PRIMARY KEY,mid TEXT NOT NULL,nickname TEXT NOT NULL,credential_ref TEXT NOT NULL,updated_at TEXT NOT NULL)")
            try db.execute(sql: "CREATE TABLE roles(uid TEXT PRIMARY KEY,account_aid TEXT NOT NULL,nickname TEXT NOT NULL,region TEXT NOT NULL,level INTEGER NOT NULL,selected INTEGER NOT NULL DEFAULT 0)")
            try db.execute(sql: "CREATE TABLE game_state(id INTEGER PRIMARY KEY CHECK(id=1),install_path TEXT NOT NULL,version TEXT NOT NULL,status TEXT NOT NULL,updated_at TEXT NOT NULL)")
            try db.execute(sql: "CREATE TABLE wishes(id TEXT PRIMARY KEY,uid TEXT NOT NULL,gacha_type TEXT NOT NULL,uigf_gacha_type TEXT NOT NULL DEFAULT '',item_id TEXT NOT NULL,name TEXT NOT NULL,item_type TEXT NOT NULL,rank INTEGER NOT NULL,time TEXT NOT NULL)")
            try db.execute(sql: "CREATE TABLE notes(uid TEXT PRIMARY KEY,payload TEXT NOT NULL,refreshed_at TEXT NOT NULL)")
        }
        try legacy.close()
        let database = try CoreDatabase(configuration: .init(databaseURL: url))
        let backup = URL(filePath: url.path + ".pre-swift.bak")
        #expect(GameFilesystem.regularFile(backup))
        let attributes = try FileManager.default.attributesOfItem(atPath: backup.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0 & 0o777 == 0o600)
        try await database.close()
    }

    @Test("mhypbase 失败恢复与伪造日志均不越界")
    func protectsMhypbaseRecovery() async throws {
        let root = try tempDir()
        let game = root.appending(path: "game")
        let session = root.appending(path: "launches/session")
        try PrivateFilesystem.ensureDirectory(game)
        try GameFilesystem.writePrivate(Data("exe".utf8), to: game.appending(path: "YuanShen.exe"))
        try GameFilesystem.writePrivate(Data("game_version=1.0.0\n".utf8), to: game.appending(path: "config.ini"))
        let original = Data("original".utf8)
        let replacement = Data("replacement".utf8)
        let target = game.appending(path: "mhypbase.dll")
        let source = root.appending(path: "source.dll")
        try GameFilesystem.writePrivate(original, to: target)
        try GameFilesystem.writePrivate(replacement, to: source)
        let integrity = MhypbaseIntegrity(
            md5: CoreHash.md5(replacement),
            sha256: SHA256.hash(data: replacement).map { String(format: "%02x", $0) }.joined(),
            size: Int64(replacement.count)
        )
        let journal = try #require(try await MhypbaseManager.prepare(
            gameRoot: game, source: source, sessionDirectory: session, integrity: integrity
        ))
        #expect(try Data(contentsOf: target) == replacement)
        #expect(try MhypbaseManager.restore(journal).isEmpty)
        #expect(try Data(contentsOf: target) == original)

        let outside = root.appending(path: "outside/mhypbase.dll")
        try GameFilesystem.writePrivate(Data("untouched".utf8), to: outside)
        try PrivateFilesystem.ensureDirectory(session)
        let forged = MhypbaseJournal(
            schema: 2, generation: "forged", phase: "planned",
            journalPath: session.appending(path: "dll-journal.json").path,
            gameRoot: root.appending(path: "outside").path,
            target: outside.path, backup: session.appending(path: "mhypbase.original.dll").path,
            originalExists: false, originalSHA256: "", originalMode: 0o600,
            originalDevice: 0, originalInode: 0, replacementMD5: CoreHash.md5(Data("x".utf8))
        )
        try GameFilesystem.writePrivate(JSONEncoder.api.encode(forged), to: session.appending(path: "dll-journal.json"))
        #expect(MhypbaseManager.recover(dataDirectory: root, gameRunning: false) == ["启动 DLL 恢复记录无效，已拒绝执行文件操作"])
        #expect(try Data(contentsOf: outside) == Data("untouched".utf8))
    }

    @Test("游戏启动使用注入进程且以异步流收敛")
    func launchesWithInjectedProcess() async throws {
        let root = try tempDir()
        let runtime = root.appending(path: "runtime")
        let game = root.appending(path: "game")
        for relative in [
            "wine/bin/wine", "wine/bin/wineboot", "wine/bin/wineserver",
            "wine/lib/wine/x86_64-windows/winemetal.dll", "lib/libmhg_dns_gate.dylib",
            "bin/mhg-window-probe"
        ] {
            try GameFilesystem.writePrivate(Data("fixture".utf8), to: runtime.appending(path: relative))
        }
        let replacement = Data("pinned".utf8)
        try GameFilesystem.writePrivate(replacement, to: runtime.appending(path: "assets/mhypbase.dll"))
        try PrivateFilesystem.ensureDirectory(game)
        try GameFilesystem.writePrivate(Data("exe".utf8), to: game.appending(path: "YuanShen.exe"))
        try GameFilesystem.writePrivate(Data("game_version=1.0.0\n".utf8), to: game.appending(path: "config.ini"))
        let database = try CoreDatabase(configuration: .init(databaseURL: root.appending(path: "mhglauncher.db")))
        let provider = FixtureProvider()
        let accounts = CoreAccountService(database: database, provider: provider, keychain: MemoryKeychainStore())
        let runner = RecordingProcessRunner()
        let service = CoreGameLaunchService(
            dataDirectory: root, runtimeRoot: runtime, accounts: accounts, provider: provider,
            runner: runner, prefixManager: WinePrefixManager(runner: runner),
            windowProbe: FixtureWindowProbe(),
            mhypbaseIntegrity: MhypbaseIntegrity(
                md5: CoreHash.md5(replacement),
                sha256: SHA256.hash(data: replacement).map { String(format: "%02x", $0) }.joined(),
                size: Int64(replacement.count)
            )
        )
        let initial = try await service.start(StartGameLaunchRequest(
            installPath: game.path, performanceProfile: .optimized, metalHud: false,
            networkDebug: false, wineLog: false, framePacing: 60,
            launchArguments: #"-popupwindow -screen-width "1920""#
        ))
        var terminal: GameLaunch?
        for try await event in service.events(initial.id, after: initial.revision) { terminal = event }
        #expect(terminal?.status == .exited)
        let requests = await runner.requests
        let gameRequest = requests.first { $0.arguments.first == "YuanShen.exe" }
        #expect(gameRequest?.arguments.contains("-popupwindow") == true)
        #expect(gameRequest?.arguments.contains("1920") == true)
        #expect(requests.allSatisfy { !$0.executable.path.contains("node") })
        try await database.close()
    }
}

private actor RecordingProcessRunner: CoreProcessRunning {
    private(set) var requests: [CoreProcessRequest] = []
    func run(_ request: CoreProcessRequest) async throws -> Int32 {
        requests.append(request)
        return 0
    }
    func terminate() {}
    func processIdentifier() -> Int32? { nil }
}

private struct FixtureWindowProbe: WindowProbing {
    func snapshot(executable: URL) async throws -> String { "fixture" }
    func status(executable: URL, processID: Int32, snapshot: String) async throws -> Int32 { 0 }
}
