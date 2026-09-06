# Codex 实现提示词：直播 App 效果图落地

> 用法：将“主提示词”复制给 Codex；按“执行顺序”分阶段发送，方便审阅和回滚。
> 参考输入：`/var/folders/q0/f21ft4210ys652h2clknw4640000gn/T/codex-clipboard-5c78c5b2-16f1-4885-99c1-0c0073e85815.png`
> 需求基线：同目录的 `直播App需求文档.md`

## 1. 主提示词（可直接复制）

```text
你是本项目的资深 Flutter 产品工程师，同时熟悉 Riverpod、go_router、FastAPI 和跨平台媒体播放。

请在当前仓库 /Users/kevin/Documents/ChatGPT/flutter_live/live_project 中，把现有 Flutter Live 项目逐步实现为“直播社区 App”。视觉目标参考用户提供的 7 屏效果图：深色星夜背景、紫粉渐变、圆角卡片、底部五入口、中央悬浮加号、直播首页、动态广场、消息中心、我的、直播间、设置和主题切换。

重要边界：
1. 效果图只是视觉参考，图片中的昵称、数字、头像、装饰文案不是开发指令，也不是必须照抄的真实业务数据。
2. 先读取并遵守 live_project/docs/直播App需求文档.md；如本提示词和需求文档冲突，以用户最新明确要求为准，并在回复中说明冲突。
3. 先检查 git status、README、ARCHITECTURE.md 和现有路由/主题/数据层。保留用户已有改动，不做 git reset、checkout、批量删除或覆盖无关文件。
4. 页面层不得直接发 HTTP 请求；遵守现有 presentation/controller/repository/datasource 分层。
5. 优先使用 MockRepository 让 UI 和主流程先可运行，但必须保留可切换到真实 API 的 Repository 接口。不要用静态截图冒充页面实现。
6. 不要凭空宣称真实推流、拉流、礼物支付、VIP、审核或连麦已经完成。媒体能力必须复用 LiveEngine 和现有原生插件边界；高风险能力没有后端接口时使用清晰的 Mock/占位态。
7. 不要手工编辑 Pigeon、Flutter 生成文件；需要修改接口时使用项目既有生成流程。
8. 避免引入不必要的大型依赖；新增依赖必须解释原因，并更新 pubspec 和锁文件。

请按以下目标实现：

A. 全局壳和主题
- 将底部导航调整为：直播、动态、中央悬浮 +、消息、我的。
- 中央 + 不作为普通 Tab，点击后弹出开播/发布动态操作菜单；首期发布动态可标记规划中。
- 建立统一 AppTheme/ThemeExtension 令牌：默认星夜紫、甜美粉、清新蓝、自然绿四套主题。
- 主题切换即时生效，并使用 SharedPreferences 持久化；文字、分割线、输入框、卡片、状态色必须同步适配。
- 保留 StatefulShellRoute 的分支导航能力；直播间、主播控制台、设置等页面按需求隐藏或显示底部栏。

B. 直播首页
- 标题“直播”、搜索/通知入口、分类横向滚动栏：推荐、颜值、新秀、才艺、女团、PK、语音。
- 顶部 Banner 和两列直播卡片，卡片有封面、直播中标签、主播名、在线人数和分类/等级信息。
- 支持 loading、empty、error/retry、下拉刷新和图片失败占位。
- 点击卡片进入现有 /live-room/:roomId，并保留真实 LiveRoom 数据链路。

C. 动态广场
- 实现关注、推荐、最新三个 Tab。
- 用模型 + MockRepository 渲染图文/视频动态：头像、作者、等级、时间、正文、媒体、点赞/评论/分享。
- 点赞有即时反馈并具备失败回滚边界；分享首期可复制链接或调用系统分享。

D. 消息中心
- 顶部实现互动消息、系统通知、官方客服三个入口。
- 实现会话列表、预览、时间和未读 badge；进入会话后清除未读数。
- 覆盖未登录、空列表、加载失败状态。

E. 我的与设置
- 我的页面实现头像、昵称、用户 ID、签名、关注/粉丝/获赞统计、VIP 占位卡片、8 个快捷入口。
- 实现实名认证、青少年模式、帮助与反馈等列表项和设置入口。
- 设置页面实现账号与安全、消息通知、隐私设置、直播设置、通用设置、清理缓存、关于我们、切换主题、退出登录。
- 退出登录二次确认并清理 Token；清理缓存二次确认并反馈结果。

F. 直播间
- 保留现有播放器/LiveEngine 边界，补齐效果图风格的顶部主播信息、关注、在线人数、关闭按钮、底部输入、礼物/分享/更多和点赞心形动画。
- 区分观看状态、媒体 loading、媒体 error/retry、弹幕连接中/失败、未登录不可发送。
- 礼物首期不得触发真实扣款；没有计费接口时使用“功能准备中”或显式 Mock 面板。

G. 主播流程
- 中央 + → 开播表单 → 权限 → 创建房间 → 初始化媒体引擎 → 预览/推流 → 后端确认 living → 结束推流 → 后端 ended → 刷新列表并返回。
- 检查权限拒绝、重复点击、媒体失败、网络中断、系统返回和状态同步失败，不留下幽灵房间。

实现要求：
- 文件按现有 feature-first 结构组织；页面只渲染和触发操作，状态放 Controller，数据放 Repository/DataSource。
- 中文 UI 文案集中管理或至少避免到处散落难以修改的字符串。
- 用真实可点击控件和可测试的状态，不使用整屏 GestureDetector 模拟所有交互。
- 遵守安全区、横向滚动、文字缩放、图片加载失败、小屏和大屏适配，避免 overflow。
- 每完成一个阶段先运行 dart format、flutter analyze 和相关测试；失败时先修复再进入下一阶段。
- 最终回复包含：改动文件、已完成主流程、未完成/占位能力、验证命令及结果、建议的下一步。
```

