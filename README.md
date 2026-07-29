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

  [开始体验](#开始体验) · [看看能做什么](#不只是启动游戏) · [使用前须知](#使用前须知)
</div>

> **使用提醒**
> MHGLauncher 是仍在开发中的非官方第三方项目，与米哈游、HoYoverse 及其关联方无隶属、授权或合作关系。通过兼容层运行游戏存在账号处罚、数据损坏或运行异常等风险，请在使用前阅读[完整说明](#使用前须知)。

## 不只是启动游戏

MHGLauncher 希望让 Mac 玩家少处理配置，多享受游戏。它不只负责打开客户端，也照顾游戏安装、版本维护、账号数据和旅行回顾。

| 畅玩国服 | 管理游戏 |
| --- | --- |
| 通过 Wine 与 DXMT 在 Apple 芯片 Mac 上运行《原神》国服，可选择 MSync、ESync 等性能模式。 | 安装、更新、预下载、暂停续传、完整性校验与修复集中完成，不再手动搬运游戏文件。 |
| **回顾每一次祈愿** | **把旅行数据放在身边** |
| 同步祈愿记录，查看保底进度、五星时间线和历史卡池；支持抽卡 URL 与 UIGF 导入导出。 | 查看实时便笺、角色详情、成就进度与消息提醒，并可选择将祈愿和成就同步到自己的云端。 |

## 为 Mac 而生

### 原生，而不是套一层网页

界面使用 SwiftUI 构建，遵循 macOS 的窗口、侧边栏、键盘操作、通知和辅助功能习惯。启动器、下载任务与游戏状态都在同一个清晰的桌面体验里。

### 不要求安装 CrossOver

MHGLauncher 使用可审计的开源 Wine 与 DXMT 组件，不依赖 CrossOver.app，也不打包闭源 CrossOver 图形界面或应用代码。Wine 在本机从固定源码自主编译；其余运行组件按固定版本下载并进行 SHA-256 校验。

### 你的凭据留在钥匙串

账号 Cookie、刷新令牌等敏感信息保存在 macOS Keychain，不写入 SQLite、UserDefaults 或日志。本地服务只通过权限为 `0600` 的 Unix Domain Socket 与应用通信。

### 云同步由你决定

不使用云同步也能运行启动器和本地数据功能。需要跨设备保存祈愿与成就时，可以连接项目提供的服务，或部署自己的云端。

## 开始体验

> 当前处于开发预览阶段，暂未提供可直接安装的正式版 App。以下方式会从源码完成测试、构建并启动 MHGLauncher。

### 你需要

- Apple 芯片 Mac（M 系列）
- macOS 26 或更高版本
- Xcode 26，包含 macOS 26 SDK
- Git 与可用的网络连接

无需单独安装 Node.js、npm、Wine 或 DXMT；项目脚本会下载、校验并从源码构建所需版本。

### 一条命令构建并运行

```bash
git clone https://github.com/HappyDIY/MHGLauncher.git
cd MHGLauncher
./release-app.command

# 跳过所有测试直接构建并启动
./release-app.command --skip-tests
```

脚本会根据代码变化运行必要测试，随后构建并打开应用。首次构建会在当前用户
钥匙串中创建并信任一个仅供本机开发使用的自签名身份，后续构建复用该身份，
避免应用更新后反复请求钥匙串凭据访问权限。关闭应用后，成品会保留在：

```text
dist/MHGLauncher.app
```

### 第一次使用

1. 阅读并确认应用内的风险说明。
2. 使用米游社扫码、短信或 Cookie 登录。
3. 让启动器定位已有游戏，或直接安装国服客户端。
4. 按引导安装经过校验的游戏运行组件。
5. 选择性能模式，开始游戏。

## 你还能看到

- **主页：** 游戏版本、运行状态、实时便笺与祈愿概览
- **游戏：** 安装更新、预下载、修复、任务进度和启动设置
- **祈愿记录：** 卡池统计、保底分析、五星时间线与 UIGF 工具
- **历史卡池：** 回看角色与武器活动祈愿
- **实时便笺：** 树脂、洞天宝钱、探索派遣等状态
- **我的角色：** 等级、命座、武器、圣遗物与详细属性
- **成就管理：** 搜索、筛选并维护成就完成进度
- **消息提醒：** 关注游戏资源恢复和版本动态
- **云同步：** 备份或恢复祈愿与成就数据
- **账号：** 登录米游社并管理当前游戏身份

## 使用前须知

| 项目 | 当前情况 |
| --- | --- |
| 支持平台 | 仅 Apple 芯片 Mac 与 macOS 26+ |
| 游戏区域 | 仅《原神》国服 |
| 项目状态 | 开发预览，功能和数据格式仍可能变化 |
| 应用分发 | 本机构建使用本地自签名身份；暂无公证或 DMG 正式发行包 |
| 游戏运行 | 基于兼容层，无法承诺与原生 Windows 环境完全一致 |
| 账号风险 | 第三方工具可能违反游戏服务条款，请自行判断并承担风险 |

建议在操作游戏资源前备份重要文件。启动器会尽力恢复启动期间临时修改的配置与兼容文件，但无法对适用性、稳定性、安全性或使用后果作出保证。

## 常见问题

<details>
  <summary><strong>需要购买或安装 CrossOver 吗？</strong></summary>
  <br />
  不需要。MHGLauncher 使用开源 Wine 与 DXMT 运行组件，不依赖 CrossOver.app。
</details>

<details>
  <summary><strong>已有游戏文件还要重新下载吗？</strong></summary>
  <br />
  不一定。可以先让启动器检测已有游戏目录，再根据校验结果补全或修复文件。
</details>

<details>
  <summary><strong>账号凭据会上传吗？</strong></summary>
  <br />
  敏感凭据保存在 macOS Keychain。云同步只处理相应的玩家数据，且属于可选功能。
</details>

<details>
  <summary><strong>支持国际服或其他游戏吗？</strong></summary>
  <br />
  当前只面向《原神》国服，不在文档范围内的游戏或服务器暂不支持。
</details>

<details>
  <summary><strong>为什么目前需要从源码构建？</strong></summary>
  <br />
  项目尚处于开发预览阶段，签名、公证和 DMG 发行不在当前范围内。从源码构建可以确保应用与本地后端来自同一版本。
</details>

<details>
  <summary><strong>我是开发者，如何了解架构和测试？</strong></summary>
  <br />

  MHGLauncher 由原生前端、本地后端、可选云端与管理后台组成：

  ```mermaid
  flowchart LR
      A["SwiftUI macOS App"]
      B["本地后端<br/>Next.js + SQLite"]
      C["云同步<br/>Next.js + PostgreSQL"]
      D["管理后台<br/>Next.js"]
      E["米哈游 / HoYoLAB API"]

      A <-->|"Bearer Token<br/>Unix Domain Socket"| B
      B <-->|"HTTPS"| C
      B <-->|"Provider 抽象"| E
      D <-->|"Service Token"| C
  ```

  | 目录 | 用途 |
  | --- | --- |
  | `frontend/` | SwiftUI macOS 应用 |
  | `backend/` | 本地 API、游戏与玩家数据服务 |
  | `cloud/` | 可选的远程同步 API |
  | `admin/` | 云服务管理后台 |
  | `scripts/` | 构建、测试与发布工具 |

  完整门禁使用 `scripts/test-all.sh`，自动化改动提交前使用 `scripts/test-ai.sh`。开发规范与更多命令见 [`AGENTS.md`](AGENTS.md)。
</details>

## 参与项目

发现问题或有新的想法，欢迎提交 [Issue][issues-url]。代码贡献请从 `main` 创建分支，使用简体中文 Conventional Commits，并在提交前确保 `scripts/test-ai.sh` 返回 `passed`。

实现细节不明确时，项目优先参考 [Snap.Hutao.Remastered][hutao-url]，并在平台差异允许的情况下保持行为一致。

## 许可证与致谢

仓库当前尚未提供根级开源许可证。在许可证明确前，请勿将源码视为已获得复制、修改或再分发授权。第三方组件遵循各自许可证，详情见 [`packaging/GAME_RUNTIME_NOTICES.md`](packaging/GAME_RUNTIME_NOTICES.md)。

感谢 [Snap.Hutao.Remastered][hutao-url] 提供业务逻辑参考，感谢 [Best README Template][template-url] 提供文档结构启发，也感谢 [Wine][wine-url]、[DXMT][dxmt-url] 与 [HDiffPatch][hdiff-url] 等开源项目。

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
[template-url]: https://github.com/othneildrew/Best-README-Template
[wine-url]: https://gitlab.winehq.org/wine/wine
[dxmt-url]: https://github.com/3Shain/dxmt
[hdiff-url]: https://github.com/sisong/HDiffPatch
