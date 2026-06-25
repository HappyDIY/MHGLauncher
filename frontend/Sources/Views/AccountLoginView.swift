import SwiftUI

struct AccountLoginView: View {
    @Bindable var store: LauncherStore
    @State private var loginMode = LoginMode.qr

    var body: some View {
        GlassCard(loginMode.title, icon: loginMode.icon) {
            Picker("登录方式", selection: $loginMode) {
                ForEach(LoginMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .motionHover(.subtle)
            switch loginMode {
            case .qr: qrLoginContent
            case .mobile: mobileLoginContent
            case .cookie: cookieLoginContent
            }
        }
    }

    private var qrLoginContent: some View {
        HStack(spacing: 24) {
            qrImage
            VStack(alignment: .leading, spacing: 12) {
                Text("使用米游社 App 扫描二维码")
                    .font(.title3.bold())
                Text(loginStatus)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .motionAnimation(.content, value: loginStatus)
                Button(store.qrSession == nil ? "生成二维码" : "重新生成") {
                    Task { await store.beginQRLogin() }
                }
                .buttonStyle(.glassProminent)
                .motionHover(.prominent)
                .disabled(store.isBusy || !store.backend.isReady)
            }
        }
        .motionAnimation(.emphasis, value: store.qrSession?.url)
    }

    private var qrImage: some View {
        Group {
            if let url = store.qrSession?.url, let image = QRCodeImage.make(url) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 180, height: 180)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .motionTransition(.emphasis)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 90))
                    .frame(width: 200, height: 200)
                    .foregroundStyle(.secondary)
                    .motionTransition(.emphasis)
            }
        }
    }

    private var mobileLoginContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("手机号", text: $store.loginMobile)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("短信验证码", text: $store.loginCaptcha)
                    .textFieldStyle(.roundedBorder)
                Button("发送验证码") {
                    Task { await store.sendMobileCaptcha() }
                }
                .disabled(store.loginMobile.count != 11 || store.isBusy)
            }
            Button("登录") {
                Task { await store.loginByMobileCaptcha() }
            }
            .buttonStyle(.glassProminent)
            .motionHover(.prominent)
            .disabled(store.mobileCaptchaSession == nil || store.loginCaptcha.isEmpty || store.isBusy)
        }
    }

    private var cookieLoginContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $store.loginCookie)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            Button("导入 Cookie") {
                Task { await store.loginByCookie() }
            }
            .buttonStyle(.glassProminent)
            .motionHover(.prominent)
            .disabled(store.loginCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusy)
        }
    }

    private var loginStatus: String {
        switch store.qrSession?.status {
        case "created": "等待扫码"
        case "scanned": "已扫码，请在手机上确认"
        case "confirmed": "登录成功"
        case "expired": "二维码已过期"
        default:
            if store.backend.isStarting { "正在启动本地服务…" }
            else if let error = store.backend.errorMessage { error }
            else { "凭据将安全保存在 macOS 钥匙串" }
        }
    }
}

private enum LoginMode: String, CaseIterable, Identifiable {
    case qr
    case mobile
    case cookie

    var id: Self { self }
    var title: String {
        switch self {
        case .qr: "扫码登录"
        case .mobile: "短信登录"
        case .cookie: "Cookie 导入"
        }
    }
    var icon: String {
        switch self {
        case .qr: "qrcode"
        case .mobile: "message.badge"
        case .cookie: "key"
        }
    }
}
