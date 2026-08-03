<a id="readme-top"></a>

<div align="center">
  <img
    src="frontend/Sources/Resources/AppIcon.icon-source/rendered/default.png"
    alt="MHGLauncher"
    width="136"
    height="136"
  />

  <h1>MHGLauncher</h1>
  <h3>在 Mac 上，轻松开启提瓦特</h3>

  <p>
    专为 Apple 芯片打造的《原神》国服非官方启动器。<br />
    从下载安装、更新修复到祈愿记录与角色数据，把旅途需要的一切放进一个原生 Mac 应用。
  </p>

  [![macOS 26+][macos-shield]][macos-url]
  [![Apple Silicon][silicon-shield]][silicon-url]
  [![开发预览][preview-shield]][project-url]
  [![质量门禁][quality-shield]][quality-url]

  [开始使用](https://github.com/HappyDIY/MHGLauncher-Docs/blob/main/guide/getting-started.md) ·
  [用户手册](https://github.com/HappyDIY/MHGLauncher-Docs/blob/main/guide/first-launch.md) ·
  [开发指南](https://github.com/HappyDIY/MHGLauncher-Docs/blob/main/development/architecture.md) ·
  [部署运维](https://github.com/HappyDIY/MHGLauncher-Docs/blob/main/operations/self-hosting.md)
</div>

> [!WARNING]
> MHGLauncher 是仍在开发中的非官方第三方项目，与米哈游、HoYoverse 及其关联方无隶属、授权或合作关系。通过兼容层运行游戏存在账号处罚、数据损坏或运行异常等风险，请在使用前阅读[隐私与风险](https://github.com/HappyDIY/MHGLauncher-Docs/blob/main/guide/security.md)。

## 能做什么

| 游戏体验 | 旅行数据 |
| --- | --- |
| 通过开源 Wine 与 DXMT 在 Apple 芯片 Mac 上运行《原神》国服，并提供 MSync、ESync 等性能模式。 | 同步祈愿记录，查看保底、五星时间线和历史卡池，支持抽卡 URL 与 UIGF 导入导出。 |
| 定位或安装游戏，完成更新、预下载、暂停续传、完整性校验和修复。 | 查看实时便笺、角色、成就和消息提醒，并按需将祈愿与成就同步到自己的云端。 |

SwiftUI 前端遵循 macOS 的窗口、侧边栏、键盘、通知和辅助功能习惯。账号 Cookie、刷新令牌等敏感信息保存在 macOS Keychain；本地后端只通过权限为 `0600` 的 Unix Domain Socket 与 App 通信。

## 构建要求

- Apple 芯片 Mac（M 系列）
- macOS 26 或更高版本
- Xcode 26，包含 macOS 26 SDK
- Git 与可用的网络连接

当前没有经过公证的 DMG 或可直接安装的正式发行包。源码构建使用：

```bash
git clone https://github.com/HappyDIY/MHGLauncher.git
cd MHGLauncher
./release-app.command
```

发布构建必须使用 `packaging/CodeSigning.plist` 中指定的项目统一证书及其私钥。证书缺失或指纹不一致时构建会终止，不会自动改用临时签名。完整流程见[构建与运行](https://github.com/HappyDIY/MHGLauncher-Docs/blob/main/guide/getting-started.md)。

## 官方文档

文档源码位于独立的 [MHGLauncher-Docs](https://github.com/HappyDIY/MHGLauncher-Docs) 项目，可直接在 GitHub 阅读：

| 文档 | 内容 |
| --- | --- |
| [用户手册](https://github.com/HappyDIY/MHGLauncher-Docs/blob/main/guide/getting-started.md) | 构建、首次启动、游戏管理、旅行数据、云同步与故障排查 |
| [开发者指南](https://github.com/HappyDIY/MHGLauncher-Docs/blob/main/development/architecture.md) | 启动器架构、本地开发、API 边界、测试和运行时打包 |
| [自托管云服务](https://github.com/HappyDIY/MHGLauncher-Docs/blob/main/operations/self-hosting.md) | PostgreSQL、cloud、admin、密钥、健康检查与备份 |
| [常见问题](https://github.com/HappyDIY/MHGLauncher-Docs/blob/main/reference/faq.md) | 平台范围、账号、兼容层和数据同步 |

本地启动文档站：

```bash
git clone https://github.com/HappyDIY/MHGLauncher-Docs.git ../MHGLauncher-Docs
cd ../MHGLauncher-Docs
npm ci
npm run dev
```

文档生产构建使用 `npm run build`，本地检查构建结果使用 `npm run preview`。

## 项目结构

| 目录 | 用途 |
| --- | --- |
| `frontend/` | Swift 6.2 / SwiftUI macOS App |
| `backend/` | 本地 Next.js API、SQLite、游戏与玩家数据服务 |
| `contracts/` | 本地 API 契约语料与边界检查输入 |
| `scripts/` | 构建、测试、运行时和发布工具 |
| [MHGLauncher-Cloud](https://github.com/HappyDIY/MHGLauncher-Cloud) | 可选的 Next.js / PostgreSQL 云同步服务与管理后台 |
| [MHGLauncher-Docs](https://github.com/HappyDIY/MHGLauncher-Docs) | 用户手册、开发指南和部署运维文档 |

架构、通信边界和 Provider 约定见[系统架构](https://github.com/HappyDIY/MHGLauncher-Docs/blob/main/development/architecture.md)。

## 支持范围

| 项目 | 当前情况 |
| --- | --- |
| 支持平台 | 仅 Apple 芯片 Mac 与 macOS 26+ |
| 游戏区域 | 仅《原神》国服 |
| 项目状态 | 开发预览，功能和数据格式仍可能变化 |
| 应用分发 | 使用固定项目证书；暂无公证或 DMG 正式发行包 |
| 云同步 | 可选，本地功能可独立使用 |

## 参与项目

发现问题或有新的想法，欢迎提交 [Issue][issues-url]。代码贡献请从 `main` 创建分支，使用简体中文 Conventional Commits，并在提交前确保 `scripts/test-ai.sh` 返回 `passed`。

实现细节不明确时，优先参考 [Snap.Hutao.Remastered][hutao-url]，并在平台差异允许的情况下保持行为兼容。详细要求见[参与贡献](https://github.com/HappyDIY/MHGLauncher-Docs/blob/main/development/contributing.md)。

## 许可证与致谢

仓库当前尚未提供根级开源许可证。在许可证明确前，请勿将源码视为已获得复制、修改或再分发授权。第三方组件遵循各自许可证，详情见 [`packaging/GAME_RUNTIME_NOTICES.md`](packaging/GAME_RUNTIME_NOTICES.md)。

感谢 [Snap.Hutao.Remastered][hutao-url] 提供业务逻辑参考，感谢 [Wine][wine-url]、[DXMT][dxmt-url] 与 [HDiffPatch][hdiff-url] 等开源项目。

<p align="center">
  <a href="#readme-top">返回顶部</a>
</p>

[project-url]: https://github.com/HappyDIY/MHGLauncher
[issues-url]: https://github.com/HappyDIY/MHGLauncher/issues
[quality-shield]: https://img.shields.io/github/actions/workflow/status/HappyDIY/MHGLauncher/quality-gate.yml?branch=main&style=for-the-badge&label=%E8%B4%A8%E9%87%8F%E9%97%A8%E7%A6%81
[quality-url]: https://github.com/HappyDIY/MHGLauncher/actions/workflows/quality-gate.yml
[macos-shield]: https://img.shields.io/badge/macOS-26%2B-000000?style=for-the-badge&logo=apple
[macos-url]: https://www.apple.com/macos/
[silicon-shield]: https://img.shields.io/badge/Apple_Silicon-arm64-555555?style=for-the-badge&logo=apple
[silicon-url]: https://support.apple.com/zh-cn/116943
[preview-shield]: https://img.shields.io/badge/%E7%8A%B6%E6%80%81-%E5%BC%80%E5%8F%91%E9%A2%84%E8%A7%88-E85D75?style=for-the-badge
[hutao-url]: https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered
[wine-url]: https://gitlab.winehq.org/wine/wine
[dxmt-url]: https://github.com/3Shain/dxmt
[hdiff-url]: https://github.com/sisong/HDiffPatch
