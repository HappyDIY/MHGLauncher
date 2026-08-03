# MHGLauncher

MHGLauncher 是面向 macOS 26（Apple Silicon）的原神国服启动器。项目采用纯 Swift 单进程架构：SwiftUI 界面通过类型化 `LauncherClient` 调用同一可执行文件内的领域服务，不再包含本地 HTTP、Unix Socket、Node.js 或 Next.js。

## 架构

```text
SwiftUI / LauncherStore
        -> LauncherClient / LauncherCoreHost
        -> Swift Domain Services / Providers / GRDB
        -> SQLite / Keychain / URLSession / Wine / hpatchz
```

- `frontend/Sources/Core`：账号、玩家资料、祈愿、成就、资源、云同步、游戏安装与启动服务。
- `frontend/Sources/State`、`frontend/Sources/Views`：SwiftUI 状态与界面。
- `frontend/Vendor`：固定版本的 xxHash 与 zstd C 源码。
- `scripts`：Swift 构建、测试、运行时资产和发布脚本。
- `../MHGLauncher-Cloud`：可选的远端同步服务，始终通过 HTTPS 访问。

账号凭据和云令牌仅保存在 macOS 钥匙串中。数据库沿用 `~/Library/Application Support/MHGLauncher/mhglauncher.db`；Swift 首次接管现有数据库前会生成权限为 `0600` 的 `.pre-swift.bak`。

## 开发

```bash
cd frontend
swift build
swift test

# 完整质量门禁
scripts/test-all.sh

# 构建并启动 App
./release-app.command
```

运行时清单使用 schema v3。Core 组件仅包含 `tools/hpatchz`；Wine、DXMT、msync、host 与 `mhypbase` 属于 game 组件，安装到 Application Support 下，不打包进 App。

## 依赖

- GRDB 7.10.0
- SwiftProtobuf 1.38.1
- swift-libgit2 1.0.1（串行 `CLibgit2` 封装）
- xxHash 0.8.3
- zstd 1.5.7
- Wine 11.0 与 DXMT（由固定源码构建）
- HDiffPatch / hpatchz 4.12.2

版本、许可证和源码摘要记录在 SwiftPM、`frontend/Vendor` 与 `packaging` 中。
