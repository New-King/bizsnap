# BizSnap — 交付规格

本文是完整交付规格，按本文实现即可。

## 一、项目与交付物

iOS 轻量商务 CRM。用户发一张商务聊天截图（可附一段文字，也可以只发文字），agent 读出其中的联系人、公司、职位、约定，主动查库里的人和过往事件，生成「创建联系人 / 更新联系人 / 创建会议」卡片；用户勾选确认后写入系统通讯录与日历，把事实沉淀成按人索引、带时间线的长期记忆，并针对这次写入生成一段洞察。

交付三样：

1. iOS App（SwiftUI，可编译可运行）
2. 服务端（Node + Hono + Mastra agent，本地可跑）
3. 仓库根 README 与本文档

## 二、运行环境

- Node 20+、pnpm；macOS + Xcode（iOS 17 模拟器）
- 服务端依赖装在 `server/`，脚本在仓库根 `scripts/`，iOS 工程在 `BizSnap/`

```bash
cd server && pnpm install
cp .env.example .env        # 填两个 key
pnpm dev                    # http://0.0.0.0:8787
```

环境变量（`server/.env`，由 `config.ts` 用 dotenv 显式加载绝对路径，从任何目录启动都读这一份）：

```
DEEPSEEK_API_KEY=        # 必填，对话 / 视觉 / 洞察
SILICONFLOW_API_KEY=     # 必填，嵌入
PORT=8787                # 可选
HOST=0.0.0.0             # 可选，真机调试要监听所有网卡
```

任一 key 缺失：打印中文提示并 `process.exit(1)`。

iOS：

```bash
cd BizSnap && xcodegen generate
bash scripts/ios-run.sh      # 或 open BizSnap.xcodeproj 后 ⌘R
```

## 三、技术栈

| 层 | 选型 |
| --- | --- |
| iOS | SwiftUI，iOS 17.0，XcodeGen 生成工程（`project.yml`） |
| 系统能力 | PhotosUI、Contacts、EventKit |
| Agent | `@mastra/core@^1.72`、`@mastra/memory@^1.33`、`@mastra/libsql@^1.24`、`@mastra/ai-sdk@^1` |
| 模型 | `@ai-sdk/deepseek@^3` + `deepseek-flash`，`ai@^7` |
| 嵌入 | 硅基流动 `BAAI/bge-large-zh-v1.5`（1024 维），`@ai-sdk/openai-compatible@^3` |
| HTTP | Hono 4 + `@hono/node-server` 2 + zod 4 |
| 存储 | LibSQL 单文件 `server/bizsnap.db`（`@libsql/client`，业务表与 Mastra memory 共用一个连接） |
| 运行 | `tsx watch`；脚本用 `tsx` 直接跑 |

依赖范围就是上表这几个包。

## 四、仓库结构

