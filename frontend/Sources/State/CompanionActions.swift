import AppKit
import Foundation

extension LauncherStore {
    func runNoteRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
            if NSApplication.shared.isActive, credential != nil {
                await refreshNote()
            }
        }
    }

    func loadCompanionData() async {
        guard let uid = selectedRole?.uid else { return }
        await perform {
            try await fetchCompanionData(uid: uid)
        }
    }

    func syncWishes() async {
        await runWishOperation(.sync) {
            updateWishOperation(0.12, "正在验证账号与角色信息")
            let client = try requireClient()
            let body = CredentialRequest(credential: try requireCredential())
            updateWishOperation(0.28, "已连接米游社，开始增量扫描卡池")
            let result: CountResponse = try await client.post(
                "/v1/wishes/sync",
                body: body,
                timeout: 300
            )
            updateWishOperation(0.76, "同步完成，新增 \(result.inserted ?? 0) 条记录", true)
            try await reloadWishes(client: client)
            finishWishOperation("本地祈愿统计已更新")
        }
    }

    func refreshNote() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try requireClient()
            let body = NoteRefreshRequest(
                credential: try requireCredential(),
                xrpcChallenge: ""
            )
            dailyNote = try await client.post("/v1/notes/refresh", body: body)
        } catch let error as APIErrorPayload {
            if error.code == "verification_required",
               let gt = error.details?["gt"],
               let challenge = error.details?["challenge"] {
                noteVerification = GeetestChallenge(
                    gt: gt,
                    challenge: challenge
                )
            } else {
                message = Self.presentableMessage(error.message)
            }
        } catch {
            message = Self.presentableMessage(error.localizedDescription)
        }
    }

    func completeNoteVerification(
        challenge: String,
        validate: String
    ) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try requireClient()
            let credential = try requireCredential()
            let verification: NoteVerificationResponse = try await client.post(
                "/v1/notes/verification",
                body: NoteVerificationRequest(
                    credential: credential,
                    challenge: challenge,
                    validate: validate
                )
            )
            dailyNote = try await client.post(
                "/v1/notes/refresh",
                body: NoteRefreshRequest(
                    credential: credential,
                    xrpcChallenge: verification.xrpcChallenge
                )
            )
            noteVerification = nil
        } catch let error as APIErrorPayload {
            message = Self.presentableMessage(error.message)
        } catch {
            message = Self.presentableMessage(error.localizedDescription)
        }
    }

    func importUIGF(from url: URL) async {
        await runWishOperation(.importUIGF) {
            updateWishOperation(0.1, "正在读取 \(url.lastPathComponent)")
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            updateWishOperation(0.32, "文件读取完成，正在校验 UIGF 数据")
            let client = try requireClient()
            let result: CountResponse = try await client.upload("/v1/wishes/import", json: data)
            updateWishOperation(0.76, "成功导入 \(result.imported ?? 0) 条记录", true)
            try await reloadWishes(client: client)
            finishWishOperation("祈愿历史与统计已重新载入")
        }
    }

    func exportUIGF(to url: URL) async {
        guard let uid = selectedRole?.uid else {
            message = LauncherError.roleMissing.localizedDescription
            return
        }
        await runWishOperation(.exportUIGF) {
            updateWishOperation(0.14, "正在整理 UID \(uid) 的祈愿记录")
            let client = try requireClient()
            let data = try await client.download(
                "/v1/wishes/export",
                query: [URLQueryItem(name: "uid", value: uid)]
            )
            updateWishOperation(0.72, "UIGF v4.2 数据生成完成")
            try data.write(to: url, options: .atomic)
            finishWishOperation("已保存到 \(url.lastPathComponent)")
        }
    }

    private func fetchCompanionData(uid: String) async throws {
        let client = try requireClient()
        async let records: [WishRecord] = client.get(
            "/v1/wishes",
            query: [URLQueryItem(name: "uid", value: uid)]
        )
        async let statistics: [WishStatistics] = client.get(
            "/v1/wishes/statistics",
            query: [URLQueryItem(name: "uid", value: uid)]
        )
        async let details: [WishBannerDetail] = client.get(
            "/v1/wishes/banner-statistics",
            query: [URLQueryItem(name: "uid", value: uid)]
        )
        async let note: DailyNote? = client.get(
            "/v1/notes",
            query: [URLQueryItem(name: "uid", value: uid)]
        )
        (wishes, wishStatistics, bannerDetails, dailyNote) = try await (records, statistics, details, note)
    }
}
