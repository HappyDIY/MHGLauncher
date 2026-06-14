import SwiftUI

struct WishOperationOverlay: View {
    let operation: WishOperationState
    let close: () -> Void
    @State private var glow = false
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                header
                progress
                logConsole
                footer
            }
            .padding(26)
            .frame(width: 540)
            .background(.thinMaterial, in: .rect(cornerRadius: 24))
            .glassEffect(
                .regular.tint(accent.opacity(0.08)).interactive(),
                in: .rect(cornerRadius: 24)
            )
            .overlay(border)
            .shadow(color: accent.opacity(glow ? 0.65 : 0.24), radius: glow ? 38 : 18)
            .scaleEffect(glow ? 1 : 0.985)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                glow = true
            }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(accent.opacity(0.14)).frame(width: 54, height: 54)
                Image(systemName: statusIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
                    .rotationEffect(.degrees(isRunning ? rotation : 0))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(operation.kind.title).font(.title2.bold())
                Text(operation.statusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(accent)
            }
            Spacer()
            Text("\(Int(operation.progress * 100))%")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
        }
    }

    private var progress: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule()
                    .fill(gradient)
                    .frame(width: max(12, proxy.size.width * operation.progress))
                    .shadow(color: accent.opacity(0.8), radius: 10)
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                            .blur(radius: glow ? 1 : 3)
                    }
            }
        }
        .frame(height: 10)
        .animation(.spring(duration: 0.55), value: operation.progress)
    }

    private var logConsole: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(operation.logs) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text(entry.emphasized ? "◆" : "›")
                                .foregroundStyle(entry.emphasized ? accent : .secondary)
                            Text(entry.message)
                                .foregroundStyle(entry.emphasized ? .primary : .secondary)
                        }
                        .font(.system(.callout, design: .monospaced))
                        .id(entry.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(height: 174)
            .background(.black.opacity(0.22), in: .rect(cornerRadius: 14))
            .glassEffect(.clear, in: .rect(cornerRadius: 14))
            .onChange(of: operation.logs.count) {
                if let id = operation.logs.last?.id {
                    withAnimation { reader.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if operation.status == .failed {
            HStack {
                Spacer()
                Button("关闭") { close() }
                    .buttonStyle(.glassProminent)
            }
        } else {
            Text(isRunning ? "正在安全处理数据，请勿关闭启动器" : "数据处理完成")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 24)
            .stroke(gradient, lineWidth: 1.2)
            .opacity(glow ? 0.9 : 0.4)
    }

    private var isRunning: Bool { operation.status == .running }
    private var accent: Color {
        operation.status == .failed ? .red : operation.status == .succeeded ? .green : .cyan
    }
    private var gradient: LinearGradient {
        LinearGradient(colors: [accent, .purple, accent], startPoint: .leading, endPoint: .trailing)
    }
    private var statusIcon: String {
        switch operation.status {
        case .running: operation.kind.icon
        case .succeeded: "checkmark"
        case .failed: "xmark"
        }
    }
}