```
bizsnap/
├── README.md
├── docs/plan.md                 本文
├── server/
│   ├── package.json              scripts: dev / start / typecheck / check:embedding / check:vision / reindex
│   ├── tsconfig.json
│   ├── .env.example
│   └── src/
│       ├── index.ts              Hono 应用：cors、请求日志、bodyLimit 12MB、/api/health、统一 notFound/onError、启动时 ensureSchema + 预加载 agent + serve()
│       ├── config.ts             读 .env、校验 key、常量（模型、嵌入、时区、默认会议时长、db 路径）、RESOURCE_ID
│       ├── llm.ts               createDeepSeek + chatModel
│       ├── http.ts              readJson / zod 校验转 400 / notFound
│       ├── sse.ts               sseResponse：单行 `data: <json>` 帧 + withSseHeartbeat 心跳
│       ├── types.ts             Attribute / ContactRecord / Interaction / CardDraft / ChatMessage / TraceStep 等
│       ├── db/
│       │   ├── client.ts        LibSQL 连接单例
│       │   ├── schema.ts        建业务表（幂等），并保证代码用到的列齐备
│       │   ├── contacts.ts      upsert、insertInteraction、listInteractions、searchByKeyword、searchInteractionsByKeywords、searchByEmbedding、findContactByName、listAll、newId
│       │   └── threads.ts       threads / messages / confirmed_cards
│       ├── mastra/
│       │   ├── index.ts         Mastra 实例（agents: { bizsnap }, storage）
│       │   ├── storage.ts       LibSQLStore（复用业务连接）+ Memory（lastMessages 20）
│       │   ├── agent.ts         bizAgent 装配
│       │   ├── prompt.ts        buildPrompt()，注入当前时间
│       │   ├── title.ts         generateTitle()：首轮结束后补会话标题
│       │   └── tools/
│       │       ├── search-contact.ts
│       │       ├── search-interactions.ts
│       │       ├── get-history.ts
│       │       ├── create-contact.ts
│       │       ├── update-contact.ts
│       │       └── create-meeting.ts
│       ├── services/
│       │   ├── attributes.ts   时间线封口与合并、renderTimeline、currentValue(s)
│       │   ├── embedding.ts    拼检索文本、调嵌入、算余弦、buildSearchColumns
│       │   ├── confirm.ts      确认编排（单事务、background 校对、系统写入结果）
│       │   ├── insight.ts      streamInsight / streamFailureNote
│       │   ├── trace.ts        TraceRecorder：把流事件收成可展示的链路
│       │   └── demo-seed.ts    resetDemo：清业务数据与会话表，回传需从系统侧删除的名单
│       └── routes/
│           ├── threads.ts
│           ├── messages.ts
│           ├── confirm.ts
│           └── demo.ts
├── BizSnap/
│   ├── project.yml              iOS 17.0、bundle com.newking.bizsnap、权限文案、ATS 放行本地
│   ├── BizSnap.xcodeproj        由 XcodeGen 生成
│   └── BizSnap/
│       ├── App/BizSnapApp.swift
│       ├── App/RootView.swift
│       ├── Models/{DTO,ActionCard,ChatMessage,StreamEvent,TraceStep}.swift
│       ├── Services/{AgentClient,SSEParser,ImageCompressor,ContactsService,CalendarService,CardExecutor}.swift
│       ├── Features/Chat/{ChatView,MessageBubble,CardStrip,Composer,ErrorBar,AgentFeedback,AgentTraceView}.swift
│       ├── Features/ThreadList/ThreadDrawer.swift
│       ├── Features/Settings/SettingsView.swift
│       └── Theme/Tokens.swift
└── scripts/
    ├── env.ts                   脚本读 server/.env
    ├── check-embedding.ts       断言嵌入返回 1024 维
    ├── check-vision.ts          现场画一张 PNG 发给 deepseek-flash，验证图片输入
    ├── reindex-embeddings.ts    遍历全库重算检索列与向量
    └── ios-run.sh               编译 → 装进已启动模拟器 → 启动 app
```

## 五、数据模型

业务表由 `db/schema.ts` 幂等创建；Mastra 的 `mastra_*` 表由 LibSQLStore 初始化。同一个 `bizsnap.db` 文件。

### `contacts` —— 状态

```ts
type AttributeType = 'industry' | 'company' | 'position' | 'project' | 'relation';

type Attribute = {
  type: AttributeType;
  value: string;          // 当前值
  since: string;          // 当前值生效日，YYYY-MM-DD
  history: { from: string; to: string; value: string }[];  // 旧值，区间不重叠，最多 10 段
};

type ContactRecord = {
  id: string;             // 归一化姓名 sha1 前 16 位
  name: string;
  phone: string;          // 不建时间线，直接覆盖；变更由 interactions.attrs 留痕
  email: string;
  attributes: Attribute[];
  searchCurrent: string;  // 派生：姓名 + 5 个当前值，空格分隔
  searchHistory: string;  // 派生：各属性历史值 + 历史 phone/email，空格分隔
  embedding: string | null;  // 派生：JSON 数组文本，1024 维，只嵌「现在」
  lastContactAt: string | null;
  interactionCount: number;
  createdAt: string;
  updatedAt: string;
};
```

### `interactions` —— 事件

```ts
type Interaction = {
  id: string;
  contactId: string;
  groupId: string;        // 同一次确认产生的多条共享
  at: string;             // ISO 8601
  kind: 'created' | 'updated' | 'meeting';
  source: 'image' | 'text' | 'both';
  attrs: string[];        // 本次动了哪些属性名，如 ['company']
  background: string;     // 为什么；没有依据则为空字符串
  meeting?: { title: string; startTime: string; endTime: string; location: string; participants: string[] };
};
```

会议只存一条记录，挂在**当前会话的主联系人**名下；`participants` 存原数组，展示时 1 人写名字、2 人写「张三、李四」、3 人以上写「张三等 4 人」。

### 卡片草案

