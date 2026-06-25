import SwiftUI

struct GameLaunchProgressView: View {
    let launch: GameLaunch

    var body: some View {
        GlassCard("启动实况", icon: "terminal") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(launch.status.title, systemImage: launch.status.icon)
                        .contentTransition(.symbolEffect(.replace))
                    Spacer()
                    Text(launch.progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                ProgressView(value: launch.progress, total: 1)
                    .tint(launch.status == .failed ? .red : .blue)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            ForEach(launch.logs) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(Self.time(entry.timestamp))
                                        .foregroundStyle(.tertiary)
                                    Text(entry.message)
                                        .foregroundStyle(entry.kind == "dns" ? .cyan : entry.kind == "wine" ? .yellow : .secondary)
                                }
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                                .motionTransition(.content)
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
        .motionAnimation(.selection, value: launch.status)
        .motionAnimation(.progress, value: launch.progress)
        .motionAnimation(.content, value: launch.logs.count)
    }

    private static func time(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: value)
        formatter.formatOptions = [.withInternetDateTime]
        date = date ?? formatter.date(from: value)
        guard let date else { return "--:--:--" }
        let display = DateFormatter()
        display.locale = .current
        display.timeZone = .current
        display.dateFormat = "HH:mm:ss"
        return display.string(from: date)
    }
}
