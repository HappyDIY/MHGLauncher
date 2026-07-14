# MHGLauncher 严格只读审查：收敛发现

- 事实来源：`/Users/admin/.claude/plans/indexed-sleeping-walrus.md`，以及 2026-07-13 对任务 #5、#9 既定缺口的定向分段源码读取。
- 基线：`2c21c4c4891057862da58b0b8428487735ff7280`
- 方法：初始结果合并 54 个具有最终输出的 Agent；任务 #5、#9 由主会话按既定文件和页面组补审；任务 #11 批次 A–E 已完成全部既有条目的交叉验证。未扫描整个项目、未启动新 Agent、未运行测试、未修改项目代码。
- 去重原则：同一根因的多条表现合并；严重度优先采用独立 verifier，缺少独立 verifier 时保留主审静态结论并在来源/人工验证字段中说明。

## 汇总

- 已确认独立发现：**134**
- Critical：**1**；High：**32**；Medium：**79**；Low：**22**
- 需人工验证但未计入确认总数：**0**
- 交叉验证后 disputed：**1**

## 已确认发现

## #3 前端状态与并发

### SR-003-001 · Critical · Unix Socket 写入可触发 SIGPIPE 并终止整个前端进程

- **文件路径和行号：** frontend/Sources/Services/UnixSocketTransport.swift:21-46,61-68；frontend/Sources/Services/APIClient.swift:92-107
- **证据：** 连接建立后后端关闭流式 socket 时，代码直接调用 Darwin.write，未设置 SO_NOSIGPIPE、MSG_NOSIGNAL 或全局信号处理；Swift 错误捕获无法捕获 SIGPIPE。
- **影响：** 后端重启、崩溃或写入竞态可直接杀死 Launcher，而不是返回可处理错误。
- **最小修复建议：** 在 socket 上设置 SO_NOSIGPIPE，并把 EPIPE 统一映射为 transport 错误；增加真实 socket 对端提前关闭测试。
- **来源 Agent ID：** `a93ac8c67b9eff720`
- **置信度：** 高
- **是否需要人工验证：** 是（需在目标 macOS 上做隔离进程验证）

### SR-003-002 · Medium · Task.detached 切断取消传播，旧页面请求仍可提交陈旧状态

- **文件路径和行号：** frontend/Sources/Services/UnixSocketTransport.swift:7-13；frontend/Sources/State/ValueActions.swift:4-20；frontend/Sources/State/GameActions.swift:5-22；frontend/Sources/State/CharacterActions.swift:41-53
- **证据：** SwiftUI 取消 .task(id:) 后，detached 阻塞 I/O 继续；返回前没有 generation、当前路径或 UID 校验。已验证旧安装路径、旧角色详情和旧 Value load 均可晚到覆盖新状态。
- **影响：** 路径被切回、角色选择跳回、旧 UID 数据覆盖当前账号，并延长被取消任务对 Store 的持有。
- **最小修复建议：** 让 transport 可取消并关闭 descriptor；所有身份/路径作用域响应在提交前核对 generation 与当前 key。
- **来源 Agent ID：** `a93ac8c67b9eff720,ac34296a39645db20,a7e509efadff8164c,a02291ec975ae1551,aecb2950b83c287e4`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-003-003 · High · QR 登录 attempt 在注销、切换方式和 complete await 后未被完整失效

- **文件路径和行号：** frontend/Sources/State/AccountActions.swift:13-21,108-124,161-199；frontend/Sources/State/AccountLoginState.swift:13-29；frontend/Sources/MHGLauncherApp.swift:91-103
- **证据：** 旧二维码已通过 applyQRSession 后等待 /auth/complete；此时注销、开始新 attempt 或切换登录方式不会覆盖第二段 await 后的提交，旧响应仍可 acceptLogin 并写 Keychain。
- **影响：** 用户明确注销或改用其他登录方式后仍可能被旧二维码重新登录。
- **最小修复建议：** 把 attempt token 贯穿 complete 和 acceptLogin；注销/模式切换必须取消任务并递增 generation。
- **来源 Agent ID：** `a9a147cb81501e781,a7e509efadff8164c,a93ac8c67b9eff720`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-003-004 · High · Wish operation 可重入，清空记录可与同步并行并被重新写回

- **文件路径和行号：** frontend/Sources/MHGLauncherApp.swift:36-60；frontend/Sources/State/WishOperationActions.swift:5-88；backend/src/services/wish-tasks.ts:14-24；backend/src/services/wishes.ts:18-45
- **证据：** App 菜单的 import/export/clear 未统一检查 wishOperation；第二个 runWishOperation 覆盖共享状态，DELETE 后旧同步还可逐页 save。
- **影响：** 操作日志和终态互相污染；“清空成功”的记录随后重新出现。
- **最小修复建议：** 在前后端使用单一 operation ownership token/互斥；clear 必须拒绝或取消并等待活动同步完成。
- **来源 Agent ID：** `a9a147cb81501e781,a7e509efadff8164c,a93ac8c67b9eff720,a034e447a5710200c`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-003-005 · High · 账号/角色转换不隔离缓存，旧身份数据会残留或重新写回

- **文件路径和行号：** frontend/Sources/State/AccountActions.swift:108-159；frontend/Sources/State/CompanionActions.swift:15-19,37-62,147-160；frontend/Sources/State/CharacterActions.swift:8-29；frontend/Sources/Views/CharactersView.swift:7-22
- **证据：** 切到无角色账号、snapshot 失败、logout 自动选择下一账号或旧请求晚到时，wishes、dailyNote、characters、companionLoaded 未按身份原子清理/重载。
- **影响：** 界面标题与数据属于不同账号，注销后仍可看到旧账号资料，或新账号显示空/旧数据。
- **最小修复建议：** 建立统一 identity generation；身份提交时同步清空全部 role-scoped cache，并只接受 generation 匹配的响应。
- **来源 Agent ID：** `a5d1d3040929aafd7,a9a147cb81501e781,aecb2950b83c287e4,a90d0168c4ea8bbc3`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-003-006 · Medium · 全局 isBusy 是共享布尔值，多个操作会提前互相清零

- **文件路径和行号：** frontend/Sources/State/LauncherStore.swift:60,140-154；frontend/Sources/State/AccountActions.swift:24-72；frontend/Sources/State/CompanionActions.swift:37-110；frontend/Sources/Views/NotesView.swift:9-20；frontend/Sources/Views/NotificationsView.swift:20-28；frontend/Sources/Views/CloudSyncView.swift:9-42
- **证据：** 两个操作都写 true；先完成者 defer 写 false，即使另一操作仍在等待。部分菜单入口又不检查该标志。补审确认 Notes 刷新、通知立即检查及 Cloud 登录/上传/取回按钮均未按 `isBusy` 禁用，可由键盘或鼠标连续重入同一全局 busy 域。
- **影响：** 控件不会在真实操作期间稳定保持禁用，允许更多重入并使忙碌状态与真实任务不一致。
- **最小修复建议：** 改为计数/operation token，或为每类操作维护独立状态并在入口拒绝重入。
- **来源 Agent ID：** `a7e509efadff8164c`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-003-007 · Medium · 通知设置未保证最后一次用户意图落盘

- **文件路径和行号：** frontend/Sources/Views/NotificationsView.swift:32-65；frontend/Sources/State/ValueActions.swift:67-70；frontend/Sources/Services/UnixSocketTransport.swift:7-13
- **证据：** 离开页面会取消 400ms debounce 且不 flush；请求发出后取消又不能终止 detached I/O，旧 PUT 响应可覆盖更新值。
- **影响：** 最后一次编辑可能静默丢失，或 UI/后端回退到旧设置。
- **最小修复建议：** 维护 dirty revision；onDisappear 提交或持久排队；响应仅在 revision 仍为最新时应用。
- **来源 Agent ID：** `a31b2cbccd26ee075,a9a147cb81501e781`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-003-008 · Medium · 短信风控上下文使用响应时的可变手机号

- **文件路径和行号：** frontend/Sources/State/AccountActions.swift:24-64；frontend/Sources/State/AccountLoginState.swift:32-42；frontend/Sources/Views/AccountLoginView.swift:65-82
- **证据：** 手机号 A 发起请求后仍可编辑为 B；verification_required 返回时从 Store 重新读取 B，并组合 A 的 session ID。
- **影响：** 验证失败、会话与号码错配，或产生非预期的短信风控请求。
- **最小修复建议：** 在请求发起时捕获并保存手机号；响应提交前核对 request generation，输入请求期间禁用或允许取消。
- **来源 Agent ID：** `a9a147cb81501e781,a93ac8c67b9eff720`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-003-009 · Low · 便笺刷新循环吞掉 sleep 取消并额外执行一次

- **文件路径和行号：** frontend/Sources/State/CompanionActions.swift:5-12；frontend/Sources/MHGLauncherApp.swift:149-172
- **证据：** Task.sleep 的 CancellationError 被 try? 吞掉，循环体在下一次 while 检查前仍调用 refreshNote/evaluateNotifications。
- **影响：** 退出时出现一次陈旧请求、错误消息或状态写入。
- **最小修复建议：** sleep 后立即 guard !Task.isCancelled，并让刷新调用传播取消。
- **来源 Agent ID：** `abc91de27caf3969e`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-003-010 · Medium · CachedAsyncImage 的旧下载可在 URL 切换或变 nil 后覆盖新状态

- **文件路径和行号：** frontend/Sources/Views/CachedAsyncImage.swift:14-22,61-85
- **证据：** URL A 的非结构化缓存任务不随 .task(id:) 取消；nil 分支不清 image/loading，A 晚到可覆盖 B 或 nil。
- **影响：** 列表复用时显示错误头像/图标，旧图在无图状态继续可见。
- **最小修复建议：** 用结构化任务和 generation/key 校验；URL 变化时先清理状态并忽略旧结果。
- **来源 Agent ID：** `a4edbf3bcaf237cb6,a02291ec975ae1551`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-003-011 · Medium · 成就档案和条目不是同一原子快照，可把条目写入错误档案

- **文件路径和行号：** frontend/Sources/State/AchievementActions.swift:4-10,23-29,40-53；frontend/Sources/Views/AchievementsView.swift:147-185；backend/src/services/achievements.ts:55-61,80-103
- **证据：** /archives 与默认 /view 分开读取并分步赋值；选择失败、并发选择或部分响应可形成“档案 B + 档案 A 条目”。
- **影响：** 用户勾选旧条目时以当前档案 ID 持久化，污染另一档案。
- **最小修复建议：** 让 view 显式携带 archive_id，并以单次 snapshot/transaction 提交；保存时强制 entry.archiveId 匹配。
- **来源 Agent ID：** `a49b3c4ab51b56524,a5e032a1cea55b4a4,ae8be4128287561b0,a02291ec975ae1551,a0086e3fb3e5516a6`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-003-012 · Medium · 成就保存和档案选择不保证 latest-intent-wins

- **文件路径和行号：** frontend/Sources/Views/AchievementComponents.swift:64-67；frontend/Sources/Views/AchievementsView.swift:147-155,179-185；frontend/Sources/State/AchievementActions.swift:23-29,40-54
- **证据：** 每次 toggle/Picker setter 创建独立未跟踪 Task；POST 和后续全量 reload 可乱序，旧选择或旧勾选最后持久化/显示。
- **影响：** 最新用户操作被旧请求反转，数据库和 UI 均可能回退。
- **最小修复建议：** 按档案/条目串行化或使用 revision/CAS；取消并忽略旧任务结果。
- **来源 Agent ID：** `a7ba47988c28e2c3f,ae8be4128287561b0,a0086e3fb3e5516a6`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-003-013 · Medium · 成就页依赖无关接口全部成功，局部失败阻止核心数据加载

- **文件路径和行号：** frontend/Sources/State/ValueActions.swift:4-20；frontend/Sources/Views/AchievementsView.swift:16-31
- **证据：** gacha-events、characters、notification settings 或 goals 任一 await 失败，loadAchievementData 不会启动，已赋值的其他状态也不回滚。
- **影响：** 已有档案被误显示为不存在或保持陈旧状态。
- **最小修复建议：** 拆分独立 loading/error domain；成就档案加载不应被无关 endpoint 阻断。
- **来源 Agent ID：** `a49195cecb5d4148f,a0086e3fb3e5516a6`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

## #4 IPC 与凭据边界

### SR-004-001 · Medium · 后端 ready 后异常退出，前端仍永久保留失效 client

- **文件路径和行号：** frontend/Sources/Services/BackendProcess.swift:7-57；frontend/Sources/Views/RootView.swift:121-123；frontend/Sources/State/LauncherStore.swift:156-160
- **证据：** Process 没有 terminationHandler；client 只在显式 stop 或启动失败时清空。
- **影响：** UI 继续显示后端就绪，所有请求反复连接旧 socket，无法进入重试界面。
- **最小修复建议：** 监听子进程终止并原子清空 client/process；发布可恢复状态并允许受控重启。
- **来源 Agent ID：** `a93ac8c67b9eff720,a5d1d3040929aafd7`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — BackendProcess 在 ready 后没有 terminationHandler，client 只在显式 stop/启动 catch 清空；RootView 以 client 是否存在判定 ready，因此子进程异常退出后没有自动重试入口。影响限于单应用可用性，严重度校准为 Medium。

### SR-004-002 · Medium · 启动 ready 读取无期限且 stdout/stderr 后续无人排空

- **文件路径和行号：** frontend/Sources/Services/BackendProcess.swift:24-42,83-103
- **证据：** 阻塞 availableData 在 detached task 中无 deadline；stderr 从不读取，stdout 只读到 ready 行。
- **影响：** 沉默子进程使 bootstrap 永久挂起；管道写满可冻结后端。
- **最小修复建议：** 加入握手超时和取消 handler；持续异步排空或重定向两个管道。
- **来源 Agent ID：** `a153eb7de5381e3b0,a0086e3fb3e5516a6`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — readSocketPath 在 detached task 内同步调用 availableData，既无 deadline 也不响应父任务取消；ready 后 stdout 停止读取且 stderr 从未读取，管道背压路径成立。

### SR-004-003 · Medium · 请求取消未传播到服务，shutdown/retry 可与旧后端重叠

- **文件路径和行号：** backend/src/api/router.ts:31-36；backend/server.ts:20-37；frontend/Sources/Services/BackendProcess.swift:51-57
- **证据：** request.signal 未传入 route/service；server.close 无 deadline；前端 terminate 后立即丢弃 Process 引用并可启动新实例。
- **影响：** 旧工作继续，shutdown 卡住，两个后端可能同时访问数据库和缓存。
- **最小修复建议：** 把 AbortSignal 贯穿 provider/service；stop 等待终止并设截止时间，重启前确认旧 PID 已退出。
- **来源 Agent ID：** `a153eb7de5381e3b0`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — dispatch 未读取/传递 request.signal，server.close 等活动请求无截止时间；前端 stop 发送 terminate 后立即丢弃 Process/client，可在旧 shutdown 未完成时创建新后端并共享 DB/cache。

### SR-004-004 · Medium · 本地与 Cloud JSON 请求体没有应用级大小上限

- **文件路径和行号：** backend/src/api/router.ts:31-36；frontend/Sources/Services/UIGFFileIO.swift:3-8；cloud/src/router.ts:11-17
- **证据：** UIGF 在前端、transport 和 request.json 中整体缓冲；Cloud body/数组同样整体解析，部分路径在授权前发生。
- **影响：** 大文件导致多份内存放大、进程终止或长时间不可用。
- **最小修复建议：** 在流入口限制 Content-Length/实际读取字节和 item 数；大导入使用流式解析。
- **来源 Agent ID：** `a153eb7de5381e3b0,a5e8116a7d76a9e57,af907af269a1fcfda`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — UIGFFileIO、URL transport/request.json 与 Cloud upload array 都整体缓冲；本地仅在 bearer 后解析，Cloud dispatch 则在具体 route/bearer 前已 request.json，均没有应用级 byte/item limit。

### SR-004-005 · Low · 后端启动/关闭会无条件删除配置路径上的普通文件或活动 socket

- **文件路径和行号：** backend/server.ts:6-16,20-27；backend/src/core/config.ts:22-34
- **证据：** rm(path,{force:true}) 不检查目标是否为 stale socket；相同路径的第二进程可 unlink 第一监听器，普通文件也会被删。
- **影响：** 自定义/复用路径造成文件丢失、活动 endpoint 被替换或双方断连。
- **最小修复建议：** lstat 校验 socket 类型与所有权；使用独占随机目录并避免关闭时删除不属于当前 inode 的路径。
- **来源 Agent ID：** `a153eb7de5381e3b0`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — server 启停对配置 socketPath 直接 rm(force) 且不 lstat/inode 校验，可 unlink 普通文件或另一个活动 socket；rm 默认不会递归删除目录，故标题范围收窄并降为 Low。