```ts
type CardKind = 'create_contact' | 'update_contact' | 'create_meeting';

type CardDraft = {
  id: string;             // 工具生成，确认时原样带回
  kind: CardKind;
  reason?: string;        // 模型复述的输入原话，confirm 时校对
  payload:
    | { name: string; phone?: string; email?: string; industry?: string; company?: string; position?: string; project?: string; relation?: string }
    | { targetName: string; changes: Record<string, string> }
    | { title: string; startTime: string; endTime: string; location?: string; participants: string[]; remark?: string };
};
```

### 会话与消息

```ts
type ThreadSummary = { id: string; title: string; contactName: string; lastMessage: string; updatedAt: string };

type TraceStep =
  | { kind: 'reasoning'; text: string }
  | { kind: 'tool'; id: string; tool: string; label: string; detail?: string; status: 'running' | 'ok' | 'error' };

type ChatMessage = {
  id: string;
  role: 'user' | 'assistant';
  text?: string;
  imageBase64?: string;   // 用户图，仅用于回显
  cards?: CardDraft[];    // 该条回复附带的卡片草案
  trace?: TraceStep[];    // 这一轮的思考与工具链路
  createdAt: string;
};
```

表结构：

| 表 | 列 |
| --- | --- |
| `threads` | `id` / `title` / `contact_name` / `last_message` / `created_at` / `updated_at` |
| `messages` | `id` / `thread_id` / `role` / `text` / `image_base64` / `cards`(JSON) / `trace`(JSON) / `created_at`；索引 `(thread_id, created_at)` |
| `confirmed_cards` | `card_id`(主键) / `thread_id` / `at` |
| `mastra_*` | 由 Memory 维护，`lastMessages: 20` |

`messages` 是给人看的账（带图、带卡片、带链路，刷新能还原），`mastra_*` 是给模型看的上下文。业务记忆（`contacts` / `interactions`）与两者正交。

## 六、记忆规则

### 1. 属性时间线（SCD2）

- 有新值：旧 `value` 压进 `history`，`to` = 新 `since` 前一天；`value` 换成新值，`since` = 今天
- 值没变：整条不动
- `history` 只增不删；超过 10 段时把最早几段合并成一段，`value` 形如「此前：房地产销售」
- 同一天内改两次：区间收敛成当天有效（`from == to`），展示为「2026-10-30 为 建筑设计」
- `history` 是 `interactions` 的物化投影，只能由确认接口派生，任何读取路径不许写

### 2. `background` 不许模型编

只复述本轮输入（截图文字 + 用户那句话）里明确出现的原因，没有就空字符串。两道关卡：

- 三个出卡工具的 `reason` 参数说明里写清：一句话说明起因、引用输入原话、没有依据就留空
- `services/confirm.ts` 的 `groundBackground()` 做字符串校对：去标点空白后整段命中 → 通过；否则切成三字片段，命中率 ≥ 50% → 通过；都不满足 → 置空并 `console.warn`

校对依据是**该会话最近 6 条消息的正文**（user 与 assistant 都算）：截图里的内容看不见，但助手会把读到的事复述在回复里，这段复述就是依据。

### 3. 写入路径

六个工具全部只读或只出草案。写库只发生在 `POST /api/threads/:id/confirm`，一个事务包住「多条 interaction + attributes 时间线封口/新值」。任一环节失败整体回滚。

`searchCurrent` / `searchHistory` / `embedding` 是派生物，在**事务提交之后**重算：嵌入要发 HTTP 请求，占着写锁等网络会卡死并发确认；嵌入失败也不该让联系人写不进去（该人暂时不参与语义检索，关键词检索照常）。

### 4. 检索：三条路各管一段

`search_contact` 的查找顺序：

1. 姓名 / 电话 / 公司 LIKE `searchCurrent` → `matchedIn: 'now'`
2. LIKE `searchHistory` → `matchedIn: 'history'`
3. 前两步命中少于 3 个时，把 query 嵌入，与全表 embedding 算余弦 → `matchedIn: 'semantic'`

`when: 'now'` 时丢掉只命中 `searchHistory` 的候选。候选最多 10 条，带 `now`（当前值）、`timeline`（可读时间线）、`inDevice`（是否已在系统通讯录）。

向量一人一条，只嵌「姓名 + 5 个当前值」：一条向量只代表一个主题，塞进历史段会摊薄权重；历史段多了还可能超出嵌入输入上限。电话邮箱不进向量，精确查找用 LIKE。

往事由 `search_interactions` 用关键词查 `interactions.background` / `meeting` 原文，不给 `interactions` 建向量。

