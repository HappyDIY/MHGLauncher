import Foundation

actor LiveNoteClient {
    private let transport: any HTTPTransport
    private let device: MiHoYoDevice
    private let notePath = "/game_record/app/genshin/api/dailyNote"
    private let indexPath = "/game_record/app/genshin/api/index"

    init(transport: any HTTPTransport, device: MiHoYoDevice) {
        self.transport = transport
        self.device = device
    }

    func note(
        credential: String,
        role: GameRole,
        challenge: String,
        challengePath: String
    ) async throws -> DailyNote {
        let snapshot = try await device.fingerprint()
        let cookie = try await gameRecordCredential(credential, deviceID: snapshot.deviceID)
        let query = "role_id=\(role.uid)&server=\(role.region)"
        try await requestIndex(
            cookie: cookie, query: query, challenge: challengePath == indexPath ? challenge : "",
            snapshot: snapshot
        )
        let payload = try await raw(
            path: "\(notePath)?\(query)",
            headers: headers(
                cookie: cookie, query: query, snapshot: snapshot,
                challenge: challengePath == notePath ? challenge : "", path: "", body: "", tool: true
            )
        )
        try await checkNote(payload, credential: credential, challenge: challenge, path: challengePath)
        let data = payload.data.objectValue ?? [:]
        let expeditions = data["expeditions"]?.arrayValue.compactMap(\.objectValue) ?? []
        let recovery = data["transformer"]?.objectValue?["recovery_time"]?.objectValue
        return DailyNote(
            uid: role.uid, currentResin: data["current_resin"]?.int ?? 0,
            maxResin: data["max_resin"]?.int ?? 200,
            finishedTasks: data["finished_task_num"]?.int ?? 0,
            totalTasks: data["total_task_num"]?.int ?? 4,
            extraTaskRewardReceived: data["is_extra_task_reward_received"]?.boolValue ?? false,
            expeditionsFinished: expeditions.filter { $0["status"]?.text == "Finished" }.count,
            expeditionsTotal: data["max_expedition_num"]?.int ?? expeditions.count,
            currentHomeCoin: data["current_home_coin"]?.int ?? 0,
            maxHomeCoin: data["max_home_coin"]?.int ?? 0,
            weeklyBossRemaining: data["remain_resin_discount_num"]?.int ?? 0,
            transformerReady: recovery?["reached"]?.boolValue ?? false,
            refreshedAt: Date()
        )
    }

    func verify(
        credential: String,
        challenge: String,
        validate: String,
        challengePath: String
    ) async throws -> String {
        let path = challengePath.nonempty ?? notePath
        let snapshot = try await device.fingerprint()
        let cookie = try await gameRecordCredential(credential, deviceID: snapshot.deviceID)
        let body = String(decoding: try JSONEncoder.api.encode([
            "geetest_challenge": challenge, "geetest_validate": validate,
            "geetest_seccode": "\(validate)|jordan"
        ]), as: UTF8.self)
        let payload = try await raw(
            path: "/game_record/app/card/wapi/verifyVerification",
            headers: headers(cookie: cookie, query: "", snapshot: snapshot, path: path, body: body),
            method: "POST", body: Data(body.utf8)
        )
        if [10306, 1034, 5003].contains(payload.retcode) {
            throw try await verificationError(credential: credential, path: path)
        }
        guard payload.retcode == 0 else { throw mihoyo(payload) }
        return payload.data.objectValue?["challenge"]?.text ?? ""
    }

    private func requestIndex(
        cookie: String,
        query: String,
        challenge: String,
        snapshot: MiHoYoDevice.Snapshot
    ) async throws {
        let payload = try await raw(
            path: "\(indexPath)?\(query)",
            headers: headers(cookie: cookie, query: query, snapshot: snapshot, challenge: challenge)
        )
        if [1034, 5003].contains(payload.retcode), !challenge.isEmpty {
            throw LauncherCoreError(code: "note_verification_failed", message: "战绩首页验证未通过或已失效，请重新刷新后再验证")
        }
        if [1034, 5003, 10306].contains(payload.retcode) {
            throw try await verificationError(credential: cookie, path: indexPath, complete: false)
        }
        guard payload.retcode == 0 else { throw mihoyo(payload) }
    }

    private func checkNote(
        _ payload: MiHoYoEnvelope,
        credential: String,
        challenge: String,
        path: String
    ) async throws {
        if [1034, 5003].contains(payload.retcode), path == notePath, !challenge.isEmpty {
            throw LauncherCoreError(code: "note_verification_failed", message: "实时便笺验证未通过或已失效，请重新刷新后再验证")
        }
        if [1034, 5003, 10306].contains(payload.retcode) {
            throw try await verificationError(credential: credential, path: notePath)
        }
        if [10102, 10103, 10104].contains(payload.retcode) {
            throw LauncherCoreError(code: "note_unavailable", message: payload.message.nonempty ?? "实时便笺当前不可用，请检查米游社数据公开或账号状态")
        }
        if payload.message.lowercased().contains("visit too frequently") {
            throw LauncherCoreError(code: "note_sync_limited", message: "访问过于频繁，请稍后再刷新实时便笺")
        }
        guard payload.retcode == 0 else { throw mihoyo(payload) }
    }

    private func verificationError(
        credential: String,
        path: String,
        complete: Bool = true
    ) async throws -> LauncherCoreError {
        let snapshot = try await device.fingerprint()
        let cookie = complete ? try await gameRecordCredential(credential, deviceID: snapshot.deviceID) : credential
        let query = "is_high=true"
        let payload = try await raw(
            path: "/game_record/app/card/wapi/createVerification?\(query)",
            headers: headers(cookie: cookie, query: query, snapshot: snapshot, path: path)
        )
        guard payload.retcode == 0,
              let data = payload.data.objectValue,
              let gt = data["gt"]?.text.nonempty,
              let challenge = data["challenge"]?.text.nonempty else { return mihoyo(payload) }
        return LauncherCoreError(
            code: "verification_required", message: "请完成人机验证后重试",
            details: [
                "gt": .string(gt), "challenge": .string(challenge),
                "xrpc_challenge_path": .string(path)
            ]
        )
    }

    private func gameRecordCredential(_ raw: String, deviceID: String) async throws -> String {
        var values = MiHoYoSigning.cookies(raw)
        if values["cookie_token"]?.nonempty == nil || values["account_id"]?.nonempty == nil {
            let data = try await passport(
                "https://passport-api.mihoyo.com/account/auth/api/getCookieAccountInfoBySToken",
                values: values, deviceID: deviceID
            )
            values["cookie_token"] = data["cookie_token"]?.text
            values["account_id"] = data["uid"]?.text
        }
        if values["ltoken"]?.nonempty == nil || values["ltuid"]?.nonempty == nil {
            let data = try await passport(
                "https://passport-api.mihoyo.com/account/auth/api/getLTokenBySToken",
                values: values, deviceID: deviceID
            )
            values["ltoken"] = data["ltoken"]?.text
            values["ltuid"] = values["stuid"] ?? values["account_id"]
        }
        return MiHoYoSigning.serialize(values.filter { ["account_id", "cookie_token", "ltoken", "ltuid"].contains($0.key) })
    }

    private func passport(_ url: String, values: [String: String], deviceID: String) async throws -> [String: JSONValue] {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 30)
        request.allHTTPHeaderFields = [
            "Cookie": MiHoYoSigning.serialize(values), "DS": MiHoYoSigning.sign(.prod),
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1",
            "x-rpc-app_version": "2.95.1", "x-rpc-client_type": "2",
            "x-rpc-device_id": deviceID, "Content-Type": "application/json"
        ]
        let payload = try await transport.send(request, policy: .mihoyo, maximumBytes: 1024 * 1024)
        return try MiHoYoEnvelope.decode(payload).data.objectValue ?? [:]
    }

    private func raw(
        path: String,
        headers: [String: String],
        method: String = "GET",
        body: Data? = nil
    ) async throws -> MiHoYoEnvelope {
        var request = URLRequest(
            url: URL(string: "https://api-takumi-record.mihoyo.com\(path)")!,
            timeoutInterval: 30
        )
        request.httpMethod = method
        request.allHTTPHeaderFields = headers
        request.httpBody = body
        let payload = try await transport.send(request, policy: .mihoyo, maximumBytes: 8 * 1024 * 1024)
        guard (200..<300).contains(payload.statusCode),
              let root = try? JSONDecoder.api.decode([String: JSONValue].self, from: payload.data) else {
            throw LauncherCoreError(code: "mihoyo_error", message: "米游社请求失败")
        }
        return MiHoYoEnvelope(
            retcode: root["retcode"]?.int ?? 0,
            message: root["message"]?.text ?? "",
            data: root["data"] ?? .object([:])
        )
    }

    private func headers(
        cookie: String,
        query: String,
        snapshot: MiHoYoDevice.Snapshot,
        challenge: String = "",
        path: String = "",
        body: String = "",
        tool: Bool = false
    ) -> [String: String] {
        var result = [
            "Cookie": cookie, "DS": MiHoYoSigning.sign(.x4, body: body, query: query),
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1",
            "Accept": "application/json", "x-rpc-app_version": "2.95.1",
            "x-rpc-client_type": "5", "x-rpc-device_id": snapshot.deviceID,
            "x-rpc-device_fp": snapshot.deviceFP, "Referer": "https://webstatic.mihoyo.com"
        ]
        if !path.isEmpty {
            result["x-rpc-challenge_game"] = "2"
            result["x-rpc-challenge_path"] = path
        }
        if !body.isEmpty { result["Content-Type"] = "application/json" }
        if tool { result["x-rpc-tool_verison"] = "v5.0.1-ys" }
        if !challenge.isEmpty { result["x-rpc-challenge"] = challenge }
        return result
    }

    private func mihoyo(_ payload: MiHoYoEnvelope) -> LauncherCoreError {
        LauncherCoreError(
            code: "mihoyo_error",
            message: payload.message.nonempty ?? "米游社请求失败（错误码 \(payload.retcode)）",
            details: ["retcode": .string(String(payload.retcode))]
        )
    }
}
