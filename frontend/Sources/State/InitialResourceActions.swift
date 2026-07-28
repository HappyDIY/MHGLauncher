import Foundation

extension LauncherStore {
    var needsMetadataSetup: Bool {
        value.resourceSyncStatus?.initialInstallRequired == true || resourceSetupError != nil
    }

    func prepareInitialResources() async {
        resourceSetupError = nil
        do {
            let client = try requireClient()
            while !Task.isCancelled {
                let status: ResourceSyncStatus = try await client.get("/v1/resources/status")
                value.resourceSyncStatus = status
                if !status.initialInstallRequired { return }
                if let error = status.error, !status.isSyncing {
                    resourceSetupError = error
                    return
                }
                try await Task.sleep(for: .milliseconds(250))
            }
        } catch is CancellationError {
            return
        } catch {
            resourceSetupError = Self.presentableMessage(error)
        }
    }

    func retryInitialResources() async {
        resourceSetupError = nil
        do {
            let client = try requireClient()
            value.resourceSyncStatus = try await client.post(
                "/v1/resources/sync",
                body: ResourceSyncRequest(force: true),
                timeout: 3_600
            )
            await prepareInitialResources()
            guard !needsMetadataSetup else { return }
            await refreshAccount()
            await loadNotificationSettings()
            await refreshGame()
            await refreshSpeedLimit()
            let savedKB = userSettings.integer(forKey: "downloadSpeedLimitKB")
            if savedKB > 0 { await setSpeedLimit(savedKB) }
            if selectedRole != nil { await loadCompanionData(); await loadValueData() }
            Task { await checkForAppUpdate(silent: true) }
        } catch {
            resourceSetupError = Self.presentableMessage(error)
        }
    }

    func startInitialResourceRetry() {
        Task { await retryInitialResources() }
    }
}
