import Foundation
import GRDB

actor CoreDatabase {
    struct Configuration: Sendable {
        let databaseURL: URL

        static var production: Self {
            let root = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/MHGLauncher", directoryHint: .isDirectory)
            return Self(databaseURL: root.appending(path: "mhglauncher.db"))
        }
    }

    private let pool: DatabasePool

    init(configuration: Configuration) throws {
        let url = configuration.databaseURL.standardizedFileURL
        try PrivateFilesystem.ensureDirectory(url.deletingLastPathComponent())
        try PrivateFilesystem.requireRegularFileIfPresent(url)
        let backupURL = URL(filePath: url.path + ".pre-swift.bak")
        try PrivateFilesystem.requireRegularFileIfPresent(backupURL)
        for suffix in ["-wal", "-shm"] {
            try PrivateFilesystem.requireRegularFileIfPresent(URL(filePath: url.path + suffix))
        }

        // 先收紧旧数据库与 WAL 文件权限，再让 GRDB 打开它们，避免在迁移窗口暴露敏感数据。
        if GameFilesystem.regularFile(url) {
            try PrivateFilesystem.setPrivateFilePermissions(url)
        }
        if GameFilesystem.regularFile(backupURL) {
            try PrivateFilesystem.setPrivateFilePermissions(backupURL)
        }
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(filePath: url.path + suffix)
            if GameFilesystem.regularFile(sidecar) {
                try PrivateFilesystem.setPrivateFilePermissions(sidecar)
            }
        }

        let existed = GameFilesystem.regularFile(url)
        let pool = try Self.openPool(databaseURL: url, backupURL: backupURL)
        do {
            if existed && !GameFilesystem.regularFile(backupURL) {
                try Self.createTakeoverBackup(pool: pool, at: backupURL)
            }
            try Self.migrate(pool)
        } catch {
            try? pool.close()
            throw error
        }
        try PrivateFilesystem.setPrivateFilePermissions(url)
        if GameFilesystem.regularFile(backupURL) {
            try PrivateFilesystem.setPrivateFilePermissions(backupURL)
        }
        self.pool = pool
    }

    func read<T: Sendable>(_ body: @Sendable (Database) throws -> T) async throws -> T {
        try await pool.read(body)
    }

    func write<T: Sendable>(_ body: @Sendable (Database) throws -> T) async throws -> T {
        try await pool.write(body)
    }

    func close() throws {
        try pool.close()
    }

    private static func openPool(databaseURL: URL, backupURL: URL) throws -> DatabasePool {
        do {
            return try makePool(databaseURL)
        } catch {
            guard GameFilesystem.regularFile(backupURL) else { throw error }
            try PrivateFilesystem.requireRegularFileIfPresent(backupURL)
            let corruptURL = URL(filePath: databaseURL.path + ".corrupt-" + UUID().uuidString)
            try PrivateFilesystem.rejectSymbolicLinks(in: corruptURL)
            let sidecars = [
                (original: URL(filePath: databaseURL.path + "-wal"), suffix: ".wal"),
                (original: URL(filePath: databaseURL.path + "-shm"), suffix: ".shm")
            ]
            var movedDatabase = false
            var movedSidecars: [(original: URL, corrupt: URL)] = []
            do {
                try FileManager.default.moveItem(at: databaseURL, to: corruptURL)
                movedDatabase = true
                for sidecar in sidecars where FileManager.default.fileExists(atPath: sidecar.original.path) {
                    try PrivateFilesystem.requireRegularFileIfPresent(sidecar.original)
                    let corruptSidecar = URL(filePath: corruptURL.path + sidecar.suffix)
                    try PrivateFilesystem.rejectSymbolicLinks(in: corruptSidecar)
                    try FileManager.default.moveItem(at: sidecar.original, to: corruptSidecar)
                    movedSidecars.append((sidecar.original, corruptSidecar))
                }
                try FileManager.default.copyItem(at: backupURL, to: databaseURL)
                try PrivateFilesystem.setPrivateFilePermissions(databaseURL)
                return try makePool(databaseURL)
            } catch {
                if movedDatabase {
                    try? PrivateFilesystem.removeRegularFileIfPresent(databaseURL)
                    try? FileManager.default.moveItem(at: corruptURL, to: databaseURL)
                }
                for moved in movedSidecars.reversed() {
                    try? PrivateFilesystem.removeRegularFileIfPresent(moved.original)
                    try? FileManager.default.moveItem(at: moved.corrupt, to: moved.original)
                }
                throw error
            }
        }
    }

    private static func makePool(_ url: URL) throws -> DatabasePool {
        var configuration = GRDB.Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=WAL")
            try db.execute(sql: "PRAGMA busy_timeout=5000")
        }
        return try DatabasePool(path: url.path, configuration: configuration)
    }

    private static func createTakeoverBackup(pool: DatabasePool, at backupURL: URL) throws {
        try PrivateFilesystem.rejectSymbolicLinks(in: backupURL)
        try pool.writeWithoutTransaction { db in
            _ = try Row.fetchAll(db, sql: "PRAGMA wal_checkpoint(FULL)")
            try db.execute(sql: "VACUUM INTO ?", arguments: [backupURL.path])
        }
        try PrivateFilesystem.setPrivateFilePermissions(backupURL)
    }

    private static func migrate(_ pool: DatabasePool) throws {
        try pool.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY)")
            var current = try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations") ?? 0
            if current < 1 { try migration1(db); current = 1 }
            if current < 2 { try migration2(db); current = 2 }
            if current < 3 { try migration3(db); current = 3 }
            if current < 4 { try migration4(db); current = 4 }
            if current < 5 { try migration5(db); current = 5 }
            if current < 6 { try migration6(db); current = 6 }
            if current < 7 { try migration7(db); current = 7 }
            if current < 8 { try migration8(db); current = 8 }
            if current < 9 { try migration9(db) }
        }
    }

    private static func record(_ version: Int, in db: Database) throws {
        try db.execute(
            sql: "INSERT OR IGNORE INTO schema_migrations(version) VALUES(?)",
            arguments: [version]
        )
    }

    private static func migration1(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS account(selected INTEGER NOT NULL DEFAULT 0,aid TEXT PRIMARY KEY,mid TEXT NOT NULL,nickname TEXT NOT NULL,credential_ref TEXT NOT NULL,updated_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS roles(uid TEXT PRIMARY KEY,account_aid TEXT NOT NULL,nickname TEXT NOT NULL,region TEXT NOT NULL,level INTEGER NOT NULL,selected INTEGER NOT NULL DEFAULT 0,FOREIGN KEY(account_aid) REFERENCES account(aid) ON DELETE CASCADE);
            CREATE TABLE IF NOT EXISTS game_state(id INTEGER PRIMARY KEY CHECK(id=1),install_path TEXT NOT NULL,version TEXT NOT NULL,status TEXT NOT NULL,updated_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS wishes(id TEXT PRIMARY KEY,uid TEXT NOT NULL,gacha_type TEXT NOT NULL,uigf_gacha_type TEXT NOT NULL DEFAULT '',item_id TEXT NOT NULL,name TEXT NOT NULL,item_type TEXT NOT NULL,rank INTEGER NOT NULL,time TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS wishes_uid_type ON wishes(uid,gacha_type,time DESC);
            CREATE TABLE IF NOT EXISTS notes(uid TEXT PRIMARY KEY,payload TEXT NOT NULL,refreshed_at TEXT NOT NULL);
            """)
        try record(1, in: db)
    }

    private static func migration2(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS characters(uid TEXT NOT NULL,avatar_id TEXT NOT NULL,name TEXT NOT NULL,element TEXT NOT NULL,level INTEGER NOT NULL,rarity INTEGER NOT NULL,constellation INTEGER NOT NULL,fetter INTEGER NOT NULL,weapon_name TEXT NOT NULL,weapon_level INTEGER NOT NULL,icon_url TEXT,payload TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(uid,avatar_id));
            CREATE TABLE IF NOT EXISTS achievement_archives(id TEXT PRIMARY KEY,name TEXT NOT NULL,selected INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL,updated_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS achievements(archive_id TEXT NOT NULL,achievement_id INTEGER NOT NULL,current INTEGER NOT NULL,status INTEGER NOT NULL,timestamp INTEGER NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(archive_id,achievement_id),FOREIGN KEY(archive_id) REFERENCES achievement_archives(id) ON DELETE CASCADE);
            CREATE TABLE IF NOT EXISTS gacha_events(id TEXT PRIMARY KEY,version TEXT NOT NULL,gacha_type TEXT NOT NULL,name TEXT NOT NULL,started_at TEXT NOT NULL,ended_at TEXT NOT NULL,orange_up TEXT NOT NULL,purple_up TEXT NOT NULL,banner_url TEXT,updated_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS notification_settings(id INTEGER PRIMARY KEY CHECK(id=1),daily_commission_enabled INTEGER NOT NULL,daily_commission_time TEXT NOT NULL,resin_full_enabled INTEGER NOT NULL,gacha_refresh_enabled INTEGER NOT NULL,version_update_enabled INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS notification_state(key TEXT PRIMARY KEY,last_triggered_at TEXT NOT NULL,state TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS cloud_sessions(uid TEXT PRIMARY KEY,token_ref TEXT NOT NULL,reverified_at TEXT NOT NULL,updated_at TEXT NOT NULL);
            INSERT OR IGNORE INTO notification_settings(id,daily_commission_enabled,daily_commission_time,resin_full_enabled,gacha_refresh_enabled,version_update_enabled) VALUES(1,0,'20:00',0,1,1);
            """)
        try record(2, in: db)
    }

    private static func migration3(_ db: Database) throws {
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS wishes_uid_time_id ON wishes(uid,time DESC,id DESC);
            CREATE INDEX IF NOT EXISTS wishes_uid_type_time_id ON wishes(uid,gacha_type,time DESC,id DESC);
            CREATE INDEX IF NOT EXISTS wishes_uid_uigf_time_id ON wishes(uid,uigf_gacha_type,time DESC,id DESC);
            """)
        try record(3, in: db)
    }

    private static func migration4(_ db: Database) throws {
        try db.execute(sql: """
            DROP TABLE IF EXISTS cycle_records;
            DELETE FROM notification_state WHERE key LIKE 'cycle:abyss:%' OR key LIKE 'cycle:theatre:%' OR key LIKE 'cycle:hard:%';
            ALTER TABLE notification_settings RENAME TO notification_settings_legacy;
            CREATE TABLE notification_settings(id INTEGER PRIMARY KEY CHECK(id=1),daily_commission_enabled INTEGER NOT NULL,daily_commission_time TEXT NOT NULL,resin_full_enabled INTEGER NOT NULL,gacha_refresh_enabled INTEGER NOT NULL,version_update_enabled INTEGER NOT NULL);
            INSERT INTO notification_settings SELECT * FROM notification_settings_legacy;
            DROP TABLE notification_settings_legacy;
            """)
        try record(4, in: db)
    }

    private static func migration5(_ db: Database) throws {
        if try db.tableExists("account_legacy") {
            try createAccount(db)
            try db.execute(sql: "INSERT OR IGNORE INTO account SELECT selected,aid,mid,nickname,credential_ref,updated_at FROM account_legacy; DROP TABLE account_legacy")
        } else if try columns(db, "account").contains("id") {
            try db.execute(sql: "ALTER TABLE account RENAME TO account_legacy")
            try createAccount(db)
            try db.execute(sql: "INSERT OR IGNORE INTO account SELECT 1,aid,mid,nickname,credential_ref,updated_at FROM account_legacy; DROP TABLE account_legacy")
        }

        if try db.tableExists("roles_legacy") {
            try createRoles(db)
            try copyLegacyRoles(db)
        } else if try !hasPrimaryKey(db, table: "roles", columns: ["account_aid", "uid"]) {
            try db.execute(sql: "ALTER TABLE roles RENAME TO roles_legacy")
            try createRoles(db)
            try copyLegacyRoles(db)
        }
        try record(5, in: db)
    }

    private static func migration6(_ db: Database) throws {
        if try hasPrimaryKey(db, table: "wishes", columns: ["uid", "id"]),
           try columns(db, "wishes").contains("time_epoch") {
            try record(6, in: db)
            return
        }
        if try !db.tableExists("wishes_legacy") {
            try db.execute(sql: "ALTER TABLE wishes RENAME TO wishes_legacy")
        }
        try createWishes(db)
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM wishes_legacy LIMIT 250001")
        guard rows.count <= 250_000 else {
            throw LauncherCoreError(code: "database_payload_too_large", message: "历史祈愿数据超过迁移限制")
        }
        for row in rows {
            let value: String = row["time"] ?? ""
            let uid: String = row["uid"] ?? ""
            let id: String = row["id"] ?? ""
            guard let normalized = normalizedTime(value) else {
                try db.execute(
                    sql: "INSERT INTO wishes_quarantine(uid,id,payload,reason) VALUES(?,?,?,?)",
                    arguments: [uid, id, "{}", "invalid_time"]
                )
                continue
            }
            try db.execute(sql: """
                INSERT INTO wishes(id,uid,gacha_type,uigf_gacha_type,item_id,name,item_type,rank,time,time_epoch)
                VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(uid,id) DO NOTHING
                """, arguments: [
                    id, uid, row["gacha_type"], row["uigf_gacha_type"] ?? "", row["item_id"],
                    row["name"], row["item_type"], row["rank"], normalized.iso, normalized.epoch
                ])
        }
        try db.execute(sql: "DROP TABLE wishes_legacy")
        try record(6, in: db)
    }

    private static func migration7(_ db: Database) throws {
        if try !columns(db, "achievement_archives").contains("revision") {
            try db.execute(sql: "ALTER TABLE achievement_archives ADD COLUMN revision INTEGER NOT NULL DEFAULT 0")
        }
        try record(7, in: db)
    }

    private static func migration8(_ db: Database) throws {
        try verifySecuritySchema(db)
        try record(8, in: db)
    }

    private static func migration9(_ db: Database) throws {
        try verifySecuritySchema(db)
        try record(9, in: db)
    }

    private static func createAccount(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS account(selected INTEGER NOT NULL DEFAULT 0,aid TEXT PRIMARY KEY,
            mid TEXT NOT NULL,nickname TEXT NOT NULL,credential_ref TEXT NOT NULL,updated_at TEXT NOT NULL)
            """)
    }

    private static func createRoles(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS roles(uid TEXT NOT NULL,account_aid TEXT NOT NULL,nickname TEXT NOT NULL,
            region TEXT NOT NULL,level INTEGER NOT NULL,selected INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(account_aid,uid),FOREIGN KEY(account_aid) REFERENCES account(aid) ON DELETE CASCADE)
            """)
    }

    private static func copyLegacyRoles(_ db: Database) throws {
        if try columns(db, "roles_legacy").contains("account_aid") {
            try db.execute(sql: "INSERT OR IGNORE INTO roles SELECT uid,account_aid,nickname,region,level,selected FROM roles_legacy")
        } else if let aid = try String.fetchOne(
            db, sql: "SELECT aid FROM account ORDER BY selected DESC,updated_at DESC LIMIT 1"
        ) {
            try db.execute(sql: """
                INSERT OR IGNORE INTO roles(uid,account_aid,nickname,region,level,selected)
                SELECT uid,?,nickname,region,level,selected FROM roles_legacy
                """, arguments: [aid])
        }
        try db.execute(sql: "DROP TABLE roles_legacy")
    }

    private static func createWishes(_ db: Database) throws {
        try db.execute(sql: """
            DROP INDEX IF EXISTS wishes_uid_type;
            DROP INDEX IF EXISTS wishes_uid_time_id;
            DROP INDEX IF EXISTS wishes_uid_type_time_id;
            DROP INDEX IF EXISTS wishes_uid_uigf_time_id;
            CREATE TABLE IF NOT EXISTS wishes(id TEXT NOT NULL,uid TEXT NOT NULL,gacha_type TEXT NOT NULL,
            uigf_gacha_type TEXT NOT NULL DEFAULT '',item_id TEXT NOT NULL,name TEXT NOT NULL,item_type TEXT NOT NULL,
            rank INTEGER NOT NULL,time TEXT NOT NULL,time_epoch INTEGER NOT NULL,PRIMARY KEY(uid,id));
            CREATE TABLE IF NOT EXISTS wishes_quarantine(uid TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,reason TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS wishes_uid_time_id ON wishes(uid,time_epoch DESC,LENGTH(id) DESC,id DESC);
            CREATE INDEX IF NOT EXISTS wishes_uid_type_time_id ON wishes(uid,gacha_type,time_epoch DESC,LENGTH(id) DESC,id DESC);
            CREATE INDEX IF NOT EXISTS wishes_uid_uigf_time_id ON wishes(uid,uigf_gacha_type,time_epoch DESC,LENGTH(id) DESC,id DESC);
            """)
    }

    private static func verifySecuritySchema(_ db: Database) throws {
        guard try hasPrimaryKey(db, table: "roles", columns: ["account_aid", "uid"]),
              try hasPrimaryKey(db, table: "wishes", columns: ["uid", "id"]),
              try columns(db, "wishes").contains("time_epoch") else {
            throw LauncherCoreError(code: "invalid_database_schema", message: "数据库结构校验失败")
        }
    }

    private static func columns(_ db: Database, _ table: String) throws -> [String] {
        try db.columns(in: table).map(\.name)
    }

    private static func hasPrimaryKey(
        _ db: Database,
        table: String,
        columns expected: [String]
    ) throws -> Bool {
        let actual = try db.columns(in: table)
            .filter { $0.primaryKeyIndex > 0 }
            .sorted { $0.primaryKeyIndex < $1.primaryKeyIndex }
            .map(\.name)
        return actual == expected
    }

    private static func normalizedTime(_ value: String) -> (iso: String, epoch: Int64)? {
        let normalized = value.contains("T") ? value : value.replacingOccurrences(of: " ", with: "T")
        let explicit = normalized.range(of: #"(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) == nil
            ? normalized + "+08:00" : normalized
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: explicit) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: explicit)
        }()
        guard let date else { return nil }
        formatter.formatOptions = [.withInternetDateTime]
        return (formatter.string(from: date), Int64(date.timeIntervalSince1970))
    }
}
