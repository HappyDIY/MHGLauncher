# 测试与质量

测试按组件分层执行。fixture 模式保证登录、游戏资料和祈愿流程在没有真实账号与外部网络时仍可验证。

## 常用命令

### 本地后端

```bash
cd backend
npm run typecheck
npm run lint
npm test
```

### SwiftUI 前端

```bash
cd frontend
swift test
swift test --filter APIClientTests
```

### 云端与后台

```bash
cd cloud && npm test
cd admin && npm test
cd admin && npm run test:e2e
```

cloud 集成测试需要 PostgreSQL。后台 Playwright 测试由显式的 e2e 命令运行。

## 仓库级门禁

```bash
scripts/test-all.sh
```

这是合并前权威门禁，包含 launcher 与 services 两部分。按修改范围也可以运行：

```bash
scripts/test-backend.sh
scripts/test-frontend.sh
scripts/test-features.sh
scripts/check-api-boundary.sh
scripts/check-source-lines.sh
```

AI 或自动化修改提交前必须运行：

```bash
scripts/test-ai.sh
```

脚本运行期间保持静默，结束时只输出一个结构化 JSON。详细日志保存在结果中的 `build/ai-tests/...` 路径。只有 `status` 为 `passed` 才能提交。

## Fixture 约束

每个新增的网络 Provider 行为都要提供确定性 fixture：

- 不访问真实米游社或 HoYoLAB 服务。
- 不包含真实 UID、Cookie 或令牌。
- 成功、失败和边界输入可重复。
- `test-features.sh` 可以通过真实 Unix Socket 触发核心流程。

## 测试策略

仓库门禁禁止提交被 `skip`、`only`、`todo` 或 disabled 的测试。修复不稳定测试时，应消除时间、网络或共享状态依赖，而不是绕过测试。

测试覆盖范围与风险匹配：

- 单文件纯函数改动使用聚焦单元测试。
- 共享服务或持久化改动补充集成测试。
- 跨 Swift/TypeScript 契约改动同时验证两端。
- 游戏启动和临时文件改动覆盖失败、取消与恢复。

## 文档验证

文档未接入仓库质量门禁，修改后需要在 `docs/` 手工执行：

```bash
npm ci
npm run build
```

构建必须没有死链、Markdown 解析错误或 SSR 异常。
