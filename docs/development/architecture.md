# 系统架构

MHGLauncher 是四个独立构建组件组成的 monorepo。macOS App 和本地后端构成启动器主体；云同步与管理后台都是可选服务。

<figure class="architecture-flow" aria-label="MHGLauncher 四组件数据流">
  <div class="flow-node">
    <strong>SwiftUI 前端</strong>
    <span>macOS 26 · arm64</span>
  </div>
  <div class="flow-arrow" aria-hidden="true">↔</div>
  <div class="flow-node">
    <strong>本地后端</strong>
    <span>Unix Socket · Next.js · SQLite</span>
  </div>
  <div class="flow-arrow" aria-hidden="true">↔</div>
  <div class="flow-node">
    <strong>可选云端</strong>
    <span>HTTPS · Next.js · PostgreSQL</span>
  </div>
</figure>

管理后台不直接操作云端业务数据，而是携带服务令牌调用云端 `/api/admin/v1` 边界。米哈游与 HoYoLAB 网络访问统一位于本地后端的 Provider 抽象之后。

## 组件职责

| 目录 | 职责 |
| --- | --- |
| `frontend/` | Swift 6.2 / SwiftUI 原生 App、状态管理、Keychain、后端进程生命周期 |
| `backend/` | 本地 API、SQLite、登录、游戏安装与启动、旅行数据、Provider |
| `cloud/` | UID 维度的祈愿和成就同步、发布与管理 API |
| `admin/` | 操作员登录、发布、用户、安全和审计界面 |
| `scripts/` | 工具链获取、测试、运行时构建、App 组装和冒烟测试 |

每个组件维护自己的依赖和构建命令。不要在根目录增加统一 Node 工作区来耦合它们。

## 前端

前端使用 SwiftUI，并在 `@Observable` Store 中维护状态。`LauncherStore` 负责应用级业务状态，`ValueStore` 负责相关值模型；页面拆成小型 View 文件。

`BackendProcess` 启动 App 内置的 Node.js 后端，传入：

- 每次运行随机生成的 API Token。
- 每次运行独立的 Socket 路径。
- 当前前端进程 PID。
- Application Support 数据目录。
- 已安装运行组件的路径。

后端输出 ready 事件后，`APIClient` 才通过 `UnixSocketTransport` 发起请求。

## 本地后端

本地后端是业务核心。Next.js 仅提供 route handler，由自定义 `server.ts` 监听 Unix Socket，不监听 TCP。

依赖注入集中在惰性 `Container` 中。新增服务时：

1. 为服务定义明确构造依赖。
2. 在 Container 中完成组装。
3. 通过手写路由调用服务。
4. 为 live Provider 行为提供 fixture 对应实现。

路由由 `router.ts` 和 `value-routes.ts` 手工匹配 method 与 path，并使用 Zod 校验请求体。

## Provider

`Provider` 隔离米哈游和 HoYoLAB 网络访问，包括扫码、手机验证码、账号资料、游戏构建、祈愿与实时便笺。

- `LiveProvider` 访问真实网络。
- `FixtureProvider` 从 `backend/fixtures/` 返回确定性数据。

测试、功能矩阵和冒烟脚本使用 fixture 模式。不要让单元测试依赖真实账号或外部接口。

## 云端与后台

云端使用 PostgreSQL 保存玩家同步数据，并验证管理服务令牌。后台有独立的管理数据库 schema，用于站长账号、会话、TOTP、恢复码和审计。

后台对云端数据的管理动作必须通过内部 HTTP API 完成，不能为了方便而直接查询或修改云端业务表。

## 参考实现

业务细节不明确时，优先检查本机 `${HOME}/Documents/Snap.Hutao.Remastered` 中对应的 Windows 实现。在平台差异允许的前提下保持行为兼容，不要凭空引入新产品行为。