嵌入模型固定 `BAAI/bge-large-zh-v1.5`（1024 维）。检索文本口径与已存的向量必须一致，全库重算走 `pnpm reindex`。

## 七、Agent

```ts
// server/src/mastra/agent.ts
export const bizAgent = new Agent({
  id: 'bizsnap',
  name: 'bizsnap',
  description: '商务助理：读截图或文字，查人、查历史，整理待确认的记录',
  instructions: buildPrompt(),
  model: chatModel as unknown as MastraLanguageModel,  // ai@7 的 provider 类型与 Mastra 内部 V4 类型字面不一致，运行时一致
  tools: {
    search_contact: searchContact,
    search_interactions: searchInteractions,
    get_contact_history: getContactHistory,
    create_contact: createContact,
    update_contact: updateContact,
    create_meeting: createMeeting,
  },
  memory,   // LibSQLStore + lastMessages: 20
});
```

调用：`bizAgent.stream([{ role: 'user', content }], { instructions: buildPrompt(), memory: { thread, resource: 'owner' }, requestContext, maxSteps: 5 })`。

- 多步上限用 Mastra 的 `maxSteps`，允许「查人 → 查历史 → 出卡」这类多步推理
- `Memory` 只承担会话消息持久化与 `lastMessages: 20`；按人索引的记忆由 `contacts` / `interactions` 承载，跨会话找人一律走数据库检索
- 会话标题（`title.ts`）在首轮 `done` 之后单独生成，失败不影响这一轮

### 系统提示（`buildPrompt()`）

每次请求重建，注入当前时间（`Asia/Shanghai`，含星期）。规则按组给出，全部是硬性的：

1. **身份**：BizSnap 商务助理；用户发截图、文字或两者；从里面读人和事，必要时查过往。
2. **能做什么**：创建联系人、更新联系人、创建会议。
3. **说话方式**：像同事汇报，不提界面 / 按钮 / 确认 / 卡片 / 流程状态；不叙述调用了什么工具、查的是库还是历史；不播报处理过程；整理好的东西还没真正写入时说「整理好了」「这样对吗」，不说「已保存」「已添加」；交代完就停。
4. **内容**：只讲商务事实（谁、哪家公司、职位、时间、谁参加）；信息没齐先问（认识一个人至少要有姓名，约会议必须有开始时间，改资料要能对上是谁）；一次输入多件事分条说；截图与文字冲突时以用户写的字为准；出错用一句自然的话说明，不粘贴原始错误。
5. **落成记录**：这一轮能定下来的必须真的调工具（`create_contact` / `update_contact` / `create_meeting`）；正文里说的每条记录都要有对应工具调用，一次调用只出一条；出错时按第 4 组说人话，不改口说「整理好了」；信息不够、正在追问的那一轮不提前建记录。
6. **只处理商务**：生活闲聊、表情包、广告、代码截图直接回「未识别到商务信息」，不调工具。
7. **查人优先**：涉及某人先 `search_contact`；需要更细履历再 `get_contact_history`；没找到人或只有模糊描述（「上次做跨境支付那个」）用 `search_interactions`；查到多人用一句话问清是哪一位；问「现在」的情况用 `when="now"`。
8. **时间**：相对时间换算成带偏移 ISO 8601（如 `2026-11-04T15:00:00+08:00`）；没说结束时间按 1 小时。
9. **字段连带过期**：换行业/换公司时旧的公司、职位、项目可能失效，先问一句再改；不自己删字段，不在一条消息里连问一串。
10. **记忆**：查得到就说，查不到就说没有记录，不编造。
11. 用中文，简洁具体，不用「我建议您」这类客套。

### 卡片的硬约束

卡片本身只有类型文案 + 勾选框，不显示任何字段。所以正文必须写清本次要写入什么（建谁、改哪项、什么时间、哪些人参加）；信息不够就先追问，不出卡。

## 八、六个工具

注册名（模型看到的 `toolName`）必须与下表一致，服务端靠这些字符串判断草案与链路。

