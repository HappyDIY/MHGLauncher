# 运行时与打包

最终 App 包含 SwiftUI 可执行文件、本地 Node.js 后端和后端生产依赖。游戏运行组件不嵌入 App，而是通过带校验的运行时清单安装。

## App 组装

```bash
scripts/build-app.sh
```

构建流程：

1. 使用固定 Node.js 工具链构建后端。
2. 以 release/arm64 构建 SwiftUI 前端。
3. 写入配置后的 `Info.plist`。
4. 组装 `dist/MHGLauncher.app`。
5. 编译原生 Icon Composer 图标。
6. 使用项目统一证书签名并完成深度校验。

最终用户不应需要单独安装 Node.js 或 npm。

## 核心运行资源

运行时清单区分启动器核心资源与游戏运行资源：

| 组件 | 用途 |
| --- | --- |
| Node.js | 运行本地后端 |
| backend `node_modules` | 后端生产依赖 |
| `hpatchz` | 应用 HDiffPatch 二进制补丁 |
| Wine 11.0 | 运行 Windows 游戏进程 |
| DXMT | DirectX 到 Metal 转换 |
| `mhypbase.dll` | 固定版本的启动兼容组件 |

每个下载二进制都要固定来源、版本、许可证和预期 SHA-256。

## Wine 与 DXMT

`scripts/fetch-game-runtime.sh` 根据固定构建输入准备 Wine 11.0 和 DXMT。Wine 从源码构建，不依赖 CrossOver.app。

对构建脚本、补丁或来源锁的修改必须运行运行时专项测试，并更新第三方通知。不能用未记录的预编译产物替换可审计来源。

## `mhypbase.dll`

这个文件由启动器独立管理：

- 游戏更新忽略它。
- 完整性校验和修复忽略它。
- 普通清理忽略它。
- 检测到修改时恢复固定兼容版本。

不要让游戏清单的普通资源逻辑接管它。

## 启动恢复

游戏启动必须经过类型化 launch session。临时文件、环境和配置变更需要在以下路径全部恢复：

- 游戏正常退出。
- 子进程启动失败。
- 用户取消。
- 启动器收到终止请求。

新启动行为的测试必须覆盖恢复失败，不能只覆盖成功进程。

## 发布边界

当前不包含：

- 公证。
- DMG 制作。
- 正式更新渠道的最终分发流程。
- 签名证书或私钥的仓库存储。

第三方组件记录见 [GAME_RUNTIME_NOTICES.md](https://github.com/HappyDIY/MHGLauncher/blob/main/packaging/GAME_RUNTIME_NOTICES.md)。