### SR-004-006 · Low · MHG_REQUEST_TIMEOUT 被解析但未应用

- **文件路径和行号：** backend/src/core/config.ts:10,17-20,30；backend/server.ts:10-15
- **证据：** 配置进入 Settings 后未设置 server/request/provider timeout。
- **影响：** 配置无效，慢请求和 shutdown 持续时间超出运维预期。
- **最小修复建议：** 明确连接到 Node server timeout 与 outbound fetch AbortSignal，并增加行为测试。
- **来源 Agent ID：** `a153eb7de5381e3b0,ae34f5f86f326cdf8`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — requestTimeout 只存在于 Settings/测试构造，生产 server、dispatch 与 provider 均无任何读取，环境变量确定为无效配置。

### SR-004-007 · Low · 缺失/畸形 JSON 被误报为 500 internal_error

- **文件路径和行号：** backend/src/api/router.ts:31-40；backend/src/core/errors.ts:12-26；cloud/src/http.ts:11-14
- **证据：** request.json 的 SyntaxError 未映射为 4xx；Cloud 还可返回原始解析异常。
- **影响：** 客户端错误被当作服务故障，污染遥测并掩盖真实输入问题。
- **最小修复建议：** 统一捕获 JSON/URI 解析异常并返回稳定 400/422，不暴露内部文本。
- **来源 Agent ID：** `a153eb7de5381e3b0,a83ebd5d90d5938ed,a29eaa66e0fac874a`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — 本地 request.json 的 SyntaxError 落入 generic errorResponse 500；Cloud fail 对非 HttpError 直接返回 error.message，畸形 JSON 因而既误分类又可暴露解析文本。

### SR-004-008 · Low · 缺少 MHG_API_TOKEN 时本地 API 鉴权失败开放

- **文件路径和行号：** backend/src/core/config.ts:27；backend/src/api/router.ts:131-137
- **证据：** 空 token 时 authorize 直接 return，手工 npm start 或错误打包环境使全部 /v1 路由无鉴权。
- **影响：** 同 UID 进程连接 socket 后可读写本地状态。
- **最小修复建议：** 启动时把空 token 视为致命配置错误，不允许 server listen。
- **来源 Agent ID：** `a153eb7de5381e3b0`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — authorize 在 expected token 为空时直接 return；settings 默认空字符串，手工或错误启动仍会 listen 0600 socket，所有 v1 路由在同 UID 边界内失去 bearer 不变量。

### SR-004-009 · High · 登录先持久选择账号，再执行可能失败的角色同步

- **文件路径和行号：** backend/src/api/router.ts:60-72；backend/src/services/accounts.ts:20-29,73-81
- **证据：** AccountService.save 已选择新账号，随后 provider.getRoles 失败使请求整体报错，前端不保存 credential。
- **影响：** “登录失败”仍改变持久选中账号；重启后可能选中无 Keychain 凭据的账号。
- **最小修复建议：** 把账号保存、角色替换和成功响应设计成可补偿事务；失败时恢复先前选择或标记未完成。
- **来源 Agent ID：** `a90d0168c4ea8bbc3,a3ff063f68993eaba,a83ebd5d90d5938ed,a48968cd5449f9173`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — mobile/cookie/complete 三条路由都先 AccountService.save 提交 selected account，再 await syncRoles；provider 失败会让响应失败而数据库选择已改变，前端也不会执行 Keychain acceptLogin。

### SR-004-010 · Medium · Keychain 写入失败会留下半接受登录

- **文件路径和行号：** frontend/Sources/State/AccountActions.swift:185-198；frontend/Sources/Services/KeychainStore.swift:13-25
- **证据：** acceptLogin 先写 account/roles，再调用可能抛错的 Keychain save；后端也已提交。
- **影响：** UI/后端显示已登录但没有 credential，启动与实时数据随后失败。
- **最小修复建议：** 先安全写 Keychain 再提交 UI，或在失败时回滚前后端选择并刷新账号列表。
- **来源 Agent ID：** `a90d0168c4ea8bbc3`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — acceptLogin 在收到已提交的后端响应后先赋 account/roles，再执行可抛错 SecItemUpdate/Add；失败由外层 perform 显示错误但没有回滚 UI 或后端选择。

### SR-004-011 · High · Logout 先删除后端账号，再执行可能失败的 Keychain 清理

- **文件路径和行号：** frontend/Sources/State/AccountActions.swift:108-124；backend/src/services/accounts.ts:61-70；frontend/Sources/Services/KeychainStore.swift:41-45
- **证据：** DELETE 成功并自动选择下一账号后，SecItemDelete 失败会跳过前端刷新/清理。
- **影响：** 前端仍持有 A 状态/凭据，后端已选择 B；旧 Keychain 项成为孤儿。
- **最小修复建议：** 使用可恢复 logout 状态机；即使 Keychain 删除失败也先重载后端身份，并提供重试清理。
- **来源 Agent ID：** `a90d0168c4ea8bbc3,a6e392db2ba6a87dc,a48968cd5449f9173`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — logout 先 DELETE 后端账号并可能自动选择下一账号，再调用 SecItemDelete；任何非 success/notFound OSStatus 会跳出 closure，跳过前端身份刷新与缓存清理。

### SR-004-012 · High · /roles/sync 可把一个账号的角色写到另一个选中账号

- **文件路径和行号：** backend/src/api/router.ts:49-51；backend/src/services/accounts.ts:73-80
- **证据：** 路由只提交 credential，syncRoles 默认使用当前 selected aid；B credential 返回的角色可被写在 A 下。
- **影响：** 持久账号-角色归属损坏，后续用 A 的 Keychain 凭据访问 B UID。
- **最小修复建议：** 要求显式 aid 并验证 credential identity；删除或限制无绑定的通用同步路由。
- **来源 Agent ID：** `a90d0168c4ea8bbc3,a83ebd5d90d5938ed`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — /roles/sync 请求 schema 只有 credential，AccountService.syncRoles 默认取当前 selected aid；provider 角色完全来自所给 credential，随后以该 aid 删除并重写角色。

### SR-004-013 · High · 每次角色同步都把选中角色重置为上游数组第一项

- **文件路径和行号：** backend/src/services/accounts.ts:73-85；backend/src/providers/live.ts:94-97
- **证据：** 同步删除旧角色后以 index===0 标记 selected，忽略已持久选择和 provider selected 字段。
- **影响：** 祈愿、便笺和角色数据静默切换到另一 UID/服务器。
- **最小修复建议：** 同步前保存 selected UID；优先保留仍存在的选择，否则使用经过验证的 provider 选择。
- **来源 Agent ID：** `a90d0168c4ea8bbc3,a83ebd5d90d5938ed,a48968cd5449f9173`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — syncRoles 无条件把 provider 返回数组 index 0 设为 selected，并先删除旧 rows；既不保存旧 selected UID，也不使用 provider 的 is_chosen 映射结果。

### SR-004-014 · Low · 一般 credential 读取把 Keychain 错误折叠为“未登录”

- **文件路径和行号：** frontend/Sources/State/LauncherStore.swift:75-78,163-165；frontend/Sources/Services/KeychainStore.swift:28-38
- **证据：** try? 将访问拒绝等 OSStatus 转为 nil；后台循环甚至静默跳过。
- **影响：** 用户无法区分凭据不存在与 Keychain 故障，操作无可行动诊断。
- **最小修复建议：** 保留 throwing access result，并把 missing 与 accessDenied/interactionNotAllowed 分开呈现。
- **来源 Agent ID：** `a90d0168c4ea8bbc3`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — LauncherStore.credential 使用 try? Keychain read，将 access denied/interaction not allowed 与 item missing 都折叠为 nil；requireCredential 与后台调用无法区分故障。

### SR-004-015 · Medium · /auth/complete 不绑定 QR 会话或 credential 的真实身份

- **文件路径和行号：** backend/src/api/router.ts:18,52-54,70-72；backend/src/services/accounts.ts:20-29,73-80
- **证据：** 持有本地 token 的调用方可直接提交任意 identity/credential_ref；角色仅由 credential 获取，却写到调用方 aid。
- **影响：** 可绕过 QR 流程并创建错配账号、角色和 Keychain 引用。
- **最小修复建议：** 请求必须携带一次性 completion/session ID；后端从会话生成 identity 并验证 aid/mid 与 credential。
- **来源 Agent ID：** `a7d2eb7a0b8d96c31`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — /auth/complete 直接接受 body 中 identity、credential 与 credential_ref，没有 QR completion/session ID；roles 虽由 credential 获取，仍按调用方 identity.aid 写入。

### SR-004-016 · Medium · Aigis verification session 未原子消费且未绑定手机号

- **文件路径和行号：** backend/src/providers/live.ts:57-81；backend/src/providers/aigis.ts:30-36
- **证据：** 并发请求都可在 delete 前通过 has(sessionId)；stored session 不含 mobile，另一号码也可复用。
- **影响：** 发送重复/错配的上游验证码请求，引发短信重复、限流或验证失败。
- **最小修复建议：** 以原子 take 删除 session，并保存/校验原始手机号；失败时按明确策略恢复。
- **来源 Agent ID：** `a7d2eb7a0b8d96c31`
- **置信度：** 高
- **是否需要人工验证：** 否（批次 B 已确认本地竞态与手机号未绑定；上游行为仅影响后果量级）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — verifyMobileCaptcha 先 has(sessionId)，await 上游请求后才 delete；并发调用可同时通过。AigisSession 结构不保存 mobile，任意合法手机号可复用同一 session。上游最终响应只影响后果，不影响竞态成立。

### SR-004-017 · Medium · Live provider 成功响应缺少运行时 schema，空字段被当作有效值

- **文件路径和行号：** backend/src/providers/live.ts:29-32,79-81,94-97,128-135；backend/src/providers/credential.ts:24-45
- **证据：** retcode=0 但 data 缺字段时，角色列表变空并删除缓存，token 字段序列化为 undefined，QR/captcha/ticket 返回占位值或空串。
- **影响：** 有效账号数据被清空，毒化 credential 进入 Keychain，或启动无 auth ticket。
- **最小修复建议：** 为每个上游响应使用严格 schema；缺少必填字段必须作为 upstream_contract_error 且不得提交状态。
- **来源 Agent ID：** `a3ff063f68993eaba`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — 多个 retcode=0 路径直接 String/Number 强转可选字段：QR 可生成 `undefined`，roles 缺 list 返回空并覆盖缓存，credential 补全可写 `undefined`，auth ticket 缺失返回空串；没有运行时 schema 阻止提交。

### SR-004-018 · Low · 临时 login_ticket 与登录输入/风控会话生命周期过长

- **文件路径和行号：** backend/src/providers/live.ts:140-148；frontend/Sources/State/AccountActions.swift:74-124；frontend/Sources/State/LauncherStore.swift:50-56
- **证据：** 换得长期 stoken 后仍保留 login_ticket；失败/取消/切换方式/logout 不统一清 loginCookie、mobile session。
- **影响：** 短期秘密长期进入 Keychain 或留在同一解锁桌面会话的 UI 内存中。
- **最小修复建议：** credential 正规化后删除已消费临时字段；统一实现登录表单 reset/cancel。
- **来源 Agent ID：** `a6e392db2ba6a87dc`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — login_ticket 换取 stoken 后 normalizeCredential 仍序列化原 Map，ticket/login_uid 未删除；前端 logout/模式切换也未统一清 loginCookie、mobileCaptchaSession 与全部输入状态。

### SR-004-019 · Low · 终态 game/wish/launch 对象和日志无界保留

- **文件路径和行号：** backend/src/services/games.ts:22-24,77-84；backend/src/services/wish-tasks.ts:9-12,47-68；backend/src/services/game-launches.ts:19-26,44-52
- **证据：** 终态任务、DownloadControl、日志、persisted launch 和 session 目录不淘汰。
- **影响：** 长时间运行逐步增长内存和磁盘。
- **最小修复建议：** 设置数量/时间 TTL，终态持久摘要与活动对象分离，并定期清理目录。
- **来源 Agent ID：** `a7d2eb7a0b8d96c31`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — GameService jobs/controls、WishTasks jobs、GameLaunchService launches/persisted/log offsets/controllers 及 launch session 目录都没有 TTL/数量淘汰；终态只改变 status，不删除容器。

### SR-004-020 · Low · Long-poll timeout 后保留空 waiter Set

- **文件路径和行号：** backend/src/services/revision-notifier.ts:5-30
- **证据：** timeout 只删 resolver，不在 Set 为空时删除 Map key；终态 ID 不会再 mark/release。
- **影响：** 每个被轮询的终态 ID 可永久增加一个空容器。
- **最小修复建议：** timeout/cancel 时若 Set 为空立即删除 key，并测试终态清理。
- **来源 Agent ID：** `a7d2eb7a0b8d96c31`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 B 交叉验证（2026-07-13）：** `CONFIRMED` — RevisionNotifier timeout 只从 Set 删除 resolver，不在 Set 为空时删除 waiters Map key；终态 ID 不再 mark/release 时该空 Set 永久保留。

## #5 前端运行时安装

### SR-005-001 · Medium · 手动安装游戏运行时与启动游戏可并发进入两个 installer

- **文件路径和行号：** frontend/Sources/Views/RuntimeStatusView.swift:12-20；frontend/Sources/Views/GameLaunchControls.swift:23-35；frontend/Sources/State/LauncherStore.swift:128-138；frontend/Sources/Services/RuntimeInstaller.swift:5,105-130；frontend/Sources/Services/RuntimeArchive.swift:117-145
- **证据：** isInstallingGameRuntime 仅展示状态，不是 ensureGameRuntime 入口 guard；启动按钮也不检查它。补审确认 RuntimeInstaller 为无锁的 `@unchecked Sendable`，并发调用会对同一 tag/component 共用缓存目标和固定 `.part` 路径，任一调用都可删除或移动另一调用正在使用的临时文件。
- **影响：** 两个 installer 竞争共享 .part、promotion 目录和进度状态。
- **最小修复建议：** 在 Store 内以 single-flight Task/actor 串行 ensureGameRuntime，所有入口 await 同一任务。
- **来源 Agent ID：** `a9a147cb81501e781`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-005-002 · High · 同一 runtime tag 的重发不会升级已安装组件并可混装新后端与旧依赖

- **文件路径和行号：** frontend/Sources/Services/RuntimeInstaller.swift:20-25,52-56,136-159；frontend/Sources/Services/RuntimeInstallerBackendCopy.swift:10-20,42-49；scripts/publish-runtime-assets.sh:18
- **证据：** 完成标记存在时跳过 manifest；同 tag --clobber 更新 Node/Wine/node_modules 对已有用户无效，而后端代码仍可替换。补审确认一次首次 `ensureGame` 会先由 `ensureCore` 获取清单，再无缓存地重新获取一次游戏清单；两次只校验相同 tag/schema，因此同 tag 内容在两次请求间变化时，单次安装也能混用两版 core/game component。
- **影响：** 运行时安全修复无法送达，JS 与旧包/原生 ABI 混装。
- **最小修复建议：** 使 tag 不可变且每次依赖变更发布新 tag；就绪判定绑定 manifest/component digest。
- **来源 Agent ID：** `a367d9b95f4efd400,a7e69a01c80790dfd`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-005-003 · Medium · 游戏运行时就绪判定遗漏启动必需文件

- **文件路径和行号：** frontend/Sources/Services/RuntimeInstaller.swift:153-159；backend/src/services/game-launch-environment.ts:11-19
- **证据：** 完成标记与少量路径存在即可 ready，未检查 wineboot、window probe、DNS gate dylib。
- **影响：** 文件被删除/隔离后 installer 跳过修复，启动才报 game_runtime_missing。
- **最小修复建议：** 把所有强制 runtimePaths 纳入完整性清单和 ready 校验，缺失时自动重装对应组件。
- **来源 Agent ID：** `a367d9b95f4efd400`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-005-004 · Medium · Promotion 后标记移动失败时 backup 回滚必然失败

