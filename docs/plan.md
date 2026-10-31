# BizSnap — 实施计划

本文是完整交付规格。按本文实现即可，不需要再做产品决策。

## 一、目标与交付物

做一个 iOS 轻量商务 CRM：用户上传一张商务聊天截图（可附一段文字），agent 理解其中的联系人、公司、职位、约定，主动查询已有联系人数据与历史记忆，生成用户可确认的行动卡片；用户确认后写入系统通讯录与日历，并**结合刚写入的事实与该联系人的完整历史，生成对用户有帮助的洞察与建议**。

交付三样：

1. iOS App（SwiftUI，可编译可运行）
2. GitHub 仓库（含服务端与 App）
3. 可运行的测试环境（本地即可：Node 服务 + iOS 模拟器）

## 二、技术栈

| 层 | 选型 |
| --- | --- |
| iOS | SwiftUI，iOS 17+，XcodeGen 管工程 |
| 系统能力 | PhotosUI、Contacts、EventKit |
| Agent | `mastra@1.31.x`、`@mastra/core@1.72.x`、`@mastra/memory@1.33.x`、`@mastra/libsql@1.24.x` |
| 模型 | `@ai-sdk/deepseek` + `deepseek-flash`，`ai@7.x` |
| 嵌入 | 硅基流动 `BAAI/bge-large-zh-v1.5`（1024 维），`@ai-sdk/openai-compatible@2.x` |
| HTTP | Hono 4 + `@hono/node-server` + zod 4 | 两个会出字的接口走 SSE 流式，见第八节 |
| 存储 | LibSQL 单文件 `bizsnap.db`（`@mastra/libsql`） |
| 运行 | Node 20+，pnpm，tsx |

环境变量（`server/.env`）：

```
DEEPSEEK_API_KEY=        # 必填
SILICONFLOW_API_KEY=     # 必填
PORT=8787                # 可选，默认 8787
```

两个 key 缺任意一个，启动时报中文错误并退出。

## 三、目录结构

```
bizsnap/
├── README.md
├── docs/
│   ├── plan.md              本文
│   ├── 开发方案.md
│   ├── 记忆设计.md
│   └── 演示脚本.md
├── server/
│   ├── package.json
│   ├── tsconfig.json
│   ├── .env.example
│   └── src/
│       ├── index.ts         Hono 应用、CORS、body limit 12mb、统一 onError、`serve()` 启动
│       ├── sse.ts           SSE 帧写法（`data:` 行 + `withSseHeartbeat` 心跳）
│       ├── http.ts          readJson / zod 校验转 400
│       ├── config.ts        环境变量校验、时区 Asia/Shanghai、默认会议 60 分钟
│       ├── types.ts         ContactRecord / Attribute / Interaction / CardDraft / ChatMessage
│       ├── db/
│       │   ├── client.ts    LibSQL 连接单例（业务表与 Mastra memory 共用一个连接）
│       │   ├── schema.ts    建业务表（幂等）
│       │   ├── contacts.ts  upsert、appendInteraction、getByContact、searchByKeyword、listAll
│       │   └── threads.ts   threads / messages / confirmed_cards
│       ├── mastra/
│       │   ├── index.ts     Mastra 实例（storage + agent 注册）
│       │   ├── storage.ts   LibSQLStore + Memory（lastMessages 20）
│       │   ├── agent.ts     bizAgent 装配
│       │   ├── prompt.ts    系统提示（含时间基准注入）
│       │   └── tools/
│       │       ├── search-contact.ts
│       │       ├── get-history.ts
│       │       ├── create-contact.ts
│       │       ├── update-contact.ts
│       │       └── create-meeting.ts
│       ├── services/
│       │   ├── attributes.ts  时间线封口与合并
│       │   ├── embedding.ts   拼检索文本、调嵌入、算余弦
│       │   ├── insight.ts     确认后的洞察生成
│       │   └── confirm.ts     确认编排（事务）
│       └── routes/
│           ├── threads.ts
│           ├── messages.ts
│           └── confirm.ts
├── BizSnap/
│   ├── project.yml
│   └── BizSnap/
│       ├── App/BizSnapApp.swift
│       ├── Models/
│       │   ├── DTO.swift
│       │   ├── ActionCard.swift
│       │   └── ChatMessage.swift
│       ├── Services/
│       │   ├── AgentClient.swift     REST + SSE 两条通路
│       │   ├── SSEParser.swift       按行切 `data:`，解成事件枚举
│       │   ├── ImageCompressor.swift
│       │   ├── ContactsService.swift
│       │   ├── CalendarService.swift
│       │   └── DemoSeed.swift
│       ├── Features/
│       │   ├── ThreadList/ThreadListView.swift
│       │   └── Chat/
│       │       ├── ChatView.swift
│       │       ├── MessageBubble.swift
│       │       ├── CardStrip.swift
│       │       └── Composer.swift
│       └── Theme/Tokens.swift
└── scripts/
    ├── check-vision.ts
    ├── check-embedding.ts
    └── seed-demo.ts
```

