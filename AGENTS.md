# AGENTS.md

## 项目

MHGLauncher 是原神国服 macOS 启动器，使用 Swift 6.2、SwiftUI 与 SwiftPM，目标平台为 macOS 26 arm64。应用采用纯 Swift 单进程架构。可选云服务和文档位于 `../MHGLauncher-Cloud` 与 `../MHGLauncher-Docs`。

Windows 参考实现是 `${HOME}/Documents/ReSearch/Snap.Hutao.Remastered`。业务行为不明确时先核对参考实现，除平台差异外保持兼容。所有用户可见文本和源码注释使用简体中文。

## 架构

- `frontend/Sources/Services/LauncherClient.swift` 定义 UI 可见的类型化领域 Client。
- `frontend/Sources/Core/LauncherCoreHost.swift` 是组合根和生命周期入口。
- `frontend/Sources/Core/Persistence` 使用 GRDB；`Core/Providers` 负责所有米哈游、HoYoLAB、Sophon、Snap.Metadata 与云端网络访问；`Core/Services` 和 `Core/Game` 实现业务。
- UI 不得感知路由、JSON、Socket、凭据或云令牌。Core 根据数据库中的 `credential_ref` 从 Keychain 读取秘密。
- 游戏任务、启动会话和祈愿任务使用 `AsyncThrowingStream`。
- 内部图片使用 `mhg-resource://`，只能由 `ImageClient` 安全解析。

禁止引入本地 HTTP、Unix Socket、Bearer Token、Node.js、Next.js、npm 或 JavaScript/TypeScript。远端服务仅通过受限制的 HTTPS `URLSession` 访问。

## 安全

- 凭据、Cookie、刷新令牌和云令牌只存 Keychain，绝不写入 SQLite、UserDefaults、日志、诊断、fixture 或测试输出。
- 启动时设置私有 umask；托管目录为 `0700`，数据库、索引、状态与诊断文件为 `0600`。
- 所有文件操作拒绝符号链接与路径逃逸。游戏失败、取消或退出后恢复临时修改。
- `mhypbase.dll` 由启动器管理，安装、更新、修复、校验和清理均忽略它；发现不一致时恢复固定兼容版本。
- Provider 网络层必须限制 HTTPS 主机、重定向、响应大小、超时和日志内容，并支持完全离线 fixture 测试。

## 数据与依赖

- 数据库路径保持 `~/Library/Application Support/MHGLauncher/mhglauncher.db`，兼容 v1-v8，当前 schema 为 v9。首次 Swift 写入前 WAL checkpoint 并创建 `0600` 的 `mhglauncher.db.pre-swift.bak`。
- 固定依赖：GRDB 7.10.0、SwiftProtobuf 1.38.1、swift-libgit2 1.0.1、xxHash 0.8.3、zstd 1.5.7。Sophon `.proto` 与生成的 `.pb.swift` 一并提交。
- 运行时清单为 schema v3：Core 仅含 `tools/hpatchz`；Wine、DXMT、msync、host、`mhypbase` 属于 game 组件。
- 下载的第三方二进制必须固定来源、版本、许可证和 SHA-256。不得依赖 CrossOver 专有代码。

## 代码规范

- 启用 Swift 6 严格并发。手写 Swift 文件不超过 1000 行。
- 使用 actor 隔离数据库、元数据、缓存、任务、启动会话、Git 与进程状态。
- 优先小型领域模块和依赖注入；测试使用内存 Keychain、临时目录、`URLProtocol` 或协议化传输及伪 `Process`。
- 使用共享 `LauncherMotion`，尊重 `accessibilityReduceMotion`，保留原生 macOS 控件行为。

## 命令

除非用户主动明确要求，否则一律不得运行任何测试或构建命令。不得因为修改完成、提交前检查或常规验证而自行运行测试、构建、打包或冒烟检查。

```bash
cd frontend
swift build -c release --arch arm64
swift test

scripts/test-frontend.sh
scripts/test-features.sh
scripts/test-all.sh
scripts/test-ai.sh
scripts/build-app.sh
scripts/smoke-app.sh
```

`scripts/test-all.sh` 是合并前权威门禁；仅在用户主动要求运行测试时使用。用户主动要求运行 `scripts/test-ai.sh` 时，其唯一 JSON 输出的 `status` 必须是 `passed`。Swift 与 C 源文件仍受 `scripts/check-source-lines.sh` 的 1000 行限制。

## Git

完成会修改文件的连贯工作后创建提交。使用 Conventional Commits，主题为简体中文。不得覆盖或丢弃无关用户变更。
