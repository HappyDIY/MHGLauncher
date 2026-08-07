import Foundation
import Observation

enum LauncherCoreState: Equatable, Sendable {
    case idle
    case initializing
    case ready
    case failed(code: String, message: String)
    case shuttingDown
    case stopped
}

@MainActor
@Observable
final class LauncherCoreHost {
    private(set) var state: LauncherCoreState = .idle
    private(set) var client: LauncherClient?
    private var database: CoreDatabase?
    private var launches: CoreGameLaunchService?
    private var game: CoreGameService?
    private var wishTasks: WishTaskCoordinator?
    private let environment: [String: String]
    private let keychain: any KeychainStoring

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        keychain: any KeychainStoring = KeychainStore()
    ) {
        self.environment = environment
        self.keychain = keychain
    }

    func start() async {
        guard state == .idle || state == .stopped else { return }
        state = .initializing
        var openedDatabase: CoreDatabase?
        do {
            PrivateFilesystem.configureProcessUmask()
            let dataDirectory = try Self.dataDirectory(environment: environment)
            try PrivateFilesystem.ensureDirectory(dataDirectory)
            let database = try CoreDatabase(configuration: .init(
                databaseURL: dataDirectory.appending(path: "mhglauncher.db")
            ))
            openedDatabase = database
            self.database = database
            let fixtureMode = environment["MHG_PROVIDER_MODE"] == "fixture"
                || environment["MHG_SMOKE_MODE"] == "1"
            let transport = URLSessionHTTPTransport()
            let provider: any GameProvider
            let records: any GameRecordProvider
            if fixtureMode {
                provider = FixtureProvider()
                records = FixtureGameRecordProvider()
            } else {
                provider = try LiveGameProvider(dataDirectory: dataDirectory, transport: transport)
                records = try LiveGameRecordProvider(dataDirectory: dataDirectory, transport: transport)
            }
            let cloudURL = Self.cloudBaseURL(environment: environment)
            let mirrorURLs = (environment["MHG_METADATA_MIRRORS"] ?? "")
                .split(separator: ",")
                .compactMap { URL(string: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            let metadataRepository: CoreMetadataRepository? = fixtureMode ? nil : CoreMetadataRepository(
                dataDirectory: dataDirectory,
                discoveryBaseURL: cloudURL,
                configuredMirrors: mirrorURLs,
                transport: transport
            )
            let images = try CoreImageService(dataDirectory: dataDirectory, transport: transport)
            let resources = CoreResourceService(
                repository: metadataRepository,
                activeSnapshot: await metadataRepository?.activeSnapshot(),
                fixtureMode: fixtureMode,
                dataDirectory: dataDirectory,
                images: images
            )
            let accounts = CoreAccountService(database: database, provider: provider, keychain: keychain)
            let notes = CoreNoteService(database: database, provider: provider, accounts: accounts)
            let wishes = CoreWishService(
                database: database,
                provider: provider,
                accounts: accounts,
                notes: notes,
                resources: resources
            )
            let wishTasks = WishTaskCoordinator()
            self.wishTasks = wishTasks
            let characters = CoreCharacterService(
                database: database,
                records: records,
                accounts: accounts,
                resources: resources,
                images: images
            )
            let achievements = CoreAchievementService(database: database, resources: resources)
            let cloud = CoreCloudService(
                database: database,
                accounts: accounts,
                provider: provider,
                wishes: wishes,
                achievements: achievements,
                keychain: keychain,
                transport: transport,
                baseURL: cloudURL,
                dataDirectory: dataDirectory,
                fixtureMode: fixtureMode
            )
            let updates = CoreUpdateService(cloudBaseURL: cloudURL, transport: transport, fixtureMode: fixtureMode)
            let runtimeTag = environment["MHG_RUNTIME_TAG"].flatMap { value in
                value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$"#, options: .regularExpression) != nil
                    ? value : nil
            } ?? RuntimeManifest.defaultTag()
            let hpatchzURL = environment["MHG_HPATCHZ"]?.nonempty
                .flatMap(Self.absolutePath)
                ?? dataDirectory.appending(path: "Runtimes/\(runtimeTag)/tools/hpatchz")
            let gameOperationCoordinator = GameOperationCoordinator()
            let game = CoreGameService(
                database: database,
                provider: provider,
                jobs: GameJobCoordinator(),
                dataDirectory: dataDirectory,
                fixtureMode: fixtureMode,
                hpatchzURL: hpatchzURL,
                operationCoordinator: gameOperationCoordinator,
                onInstalled: { _ in _ = try? await resources.sync(force: false) }
            )
            self.game = game
            let notifications = CoreNotificationService(database: database, resources: resources, game: game)
            let runtimeRoot = environment["MHG_GAME_RUNTIME_ROOT"]?.nonempty
                .flatMap(Self.absolutePath)
                ?? dataDirectory.appending(path: "Runtimes/\(runtimeTag)/game-runtime")
            let launches = CoreGameLaunchService(
                dataDirectory: dataDirectory,
                runtimeRoot: runtimeRoot,
                accounts: accounts,
                provider: provider,
                operationCoordinator: gameOperationCoordinator
            )
            self.launches = launches
            client = CoreLauncherClient.make(
                accounts: accounts,
                game: game,
                launches: launches,
                wishes: wishes,
                wishTasks: wishTasks,
                notes: notes,
                characters: characters,
                resources: resources,
                achievements: achievements,
                cloud: cloud,
                notifications: notifications,
                updates: updates,
                images: images
            )
            try Self.cleanLegacyCoreAssets(dataDirectory: dataDirectory)
            state = .ready
        } catch let error as LauncherCoreError {
            await cleanupAfterFailedStart(openedDatabase)
            state = .failed(code: error.code, message: error.message)
        } catch {
            await cleanupAfterFailedStart(openedDatabase)
            state = .failed(code: "core_initialization_failed", message: "Launcher Core 初始化失败")
        }
    }

    func stop() async {
        guard state != .stopped else { return }
        state = .shuttingDown
        await wishTasks?.shutdown()
        await game?.shutdown()
        await launches?.shutdown()
        wishTasks = nil
        game = nil
        launches = nil
        client = nil
        try? await database?.close()
        database = nil
        state = .stopped
    }

    private func cleanupAfterFailedStart(_ openedDatabase: CoreDatabase?) async {
        await wishTasks?.shutdown()
        await game?.shutdown()
        await launches?.shutdown()
        wishTasks = nil
        game = nil
        launches = nil
        client = nil
        let value = database ?? openedDatabase
        database = nil
        try? await value?.close()
    }

    private static func dataDirectory(environment: [String: String]) throws -> URL {
        if let override = environment["MHG_DATA_DIR"]?.nonempty {
            guard let value = absolutePath(override) else {
                throw LauncherCoreError(code: "unsafe_data_path", message: "数据目录无效")
            }
            return value
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/MHGLauncher")
    }

    private static func absolutePath(_ value: String) -> URL? {
        guard !value.isEmpty,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let url = URL(filePath: value).standardizedFileURL
        return url.path.hasPrefix("/") ? url : nil
    }

    private static func cloudBaseURL(environment: [String: String]) -> URL? {
        let raw = environment["MHG_CLOUD_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonempty
            ?? environment["MHG_CLOUD_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonempty
            ?? (Bundle.main.object(forInfoDictionaryKey: "MHGCloudBaseURL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonempty
        guard let raw,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host?.nonempty != nil,
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              url.query == nil,
              url.fragment == nil else { return nil }
        return url
    }

    private static func cleanLegacyCoreAssets(dataDirectory: URL) throws {
        let ledger = dataDirectory.appending(path: "swift-core-takeover.json")
        let runtimes = dataDirectory.appending(path: "Runtimes")
        guard (try? PrivateFilesystem.rejectSymbolicLinks(in: runtimes)) != nil else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: runtimes,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ) else { return }
        for root in entries {
            let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            guard hasLegacyRuntimeMarker(at: root) else { continue }
            var cleanupFailed = false
            for relative in ["node", "backend"] {
                let target = root.appending(path: relative)
                guard target.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else { continue }
                do {
                    if (try? target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))?.isDirectory == true {
                        try PrivateFilesystem.removeDirectoryIfPresent(target)
                    } else {
                        try PrivateFilesystem.removeRegularFileIfPresent(target)
                    }
                } catch {
                    cleanupFailed = true
                }
            }
            if cleanupFailed { return }
        }
        let payload = try JSONSerialization.data(withJSONObject: [
            "schema": 1, "completed_at": CoreDate.string(Date())
        ], options: [.sortedKeys])
        try GameFilesystem.writePrivate(payload, to: ledger)
    }

    private static func hasLegacyRuntimeMarker(at root: URL) -> Bool {
        let marker = root.appending(path: RuntimeInstallLedger.markerName)
        if GameFilesystem.regularFile(marker),
           let values = try? marker.resourceValues(forKeys: [.fileSizeKey]),
           (values.fileSize ?? 0) <= 1024 * 1024,
           let data = try? Data(contentsOf: marker, options: .mappedIfSafe),
           let record = try? JSONDecoder().decode(RuntimeInstallRecord.self, from: data),
           (record.schemaVersion == 2 || record.schemaVersion == 3),
           record.tag == root.lastPathComponent,
           record.appVersion.utf8.count <= 128,
           record.manifestDigest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
           !record.requiredPaths.isEmpty,
           record.requiredPaths.count <= 4_096,
           record.requiredPaths.allSatisfy(RuntimeManifest.isSafeRelativePath) {
            return true
        }
        for name in [".mhg-runtime-ledger.json", ".core-complete", ".game-complete"] {
            let candidate = root.appending(path: name)
            guard GameFilesystem.regularFile(candidate),
                  let values = try? candidate.resourceValues(forKeys: [.fileSizeKey]),
                  (values.fileSize ?? 0) <= 1024 * 1024 else { continue }
            if name != ".mhg-runtime-ledger.json" { return true }
            guard let data = try? Data(contentsOf: candidate, options: .mappedIfSafe),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["schema_version"] != nil || object["schemaVersion"] != nil else { continue }
            return true
        }
        return false
    }
}
