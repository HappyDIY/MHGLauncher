import SwiftUI

struct CharactersView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        Group {
            if store.characters.isEmpty {
                CharacterEmptyView(isBusy: store.isBusy, canSync: store.selectedRole != nil) {
                    Task { await store.refreshCharacters() }
                }
            } else {
                HSplitView {
                    CharacterBrowserView(store: store)
                        .frame(minWidth: 250, idealWidth: 310, maxWidth: 360)
                    CharacterDetailView(store: store)
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("我的角色")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                syncButton
            }
        }
        .task {
            await store.loadCharacters()
            if store.characters.isEmpty { await store.refreshCharacters() }
        }
        .motionEntrance(.content)
    }

    private var syncButton: some View {
        Button {
            Task { await store.refreshCharacters() }
        } label: {
            HStack(spacing: 7) {
                if store.isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text("同步角色")
            }
        }
        .buttonStyle(.glassProminent)
        .disabled(store.isBusy || store.selectedRole == nil)
        .motionHover(.prominent)
    }
}
