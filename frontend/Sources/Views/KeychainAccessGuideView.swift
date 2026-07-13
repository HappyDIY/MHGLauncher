import SwiftUI

struct KeychainAccessGuideView: View {
    let errorMessage: String?
    let continueAction: () -> Void
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "key.radiowaves.forward")
                .font(.system(size: 54, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)

            VStack(spacing: 10) {
                Text("授权钥匙串访问")
                    .font(.largeTitle.weight(.semibold))
                Text("启动器会通过 macOS 钥匙串保存账号凭据。继续后若系统请求访问权限，请选择允许。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }

            Button("继续授权", systemImage: "checkmark.shield") {
                continueAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityFocused($errorFocused)
                    .accessibilityLiveRegion(.assertive)
            }
        }
        .padding(32)
        .frame(width: 1150, height: 750)
        .onChange(of: errorMessage) { errorFocused = $1 != nil }
    }
}
