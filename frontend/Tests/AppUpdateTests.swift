import Foundation
import Testing
@testable import MHGLauncher

struct AppUpdateTests {
    @Test func comparesSemanticVersions() {
        #expect(AppVersion("0.2.0")! > AppVersion("0.1.9")!)
        #expect(AppVersion("1.0.0")! > AppVersion("1.0.0-beta.2")!)
        #expect(AppVersion("1.0.0-beta.10")! > AppVersion("1.0.0-beta.2")!)
        #expect(AppVersion("broken") == nil)
    }

    @Test func decodesCloudManifestAndChecksCurrentVersion() throws {
        let data = Data(#"{"version":"0.2.0","download_url":"https://download.example/update.dmg","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":1024,"changelog":"更新日志"}"#.utf8)
        let manifest = try JSONDecoder.api.decode(AppUpdateManifest.self, from: data)
        #expect(manifest.isNewer(than: "0.1.0"))
        #expect(!manifest.isNewer(than: "0.2.0"))
    }

    @Test func hashesDownloadedFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("MHGLauncher".utf8).write(to: url)
        #expect(try AppUpdateDownload.sha256(of: url) == "f005c265090bca6097a1b2f23217b4f746fcb0484ca5959ddf52a014c3046b42")
    }
}