## 四、数据模型

### `contacts`（状态）

```ts
export type AttributeType = 'industry' | 'company' | 'position' | 'project' | 'relation';

export type Attribute = {
  type: AttributeType;
  value: string;
  since: string;          // ISO 日期，当前值生效日
  history: { from: string; to: string; value: string }[];  // 旧值，区间不重叠，最多 10 段
};

export type ContactRecord = {
  id: string;             // 姓名归一化后 sha1 前 16 位
  name: string;
  phone: string;
  email: string;
  attributes: Attribute[];
  searchCurrent: string;  // 派生：name + 各属性当前值，空格分隔
  searchHistory: string;  // 派生：各属性历史值 + 历史 phone/email，空格分隔
  embedding: string | null; // JSON 数组文本，1024 维
  lastContactAt: string;
  interactionCount: number;
};
```

### `interactions`（事件）

```ts
export type Interaction = {
  id: string;
  contactId: string;
  groupId: string;         // 同一次确认的多条共享
  at: string;              // ISO 8601
  kind: 'created' | 'updated' | 'meeting';
  source: 'image' | 'text' | 'both';
  attrs: string[];         // 本次动了哪些属性名，如 ['company']
  background: string;      // 为什么；没有依据则为空字符串
  meeting?: {
    title: string;
    startTime: string;     // 带时区偏移的 ISO 8601
    endTime: string;
    location: string;
    participants: string[];
  };
};
```

### 卡片草案

```ts
export type CardKind = 'create_contact' | 'update_contact' | 'create_meeting';

export type CardDraft = {
  id: string;
  kind: CardKind;
  payload:
    | { name: string; phone?: string; email?: string; industry?: string;
        company?: string; position?: string; project?: string; relation?: string }
    | { targetName: string; changes: Record<string, string> }
    | { title: string; startTime: string; endTime: string;
        location?: string; participants: string[]; remark?: string };
};
```

### 消息

```ts
export type ChatMessage = {
  id: string;
  role: 'user' | 'assistant';
  text?: string;
  imageBase64?: string;   // 用户图，仅用于回显
  cards?: CardDraft[];    // 该条 agent 回复附带的卡片
  createdAt: string;
};
```

## 五、记忆规则

### 1. 属性时间线

- 某属性有新值 → 旧 `value` 压进 `history`，`to` = 新 `since` 前一天；`value` 替换，`since` = 今天
- 值没变 → 不动
- `history` 只增不删；超过 10 段时把最早的几段合并为一段，`value` 形如「此前：房地产销售」
- `phone` / `email` 不建时间线，直接覆盖；变更记录在 `interactions.attrs` 留痕

### 2. `background`

只复述本轮输入里明确出现的原因（截图文字或用户那句话）。找不到依据就写空字符串。

