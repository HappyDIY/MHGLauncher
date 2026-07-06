import AppKit
import SwiftUI
import Testing
@testable import MHGLauncher

@Suite("交互可用性")
struct InteractiveSurfaceTests {
    @Test("所有主入口可实例化且布局无崩溃")
    @MainActor
    func destinationSurfacesRender() {
        for destination in Destination.allCases {
            let store = fixtureStore()
            store.selectedDestination = destination
            render(AnyView(RootView(store: store)), name: destination.rawValue)
        }
        render(
            AnyView(RuntimeSetupView(store: LauncherStore())),
            name: "运行时准备"
        )
        render(
            AnyView(WishHistoryPanel(records: InteractiveFixtures.wishRecords, selectedGachaType: "301")),
            name: "祈愿历史"
        )
    }

    @Test("交互控件都有可读名称")
    func interactiveControlsHaveReadableNames() throws {
        let controls = try InteractiveSourceScanner.controls()
        #expect(controls.count >= 40)
        let unreadable = controls.filter { !$0.hasReadableName }
        if !unreadable.isEmpty {
            Issue.record(unreadable.map(\.summary).joined(separator: "\n"))
        }
    }

    @Test("编辑型控件提供明确用途")
    func editableControlsExposePurpose() throws {
        let controls = try InteractiveSourceScanner.controls()
        let weakEditors = controls.filter { control in
            control.kind == "TextEditor"
                && !control.snippet.contains(".accessibilityLabel(")
        }
        let weakNumericFields = controls.filter { control in
            control.kind == "TextField"
                && control.snippet.contains(#""0","#)
                && !control.snippet.contains(".accessibilityLabel(")
        }
        if !weakEditors.isEmpty || !weakNumericFields.isEmpty {
            Issue.record((weakEditors + weakNumericFields).map(\.summary).joined(separator: "\n"))
        }
    }

    @MainActor
    private func render(_ view: AnyView, name: String) {
        let host = NSHostingView(
            rootView: view
                .environment(\.accessibilityReduceMotion, true)
                .frame(width: 1100, height: 740)
        )
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 740)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width.isFinite, "布局宽度无效：\(name)")
        #expect(host.fittingSize.height.isFinite, "布局高度无效：\(name)")
    }

    @MainActor
    private func fixtureStore() -> LauncherStore {
        let store = LauncherStore()
        store.backend.useClient(APIClient(token: "fixture") { _ in
            APIResponse(status: 200, body: Data("{}".utf8))
        })
        store.account = InteractiveFixtures.account
        store.accounts = [InteractiveFixtures.account]
        store.roles = [InteractiveFixtures.role]
        store.gameState = InteractiveFixtures.gameState
        store.gameJob = InteractiveFixtures.gameJob
        store.gameLaunch = InteractiveFixtures.gameLaunch
        store.installPath = "/Games/Genshin Impact Game"
        store.gameRuntimeReady = true
        store.companionLoaded = true
        store.dailyNote = InteractiveFixtures.dailyNote
        store.wishes = InteractiveFixtures.wishRecords
        store.wishStatistics = [InteractiveFixtures.wishStatistics]
        store.bannerDetails = [InteractiveFixtures.bannerDetail]
        store.speedLimitKB = 1024
        store.loginMobile = "13800138000"
        store.loginCaptcha = "123456"
        store.loginCookie = "stoken=fixture; mid=mid"
        store.mobileCaptchaSession = MobileCaptchaSession(
            mobile: store.loginMobile,
            actionType: "login",
            countdown: 60,
            aigis: nil,
            verification: nil
        )
        return store
    }
}

private struct InteractiveControl {
    let file: String
    let line: Int
    let kind: String
    let text: String
    let snippet: String

    var hasReadableName: Bool {
        if kind == "TextEditor" { return snippet.contains(".accessibilityLabel(") }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let first = quotedText(in: trimmed), !first.isEmpty { return true }
        if trimmed.contains("\(kind)("), !trimmed.contains("\(kind)()") {
            let value = trimmed.components(separatedBy: "\(kind)(").dropFirst().joined()
            if !value.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
                return !value.trimmingCharacters(in: .whitespaces).hasPrefix("\"\"")
            }
        }
        return snippet.contains("Label(\"")
            || snippet.contains("Text(\"")
            || snippet.contains(".help(\"")
            || snippet.contains(".accessibilityLabel(")
    }

    var summary: String { "\(file):\(line) \(kind) 缺少可读名称" }
}

private enum InteractiveSourceScanner {
    static let kinds = [
        "Button", "Menu", "Picker", "Toggle",
        "TextField", "TextEditor", "DatePicker", "Stepper", "Slider"
    ]

    static func controls() throws -> [InteractiveControl] {
        try sourceURLs().flatMap { url in
            let text = try String(contentsOf: url)
            let lines = text.components(separatedBy: .newlines)
            return lines.enumerated().compactMap { offset, line in
                guard let kind = kinds.first(where: { contains($0, in: line) }) else {
                    return nil
                }
                let end = min(lines.count, offset + 60)
                return InteractiveControl(
                    file: url.lastPathComponent,
                    line: offset + 1,
                    kind: kind,
                    text: line,
                    snippet: lines[offset..<end].joined(separator: "\n")
                )
            }
        }
    }

    private static func contains(_ kind: String, in line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("\(kind)(") || trimmed.hasPrefix("\(kind) {")
    }

    private static func sourceURLs() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources")
        let views = root.appending(path: "Views")
        let viewFiles = try FileManager.default.contentsOfDirectory(
            at: views,
            includingPropertiesForKeys: nil
        )
        return (viewFiles + [root.appending(path: "MHGLauncherApp.swift")])
            .filter { $0.pathExtension == "swift" }
    }
}

private func quotedText(in value: String) -> String? {
    guard let start = value.firstIndex(of: "\"") else { return nil }
    let rest = value[value.index(after: start)...]
    guard let end = rest.firstIndex(of: "\"") else { return nil }
    return String(rest[..<end])
}
