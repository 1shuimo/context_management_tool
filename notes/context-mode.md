# `context-mode` 详细调研

## 基本信息

- 本地目录：`research/context-mode`
- 远程仓库：[`mksglu/context-mode`](https://github.com/mksglu/context-mode)
- 当前本地 `HEAD`：`3469b7ab422afc0323bfde76ba67c80f7fbe8570`
- 包名：`context-mode`
- 定位：MCP server + hook/plugin 组合，用于减少工具输出进入上下文，并在 compaction 后恢复会话状态

## 为什么它和 agent runtime 优化直接相关

在这批本地仓库里，`context-mode` 最接近“runtime 外挂上下文虚拟化层”。

它不是单纯做：

- prompt 摘要
- 长期 memory
- CLI 输出压缩

它更接近在 runtime 内增加两层能力：

1. **把重输出先挪到 sandbox / 本地索引，而不是直接塞进 prompt**
2. **在会话 compact 之后，用结构化 snapshot 和全文检索把工作状态拉回来**

如果你已经有自己的 agent 运行链路，这个仓库最值得拆出来借鉴的不是整套产品形态，而是几个内部模块：

- 工具输出进入 prompt 之前的“轻量化返回策略”
- 本地 FTS5 检索层
- session event 抽取和 resume snapshot 构建

## 关键源码入口

- 输出执行与意图检索：
  - [`research/context-mode/src/server.ts`](../research/context-mode/src/server.ts)
    - 注册 `ctx_execute`、`ctx_search` 等 MCP 工具，并决定大输出是直接截断返回，还是先入库再按 `intent` 做薄返回。
- 截断逻辑：
  - [`research/context-mode/src/truncate.ts`](../research/context-mode/src/truncate.ts)
    - 实现 `smartTruncate()`，核心是保留头尾关键片段并插入省略提示，而不是简单砍前 N 行。
- 本地知识库：
  - [`research/context-mode/src/store.ts`](../research/context-mode/src/store.ts)
    - `ContentStore` 的主体，负责 SQLite/FTS5 建库、chunking、索引、BM25 检索和 fuzzy fallback。
- session snapshot：
  - [`research/context-mode/src/session/snapshot.ts`](../research/context-mode/src/session/snapshot.ts)
    - 把 session events 抽成 resume artifact，并按优先级控制哪些状态必须在 compact 后恢复。
- session DB：
  - [`research/context-mode/src/session/db.ts`](../research/context-mode/src/session/db.ts)
    - 负责 session event 的落库、查询和生命周期管理，是 snapshot builder 的底层数据面。
- Codex / 各平台适配：
  - [`research/context-mode/src/adapters/`](../research/context-mode/src/adapters)
    - 把 Claude Code、Gemini CLI、Codex CLI 等平台统一抽象到同一套 hook 生命周期接口上。

## 核心机制

### 1. MCP 工具层

`server.ts` 注册的核心工具包括：

- `ctx_execute`
- `ctx_execute_file`
- `ctx_batch_execute`
- `ctx_index`
- `ctx_search`
- `ctx_fetch_and_index`

这套设计的重点不是“执行更多工具”，而是把高噪声操作改写成：

- 在 sandbox 里运行
- 只让必要摘要/片段进入上下文
- 原始大内容进入本地存储或索引

这对自有 runtime 的意义是：

- 你的 tool runtime 不一定要换成 MCP
- 但可以复用同样的“tool result -> store/index -> thin return”思路

### 2. 大输出处理有两条路

#### 路径 A：`smartTruncate()`

[`truncate.ts`](../research/context-mode/src/truncate.ts) 里的 `smartTruncate()` 不是简单截头，而是：

- `60%` 保留头部
- `40%` 保留尾部
- 中间打上截断说明

它针对的是：

- 构建日志
- 测试输出
- shell 输出

这种实现很实用，但它仍然只是“更聪明的截断”，不是可逆压缩。

#### 路径 B：`intentSearch()`

当 `ctx_execute` 或 `ctx_execute_file`：

- 传入了 `intent`
- 且输出大于 `5_000` bytes

`server.ts` 会走 `intentSearch()`：

1. 把完整输出 `indexPlainText()` 到本地 store
2. 用 `intent` 作为查询去命中 relevant section
3. 返回：
   - 匹配到的 section 标题
   - 首行 preview
   - searchable terms

也就是说，模型不会拿到整份原始输出，而是先拿到一份“检索导览页”。

这是这个仓库最值得借鉴的地方之一：

- 不是所有大输出都要直接进模型
- 可以先给模型一个检索入口页
- 再让模型决定是否继续 `search()`

### 3. `ContentStore` 是真实可用的本地检索层

[`store.ts`](../research/context-mode/src/store.ts) 不是玩具实现。

它有这些关键点：

- SQLite FTS5
- `porter unicode61` tokenizer
- trigram FTS5
- fuzzy fallback
- BM25 排序

支持的 chunking 也不止一种：

- markdown heading chunking
- plain text line-group chunking
- JSON tree chunking

这意味着它对以下 runtime 产物都适用：

- 文档和 README
- shell/test/build/log 输出
- 网页抓取结果
- JSON API 返回
- MCP tool inventory

如果你要在自有 agent runtime 里加“可检索上下文外存”，这里基本已经是一套可以直接拆用的最小内核。

### 4. session continuity 做得很完整

[`session/snapshot.ts`](../research/context-mode/src/session/snapshot.ts) 和
[`session/db.ts`](../research/context-mode/src/session/db.ts) 组合起来，解决的是：

- compact 之后 agent 如何知道自己刚才在干什么

它会记录和提取：

- active files
- task state
- rules
- decisions
- cwd / env / git
- errors
- subagents / intent / mcp

snapshot 不是无预算拼接，而是优先级分层：

- `P1`: file / task / rule
- `P2`: cwd / error / decision / env / git
- `P3-P4`: intent / mcp / subagent

这对你自己的 runtime 很重要，因为真正有用的不是“把聊天摘要一下”，而是：

- **把 runtime state 提炼成结构化 resume artifact**

这可以在任何 agent stack 上复用，不依赖它的产品外壳。

### 5. 多平台适配是产品层，真正可借鉴的是适配抽象

`src/adapters/` 下把不同平台抽象成统一 `HookAdapter`。

支持面包括：

- Claude Code
- Gemini CLI
- VS Code Copilot
- OpenCode
- Codex CLI

对你自己的 runtime 来说，关键不在于是否复用这些平台 adapter，而在于这个抽象边界：

- `preToolUse`
- `postToolUse`
- `preCompact`
- `sessionStart`

如果你自己的 runtime 里也能定义这几个事件点，那 `context-mode` 的 session 和 routing 模块就很容易嫁接。

## 它最强的地方

### 强项 1：把“检索”做成默认数据面，而不是补充功能

很多项目只是把东西存起来；`context-mode` 则是：

- 先索引
- 再按 query 返回薄结果

这更接近 runtime 真正能省上下文的工作方式。

### 强项 2：session continuity 是一等公民

它不是“索引一下日志”就结束，而是：

- 存 session event
- build snapshot
- compact 后恢复

这对长任务 runtime 非常重要。

### 强项 3：模块边界清楚

如果不想整套搬运，最容易拆出来的是：

- `ContentStore`
- `snapshot builder`
- `intentSearch` 这一层策略

## 它不解决什么

### 1. 不是严格可逆工具输出压缩

它没有做到：

- 每个大工具输出都变成稳定 handle
- 按 handle 完整恢复原始 payload
- `read(handle)` / `slice(handle)` / `search(handle, query)` 这种显式接口

它更像：

- 原文被索引
- 后续按 query 找 chunk

### 2. 不是你 runtime 的前置拦截器

它虽然能在某些平台上通过 hook 起作用，但如果你有自己的 runtime：

- 你仍然需要自己定义 intercept 点
- 然后把它的 store / snapshot / search 模块接进去

### 3. 它的默认输出路径里仍有截断

没传 `intent` 的大输出，还是可能进入 `smartTruncate()`。

这对“完全不想把大原文放进 prompt”的场景仍然不够硬。

## 对自有 agent runtime 最值得借鉴的部分

### 最值得直接复用

1. `ContentStore`
2. `intentSearch()` 这一套“先索引再给命中导航”的返回策略
3. session snapshot builder

### 最值得模仿但不一定直接复用

1. 平台 adapter 抽象
2. hook / plugin 注册逻辑
3. sandbox 执行工具包装

### 最需要你自己补的部分

1. stable handle 层
2. raw payload store
3. 你自己 runtime 的 tool lifecycle 注入点

## 结论

`context-mode` 在这批本地仓库里最像：

> 可检索的上下文虚拟化层 + 会话连续性层

如果你要优化的是自己的 agent runtime，而不是某个现成 CLI，它最值得拿走的不是平台接入，而是：

- **`store`**
- **`intentSearch`**
- **`session snapshot`**

这三块可以作为你 runtime 里的中间层，放在：

- tool execution 之后
- prompt assembly 之前
- compact / resume 边界上
