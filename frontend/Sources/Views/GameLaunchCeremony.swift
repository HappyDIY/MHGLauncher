import SwiftUI

struct GameLaunchCeremonyHost: View {
    @Bindable var store: LauncherStore

    var body: some View {
        Group {
            if isPresented {
                GameLaunchCeremonyOverlay(status: store.gameLaunch?.status)
                    .motionTransition(.emphasis)
                    .accessibilityIdentifier("game-launch-ceremony")
            }
        }
        .motionAnimation(.emphasis, value: isPresented)
    }

    private var isPresented: Bool {
        if store.isLaunchingGame { return true }
        guard let status = store.gameLaunch?.status else { return false }
        return [.preparing, .starting, .waitingWindow].contains(status)
    }
}

private struct GameLaunchCeremonyOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: GameLaunchStatus?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Color.black.opacity(0.58)
            launchGrid
            VStack(spacing: 24) {
                LaunchReactor(reduceMotion: reduceMotion)
                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                LaunchPhaseRail(activeIndex: activeIndex)
            }
            .padding(36)
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("游戏启动进度")
        .accessibilityValue(title)
    }

    private var launchGrid: some View {
        Canvas { context, size in
            let spacing: CGFloat = 36
            var path = Path()
            stride(from: CGFloat.zero, through: size.width, by: spacing).forEach {
                path.move(to: CGPoint(x: $0, y: 0))
                path.addLine(to: CGPoint(x: $0, y: size.height))
            }
            stride(from: CGFloat.zero, through: size.height, by: spacing).forEach {
                path.move(to: CGPoint(x: 0, y: $0))
                path.addLine(to: CGPoint(x: size.width, y: $0))
            }
            context.stroke(path, with: .color(.cyan.opacity(0.09)), lineWidth: 0.5)
        }
        .mask(
            RadialGradient(
                colors: [.black, .black.opacity(0.45), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 390
            )
        )
        .accessibilityHidden(true)
    }

    private var title: String {
        switch status {
        case .preparing: "正在校验游戏环境"
        case .starting: "正在点火启动引擎"
        case .waitingWindow: "正在等待游戏窗口"
        default: "正在建立启动序列"
        }
    }

    private var subtitle: String {
        switch status {
        case .preparing: "确认兼容组件与游戏文件"
        case .starting: "Wine 与图形转换层正在就绪"
        case .waitingWindow: "启动完成后将自动进入游戏"
        default: "正在准备本次游戏会话"
        }
    }

    private var activeIndex: Int {
        switch status {
        case .starting: 1
        case .waitingWindow: 2
        default: 0
        }
    }
}

private struct LaunchReactor: View {
    let reduceMotion: Bool
    @State private var rotates = false
    @State private var glows = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.cyan.opacity(0.18), lineWidth: 1)
                .frame(width: 178, height: 178)
            Circle()
                .trim(from: 0.08, to: 0.74)
                .stroke(
                    AngularGradient(
                        colors: [.clear, .cyan, .white, .orange, .clear],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 156, height: 156)
                .rotationEffect(.degrees(rotates ? 360 : 0))
            Circle()
                .stroke(
                    .white.opacity(0.32),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 8])
                )
                .frame(width: 126, height: 126)
                .rotationEffect(.degrees(rotates ? -360 : 0))
            Circle()
                .fill(.cyan.opacity(glows ? 0.18 : 0.06))
                .frame(width: 92, height: 92)
                .shadow(color: .cyan.opacity(glows ? 0.65 : 0.22), radius: 26)
            Image(systemName: "power")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(LauncherMotion.activityRotation) { rotates = true }
            withAnimation(LauncherMotion.activityGlow) { glows = true }
        }
        .accessibilityHidden(true)
    }
}

private struct LaunchPhaseRail: View {
    let activeIndex: Int
    private let phases = ["环境校验", "引擎启动", "窗口就绪"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(phases.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle()
                        .fill(index <= activeIndex ? Color.cyan : Color.white.opacity(0.18))
                        .frame(width: 54, height: 1)
                }
                VStack(spacing: 7) {
                    Circle()
                        .fill(index <= activeIndex ? Color.cyan : Color.white.opacity(0.2))
                        .frame(width: 7, height: 7)
                        .shadow(
                            color: index == activeIndex ? .cyan.opacity(0.8) : .clear,
                            radius: 7
                        )
                    Text(phases[index])
                        .font(.caption2.weight(index == activeIndex ? .semibold : .regular))
                        .foregroundStyle(index <= activeIndex ? .white : .secondary)
                }
            }
        }
        .motionAnimation(.progress, value: activeIndex)
    }
}
