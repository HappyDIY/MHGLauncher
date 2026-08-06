import Foundation
import GRDB

actor CoreWishService {
    private struct StoredWish: Sendable {
        let record: WishRecord
        let uigfType: String
    }

    private let database: CoreDatabase
    private let provider: any GameProvider
    private let accounts: CoreAccountService
    private let notes: CoreNoteService
    private let resources: CoreResourceService

    init(
        database: CoreDatabase,
        provider: any GameProvider,
        accounts: CoreAccountService,
        notes: CoreNoteService,
        resources: CoreResourceService
    ) {
        self.database = database
        self.provider = provider
        self.accounts = accounts
        self.notes = notes
        self.resources = resources
    }

    func sync(log: (@Sendable (String) async -> Void)? = nil) async throws -> Int {
        guard let role = try await accounts.selectedRole() else {
            throw LauncherCoreError(code: "role_missing", message: "尚未选择游戏角色")
        }
        let credential = try await accounts.credential()
        let newest = try await database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT gacha_type,id FROM (
                    SELECT COALESCE(NULLIF(uigf_gacha_type,''),gacha_type) gacha_type,id,
                    ROW_NUMBER() OVER(PARTITION BY COALESCE(NULLIF(uigf_gacha_type,''),gacha_type)
                    ORDER BY LENGTH(id) DESC,id DESC) row_number FROM wishes WHERE uid=?
                ) WHERE row_number=1
                """, arguments: [role.uid])
            return Dictionary(rows.map { row in
                (row["gacha_type"] as String, row["id"] as String)
            }, uniquingKeysWith: { first, _ in first })
        }
        await log?("已读取 \(newest.count) 个卡池的本地增量检查点")
        var inserted = 0
        var pages = 0
        var processed = 0
        for try await records in provider.wishes(
            credential: credential,
            role: role,
            newest: newest
        ) {
            processed += records.count
            guard processed <= 250_000 else {
                throw LauncherCoreError(code: "wish_payload_too_large", message: "祈愿记录数量超出限制")
            }
            guard records.allSatisfy({ $0.uid == role.uid }) else {
                throw LauncherCoreError(code: "wish_uid_mismatch", message: "祈愿记录与当前 UID 不匹配")
            }
            let values = records.map { StoredWish(record: $0, uigfType: Self.uigfType(for: $0.gachaType)) }
            let added = try await newRecordCount(values)
            try await save(values)
            inserted += added
            pages += 1
            await log?("第 \(pages) 页读取 \(records.count) 条记录，新增 \(added) 条")
        }
        await log?("米游社分页读取完成，共处理 \(pages) 页")
        return inserted
    }

    func importUIGF(_ data: Data) async throws -> (inserted: Int, uids: [String]) {
        guard data.count <= 64 * 1024 * 1024 else {
            throw LauncherCoreError(code: "uigf_too_large", message: "UIGF 文件大小超出限制")
        }
        let records = try Self.parseUIGF(data)
        let inserted = try await newRecordCount(records)
        try await save(records)
        return (inserted, Array(Set(records.map(\.record.uid))).sorted())
    }

    func importGachaURL(_ value: String) async throws -> (inserted: Int, uids: [String]) {
        guard let input = URL(string: value),
              let url = MiHoYoSigning.normalizedGachaURL(input) else {
            throw LauncherCoreError(code: "gacha_url_invalid", message: "抽卡 URL 无效")
        }
        var values: [StoredWish] = []
        for try await page in provider.wishes(gachaURL: url) {
            let pageValues = page.map {
                StoredWish(record: $0, uigfType: Self.uigfType(for: $0.gachaType))
            }
            values += pageValues
            guard Set(values.map(\.record.uid)).count <= 1 else {
                throw LauncherCoreError(code: "gacha_uid_mismatch", message: "抽卡 URL 返回了不一致的 UID")
            }
            guard values.count <= 200_000 else {
                throw LauncherCoreError(code: "uigf_too_large", message: "祈愿记录不能超过 200000 条")
            }
        }
        guard !values.isEmpty else {
            throw LauncherCoreError(code: "gacha_url_unverified", message: "抽卡 URL 可用，但无法确认 UID")
        }
        let inserted = try await newRecordCount(values)
        try await save(values)
        return (inserted, Array(Set(values.map(\.record.uid))).sorted())
    }

    func clear() async throws -> Int {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM wishes")
            return db.changesCount
        }
    }

    func list(uid: String) async throws -> [WishRecord] {
        guard Self.validUID(uid) else {
            throw LauncherCoreError(code: "uid_invalid", message: "角色 UID 无效")
        }
        let records: [WishRecord] = try await database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM wishes WHERE uid=? ORDER BY time_epoch DESC,LENGTH(id) DESC,id DESC",
                arguments: [uid]
            )
            guard rows.count <= 250_000 else {
                throw LauncherCoreError(code: "wish_payload_too_large", message: "祈愿记录数量超出限制")
            }
            return rows.map(Self.wish)
        }
        var enriched: [WishRecord] = []
        enriched.reserveCapacity(records.count)
        for record in records { enriched.append(try await resources.enrich(record)) }
        return enriched
    }

    func importCloud(_ records: [WishRecord]) async throws -> Int {
        guard records.count <= 20_000 else {
            throw LauncherCoreError(code: "cloud_payload_invalid", message: "云端记录格式无效")
        }
        let values = records.map { StoredWish(record: $0, uigfType: Self.uigfType(for: $0.gachaType)) }
        let inserted = try await newRecordCount(values)
        try await save(values)
        return inserted
    }

    func snapshot(uid: String) async throws -> CompanionSnapshot {
        let wishes = try await list(uid: uid)
        let note = try await notes.get(uid: uid)
        let statistics = Self.statistics(wishes)
        let ascending = wishes.reversed()
        let grouped = Dictionary(grouping: ascending, by: \WishRecord.gachaType)
        let banners = grouped.keys.sorted().map { type in
            Self.banner(uid: uid, type: type, records: grouped[type] ?? [])
        }
        return CompanionSnapshot(
            wishes: wishes,
            statistics: statistics,
            bannerStatistics: banners,
            note: note
        )
    }

    func exportUIGF(uid: String) async throws -> Data {
        guard Self.validUID(uid) else {
            throw LauncherCoreError(code: "uid_invalid", message: "角色 UID 无效")
        }
        let wishes = try await list(uid: uid)
        let timezone = uid.hasPrefix("6") ? -5 : uid.hasPrefix("7") ? 1 : 8
        let list: [[String: String]] = wishes.reversed().map { value in
            var item = [
                "uigf_gacha_type": Self.uigfType(for: value.gachaType),
                "gacha_type": value.gachaType,
                "item_id": value.itemId,
                "count": "1",
                "time": Self.localTime(value.time, timezone: timezone),
                "id": value.id
            ]
            if !value.name.isEmpty { item["name"] = value.name }
            if !value.itemType.isEmpty { item["item_type"] = value.itemType }
            if value.rank > 0 { item["rank_type"] = String(value.rank) }
            return item
        }
        let value: [String: Any] = [
            "info": [
                "export_timestamp": Int(Date().timeIntervalSince1970),
                "export_app": "MHGLauncher",
                "export_app_version": "1.0.0",
                "version": "v4.2"
            ],
            "hk4e": [["uid": uid, "timezone": timezone, "lang": "zh-cn", "list": list]]
        ]
        return try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    }

    private func save(_ values: [StoredWish]) async throws {
        guard !values.isEmpty else { return }
        try Self.validate(values)
        try await database.write { db in
            for value in values {
                let record = value.record
                try db.execute(sql: """
                    INSERT INTO wishes(id,uid,gacha_type,uigf_gacha_type,item_id,name,item_type,rank,time,time_epoch)
                    VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(uid,id) DO UPDATE SET
                    uigf_gacha_type=COALESCE(NULLIF(excluded.uigf_gacha_type,''),wishes.uigf_gacha_type),
                    name=COALESCE(NULLIF(excluded.name,''),wishes.name),
                    item_type=COALESCE(NULLIF(excluded.item_type,''),wishes.item_type),
                    rank=CASE WHEN excluded.rank>0 THEN excluded.rank ELSE wishes.rank END
                    """, arguments: [
                        record.id, record.uid, record.gachaType, value.uigfType,
                        record.itemId, record.name, record.itemType, record.rank,
                        CoreDate.string(record.time), Int64(record.time.timeIntervalSince1970)
                    ])
            }
        }
    }

    private func newRecordCount(_ values: [StoredWish]) async throws -> Int {
        try Self.validate(values)
        let grouped = Dictionary(grouping: values, by: { $0.record.uid })
        var existing = 0
        for (uid, records) in grouped {
            let ids = Array(Set(records.map(\.record.id)))
            if ids.isEmpty { continue }
            for start in stride(from: 0, to: ids.count, by: 500) {
                let batch = Array(ids[start..<min(start + 500, ids.count)])
                let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
                existing += try await database.read { db in
                    try Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM wishes WHERE uid=? AND id IN (\(placeholders))",
                        arguments: StatementArguments([uid] + batch)
                    ) ?? 0
                }
            }
        }
        return Set(values.map { "\($0.record.uid):\($0.record.id)" }).count - existing
    }

    private nonisolated static func validate(_ values: [StoredWish]) throws {
        guard values.count <= 200_000 else {
            throw LauncherCoreError(code: "wish_payload_too_large", message: "祈愿记录数量超出限制")
        }
        let gachaTypes: Set<String> = ["100", "200", "301", "302", "400", "500"]
        let uigfTypes: Set<String> = ["100", "200", "301", "302", "500"]
        let latest = Date().addingTimeInterval(86_400).timeIntervalSince1970
        for value in values {
            let record = value.record
            guard validUID(record.uid),
                  record.id.range(of: #"^\d{1,19}$"#, options: .regularExpression) != nil,
                  gachaTypes.contains(record.gachaType),
                  uigfTypes.contains(value.uigfType),
                  value.uigfType == record.gachaType
                    || record.gachaType == "400" && value.uigfType == "301",
                  !record.itemId.isEmpty, record.itemId.utf8.count <= 128,
                  !record.itemId.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  record.name.utf8.count <= 512,
                  !record.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  record.itemType.utf8.count <= 128,
                  !record.itemType.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  (0...5).contains(record.rank),
                  record.time != .distantPast,
                  record.time.timeIntervalSince1970.isFinite,
                  record.time.timeIntervalSince1970 >= 946_684_800,
                  record.time.timeIntervalSince1970 <= latest else {
                throw LauncherCoreError(code: "wish_item_invalid", message: "祈愿记录字段无效")
            }
        }
    }

    private nonisolated static func statistics(_ records: [WishRecord]) -> [WishStatistics] {
        Dictionary(grouping: records, by: \WishRecord.gachaType).keys.sorted().map { type in
            let group = Dictionary(grouping: records, by: \WishRecord.gachaType)[type] ?? []
            let firstFive = group.firstIndex { $0.rank == 5 }
            return WishStatistics(
                uid: group.first?.uid ?? "",
                gachaType: type,
                total: group.count,
                fiveStarCount: group.count { $0.rank == 5 },
                pullsSinceFiveStar: firstFive ?? group.count
            )
        }
    }

    private nonisolated static func banner(
        uid: String,
        type: String,
        records: [WishRecord]
    ) -> WishBannerDetail {
        var orange = 0, purple = 0, three = 0, four = 0, five = 0, maximum = 0, minimum = 0
        var lastUpOrange = 0, smallWin = 0, smallLose = 0
        var previousIsUp = true
        var distances: [Int] = [], upCycles: [Int] = []
        var orangeItems: [WishBannerItem] = [], purpleItems: [WishBannerItem] = []
        let limited = ["301", "302"].contains(type)
        for (index, item) in records.enumerated() {
            orange += 1; purple += 1; lastUpOrange += 1
            if item.rank == 5 {
                five += 1; distances.append(orange); maximum = max(maximum, orange)
                minimum = minimum == 0 ? orange : min(minimum, orange)
                let isUp = limited && !standardFiveStarIDs.contains(item.itemId)
                if limited {
                    if isUp {
                        upCycles.append(lastUpOrange)
                        if previousIsUp { smallWin += 1 }
                    } else if previousIsUp { smallLose += 1 }
                    previousIsUp = isUp
                }
                orangeItems.append(bannerItem(item, pull: index + 1, pity: orange))
                orange = 0; purple = 0; lastUpOrange = 0
            } else if item.rank == 4 {
                four += 1
                purpleItems.append(bannerItem(item, pull: index + 1, pity: purple))
                purple = 0
            } else if item.rank == 3 { three += 1 }
        }
        let total = records.count
        let smallTries = smallWin + smallLose
        return WishBannerDetail(
            uid: uid,
            gachaType: type,
            total: total,
            timeFrom: records.first?.time,
            timeTo: records.last?.time,
            fiveStarCount: five,
            fourStarCount: four,
            threeStarCount: three,
            fiveStarPercent: rounded(Double(five) / Double(max(total, 1)), digits: 4),
            fourStarPercent: rounded(Double(four) / Double(max(total, 1)), digits: 4),
            threeStarPercent: rounded(Double(three) / Double(max(total, 1)), digits: 4),
            maxPity: maximum,
            minPity: minimum,
            averagePity: rounded(Double(distances.reduce(0, +)) / Double(max(distances.count, 1)), digits: 2),
            lastPity: orange,
            lastPurplePity: purple,
            guaranteeThreshold: type == "302" ? 80 : 90,
            fiveStarItems: orangeItems.reversed(),
            fourStarItems: purpleItems.reversed(),
            averageUpPity: rounded(Double(upCycles.reduce(0, +)) / Double(max(upCycles.count, 1)), digits: 2),
            smallGuaranteeWinRate: rounded(smallTries == 0 ? 0 : Double(smallWin) / Double(smallTries), digits: 4)
        )
    }

    private nonisolated static func bannerItem(
        _ item: WishRecord,
        pull: Int,
        pity: Int
    ) -> WishBannerItem {
        WishBannerItem(
            name: item.name,
            itemId: item.itemId,
            itemType: item.itemType,
            rank: item.rank,
            iconUrl: item.iconUrl,
            pullNumber: pull,
            pity: pity,
            time: item.time
        )
    }

    private nonisolated static func wish(_ row: Row) -> WishRecord {
        WishRecord(
            id: row["id"],
            uid: row["uid"],
            gachaType: row["gacha_type"],
            itemId: row["item_id"],
            name: row["name"],
            itemType: row["item_type"],
            rank: row["rank"],
            time: CoreDate.parse(row["time"]),
            iconUrl: nil
        )
    }

    private nonisolated static func parseUIGF(_ data: Data) throws -> [StoredWish] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["info"] as? [String: Any] else { throw uigfError() }
        var groups: [(String, Int, [[String: Any]])] = []
        if info["uigf_version"] != nil {
            guard let uid = string(info["uid"]), validUID(uid),
                  let list = root["list"] as? [[String: Any]] else { throw uigfError() }
            groups = [(uid, 8, list)]
        } else {
            guard let version = info["version"] as? String,
                  ["v4.0", "v4.1", "v4.2"].contains(version),
                  let accounts = root["hk4e"] as? [[String: Any]], accounts.count <= 100 else {
                throw uigfError()
            }
            groups = try accounts.map { account in
                guard let uid = string(account["uid"]), validUID(uid),
                      let list = account["list"] as? [[String: Any]] else { throw uigfError() }
                let timezone = int(account["timezone"]) ?? 8
                guard (-12...14).contains(timezone) else { throw uigfError() }
                return (uid, timezone, list)
            }
        }
        guard groups.reduce(0, { $0 + $1.2.count }) <= 200_000 else {
            throw LauncherCoreError(code: "uigf_too_large", message: "UIGF 记录不能超过 200000 条")
        }
        let gachaTypes: Set<String> = ["100", "200", "301", "302", "400", "500"]
        let uigfTypes: Set<String> = ["100", "200", "301", "302", "500"]
        let records = try groups.flatMap { uid, timezone, list in
            try list.map { item -> StoredWish in
                guard let id = string(item["id"]), id.range(of: #"^\d{1,19}$"#, options: .regularExpression) != nil,
                      let gacha = string(item["gacha_type"]), gachaTypes.contains(gacha),
                      let uigf = string(item["uigf_gacha_type"]), uigfTypes.contains(uigf),
                      let itemID = string(item["item_id"]),
                      let time = date(string(item["time"]) ?? "", timezone: timezone) else {
                    throw LauncherCoreError(code: "uigf_item_invalid", message: "UIGF 记录字段无效")
                }
                return StoredWish(
                    record: WishRecord(
                        id: id, uid: uid, gachaType: gacha, itemId: itemID,
                        name: string(item["name"]) ?? "", itemType: string(item["item_type"]) ?? "",
                        rank: int(item["rank_type"]) ?? 0, time: time, iconUrl: nil
                    ),
                    uigfType: uigf
                )
            }
        }
        guard !records.isEmpty else {
            throw LauncherCoreError(code: "uigf_empty", message: "UIGF 文件不包含原神祈愿记录")
        }
        return records
    }

    private nonisolated static func date(_ value: String, timezone: Int) -> Date? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "T")
        let hasOffset = candidate.range(of: #"(?:Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression) != nil
        let sign = timezone >= 0 ? "+" : "-"
        let offset = String(format: "%@%02d:00", sign, abs(timezone))
        return ISO8601DateFormatter().date(from: hasOffset ? candidate : candidate + offset)
    }

    private nonisolated static func localTime(_ date: Date, timezone: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: timezone * 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private nonisolated static func uigfType(for gachaType: String) -> String {
        gachaType == "400" ? "301" : gachaType
    }

    private nonisolated static func rounded(_ value: Double, digits: Int) -> Double {
        let scale = pow(10, Double(digits))
        return (value * scale).rounded() / scale
    }

    private nonisolated static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private nonisolated static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private nonisolated static func validUID(_ value: String) -> Bool {
        value.range(of: #"^\d{9,10}$"#, options: .regularExpression) != nil
    }

    private nonisolated static func uigfError() -> LauncherCoreError {
        LauncherCoreError(code: "uigf_invalid", message: "UIGF 文件不符合受支持的规范")
    }

    private nonisolated static let standardFiveStarIDs: Set<String> = [
        "10000003", "10000016", "10000035", "10000041", "10000042", "10000069",
        "10000079", "10000109", "11501", "11502", "12501", "12502", "13502",
        "13505", "14501", "14502", "15501", "15502"
    ]
}