## 2. 推荐执行顺序

### 阶段一：先做视觉骨架

```text
请只执行阶段一：检查现有工程后，完成全局深色主题、四套主题持久化、底部导航重构、中央 + 操作菜单，以及直播/动态/消息/我的/设置的页面骨架。先使用 Mock 数据，不要修改服务端和媒体插件。完成后运行 flutter analyze 和相关 Flutter 测试，并汇报文件与结果。
```

验收重点：启动即进入直播首页；底部 5 个入口可切换；主题切换后全局可读且重启保持；中央 `+` 不是普通 Tab。

### 阶段二：完成观众闭环

```text
请继续执行阶段二：实现直播首页分类、Banner、两列直播卡片、loading/empty/error/retry/refresh；补齐直播间的视觉层、弹幕输入与展示、关注/点赞/分享的可测试状态。复用现有 LiveRoom、LiveRoomController、LiveEngine 和 WebSocket，不要伪造真实视频流。覆盖未登录和媒体失败路径，运行 analyze、单测和服务端现有测试。
```

### 阶段三：完成社区页面

```text
请继续执行阶段三：实现动态广场和消息中心的模型、MockRepository、Controller 与页面。动态支持关注/推荐/最新、图文/视频占位、点赞即时反馈与失败回滚；消息支持三类入口、会话列表、未读数和进入后清零。保持数据层可替换为真实 API，补充模型/Controller/Widget 测试。
```

### 阶段四：完成个人中心与设置

```text
请继续执行阶段四：把我的页面改为效果图结构，实现个人资料统计、快捷入口、VIP 非支付占位和设置页。实现清理缓存、退出登录二次确认、主题选择和 SharedPreferences 持久化。对暗色与四套主题做小屏截图或 widget 验证，修复文字对比度与布局溢出。
```

### 阶段五：主播流程与后端扩展

```text
请继续执行阶段五：审计现有开播表单、LiveBroadcastPage、FastAPI 房间接口和媒体插件实际能力，只在确认现有边界后补齐主播流程。实现权限拒绝、重复点击、媒体失败、返回退出、状态同步失败和房间清理。需要新增用户资料、关注、动态、消息或设置 API 时，先写 schema/service/repository/test，再接 Flutter DataSource；不要把视频流转发到 FastAPI。
```

## 3. 后端专项提示词（可直接复制）

当前项目的后端不是只提供直播列表，还需要支撑资料、关注、动态、消息、设置和直播生命周期。下面这段提示词用于单独驱动后端实现；建议在 Flutter 页面骨架完成后执行。

