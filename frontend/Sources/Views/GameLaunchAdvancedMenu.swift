import SwiftUI

struct GameLaunchAdvancedMenu: View {
    @Bindable var store: LauncherStore
    @State private var editor: AdvancedLaunchEditor?
    @State private var draftArguments = ""
    @State private var command = ""

    var body: some View {
        Menu {
            Button("自定义启动参数…", systemImage: "text.append", action: showArguments)
            Divider()
            Button("打开 Wine 文件目录", systemImage: "folder", action: openExplorer)
            .disabled(wineToolsDisabled)
            Button("打开 Wine 首选项", systemImage: "gearshape", action: openPreferences)
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
            TextField(selection.placeholder, text: selection == .arguments ? $draftArguments : $command)
                .textFieldStyle(.roundedBorder)
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

    func presentEditor(_ selection: AdvancedLaunchEditor) {
        Task { @MainActor in
            await Task.yield()
            editor = selection
        }
    }

    func openExplorer() {
        Task { await store.startWineTool(.explorer) }
    }

    func openPreferences() {
        Task { await store.startWineTool(.preferences) }
    }

    func dismissEditor() {
        editor = nil
    }

    func submit(_ selection: AdvancedLaunchEditor) {
        if selection == .arguments {
            store.gameLaunchArguments = draftArguments
            store.showStatus("启动参数已保存")
        } else {
            Task { await store.startWineTool(.run, command: command) }
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
    var id: Self { self }
    var title: String { self == .arguments ? "自定义启动参数" : "运行 Windows 命令" }
    var placeholder: String { self == .arguments ? "启动参数" : "Windows 命令" }
    var actionTitle: String { self == .arguments ? "保存" : "运行" }
}
