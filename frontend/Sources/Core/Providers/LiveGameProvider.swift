import Foundation

actor LiveGameProvider: GameProvider {
    private struct AigisSession: Sendable {
        let id: String
        let mobile: String
        let gt: String
        let challenge: String
        let expiresAt: Date
    }

    private let transport: any HTTPTransport
    private let device: MiHoYoDevice
    private let sophon: SophonProvider
    private let noteClient: LiveNoteClient
    private var qrSessions: [String: QRSession] = [:]
    private var aigisSessions: [String: AigisSession] = [:]
    private static let agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1"
    private static let maximumSessionCount = 64
    private static let maximumWishPages = 2_500
    private static let maximumImportedGachaRecords = 50_000

    init(dataDirectory: URL, transport: any HTTPTransport) throws {
        self.transport = transport
        device = try MiHoYoDevice(dataDirectory: dataDirectory, transport: transport)
        sophon = SophonProvider(transport: transport)
        noteClient = LiveNoteClient(transport: transport, device: device)
    }

    func createQRSession() async throws -> QRSession {
        pruneSessions()
        var request = request(
            "https://passport-api.mihoyo.com/account/ma-cn-passport/app/createQRLogin",
            method: "POST", headers: try await qrHeaders(), body: Data("{}".utf8)
        )
        request.timeoutInterval = 30
        let data = try await api(request)
        guard let id = data["ticket"]?.text.nonempty,
              Self.validText(id, maximum: 512),
              let url = data["url"]?.text.nonempty,
              Self.validText(url, maximum: 4_096),
              let qrURL = URL(string: url), qrURL.scheme?.lowercased() == "https",
              qrURL.user == nil, qrURL.password == nil,
              qrURL.port == nil, qrURL.fragment == nil, qrURL.host?.isEmpty == false else {
            throw LauncherCoreError(code: "qr_payload_invalid", message: "二维码登录结果无效")
        }
        let session = QRSession(
            id: id, url: url, status: "created", expiresAt: Date().addingTimeInterval(300)
        )
        qrSessions[id] = session
        return session
    }

    func queryQRSession(_ id: String) async throws -> (QRSession, ProviderIdentity?) {
        guard Self.validText(id, maximum: 512, allowEmpty: false) else {
            throw LauncherCoreError(code: "qr_session_invalid", message: "二维码会话标识无效")
        }
        guard let prior = qrSessions[id] else {
            throw LauncherCoreError(code: "qr_session_missing", message: "二维码会话不存在")
        }
        guard prior.expiresAt > Date() else {
            let expired = session(prior, status: "expired")
            qrSessions[id] = expired
            return (expired, nil)
        }
        let body = try JSONEncoder.api.encode(["ticket": id])
        let payload = try await transport.send(
            request(
                "https://passport-api.mihoyo.com/account/ma-cn-passport/app/queryQRLoginStatus",
                method: "POST", headers: try await qrHeaders(), body: body
            ),
            policy: .mihoyo,
            maximumBytes: 1024 * 1024
        )
        let envelope = try MiHoYoEnvelope.decode(payload, allowRetcode: [-3501])
        if envelope.retcode == -3501 {
            let expired = session(prior, status: "expired")
            qrSessions[id] = expired
            return (expired, nil)
        }
        let data = envelope.data.objectValue ?? [:]
        let raw = (data["status"] ?? data["stat"] ?? data["qr_status"])?.text.lowercased() ?? ""
        let status = ["confirmed", "confirm", "3"].contains(raw) ? "confirmed"
            : ["scanned", "scan", "2"].contains(raw) ? "scanned"
            : ["expired", "expire", "4"].contains(raw) ? "expired" : "created"
        let updated = prior.status == "confirmed" ? prior : session(prior, status: status)
        qrSessions[id] = updated
        guard status == "confirmed" else { return (updated, nil) }
        qrSessions.removeValue(forKey: id)
        let confirmed = data["payload"]?.objectValue ?? data
        let tokens = confirmed["tokens"]?.arrayValue.compactMap(\.objectValue) ?? []
        guard tokens.count <= 64 else {
            throw LauncherCoreError(code: "qr_payload_invalid", message: "二维码登录结果无效")
        }
        guard let token = tokens.first(where: { $0["token_type"]?.int == 1 })?["token"]?.text.nonempty,
              let user = (confirmed["user_info"] ?? confirmed["user"])?.objectValue else {
            throw LauncherCoreError(code: "qr_payload_invalid", message: "二维码登录结果缺少凭据")
        }
        return (updated, try await identity(user: user, token: token))
    }

    func identifyCredential(_ credential: String) async throws -> ProviderIdentity {
        let normalized = try await normalizeCredential(credential)
        let completed: String
        do { completed = try await completeCredential(normalized) }
        catch let error as LauncherCoreError where error.code == "mihoyo_error" {
            throw LauncherCoreError(code: "credential_expired", message: "米游社返回登录状态失效，请重新获取 Cookie 后重试")
        }
        let values = MiHoYoSigning.cookies(completed)
        guard let aid = (values["stuid"] ?? values["account_id"])?.nonempty,
              let stoken = values["stoken"]?.nonempty else {
            throw LauncherCoreError(code: "credential_invalid", message: "Cookie 缺少 stuid/stoken，或 login_ticket/login_uid")
        }
        _ = stoken
        return ProviderIdentity(
            aid: aid, mid: values["mid"] ?? "", nickname: "米游社用户", credential: completed
        )
    }

    func createMobileCaptcha(_ mobile: String) async throws -> MobileCaptchaSession {
        try await createMobileCaptcha(mobile, aigis: "")
    }

    func verifyMobileCaptcha(_ value: MobileCaptchaVerificationRequest) async throws -> MobileCaptchaSession {
        guard value.sessionId.utf8.count <= 512,
              value.challenge.utf8.count <= 4_096,
              value.validate.utf8.count <= 4_096,
              Self.validText(value.sessionId),
              Self.validText(value.challenge),
              Self.validText(value.validate) else {
            throw LauncherCoreError(code: "aigis_payload_invalid", message: "验证码验证信息无效")
        }
        guard let pending = aigisSessions.removeValue(forKey: value.sessionId),
              pending.mobile == value.mobile,
              pending.challenge == value.challenge,
              pending.expiresAt > Date() else {
            throw LauncherCoreError(code: "aigis_session_missing", message: "验证码验证会话不存在或已过期")
        }
        let object = [
            "geetest_challenge": value.challenge,
            "geetest_validate": value.validate,
            "geetest_seccode": "\(value.validate)|jordan"
        ]
        let encoded = try JSONEncoder.api.encode(object).base64EncodedString()
        return try await createMobileCaptcha(value.mobile, aigis: "\(value.sessionId);\(encoded)")
    }

    func loginByMobileCaptcha(_ value: MobileLoginRequest) async throws -> ProviderIdentity {
        guard value.aigis.map({ Self.validText($0) }) ?? true else {
            throw LauncherCoreError(code: "aigis_payload_invalid", message: "验证码验证信息无效")
        }
        let object: [String: String] = [
            "area_code": try MiHoYoSigning.encryptPassport("+86"),
            "action_type": value.actionType,
            "captcha": value.captcha,
            "mobile": try MiHoYoSigning.encryptPassport(value.mobile)
        ]
        let body = try JSONEncoder.api.encode(object)
        let text = String(decoding: body, as: UTF8.self)
        var headers = try await passportHeaders(ds: MiHoYoSigning.sign(.prod, body: text))
        if let aigis = value.aigis?.nonempty { headers["x-rpc-aigis"] = aigis }
        let data = try await api(request(
            "https://passport-api.mihoyo.com/account/ma-cn-passport/app/loginByMobileCaptcha",
            method: "POST", headers: headers, body: body
        ))
        guard let token = data["token"]?.objectValue?["token"]?.text.nonempty,
              let user = data["user_info"]?.objectValue else {
            throw LauncherCoreError(code: "login_payload_invalid", message: "短信登录结果缺少凭据")
        }
        return try await identity(user: user, token: token)
    }

    func roles(credential: String) async throws -> [GameRole] {
        var request = URLRequest(url: URL(string: "https://api-takumi.mihoyo.com/binding/api/getUserGameRolesByStoken")!)
        request.allHTTPHeaderFields = try await headers(
            cookie: credential,
            ds: MiHoYoSigning.sign(.lk2, generation: 1)
        ).merging(["Referer": "https://app.mihoyo.com"]) { _, new in new }
        let data = try await api(request)
        guard let list = data["list"]?.arrayValue, list.count <= 256 else {
            throw LauncherCoreError(code: "role_payload_too_large", message: "游戏角色数量超出限制")
        }
        return list.compactMap { item in
            guard let value = item.objectValue, value["game_biz"]?.text == "hk4e_cn" else { return nil }
            return GameRole(
                uid: value["game_uid"]?.text ?? "",
                nickname: value["nickname"]?.text ?? "",
                region: value["region"]?.text ?? "",
                level: value["level"]?.int ?? 0,
                selected: value["is_chosen"]?.boolValue ?? false
            )
        } ?? []
    }

    func build(installedVersion: String, audioLanguages: [String]) async throws -> GameBuild {
        try await sophon.build(installedVersion: installedVersion, audioLanguages: audioLanguages)
    }

    func installedBuild(version: String, audioLanguages: [String]) async throws -> GameBuild {
        try await sophon.installedBuild(version: version, audioLanguages: audioLanguages)
    }

    func predownloadBuild(installedVersion: String, audioLanguages: [String]) async throws -> GameBuild? {
        try await sophon.predownloadBuild(installedVersion: installedVersion, audioLanguages: audioLanguages)
    }

    func gachaURL(credential: String, role: GameRole) async throws -> URL {
        let key = try await authKey(credential: credential, role: role)
        var components = URLComponents(string: "https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog")!
        components.queryItems = [
            .init(name: "lang", value: "zh-cn"), .init(name: "auth_appid", value: "webview_gacha"),
            .init(name: "authkey", value: key), .init(name: "authkey_ver", value: "1"),
            .init(name: "sign_type", value: "2")
        ]
        return components.url!
    }

    nonisolated func wishes(
        credential: String,
        role: GameRole,
        newest: [String: String]
    ) -> AsyncThrowingStream<[WishRecord], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let key = try await self.authKey(credential: credential, role: role)
                    for type in ["100", "200", "301", "302", "500"] {
                        var collected: [WishRecord] = []
                        var end = "0"
                        var page = 0
                        while true {
                            page += 1
                            guard page <= Self.maximumWishPages else {
                                throw LauncherCoreError(code: "wish_sync_limit", message: "祈愿记录分页过多，已停止读取")
                            }
                            var components = URLComponents(string: "https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog")!
                            components.queryItems = [
                                .init(name: "auth_appid", value: "webview_gacha"), .init(name: "authkey_ver", value: "1"),
                                .init(name: "sign_type", value: "2"), .init(name: "authkey", value: key),
                                .init(name: "lang", value: "zh-cn"), .init(name: "gacha_type", value: type),
                                .init(name: "size", value: "20"), .init(name: "end_id", value: end)
                            ]
                            let data = try await self.api(URLRequest(url: components.url!))
                            let values = data["list"]?.arrayValue.compactMap(\.objectValue) ?? []
                            guard values.count <= 100 else {
                                throw LauncherCoreError(code: "wish_payload_invalid", message: "祈愿分页数据无效")
                            }
                            let records = values.compactMap { Self.wish(uid: role.uid, value: $0) }
                            let index = newest[type].flatMap { id in records.firstIndex { $0.id == id } }
                            let fresh = index.map { Array(records[..<$0]) } ?? records
                            collected += fresh
                            guard collected.count <= Self.maximumImportedGachaRecords else {
                                throw LauncherCoreError(code: "gacha_record_limit", message: "祈愿记录过多，已停止读取")
                            }
                            try await Task.sleep(for: .milliseconds(Int.random(in: 1_000...1_999)))
                            if fresh.count < records.count || records.count < 20 { break }
                            guard let next = records.last?.id, next != end else {
                                throw LauncherCoreError(code: "wish_pagination_invalid", message: "祈愿记录分页游标未推进")
                            }
                            end = next
                        }
                        if !collected.isEmpty { continuation.yield(collected) }
                        try await Task.sleep(for: .milliseconds(Int.random(in: 1_000...1_999)))
                    }
                    continuation.finish()
                } catch let error as LauncherCoreError where error.message.lowercased().contains("visit too frequently") {
                    continuation.finish(throwing: LauncherCoreError(code: "wish_sync_limited", message: "访问过于频繁，请稍后再同步祈愿记录"))
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated func wishes(gachaURL: URL) -> AsyncThrowingStream<[WishRecord], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let base = MiHoYoSigning.normalizedGachaURL(gachaURL) else {
                        throw LauncherCoreError(code: "gacha_url_invalid", message: "抽卡 URL 无效")
                    }
                    let hintedUID = Self.queryUID(base)
                    var provenUID: String?
                    var total = 0
                    for type in ["100", "200", "301", "302", "500"] {
                        var end = "0"
                        var page = 0
                        while true {
                            page += 1
                            guard page <= Self.maximumWishPages else {
                                throw LauncherCoreError(code: "wish_sync_limit", message: "祈愿记录分页过多，已停止读取")
                            }
                            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
                            var query = (components.queryItems ?? []).reduce(into: [String: String]()) {
                                $0[$1.name] = $1.value ?? ""
                            }
                            query["gacha_type"] = type
                            query["size"] = "20"
                            query["end_id"] = end
                            query["lang"] = query["lang"] ?? "zh-cn"
                            components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
                            guard let url = components.url else {
                                throw LauncherCoreError(code: "gacha_url_invalid", message: "抽卡 URL 无效")
                            }
                            let data = try await self.api(URLRequest(url: url, timeoutInterval: 30))
                            let values = data["list"]?.arrayValue.compactMap(\.objectValue) ?? []
                            guard values.count <= 100 else {
                                throw LauncherCoreError(code: "wish_payload_invalid", message: "祈愿分页数据无效")
                            }
                            if let hintedUID {
                                guard values.allSatisfy({
                                    $0["uid"]?.text.nonempty.map { $0 == hintedUID } ?? true
                                }) else {
                                    throw LauncherCoreError(code: "gacha_uid_mismatch", message: "抽卡 URL 返回了不一致的 UID")
                                }
                            }
                            let records = values.compactMap {
                                Self.wish(uid: hintedUID ?? $0["uid"]?.text ?? "", value: $0)
                            }
                            for record in records {
                                if let provenUID, provenUID != record.uid {
                                    throw LauncherCoreError(code: "gacha_uid_mismatch", message: "抽卡 URL 返回了不一致的 UID")
                                }
                                provenUID = provenUID ?? record.uid
                            }
                            total += records.count
                            guard total <= Self.maximumImportedGachaRecords else {
                                throw LauncherCoreError(code: "gacha_record_limit", message: "抽卡 URL 返回的记录过多")
                            }
                            if !records.isEmpty { continuation.yield(records) }
                            if records.count < 20 { break }
                            guard let next = records.last?.id, next != end else {
                                throw LauncherCoreError(code: "wish_pagination_invalid", message: "祈愿记录分页游标未推进")
                            }
                            end = next
                            try await Task.sleep(for: .milliseconds(Int.random(in: 1_000...1_999)))
                        }
                    }
                    guard let provenUID, total > 0 else {
                        throw LauncherCoreError(code: "gacha_url_unverified", message: "抽卡 URL 可用，但无法确认 UID")
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func dailyNote(
        credential: String,
        role: GameRole,
        challenge: String,
        challengePath: String
    ) async throws -> DailyNote {
        try await noteClient.note(
            credential: credential, role: role, challenge: challenge, challengePath: challengePath
        )
    }

    func verifyNoteChallenge(
        credential: String,
        challenge: String,
        validate: String,
        challengePath: String
    ) async throws -> String {
        try await noteClient.verify(
            credential: credential, challenge: challenge, validate: validate, challengePath: challengePath
        )
    }

    func authTicket(credential: String) async throws -> String {
        let values = MiHoYoSigning.cookies(credential)
        guard let stoken = values["stoken"]?.nonempty,
              let mid = values["mid"]?.nonempty,
              let aid = (values["stuid"] ?? values["account_id"])?.nonempty,
              Int(aid) != nil else {
            throw LauncherCoreError(code: "credential_invalid", message: "Cookie 缺少 stoken/mid/stuid，无法创建游戏登录票据")
        }
        let body = try JSONEncoder.api.encode([
            "game_biz": JSONValue.string("hk4e_cn"), "mid": .string(mid),
            "stoken": .string(stoken), "uid": .number(Double(aid)!)
        ])
        let snapshot = await device.snapshot()
        let data = try await api(request(
            "https://passport-api.mihoyo.com/account/ma-cn-verifier/app/createAuthTicketByGameBiz",
            method: "POST",
            headers: [
                "Cookie": credential, "User-Agent": "HYPContainer/1.1.4.133",
                "x-rpc-app_id": "ddxf5dufpuyo", "x-rpc-client_type": "3",
                "x-rpc-device_id": snapshot.hoyoplayDeviceID, "Content-Type": "application/json"
            ], body: body
        ))
        guard let ticket = data["ticket"]?.text.nonempty,
              ticket.utf8.count <= 4_096,
              !ticket.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw LauncherCoreError(code: "auth_ticket_invalid", message: "游戏登录票据无效")
        }
        return ticket
    }

    private func createMobileCaptcha(_ mobile: String, aigis: String) async throws -> MobileCaptchaSession {
        guard Self.validText(aigis, maximum: 16 * 1024) else {
            throw LauncherCoreError(code: "aigis_payload_invalid", message: "验证码验证信息无效")
        }
        let object = [
            "area_code": try MiHoYoSigning.encryptPassport("+86"),
            "mobile": try MiHoYoSigning.encryptPassport(mobile)
        ]
        let body = try JSONEncoder.api.encode(object)
        let text = String(decoding: body, as: UTF8.self)
        var headers = try await passportHeaders(ds: MiHoYoSigning.sign(.prod, body: text))
        headers["x-rpc-aigis"] = aigis
        let payload = try await transport.send(
            request(
                "https://passport-api.mihoyo.com/account/ma-cn-verifier/verifier/createLoginCaptcha",
                method: "POST", headers: headers, body: body
            ), policy: .mihoyo, maximumBytes: 1024 * 1024
        )
        if let raw = payload.headers["x-rpc-aigis"]?.nonempty,
           raw.utf8.count <= 16 * 1024,
           let data = raw.data(using: .utf8),
           let value = try? JSONDecoder.api.decode([String: JSONValue].self, from: data),
           let id = value["session_id"]?.text.nonempty,
           let encoded = value["data"]?.text.data(using: .utf8),
           let verification = try? JSONDecoder.api.decode([String: JSONValue].self, from: encoded),
           let gt = verification["gt"]?.text.nonempty,
           let challenge = verification["challenge"]?.text.nonempty,
           id.utf8.count <= 512, gt.utf8.count <= 512, challenge.utf8.count <= 4_096,
           Self.validText(id), Self.validText(gt), Self.validText(challenge) {
            pruneSessions()
            aigisSessions[id] = AigisSession(
                id: id, mobile: mobile, gt: gt, challenge: challenge,
                expiresAt: Date().addingTimeInterval(300)
            )
            throw LauncherCoreError(
                code: "verification_required", message: "请完成人机验证后重试",
                details: ["gt": .string(gt), "challenge": .string(challenge), "session_id": .string(id)]
            )
        }
        let envelope = try MiHoYoEnvelope.decode(payload)
        let data = envelope.data.objectValue ?? [:]
        let actionType = data["action_type"]?.text ?? ""
        let countdown = data["countdown"]?.int ?? 60
        let aigis = payload.headers["x-rpc-aigis"]?.nonempty
        guard Self.validText(actionType, maximum: 128, allowEmpty: false),
              (0...3_600).contains(countdown),
              aigis.map({ Self.validText($0, maximum: 16 * 1024, allowEmpty: false) }) ?? true else {
            throw LauncherCoreError(code: "captcha_payload_invalid", message: "短信验证码响应无效")
        }
        return MobileCaptchaSession(
            mobile: mobile,
            actionType: actionType,
            countdown: countdown,
            aigis: aigis,
            verification: nil
        )
    }

    private func identity(user: [String: JSONValue], token: String) async throws -> ProviderIdentity {
        let aid = user["aid"]?.text ?? ""
        let mid = user["mid"]?.text ?? ""
        let credential = try await completeCredential("stuid=\(aid); stoken=\(token); mid=\(mid)")
        return ProviderIdentity(
            aid: aid, mid: mid,
            nickname: user["account_name"]?.text.nonempty ?? "米游社用户",
            credential: credential
        )
    }

    private func normalizeCredential(_ raw: String) async throws -> String {
        var values = MiHoYoSigning.cookies(raw)
        if values["stoken"]?.nonempty != nil { return MiHoYoSigning.serialize(values) }
        guard let ticket = values["login_ticket"]?.nonempty,
              let uid = values["login_uid"]?.nonempty else {
            throw LauncherCoreError(code: "credential_invalid", message: "Cookie 缺少 stuid/stoken，或 login_ticket/login_uid")
        }
        var components = URLComponents(string: "https://api-takumi.mihoyo.com/auth/api/getMultiTokenByLoginTicket")!
        components.queryItems = [
            .init(name: "login_ticket", value: ticket), .init(name: "uid", value: uid),
            .init(name: "token_types", value: "3")
        ]
        let data = try await api(URLRequest(url: components.url!))
        let stoken = data["list"]?.arrayValue.compactMap(\.objectValue)
            .first(where: { $0["name"]?.text == "stoken" })?["token"]?.text
        guard let stoken = stoken?.nonempty else {
            throw LauncherCoreError(code: "credential_invalid", message: "Cookie 登录票据无法换取 stoken，请重新获取 Cookie")
        }
        values["stuid"] = uid
        values["stoken"] = stoken
        values["login_ticket"] = nil
        values["login_uid"] = nil
        return MiHoYoSigning.serialize(values)
    }

    private func completeCredential(_ raw: String) async throws -> String {
        var values = MiHoYoSigning.cookies(raw)
        guard values["stoken"]?.nonempty != nil else { return MiHoYoSigning.serialize(values) }
        let snapshot = await device.snapshot()
        if values["cookie_token"]?.nonempty == nil || values["account_id"]?.nonempty == nil {
            let data = try await passport(
                "https://passport-api.mihoyo.com/account/auth/api/getCookieAccountInfoBySToken",
                values: values, deviceID: snapshot.deviceID
            )
            values["cookie_token"] = data["cookie_token"]?.text
            values["account_id"] = data["uid"]?.text
        }
        if values["ltoken"]?.nonempty == nil || values["ltuid"]?.nonempty == nil {
            let data = try await passport(
                "https://passport-api.mihoyo.com/account/auth/api/getLTokenBySToken",
                values: values, deviceID: snapshot.deviceID
            )
            values["ltoken"] = data["ltoken"]?.text
            values["ltuid"] = values["stuid"] ?? values["account_id"]
        }
        return MiHoYoSigning.serialize(values)
    }

    private func passport(_ url: String, values: [String: String], deviceID: String) async throws -> [String: JSONValue] {
        let headers = [
            "Cookie": MiHoYoSigning.serialize(values), "DS": MiHoYoSigning.sign(.prod),
            "User-Agent": Self.agent, "x-rpc-app_version": "2.95.1",
            "x-rpc-client_type": "2", "x-rpc-device_id": deviceID, "Content-Type": "application/json"
        ]
        return try await api(request(url, headers: headers))
    }

    private func authKey(credential: String, role: GameRole) async throws -> String {
        let body = try JSONEncoder.api.encode([
            "auth_appid": JSONValue.string("webview_gacha"), "game_biz": .string("hk4e_cn"),
            "game_uid": .number(Double(role.uid) ?? 0), "region": .string(role.region)
        ])
        let data = try await api(request(
            "https://api-takumi.mihoyo.com/binding/api/genAuthKey",
            method: "POST",
            headers: try await headers(cookie: credential, ds: MiHoYoSigning.sign(.lk2, generation: 1)),
            body: body
        ))
        guard let key = data["authkey"]?.text.nonempty,
              key.utf8.count <= 8 * 1024,
              !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw LauncherCoreError(code: "gacha_authkey_invalid", message: "祈愿鉴权信息无效")
        }
        return key
    }

    private nonisolated static func wish(uid: String, value: [String: JSONValue]) -> WishRecord? {
        let type = value["gacha_type"]?.text ?? ""
        let time = value["time"]?.text.replacingOccurrences(of: " ", with: "T") ?? ""
        let date = CoreDate.parse(time)
        guard date != .distantPast,
              uid.range(of: "^[0-9]{9,10}$", options: .regularExpression) != nil else { return nil }
        return WishRecord(
            id: value["id"]?.text ?? "", uid: uid, gachaType: type,
            itemId: value["item_id"]?.text ?? "", name: value["name"]?.text ?? "",
            itemType: value["item_type"]?.text ?? "", rank: value["rank_type"]?.int ?? 0,
            time: date, iconUrl: nil
        )
    }

    private nonisolated static func queryUID(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { ["uid", "game_uid", "role_id"].contains($0.name) }?.value?.nonempty
    }

    private func pruneSessions() {
        let now = Date()
        qrSessions = qrSessions.filter { $0.value.expiresAt > now }
        aigisSessions = aigisSessions.filter { $0.value.expiresAt > now }
        while qrSessions.count >= Self.maximumSessionCount {
            guard let oldest = qrSessions.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key else { break }
            qrSessions.removeValue(forKey: oldest)
        }
        while aigisSessions.count >= Self.maximumSessionCount {
            guard let oldest = aigisSessions.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key else { break }
            aigisSessions.removeValue(forKey: oldest)
        }
    }

    private func api(_ request: URLRequest) async throws -> [String: JSONValue] {
        let payload = try await transport.send(request, policy: .mihoyo, maximumBytes: 8 * 1024 * 1024)
        return try MiHoYoEnvelope.decode(payload).data.objectValue ?? [:]
    }

    private func headers(cookie: String, ds: String) async throws -> [String: String] {
        let snapshot = try await device.fingerprint()
        return [
            "Cookie": cookie, "DS": ds, "User-Agent": Self.agent,
            "x-rpc-app_version": "2.95.1", "x-rpc-client_type": "5",
            "x-rpc-device_id": snapshot.deviceID, "x-rpc-device_fp": snapshot.deviceFP,
            "Content-Type": "application/json"
        ]
    }

    private func passportHeaders(ds: String) async throws -> [String: String] {
        let snapshot = await device.snapshot()
        return [
            "Cookie": "", "DS": ds, "User-Agent": Self.agent, "x-rpc-aigis": "",
            "x-rpc-app_id": "bll8iq97cem8", "x-rpc-app_version": "2.95.1",
            "x-rpc-client_type": "2", "x-rpc-device_id": snapshot.deviceID,
            "x-rpc-device_name": "", "x-rpc-game_biz": "bbs_cn",
            "x-rpc-sdk_version": "2.16.0", "Content-Type": "application/json"
        ]
    }

    private func qrHeaders() async throws -> [String: String] {
        let snapshot = await device.snapshot()
        return [
            "User-Agent": "HYPContainer/1.1.4.133", "x-rpc-app_id": "ddxf5dufpuyo",
            "x-rpc-client_type": "3", "x-rpc-device_id": snapshot.hoyoplayDeviceID,
            "Content-Type": "application/json"
        ]
    }

    private func request(
        _ string: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> URLRequest {
        var value = URLRequest(url: URL(string: string)!, timeoutInterval: 30)
        value.httpMethod = method
        value.allHTTPHeaderFields = headers
        value.httpBody = body
        return value
    }

    private func session(_ value: QRSession, status: String) -> QRSession {
        QRSession(id: value.id, url: value.url, status: status, expiresAt: value.expiresAt)
    }

    private nonisolated static func validText(
        _ value: String,
        maximum: Int = 4_096,
        allowEmpty: Bool = true
    ) -> Bool {
        (allowEmpty || !value.isEmpty) && value.utf8.count <= maximum
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
