import Foundation
import GRDB

actor CoreNotificationService {
    private let database: CoreDatabase
    private let resources: CoreResourceService
    private let now: @Sendable () -> Date

    init(
        database: CoreDatabase,
        resources: CoreResourceService,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.database = database
        self.resources = resources
        self.now = now
    }

    func settings() async throws -> NotificationSettings {
        try await database.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM notification_settings WHERE id=1"
            )
            return NotificationSettings(
                dailyCommissionEnabled: row?["daily_commission_enabled"] ?? false,
                dailyCommissionTime: row?["daily_commission_time"] ?? "20:00",
                resinFullEnabled: row?["resin_full_enabled"] ?? false,
                gachaRefreshEnabled: row?["gacha_refresh_enabled"] ?? true,
                versionUpdateEnabled: row?["version_update_enabled"] ?? true
            )
        }
    }

    func update(_ value: NotificationSettings) async throws -> NotificationSettings {
        guard value.dailyCommissionTime.range(
            of: #"^(?:[01]\d|2[0-3]):[0-5]\d$"#,
            options: .regularExpression
        ) != nil else {
            throw LauncherCoreError(code: "notification_time_invalid", message: "提醒时间格式无效")
        }
        try await database.write { db in
            try db.execute(sql: """
                UPDATE notification_settings SET daily_commission_enabled=?,daily_commission_time=?,
                resin_full_enabled=?,gacha_refresh_enabled=?,version_update_enabled=? WHERE id=1
                """, arguments: [
                    value.dailyCommissionEnabled, value.dailyCommissionTime,
                    value.resinFullEnabled, value.gachaRefreshEnabled, value.versionUpdateEnabled
                ])
        }
        return value
    }

    func evaluate(uid: String?) async throws -> [NotificationEvent] {
        let config = try await settings()
        let currentNote: DailyNote?
        if let uid { currentNote = try await note(uid: uid) }
        else { currentNote = nil }
        let game = try await gameState()
        let current = now()
        var events: [NotificationEvent] = []
        try await evaluateDaily(&events, note: currentNote, config: config, current: current)
        try await evaluateResin(&events, note: currentNote, config: config, current: current)
        try await evaluateGacha(&events, config: config, current: current)
        if config.versionUpdateEnabled, game?.status == .updateAvailable {
            try await add(
                &events,
                key: "version:\(game?.availableVersion ?? "")",
                title: "游戏版本更新可用",
                body: "可更新到 \(game?.availableVersion ?? "")",
                destination: "game",
                current: current
            )
        }
        return events
    }

    func acknowledge(_ keys: [String]) async throws -> [String] {
        guard keys.count <= 256,
              keys.allSatisfy({
                  !$0.isEmpty && $0.utf8.count <= 512
                      && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
              }) else {
            throw LauncherCoreError(code: "notification_key_invalid", message: "提醒标识无效")
        }
        let unique = Array(Set(keys))
        let createdAt = CoreDate.string(now())
        try await database.write { db in
            for key in unique {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO notification_state(key,last_triggered_at,state) VALUES(?,?,?)
                    """, arguments: [key, createdAt, "{}"])
            }
        }
        return unique
    }

    private func evaluateDaily(
        _ events: inout [NotificationEvent],
        note: DailyNote?,
        config: NotificationSettings,
        current: Date
    ) async throws {
        guard let note else { return }
        let key = "daily:\(note.uid):\(chinaDay(current))"
        try await removeOther(prefix: "daily:\(note.uid):", current: key)
        guard config.dailyCommissionEnabled,
              !note.extraTaskRewardReceived,
              isAfter(config.dailyCommissionTime, date: current) else { return }
        try await add(
            &events,
            key: key,
            title: "每日委托奖励尚未领取",
            body: "UID \(note.uid) 还有每日委托奖励未领取",
            destination: "notes",
            current: current
        )
    }

    private func evaluateResin(
        _ events: inout [NotificationEvent],
        note: DailyNote?,
        config: NotificationSettings,
        current: Date
    ) async throws {
        guard let note else { return }
        let key = "resin:\(note.uid):\(note.maxResin)"
        guard config.resinFullEnabled, note.currentResin >= note.maxResin else {
            try await database.write { db in
                try db.execute(sql: "DELETE FROM notification_state WHERE key=?", arguments: [key])
            }
            return
        }
        try await add(
            &events,
            key: key,
            title: "体力已回满",
            body: "UID \(note.uid) 当前体力 \(note.currentResin)/\(note.maxResin)",
            destination: "notes",
            current: current
        )
    }

    private func evaluateGacha(
        _ events: inout [NotificationEvent],
        config: NotificationSettings,
        current: Date
    ) async throws {
        guard config.gachaRefreshEnabled else { return }
        let start = try await resources.gachaEvents()
            .filter { event in
                guard let started = event.startedAt, started <= current else { return false }
                return event.endedAt == nil || event.endedAt! >= current
            }
            .compactMap(\.startedAt)
            .max()
        guard let start else { return }
        let key = "gacha:\(Int(start.timeIntervalSince1970 * 1000))"
        try await removeOther(prefix: "gacha:", current: key)
        try await add(
            &events,
            key: key,
            title: "卡池已刷新",
            body: "新的活动祈愿已经开放",
            destination: "gachaHistory",
            current: current
        )
    }

    private func add(
        _ events: inout [NotificationEvent],
        key: String,
        title: String,
        body: String,
        destination: String,
        current: Date
    ) async throws {
        let exists = try await database.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM notification_state WHERE key=?)",
                arguments: [key]
            ) ?? false
        }
        guard !exists else { return }
        events.append(NotificationEvent(
            key: key,
            title: title,
            body: body,
            destination: destination,
            createdAt: current
        ))
    }

    private func removeOther(prefix: String, current: String) async throws {
        try await database.write { db in
            try db.execute(
                sql: "DELETE FROM notification_state WHERE key LIKE ? AND key<>?",
                arguments: [prefix + "%", current]
            )
        }
    }

    private func note(uid: String) async throws -> DailyNote? {
        guard uid.range(of: #"^\d{9,10}$"#, options: .regularExpression) != nil else {
            throw LauncherCoreError(code: "uid_invalid", message: "角色 UID 无效")
        }
        try await database.read { db in
            guard let payload = try String.fetchOne(
                db, sql: "SELECT payload FROM notes WHERE uid=?", arguments: [uid]
            ) else { return nil }
            guard payload.utf8.count <= 1024 * 1024 else {
                throw LauncherCoreError(code: "note_payload_too_large", message: "实时便笺数据超出限制")
            }
            let value = try JSONDecoder.api.decode(DailyNote.self, from: Data(payload.utf8))
            guard value.uid == uid else {
                throw LauncherCoreError(code: "note_uid_mismatch", message: "实时便笺与当前 UID 不匹配")
            }
            return value
        }
    }

    private func gameState() async throws -> GameState? {
        try await database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM game_state WHERE id=1") else {
                return nil
            }
            let status = GameStatus(rawValue: row["status"] as String) ?? .notInstalled
            return GameState(
                installPath: row["install_path"],
                installedVersion: row["version"],
                availableVersion: row["version"],
                status: status,
                updateKind: nil,
                downloadBytes: nil,
                predownloadVersion: nil,
                predownloadFinished: nil
            )
        }
    }

    private func isAfter(_ value: String, date: Date) -> Bool {
        let values = value.split(separator: ":").compactMap { Int($0) }
        guard values.count == 2 else { return false }
        let components = chinaCalendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0, components.minute ?? 0) >= (values[0], values[1])
    }

    private func chinaDay(_ date: Date) -> String {
        let components = chinaCalendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private var chinaCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        return calendar
    }
}
