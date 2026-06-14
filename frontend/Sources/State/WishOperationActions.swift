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
            message = Self.presentableMessage(error.localizedDescription)
            return
        }
        await runWishOperation(.clearAll) {
            updateWishOperation(nil, "本机身份认证已通过", true)
            updateWishOperation(nil, "正在请求后端删除全部祈愿记录")
            let client = try requireClient()
            let result: CountResponse = try await client.deleteResponse("/v1/wishes")
            wishes = []
            wishStatistics = []
            bannerDetails = []
            finishWishOperation("已永久删除 \(result.deleted ?? 0) 条记录")
        }
    }

    func runWishOperation(
        _ kind: WishOperationKind,
        operation: () async throws -> Void
    ) async {
        isBusy = true
        wishOperation = WishOperationState(kind: kind)
        defer { isBusy = false }
        do {
            try await operation()
            let id = wishOperation?.id
            try? await Task.sleep(for: .seconds(1.4))
            if wishOperation?.id == id, wishOperation?.status == .succeeded {
                wishOperation = nil
            }
        } catch let error as APIErrorPayload {
            failWishOperation(Self.presentableMessage(error.message))
        } catch {
            failWishOperation(Self.presentableMessage(error.localizedDescription))
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
                throw WishTaskFailure(message: snapshot.error)
            case .queued, .running:
                try await Task.sleep(for: .milliseconds(250))
                snapshot = try await client.get("/v1/wishes/tasks/\(snapshot.id)")
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
        guard let uid = selectedRole?.uid else { throw LauncherError.roleMissing }
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
        (wishes, wishStatistics, bannerDetails) = try await (records, statistics, details)
    }
}

private struct WishTaskFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        LauncherStore.presentableMessage(message)
    }
}
