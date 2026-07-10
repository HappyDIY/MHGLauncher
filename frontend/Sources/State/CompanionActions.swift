import AppKit
import Foundation

extension LauncherStore {
    func runNoteRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
            if NSApplication.shared.isActive, credential != nil {
                await refreshNote()
                await evaluateNotifications()
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
            let client = try requireClient()
            let body = CredentialRequest(credential: try requireCredential())
            let task: WishTaskSnapshot = try await client.post(
                "/v1/wishes/tasks/sync",
                body: body
            )
            _ = try await waitForWishTask(task, client: client)
            updateWishOperation(nil, "后端同步已完成，正在载入最新祈愿数据")
            try await reloadWishes(client: client)
            finishWishOperation("已从后端载入 \(wishes.count) 条祈愿记录")
        }
    }

    func refreshNote() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try requireClient()
            let body = NoteRefreshRequest(
                credential: try requireCredential(),
                xrpcChallenge: "",
                xrpcChallengePath: ""
            )
            dailyNote = try await client.post("/v1/notes/refresh", body: body)
        } catch let error as APIErrorPayload {
            if error.code == "verification_required",
               let gt = error.details?["gt"],
               let challenge = error.details?["challenge"] {
                noteVerification = GeetestChallenge(
                    gt: gt,
                    challenge: challenge,
                    xrpcChallengePath: error.details?["xrpc_challenge_path"]
                )
            } else {
                message = Self.presentableMessage(error)
            }
        } catch {
            message = Self.presentableMessage(error.localizedDescription)
        }
    }

    func completeNoteVerification(
        challenge: String,
        validate: String
    ) async {
        let verificationContext = noteVerification
        noteVerification = nil
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
                    validate: validate,
                    xrpcChallengePath: verificationContext?.xrpcChallengePath ?? ""
                )
            )
            dailyNote = try await client.post(
                "/v1/notes/refresh",
                body: NoteRefreshRequest(
                    credential: credential,
                    xrpcChallenge: verification.xrpcChallenge,
                    xrpcChallengePath: verificationContext?.xrpcChallengePath ?? ""
                )
            )
        } catch let error as APIErrorPayload {
            if error.code == "verification_required",
               let gt = error.details?["gt"],
               let challenge = error.details?["challenge"] {
                noteVerification = GeetestChallenge(
                    gt: gt,
                    challenge: challenge,
                    xrpcChallengePath: error.details?["xrpc_challenge_path"]
                )
            } else {
                noteVerification = nil
                message = Self.presentableMessage(error)
            }
        } catch {
            noteVerification = nil
            message = Self.presentableMessage(error.localizedDescription)
        }
    }

    func importUIGF(from url: URL) async {
        await runWishOperation(.importUIGF) {
            updateWishOperation(nil, "正在读取 \(url.lastPathComponent)")
            let data = try UIGFFileIO.read(from: url)
            updateWishOperation(nil, "文件读取完成，共 \(data.count) 字节")
            let client = try requireClient()
            let task: WishTaskSnapshot = try await client.upload(
                "/v1/wishes/tasks/import",
                json: data
            )
            _ = try await waitForWishTask(task, client: client)
            updateWishOperation(nil, "后端导入已完成，正在载入最新祈愿数据")
            try await reloadWishes(client: client)
            finishWishOperation("已从后端载入 \(wishes.count) 条祈愿记录")
        }
    }

    func exportUIGF(to url: URL) async {
        guard let uid = selectedRole?.uid else {
            message = LauncherError.roleMissing.localizedDescription
            return
        }
        await runWishOperation(.exportUIGF) {
            updateWishOperation(nil, "正在请求后端导出 UID \(uid) 的祈愿记录")
            let client = try requireClient()
            let data = try await client.download(
                "/v1/wishes/export",
                query: [URLQueryItem(name: "uid", value: uid)]
            )
            updateWishOperation(nil, "后端已生成 \(data.count) 字节 UIGF 数据")
            try UIGFFileIO.write(data, to: url)
            finishWishOperation("已保存到 \(url.lastPathComponent)")
        }
    }

    private func fetchCompanionData(uid: String) async throws {
        let client = try requireClient()
        let snapshot: CompanionSnapshot = try await client.get(
            "/v1/companion/snapshot",
            query: [URLQueryItem(name: "uid", value: uid)]
        )
        (wishes, wishStatistics, bannerDetails, dailyNote) = (
            snapshot.wishes,
            snapshot.statistics,
            snapshot.bannerStatistics,
            snapshot.note
        )
        companionLoaded = true
    }
}
