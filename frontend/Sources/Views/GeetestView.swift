import SwiftUI
import WebKit

struct GeetestView: View {
    let challenge: GeetestChallenge
    let subtitle: String
    let onComplete: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("米游社人机验证")
                        .font(.title2.bold())
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .motionHover()
            }
            .motionEntrance(order: 0)
            GeetestWebView(challenge: challenge) { value, validate in
                onComplete(value, validate)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .motionEntrance(order: 1)
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 520)
    }
}

private struct GeetestWebView: NSViewRepresentable {
    let challenge: GeetestChallenge
    let onComplete: (String, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(
            context.coordinator,
            name: "geetest"
        )
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    private var html: String {
        let gt = javascriptString(challenge.gt)
        let value = javascriptString(challenge.challenge)
        return """
        <html><head><meta name="viewport" content="width=device-width">
        <style>body{background:#1f1b24;display:flex;align-items:center;
        justify-content:center;height:100vh;margin:0}</style></head>
        <body><div id="captcha"></div>
        <script src="https://static.geetest.com/static/js/gt.0.5.2.js"></script>
        <script>
        initGeetest({protocol:"https://",gt:\(gt),challenge:\(value),
        new_captcha:true,product:"bind",api_server:"api.geetest.com"},
        function(c){c.onReady(function(){c.verify();});
        c.onSuccess(function(){window.webkit.messageHandlers.geetest
        .postMessage(c.getValidate());});});
        </script></body></html>
        """
    }

    private func javascriptString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value])
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return String(json.dropFirst().dropLast())
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onComplete: (String, String) -> Void

        init(onComplete: @escaping (String, String) -> Void) {
            self.onComplete = onComplete
        }

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let value = message.body as? [String: Any],
                  let challenge = value["geetest_challenge"] as? String,
                  let validate = value["geetest_validate"] as? String else {
                return
            }
            onComplete(challenge, validate)
        }
    }
}