- **文件路径和行号：** frontend/Sources/Services/RuntimeInstallerPaths.swift:36-55；frontend/Sources/Services/RuntimeInstaller.swift:67-76,162-175
- **证据：** 新目录已移入正式路径后，完成标记移动失败；catch 直接把 backup move 到仍存在的正式路径并吞错。补审确认 core promotion 也吞掉 backup 恢复失败，并且 core/game 两条路径都会在下一次 promotion 开始时先无条件删除既有 backup，未通过 journal 区分可清理残留和唯一可恢复副本。
- **影响：** 旧可用运行时留在 backup，下一次重试删除 backup 后永久丢失。
- **最小修复建议：** 失败时先移走/删除新目录再原子恢复 backup；保留 recovery marker 并测试每一步故障。
- **来源 Agent ID：** `a367d9b95f4efd400`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）

### SR-005-005 · Medium · RuntimeArchive 不检查链接目标与解压后对象类型

- **文件路径和行号：** frontend/Sources/Services/RuntimeArchive.swift:50-68,155-160；frontend/Sources/Services/RuntimeInstaller.swift:145-159；scripts/build-runtime-assets.sh:45-50；scripts/create-smoke-runtime-assets.sh:39-42
- **证据：** 校验只把 `tar -tzf` 的非详细条目名交给词法路径检查，未读取 symlink/hardlink target 或条目类型；解压后也没有 `lstat`/树遍历。生产打包使用保留链接的 tar，smoke producer 还明确把 symlink node_modules 打入归档，而 ready 检查会跟随链接。安全名称下的绝对或越界 symlink 因此可落盘并让可执行文件/依赖解析到运行时根外；hardlink、FIFO 等特殊类型同样没有契约。
- **影响：** 已签名但构建异常或被污染的 component 可让 launcher 执行、读取或保留托管目录外的对象，promotion/rollback 也无法真正封装其依赖。
- **最小修复建议：** 使用结构化 tar 解析器校验条目类型及 symlink/hardlink target containment；解压后以 `lstat` 复核整棵树，同时显式允许 node_modules 所需且仍留在根内的相对链接。
- **来源 Agent ID：** `主会话-#5-2026-07-13`
- **置信度：** 高
- **是否需要人工验证：** 否（未运行测试；建议补链接和特殊条目 fixture）

### SR-005-006 · Medium · 清单下载在官方源前串行读取无大小边界的第三方镜像

- **文件路径和行号：** frontend/Sources/Services/RuntimeDownloadSource.swift:12-35,49-89；frontend/Sources/Services/RuntimeManifestDownload.swift:5-24；frontend/Tests/RuntimeInstallerTests.swift:79-109
- **证据：** 五个硬编码第三方 proxy 固定排在 GitHub 前面，manifest 与 signature 对每个源串行使用 `URLSession.shared.data` 完整读入内存；没有 installer 专用的短超时或响应大小上限，签名验证只能在两份 body 全部下载后发生。后续 benchmark 只排序 component 下载源，无法保护此前的 manifest 获取；现有测试只验证源数量、签名原语和 component fallback，未覆盖 manifest timeout/oversize/fallback。
- **影响：** 任一失效镜像可在官方源可用时仍显著拖延安装；恶意或故障镜像可返回超大 body 造成内存压力，并阻止及时 fallback。
- **最小修复建议：** 对 manifest/signature 设置严格 byte limit 和短超时，竞速或优先官方源，缓存近期健康度，并为网络、HTTP、超限、签名失败分别测试 fallback。
- **来源 Agent ID：** `主会话-#5-2026-07-13`
- **置信度：** 高
- **是否需要人工验证：** 否（未运行测试；建议使用注入 URLProtocol 的确定性测试）

### SR-005-007 · Medium · Installer 吞掉取消并可在任务取消后继续解压和 promotion

- **文件路径和行号：** frontend/Sources/Services/RuntimeDownloadSource.swift:52-88；frontend/Sources/Services/RuntimeArchive.swift:123-146,174-189；frontend/Sources/Services/RuntimeInstaller.swift:105-133；frontend/Sources/MHGLauncherApp.swift:148-170
- **证据：** benchmark 和 archive download 都以无类型 `catch` 吞掉取消错误，下载最终被改写为普通 downloadFailed；组件循环及 marker/promotion 前没有 `Task.checkCancellation()`。缓存命中后会直接进入同步 `/usr/bin/tar` 加 `waitUntilExit`，该进程也没有随 Swift Task 取消。启动由 SwiftUI `.task` 驱动，视图消失可取消父任务，但 installer 仍能继续写 marker 并切换正式目录。
- **影响：** 用户关闭窗口、生命周期切换或上层主动取消后，文件系统仍可能继续发生大规模解压和原子切换；调用方还会收到错误分类错误的失败状态。
- **最小修复建议：** 保留并重新抛出 `CancellationError`/`URLError.cancelled`，在每个组件、解压前后及 promotion 前检查取消，并为 tar 子进程安装取消终止与清理处理。
- **来源 Agent ID：** `主会话-#5-2026-07-13`
- **置信度：** 高
- **是否需要人工验证：** 否（未运行测试；建议覆盖缓存命中和 tar 运行中的取消）

### SR-005-008 · Medium · 崩溃遗留的随机 staging 与完整 backup 没有启动恢复或清理

- **文件路径和行号：** frontend/Sources/Services/RuntimeInstaller.swift:27-48,56-76,162-175；frontend/Sources/Services/RuntimeInstallerPaths.swift:30-55
- **证据：** 每次安装创建带 UUID 的新 stage，只有当前调用的 `catch` 会尝试删除；进程终止后没有任何代码枚举旧 stage。core/game backup 也只在 promotion 内处理：若新 runtime 已就绪但清理前崩溃，完整 backup 会永久保留；若旧 runtime 已移入 backup 后崩溃，重启不会恢复它，下一次 promotion 反而先删除该唯一副本。
- **影响：** 多 GB 游戏运行时可随重试无限占用磁盘；本可立即恢复的旧版本被忽略并可能在新提交成功前删除，迫使重新下载且扩大故障窗口。
- **最小修复建议：** 为 stage/backup 写入带任务 ID 和阶段的持久化 journal，启动时先恢复或安全清理；只有确认新目录和 marker 提交完成后才能删除旧副本。
- **来源 Agent ID：** `主会话-#5-2026-07-13`
- **置信度：** 高
- **是否需要人工验证：** 否（未运行测试；建议逐 promotion 步骤注入进程终止）

### SR-005-009 · Medium · Manifest 只校验 schema/tag，component 与目标平台契约未被执行

- **文件路径和行号：** frontend/Sources/Models/RuntimeModels.swift:14-34；frontend/Sources/Services/RuntimeInstaller.swift:20-45,105-142；scripts/build-runtime-assets.sh:45-78,177-183；scripts/fetch-node.sh:5-7；scripts/test-runtime-assets.sh:8-17
- **证据：** consumer 仅检查 `schemaVersion == 1` 和 tag；component ID/version 不要求非空或唯一，required kind/ID 不校验，`installRoot` 虽解码却从未读取，schema 也没有 platform/architecture。producer 实际固定打包 darwin-arm64 Node 和 x86_64 Wine/DXMT，但清单不能表达或约束该组合；资产测试只检查 schema/tag/file size/hash。空 core components 仍会写 `.core-complete`、promotion 并直接返回，重复或重叠 component 则按顺序覆盖同一 destination。
- **影响：** 已签名但生成错误的清单可把缺失、重复、错误 install root 或错误平台的资产安装并部分标记完成，故障直到进程启动或具体功能使用时才暴露。
- **最小修复建议：** 在 schema 中加入目标 platform/host architecture，验证必需且唯一的 component ID、kind、非空 version、安全 installRoot、hash/size/parts 一致性，并在提交前验证最终安装后置条件。
- **来源 Agent ID：** `主会话-#5-2026-07-13`
- **置信度：** 高
- **是否需要人工验证：** 否（未运行测试；建议 producer/consumer 共用 schema fixture）

## #6 后端游戏资源流程

### SR-006-001 · High · 远端 build.version/tag 可逃逸下载缓存并驱动递归删除

- **文件路径和行号：** backend/src/providers/sophon.ts:57,74；backend/src/services/games.ts:108,131
- **证据：** version 未限制路径组件，join(dataDir,"downloads",version) 可被 ../ 规范化到任意可写目录；成功后 rmSync recursive。
- **影响：** 受污染元数据可写入并删除数据目录外文件。
- **最小修复建议：** 将 version 限制为严格标识符；resolve/relative 验证缓存路径包含性并避免递归删除未带 ownership marker 的目录。
- **来源 Agent ID：** `ac1b91725518d4897,a47ea12bbc6dc7390,a7f0bef8a45fbb811`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — Sophon 将远端 tag 原样作为 build.version；GameService 随后把它传入 downloads 路径并在成功后递归删除 cache，含 `..` 的 tag 可达该 sink。

### SR-006-002 · High · 安装会无条件递归删除用户同名 .staging 和 .backup 邻接目录

- **文件路径和行号：** backend/src/services/games.ts:106-113,130,137；backend/src/services/installer.ts:35-45
- **证据：** 目录仅由 installPath 加固定后缀生成，删除前无归属标记。
- **影响：** 碰巧同名的用户照片/文档目录会不可恢复删除。
- **最小修复建议：** 使用 dataDir 内随机任务 staging；backup/stage 必须含 launcher ownership marker 和任务 ID 后才可清理。
- **来源 Agent ID：** `ac1b91725518d4897`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — install/full-update 的非 in-place 路径由用户安装目录直接派生固定 `.staging`/`.backup`，stageExisting 与 activate 在任何 ownership 检查前递归删除同名目录。

### SR-006-003 · Medium · 词法路径包含检查不能阻止父目录 symlink 逃逸

- **文件路径和行号：** backend/src/services/installer.ts:7-13；backend/src/services/sophon-install.ts:22-41；backend/src/services/game-build.ts:20-24
- **证据：** safeTarget 只 resolve 字符串；游戏树中的 symlink 父目录仍把写入、rename、deprecated 删除导向根目录外。
- **影响：** 更新/修复可覆盖或删除游戏目录外文件。
- **最小修复建议：** 逐组件 lstat 拒绝 symlink，或在受控 dirfd 下使用 no-follow 语义；解压后审计链接。
- **来源 Agent ID：** `ac1b91725518d4897,a8956da2040afb49e,ae50e0a7d8eddf755`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — safeTarget 只做字符串 resolve/relative；Sophon 写入、rename 与 removeSafe 都会继续跟随已存在的父目录 symlink，代码中没有 lstat/no-follow 屏障。

### SR-006-004 · Medium · Verify/repair 快速路径可不读取文件内容而接受同尺寸损坏文件

- **文件路径和行号：** backend/src/services/game-integrity.ts:18-32,47-58
- **证据：** 无索引时只比较 pkg_version 的期望 MD5；有索引时比较 size/mtime 与保存摘要，不重新哈希实际文件。
- **影响：** 同尺寸替换或恢复 mtime 的损坏文件通过校验，repair 不修复。
- **最小修复建议：** 显式 verify 必须计算实际内容摘要；快速路径仅用于普通状态查询并采用可信元数据。
- **来源 Agent ID：** `ac1b91725518d4897`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — 同版本 repair 必经 selectInvalidAssets；fastValid 只比较 size+mtime+已保存摘要，或把 pkg_version 的期望摘要与远端期望值互比，从未读取当前文件内容。

### SR-006-005 · High · Version-diff 在下载补丁前可删除上一 full install 的全部资产

- **文件路径和行号：** backend/src/services/games.ts:114；backend/src/services/game-build.ts:14-24,35-38；backend/src/providers/sophon.ts:60-74
- **证据：** diff build 的 assets 通常为空；removeRetired 只以 build.assets 建 current set，于是把 .mhg-assets.json 中所有旧项视为退休。
- **影响：** YuanShen.exe 和未变化文件在补丁开始前被删除，取消/失败无法恢复。
- **最小修复建议：** version_diff 只删除显式 deprecated_files；完整资产清理必须依赖权威 full manifest 且在事务提交后执行。
- **来源 Agent ID：** `a8956da2040afb49e,ae50e0a7d8eddf755`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — version_diff 的 assets 为空而 patch_assets 非空时走 in-place；removeRetired 在 installPatches 前以空 assets 构造 current set，可先删除 `.mhg-assets.json` 记录的全部旧资产。

### SR-006-006 · High · Patch 在最终校验前覆盖原文件，错误 range/MD5 会删除目标

- **文件路径和行号：** backend/src/services/patch-install.ts:29-42；backend/src/services/file-hash.ts:32-45；backend/src/providers/sophon.ts:68
- **证据：** range 未验证安全整数/边界，copyRange 可短读；direct/hpatch 输出先 rename 到 target，随后 MD5 失败执行 rm(target)。
- **影响：** 恶意或错误清单、坏源文件或工具错误可摧毁原游戏资产。
- **最小修复建议：** 严格验证 range 和写入字节数；在独立 temp 上完成 size+MD5 后原子替换，并保留原文件用于回滚。
- **来源 Agent ID：** `ac1b91725518d4897,a8956da2040afb49e,ae50e0a7d8eddf755`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — apply 在 range 未验证且未确认完整读取的情况下生成 segment；direct/hpatch 均先替换 target，最终 MD5 失败再 rm target，原文件已不可恢复。

### SR-006-007 · High · 多资产 patch 更新无任务级事务或崩溃恢复

- **文件路径和行号：** backend/src/services/games.ts:103-138；backend/src/services/patch-install.ts:11-18,29-42
- **证据：** patch_assets 强制 in-place 且逐文件提交；后续资产失败或进程死亡不会恢复已提交文件。
- **影响：** 目录进入新旧混合版本，重试可能把旧到新 patch 应用于已更新文件。
- **最小修复建议：** 建立 durable patch journal/backup set；全部验证后统一 commit，失败按逆序恢复。
- **来源 Agent ID：** `a8956da2040afb49e,ac1b91725518d4897,ae50e0a7d8eddf755`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — installPatches 逐资产直接提交到正式树，外层 run 没有 patch journal/backup；任一后续资产错误或进程终止都会保留先前提交。

### SR-006-008 · Medium · 仅含 deprecated_files 的差分不删除文件却仍写入目标版本

- **文件路径和行号：** backend/src/providers/sophon.ts:60-74；backend/src/services/games.ts:74-76,106,117-131
- **证据：** 删除逻辑错误地位于 patch_assets.length 分支；空 patch diff 走空安装路径并写新版本。
- **影响：** 官方要求删除的旧文件保留，状态却宣称升级完成，后续 diff 基线错误。
- **最小修复建议：** 把 deprecated_files 计入工作量和 in-place 判定；空差分必须拒绝或验证确为 no-op。
- **来源 Agent ID：** `a47ea12bbc6dc7390`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — 条件成立但范围需收窄：仅含 deprecated_files 且无 patch/assets 时不会执行显式 deprecated 删除；在没有 `.mhg-assets.json` 的普通安装上仍复制旧树并提交新版本。

### SR-006-009 · Medium · 空或不完整的成功 build 可只改版本号并报告更新完成

- **文件路径和行号：** backend/src/providers/sophon.ts:51-57,109-114；backend/src/services/games.ts:63-83,103-132
- **证据：** retcode=0 但 manifests 缺失/未匹配时产生不同版本且零资源；现有零大小 guard 只拒绝版本相同。
- **影响：** 旧客户端被标记为新版本，未来更新选择和启动状态失真。
- **最小修复建议：** 不同版本的 build 必须含权威资源/删除集合；空选中 manifest 作为上游契约错误。
- **来源 Agent ID：** `a7f0bef8a45fbb811`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — selected manifests 为空可生成“不同 version + 零资源”build；same-version guard 不触发，已有树被复制后只写 `.mhg-version` 并保存 ready 状态。

### SR-006-010 · High · patch.id/chunk.name 未约束路径，可越出缓存并写任意文件

- **文件路径和行号：** backend/src/services/patch-install.ts:21-27,45-47；backend/src/services/sophon-install.ts:47-52,78-80；backend/src/services/predownload.ts:28-42
- **证据：** 标识直接 join(cache,id/name)；哈希只取下划线前缀，攻击者可把正确 xxhash 与 ../../target 组合。
- **影响：** 以 Launcher 用户权限覆盖任意文件，且后续缓存清理不会删除逃逸文件。
- **最小修复建议：** 要求单一 basename/固定哈希格式，并对最终 resolve 路径做 containment 检查。
- **来源 Agent ID：** `a8956da2040afb49e,ae50e0a7d8eddf755,a47ea12bbc6dc7390`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — patch.id/chunk.name 原样 join 到 cache；下载层会创建逃逸路径的父目录，校验又只取名称下划线前缀，因此可构造合法 hash 前缀并越界。

