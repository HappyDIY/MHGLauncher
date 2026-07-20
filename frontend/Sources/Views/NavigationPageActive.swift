import SwiftUI

// 标记当前视图所在的导航页是否为激活页。被缓存但不可见的页面（opacity 0）
// 仍位于视图树内，默认会随后台轮询持续重绘；下游高频组件读取此值即可在
// 页面不可见时暂停渲染与计时器，且不影响数据采集。默认 true，使宿主之外
// （表单、覆盖层等）的视图保持常规行为。
private struct NavigationPageActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var navigationPageActive: Bool {
        get { self[NavigationPageActiveKey.self] }
        set { self[NavigationPageActiveKey.self] = newValue }
    }
}