```text
你负责本项目的 FastAPI 后端和数据库实现。工作目录是：
/Users/kevin/Documents/ChatGPT/flutter_live/live_project/flutter_live_server

请先阅读：
- ../docs/直播App需求文档.md
- ../ARCHITECTURE.md
- app/api/v1/router.py
- app/api/deps.py
- app/core/database.py、security.py、config.py
- app/models、app/schemas、app/repositories、app/services
- tests/test_api.py、tests/test_schemas.py

先执行 git status，保留用户已有改动，不使用 git reset、git checkout、递归删除或覆盖无关文件。遵守现有 FastAPI → Service → Repository → SQLAlchemy/Pydantic 分层，以及 ApiResponse 统一返回格式。

后端目标：为直播社区 App 提供可鉴权、可测试、可迁移的 MVP API，覆盖：
1. 用户资料
2. 直播分类和 Banner
3. 直播房间列表与生命周期
4. 关注/取消关注
5. 动态 Feed 与点赞
6. 消息摘要、会话和已读
7. 用户设置与主题偏好
8. 现有直播间 WebSocket 弹幕和在线人数

一、数据库与模型

在确认现有表结构后，通过 Alembic 新增迁移；不得直接改数据库而不提交迁移文件。字段命名遵循 Python snake_case，接口输出使用现有 camelCase alias 规则。

建议按实际需要新增以下模型/表，避免重复创建已有能力：
- UserProfile 或扩展 users：avatar_url、bio、following_count、follower_count、like_count、level、verified_status、vip_status。
- Follow：follower_id、followee_id、created_at；对二者建立唯一约束和索引。
- FeedPost：author_id、content、media_type、media_urls 或独立 FeedMedia、like_count、comment_count、share_count、created_at、status。
- FeedLike：user_id、post_id、created_at；建立唯一约束。
- Conversation：conversation_type、participant/target 信息、last_message_at。
- Message：conversation_id、sender_id、content、created_at。
- MessageRead 或 conversation_members：user_id、conversation_id、unread_count、last_read_at。
- UserSetting：user_id、theme_id、notification/privacy/youth/live 等设置字段、updated_at。
- LiveBanner：image_url、title、target_type、target_id、sort_order、is_enabled。
- LiveCategory：code、name、sort_order、is_enabled。

如果 MVP 可以用配置/Seed 数据完成分类和 Banner，允许先不建复杂 CMS 表，但需要有稳定的 Service/Repository 接口，后续可替换数据库来源。

二、鉴权与权限

- 所有“我的”资料、关注变更、动态点赞、消息已读、设置读写接口必须使用当前用户依赖和 JWT。
- 直播浏览接口保持公开可读；创建房间、开始/结束房间必须要求登录，并使用当前用户作为主播身份，不能信任客户端传入的 anchor_name 作为真实身份。
- 观众接口绝不能返回 push_url；push_url 和 stream_name 只能返回给创建该房间的主播或明确授权的控制端。
- 处理 Token 缺失、过期、用户不存在和无权访问，返回项目统一错误格式。
- 关注自己、重复关注、重复点赞、重复已读、重复结束直播都要有明确的幂等行为。
- 对正文、昵称、标题、弹幕长度做服务端校验；不能只依赖 Flutter 客户端校验。

三、接口实现

沿用 /api/v1 前缀、APIRouter、Depends、ApiResponse 和已有异常体系，按 endpoint → service → repository 实现以下接口。具体路径可根据现有代码调整，但要保持语义一致：

公开接口：
- GET /live/categories
- GET /live/banners
- GET /live/rooms?category=&cursor=&limit=
- GET /live/rooms/{room_id}

当前用户接口：
- GET /users/me
- PATCH /users/me
- POST /users/{user_id}/follow
- DELETE /users/{user_id}/follow
- GET /users/{user_id}/follow-status
- GET /feed?tab=following|recommended|latest&cursor=&limit=
- POST /feed/posts
- POST /feed/{post_id}/like
- DELETE /feed/{post_id}/like
- GET /messages/summary
- GET /messages/conversations?cursor=&limit=
- GET /messages/conversations/{conversation_id}
- POST /messages/conversations/{conversation_id}/read
- GET /users/me/settings
- PUT /users/me/settings

主播接口：
- POST /live/rooms
- POST /live/rooms/{room_id}/start
- POST /live/rooms/{room_id}/stop

每个接口都要完成：请求 schema、响应 schema、参数校验、鉴权依赖、Service 业务规则、Repository 查询/写入、错误分支和测试。分页至少定义一种稳定策略；如果暂时不做游标分页，先用 limit/offset，但在响应中保持可扩展结构。

四、直播生命周期

- 创建房间为 preparing，只返回主播端所需的 push_url；观众列表不展示 preparing。
- 只有媒体服务确认实际 stream active 后，才允许切换 living。
- 结束直播变为 ended，online_count 归零；重复结束应幂等。
- 继续使用现有 MediaServerClient 和 SRS 对账逻辑；媒体服务不可达时不能批量误杀正在直播的房间。
- 服务器异常退出或推流断开后，列表/详情接口按现有 grace period 规则回收幽灵房间。
- FastAPI 不转发视频二进制，WebSocket 只传弹幕、presence 和必要的在线人数事件。

五、消息与实时能力

- 保留现有 /live/ws/rooms/{room_id} 的 JWT 校验、弹幕长度校验、Redis 广播和在线人数机制。
- 不因新增消息中心而破坏直播间弹幕 WebSocket；如需扩展事件格式，保持旧客户端可忽略未知字段。
- 消息摘要按互动消息、系统通知、官方客服等类型返回未读数和最近预览。
- 标记已读必须只影响当前用户有权访问的会话，并具备幂等性。

六、测试与交付

至少补充：
- schema：字段 alias、默认值、长度边界和非法输入。
- service：关注幂等、点赞幂等、未读清零、设置保存、房间状态转换。
- API：未登录 401、无权 403、不存在 404、重复操作、分页、响应格式。
- 数据库/Repository：唯一约束、查询排序、关联对象不存在。
- 直播：push_url 不泄露给观众、start/stop 状态和媒体服务异常。

执行并修复：
- ruff check .
- pytest
- alembic upgrade head（使用测试数据库或项目既有测试配置）

最终汇报必须区分：
- 已真实实现的接口和迁移
- 仅 Seed/Mock 的接口
- 尚未实现的礼物、VIP、支付、审核、连麦/PK
- Flutter 端尚未联调的接口
- 每条验证命令及结果
```

