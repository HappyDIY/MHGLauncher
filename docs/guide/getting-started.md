# 构建与运行

MHGLauncher 目前处于开发预览阶段，暂未提供经过公证的 DMG 或可直接安装的正式发行包。当前体验方式是从源码构建 macOS App。

## 运行条件

| 项目 | 要求 |
| --- | --- |
| Mac | Apple 芯片（M 系列） |
| 系统 | macOS 26 或更高版本 |
| 开发工具 | Xcode 26，包含 macOS 26 SDK |
| 其他 | Git、可用的网络连接 |

项目脚本会获取固定版本的 Node.js 工具链。Wine、DXMT 和其他游戏运行组件不会打进 App，而是在首次需要时安装到应用管理的 Application Support 目录。

## 获取源码

```bash
git clone https://github.com/HappyDIY/MHGLauncher.git
cd MHGLauncher
```

::: warning 当前签名限制
发布构建必须使用 `packaging/CodeSigning.plist` 中指定的项目统一证书及其私钥。证书未安装、指纹不一致或签名校验失败时，构建会终止，不会自动降级为临时签名。未获授权的普通用户当前可能无法完成发布构建。
:::

## 构建并启动

```bash
./release-app.command
```

脚本会比较源码与上一次成功构建，按需运行测试、构建本地后端和 SwiftUI 前端、组装 App、完成签名，然后启动应用。关闭应用后，固定入口保留在：

```text
dist/MHGLauncher.app
```

需要明确跳过测试时可以运行：

```bash
./release-app.command --skip-tests
```

`--skip-tests` 只影响测试，不绕过构建、签名或产物校验。

## 第一次打开前

1. 备份已有游戏目录中的重要文件。
2. 确认磁盘空间足以容纳游戏本体、下载暂存文件和运行组件。
3. 准备可用的米游社账号，但不要把 Cookie 或验证码写进终端命令、Issue 或日志。
4. 阅读[隐私与风险](./security)后再确认应用内提示。

接下来前往[首次启动与账号](./first-launch)完成登录和游戏身份选择。

## 本地预览这套文档

文档站与其他组件一样独立管理依赖：

```bash
cd docs
npm ci
npm run dev
```

生产构建和本地预览使用：

```bash
npm run build
npm run preview
```