### SR-006-011 · Medium · Patch original_name 被保留但完全未作为源路径使用

- **文件路径和行号：** backend/src/providers/sophon.ts:68；backend/src/services/patch-install.ts:29-37
- **证据：** 只把 original_name 当布尔值，hpatchz 输入仍是 asset.name。
- **影响：** 重命名/移动 patch 确定失败或对错误源文件应用补丁。
- **最小修复建议：** 分别构造并校验 sourceTarget(original_name) 与 destinationTarget(asset.name)。
- **来源 Agent ID：** `a8956da2040afb49e,ae50e0a7d8eddf755,a47ea12bbc6dc7390`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — original_name 只决定是否调用 hpatchz；实际源参数始终是 destination `asset.name`，所以 original_name 与目标名不同时代码确定使用错误源。

### SR-006-012 · Medium · mhypbase.dll 保护可被词法等价路径 mhypbase.dll/. 绕过

- **文件路径和行号：** backend/src/services/game-build.ts:20-38；backend/src/services/installer.ts:7-12
- **证据：** 保护检查原始最后组件“.”，safeTarget 随后规范化为真实 mhypbase.dll。
- **影响：** 官方资源清理/替换可删除 Launcher 管理的兼容 DLL，违反核心不变量。
- **最小修复建议：** 先规范化相对路径再按 canonical basename/real target 过滤，并测试所有等价路径。
- **来源 Agent ID：** `ae50e0a7d8eddf755`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — isProtectedAsset 在原始字符串上取末组件，`mhypbase.dll/.` 得到 `.`；后续 safeTarget 会规范化成真实 DLL 路径，保护可达地失效。

### SR-006-013 · High · 资源任务 reservation 非原子，且与游戏启动只做单向互斥

- **文件路径和行号：** backend/src/services/games.ts:63-84；backend/src/services/game-launches.ts:35-38；frontend/Sources/Views/GameResourceActionButtons.swift:18-35
- **证据：** GameService.start 在 busy 后先 await provider/磁盘再登记 job；并发 job 都可通过。资源侧也不检查活动 launch。
- **影响：** 两个任务竞争同一 cache/目标；游戏运行中可被更新、删除和 patch。
- **最小修复建议：** 在首个 await 前同步 reservation；以 installPath 为 key 的统一锁同时覆盖 launch 与所有 resource jobs。
- **来源 Agent ID：** `a8956da2040afb49e,a13d08d6b4684ab08`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — GameService.start 在首个 provider await 前仅查询 busy，直到所有远端/磁盘检查后才登记 job；GameLaunchService 只单向查询 resourcesBusy，资源服务没有 launchBusy 反向检查。

### SR-006-014 · Medium · 下载和 manifest fetch 缺少自主 stall timeout

- **文件路径和行号：** backend/src/services/download-transfer.ts:22,28-33；backend/src/providers/sophon.ts:99-114
- **证据：** fetch 等响应头或 reader.read 可永久不返回；配置 timeout 未传入。
- **影响：** 任务永久 running 并阻止所有后续资源操作。
- **最小修复建议：** 对连接、首字节和每次 body read 使用组合 AbortSignal/截止时间，并区分用户取消。
- **来源 Agent ID：** `a13ac1b256bfb96c0,a7f0bef8a45fbb811`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — 下载 fetch 只有用户控制的 AbortSignal、没有 stall deadline；Sophon metadata/manifest fetch 连该 signal 也没有，且 provider await 发生在 job 登记前。影响为单任务/请求挂起，严重度校准为 Medium。

### SR-006-015 · High · Pause/cancel 不是提交屏障，终态可被后续完成覆盖

- **文件路径和行号：** backend/src/services/download-transfer.ts:30-55；backend/src/services/sophon-install.ts:28-43；backend/src/services/games.ts:92-100,124-132
- **证据：** 最后 read 后、hash/rename/解压/最终状态前缺少 checkpoint；cancelled/paused 可继续变 completed。
- **影响：** 用户取消后游戏目录仍被修改，版本和完整性索引仍更新。
- **最小修复建议：** 在每个不可逆阶段前后 checkpoint；cancel 等待 worker 全部退出后才发布终态。
- **来源 Agent ID：** `a13ac1b256bfb96c0`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — control.cancel 先发布 cancelled，但最后一次 reader/checkpoint 后的 hash、rename、解压、版本与索引提交前没有 checkpoint，run 最后可把状态覆写为 completed。

### SR-006-016 · Medium · 并发 worker 首错后 sibling 仍下载、rename 并发布 revision

- **文件路径和行号：** backend/src/services/sophon-install.ts:14-27,55-60；backend/src/services/predownload.ts:37-50
- **证据：** Promise.all 首个 rejection 不取消其他 worker，worker 无共享 failed 标志。
- **影响：** 任务已 failed/busy=false 后旧 worker 继续写 cache，与新任务并发。
- **最小修复建议：** 首错触发共享 AbortController；等待 Promise.allSettled 后再发布 failed。
- **来源 Agent ID：** `a13ac1b256bfb96c0`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — Promise.all 首错会立即让 run 发布 failed，而 sibling promise 不会被取消，仍可完成 cache rename 与 revision 回调；目标树组装不再继续，故严重度校准为 Medium。

### SR-006-017 · Medium · Range 续传只检查 206，不验证 Content-Range

- **文件路径和行号：** backend/src/services/download-transfer.ts:15-40
- **证据：** 206 body 的起点、终点和总长度均未校验，错误内容被 append，后验 hash 才失败且不进入网络重试。
- **影响：** 代理/CDN 错误 range 造成重复失败和无效流量。
- **最小修复建议：** 要求 Content-Range 起点等于 offset、总长度一致；不满足时清零并重下。
- **来源 Agent ID：** `a13ac1b256bfb96c0`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — 续传分支仅要求 HTTP 206，不读取 Content-Range；错误区间会被 append，直到后验长度/hash 路径才失败。

### SR-006-018 · Medium · Predownload 完成状态不证明缓存真实、有效或可消费

- **文件路径和行号：** backend/src/services/predownload.ts:22-55；backend/src/services/predownload-status.ts:7-15；backend/src/services/games.ts:54-61,141-152
- **证据：** patch 路径不做 hash；空 build 仍 finished；状态只信任 JSON finished，不比较 tag/chunk 或文件存在。
- **影响：** UI 报告预下载完成但正式更新仍需重下或发现损坏。
- **最小修复建议：** 完成前验证全部 cache；状态读取按目标 tag/manifest 重算并清除失效 marker。
- **来源 Agent ID：** `a13ac1b256bfb96c0,aaafc43df23ba7f9b,a47ea12bbc6dc7390,a7f0bef8a45fbb811`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — patch predownload 只按长度下载并 rename、不做 xxhash；空 build 仍写 finished，readPredownloadStatus 又只反序列化 marker，不核对文件/tag 清单。

### SR-006-019 · Medium · 下载进度可出现 done>total、1/0 或共享 chunk 永远不满

- **文件路径和行号：** backend/src/services/download-transfer.ts:42-53；backend/src/services/job-progress.ts:9-32；backend/src/services/games.ts:77-82
- **证据：** 最后一次超读在抛错前跳过清理；chunk total 按引用数，completed 按名称去重且 patch 不计 total。
- **影响：** 终态快照自相矛盾并保留 oversized .part，前端无法可靠解释进度。
- **最小修复建议：** 统一唯一资源计数口径，夹紧 bytes，完成时移除 active；错误前总是清理非法 part。
- **来源 Agent ID：** `a13ac1b256bfb96c0`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — 第六次 oversized 响应会在 catch 的清理分支前抛出并留下超量进度/part；chunks_total 按引用计数而 completed 用名称 Set，patch job 又未计入 total。

### SR-006-020 · Medium · 本地 EACCES/ENOSPC 等错误被当作网络瞬时错误重试

- **文件路径和行号：** backend/src/services/download-transfer.ts:22-53
- **证据：** 通用 catch 仅特判 AbortError，open/write/close 文件错误也指数退避并重新 fetch。
- **影响：** 浪费网络和时间，错误分类误导，残留 part 参与后续 Range。
- **最小修复建议：** 按错误域分类；本地不可恢复错误立即失败并返回 storage-specific code。
- **来源 Agent ID：** `a13ac1b256bfb96c0`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — streamDownload 的通用 catch 包含 open/write/close 等本地异常，除 AbortError 外统一网络重试并最终包装为 502 download_failed。

### SR-006-021 · Medium · 生产 predownload 的 full chunks 常不会被正式 diff patch 更新消费

- **文件路径和行号：** backend/src/providers/sophon.ts:31-48,60-74；backend/src/services/games.ts:117-118,149-150
- **证据：** 预下载固定 fullBuild/chunks；正式通道若存在 diff_tags 则 installPatches 消费 patch IDs。
- **影响：** 预下载成功仍在正式更新时重新下载，之后缓存被整体删除。
- **最小修复建议：** 预下载应选择与最终 update 相同的 build kind，或让 update 能复用 full chunks。
- **来源 Agent ID：** `aaafc43df23ba7f9b`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — predownloadBuild 固定 fullBuild/chunks，而正式 build 在 diff_tags 命中时固定 patchBuild/patch IDs；run 成功后递归删除版本 cache，二者没有复用桥接。

### SR-006-022 · Medium · 磁盘空间计算从不扣除已下载缓存

- **文件路径和行号：** backend/src/services/disk-space.ts:17-20；backend/src/services/games.ts:45-52,74-75
- **证据：** alreadyDownloadedBytes 参数有测试但所有生产调用只传两个参数。
- **影响：** 已有完整 chunk/patch 仍按全量空间拒绝任务。
- **最小修复建议：** 扫描并校验可复用缓存后传入真实已下载字节；避免未验证 part 抵扣。
- **来源 Agent ID：** `aaafc43df23ba7f9b`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — diskSpaceInfo 支持 alreadyDownloadedBytes，但 GameService.state/start/spaceCheck 的生产调用均只传 path 与全量 size。

### SR-006-023 · Medium · Sophon 元数据/manifest 无压缩与解压大小上限

- **文件路径和行号：** backend/src/providers/sophon.ts:99-106,114
- **证据：** response.json/arrayBuffer 全量缓冲，zstd 同步解压且无输出上限，完整性校验在内存分配之后。
- **影响：** 超大响应或高压缩比数据耗尽内存/阻塞事件循环。
- **最小修复建议：** 流式限长读取，解压设置最大输出和条目数，再执行 hash/schema。
- **来源 Agent ID：** `a7f0bef8a45fbb811`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — metadata 使用 response.json，manifest 使用 arrayBuffer 后同步 zstdDecompressSync；两条路径都在完整缓冲/解压前没有 byte/output/entry 上限。

### SR-006-024 · Low · Legacy segment.filename 可逃逸 cache 并覆盖任意文件

- **文件路径和行号：** backend/src/services/games.ts:120-122；backend/src/services/download.ts:24-28；backend/src/providers/fixture.ts:48-49
- **证据：** fixture legacy build 的 filename 未调用 safeTarget，join(cache,"../../target") 写 part 并在 MD5 通过后 rename。
- **影响：** 受支持 fixture 模式下以 provider 内容覆盖 cache 外文件。
- **最小修复建议：** 把 filename 限制为 basename，并验证 target 位于 cache；fixture 输入同样使用 schema。
- **来源 Agent ID：** `ac1b91725518d4897`
- **置信度：** 高
- **是否需要人工验证：** 否（默认 live 不生产 segments，但配置模式可达）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — 路径缺陷存在，但 segments 只由显式 MHG_PROVIDER_MODE=fixture 的本地 FixtureProvider 产生；同 UID 本地 fixture 控制者已可写目标，故降为 Low。

### SR-006-025 · Low · Legacy ZIP 缺少完整 manifest 也可被标记为成功安装

- **文件路径和行号：** backend/src/services/installer.ts:26-33；backend/src/services/games.ts:120-132
- **证据：** mhg-manifest.json 不存在时 verify 直接返回，只要存在名为 YuanShen.exe 的对象即可写版本并 activate。
- **影响：** 单文件或不完整 ZIP 被记录为完整版本，更新形成混合树。
- **最小修复建议：** Legacy 包必须携带签名/固定完整文件清单；YuanShen.exe 必须是普通文件并校验摘要。
- **来源 Agent ID：** `ac1b91725518d4897`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — verify 在缺少 mhg-manifest.json 时直接成功且只剩 YuanShen.exe 存在性后置条件；该 segments/ZIP 分支同样仅 fixture 模式可达，故降为 Low。

## #7 游戏启动与秘密

### SR-007-001 · High · 关闭 Launcher 会丢失活动游戏所有权并中断 DLL 恢复生命周期

- **文件路径和行号：** frontend/Sources/MHGLauncherApp.swift:15-18,149-155；backend/server.ts:20-37；backend/src/services/game-launch-process.ts:45-70；backend/src/services/game-launch-recovery.ts:7-29
- **证据：** Wine 子进程 detached/unref；shutdown 只关 HTTP/DB，不 abort launch。重启时 Map 为空，游戏仍运行则 recovery 只跳过一次。
- **影响：** 停止按钮和轮询消失，游戏退出后无人恢复 DLL；重启后资源任务/再次启动可与旧游戏冲突。
- **最小修复建议：** shutdown 协调活动 launch：持久化 owner、等待/停止进程和恢复 DLL；重启应重新附着或持续监测 recovery。
- **来源 Agent ID：** `a5d1d3040929aafd7,a13d08d6b4684ab08,a6e392db2ba6a87dc,ada0a1317e1a1193b`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — 窗口关闭会 terminate 后端；shutdown 只关闭 HTTP/DB/socket，Wine child 已 detached+unref。重启构造器仅调用一次 recovery，检测游戏仍运行时直接跳过且不再监测。

### SR-007-002 · High · wineserver 停止失败仍报告 stopped 并恢复 DLL

- **文件路径和行号：** backend/src/services/game-launch-process.ts:64-69,130-134；backend/src/services/game-launches.ts:68-92
- **证据：** spawnSync -k/-w 的 status/error 被忽略，abort handler 无条件 resolve(0)。
- **影响：** 旧游戏可能仍运行，UI 允许新任务，DLL 在被使用时恢复。
- **最小修复建议：** 检查每个命令结果并确认目标进程退出；失败保持 stopping/failed 且不恢复 DLL。
- **来源 Agent ID：** `a13d08d6b4684ab08`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — abort handler 无条件调用忽略 status/error 的 wineserver -k/-w 后 resolve(0)；execute 因 launch 已 stopping 而发布 stopped 并立即 restore DLL。

### SR-007-003 · High · Launch 状态持久化失败不原子，可留下永久 busy 或失控游戏

- **文件路径和行号：** backend/src/services/game-launches.ts:44-53,76-110,163-170；backend/src/services/game-launch-process.ts:42-69
- **证据：** Map 先 set 再 persist；spawn/unref 后 reporter persist 早于 listener 安装；persisted cache 又先于文件写入更新。
- **影响：** 客户端拿不到 ID 但服务永久 busy，或游戏继续运行却丢失监听/DLL 事务状态。
- **最小修复建议：** 先持久化 prepared record 再发布 Map；spawn 后立即安装 listener；持久化失败必须补偿/终止子进程。
- **来源 Agent ID：** `a13d08d6b4684ab08`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — start 先写 Map/notifier 再 persist；persist 抛错会留下永久 preparing。child unref 后 reporter persist 又发生在 exit/error listener 安装前，persisted cache 也先于磁盘写更新。

### SR-007-004 · Medium · Launch 轮询一次 transport 错误即永久脱离

- **文件路径和行号：** frontend/Sources/State/GameActions.swift:136-172；frontend/Sources/Views/GameLaunchControls.swift:35-40,68-71
- **证据：** 未保存的 Task 在任一 socket 错误后 catch 返回，无重试、重附着或清理陈旧 gameLaunch。
- **影响：** UI 长期停在旧非终态并禁用启动；真实游戏与状态分离。
- **最小修复建议：** 保存轮询所有权，区分瞬时错误并重试；后端恢复后按持久 session 重新附着。
- **来源 Agent ID：** `a13d08d6b4684ab08`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — Swift pollLaunch 的唯一 do/catch 在任一 transport 错误后设置 message 并返回；Task 未保存、无 retry/re-attach，非终态 gameLaunch 保留。

### SR-007-005 · High · mhypbase.dll 先替换、后持久 journal，存在不可恢复崩溃窗口