两道关卡：`prompt.ts` 里明确要求；`services/confirm.ts` 里做字符串校对，输入中不含该原因时置空并打 warn。

### 3. 写入路径

五个工具一律只读或只返回草案，不碰数据库。写库只发生在 `POST /api/threads/:id/confirm`，一个事务包住：

```
多条 interaction → attributes 封口与新值
```

任一环节失败整体回滚。`searchCurrent` / `searchHistory` / `embedding` 在事务提交后重算：嵌入要发 HTTP 请求，占着写锁等网络会把并发确认卡死；嵌入失败也只是这个人暂时不参与语义检索。

### 4. 检索

`search_contact` 的查找顺序：

1. 姓名 / 电话 / 公司 LIKE `searchCurrent` → `matchedIn: 'now'`
2. LIKE `searchHistory` → `matchedIn: 'history'`
3. 前两步命中少于 3 个时，把 query 嵌入，与全表 embedding 算余弦相似度 → `matchedIn: 'semantic'`

`when: 'now'` 时丢掉只命中 `searchHistory` 的候选。

向量只用于「找到是谁」，命中后所有事实回数据库取。

## 六、Agent

```ts
// src/mastra/agent.ts
const memory = new Memory({
  storage: new LibSQLStore({ id: 'bizsnap', url: 'file:./bizsnap.db' }),
  options: { lastMessages: 20 },
});

export const bizAgent = new Agent({
  name: 'bizsnap',
  instructions: buildPrompt({ now: new Date(), timezone: 'Asia/Shanghai' }),
  model: deepseek('deepseek-flash'),
  tools: { searchContact, getContactHistory, createContact, updateContact, createMeeting },
  memory,
});
```

`agent.generate(messages, { memory: { thread, resource }, stopWhen: stepCountIs(5) })`。

### 系统提示要点

1. **身份**：商务 CRM 助手，只处理商务信息。
2. **非商务输入**：生活闲聊、表情包、广告、代码截图，直接回复「未识别到商务信息」，不调用工具、不出卡片。
3. **查人优先**：涉及某个人时先 `search_contact`；需要历史细节时再 `get_contact_history`。查到多人时，用一句话让用户确认是哪一个，不要自己猜。
4. **必须说清**：卡片只有「创建联系人 / 创建会议 / 更新联系人」这几个字，不显示任何字段。所以每条回复的正文必须写明本次要写入的具体内容：建谁、哪家公司、什么职位、约在哪天几点、哪些人参加。不许只出卡不说话。
5. **信息不足先问**：缺关键信息（如创建会议没有时间、创建联系人没有姓名）时，在对话里追问，不生成卡片。
6. **时间**：提示里带 `now`、`weekday`、`timezone`。用户说「下周三下午三点」时换算成带 `+08:00` 偏移的 ISO 8601。不写相对时间。
7. **background**：写事件原因时只复述输入里出现的话；没有就留空，不推测。
8. **洞察**：卡片发出前不要长篇分析；洞察在用户确认之后由服务端单独生成。

## 七、五个工具

| 工具 | inputSchema | 返回 |
| --- | --- | --- |
| `search_contact` | `query: string`、`when?: 'now' \| 'any'`（默认 any） | `{ inDevice: boolean, candidates: [{ id, name, now: Record<string,string>, timeline: string, matchedIn }] }`，最多 10 条 |
| `get_contact_history` | `name: string`、`limit?: number`（默认 8） | `{ name, timeline: string, events: [{ at, kind, attrs, background, meeting? }] }` |
| `create_contact` | name（必填）/ phone / email / industry / company / position / project / relation / `reason?` | `CardDraft`（kind `create_contact`）；同名已存在时返回 error |
| `update_contact` | `target_name`（必填）+ 任意字段 + `reason?` | `CardDraft`（kind `update_contact`，`changes` 只含本次要改的字段）；无变化时返回 error |
| `create_meeting` | title / start_time / end_time / participants（数组）/ location / remark / `reason?` | `CardDraft`（kind `create_meeting`） |

