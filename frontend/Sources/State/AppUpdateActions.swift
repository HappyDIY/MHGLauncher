import AppKit
import Foundation

extension LauncherStore {
    var currentAppVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    }

    func checkForAppUpdate(silent: Bool = false) async {
        guard !appUpdate.isChecking else { return }
        appUpdate.isChecking = true
        appUpdate.errorMessage = nil
        defer { appUpdate.isChecking = false }
        do {
            let manifest: AppUpdateManifest = try await requireClient().get("/v1/app-update")
            guard manifest.isNewer(than: currentAppVersion) else {
                appUpdate.manifest = nil
                if !silent { showStatus("MHGLauncher 已是最新版本") }
                return
            }
            appUpdate.manifest = manifest
            appUpdate.showsSheet = true
        } catch {
            let message = Self.presentableMessage(error)
            appUpdate.errorMessage = message
            if !silent { self.message = message }
        }
    }

    func downloadAppUpdate() async {
        guard let manifest = appUpdate.manifest, !appUpdate.isDownloading else { return }
        appUpdate.isDownloading = true
        appUpdate.errorMessage = nil
        defer { appUpdate.isDownloading = false }
        do {
            let url = try await AppUpdateDownload.download(manifest)
            guard NSWorkspace.shared.open(url) else { throw CocoaError(.fileNoSuchFile) }
            appUpdate.showsSheet = false
            showStatus("更新包已通过 SHA-256 校验并打开")
        } catch {
            appUpdate.errorMessage = "更新包下载或校验失败，请稍后重试"
        }
    }
}