- **文件路径和行号：** backend/src/services/game-launch-files.ts:22-40；backend/src/services/game-launch-recovery.ts:13-19
- **证据：** 原 DLL 已备份并替换后才写 dll-journal.json；SIGKILL/掉电落在中间时恢复扫描看不到事务。
- **影响：** 兼容 DLL 永久留在游戏目录，原文件成为孤立备份。
- **最小修复建议：** 先持久化包含 planned target/backup 的 journal 并 fsync，再执行替换；恢复识别 prepared/committed 两阶段。
- **来源 Agent ID：** `ac1b91725518d4897,a13d08d6b4684ab08,ada0a1317e1a1193b,a8956da2040afb49e`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — prepareDll 在 journal 写入前已备份并替换 target；writeAtomic/copyAtomic 只 fsync 文件、不 fsync 父目录，进一步确认掉电时 journal 与 rename 顺序没有 durable commit 边界。

### SR-007-006 · High · 正常恢复不消费旧 journal，后续中断可用旧备份回滚新 DLL

- **文件路径和行号：** backend/src/services/game-launches.ts:88-96；backend/src/services/game-launch-recovery.ts:11-19；backend/src/services/game-launch-files.ts:44-55
- **证据：** 成功路径 restoreDll 后 journal 留存；多 session 恢复顺序未排序，旧 journal 在目标为注入摘要时再次生效。
- **影响：** 后来更新的新原 DLL 可被更旧备份覆盖。
- **最小修复建议：** 成功恢复后原子标记/删除 journal；journal 带 generation 与原目标身份，只恢复最新未完成事务。
- **来源 Agent ID：** `ada0a1317e1a1193b`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — 正常 execute 调 restoreDll 后不删除/重命名 journal；启动恢复按 readdir 未排序处理旧 journal，目标再次处于 replacement 摘要时旧备份可重新生效。

### SR-007-007 · High · restoreDll 的第二次文件系统错误逃出 catch 并留下非终态会话

- **文件路径和行号：** backend/src/services/game-launches.ts:76-102；backend/src/services/game-launch-files.ts:44-55
- **证据：** 正常 restore 抛错进入 catch，catch 再调同一 restore；第二次错误无外层捕获，execute 又以 void 启动。
- **影响：** launch 保持 running/preparing、服务永久 busy，DLL 可能继续注入。
- **最小修复建议：** 用单一 finally 状态机捕获所有恢复错误；无论恢复成功与否都发布明确终态和可重试 recovery。
- **来源 Agent ID：** `ada0a1317e1a1193b`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — try 中 restoreDll 抛错会进入 catch，catch 无保护地再次调用同一函数；第二次异常虽执行 finally，但不会发布 failed/stopped 终态。

### SR-007-008 · Medium · 启动恢复未成功也消费 journal，warning 又被调用方丢弃

- **文件路径和行号：** backend/src/services/game-launch-recovery.ts:17-20；backend/src/services/game-launches.ts:27-33；backend/src/services/game-launch-files.ts:46-52
- **证据：** backup 校验失败或目标被修改时 restore 返回 warning，但 journal 仍 rename 为 .restored，构造器忽略 warnings。
- **影响：** 暂态可恢复失败失去自动重试入口，用户不知道 DLL 未恢复。
- **最小修复建议：** 仅在 confirmed restored/intentional superseded 时消费 journal；持久化并向前端呈现 recovery warning。
- **来源 Agent ID：** `ada0a1317e1a1193b`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — recoverInterruptedDlls 无论 restoreDll 返回何种 warning 都把 journal rename 为 `.restored`；构造器调用者丢弃 warnings，失败既不重试也不展示。

### SR-007-009 · Low · DLL 恢复不保留原权限模式

- **文件路径和行号：** backend/src/services/game-launch-files.ts:16-18,32-35,51-54,76-80
- **证据：** backup 被强制 chmod 0600，journal 不记录原 mode；restore 从 backup mode 复制。
- **影响：** 原 0644/0700 等权限被改成 0600，其他合法读取上下文失效。
- **最小修复建议：** journal 记录原 mode/ownership 元数据，恢复后显式还原。
- **来源 Agent ID：** `ada0a1317e1a1193b`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — prepare 时 backup 被强制写为 0600，journal 不记录原 mode，restore 又读取 backup 的 0600 写回；问题确认但通常不阻止同用户游戏读取，降为 Low。

### SR-007-010 · High · 长期账号凭据被复制到持久 Wine 注册表且 logout 不清除

- **文件路径和行号：** frontend/Sources/State/LauncherStore.swift:168-173；backend/src/services/game-account-registry.ts:15-50；backend/src/services/game-launch-process.ts:21-34
- **证据：** cookie_token/stoken/ltoken 从 Keychain 写入持久 prefix，退出游戏、Launcher logout 和后端 shutdown 均不删除。
- **影响：** 同用户进程可绕过 Keychain ACL 读取普通 prefix 文件；UI 已注销但游戏凭据副本长期存在。
- **最小修复建议：** 明确产品策略；默认使用会话级注册表并在退出/logout 清理，若保留则提供可见选项和安全说明。
- **来源 Agent ID：** `a6e392db2ba6a87dc`
- **置信度：** 高
- **是否需要人工验证：** 否（批次 A 已确认代码路径；动态环境仅影响影响量级）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — registry value 明确包含 cookie_token/stoken/accessToken 且写入固定持久 wineprefix；游戏退出、后端 shutdown 与前端 logout 仅清 Keychain/内存，没有 registry delete。

### SR-007-011 · Medium · 临时 auth ticket 通过游戏进程 argv 暴露

- **文件路径和行号：** backend/src/providers/live.ts:128-135；backend/src/services/game-launch-process.ts:43-46
- **证据：** ticket 拼为 login_auth_ticket=... 命令行参数并在进程存续期可被同用户进程检查。
- **影响：** 临时认证票据暴露窗口扩大。
- **最小修复建议：** 优先使用受限权限的临时文件、匿名管道或游戏支持的安全 IPC；记录并限制 TTL。
- **来源 Agent ID：** `a6e392db2ba6a87dc`
- **置信度：** 高
- **是否需要人工验证：** 否（批次 A 已确认代码路径；动态环境仅影响影响量级）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — auth ticket 被直接拼入 Wine child argv；非沙箱同 UID 进程可在进程存续期观察命令行，TTL 只影响暴露时长、不影响代码路径成立。

### SR-007-012 · Medium · 游戏 stdout/stderr 无条件持久写盘且无 redaction/轮转

- **文件路径和行号：** backend/src/services/game-launch-process.ts:38-47；backend/src/services/game-launches.ts:131-170；frontend/Sources/Views/GameLaunchProgressView.swift:20-43
- **证据：** 即使 wine_log=false 仍 append 共享日志；开启后原始行进入 status/UI，仅截长不脱敏，文件和 session 无清理上限。
- **影响：** 若 Wine/游戏打印 ticket 或账号信息，临时秘密被持久化并展示；日志无限增长。
- **最小修复建议：** 默认丢弃或按会话轮转；对 token/cookie/ticket 做结构化 redaction，终态清理旧日志。
- **来源 Agent ID：** `a6e392db2ba6a87dc`
- **置信度：** 高
- **是否需要人工验证：** 否（批次 A 已确认代码路径；动态环境仅影响影响量级）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — wine_log=false 仍以 append 打开共享 game-launch.log；true 时原始行进入 session/UI。两者都无轮转/redaction，持久化与无限增长已确认，秘密内容影响保持条件式。

### SR-007-013 · High · 游戏启动未验证请求 credential 属于当前选中账号

- **文件路径和行号：** backend/src/api/router.ts:84-87；backend/src/providers/live.ts:128-135；backend/src/services/game-account-registry.ts:24-50
- **证据：** ticket 由请求 credential 生成，registry 元数据来自 accounts.get；两者没有 identity binding。
- **影响：** 可形成账号 B 元数据 + 账号 A token/ticket 的矛盾登录状态并污染共享 Wine registry。
- **最小修复建议：** 后端从选中 aid 的可信 credential reference 取凭据，或从 credential 派生身份并与 selected account 严格比较。
- **来源 Agent ID：** `a90d0168c4ea8bbc3,a6e392db2ba6a87dc,a93ac8c67b9eff720`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — API route 分别从 accounts.get 取当前账号元数据、从请求 credential 创建 ticket/registry account；两者之间没有 aid/mid 绑定，正常竞态或已授权本地请求均可传入不匹配凭据。

### SR-007-014 · High · 无 timeout 的同步 Wine/探针命令可冻结后端事件循环

- **文件路径和行号：** backend/src/services/game-launch-process.ts:36-37,56-63,73-134；backend/src/services/game-account-registry.ts:15-21
- **证据：** wineboot、wineserver、registry、locale/Retina 配置与 25ms 窗口探针均使用无 timeout 的 spawnSync；任一子命令不退出时，Node 事件循环无法处理 HTTP stop、abort 或 30 秒 fallback。
- **影响：** 后端可无限无响应，活动 launch 与 DLL 事务长期悬挂，前端也无法发送停止请求。
- **最小修复建议：** 改用可取消的异步子进程，分别设置 deadline/kill；窗口探针禁止在高频 timer 内同步 spawn。
- **来源 Agent ID：** `a13d08d6b4684ab08`
- **置信度：** 高
- **是否需要人工验证：** 否（批次 A 已确认同步阻塞路径；建议补挂起 runner 测试）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — 由原 SR-C-001 提升；所有引用的 spawnSync 均无 timeout，且在主事件循环直接执行。

### SR-007-015 · Medium · DLL target 与固定 PID 临时文件未强制 regular/no-follow

- **文件路径和行号：** backend/src/services/game-launch-files.ts:22-40,44-55,72-85
- **证据：** prepare/restore 对 target 仅 exists/hash/copy，没有 lstat regular-file gate；symlink 会被跟随，hardlink 关系在替换恢复后丢失，FIFO/device 可能在同步 hash/copy 阻塞。copyAtomic/writeAtomic 又使用可预测的 `<target>.<pid>.tmp`，没有 O_EXCL/O_NOFOLLOW，预置链接可影响 referent。
- **影响：** 非普通 DLL 或预置临时链接可造成后端挂起、对象语义丢失或覆盖非预期文件；同 UID 威胁模型限制安全影响但不消除恢复正确性问题。
- **最小修复建议：** target/backup 必须 lstat 为普通文件；临时文件使用随机名加 O_CREAT|O_EXCL|O_NOFOLLOW，并在 rename 前复核 inode/type。
- **来源 Agent ID：** `ada0a1317e1a1193b`
- **置信度：** 高
- **是否需要人工验证：** 否（批次 A 已确认文件类型与创建 flag 缺口）
- **批次 A 交叉验证（2026-07-13）：** `CONFIRMED` — 合并原 SR-C-003 与 SR-C-005；二者属于同一 no-follow/对象类型不变量。

## #8 API、数据库与 Cloud

### SR-008-001 · Medium · Cloud 把 gacha URL 查询 UID 当作已验证所有权

- **文件路径和行号：** cloud/src/auth.ts:12-19；cloud/src/router.ts:25-29；backend/src/providers/live-game-record.ts:45-55
- **证据：** caller-controlled uid 优先于 response item UID，并把返回记录重标为该 UID 后签发 session。
- **影响：** 若上游容忍冲突参数，攻击者可获得其他租户 session 并读写/删除其记录。
- **最小修复建议：** 身份只能来自经过验证的上游响应；拒绝 query/response UID 不一致并移除多余 UID 参数。
- **来源 Agent ID：** `a5905b20fe949d83e,a7cbefb003c896363,a29eaa66e0fac874a,af907af269a1fcfda`
- **置信度：** 高
- **是否需要人工验证：** 否（批次 C 已确认代码信任边界；上游冲突 UID 行为仅影响可利用性量级）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — verifyGachaUrl 优先采用调用方 URL 中的 uid/game_uid/role_id，并把所有响应项重标为该值后 issue session；信任边界缺陷确定，但跨租户实际利用依赖官方 endpoint 是否接受冲突 UID，故降为 Medium。

### SR-008-002 · High · Cloud 接受 HTTP gacha URL，authkey 可明文发送

- **文件路径和行号：** cloud/src/router.ts:7,25-33；cloud/src/auth.ts:8-13
- **证据：** 只校验 hostname/authkey，不要求 https:；初始 HTTP 请求在任何 redirect 前已携带 secret。
- **影响：** 网络观察者可窃取 authkey，主动中间人可伪造 ownership proof。
- **最小修复建议：** 仅允许 https，禁用跨协议/跨主机 redirect，并在 fetch 前重建允许的 URL。
- **来源 Agent ID：** `a5905b20fe949d83e,a7cbefb003c896363,a29eaa66e0fac874a`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — URL 校验只限制 hostname/authkey，不限制 protocol；fetch 会直接请求 caller 提供的 http URL，authkey 已在首次明文请求中发送，redirect 发生前即暴露。

### SR-008-003 · Medium · Cloud session 无绝对过期、撤销或重新认证轮换

- **文件路径和行号：** cloud/src/db.ts:5-7；cloud/src/auth.ts:22-48；cloud/src/router.ts:24-54
- **证据：** token hash 永久有效读权限；reverify 更新同一 token 的时间，不旋转或废止旧 session。
- **影响：** 被复制 token 可无限期读取，合法用户重新验证还会恢复其写/删权限。
- **最小修复建议：** 设置绝对/空闲 TTL、token rotation 和 logout/revoke；认证新 session 时可按策略废止旧 token。
- **来源 Agent ID：** `a7cbefb003c896363`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — requireSession 只按 token hash 查询且不检查 created_at/reverified_at；24 小时 freshness 仅用于写/删，reverify 更新原 token 而不轮换，且没有 revoke/logout route。

### SR-008-004 · Medium · Cloud upload 无 item runtime schema 并原样 round-trip JSONB

- **文件路径和行号：** cloud/src/router.ts:8-9,44-46；cloud/src/gacha.ts:3-24；backend/src/services/cloud-sync.ts:51-55
- **证据：** items 是 z.array(z.any())；只检查 truthy id/同 UID，payload 原样保存，消费者把 unknown[] 强转 WishRecord。
- **影响：** 持久契约损坏、pool/rank/type/time 错乱，后续 Swift/TS 解码或统计失败。
- **最小修复建议：** 建立共享 CloudWish schema，规范化后再入库；retrieve 再验证历史 payload。
- **来源 Agent ID：** `a5905b20fe949d83e,aebcc725a3c472a71,a07aba7aef5937c4a,a29eaa66e0fac874a`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — uploadBody 明确为 z.array(z.any)，gacha.upload 只检查 uid/id truthy 后原样写 payload JSONB；retrieve 返回 payload，local CloudSyncService 再把 unknown[] 强转 WishRecord 保存。

### SR-008-005 · Medium · Cloud 把数据库/运行时内部异常原文返回客户端

- **文件路径和行号：** cloud/src/http.ts:11-14；cloud/src/gacha.ts:8-19；backend/src/services/cloud-sync.ts:70-77
- **证据：** null item TypeError、PostgreSQL cast/constraint/deadlock、解析错误均以 raw message 返回，local proxy 继续透传。
- **影响：** 泄露实现细节并把客户端输入问题误标 500。
- **最小修复建议：** 只向客户端返回稳定 code/通用 message；详细错误仅写受控服务日志。
- **来源 Agent ID：** `a5905b20fe949d83e,af907af269a1fcfda,a07aba7aef5937c4a,a29eaa66e0fac874a`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — Cloud fail 对非 HttpError 直接回传 Error.message；null item、PostgreSQL cast/constraint/deadlock 等错误均可到达该分支，本地 proxy 又把 message 作为 cloud_error 透传。

### SR-008-006 · Medium · Cloud gacha 时间语义依赖 PostgreSQL session timezone

- **文件路径和行号：** cloud/src/auth.ts:54-58；cloud/src/db.ts:7；cloud/src/gacha.ts:22-34；frontend/Sources/Models/CompanionModels.swift:3-13
- **证据：** 官方无时区字符串写入 TIMESTAMPTZ 时按部署 timezone 解释，JSONB 又保留无时区原文；Swift 明确按 GMT+8 解码。
- **影响：** 同一记录在 Cloud entries 与 Swift/retrieve 中可相差八小时。
- **最小修复建议：** 入口明确按 Asia/Shanghai 解析并存 UTC，同时返回带时区的 ISO 8601；数据库连接固定 timezone。
- **来源 Agent ID：** `a5905b20fe949d83e,a07aba7aef5937c4a`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — Cloud 把无 offset 的 `yyyy-MM-ddTHH:mm:ss` 直接绑定 TIMESTAMPTZ，连接没有 SET TIME ZONE；payload 保留原文，而 Swift fallback 固定 GMT+8，部署 timezone 可造成两套时间语义。