`search_contact` 需要设备通讯录快照：从本轮请求的 `contactsSnapshot` 里匹配姓名与电话，用于填 `inDevice`。

## 八、接口

除两个会出字的接口（发消息、确认）走 `text/event-stream` 外，其余返回 JSON。

### `POST /api/threads`

请求 `{ title?: string }` → 返回 `{ threadId }`。内部用 Mastra memory 建 thread。

### `GET /api/threads`

返回会话列表：

```json
[{ "id": "...", "title": "王建国", "contactName": "王建国", "lastMessage": "已帮你建好…", "updatedAt": "2026-10-29T12:00:00+08:00" }]
```

按 `updatedAt` 倒序。

### `GET /api/threads/:id/messages`

返回该 thread 的消息数组，元素结构同 `ChatMessage`。卡片从 assistant 消息的 tool 结果还原；`imageBase64` 只回显用户自己发的图。

### `POST /api/threads/:id/messages` → `text/event-stream`

请求：

```json
{ "text": "可选", "imageBase64": "可选，JPEG base64", "contactsSnapshot": [{ "name": "", "company": "", "position": "", "phones": [] }] }
```

处理：

1. 组装 user 消息（有图时带 `image` part：`{ type: 'image', image: Buffer.from(base64, 'base64'), mediaType: 'image/jpeg' }`）
2. `const stream = await bizAgent.stream(...)`，带 `memory: { thread: id, resource: 'owner' }` 与 `maxSteps: 5`
3. 边消费 `stream.fullStream` 边转发：
   - `chunk.type === 'text-delta'` → 推 `text`（`chunk.payload.text`）
   - `chunk.type === 'tool-result'` 且 `chunk.payload.toolName` 是三个出卡工具 → 把 `chunk.payload.result.card` 作为 `card` 事件立即推送
4. 流结束：落库 assistant 消息（累积文本 + 卡片），再推 `done`

### SSE 协议（两个流式接口共用）

每条事件是一行 `data: <json>`，**不使用 SSE 的 `event:` 名**，JSON 里必带 `type`。客户端只按行读、只认 `data:` 前缀，Swift 侧解析成本最低。

| `type` | 载荷 | 说明 |
| --- | --- | --- |
| `start` | `{ threadId, messageId }` | 建流后立即发 |
| `text` | `{ delta }` | 增量文本，客户端自行拼接 |
| `card` | `{ card }` | 出卡工具一返回就推，早于文字结束 |
| `done` | `{ message }` 或 `{ insight, contactName }` | 结束帧，正文以它为准覆盖增量 |
| `error` | `{ error }` | 中途失败；客户端保留已收片段并给「重试」 |

- 心跳用 `@mastra/ai-sdk` 的 `withSseHeartbeat(response, 15000)`：空闲时在两帧之间插 `: heartbeat` 注释，不打断帧
- 客户端断开 → 服务端停止消费上游、删掉本轮用户消息，不写 assistant 消息
- 卡片不等整段文字结束：用户看到卡片的时机从「回复结束」提前到「工具返回」

### `POST /api/threads/:id/confirm` → `text/event-stream`

请求：

```json
{ "cards": [{ "id": "", "kind": "create_contact", "payload": {} }] }
```

处理（`services/confirm.ts`，单事务）：

1. 逐张卡落库：`create_contact` 新建或按姓名合并；`update_contact` 更新目标联系人属性；`create_meeting` 写一条 meeting 事件，挂在**当前会话主联系人**名下（`participants` 存全名单，1 人写名字、2 人写两个名字、3 人以上写「张三等 4 人」由前端渲染，数据库存原数组）
2. 每张卡写一条 `interaction`，共用同一个 `groupId`
3. 事务提交后重算受影响联系人的 `searchCurrent` / `searchHistory` / `embedding`
4. 立即推 `written`（`{ written: [{ cardId, kind, contactName, background, ok, error? }], contactName }`）——客户端拿到这一帧就开始写系统通讯录 / 日历
5. 调 `services/insight.ts`，边生成边推 `text`，结束后推 `done`

