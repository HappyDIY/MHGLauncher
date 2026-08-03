import Foundation

actor LiveGameRecordProvider: GameRecordProvider {
    private let transport: any HTTPTransport
    private let device: MiHoYoDevice
    private let root = "https://api-takumi-record.mihoyo.com/game_record/app/genshin/api"

    init(dataDirectory: URL, transport: any HTTPTransport) throws {
        self.transport = transport
        device = try MiHoYoDevice(dataDirectory: dataDirectory, transport: transport)
    }

    func characters(credential: String, role: GameRole) async throws -> [GameCharacter] {
        let body = try JSONEncoder.api.encode([
            "role_id": JSONValue.string(role.uid), "server": .string(role.region),
            "sort_type": .number(1)
        ])
        let data = try await api(path: "/character/list", credential: credential, body: body)
        return data["list"]?.arrayValue.compactMap { item in
            item.objectValue.flatMap { character(uid: role.uid, summary: $0, payload: $0) }
        } ?? []
    }

    func characterDetail(
        credential: String,
        role: GameRole,
        avatarID: String
    ) async throws -> GameCharacter {
        guard let id = Int(avatarID) else {
            throw LauncherCoreError(code: "character_id_invalid", message: "角色标识无效")
        }
        let body = try JSONEncoder.api.encode([
            "role_id": JSONValue.string(role.uid), "server": .string(role.region),
            "sort_type": .number(1), "character_ids": .array([.number(Double(id))])
        ])
        let data = try await api(path: "/character/detail", credential: credential, body: body)
        let item = data["list"]?.arrayValue.first?.objectValue
            ?? data["avatars"]?.arrayValue.first?.objectValue
        guard let item,
              let result = character(
                uid: role.uid,
                summary: item["base"]?.objectValue ?? item,
                payload: item
              ) else {
            throw LauncherCoreError(code: "character_missing", message: "角色详情不存在")
        }
        return result
    }

    private func api(path: String, credential: String, body: Data) async throws -> [String: JSONValue] {
        let snapshot = try await device.fingerprint()
        let bodyText = String(decoding: body, as: UTF8.self)
        var request = URLRequest(url: URL(string: root + path)!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = body
        request.allHTTPHeaderFields = [
            "Cookie": credential, "DS": MiHoYoSigning.sign(.x4, body: bodyText),
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1",
            "x-rpc-app_version": "2.95.1", "x-rpc-client_type": "5",
            "x-rpc-device_id": snapshot.deviceID, "x-rpc-device_fp": snapshot.deviceFP,
            "Content-Type": "application/json", "Referer": "https://app.mihoyo.com"
        ]
        let payload = try await transport.send(request, policy: .mihoyo, maximumBytes: 32 * 1024 * 1024)
        return try MiHoYoEnvelope.decode(payload).data.objectValue ?? [:]
    }

    private nonisolated func character(
        uid: String,
        summary: [String: JSONValue],
        payload: [String: JSONValue]
    ) -> GameCharacter? {
        guard let id = summary["id"]?.text.nonempty else { return nil }
        let weapon = summary["weapon"]?.objectValue
        let encoded = try? JSONEncoder.api.encode(payload)
        let detail = encoded.flatMap { try? JSONDecoder.api.decode(CharacterPayload.self, from: $0) }
        let icon = summary["icon"]?.text.nonempty.flatMap(URL.init(string:))
        return GameCharacter(
            uid: uid, avatarId: id, name: summary["name"]?.text ?? "",
            element: summary["element"]?.text ?? "", level: summary["level"]?.int ?? 0,
            rarity: summary["rarity"]?.int ?? 0,
            constellation: summary["actived_constellation_num"]?.int ?? 0,
            fetter: summary["fetter"]?.int ?? 0,
            weaponName: weapon?["name"]?.text ?? "", weaponLevel: weapon?["level"]?.int ?? 0,
            iconUrl: icon, payload: detail, updatedAt: Date()
        )
    }
}