| 工具 | 入参 | 行为 |
| --- | --- | --- |
| `search_contact` | `query: string`、`when?: 'now' \| 'any'`（默认 any） | 三段检索（见第六节），返回 `{ query, when, total, inDevice, candidates: [{ id, name, now, timeline, matchedIn, inDevice }], note }`，最多 10 条；库里没有时 `note` 提示「可能是新联系人」 |
| `search_interactions` | `keywords: string[]`（2~6 字实词）、`limit?`（默认 8） | 关键词再切 2-gram 补充，在 `background` / `meeting` 子串匹配，命中多的排前，返回事件原文（带 `contactName`）交模型判断 |
| `get_contact_history` | `name: string`、`limit?`（默认 8） | 该人完整属性时间线 + 最近 N 条事件；找不到时返回 `{ found: false, message }` |
| `create_contact` | `name`（必填）+ phone / email / industry / company / position / project / relation + `reason?` | 只返回 `{ draft }`；同名已存在时返回 `{ error }`，提示改用 `update_contact` |
| `update_contact` | `target_name`（必填）+ 任意要改字段 + `reason?` | 只返回 `{ draft, current }`；目标不存在或字段全无变化时返回 `{ error }` |
| `create_meeting` | `title` / `start_time`（必填，带偏移 ISO 8601）/ `end_time?` / `participants`（非空数组）/ `location?` / `remark?` / `reason?` | 只返回 `{ draft }`；时间格式非法或结束早于开始时返回 `{ error }`；省略结束时间按 60 分钟补齐 |

`search_contact` 需要设备通讯录快照：从本轮请求的 `contactsSnapshot` 里按姓名归一化或电话后 7 位匹配，用来填 `inDevice`。

## 九、HTTP 接口

除两条出字的接口（发消息、确认）返回 `text/event-stream` 外，其余都是 JSON。所有错误返回 `{ error: string }`。

| 方法 | 路径 | 入参 | 出参 |
| --- | --- | --- | --- |
| GET | `/api/health` | — | `{ ok, model, time }` |
| POST | `/api/threads` | `{ title? }` | `{ threadId }` |
| GET | `/api/threads` | — | `ThreadSummary[]`，`updatedAt` 倒序 |
| PATCH | `/api/threads/:id` | `{ title?, contactName? }` | `{ ok }` |
| DELETE | `/api/threads/:id` | — | `{ ok }`，连消息一起删 |
| GET | `/api/threads/:id/messages` | — | `ChatMessage[]`，卡片带 `confirmed` 标记（按 `confirmed_cards` 判定），带 `trace` |
| POST | `/api/threads/:id/messages` | `{ text?, imageBase64?, contactsSnapshot? }` | SSE |
| POST | `/api/threads/:id/confirm` | `{ cards: [{ id, kind, reason?, payload }] }` | SSE |
| POST | `/api/demo/reset` | — | `{ ok, createdNames, meetingTitles }`，清业务数据 + 会话表，回传要从系统侧删掉的名单 |

`contactsSnapshot` 最多 200 条，只含 `name` / `company` / `position` / `phones`。

### 发消息（`routes/messages.ts`）

1. 校验：`text` 与 `imageBase64` 至少一个；`imageBase64` 超过 12MB 直接 400
2. 先落一条 user 消息（`messages` 表）
3. 组装 content：有图 → `{ type: 'image', image: Buffer.from(base64,'base64'), mediaType }`，mediaType 按文件头判断（`/9j/` JPEG、`iVBORw0KGgo` PNG、`UklGR` WebP，默认 JPEG）；再附文字，未传文字时用默认句「请读这张截图里的商务信息，把能确定的内容整理成记录。」
4. `requestContext.set('contactsSnapshot', ...)`，`bizAgent.stream(...)`，`maxSteps: 5`
5. 消费 `stream.fullStream`，逐帧转发（见第十节）
6. 收尾：正文为空时用兜底文案（有卡片「整理好了，看一眼对不对。」，无卡片「没有识别到可记录的信息。」）；落 assistant 消息（文本 + 卡片 + 链路）→ 推 `done`；首轮无标题时生成标题 → 推 `title`
7. 客户端断开或流异常：删掉本轮 user 消息，不写 assistant 消息

### 确认（`routes/confirm.ts`）

1. `confirmCards()` 单事务落库：`create_contact` 新建或按姓名合并、`update_contact` 更新目标属性、`create_meeting` 写一条 meeting 事件；每张卡写一条 interaction，共用同一个 `groupId`
2. `markCardsConfirmed()` 写 `confirmed_cards`
3. 事务提交后**立即**推 `written`（客户端拿到就开始写系统通讯录/日历）
4. 无洞察素材时走 `streamFailureNote`，仍无文字则用 `statusNote()` 模板兜底（几张成了、哪张没成、为什么）
5. 有素材时 `streamInsight()` 逐字推 `text`，结束后推 `done`

洞察只走流，不写入消息表。

## 十、SSE 协议

