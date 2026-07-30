# API 边界

本地 API 是 SwiftUI 前端与 Node.js 后端之间的私有、类型化、版本化协议。它不是供局域网或第三方客户端调用的公共 HTTP 服务。

## 传输与鉴权

每次启动由前端生成 Socket 路径和 Bearer Token，然后通过环境变量交给后端：

```text
MHG_SOCKET_PATH
MHG_API_TOKEN
MHG_PARENT_PID
```

关键不变量：

- 只监听 Unix Domain Socket，不监听 TCP。
- Socket 文件权限必须是 `0600`。
- 包括 health 在内的每条本地 API 路由都要求 Bearer Token。
- Token 比较使用恒定时间方法。
- 父进程消失时，后端终止并清理 Socket。

不要在文档、日志或测试快照中输出真实运行令牌。

## 版本化与校验

业务路由位于 `/v1` 边界。手写 dispatcher 根据 method 和 path 匹配处理器，Zod 在进入服务层前校验请求体。

新增或修改契约时，同时核对：

- Swift 与 TypeScript 的字段名。
- 可选值和 `null` 的含义。
- enum 原始值。
- 数字、字符串和布尔类型。
- 错误 detail 中的值类型。

前端解码失败不能覆盖后端真正的业务错误。

## 长轮询

任务、游戏启动和祈愿同步等耗时操作使用：

```text
?after=<游标>&wait=<等待时间>
```

客户端提交当前游标，后端在新事件、任务完成或等待超时后返回。实现必须处理：

- 首次请求没有游标。
- 超时但没有新事件。
- 客户端重复上一游标。
- 任务已完成后再次查询。
- 客户端取消和进程退出。

不要用高频短轮询替代既有长轮询约定。

## 跨服务边界

本地后端通过 HTTPS 访问可选云端；生产地址必须是 HTTPS，只有 localhost/loopback 开发地址允许 HTTP。

管理后台通过内部地址和 `MHG_ADMIN_SERVICE_TOKEN` 调用云端管理 API。后台不能直接操作云端业务表。

## 契约验证

跨端契约语料位于 `contracts/local-api/v1/`。修改 API、共享模型、任务 payload 或持久化形状后运行：

```bash
scripts/check-api-boundary.sh
```

该检查联合验证 TypeScript API 类型、Swift 模型和语料字段，不能只测试其中一端。