`insight` 只走流、不写入 thread 消息。

## 九、洞察生成

`services/insight.ts`，用 `ai` 的 `streamText`（`deepseek-flash`，不带工具），把 `textStream` 的每个 chunk 直接推成 `text` 帧；流结束后拼出全文留在 `done` 里。需要非流式的场合（比如脚本里）才用 `generateText`。

输入：

- 该联系人全部 `attributes`（含 `history`）
- 最近 8 条 `interactions`（含 `at`、`kind`、`background`、`meeting`）
- 本次刚写入的 `interactions`

要求模型输出 1–3 句中文，结构固定：

1. 先陈述时间线上一个具体事实（认识多久、换过什么、上次见面距今多久）
2. 再给一条可执行的下一步建议（问什么、约谁、什么时候）

约束：

- 只用输入里存在的信息，不推测
- 不出现「依据」「根据记录」这类标签
- 不写空话（「保持联系」「继续跟进」这种）
- 中文，不超过 120 字

## 十、iOS 规格

`project.yml`：iOS 17.0、bundle `com.bizsnap.app`、`NSContactsUsageDescription`、`NSCalendarsFullAccessUsageDescription`、`NSAppTransportSecurity.NSAllowsLocalNetworking = true`。服务地址默认 `http://127.0.0.1:8787`，设置页可改。

### 主题

跟随系统外观。`Theme` 里每个语义色给两套取值，由系统在浅色/深色间切换。

| 语义 | 浅色 | 深色 |
| --- | --- | --- |
| 背景 | `#F4F5F7` | `#0E0F12` |
| 卡片底 | `#FFFFFF` | `#16181D` |
| 浮层 | `#FFFFFF` | `#1E2128` |
| 主色 | `#3D6EF0` | `#5B8CFF` |
| 主色浅 | `#5B8CFF` | `#7AA2FF` |
| 正文 | `#111318` | `#F2F3F5` |
| 次要 | `#565E6C` | `#A0A6B0` |
| 弱 | `#8A91A0` | `#6B7280` |
| 成功 / 警示 / 错误 | `#1FA84E` / `#E08600` / `#E03127` | `#34C759` / `#FF9F0A` / `#FF453A` |

1px 描边与分隔线：浅色下用黑、深色下用白，再叠加各自的透明度。圆角 16，间距基数 8。字号：标题 28 加粗、条目标题 16 半粗、正文 15、辅助 12。

### 页面一：会话列表

- 顶部：左「会话」28 加粗；右侧设置入口（填入演示联系人、服务地址、清空数据）
- 行：48pt 高，左侧 40pt 圆形首字头像，中间联系人名 16 半粗 + 最后一条消息摘要 14 灰单行截断，右侧时间 12 灰
- 空态：虚线描边卡，文案「把一段商务对话变成通讯录里的一条记录」，下方主按钮「开始第一段对话」
- 右下角 56pt 圆形加号按钮，蓝色渐变

### 页面二：会话详情

- 导航栏：返回 + 会话标题（可点改名）+ 右侧服务状态圆点（在线绿 / 离线灰）
- 消息流间距 12：
  - 用户文字：右对齐蓝色气泡，圆角 16，最大宽度 78%
  - 用户图片：圆角 12，最大高度 240，点击全屏
  - agent 文字：左对齐深灰气泡，圆角 16，最大宽度 78%
  - **卡片**：整宽窄条，高 64。左侧类型文案（创建联系人 / 创建会议 / 更新联系人）16 半粗，右侧 22pt 圆形勾选框。**不显示任何字段、不显示时间、不显示依据**。选中时描边变主色、整体缩放 1.02。确认后原地折叠成一行「已写入通讯录 ›」。非最新一批的卡片整体 40% 透明、勾选框禁用