一行 `data: <json>`，帧类型放在 JSON 的 `type` 字段里；客户端只按行读、只认 `data:` 前缀。心跳用 `withSseHeartbeat(response, 15000)`，只在两帧之间插 `: heartbeat` 注释。

| `type` | 载荷 | 出现于 | 说明 |
| --- | --- | --- | --- |
| `start` | `{ threadId, messageId }` | 发消息 | 建流后立即发 |
| `reasoning` | `{ delta }` | 发消息 | 模型思考增量，客户端往后接 |
| `tool` | `{ step: TraceStep }` | 发消息 | 工具调用一步；同一 `id` 再来一帧表示状态变化（running → ok/error） |
| `text` | `{ delta }` | 两条流 | 正文 / 洞察增量 |
| `card` | `{ card }` | 发消息 | 三个出卡工具一返回就推 |
| `written` | `{ written: [{ cardId, kind, contactName, background, ok, error? }], contactName }` | 确认 | 事务提交后第一帧 |
| `done` | `{ message?, insight?, contactName?, title? }` | 两条流 | 结束帧；发消息带落库后的完整消息，确认带洞察全文 |
| `title` | `{ title }` | 发消息 | `done` 之后补的会话标题 |
| `error` | `{ error }` | 两条流 | 中途失败 |

约定：

- 卡片帧先于文字到达（模型先调工具后写字）；客户端把它们收在 `done` 的正式消息里一起渲染
- `done` 是权威：正文以它为准覆盖增量
- 客户端断开 → 停止消费上游、删掉本轮 user 消息、不写 assistant 消息
- 链路（`reasoning` / `tool`）随流下发，同时按顺序落进 `messages.trace`，重开会话时照原样还原

### 链路的中文标签

`services/trace.ts` 维护工具名 → 标签映射，未知工具回落成原工具名：

| 工具 | 标签 |
| --- | --- |
| `search_contact` | 查联系人 |
| `search_interactions` | 查往来记录 |
| `get_contact_history` | 查履历 |
| `create_contact` | 整理联系人 |
| `update_contact` | 整理资料更新 |
| `create_meeting` | 安排会议 |

`detail` 从入参里按 `query` → `target_name` → `name` → `title` 顺序取第一个非空值（截断 40 字）。`snapshot()` 落库前过滤掉纯空白思考段。

## 十一、洞察生成

`services/insight.ts`，用 `ai` 的 `streamText`（`deepseek-flash`，不带工具），`textStream` 每个 chunk 直接推 `text` 帧；结束后把全文留在 `done` 里。

输入：该联系人全部 `attributes`（含 history）、最近 8 条 `interactions`、本次刚写入的 `interactions`。

要求：1–3 句中文，先说时间线上的一个具体事实（认识多久、换过什么、上次见面距今多久），再给一条可执行的下一步建议（问什么、约谁、什么时候）。

约束：只用输入里存在的信息；不出现「依据」「根据记录」这类标签；不写「保持联系」「继续跟进」这类空话；不超过 120 字。

## 十二、iOS 客户端

### 工程配置（`project.yml`）

iOS 17.0、`PRODUCT_BUNDLE_IDENTIFIER = com.newking.bizsnap`、竖屏、`Info.plist` 里给通讯录 / 日历（读写与只写）/ 相册 / 相机 / 本地网络五类权限文案，`NSAppTransportSecurity` 放行 `127.0.0.1` 与 `localhost` 明文 HTTP，`NSAllowsLocalNetworking = true`。服务地址默认 `http://127.0.0.1:8787`，存在 `AgentClient` 里，设置页可改。

### 主题（`Theme/Tokens.swift`）

跟随系统外观，同一语义色两套取值：

| 语义 | 浅色 | 深色 |
| --- | --- | --- |
| background | `#F5F5F3` | `#0B0B0A` |
| surface | `#FCFCFB` | `#151515` |
| elevated | `#FFFFFF` | `#1A1A19` |
| inset | `#F0F0EE` | `#20201E` |
| accent | `#3D6EF0` | `#5B8CFF` |
| accentSoft | `#5B8CFF` | `#7AA2FF` |
| textPrimary | `#111318` | `#E9EBEF` |
| textSecondary | `#565E6C` | `#9BA1AB` |
| textTertiary | `#8A91A0` | `#6B7280` |
| green / orange / red | `#1FA84E` / `#E08600` / `#E03127` | `#34C759` / `#FF9F0A` / `#FF453A` |
| stroke | 黑 | 白 |

