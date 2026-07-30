import Foundation
import Testing
@testable import MHGLauncher

@Suite("Wine 高级工具", .serialized)
struct WineToolActionTests {
    @Test("运行命令发送严格的 Wine 工具请求")
    @MainActor
    func runCommand() async throws {
        let body = JSONValue.object([
            "action": .string("run"),
            "command": .string("regedit"),
            "performance_profile": .string("compatibility"),
        ])
        let transport = ScriptedTransport([
            try .init("POST", "/v1/game/wine-tools", body: body, response: EmptyResponse()),
        ])
        let client = APIClient(token: "fixture") { try await transport.respond($0) }
        let suite = "WineToolActionTests.\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suite)!
        settings.removePersistentDomain(forName: suite)
        let store = LauncherStore(dependencies: LauncherDependencies(
            keychain: MemoryKeychainStore(),
            userSettings: settings
        ))
        store.backend.useClient(client)
        store.gameRuntimeReady = true
        store.gamePerformanceProfile = .compatibility

        await store.startWineTool(.run, command: "regedit")

        #expect(!store.isStartingWineTool)
        #expect(store.message == nil)
        try await transport.verify()
    }

    @Test("自定义启动参数保存到用户设置")
    @MainActor
    func persistsLaunchArguments() {
        let suite = "WineToolArguments.\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suite)!
        settings.removePersistentDomain(forName: suite)
        let store = LauncherStore(dependencies: LauncherDependencies(
            keychain: MemoryKeychainStore(),
            userSettings: settings
        ))
        store.gameLaunchArguments = "-popupwindow"
        #expect(settings.string(forKey: "gameLaunchArguments") == "-popupwindow")
    }

    @Test("高级菜单动作可完整触发")
    @MainActor
    func advancedMenuActions() async throws {
        let transport = ScriptedTransport([
            try wineToolStep(.explorer),
            try wineToolStep(.preferences, command: "win10"),
            try wineToolStep(.run, command: ""),
        ])
        let client = APIClient(token: "fixture") { try await transport.respond($0) }
        let store = LauncherStore()
        store.backend.useClient(client)
        store.gameRuntimeReady = true
        let menu = GameLaunchAdvancedMenu(store: store)
        _ = menu.body
        _ = menu.editorView(.arguments)
        _ = menu.editorView(.command)
        _ = menu.editorView(.preferences)
        for editor in [AdvancedLaunchEditor.arguments, .command, .preferences] {
            _ = editor.id; _ = editor.title; _ = editor.placeholder; _ = editor.actionTitle
        }
        for version in WineWindowsVersion.allCases {
            _ = version.id; _ = version.title
        }
        menu.showArguments(); menu.submit(.arguments)
        menu.showCommand(); menu.dismissEditor()
        menu.openExplorer(); try await waitForWineTool(store)
        menu.showPreferences(); menu.submit(.preferences); try await waitForWineTool(store)
        menu.submit(.command); try await waitForWineTool(store)
        #expect(!menu.wineToolsDisabled)
        try await transport.verify()
    }

    @MainActor
    private func waitForWineTool(_ store: LauncherStore) async throws {
        await Task.yield()
        for _ in 0..<100 where store.isStartingWineTool {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!store.isStartingWineTool)
    }

    private func wineToolStep(
        _ action: WineToolAction,
        command: String? = nil
    ) throws -> ScriptedTransport.Expectation {
        var fields: [String: JSONValue] = [
            "action": .string(action.rawValue),
            "performance_profile": .string("optimized"),
        ]
        if let command { fields["command"] = .string(command) }
        return try .init(
            "POST", "/v1/game/wine-tools",
            body: .object(fields),
            response: EmptyResponse()
        )
    }
}
