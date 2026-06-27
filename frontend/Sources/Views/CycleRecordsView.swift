import SwiftUI

struct CycleRecordsView: View {
    @Bindable var store: LauncherStore
    let kind: CycleKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: kind.title, subtitle: store.selectedRole.map { "UID \($0.uid)" } ?? "未选择角色")
                HStack {
                    Button {
                        Task { await store.refreshCycle(kind) }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Text("\(records.count) 个周期")
                        .foregroundStyle(.secondary)
                }
                LazyVStack(spacing: 14) {
                    ForEach(records) { record in
                        GlassCard(record.title, icon: kindIcon) {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(record.summary)
                                        .font(.title3.weight(.semibold))
                                    Text(period(record))
                                        .foregroundStyle(.secondary)
                                    Text(record.uploadedAt == nil ? "未上传" : "已上传")
                                        .font(.caption)
                                        .foregroundStyle(record.uploadedAt == nil ? .orange : .green)
                                }
                                Spacer()
                                Button {
                                    Task { await store.uploadCycle(record) }
                                } label: {
                                    Image(systemName: "icloud.and.arrow.up")
                                }
                                .help("上传")
                            }
                        }
                    }
                }
            }
        }
        .task { await store.loadCycle(kind) }
        .motionEntrance(.content)
    }

    private var records: [CycleRecord] { store.value.records(for: kind) }
    private var kindIcon: String {
        switch kind {
        case .abyss: "moon.stars"
        case .theatre: "theatermasks"
        case .hard: "flame"
        }
    }

    private func period(_ record: CycleRecord) -> String {
        guard let start = record.startedAt, let end = record.endedAt else { return "周期时间待同步" }
        return "\(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))"
    }
}