### SR-008-007 · Medium · Wish/Gacha 数字 ID 以 TEXT 排序和 MAX，checkpoint 与 pity 可错误

- **文件路径和行号：** backend/src/services/wishes.ts:19-20,47-56,83-86；cloud/src/gacha.ts:22-29；backend/src/services/uigf.ts:6-8
- **证据：** 可变长度数字字符串 9 与 10 按词法顺序相反；同时间记录的统计和 MAX(id) 直接使用文本。
- **影响：** 同步 checkpoint 回退、历史顺序和 pity 计算错误，Cloud end-id 返回较小数字。
- **最小修复建议：** 验证固定宽度，或用任意精度 numeric/长度+文本排序表达数字顺序。
- **来源 Agent ID：** `a5905b20fe949d83e,a07aba7aef5937c4a,a6a5927ee99cb274c`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — SQLite MAX/ORDER BY 与 PostgreSQL MAX(id) 都直接作用于 TEXT；UIGF 允许 1–19 位数字 ID，因此 9/10 等可达输入会产生词法而非数值顺序。

### SR-008-008 · Medium · 首次数据库初始化失败会永久毒化 Cloud 进程

- **文件路径和行号：** cloud/src/db.ts:17-22；cloud/src/router.ts:13；cloud/app/health/route.ts:1-3
- **证据：** rejected promise 保存在 globalThis.mhgCloudReady，后续请求复用同一拒绝，不重试；health 仍 200。
- **影响：** 数据库恢复后 API 仍不可用直到重启，健康检查误报。
- **最小修复建议：** 初始化失败时清除缓存 promise并指数重试；health 必须反映 ready 状态。
- **来源 Agent ID：** `af907af269a1fcfda,a07aba7aef5937c4a`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — ready 使用 `globalThis.mhgCloudReady ??=` 缓存首次 promise；reject 后不会清空，所有后续请求复用同一 rejection，而独立 health route 始终返回 ok。

### SR-008-009 · High · Cloud migration 版本表只写不读，可把不兼容 schema 标记为最新

- **文件路径和行号：** cloud/src/db.ts:3-21；cloud/src/gacha.ts:8-25
- **证据：** CREATE TABLE IF NOT EXISTS 只检查表名，缺列/错类型不会修复，却仍插入 v1/v2 marker。
- **影响：** 漂移或旧部署被永久记录为 current，上传失败或 retrieve 返回错误结构。
- **最小修复建议：** 读取 migration ledger，按版本执行事务化 ALTER/验证；启动时 introspect 必需列、类型和约束。
- **来源 Agent ID：** `a07aba7aef5937c4a`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — Cloud 启动只执行 CREATE IF NOT EXISTS 和 INSERT markers，从不读取 ledger 决定迁移；同名旧表缺列/错类型时 CREATE no-op，仍会写 v1/v2。

### SR-008-010 · Medium · Cloud destructive migration 与版本 marker 分属独立 autocommit

- **文件路径和行号：** cloud/src/db.ts:17-21
- **证据：** DROP cycle_records 成功后 version 2 insert 可失败，没有事务包裹。
- **影响：** 迁移报告失败但数据已删除，且初始化 promise 随后永久拒绝。
- **最小修复建议：** 每个 migration 和 marker 必须在同一数据库事务内执行。
- **来源 Agent ID：** `a07aba7aef5937c4a`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — DROP cycle_records 与 INSERT version 2 是两个独立 pool.query，没有 BEGIN/COMMIT；前者成功而后者失败时数据删除已提交且 ready promise 永久 rejected。

### SR-008-011 · Medium · 并发 Cloud upload 按调用方顺序加锁，可发生 PostgreSQL deadlock

- **文件路径和行号：** cloud/src/router.ts:44-46；cloud/src/gacha.ts:8-18
- **证据：** 两个 batch 分别按 [A,B] 与 [B,A] 顺序 upsert，同一事务内形成相反 row lock 顺序；无 40P01 重试。
- **影响：** 一个完整同步批次回滚并以 500 失败。
- **最小修复建议：** 入库前按稳定复合键排序/去重，并对 deadlock/serialization failure 做有限重试。
- **来源 Agent ID：** `a07aba7aef5937c4a`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — upload 在单事务中按 caller items 顺序逐行 upsert；并发 [A,B] 与 [B,A] 会以相反顺序获取相同复合主键行锁，代码没有排序、去重或 40P01 retry。

### SR-008-012 · High · 本地 wishes 以全局 id 为主键，跨 UID 冲突会丢失并污染记录

- **文件路径和行号：** backend/src/core/database.ts:11；backend/src/services/wishes.ts:32-42,89-94
- **证据：** schema 是 id TEXT PRIMARY KEY，upsert conflict 也只按 id；B 的相同 id 不插入且部分字段覆盖 A。
- **影响：** B 丢记录，A 混入 B 元数据，列表/统计/export/cloud upload 均不完整。
- **最小修复建议：** 迁移为 PRIMARY KEY(uid,id)，所有 conflict/checkpoint/dedup 查询同时按 UID。
- **来源 Agent ID：** `aebcc725a3c472a71,ad9c4bf8f5ab19253,a6a5927ee99cb274c`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — SQLite wishes 的唯一键与 ON CONFLICT 都只有 id；UIGF 可为不同 UID 导入相同合法数字 ID，第二条会更新第一条部分字段却保留原 uid，跨 UID 丢失/污染可达。

### SR-008-013 · Medium · SQLite 以原始时间文本排序已接受的多时区 Wish 时间

- **文件路径和行号：** backend/src/core/database.ts:11；backend/src/services/wishes.ts:47-56,83-86；backend/src/services/uigf.ts:43-51
- **证据：** Date.parse 接受不同 offset 表达并原样存 TEXT；SQL 词法排序不等于时间顺序。
- **影响：** 历史、pity、UP cycle、export 顺序错误。
- **最小修复建议：** 导入时规范化为 UTC epoch/ISO Z，数据库按整数时间排序并保留原显示值。
- **来源 Agent ID：** `a6a5927ee99cb274c`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — UIGF 仅用 Date.parse 验证后保存原始 offset/date text；wishes 的 list/statistics/banner SQL 均按 time TEXT 排序，等价时刻的不同表示可被错误排序。

### SR-008-014 · Low · roles 主键是全局 UID 而非账号作用域

- **文件路径和行号：** backend/src/core/database.ts:9；backend/src/services/accounts.ts:73-80；backend/src/providers/fixture.ts:44-46
- **证据：** 模型有 account_aid，但 PRIMARY KEY(uid)；两个账号出现同 UID 时第二次 insert 唯一冲突。
- **影响：** 支持的 fixture 多账号登录失败，数据库无法表达逻辑所有权。
- **最小修复建议：** 改为复合键(account_aid,uid)，并修正选择/更新谓词。
- **来源 Agent ID：** `a6a5927ee99cb274c`
- **置信度：** 高
- **是否需要人工验证：** 否（fixture 模式确定可达；live UID 全局性未写入契约）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — roles 确为 PRIMARY KEY(uid) 而 syncRoles 按 account_aid 重建；但 live UID 按业务全局唯一，确定冲突只在显式 fixture/重复凭据场景，故降为 Low。

### SR-008-015 · Medium · 历史 account/roles SQLite 迁移非事务且不可恢复续跑

- **文件路径和行号：** backend/src/core/database.ts:72-104
- **证据：** rename/create/copy/drop 的旧格式转换不在 transaction；中断后基础 schema 新建空表使迁移谓词误认为已完成。
- **影响：** 账号或角色数据永久表现为丢失，legacy 表成为孤儿或被删除。
- **最小修复建议：** 将旧迁移纳入版本 ledger 和单事务；启动时检测并恢复 account_legacy/roles_legacy。
- **来源 Agent ID：** `a6a5927ee99cb274c,a48968cd5449f9173`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — migrateAccounts 的 ALTER/CREATE/INSERT/DROP exec 没有显式 transaction；中断后 constructor 先执行基础 schema，可新建空正式表并让迁移谓词跳过遗留 *_legacy。

### SR-008-016 · Medium · UIGF 接受 Swift 无法解码的时间并在提交后使该 UID 全部加载失败

- **文件路径和行号：** backend/src/services/uigf.ts:8,43-58；frontend/Sources/Services/APIClient.swift:155-170；frontend/Sources/Models/CompanionModels.swift:3-13
- **证据：** Date.parse 接受 2026-01-01 等 date-only，原文存库；Swift Date decoder 只接受完整 ISO/date-time。
- **影响：** 导入任务已 completed，但 reload 报失败；以后 snapshot 持续解码失败。
- **最小修复建议：** UIGF schema 只接受明确格式并在存储前规范化；对历史数据迁移/隔离坏记录。
- **来源 Agent ID：** `a5e8116a7d76a9e57`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — UIGF 的 Date.parse 接受 date-only，record 原样保存；APIClient 只接受完整 ISO internet date 或 `yyyy-MM-ddTHH:mm:ss`，一个坏 time 会让 snapshot 整体 decode 失败。

### SR-008-017 · Medium · UIGF import 提交 UID 范围与前端完成/重载范围不一致

- **文件路径和行号：** backend/src/services/uigf.ts:12-29；backend/src/services/wish-tasks.ts:27-33；frontend/Sources/State/CompanionActions.swift:112-125
- **证据：** 选中 A 时可导入 B；后端保存 B，前端只 reload A 并用 A 的 count 报成功。无角色首次导入则提交后报 roleMissing。
- **影响：** 用户看到零条/失败但数据库已变化，导入记录隐藏到以后选中对应 UID。
- **最小修复建议：** 导入前展示并确认账户 UID；task 返回按 UID 的计数，前端按导入目标刷新，不依赖 selectedRole。
- **来源 Agent ID：** `a5e8116a7d76a9e57,aebcc725a3c472a71,ad9c4bf8f5ab19253`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — importUIGF 可一次返回任意 UID groups，WishTasks 全部保存并只返回总数；前端完成后 reloadWishes 强制 selectedRole UID，无角色时在提交后抛 roleMissing。

### SR-008-018 · Medium · UIGF 接受空或无意义 UID 并持久化不可达记录

- **文件路径和行号：** backend/src/services/uigf.ts:12-16,43-50；backend/src/services/wishes.ts:32-50
- **证据：** UID 仅 String coercion，无非空/数字格式约束；空字符串满足 SQLite NOT NULL。
- **影响：** 任务成功但正常 UI/API 按真实 role UID 永远查不到，只能全局 clear。
- **最小修复建议：** 要求合法游戏 UID 格式并拒绝空值；导入前验证 account 集合。
- **来源 Agent ID：** `a5e8116a7d76a9e57,aebcc725a3c472a71,ad9c4bf8f5ab19253`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — modern/legacy account uid 仅 z.coerce.string，无 min/regex；空字符串通过并写入 wishes NOT NULL 列，正常 snapshot 始终按真实 role UID 查询不到。

### SR-008-019 · Medium · Live wish 同步遗漏代码库已支持的 gacha type 500

- **文件路径和行号：** backend/src/providers/live.ts:102-117；backend/src/services/uigf.ts:18-19；frontend/Sources/Models/WishHistoryPresentation.swift:113-118
- **证据：** live provider 只迭代 100/200/301/302，其他层明确接受并展示 500。
- **影响：** 同步成功但该池历史和 pity 永久不完整。
- **最小修复建议：** 以共享受支持 pool 集合驱动 provider，同步与 UIGF/UI 使用同一枚举。
- **来源 Agent ID：** `ad9c4bf8f5ab19253`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — LiveProvider.wishes 的迭代集合固定为 100/200/301/302；UIGF schema 与前端 presentation 明确接受 500，因此 live 同步确定不会请求该已支持类型。

### SR-008-020 · Medium · Cloud upload/retrieve 使用 selectedRole 而非已认证 cloud session UID

- **文件路径和行号：** frontend/Sources/State/ValueActions.swift:32-60；frontend/Sources/Views/CloudSyncView.swift:14-38
- **证据：** 登录显示 B session，但操作重新读取 selectedRole A；可能静默 return、报缺凭据或使用仍存的 A token。
- **影响：** 界面显示与实际同步账号不一致，首次无角色时无法取回。
- **最小修复建议：** Cloud 操作绑定显式 session UID/token；若要同步某角色，要求用户确认且验证 UID 一致。
- **来源 Agent ID：** `aebcc725a3c472a71`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — Cloud 登录保存并展示 proof.uid session，但 upload/retrieve 每次重新读取 selectedRole.uid 和对应 Keychain token；切换角色或无角色时会错 UID、缺 token 或静默 return。

### SR-008-021 · Low · 角色详情 path ID 未验证并被 Number 非安全强制转换

- **文件路径和行号：** backend/src/api/router.ts:112-116,139；backend/src/providers/live-game-record.ts:26-31；backend/src/providers/fixture-game-record.ts:17-20
- **证据：** not-a-number 在 fixture 被持久化；live 中 Number 变 NaN，JSON.stringify 发送 null；0x64 等别名被接受。
- **影响：** 创建伪角色记录或向上游发送畸形 ID，错误被误归类为 upstream。
- **最小修复建议：** route schema 要求十进制安全整数范围，并保留 canonical 字符串。
- **来源 Agent ID：** `ae34f5f86f326cdf8`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — route 捕获任意非空 path segment；live 用 Number 可接受 0x/指数别名并把 NaN 序列化为 null，fixture 则直接构造任意 avatarId。影响主要是错误请求/fixture 污染，降为 Low。

### SR-008-022 · Low · Cloud 登录 session 与初始 records 上传不是同一事务

- **文件路径和行号：** cloud/src/router.ts:25-29；cloud/src/auth.ts:22-28；cloud/src/gacha.ts:8-19
- **证据：** issue 已提交后 upload 失败，请求不返回 token，但 session 行永久存在。
- **影响：** 重试可累积客户端无法访问或撤销的孤儿 session。
- **最小修复建议：** 在一个数据库事务内创建 session 和初始记录，或失败时补偿删除 session。
- **来源 Agent ID：** `aebcc725a3c472a71,a07aba7aef5937c4a,af907af269a1fcfda`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — auth/gacha-url 先调用 issue 在独立事务提交 session，随后才调用 gacha.upload；upload 失败时 route 不返回 token，也没有补偿删除已提交 session。

### SR-008-023 · Low · Cloud Authorization parser 接受裸 token 且 Bearer 匹配大小写敏感

- **文件路径和行号：** cloud/src/http.ts:16-19
- **证据：** 缺少 Bearer 前缀时完整 header 仍作为 token；合法小写 bearer 又不能匹配。
- **影响：** 违反协议并可能绕过只针对 Bearer 的中间策略，客户端兼容性不一致。
- **最小修复建议：** 严格、大小写不敏感解析 Bearer scheme，拒绝裸值和额外字段。
- **来源 Agent ID：** `a7cbefb003c896363,a29eaa66e0fac874a,af907af269a1fcfda`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 C 交叉验证（2026-07-13）：** `CONFIRMED` — bearer 仅执行大小写敏感的 `replace(/^Bearer /, "")`；裸 header 保持原值并可匹配 token，小写 bearer 则保留前缀而失败，协议不一致确定成立。

## #9 UI 与可访问性

### SR-009-001 · Medium · 历史筛选后才计算 pity，显示计数被过滤条件破坏

- **文件路径和行号：** frontend/Sources/Views/WishHistoryPanel.swift:15-21,135-166
- **证据：** 先按星级/名称/日期过滤，再把 matches 传给 buildPityEntries；选择五星时中间抽数全部消失。
- **影响：** 每个五星常显示计数 1，用户看到错误 pity。
- **最小修复建议：** 在完整 pool 时间序列上先计算 pity，再对带 pity 的行做显示筛选。
- **来源 Agent ID：** `aac576ca90b176a71`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — filteredRecords 先应用 pool/rank/search/date，再把 matches 交给 buildPityEntries；五星筛选时中间抽数确定消失并把每个五星 pity 重算为 1。错误仅影响展示，降为 Medium。

### SR-009-002 · Medium · 日期控件显示具体值但 optional 过滤实际未启用