圆角 16，间距基数 8；`glassCard` 修饰符统一「半透明叠加 + 1px 细边」；`accentGradient` 用于主按钮。

### 页面结构

打开即聊天（`RootView`）：最近一次会话直接恢复，左边抽屉（`ThreadDrawer`）切会话 / 新建 / 改名 / 删除，抽屉底部进设置。

**聊天页（`ChatView`）**

- 顶部：左汉堡开抽屉，中间标题（可点改名）+ 服务状态圆点，右侧 `confirming` 时显示小菊花
- 消息流：气泡 + 卡片，`AgentTraceView` 在气泡上方
- 空态：一句轻提示「把一段商务对话，变成通讯录里的一条记录」
- 流式气泡：首字之前显示竖条 loading（`TypingBars`：5 根 3×15 胶囊，`scaleEffect(y:)` 在 1 ↔ 0.3 之间，每根延迟 0.1s、0.45s 一次往返，颜色 `textSecondary`）；首字到达后换成真实气泡 + 光标
- 输入栏（`Composer`）：左侧图片按钮直接打开相册（不弹二级菜单），中间输入框，右侧发送；选图后上方显示缩略图与「×」
- 卡片全部收在消息里，不单独成区

**会话列表（抽屉）**：每行首字头像 + 标题 + 最后一句摘要 + 时间；顶部「BizSnap」+ 新建按钮；行左滑删除、长按改名。

**设置页**：服务地址输入与保存、健康检查、清空全部数据（调 `/api/demo/reset`，再按回传名单删系统侧联系人 / 日历事件）。

### 卡片（`CardStrip`）

- 整宽窄条：左侧类型文案（创建联系人 / 创建会议 / 更新联系人），右侧圆形勾选框；不显示字段、时间、依据
- 同类型只认最后一张：更早的同类型卡 40% 透明、勾选框禁用；不同类型互不影响
- 选中：描边变 accent、整体轻微放大
- 流式阶段用 `pending` 样式不可点；`done` 之后才参与勾选
- 确认成功后原地折叠成一行状态话术：写进日历「已写入日历」、写进通讯录「已写入通讯录」；服务端已落库但系统未写入时不能显示「已写入」
- 单张卡片写入失败：标红 + 重试按钮，权限类错误给「去设置」

### 确认条

- 有勾选时出现在输入栏上方，文案「确认选中 N 项」，主色渐变；`confirming` 时禁用并显示菊花
- 点确认先做日历权限判断（会议卡且未授权时弹解释），再发起 `/confirm`
- `written` 到达 → 逐张写系统（`CardExecutor` + `ContactsService` / `CalendarService`），成功折叠、失败标红；同时 agent 会补一条文字说明为什么没成
- 写库成功才收起；失败或部分失败时按钮留在原处可再次提交
- 条出现时气泡区同步让位：先贴底，再从底部升起

### 链路展示（`AgentTraceView`）

- 左侧一根竖向细线，右侧按顺序排思考与工具行
- 思考：11.5pt 斜体、`textTertiary`、最多 2 行截断
- 工具行：SF Symbol 图标 + 中文标签 + `· 入参`；右端状态：调用中空心圆、成功对勾、失败感叹号
- 整体 `opacity 0.72` + 低透明度大半径阴影（朦胧感）+ 3.4s 往返的 ±1px 缓慢浮动；新行淡入
- 流式阶段随事件长出来（`reasoning` 逐字追加，`tool` 按 id 就地改状态），`done` 之后由正式消息的 `trace` 接管

### 滚动

- 贴底滚动统一指向消息列表末尾的一个恒定空视图，它常驻在列表里
- 消息数变化、卡片出现、确认条出现/收起、错误条出现、链路变长 → 贴底；卡片浮现这类延后占位的情况在动画收尾时补滚一次
- 逐字流式时直接贴底，不加动画

### 图片

- 发送前压缩：按总像素不超过 1300×1300 等比缩放、JPEG 质量 0.7（对齐 DeepSeek 视觉对每图缩放的上限）
- 回显解码结果按消息 id 缓存（`NSCache`）

### 反馈规则

任何一次交互都要落一句话到消息流里：

- 失败时有半截内容就留半截，一句都没有就补一句人话（`AgentFeedback` 统一措辞），绝不产生空消息
- 卡片类失败就地标红 + 重试，同时补一条 agent 文字说清为什么没成、下一步做什么
- 服务端确认流由 `statusNote()` 兜底，不能只发一个空的 `done`

