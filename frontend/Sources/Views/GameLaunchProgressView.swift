import SwiftUI

struct GameLaunchProgressView: View {
    let launch: GameLaunch

    var body: some View {
        GlassCard("启动实况", icon: "terminal") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(launch.status.title, systemImage: launch.status.icon)
                    Spacer()
                    Text(launch.progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: launch.progress, total: 1)
                    .tint(launch.status == .failed ? .red : .blue)
                    .animation(.easeOut(duration: 0.2), value: launch.progress)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            ForEach(launch.logs) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(Self.time(entry.timestamp))
                                        .foregroundStyle(.tertiary)
                                    Text(entry.message)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                            }
                        }
                    }
                    .frame(minHeight: 110, maxHeight: 180)
                    .onChange(of: launch.logs.count) {
                        if let id = launch.logs.last?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
    }

    private static func time(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return "--:--:--" }
        return date.formatted(date: .omitted, time: .standard)
    }
}
