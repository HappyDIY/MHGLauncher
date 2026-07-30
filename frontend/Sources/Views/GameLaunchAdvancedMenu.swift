import SwiftUI

struct GameLaunchAdvancedMenu: View {
    @Bindable var store: LauncherStore
    @State private var editor: AdvancedLaunchEditor?
    @State private var draftArguments = ""
    @State private var command = ""
    @State private var wineVersion = WineWindowsVersion.windows10

    var body: some View {
        Menu {
            Button("自定义启动参数…", systemImage: "text.append", action: showArguments)
            Divider()
            Button("打开 Wine 文件目录", systemImage: "folder", action: openExplorer)
            .disabled(wineToolsDisabled)
            Button("Wine 首选项…", systemImage: "gearshape", action: showPreferences)
            .disabled(wineToolsDisabled)
            Button("运行命令…", systemImage: "terminal", action: showCommand)
            .disabled(wineToolsDisabled)
        } label: {
            Label("高级选项", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .disabled(store.isStartingWineTool)
        .sheet(item: $editor, content: editorView)
    }

    @ViewBuilder
    func editorView(_ selection: AdvancedLaunchEditor) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(selection.title).font(.headline)
            if selection == .preferences {
                Picker("Windows 版本", selection: $wineVersion) {
                    ForEach(WineWindowsVersion.allCases) { version in
                        Text(version.title).tag(version)
                    }
                }
            } else {
                TextField(selection.placeholder, text: selection == .arguments ? $draftArguments : $command)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel, action: dismissEditor)
                Button(selection.actionTitle) { submit(selection) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection == .command && command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    func showArguments() {
        draftArguments = store.gameLaunchArguments
        presentEditor(.arguments)
    }

    func showCommand() {
        command = ""
        presentEditor(.command)
    }

    func showPreferences() {
        wineVersion = WineWindowsVersion(
            rawValue: store.userSettings.string(forKey: "wineWindowsVersion") ?? ""
        ) ?? .windows10
        presentEditor(.preferences)
    }

    func presentEditor(_ selection: AdvancedLaunchEditor) {
        Task { @MainActor in
            await Task.yield()
            editor = selection
        }
    }

    func openExplorer() {
        Task { await store.startWineTool(.explorer) }
    }

    func dismissEditor() {
        editor = nil
    }

    func submit(_ selection: AdvancedLaunchEditor) {
        switch selection {
        case .arguments:
            store.gameLaunchArguments = draftArguments
            store.showStatus("启动参数已保存")
        case .command:
            Task { await store.startWineTool(.run, command: command) }
        case .preferences:
            store.userSettings.set(wineVersion.rawValue, forKey: "wineWindowsVersion")
            Task { await store.startWineTool(.preferences, command: wineVersion.rawValue) }
        }
        editor = nil
    }

    var wineToolsDisabled: Bool {
        guard let status = store.gameLaunch?.status else { return false }
        return ![.stopped, .exited, .failed].contains(status)
    }
}

enum AdvancedLaunchEditor: String, Identifiable {
    case arguments
    case command
    case preferences
    var id: Self { self }
    var title: String {
        switch self {
        case .arguments: "自定义启动参数"
        case .command: "运行 Windows 命令"
        case .preferences: "Wine 首选项"
        }
    }
    var placeholder: String { self == .arguments ? "启动参数" : "Windows 命令" }
    var actionTitle: String {
        switch self {
        case .arguments: "保存"
        case .command: "运行"
        case .preferences: "应用"
        }
    }
}

enum WineWindowsVersion: String, CaseIterable, Identifiable {
    case windows10 = "win10"
    case windows81 = "win81"
    case windows7 = "win7"
    var id: Self { self }
    var title: String {
        switch self {
        case .windows10: "Windows 10"
        case .windows81: "Windows 8.1"
        case .windows7: "Windows 7"
        }
    }
}
