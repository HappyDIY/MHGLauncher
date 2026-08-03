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
        do {
            PrivateFilesystem.configureProcessUmask()
            let dataDirectory = try Self.dataDirectory(environment: environment)
            try PrivateFilesystem.ensureDirectory(dataDirectory)
            let database = try CoreDatabase(configuration: .init(
                databaseURL: dataDirectory.appending(path: "mhglauncher.db")
            ))
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
            let cloudURL = environment["MHG_CLOUD_URL"].flatMap(URL.init(string:))
            let mirrorURLs = (environment["MHG_METADATA_MIRRORS"] ?? "")
                .split(separator: ",")
                .compactMap { URL(string: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            let metadataRepository: CoreMetadataRepository? = fixtureMode ? nil : CoreMetadataRepository(
                dataDirectory: dataDirectory,
                discoveryBaseURL: cloudURL,
                configuredMirrors: mirrorURLs,
                transport: transport
            )
            let resources = CoreResourceService(
                repository: metadataRepository,
                activeSnapshot: await metadataRepository?.activeSnapshot()
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
            let characters = CoreCharacterService(database: database, records: records, accounts: accounts)
            let achievements = CoreAchievementService(database: database, resources: resources)
            let notifications = CoreNotificationService(database: database, resources: resources)
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
            let images = try CoreImageService(dataDirectory: dataDirectory, transport: transport)
            let runtimeTag = environment["MHG_RUNTIME_TAG"]?.nonempty
                ?? RuntimeManifest.defaultTag()
            let hpatchzURL = environment["MHG_HPATCHZ"]?.nonempty.map { URL(filePath: $0) }
                ?? dataDirectory.appending(path: "Runtimes/\(runtimeTag)/tools/hpatchz")
            let game = CoreGameService(
                database: database,
                provider: provider,
                jobs: GameJobCoordinator(),
                dataDirectory: dataDirectory,
                fixtureMode: fixtureMode,
                hpatchzURL: hpatchzURL
            )
            let runtimeRoot = environment["MHG_GAME_RUNTIME_ROOT"]?.nonempty.map { URL(filePath: $0) }
                ?? dataDirectory.appending(path: "Runtimes/\(runtimeTag)/game-runtime")
            let launches = CoreGameLaunchService(
                dataDirectory: dataDirectory,
                runtimeRoot: runtimeRoot,
                accounts: accounts,
                provider: provider
            )
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
            self.database = database
            self.launches = launches
            self.game = game
            self.wishTasks = wishTasks
            try Self.cleanLegacyCoreAssets(dataDirectory: dataDirectory)
            state = .ready
        } catch let error as LauncherCoreError {
            state = .failed(code: error.code, message: error.message)
        } catch {
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

    private static func dataDirectory(environment: [String: String]) throws -> URL {
        if let override = environment["MHG_DATA_DIR"]?.nonempty {
            let value = URL(filePath: override).standardizedFileURL
            guard !override.contains("\0") else {
                throw LauncherCoreError(code: "unsafe_data_path", message: "数据目录无效")
            }
            return value
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/MHGLauncher")
    }

    private static func cleanLegacyCoreAssets(dataDirectory: URL) throws {
        let ledger = dataDirectory.appending(path: "swift-core-takeover.json")
        guard !FileManager.default.fileExists(atPath: ledger.path) else { return }
        let runtimes = dataDirectory.appending(path: "Runtimes")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: runtimes,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ) else { return }
        for root in entries {
            let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let ledgerURL = root.appending(path: ".mhg-runtime-ledger.json")
            guard GameFilesystem.regularFile(ledgerURL),
                  let data = try? Data(contentsOf: ledgerURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["schema_version"] != nil || object["schemaVersion"] != nil else { continue }
            for relative in ["node", "backend/app"] {
                let target = root.appending(path: relative)
                guard target.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else { continue }
                try? FileManager.default.removeItem(at: target)
            }
        }
        let payload = try JSONSerialization.data(withJSONObject: [
            "schema": 1, "completed_at": CoreDate.string(Date())
        ], options: [.sortedKeys])
        try GameFilesystem.writePrivate(payload, to: ledger)
    }
}
