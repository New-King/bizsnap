# BizSnap

iOS 轻量商务 CRM。上传一段商务聊天截图（或直接打一句话），agent 读出其中的联系人、公司和约定，生成「创建联系人 / 更新联系人 / 创建会议」三类卡片；勾选确认后写入系统通讯录与日历，并把事实沉淀成按人索引、带时间线的长期记忆。下次新开一个会话，只报一句「上次做跨境支付那个」，也能把他找回来。

## 当前状态

服务端与 iOS 端均已实现，服务端四个验收 Case 已在本机跑通（包含真实 DeepSeek 视觉输入与硅基流动嵌入）。实现规格见 `docs/plan.md`，设计取舍见 `docs/开发方案.md` 与 `docs/记忆设计.md`，演示流程与实测输出见 `docs/演示脚本.md`。

## 结构

```
bizsnap/
├── docs/            plan、开发方案、记忆设计、演示脚本
├── server/          Hono + Mastra agent（messages / confirm 走 SSE）
│   └── src/
│       ├── db/      contacts / interactions / threads / messages
│       ├── mastra/  agent、prompt、storage、五个工具
│       ├── services/ 时间线、嵌入、确认落库、洞察、演示数据
│       └── routes/  会话、消息、确认、demo
├── BizSnap/         iOS 工程（XcodeGen 生成）
│   └── BizSnap/
│       ├── Models/  DTO、行动卡片、消息
│       ├── Services/ 接口调用、通讯录、日历、卡片执行
│       ├── Features/ 会话列表、会话详情、设置
│       └── Theme/
└── scripts/         两个外部依赖的自检（纯 fetch，不依赖 server 的依赖）
```

## 运行

需要 Node 20+、Xcode 与 iOS 17 模拟器。三步：

```bash
# 1. 装依赖
cd server && pnpm install

# 2. 配 key（两个都要）
cp .env.example .env
#   DEEPSEEK_API_KEY=   deepseek-flash
#   SILICONFLOW_API_KEY=  bge-large-zh-v1.5 嵌入

# 3. 起服务
pnpm dev          # :8787

# 可选：自检两个外部依赖
pnpm check:embedding    # 断言 bge-large-zh-v1.5 返回 1024 维
pnpm check:vision       # 现场画一张 PNG 发给 deepseek-flash，验证图片输入

# 可选：改过嵌入口径（向量文本的拼法）后重算全库
pnpm reindex            # 逐人重写检索列与向量
```

脚本都在仓库根的 `scripts/`，通过 `server/package.json` 里的 npm script 调用（`tsx ../scripts/xxx.ts`），所以只用 Node 内置模块与全局 `fetch`，不需要额外装包。

iOS 端：

```bash
cd BizSnap && xcodegen generate
open BizSnap.xcodeproj
```

从空库开始跑：设置页只有服务地址与「清空全部数据」（服务端库、本应用写进系统通讯录的联系人、写进日历的会议一起清）。

服务地址默认 `http://127.0.0.1:8787`，`Info.plist` 里已放行本地网络的明文 HTTP。

## 两个设计决定

**卡片只有三个固定文案**（创建联系人 / 创建会议 / 更新联系人），不显示字段。所以 agent 必须在正文里把「建谁、改哪项、什么时候、哪些人」写清楚。卡片只读，内容不对就继续说话让它重出；只有最新一批卡片可勾选。

**记忆是两张表，不是三层**：

| 表 | 角色 |
| --- | --- |
| `contacts` | 状态。当前值 + 每条属性的变更时间线，外加一条按人向量 |
| `interactions` | 事件。发生过什么、为什么、见了谁 |

写入只发生在确认之后，五个工具没有任何写操作。

## 已知限制

- 当前机器没有预装 iOS 模拟器 runtime，第一次跑要先 `xcodebuild -downloadPlatform iOS`（约 7.9 GB）
- 通讯录 / 日历是真实系统权限，写入失败只影响单张卡片，可单独重试
- 行业、项目、关系只存在本地库，系统通讯录没有对应字段