## 十三、脚本

| 脚本 | 作用 |
| --- | --- |
| `scripts/env.ts` | 从 `server/.env` 读 key；找不到文件就提示复制 `.env.example` |
| `scripts/check-embedding.ts` | 调 `BAAI/bge-large-zh-v1.5` 嵌入一句中文，打印维度并断言 1024 |
| `scripts/check-vision.ts` | 现场画一张 512×512 PNG，发给 `deepseek-flash` 问「描述图片内容」；失败时改用 `createOpenAICompatible({ baseURL: 'https://api.deepseek.com' })` 再试一次 |
| `scripts/reindex-embeddings.ts` | 遍历全库重写 `searchCurrent` / `searchHistory` / `embedding`（`pnpm reindex`） |
| `scripts/ios-run.sh` | 编译 → 装进已启动的模拟器（默认 iPhone 17）→ 启动 app；`bash scripts/ios-run.sh [UDID]` |

脚本只用 Node 内置模块与全局 `fetch`，通过 `server/package.json` 的 npm script 调用（`tsx ../scripts/xxx.ts`）。

## 十四、实现顺序

1. `server` 骨架：package.json、tsconfig、config、index（Hono 起服务、`/api/health`）
2. `scripts/check-embedding.ts` 与 `scripts/check-vision.ts` 跑通
3. `db/`：建表、读写、检索
4. `mastra/`：agent + prompt + 六个工具（先三个只读，再三个出草案）
5. `services/`：attributes、embedding、confirm、insight、trace、demo-seed
6. `routes/`：threads、messages、confirm、demo；两条 SSE 流按第十节帧表实现
7. iOS：XcodeGen 工程 + 主题 + 聊天页 + 抽屉 + 设置
8. 卡片窄条、多选、确认条、系统写入
9. 链路展示、loading、滚动与错误反馈
10. 按第十五节验收

## 十五、验收

前置：`pnpm dev` 起服务，`bash scripts/ios-run.sh` 装 app，设置页填服务地址、需要时「清空全部数据」。从空库开始，数据全部由对话 + 确认产生。

**Case 1 截图 → 卡片**：发一张含姓名、公司、职位、约见时间的商务聊天截图。
预期：正文逐字出现，卡片在正文之后显示；正文说清建谁、什么公司职位、约在何时、去哪里；出现「创建联系人」+「创建会议」两张卡；链路里能看到「查联系人」「整理联系人」「安排会议」；勾选两张 →「确认选中 2 项」→ 确认后折叠，系统通讯录与日历里能看到对应条目。

**Case 2 跨会话找人**：新建会话，只说「上次做跨境支付那个，最近有联系吗」。
预期：agent 自己检索，报出命中的人（如陈默 / 李静），一句话问清是哪一位；正文体现过去与现在的区别。追加「现在谁在做跨境支付」，`when='now'` 生效，只报当前仍在做这件事的人。

**Case 3 更新与洞察**：发「李静已经从 C 公司跳到 D 公司了，还在管供应链，项目也从供应链优化换成了仓储自动化」。
预期：出现一张「更新联系人」卡；正文写清公司 C → D、项目变更，职位未提新头衔时保留；确认后卡片折叠，`attributes` 里 `company.value = D 公司`、`since = 今天`、`history` 多出 C 公司那段；随后洞察逐字流出，含基于时间线的具体事实 + 一条可执行的跟进建议。

**Case 4 不落库**：出一张卡但不确认，退出再进。
预期：库里查不到该人，聊天记录与卡片仍在。

**Case 5 非商务输入**：发「哈哈哈今天好累啊，晚上吃啥」。
预期：只回「未识别到商务信息」，不调工具、不出卡。

## 十六、硬性约束

- 六个工具只读或只出草案；写库只发生在确认接口，单事务
- `history` 与检索列只由确认流程派生，任何读取路径不写
- `background` 只复述输入里出现的原因，没有依据就留空
- 跨会话找人只走数据库检索，不用聊天消息向量召回
- 洞察只回给前端，不落库
- 卡片只读：内容不对就在输入栏继续说一句，agent 重出卡片，旧卡自动置灰
- 系统通讯录只能承载 name / phone / email / company / position；industry / project / relation 只在本应用内
- 以本地库为准，先落库再写系统：通讯录写错不可撤回
- 时间一律带时区偏移的 ISO 8601；iOS 写 EventKit 前用 `ISO8601DateFormatter` 校验
