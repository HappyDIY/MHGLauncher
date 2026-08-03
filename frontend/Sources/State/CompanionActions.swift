import Foundation

extension LauncherStore {
    func runNoteRefreshLoop() async {
        while !Task.isCancelled {
            if account != nil, selectedRole != nil {
                await refreshNote(silent: true)
            }
            await evaluateNotifications(silent: true)
            do {
                try await clock.sleep(for: .seconds(300))
            } catch {
                return
            }
        }
    }

    func loadCompanionData() async {
        guard let uid = selectedRole?.uid else { return }
        let generation = companionDataGeneration
        await perform {
            try await fetchCompanionData(uid: uid, generation: generation)
        }
    }

    func syncWishes() async {
        await runWishOperation(.sync) {
            let client = try requireClient()
            let task = try await client.companion.startWishSync()
            _ = try await waitForWishTask(task, client: client)
            updateWishOperation(nil, "同步已完成，正在载入最新祈愿数据")
            try await reloadWishes(client: client)
            finishWishOperation("已载入 \(wishes.count) 条祈愿记录")
        }
    }

    func refreshNote(silent: Bool = false) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try requireClient()
            let body = NoteRefreshRequest(
                xrpcChallenge: "",
                xrpcChallengePath: ""
            )
            dailyNote = try await client.companion.refreshNote(body)
        } catch let error as LauncherCoreError {
            if error.code == "verification_required",
               let gt = error.details?["gt"]?.stringValue,
               let challenge = error.details?["challenge"]?.stringValue {
                guard !silent else { return }
                noteVerification = GeetestChallenge(
                    gt: gt,
                    challenge: challenge,
                    xrpcChallengePath: error.details?["xrpc_challenge_path"]?.stringValue
                )
            } else if !silent {
                message = Self.presentableMessage(error)
            }
        } catch {
            if !silent { message = Self.presentableMessage(error) }
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
            let verification = try await client.companion.verifyNote(
                NoteVerificationRequest(
                    challenge: challenge,
                    validate: validate,
                    xrpcChallengePath: verificationContext?.xrpcChallengePath ?? ""
                )
            )
            dailyNote = try await client.companion.refreshNote(
                NoteRefreshRequest(
                    xrpcChallenge: verification.xrpcChallenge,
                    xrpcChallengePath: verificationContext?.xrpcChallengePath ?? ""
                )
            )
        } catch let error as LauncherCoreError {
            if error.code == "verification_required",
               let gt = error.details?["gt"]?.stringValue,
               let challenge = error.details?["challenge"]?.stringValue {
                noteVerification = GeetestChallenge(
                    gt: gt,
                    challenge: challenge,
                    xrpcChallengePath: error.details?["xrpc_challenge_path"]?.stringValue
                )
            } else {
                noteVerification = nil
                message = Self.presentableMessage(error)
            }
        } catch {
            noteVerification = nil
            message = Self.presentableMessage(error)
        }
    }

    func importUIGF(from url: URL) async {
        guard selectedRole != nil else {
            message = LauncherError.roleMissing.localizedDescription
            return
        }
        await runWishOperation(.importUIGF) {
            updateWishOperation(nil, "正在读取 \(url.lastPathComponent)")
            let data = try UIGFFileIO.read(from: url)
            updateWishOperation(nil, "文件读取完成，共 \(data.count) 字节")
            let client = try requireClient()
            let task = try await client.companion.importUIGF(data)
            _ = try await waitForWishTask(task, client: client)
            updateWishOperation(nil, "导入已完成，正在载入最新祈愿数据")
            try await reloadWishes(client: client)
            finishWishOperation("已载入 \(wishes.count) 条祈愿记录")
        }
    }

    func importWishes(fromGachaURL value: String) async {
        await runWishOperation(.importGachaURL) {
            let client = try requireClient()
            let task = try await client.companion.importGachaURL(
                value.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let snapshot = try await waitForWishTask(task, client: client)
            guard let uid = snapshot.targetUids?.first else { throw LauncherError.roleMissing }
            manualWishUID = uid
            updateWishOperation(nil, "URL 导入已完成，正在载入 UID \(uid) 的祈愿数据")
            try await reloadWishes(client: client)
            finishWishOperation("已载入 \(wishes.count) 条祈愿记录")
        }
    }

    func exportUIGF(to url: URL) async {
        guard let uid = selectedRole?.uid else {
            message = LauncherError.roleMissing.localizedDescription
            return
        }
        await runWishOperation(.exportUIGF) {
            updateWishOperation(nil, "正在导出 UID \(uid) 的祈愿记录")
            let client = try requireClient()
            let data = try await client.companion.exportUIGF(uid)
            updateWishOperation(nil, "已生成 \(data.count) 字节 UIGF 数据")
            try UIGFFileIO.write(data, to: url)
            finishWishOperation("已保存到 \(url.lastPathComponent)")
        }
    }

    private func fetchCompanionData(uid: String, generation: Int) async throws {
        let client = try requireClient()
        let snapshot = try await client.companion.snapshot(uid)
        await applyCompanionSnapshot(snapshot, uid: uid, generation: generation)
    }
}