- **文件路径和行号：** frontend/Sources/Views/WishHistoryPanel.swift:78-120,143-149
- **证据：** nil 起止日期通过 fallback 显示首条日期/今天；只设置一端时另一端也看似生效。
- **影响：** 用户误以为表格受所见日期范围限制。
- **最小修复建议：** 为未启用端提供显式 toggle/占位状态，或使用非 optional 且始终实际应用的范围。
- **来源 Agent ID：** `aac576ca90b176a71`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — DatePicker 在 nil 时显示 records.first/today 的具体日期，但过滤仅在 optional 非 nil 时执行；特别是只设置一端时，另一端显示值与实际无边界状态不一致。

### SR-009-003 · Medium · 祈愿日期显示与筛选使用不同 timezone

- **文件路径和行号：** frontend/Sources/Views/WishHistoryPanel.swift:22-25,80-126
- **证据：** 表格/DatePicker 使用环境时区，边界计算硬编码 Asia/Shanghai。
- **影响：** 非中国时区、午夜附近记录显示在一天却被另一日筛选。
- **最小修复建议：** 统一使用明确 game timezone 展示和筛选，或全部按用户时区且清晰标注。
- **来源 Agent ID：** `aac576ca90b176a71`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — Table/DatePicker 使用环境时区格式化，而 start/endOfDay 的 Calendar 明确固定 Asia/Shanghai；非中国时区午夜附近记录可见日期与过滤边界分离。

### SR-009-004 · Medium · 自定义选中项只靠视觉样式，VoiceOver 不知当前状态

- **文件路径和行号：** frontend/Sources/Views/HistoryWishViews.swift:8-35,54-60；frontend/Sources/Views/AccountView.swift:50-75,80-103；frontend/Sources/Views/CharactersView.swift:78-92,166-193；frontend/Sources/Views/AchievementsView.swift:130-144；frontend/Sources/Views/AchievementComponents.swift:10-33
- **证据：** 历史池按钮无 accessibility selected/value trait，当前行仅改变背景和描边。补审确认账号/角色切换、角色网格和成就目标按钮也只用 checkmark、颜色、边框与 hover 表示 `selected`，没有 `.isSelected` trait 或 accessibility value。
- **影响：** VoiceOver 用户无法确定哪个 pool 控制详情区、当前账号/角色、当前角色卡或正在过滤的成就目标。
- **最小修复建议：** 为所有选中行添加 accessibilityValue/traits(.isSelected)，并在变化时公告。
- **来源 Agent ID：** `aac576ca90b176a71`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — History、Account、Characters grid 与 Achievement goal 都用普通 Button 加颜色/checkmark/边框表达 selected，引用行段均没有 accessibilityValue 或 `.isSelected` trait。

### SR-009-005 · Low · 五星时间线显式 accessibilityLabel 丢弃可见日期

- **文件路径和行号：** frontend/Sources/Views/WishFiveStarTimeline.swift:58-71
- **证据：** children combine 后自定义 label 只包含名称和 pity，覆盖日期子文本。
- **影响：** VoiceOver 无法获知抽取日期。
- **最小修复建议：** 把日期加入 label/value，或不要覆盖自动组合出的完整文本。
- **来源 Agent ID：** `aac576ca90b176a71`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — timeline 先 combine children，随后显式 accessibilityLabel 仅写 name+pity，覆盖 content 中的可见日期；日期缺失确定但属于辅助信息，降为 Low。

### SR-009-006 · Medium · 无账号/角色时部分 destination 永久显示载入态

- **文件路径和行号：** frontend/Sources/Views/WishesView.swift:16-21；frontend/Sources/Views/WishLoadingPlaceholder.swift:11-12；frontend/Sources/Views/NotificationsView.swift:7-33；frontend/Sources/State/ValueActions.swift:4-20
- **证据：** Wishes 的 companionLoaded 初始 false，无 selectedRole 时 bootstrap 不发请求，也不转 empty/error state。补审确认 Notifications 在 settings 为 nil 时只显示无标签 ProgressView，而 loadValueData 遇到无 selectedRole 会立即 return，因此该页面同样永久停留在载入态。
- **影响：** 用户看不到登录/选择角色引导，也没有可操作的重试或空状态。
- **最小修复建议：** 将 loading、noAccount/noRole、loaded 分成明确状态，空身份显示可操作登录入口。
- **来源 Agent ID：** `a617cef8e48e16482`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — Wishes 以 companionLoaded=false 显示 loading；Notifications 以 settings=nil 显示 ProgressView。无 selectedRole 时相关加载函数直接 return，两页都没有转入登录/空/错误状态。

### SR-009-007 · Medium · Wish operation overlay 仅局部呈现且未建立键盘/无障碍模态性

- **文件路径和行号：** frontend/Sources/Views/WishesView.swift:32-38；frontend/Sources/Views/WishOperationOverlay.swift:10-30；frontend/Sources/MHGLauncherApp.swift:36-40；frontend/Sources/Views/GachaHistoryView.swift:50-86
- **证据：** 从 History/全局命令启动时 overlay 不可见；在 Wishes 中底层元素仍留在 focus/a11y 树，侧栏可导航离开。
- **影响：** 失败操作可无关闭路径地锁住同步入口；键盘/VoiceOver 可激活“模态层”后控件。
- **最小修复建议：** 把 operation presenter 提升到 RootView/window 层；隐藏底层 a11y、约束 focus，并在所有入口可见。
- **来源 Agent ID：** `a034e447a5710200c,a617cef8e48e16482`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — WishOperationOverlay 只挂在 WishesView 局部 overlay；History/菜单可在其他 destination 启动 operation，且 overlay 未隐藏底层 accessibility tree、未约束 focus，侧栏仍可离开。

### SR-009-008 · Medium · 日志自动滚动无视 Reduce Motion

- **文件路径和行号：** frontend/Sources/Views/WishOperationOverlay.swift:115-118；frontend/Sources/Views/GameLaunchProgressView.swift:20-42
- **证据：** Wish operation 每次 logs.count 变化无条件 `withAnimation` scrollTo，虽然同一视图已读取 accessibilityReduceMotion。补审确认游戏启动日志也在每条日志到达时无条件 `withAnimation` 滚到底部，且该视图完全未读取 Reduce Motion。
- **影响：** 开启减少动态效果后，祈愿同步和游戏启动日志仍持续产生垂直滚动动画。
- **最小修复建议：** reduceMotion 时无动画跳转或只更新可访问状态，并让所有日志视图共用同一滚动策略。
- **来源 Agent ID：** `a617cef8e48e16482`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — WishOperationOverlay 与 GameLaunchProgressView 的 logs.count 回调都无条件 `withAnimation { scrollTo }`；前者虽读取 reduceMotion 也未在该路径使用，后者完全未读取。

### SR-009-009 · Medium · 支持的五种卡池无法容纳固定宽度 pool selector

- **文件路径和行号：** frontend/Sources/Views/PoolSelector.swift:18-24,45-53；frontend/Sources/Views/WishesView.swift:116-120
- **证据：** 360pt detail 中非滚动 HStack 至少有四个 48pt 按钮、间距和一个带文字选中项；UIGF 支持第五种 500。
- **影响：** 标签压缩/换行/裁切，池不可发现或难点击。
- **最小修复建议：** 使用自适应 wrapping、Menu/Picker 或横向滚动，并测试五池和长本地化文本。
- **来源 Agent ID：** `a617cef8e48e16482`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — PoolSelector 为不可换行 HStack，五类 pool 中四个图标按钮、一个展开文字按钮及四段 spacing 已达到/超过 Wishes 360pt detail 宽度，长标签会压缩或溢出。

### SR-009-010 · Low · 预先累积的 operation 日志打开时停在最旧条目

- **文件路径和行号：** frontend/Sources/Views/WishOperationOverlay.swift:93-119
- **证据：** scrollTo 只在 onChange(logs.count) 运行；视图首次出现已有日志不会触发。
- **影响：** 最新失败原因藏在折叠区下方，直到手动滚动或新日志到达。
- **最小修复建议：** onAppear/task 初次滚到底，并在用户主动向上查看时避免强制抢滚动。
- **来源 Agent ID：** `a617cef8e48e16482`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — logConsole 只有 logs.count onChange，没有 initial/onAppear scroll；视图首次插入时已存在的日志不会触发，174pt console 从顶部显示旧记录。影响为可恢复的可见性问题，降为 Low。

### SR-009-011 · Low · 重复角色数量可显示不存在的 7 命、8 命

- **文件路径和行号：** frontend/Sources/Views/WishResultsPanel.swift:126-127
- **证据：** constellation 直接 count-1 且无上限，UI 标签使用“命”。
- **影响：** 高重复抽取时展示游戏语义错误。
- **最小修复建议：** 将命座显示 clamp 到 6，并把额外副本单独显示为溢出数量。
- **来源 Agent ID：** `a617cef8e48e16482`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — WishResultItem.constellation 明确为 max(count-1,0) 且 amountText 直接显示“命”，没有上限；同角色 8 次以上记录可显示 7 命及更高。

### SR-009-012 · Low · 缺少前置条件时多个控件保持启用但静默 no-op

- **文件路径和行号：** frontend/Sources/MHGLauncherApp.swift:21-45,63-67,99-103,149-162；frontend/Sources/Views/NotificationsView.swift:20-28；frontend/Sources/Views/CloudSyncView.swift:27-42；frontend/Sources/State/ValueActions.swift:44-60,73-80
- **证据：** Keychain guide 分支没有 focused store，菜单可选链静默返回。补审确认“立即检查”在无 selectedRole 时由 evaluateNotifications 直接 return，Cloud“上传/取回”也在无角色时直接 return，但三个按钮都没有 disabled 条件、解释或反馈。
- **影响：** 键盘和 VoiceOver 用户会遇到外观及语义上可执行、激活后却完全无响应的控件。
- **最小修复建议：** 依据账号、角色、session 和 busy 状态统一 disable，并通过 help/说明文本解释缺少的前置条件；若仍允许激活则必须显示可播报错误。
- **来源 Agent ID：** `ac5c8c8329d910647`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — Keychain guide 无 focused store 时菜单 optional-chain no-op；Notifications evaluate 和 Cloud upload/retrieve 在无 selectedRole 时直接 return，而对应控件没有 disabled/反馈。

### SR-009-013 · Low · 结果卡使用 interactive glass 但没有任何动作

- **文件路径和行号：** frontend/Sources/Views/WishResultsPanel.swift:68-94
- **证据：** 非 Button 的静态卡应用 .glassEffect(...interactive())，无 tap/selection/navigation。
- **影响：** hover/press 反馈暗示可点击，点击却无结果。
- **最小修复建议：** 移除 interactive material，或把卡片实现为有明确动作和可访问名称的控件。
- **来源 Agent ID：** `a034e447a5710200c`
- **置信度：** 高
- **是否需要人工验证：** 否（批次 E 已确认静态卡明确请求 interactive material）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — WishResultCard 不是 Button、没有 gesture/navigation，却显式使用 `.glassEffect(...interactive())`；代码确实请求交互材质反馈，低严重度误导成立。

### SR-009-014 · Medium · Keychain 授权失败写入了当前不可见的 alert 状态

- **文件路径和行号：** frontend/Sources/MHGLauncherApp.swift:136-147；frontend/Sources/Views/RootView.swift:53-63；frontend/Sources/Views/KeychainAccessGuideView.swift:23-30
- **证据：** 授权失败时仍停留在 KeychainAccessGuideView，只设置 `store.message`；展示该 message 的 `.alert` 仅挂在尚未进入视图树的 RootView 上，引导页自身没有错误 UI、焦点目标或重试说明。
- **影响：** 用户点击“继续授权”后若授权失败，界面无任何可见或 VoiceOver 反馈并保持原状，无法判断失败原因。
- **最小修复建议：** 在引导层承载可聚焦、可播报的错误状态，或把授权结果提升到共同 shell 的 alert；失败后恢复焦点到重试按钮。
- **来源 Agent ID：** `主会话-#9-2026-07-13`
- **置信度：** 高
- **是否需要人工验证：** 否（未运行测试；建议覆盖授权拒绝与系统错误）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — Keychain 授权 failure 仅设置 store.message 且保留 guide 分支；展示 message 的 alert 只存在于未挂载的 RootView，引导页没有任何错误/焦点恢复 UI。

### SR-009-015 · Medium · 关键动态状态和进度没有无障碍播报或完整语义

- **文件路径和行号：** frontend/Sources/Views/AccountLoginView.swift:24-63,102-111；frontend/Sources/Views/RootView.swift:39-52；frontend/Sources/Views/RuntimeSetupView.swift:11-35；frontend/Sources/Views/RuntimeStatusView.swift:8-28；frontend/Sources/Views/GameLaunchControls.swift:22-55；frontend/Sources/Views/GameJobCard.swift:17-63,66-74,147-158；frontend/Sources/Views/NotificationsView.swift:7-29；frontend/Sources/Views/NotesView.swift:9-81,89-99；frontend/Sources/Views/CloudSyncView.swift:20-42
- **证据：** QR 阶段、全局 statusMessage、运行时安装/错误、游戏启动状态、资源任务消息、通知载入、便笺刷新值和 Cloud session/message 都以普通 Text/Label 动态替换，仅设置视觉 transition 或 identifier，没有 live-region/announcement。GameJob 的整体和分块进度条还是纯 GeometryReader/Shape，没有 progress role、label 或 value；生成的二维码 Image 也没有 label、hint 或 decorative 隐藏语义。
- **影响：** VoiceOver 焦点停在操作控件时不会可靠获知扫码、启动、安装、通知载入、便笺刷新、Cloud 成功/失败或完成阶段；分块进度完全依赖视觉宽度，二维码还可能只被读作无名称图片。
- **最小修复建议：** 为关键状态设置节流的 live region/announcement，为自绘进度提供 label/value 和 progress 语义，并为二维码提供明确 label/hint 或隐藏重复图片语义。
- **来源 Agent ID：** `主会话-#9-2026-07-13`
- **置信度：** 高
- **是否需要人工验证：** 否（未运行测试；建议以 VoiceOver 自动化/人工回归验证公告时序）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — 引用的 QR、status、runtime、launch、job、notification、note、cloud 状态均无 live-region/announcement；GameJob 自绘 Shape 进度无 label/value/role，动态内容语义缺口确定。

### SR-009-016 · Medium · 忙碌态会把主要操作按钮替换成无名称 spinner

- **文件路径和行号：** frontend/Sources/Views/GameLaunchControls.swift:23-35；frontend/Sources/Views/HomeView.swift:64-90；frontend/Tests/InteractiveSurfaceTests.swift:26-50,99-120
- **证据：** 启动游戏和首页预下载进入 pending 状态后，Button label 分支只剩 `ProgressView`，原“启动游戏/预下载”文本及明确 accessibilityLabel 一并消失。源码扫描测试只检查静态 snippet 中是否出现 Text/Label，无法验证运行时条件分支实际暴露的名称。
- **影响：** VoiceOver 用户在操作后可能只听到无上下文的进度指示器/按钮，无法确认哪个动作正在执行；键盘焦点仍停在该控件时尤为明显。
- **最小修复建议：** 忙碌态始终保留可见或仅无障碍可见的动作名称，并提供“正在启动游戏”“正在准备预下载”等 accessibility label/value。
- **来源 Agent ID：** `主会话-#9-2026-07-13`
- **置信度：** 高
- **是否需要人工验证：** 否（未运行测试；建议渲染各状态后读取 AX 树）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — GameLaunch 与 Home predownload 的 busy 分支把 Button label 完全替换为裸 ProgressView；运行时 AX 名称不再含原动作，静态 scanner 只因另一分支存在 Text/Label 而无法发现。

### SR-009-017 · Medium · 成就勾选框的无障碍名称无法区分对应条目

- **文件路径和行号：** frontend/Sources/Views/AchievementComponents.swift:57-76；frontend/Sources/Views/AchievementsView.swift:147-158
- **证据：** 每一行 Toggle 都隐藏可见 label，并统一覆盖为“完成成就”；名称不包含 `entry.title`、成就 ID 或当前完成状态。VoiceOver 单独聚焦勾选框时，同屏所有控件名称完全相同。
- **影响：** 键盘或 VoiceOver 用户无法可靠判断正在勾选哪个成就，可能修改错误条目；异步重载后也难以确认结果。
- **最小修复建议：** 使用“完成成就：<标题>，ID <id>”作为 label，并通过 value/trait 暴露已完成状态；把说明文本与控件组合为单个可访问行。
- **来源 Agent ID：** `主会话-#9-2026-07-13`
- **置信度：** 高
- **是否需要人工验证：** 否（未运行测试；建议读取多行 Toggle 的 AX 名称）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — 每个 AchievementEntryRow Toggle 都 labelsHidden 后统一 accessibilityLabel“完成成就”，没有 title/id/value；同屏控件的可访问名称不可区分。

