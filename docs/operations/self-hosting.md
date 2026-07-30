# 自托管云服务

自托管环境包含 PostgreSQL、cloud 和 admin 三个服务。云端保存玩家同步数据，管理后台通过内部 API 管理发布、用户、安全和审计。

## 准备环境

需要：

- Docker 与 Docker Compose。
- 可持久化的 PostgreSQL volume。
- 分别用于 cloud 和 admin 的 HTTPS 域名或反向代理路径。
- 备份位置与恢复演练流程。

复制示例配置：

```bash
cp .env.example .env
```

## 生产密钥

`.env` 至少配置：

```dotenv
MHG_CLOUD_BASE_URL=https://cloud.example.com
MHG_ADMIN_SERVICE_TOKEN=replace-with-a-long-random-token
MHG_ADMIN_AUDIT_KEY=replace-with-an-independent-random-key
MHG_ADMIN_ENCRYPTION_KEY=replace-with-64-hex-characters
MHG_ADMIN_ORIGIN=https://admin.example.com
```

可以用以下命令分别生成随机值：

```bash
openssl rand -hex 32
```

要求：

- cloud 与 admin 使用相同的 `MHG_ADMIN_SERVICE_TOKEN`。
- `MHG_ADMIN_AUDIT_KEY` 与服务令牌相互独立。
- `MHG_ADMIN_ENCRYPTION_KEY` 是 64 个十六进制字符。
- `MHG_ADMIN_ORIGIN` 与浏览器访问后台的 HTTPS Origin 完全一致。
- `.env` 不提交到 Git。

## 启动

```bash
docker compose up -d --build
docker compose ps
```

默认端口映射为：

| 服务 | 地址 |
| --- | --- |
| PostgreSQL | `127.0.0.1:54329` |
| cloud | `127.0.0.1:3333` |
| admin | `127.0.0.1:3400` |

这些默认值只绑定回环地址。生产环境应通过反向代理发布 cloud 与 admin，并在代理层启用 HTTPS；不要把数据库直接暴露到公网。

## 数据库与站长账号

PostgreSQL 初始化脚本会创建独立的管理角色。服务启动后执行管理数据库迁移：

```bash
docker compose exec admin npm run migrate
```

首次创建站长账号：

```bash
docker compose exec admin npm run owner:create
```

命令会要求：

- 有效邮箱。
- 至少 12 位的密码。
- 将 TOTP URI 添加到验证器。
- 输入当前 6 位验证码。

最后生成 10 个一次性恢复码。恢复码只显示一次，应立即保存到独立的安全位置。

需要重置已有站长时显式运行：

```bash
docker compose exec admin npm run owner:create -- --reset
```

## 健康检查

```bash
curl --fail http://127.0.0.1:3333/health
curl --fail http://127.0.0.1:3400/health
```

正常响应为：

```json
{"ok":true}
```

`503` 表示服务无法完成数据库健康检查。检查容器状态、连接字符串、PostgreSQL 日志和 volume 权限。

## 发布信息

cloud 可以从环境变量提供当前更新信息：

```dotenv
MHG_UPDATE_VERSION=
MHG_UPDATE_DOWNLOAD_URL=
MHG_UPDATE_SHA256=
MHG_UPDATE_SIZE=
MHG_UPDATE_CHANGELOG=
```

发布下载地址必须使用可信 HTTPS，SHA-256 和文件大小应与最终产物完全一致。不要在构建尚未固定时提前发布元数据。

## 备份

停止写入或选择业务低峰后创建 PostgreSQL 自定义格式备份：

```bash
docker compose exec -T db \
  pg_dump -U mhglauncher -d mhglauncher --format=custom \
  > mhglauncher.dump
```

备份应加密、限制访问并复制到独立存储。定期在隔离环境验证恢复，而不是只确认备份文件存在。

执行 `docker compose down` 不会删除命名 volume；不要在没有可用备份时添加 `-v`。

## 升级

1. 备份数据库和 `.env`。
2. 阅读目标提交中的数据与环境变量变更。
3. 先在隔离环境构建并运行健康检查。
4. 更新镜像并执行必要迁移。
5. 验证 cloud、admin、登录、同步和审计。
6. 确认旧版本回滚不会读取不兼容数据。

不要通过复用开发默认密码、关闭 Origin 校验或在公网开放数据库来缩短升级过程。
