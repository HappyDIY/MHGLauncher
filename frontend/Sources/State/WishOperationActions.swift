import Foundation
import LocalAuthentication

extension LauncherStore {
    func clearAllWishes() async {
        do {
            try await deviceOwnerAuthenticator.authenticate(
                reason: "确认清空 MHGLauncher 中的全部祈愿记录"
            )
        } catch let error as LAError where error.code == .userCancel {
            return
        } catch {
            message = Self.presentableMessage(error)
            return
        }
        await runWishOperation(.clearAll) {
            updateWishOperation(nil, "本机身份认证已通过", true)
            updateWishOperation(nil, "正在请求后端删除全部祈愿记录")
            let client = try requireClient()
            let result: CountResponse = try await client.deleteResponse("/v1/wishes")
            clearWishPresentation()
            wishStatistics = []
            bannerDetails = []
            finishWishOperation("已永久删除 \(result.deleted ?? 0) 条记录")
        }
    }

    func runWishOperation(
        _ kind: WishOperationKind,
        operation: () async throws -> Void
    ) async {
        guard wishOperation == nil else { return }
        isBusy = true
        let state = WishOperationState(kind: kind)
        let operationID = state.id
        wishOperation = state
        defer { isBusy = false }
        do {
            try await operation()
            try? await Task.sleep(for: .seconds(1.4))
            if wishOperation?.id == operationID, wishOperation?.status == .succeeded {
                wishOperation = nil
            }
        } catch let error as APIErrorPayload {
            if wishOperation?.id == operationID {
                failWishOperation(Self.presentableMessage(error))
            }
        } catch {
            if wishOperation?.id == operationID {
                failWishOperation(Self.presentableMessage(error))
            }
        }
    }

    func updateWishOperation(
        _ progress: Double?,
        _ message: String,
        _ emphasized: Bool = false
    ) {
        wishOperation?.update(
            progress: progress,
            message: message,
            emphasized: emphasized
        )
    }

    func waitForWishTask(
        _ initial: WishTaskSnapshot,
        client: APIClient
    ) async throws -> WishTaskSnapshot {
        var snapshot = initial
        while true {
            wishOperation?.apply(snapshot)
            switch snapshot.status {
            case .completed:
                return snapshot
            case .failed:
                throw WishTaskFailure(message: snapshot.failureMessage)
            case .queued, .running:
                snapshot = try await client.get(
                    "/v1/wishes/tasks/\(snapshot.id)",
                    query: LongPollQuery.items(after: snapshot.revision)
                )
            }
        }
    }

    func finishWishOperation(_ message: String) {
        wishOperation?.succeed(message)
    }

    private func failWishOperation(_ message: String) {
        wishOperation?.fail(message)
    }

    func reloadWishes(client: APIClient) async throws {
        guard let uid = activeWishUID else { throw LauncherError.roleMissing }
        let generation = companionDataGeneration
        let snapshot: CompanionSnapshot = try await client.get(
            "/v1/companion/snapshot",
            query: [URLQueryItem(name: "uid", value: uid)]
        )
        await applyCompanionSnapshot(snapshot, uid: uid, generation: generation)
    }
}

private struct WishTaskFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        LauncherStore.presentableMessage(message)
    }
}