- 底部：吸底输入栏。左侧「+」打开相册/拍照，中间圆角输入框占位「说点什么，或贴一张聊天截图」，右侧发送按钮（有内容时点亮）。选图后输入框上方显示缩略图与「×」
- 发送后先插入两条灰色骨架占位；收到第一个 `text` / `card` 事件就换成真实气泡，文字随 `delta` 增长
- 卡片可以**先于文字**出现：`card` 帧一到就渲染窄卡，此时正文可能还在打字
- 流中断时保留已收片段，在该消息下方显示浅红提示条 +「重试」
- 出错时在该消息位置显示浅红提示条 +「重试」，不弹全局弹窗

### 卡片交互

- 只有**最后一条含卡片的 agent 回复**里的卡片可勾选；更早的置灰不可点
- 多选，底部吸底按钮显示「确认选中 N 项」，点击后提交 `/api/threads/:id/confirm`
- 提交流程：服务端落库成功 → 逐张调本地 Contacts / EventKit → 单张失败只标红该卡并给重试，其余照常折叠
- 卡片不可编辑；内容不对就在输入栏继续说一句，agent 重新出卡，旧卡自动置灰

### 权限与演示数据

- 首次使用通讯录 / 日历前，先弹一句解释文案再请求权限
- 设置页「填入演示联系人」写 6–8 位覆盖「换行业 / 换公司 / 换职位」三类变化的人

## 十一、实现顺序

1. `server` 骨架：package.json、tsconfig、config、index（Hono 能起服务）
2. `scripts/check-embedding.ts` 与 `scripts/check-vision.ts`，跑通再往下
3. `db/`：建表、读写、检索
4. `mastra/`：agent + prompt + 五个工具（先只读两个，再三个草案）
5. `services/`：attributes、embedding、confirm、insight
6. `routes/`：Hono 路由 + SSE（messages、confirm 两条流；其余返回 JSON）
7. `BizSnap`：XcodeGen 工程 + 会话列表 + 消息流 + 输入栏
8. 卡片窄条、多选、确认、旧卡置灰
9. Contacts / EventKit 写入与演示数据
10. 验收三个 Case

## 十二、验收

前置：`pnpm dev` 起服务；`xcodegen generate` 后运行模拟器；设置页填入演示联系人；`pnpm tsx scripts/seed-demo.ts` 灌历史。

**Case 1（卡片）**：发一张带姓名、公司、约见时间的聊天截图。预期：agent 正文**先逐字出现**，卡片在正文之后才显示；正文说清建谁、约在何时；出现「创建联系人」「创建会议」两张卡；勾选确认后写入系统通讯录与日历。

**Case 2（跨会话找回）**：新建会话，只说「上次做跨境支付那个，最近有联系吗」。预期：agent 自行检索并报出该人，正文体现出他过去与现在的区别。追加一句「现在谁在做跨境支付」，不再报已转岗的那位。

**Case 3（更新与洞察）**：发一张「老李从 A 公司跳到 B 公司，还在管合规」的截图。预期：出现「更新联系人」卡片；确认后卡片立即折叠、旧公司进历史；**随后洞察逐字流出来，含基于时间线的具体事实 + 一条可执行的跟进建议**。

**Case 4（不落库）**：出一张卡但不确认，退出再进。预期：数据库无该记录。

## 十三、自检脚本

`scripts/check-embedding.ts`：读 `SILICONFLOW_API_KEY`，调 `BAAI/bge-large-zh-v1.5` 嵌入一句中文，打印维度，断言 1024。

`scripts/check-vision.ts`：用 `deepseek('deepseek-flash')` 传一张本地图片（base64）+ 一句「描述图片内容」，打印回复。若报错，改用 `createOpenAICompatible({ baseURL: 'https://api.deepseek.com' })` + 同名模型，再跑一次。

`scripts/seed-demo.ts`：直接写库，插入 3 位联系人与若干历史事件，其中一位保留「做过跨境支付、现已转岗」的时间线，供 Case 2 演示。
