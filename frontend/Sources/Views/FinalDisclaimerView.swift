import SwiftUI

struct FinalDisclaimerView: View {
    let allowsCancellation: Bool
    let onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("最终免责声明", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.orange)
            Text("MHGLauncher 是非官方第三方工具，与米哈游、HoYoverse 及其关联方无隶属、授权或合作关系。")
            Text("本工具会操作游戏文件，并通过兼容层运行游戏。相关行为可能导致账号处罚、数据损坏、游戏异常或其他损失，开发者不对工具的适用性、稳定性、安全性及使用后果作任何保证或承担责任。")
            Text("继续使用即表示你已了解并自愿承担全部风险，同时承诺遵守游戏服务条款及所在地法律法规。请提前备份重要数据。")
            Divider()
            Text("请一字不差输入以下内容以确认：")
                .font(.headline)
            Text(FinalDisclaimerConsent.confirmationText)
                .textSelection(.enabled)
                .font(.callout.weight(.semibold))
            TextField("输入确认内容", text: $confirmation)
                .textFieldStyle(.roundedBorder)
                .onSubmit { agreeIfPossible() }
            HStack {
                if allowsCancellation {
                    Button("取消", role: .cancel) { dismiss() }
                }
                Spacer()
                Button("我已知悉并同意") {
                    FinalDisclaimerConsent.accept()
                    onAgree()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!FinalDisclaimerConsent.matches(confirmation))
            }
        }
        .padding(24)
        .frame(width: 600)
        .interactiveDismissDisabled(!allowsCancellation)
    }

    private func agreeIfPossible() {
        guard FinalDisclaimerConsent.matches(confirmation) else { return }
        FinalDisclaimerConsent.accept()
        onAgree()
        dismiss()
    }
}
