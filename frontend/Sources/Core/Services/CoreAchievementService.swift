import Foundation
import GRDB

actor CoreAchievementService {
    private let database: CoreDatabase
    private let resources: CoreResourceService

    init(database: CoreDatabase, resources: CoreResourceService) {
        self.database = database
        self.resources = resources
    }

    func archive(uid: String) async throws -> AchievementArchive {
        guard uid.range(of: #"^\d{9,10}$"#, options: .regularExpression) != nil else {
            throw LauncherCoreError(code: "uid_invalid", message: "角色 UID 无效")
        }
        let now = Date()
        try await database.write { db in
            try db.execute(sql: "UPDATE achievement_archives SET selected=0")
            try db.execute(sql: """
                INSERT INTO achievement_archives(id,name,selected,created_at,updated_at,revision)
                VALUES(?,?,1,?,?,0) ON CONFLICT(id) DO UPDATE SET name=excluded.name,selected=1
                """, arguments: [uid, uid, CoreDate.string(now), CoreDate.string(now)])
        }
        return try await requireArchive(uid)
    }

    func goals() async throws -> [AchievementGoal] { try await resources.achievementGoals() }

    func snapshot(archiveID: String) async throws -> AchievementSnapshot {
        let archive = try await requireArchive(archiveID)
        let saved = try await items(archiveID: archiveID)
        let entries = try await resources.achievementEntries(
            archiveID: archiveID,
            saved: Dictionary(uniqueKeysWithValues: saved.map { ($0.achievementId, $0) })
        )
        return AchievementSnapshot(
            archive: archive,
            entries: entries,
            revision: archive.revision ?? 0
        )
    }

    func save(_ request: AchievementSaveRequest) async throws -> AchievementSnapshot {
        let progress = try await resources.achievementProgress()
        let now = Date()
        try await database.write { db in
            let current = try Int.fetchOne(
                db,
                sql: "SELECT revision FROM achievement_archives WHERE id=?",
                arguments: [request.archiveId]
            )
            guard let current else {
                throw LauncherCoreError(code: "archive_missing", message: "成就档案不存在")
            }
            guard current == request.expectedRevision else {
                throw LauncherCoreError(
                    code: "archive_revision_conflict",
                    message: "成就档案已被其他操作更新"
                )
            }
            for item in request.items {
                let normalized = item.status >= 2
                    ? max(item.current, progress[item.achievementId] ?? 0) : item.current
                try db.execute(sql: """
                    INSERT INTO achievements(archive_id,achievement_id,current,status,timestamp,updated_at)
                    VALUES(?,?,?,?,?,?) ON CONFLICT(archive_id,achievement_id) DO UPDATE SET
                    current=excluded.current,status=excluded.status,timestamp=excluded.timestamp,
                    updated_at=excluded.updated_at
                    """, arguments: [
                        request.archiveId, item.achievementId, normalized, item.status,
                        item.timestamp, CoreDate.string(now)
                    ])
            }
            try db.execute(sql: """
                UPDATE achievement_archives SET revision=revision+1,updated_at=? WHERE id=?
                """, arguments: [CoreDate.string(now), request.archiveId])
        }
        return try await snapshot(archiveID: request.archiveId)
    }

    func importUIAF(data: Data, archiveID: String, expectedRevision: Int) async throws -> AchievementSnapshot {
        guard data.count <= 64 * 1024 * 1024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["list"] as? [[String: Any]], list.count <= 200_000 else {
            throw LauncherCoreError(code: "uiaf_invalid", message: "UIAF 文件格式无效")
        }
        let items = list.compactMap { value -> AchievementItemInput? in
            guard let id = Self.int(value["id"]), id > 0 else { return nil }
            return AchievementItemInput(
                achievementId: id,
                current: Self.int(value["current"]) ?? 0,
                status: Self.int(value["status"]) ?? 0,
                timestamp: Self.int(value["timestamp"]) ?? 0
            )
        }
        return try await save(AchievementSaveRequest(
            archiveId: archiveID,
            expectedRevision: expectedRevision,
            items: items
        ))
    }

    func exportUIAF(archiveID: String) async throws -> Data {
        let list = try await items(archiveID: archiveID).map { value in
            [
                "id": value.achievementId,
                "current": value.current,
                "status": value.status,
                "timestamp": value.timestamp
            ]
        }
        let value: [String: Any] = [
            "info": [
                "export_app": "MHGLauncher",
                "uiaf_version": "v1.1",
                "export_timestamp": Int(Date().timeIntervalSince1970)
            ],
            "list": list
        ]
        return try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    }

    func cloudItems(archiveID: String) async throws -> [AchievementItemInput] {
        try await items(archiveID: archiveID).map {
            AchievementItemInput(
                achievementId: $0.achievementId,
                current: $0.current,
                status: $0.status,
                timestamp: $0.timestamp
            )
        }
    }

    func importCloud(
        archiveID: String,
        values: [AchievementItemInput]
    ) async throws -> Int {
        guard values.count <= 200_000 else {
            throw LauncherCoreError(code: "cloud_payload_invalid", message: "云端成就格式无效")
        }
        let selected = try await archive(uid: archiveID)
        _ = try await save(AchievementSaveRequest(
            archiveId: selected.id,
            expectedRevision: selected.revision ?? 0,
            items: values
        ))
        return values.count
    }

    private func requireArchive(_ id: String) async throws -> AchievementArchive {
        try await database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM achievement_archives WHERE id=?",
                arguments: [id]
            ) else {
                throw LauncherCoreError(code: "archive_missing", message: "成就档案不存在")
            }
            return Self.archive(row)
        }
    }

    private func items(archiveID: String) async throws -> [AchievementItem] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM achievements WHERE archive_id=? ORDER BY achievement_id",
                arguments: [archiveID]
            ).map(Self.item)
        }
    }

    private nonisolated static func archive(_ row: Row) -> AchievementArchive {
        AchievementArchive(
            id: row["id"],
            name: row["name"],
            selected: row["selected"],
            createdAt: CoreDate.parse(row["created_at"]),
            updatedAt: CoreDate.parse(row["updated_at"]),
            revision: row["revision"]
        )
    }

    private nonisolated static func item(_ row: Row) -> AchievementItem {
        AchievementItem(
            archiveId: row["archive_id"],
            achievementId: row["achievement_id"],
            current: row["current"],
            status: row["status"],
            timestamp: row["timestamp"],
            updatedAt: CoreDate.parse(row["updated_at"])
        )
    }

    private nonisolated static func int(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
