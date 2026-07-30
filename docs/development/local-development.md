# 本地开发

四个组件独立管理构建与依赖。修改前先确认工作目录，避免在错误组件中生成锁文件。

## 工具链

- Swift 6.2、Xcode 26、macOS 26 SDK。
- Node.js 24.17.x；项目脚本会通过 `scripts/fetch-node.sh` 获取固定版本。
- npm 与各 Node 组件自己的 `package-lock.json`。
- PostgreSQL 18，用于 cloud 与 admin 集成开发。
- Docker 与 Docker Compose，用于完整服务环境。

## 本地后端

```bash
cd backend
npm ci
npm run dev
```

直接运行后端时必须提供非空 `MHG_API_TOKEN`。测试和手工验证还应使用独立临时目录与 Socket：

```bash
MHG_API_TOKEN=local-development-token \
MHG_SOCKET_PATH=/tmp/mhglauncher-dev.sock \
MHG_DATA_DIR=/tmp/mhglauncher-dev-data \
MHG_PROVIDER_MODE=fixture \
MHG_FIXTURE_DIR="$PWD/fixtures" \
npm run dev
```

示例令牌只用于本机临时开发。真实运行由前端随机生成令牌，不应固定或提交它。

## SwiftUI 前端

```bash
cd frontend
swift build -c release --arch arm64
swift test
```

日常调试通常通过仓库根目录的 `release-app.command` 运行完整 App，因为前端需要打包后的后端与运行组件清单。

## 云端

```bash
cd cloud
npm ci
npm run dev
```

云端必须配置 `DATABASE_URL`。需要连同 PostgreSQL 与后台一起运行时，优先使用根目录：

```bash
docker compose up --build
```

默认端口映射只绑定 `127.0.0.1`。

## 管理后台

```bash
cd admin
npm ci
npm run dev
```

后台默认监听 3400，需要 `ADMIN_DATABASE_URL`、`MHG_CLOUD_INTERNAL_URL`、服务令牌、加密密钥和正确的 `MHG_ADMIN_ORIGIN`。

## 文档

```bash
cd docs
npm ci
npm run dev
```

文档只依赖 VitePress，不加入现有应用质量门禁。提交前仍应至少运行 `npm run build` 验证链接和服务端渲染。

## 编码边界

- Swift 使用严格并发，TypeScript 使用 strict mode。
- 手写 Swift 和 TypeScript 文件不超过 200 行。
- 源码注释与用户可见文本使用简体中文。
- 结构化数据使用解析器和类型模型，不用字符串拼接模拟协议。
- 不记录 Cookie、令牌或其他敏感值。
