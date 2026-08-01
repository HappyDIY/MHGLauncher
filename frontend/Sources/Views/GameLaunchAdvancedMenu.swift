import SwiftUI

struct GameLaunchAdvancedMenu: View {
    @Bindable var store: LauncherStore
    @Binding var editor: AdvancedLaunchEditor?

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
    }

    func showArguments() {
        editor = .arguments
    }

    func showCommand() {
        editor = .command
    }

    func openExplorer() {
        Task { await store.startWineTool(.explorer) }
    }

    func openPreferences() {
        Task { await store.startWineTool(.preferences) }
    }

    var wineToolsDisabled: Bool {
        guard let status = store.gameLaunch?.status else { return false }
        return ![.stopped, .exited, .failed].contains(status)
    }
}

struct GameLaunchAdvancedEditor: View {
    @Bindable var store: LauncherStore
    let selection: AdvancedLaunchEditor
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(store: LauncherStore, selection: AdvancedLaunchEditor) {
        self.store = store
        self.selection = selection
        _text = State(initialValue: selection == .arguments ? store.gameLaunchArguments : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(selection.title).font(.headline)
            TextField(selection.placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button(selection.actionTitle, action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(selection == .command && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    func submit() {
        if selection == .arguments {
            store.gameLaunchArguments = text
            store.showStatus("启动参数已保存")
        } else {
            Task { await store.startWineTool(.run, command: text) }
        }
        dismiss()
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