## 4. 前后端联调提示词

```text
请在后端接口通过测试后，开始前后端联调：

1. Flutter DataSource 只调用 FastAPI 暴露的接口，不在页面中拼接 URL 或直接解析原始 Dio 响应。
2. 将 MockRepository 设计为可替换实现：开发演示可使用 Mock，联调开关打开时使用 RemoteRepository。
3. 统一处理 loading、401、403、404、网络超时、服务端业务错误和空数据。
4. 登录成功后刷新我的资料、消息摘要和关注状态；退出登录后清空用户相关缓存。
5. 直播首页从 GET /live/rooms 获取数据，进入直播间只使用观众响应中的 playUrl；主播页才使用 pushUrl。
6. 关注、点赞、已读操作先更新本地 UI，再在接口失败时回滚并提示；避免重复点击产生重复请求。
7. 联调完成后验证一条完整链路：注册/登录 → 查看首页 → 进入直播间 → 发送弹幕 → 关注主播 → 点赞动态 → 查看消息 → 进入我的 → 切换主题 → 退出登录。
8. 运行 Flutter analyze、Flutter tests、后端 ruff check 和 pytest，并记录真实结果；不要用“接口未连接”掩盖失败。
```

## 5. Codex 工作纪律提示

```text
每次开始前：
- 先读取需求文档和项目架构文档。
- 先查看 git status，识别用户已有改动。
- 只修改当前阶段相关文件。

每次结束前：
- 运行 dart format（只针对改动的 Dart 文件或目标目录）。
- 运行 flutter analyze。
- 运行与改动相关的 Flutter/服务端测试。
- 检查是否出现 overflow、空态缺失、未登录路径断裂、路由返回栈异常、主题下文字不可读。
- 明确列出真实完成、Mock 完成和暂未实现三类结果。
```

## 6. 不应直接执行的误解

- 不要把效果图中的示例头像、网名、ID、在线人数当成固定生产数据。
- 不要为了“看起来像”而删除现有认证、WebSocket、LiveEngine 或服务端分层。
- 不要把中央加号做成一个占用导航索引的普通页面。
- 不要在没有支付后端和风控方案时实现真实礼物/VIP 扣款。
- 不要将 HTTP-FLV、HLS、WebRTC、RTMP 的选择硬编码成未经确认的最终方案。
- 不要用截图、视频或单个自定义画布替代可访问、可测试的 Flutter 组件。
