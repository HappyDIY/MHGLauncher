# 参与贡献

贡献应保持产品范围、平台安全边界和参考实现兼容性。不要因为实现方便而绕过本地 Socket、Provider 或运行时恢复机制。

## 开始前

1. 从 `main` 创建分支。
2. 阅读根目录 `AGENTS.md` 和 `CLAUDE.md`。
3. 查找当前组件的现有模式。
4. 业务行为不明确时检查 Snap.Hutao.Remastered。
5. 明确修改是否跨越 Swift/TypeScript API 边界。

## 实现原则

- 保持改动范围与请求一致。
- 优先使用现有依赖注入和小模块。
- 新网络行为必须进入 Provider。
- 新服务必须由 Container 组装。
- 新用户文案和错误信息使用简体中文。
- 不记录、持久化或提交敏感信息。
- 不超过手写 Swift/TypeScript 1000 行限制。

## API 与持久化修改

修改共享模型、任务 payload、API 字段或持久化形状时：

1. 同步更新 TypeScript 和 Swift 类型。
2. 更新契约语料。
3. 验证可选性、enum 和 JSON 字段名。
4. 运行 `scripts/check-api-boundary.sh`。
5. 为迁移和旧数据提供兼容测试。

## 提交前

先运行与修改范围对应的组件测试，再执行：

```bash
scripts/test-ai.sh
```

确认 JSON 中 `status` 为 `passed`。提交使用简体中文 Conventional Commits，例如：

```text
feat(backend): 实现游戏资源下载服务
fix(frontend): 修复账号切换状态
docs: 完善云服务部署说明
```

## 文档贡献

文档以当前代码为事实来源。新增页面时：

- 把页面加入对应侧边栏。
- 使用相对链接连接文档内部页面。
- 不复制真实凭据、UID 或生产地址。
- 不使用未经授权的游戏截图和素材。
- 在 `docs/` 运行 `npm run build`。

发现问题或提出需求请使用 [GitHub Issues](https://github.com/HappyDIY/MHGLauncher/issues)。