### SR-009-018 · Medium · 角色与成就图片组件无法提供替代文本，技能只剩无名称图标和等级

- **文件路径和行号：** frontend/Sources/Views/CachedAsyncImage.swift:26-60；frontend/Sources/Views/CharacterDetailSections.swift:3-24,29-48；frontend/Sources/Views/CharacterDetailView.swift:31-52；frontend/Sources/Views/AchievementComponents.swift:10-42；frontend/Sources/Models/CharacterModels.swift:75-89；frontend/Sources/Views/HistoryWishViews.swift:127-145
- **证据：** CachedAsyncImage API 没有 accessibility label/hidden 参数，最终 `Image(nsImage:)` 也不设置语义。角色技能条仅渲染图标和等级，虽然模型已有 skill.name/desc；角色头像和成就目标图标不能明确隐藏。补充验证确认 HistoryWishIcon 也无可见名称或 accessibilityLabel，仅依赖非交互元素的 `.help`。
- **影响：** VoiceOver 用户无法知道每个技能等级属于哪个技能，并会在角色、命座和成就列表中遇到无意义的“图片”元素。
- **最小修复建议：** 让 CachedAsyncImage 接受 label 或 decorative 模式；技能使用名称和等级组合 label，命座使用名称/激活状态，重复头像与目标图标显式 accessibilityHidden。
- **来源 Agent ID：** `主会话-#9-2026-07-13`
- **置信度：** 高
- **是否需要人工验证：** 否（未运行测试；建议检查远程图与 placeholder 两种 AX 树）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — CachedAsyncImage 无 label/decorative API且 Image(nsImage:)不设语义；技能只显示图标+等级而模型已有 name。HistoryWishIcon 同样仅依赖不可聚焦 `.help`，故合并原 SR-C-008。

### SR-009-019 · Medium · 成就工具栏的固定单行尺寸无法容纳辅助文本缩放

- **文件路径和行号：** frontend/Sources/Views/AchievementsView.swift:35-91；frontend/Sources/MHGLauncherApp.swift:148-159；frontend/Tests/InteractiveSurfaceTests.swift:8-24,53-63
- **证据：** 页面把 header actions 和包含 128 宽布局 picker、至少 260 宽搜索框、190 宽档案 picker、两个 checkbox 与计数的工具栏固定在不可换行 HStack；应用窗口又固定 content size。现有布局测试只在单一 1100×740 默认环境确认 fittingSize 有限，不注入 accessibility Dynamic Type，也不检查截断、重叠或不可达控件。
- **影响：** 放大字体或使用较长档案名时，工具栏只能压缩/截断，后部筛选控件和计数可能不可读或难以操作。
- **最小修复建议：** 按可用宽度切换多行/自适应布局，移除固定 picker 宽度并允许页面滚动；加入 accessibility text size 与长内容快照/布局测试。
- **来源 Agent ID：** `主会话-#9-2026-07-13`
- **置信度：** 高
- **是否需要人工验证：** 否（未运行测试；建议补多档 Dynamic Type 渲染）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — Achievements header/toolbar 是不可换行 HStack，包含固定 128/190 宽 picker、min 260 搜索框、两个 checkbox 和计数；固定 content-size 窗口在默认宽度已接近下限，辅助字体放大可达压缩/截断。

### SR-009-020 · Medium · 提醒时间接受任意文本且无错误状态，非法值会静默禁用提醒

- **文件路径和行号：** frontend/Sources/Views/NotificationsView.swift:13-18,48-65；backend/src/api/value-routes.ts:14-18；backend/src/services/notifications.ts:20-32,59-63
- **证据：** UI 使用普通 TextField 并在每次输入后保存，没有时间格式、范围校验或错误提示；API 只要求任意 string。evaluate 直接 `split(":").map(Number)`，`abc`/`25:99` 等值产生 NaN 或越界数字，比较结果使每日委托提醒永不触发或在错误时刻触发，但设置仍被成功持久化。
- **影响：** 用户看到已启用且已保存的提醒，实际通知长期静默失效，界面没有任何可见或 VoiceOver 错误状态。
- **最小修复建议：** 使用受约束的时间控件或严格 `HH:mm` 校验，前后端共同限制 00:00–23:59；保存失败时保留焦点并显示可播报的字段级错误。
- **来源 Agent ID：** `主会话-#9-2026-07-13`
- **置信度：** 高
- **是否需要人工验证：** 否（未运行测试；建议覆盖非法文本和边界时间）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — 通知时间为任意 TextField，前端 debounce 保存；API 只校验 string，backend split+Number 对 NaN/越界不报错并持久化，提醒比较会静默永不成立或错误成立。

### SR-009-021 · Low · Keychain 引导的 frame 外 padding 会改变固定窗口内容尺寸

- **文件路径和行号：** frontend/Sources/Views/KeychainAccessGuideView.swift:29-30；frontend/Sources/MHGLauncherApp.swift:136-159
- **证据：** 引导页先固定为 1150×750，再在 frame 外添加 32pt padding，向 WindowGroup 请求的内容尺寸成为 1214×814；进入 RootView 后又切回 1150×750，且 windowResizability 为 contentSize。
- **影响：** 授权切换时窗口会改变尺寸；在低高度工作区，引导窗口可能超出可用区域。影响主要为布局与可达性，故定为 Low。
- **最小修复建议：** 把 padding 纳入内部固定 frame，或改用可适配工作区的 min/ideal/max 布局。
- **来源 Agent ID：** `ac5c8c8329d910647`
- **置信度：** 高
- **是否需要人工验证：** 否（批次 E 已确认 SwiftUI modifier 尺寸关系）
- **批次 E 交叉验证（2026-07-13）：** `CONFIRMED` — 由原 SR-C-006 以 Medium→Low 提升为确认项。

## #10 构建发布与供应链

### SR-010-001 · High · 未经校验的 release tag 可让构建脚本 rm -rf 仓库外目录

- **文件路径和行号：** scripts/build-runtime-assets.sh:5-6,82；scripts/publish-runtime-assets.sh:5-6,12
- **证据：** tag 直接拼入输出路径，../../frontend 等规范化后成为任意相对目录；签名检查后执行 rm -rf。
- **影响：** 发布机未提交源码、缓存或用户目录被递归删除。
- **最小修复建议：** tag 只允许严格 semver/slug；realpath 后要求位于固定 build root，删除前验证 ownership marker。
- **来源 Agent ID：** `a367d9b95f4efd400`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 D 交叉验证（2026-07-13）：** `CONFIRMED` — tag 未经任何 slug/semver 校验直接进入 `$root/build/runtime-assets/$tag`；build-runtime-assets 在签名 key 检查后执行 rm -rf，含 `../` 的发布参数可达仓库内外的规范化目录。

### SR-010-002 · High · App 版本与 runtime Release tag 没有发布级绑定

- **文件路径和行号：** packaging/Info.plist:22-25；frontend/Sources/Models/RuntimeModels.swift:36-47；scripts/publish-runtime-assets.sh:5
- **证据：** App 从固定 CFBundleShortVersionString 推导 tag，发布脚本却接受独立自由参数。
- **影响：** 新 App 继续下载旧 runtime，或旧 release 撤下后首次启动失败。
- **最小修复建议：** 发布命令单一版本源同时生成 plist、tag、manifest；构建时断言三者一致。
- **来源 Agent ID：** `a367d9b95f4efd400`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 D 交叉验证（2026-07-13）：** `CONFIRMED` — 客户端只从 CFBundleShortVersionString 推导固定 runtime tag，publish 脚本独立接受任意 tag，build/release 流程没有一致性断言或单一版本源；错配可让整版新安装失败。

### SR-010-003 · High · Publisher 只因 manifest 存在就上传，未验证本地产物集合和摘要

- **文件路径和行号：** scripts/publish-runtime-assets.sh:12,18-19；scripts/build-runtime-assets.sh:82-84,177-183
- **证据：** 旧 manifest 存在时跳过 rebuild，也不重验签名、引用文件、size/hash 或残留资产。
- **影响：** 上传可“成功”但内容陈旧、缺失或与 manifest 不一致，客户端安装失败。
- **最小修复建议：** 发布前总是从干净目录重建，或执行独立 verify-manifest 命令并拒绝未引用/缺失资产。
- **来源 Agent ID：** `a367d9b95f4efd400`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 D 交叉验证（2026-07-13）：** `CONFIRMED` — publish 仅在 manifest 缺失时重建；存在时直接 glob --clobber 上传，不重算签名、size/hash、不检查引用文件或额外残留，陈旧/缺失集合可达。

### SR-010-004 · Medium · 对公开 Release 使用 --clobber 无原子切换或回滚

- **文件路径和行号：** scripts/publish-runtime-assets.sh:14-18
- **证据：** manifest 和多个 archive 独立覆盖，上传中/失败后可形成新旧混合；脚本不检查 release 是否 draft。
- **影响：** 用户在窗口期持续得到 hash 失败，CDN 同 URL 缓存延长故障。
- **最小修复建议：** 禁止修改公开 tag；上传到新 draft tag，完整验证后一次性发布。
- **来源 Agent ID：** `a367d9b95f4efd400`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 D 交叉验证（2026-07-13）：** `CONFIRMED` — 已有 release 无论 draft/public 都直接逐文件 `gh release upload --clobber`；没有 draft 状态检查、全量预验证或回滚，公开 tag 上可出现可观察的新旧混合窗口。

### SR-010-005 · High · better-sqlite3 远程 prebuild 未做内容认证却被项目重新签名

- **文件路径和行号：** scripts/build-runtime-assets.sh:89-112,177-183；backend/node_modules/prebuild-install/download.js:31-118
- **证据：** npm lock 只认证 npm 包；install script 下载 .node 后仅 require 验证可加载，无预期 hash/signature。
- **影响：** 上游/CDN/缓存污染的原生代码被打包并用官方 Ed25519 manifest 背书。
- **最小修复建议：** 禁用远程 prebuild 并从源码可复现构建，或固定每个平台二进制 SHA-256/签名并在打包前验证。
- **来源 Agent ID：** `a7e69a01c80790dfd`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 D 交叉验证（2026-07-13）：** `CONFIRMED` — better-sqlite3 的锁文件只认证 npm tarball；其 install script 调 prebuild-install 从远端/缓存取得 native archive，download.js 仅检查 HTTP 200、解包并 require，可加载即被后续 Ed25519 runtime manifest 重新背书。

### SR-010-006 · Medium · Runtime 资产遗漏 Node 与部分 npm 依赖许可证文本

- **文件路径和行号：** scripts/build-runtime-assets.sh:96-106；backend/node_modules/next/license.md:1；scripts/fetch-node.sh:20-22
- **证据：** Node 组件只复制二进制；node_modules 清理所有 *.md，删除 Next/styled-jsx 等实际 license 文件。
- **影响：** 分发物可能不满足许可证保留义务，无法完整审计第三方声明。
- **最小修复建议：** 构建机器可读 THIRD_PARTY_NOTICES/SBOM，显式收集每个生产依赖和 Node 的许可证。
- **来源 Agent ID：** `a367d9b95f4efd400,a7e69a01c80790dfd`
- **置信度：** 高
- **是否需要人工验证：** 否（批次 D 已确认打包遗漏；最终法律责任不影响技术事实）
- **批次 D 交叉验证（2026-07-13）：** `CONFIRMED` — runtime 构建只复制 Node 可执行文件，并在生产 node_modules 中删除全部 `*.md`；Next 等实际 license.md 被删除，现有 notices 仅覆盖 Wine/DXMT/mhypbase，技术遗漏确定成立。

### SR-010-007 · Medium · README 声称 self-contained/内嵌 Wine，但 App 构建明确排除运行时

- **文件路径和行号：** README.md:32-43；scripts/build-app.sh:24-35,65-69；frontend/Sources/State/LauncherStore.swift:80-101
- **证据：** build-app 断言 Node/GameRuntime 不在 bundle；干净机器首次运行必须联网下载。
- **影响：** 离线或 release 不可用时按文档构建的应用无法启动后端/游戏。
- **最小修复建议：** 修正文档为按需下载，或真正把已审计 runtime 资产打包进 App；加入离线交付测试。
- **来源 Agent ID：** `a7e69a01c80790dfd,ad931c9bf8341b973`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 D 交叉验证（2026-07-13）：** `CONFIRMED` — README 明确称 self-contained 且 bundle 含 Wine/DXMT；build-app 反向断言 Backend/node 与 GameRuntime 不存在，LauncherStore 首次启动必须下载 runtime，文档与交付路径直接矛盾。

### SR-010-008 · Medium · backend typecheck 既依赖未生成 Next routes 又排除 route validator

- **文件路径和行号：** backend/next-env.d.ts:3；.gitignore:19；scripts/test-backend.sh:8-11；backend/package.json:9-13；backend/tsconfig.json:29-41；backend/.next/types/validator.ts:21-37
- **证据：** 干净 checkout 中 `.next` 被忽略，next-env 却静态 import `.next/types/routes.d.ts`；npm ci 后直接 tsc 不会先生成它。已有 `.next` 时，tsconfig include 随即被 exclude `.next` 抵消，next-env 只 import routes.d.ts，不会纳入验证 route handler exports 的 validator.ts。
- **影响：** 独立 typecheck 在干净环境不可复现；有本机残留时又可能通过而 Next build 因 route 契约失败。
- **最小修复建议：** typecheck 前运行受支持的 Next typegen/build，并明确把 validator 纳入同一 gate；不要依赖被忽略的历史 `.next`。
- **来源 Agent ID：** `ad931c9bf8341b973`
- **置信度：** 高
- **是否需要人工验证：** 否（建议补动态回归测试）
- **批次 D 交叉验证（2026-07-13）：** `CONFIRMED` — 干净 checkout 的 next-env.d.ts 导入被 .gitignore 排除且 npm ci 不生成的 routes.d.ts，test-backend 直接 tsc 可失败；生成后 tsconfig 又 exclude 整个 .next，validator.ts 不被独立 typecheck。两项同属一个 Next 生成类型接线缺陷，合并原 SR-010-009 并降为 Medium。

## 交叉验证已删除/合并条目

- `SR-C-002`：合并进 `SR-007-005`；父目录 fsync 是同一 DLL journal 崩溃一致性证据，跨卷 rename 叙述不成立（临时文件与目标同目录）。
- `SR-C-003`、`SR-C-005`：合并并提升为 `SR-007-015`。
- `SR-C-004`：删除为 `DISPUTED`；journal 位于 0700 session 目录并以 0600 原子写入，正常代码没有外部可控写入路径，危害条件仅剩同 UID 主动篡改或非结构化磁盘损坏，而同 UID 已可直接修改这些目标。
- `SR-010-009`：批次 D 合并进 `SR-010-008`；二者是同一 Next 生成类型接线错误在“干净 checkout 失败”和“残留产物假通过”两个环境下的表现。
- `SR-C-008`：批次 E 合并进 `SR-009-018`；History Wish 图标与角色/成就图片共享同一缺少 label/decorative 语义的根因。


## 交叉验证 disputed 条目

### SR-C-007 · DISPUTED · 动画进行中切换 Reduce Motion 是否继续旧 transaction

- **文件路径和行号：** frontend/Sources/Views/MotionSystem.swift:135-154
- **批次 E 结论：** modifier 确实没有显式 onChange，但环境变化会重算 spec，且 appeared 已为最终状态；仅凭源码无法判定 SwiftUI 会继续、替换还是立即完成现有 transaction。在禁止 UI 动态验证的约束下，原“仍完成旧位移/缩放/模糊”描述证据相互不足，标记 `DISPUTED`，不计入确认发现。

## 需人工验证的静态候选（不计入确认总数）

无。

## 验证限制

- 本报告是严格只读静态收敛；没有运行测试、构建、App、后端、Cloud、Wine 或网络请求。
- 405 个 429 Agent 与 8 个其他 API 错误 Agent 不计为成功证据；仅在其范围被上述成功 Agent 实质覆盖时忽略。
- 原任务 #11 已按批次 A–E 对既有条目逐项交叉验证完成；本轮未启动子 Agent，结论仍属于静态代码路径验证，不替代 UI/平台/网络动态回归。
