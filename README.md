# Agent Runtime Context Optimization Research

截至 `2026-03-08`，这个仓库的目标已经固定成一件事：

> 为你自己的 agent runtime 设计一套更稳的上下文优化层，而不是只给某个现成 CLI 打补丁。

这不是源码产品仓库，而是一个调研与设计仓库：

- `notes/` 放每个项目的详细笔记
- 根 `README.md` 只保留总览、比较和拼装建议
- `research/` 是本地镜像区，用来放上游 GitHub 项目的 checkout

## 快速开始

如果你只是想看结论，直接读：

- [`notes/README.md`](notes/README.md)
- [`notes/context-mode.md`](notes/context-mode.md)
- [`notes/context-gateway.md`](notes/context-gateway.md)
- [`notes/headroom.md`](notes/headroom.md)

如果你想在本地对照源码继续读：

```bash
bash scripts/bootstrap_research.sh
```

这会把上游项目 clone 到 `research/`，并自动 checkout 到当前笔记引用的固定 commit。主仓库默认不跟踪这些上游源码，避免把 9 个外部仓库直接塞进一个 GitHub 仓库里。

如果你只想拉各仓库最新默认分支，也可以运行：

```bash
bash scripts/bootstrap_research.sh latest
```

## 仓库结构

```text
.
├── README.md
├── notes/
│   ├── README.md
│   ├── context-mode.md
│   ├── context-gateway.md
│   ├── headroom.md
│   ├── reme.md
│   ├── ctx-zip.md
│   ├── deepagents.md
│   ├── letta.md
│   ├── mem0.md
│   ├── rtk.md
│   └── claude-context-mode.md
├── research/              # 本地镜像区，默认不纳入主仓库版本管理
└── scripts/
    └── bootstrap_research.sh
```

## 当前本地盘点

这轮重新核对后，当前 `research/` 里的实际 Git 仓库是 9 个：

| 本地目录 | 上游仓库 | 定位 | 详细笔记 |
|---|---|---|---|
| `research/context-mode` | [`mksglu/context-mode`](https://github.com/mksglu/context-mode) | 输出外置检索 + session continuity | [`notes/context-mode.md`](notes/context-mode.md) |
| `research/Context-Gateway` | [`Compresr-ai/Context-Gateway`](https://github.com/Compresr-ai/Context-Gateway) | API gateway + preemptive compaction + tool discovery filtering | [`notes/context-gateway.md`](notes/context-gateway.md) |
| `research/headroom` | [`chopratejas/headroom`](https://github.com/chopratejas/headroom) | 通用压缩中间层 + 可逆 CCR + memory bridge | [`notes/headroom.md`](notes/headroom.md) |
| `research/rtk` | [`rtk-ai/rtk`](https://github.com/rtk-ai/rtk) | shell/CLI 输出前门压缩 | [`notes/rtk.md`](notes/rtk.md) |
| `research/ctx-zip` | [`karthikscale3/ctx-zip`](https://github.com/karthikscale3/ctx-zip) | 轻量级文件落盘式 tool result compaction 库 | [`notes/ctx-zip.md`](notes/ctx-zip.md) |
| `research/ReMe` | [`agentscope-ai/ReMe`](https://github.com/agentscope-ai/ReMe) | 文件记忆 + 向量记忆 + tool result compact | [`notes/reme.md`](notes/reme.md) |
| `research/deepagents` | [`langchain-ai/deepagents`](https://github.com/langchain-ai/deepagents) | orchestration / subagent / compact runtime | [`notes/deepagents.md`](notes/deepagents.md) |
| `research/letta` | [`letta-ai/letta`](https://github.com/letta-ai/letta) | stateful memory runtime | [`notes/letta.md`](notes/letta.md) |
| `research/mem0` | [`mem0ai/mem0`](https://github.com/mem0ai/mem0) | 外部长期记忆服务层 | [`notes/mem0.md`](notes/mem0.md) |

额外还有一份历史残留笔记：

- [`notes/claude-context-mode.md`](notes/claude-context-mode.md)

它不再对应当前 `research/` 里的真实仓库，只保留为旧调研草稿的说明。

## 为什么不用 Submodule

当前这个仓库更适合作为：

- 调研总览
- 结构化笔记
- 上游项目导航入口

而不是 9 个外部仓库的聚合源码仓库。

所以这里默认选择：

- 在 `README` 和 `notes/README.md` 里放上游 GitHub 超链接
- 用 `scripts/bootstrap_research.sh` 在本地拉源码镜像
- `research/` 默认不纳入主仓库版本管理

不默认用 submodule 的原因很直接：

- clone 后经常还要额外 `--recurse-submodules`
- GitHub 浏览时，submodule 仍然只是跳转入口，不比普通链接更清晰
- 9 个子模块会让仓库维护、提交和同步都变重
- 你这个仓库的主价值是“文档与结论”，不是“托管上游源码”

如果后面你只想长期跟踪 1 到 2 个核心项目，再单独加 submodule 会更合理。

## 你真正要解决的问题

如果目标是优化自有 agent runtime，而不是优化某个现成产品，那么问题更适合拆成 6 层：

1. **工具结果前门压缩**
   大 shell / test / build / grep / gh 输出，能不能在进入 prompt 前先压掉。

2. **输出外置与按需取回**
   大内容能不能不直接塞 prompt，而是先落到本地或外部存储，需要时再读回。

3. **API / proxy 侧压缩与可逆恢复**
   如果你控制 LLM API 边界，能不能在请求/响应层做后台压缩、可逆 retrieval、工具发现过滤。

4. **会话连续性**
   compact 后，agent 还能不能知道自己刚才在编辑什么、做到了哪一步、有哪些规则和决策。

5. **长期记忆**
   哪些信息应该进入长期 memory，而不是继续挂在当前会话上下文里。

6. **任务编排与上下文隔离**
   哪些工作应该切给子代理或局部上下文，而不是持续污染主上下文窗口。

## 总结论

### 1. 现在依然没有一个仓库单独闭环

如果标准是：

- 大输出尽量不进 prompt
- 需要时能按稳定引用或检索取回
- compact 后还能恢复工作状态
- 还能维护长期记忆和子任务隔离

那么当前本地 9 个仓库里，依然没有任何一个单独覆盖完整解。

### 2. `context-mode` 仍然是最接近“runtime 本地上下文虚拟化层”的实现

原因见 [`notes/context-mode.md`](notes/context-mode.md)：

- 有 `ContentStore`
- 有 `intentSearch()` 这种“先索引，再给导航页”的薄返回
- 有 session event 和 resume snapshot

如果你已经有自己的 runtime，它最适合放在：

- tool execution 之后
- prompt assembly 之前
- compact / resume 边界上

### 3. `rtk` 仍然是最强的 shell / CLI 前门压缩层

原因见 [`notes/rtk.md`](notes/rtk.md)：

- rewrite registry 成熟
- 按命令族做压缩器
- 有 tee fallback

它最适合放在：

- shell / cli tool adapter 层

### 4. `Context-Gateway` 和 `headroom` 把“代理前压缩”往 API 层推进了一步

两者都值得看，但位置不完全一样：

- [`notes/context-gateway.md`](notes/context-gateway.md)
  - 更像真正插在 agent 与 provider API 之间的 gateway
  - 强项是 **后台预压缩**、**tool discovery filtering**、**expand_context selective replace**

- [`notes/headroom.md`](notes/headroom.md)
  - 更像通用 SDK / middleware / proxy
  - 强项是 **content-aware transform pipeline**、**CCR 可逆 retrieval**、**memory bridge**

如果你控制的是 HTTP/API 边界，而不只是本地工具链，这两条路线比上一轮调研更值得纳入。

### 5. `ReMe` 和 `ctx-zip` 补的是“文件化外置”这一层

- [`notes/reme.md`](notes/reme.md)
  - 更适合“可读写 markdown memory + tool_result 文件缓存 + hybrid search”

- [`notes/ctx-zip.md`](notes/ctx-zip.md)
  - 更适合“轻量级 SDK，把工具结果落盘，再靠 `sandbox_cat/grep/find` 按需读回”

它们都不是完整 runtime，但都对“别把大工具结果直接塞 prompt”这件事有现实价值。

### 6. `deepagents` / `letta` / `mem0` 的位置没有变

- [`notes/deepagents.md`](notes/deepagents.md)
  - 最值得借鉴的是 orchestration、subagent 隔离、compact 事件

- [`notes/letta.md`](notes/letta.md)
  - 最值得借鉴的是 memory tiering 和 memory tools

- [`notes/mem0.md`](notes/mem0.md)
  - 最值得借鉴的是外部长期记忆 API、scope 建模、增量维护

## 一页对比表

| 项目 | 最值得借鉴的层 | 最强能力 | 不要误判成什么 | 详细笔记 |
|---|---|---|---|---|
| `context-mode` | 输出外置检索 + session continuity | FTS5/BM25 + intent search + snapshot | 通用 HTTP proxy | [`notes/context-mode.md`](notes/context-mode.md) |
| `Context-Gateway` | API gateway 压缩层 | preemptive compaction + tool discovery filtering | 完整 session state runtime | [`notes/context-gateway.md`](notes/context-gateway.md) |
| `headroom` | 通用压缩中间层 | content-aware pipeline + CCR reversible retrieval | coding-agent 专用 snapshot 系统 | [`notes/headroom.md`](notes/headroom.md) |
| `rtk` | 工具结果前门压缩 | rewrite + command-family compressor + tee | 长期 memory runtime | [`notes/rtk.md`](notes/rtk.md) |
| `ctx-zip` | 轻量文件外置库 | write-to-file + sandbox readers + boundary compaction | 全功能 retrieval system | [`notes/ctx-zip.md`](notes/ctx-zip.md) |
| `ReMe` | 文件记忆 + tool result compact | MEMORY.md / memory/ / tool_result/ + hybrid search | 通用 shell 前门压缩器 | [`notes/reme.md`](notes/reme.md) |
| `deepagents` | orchestration + compact + subagent isolation | task/subagent + summarization middleware | 原始输出 handle store | [`notes/deepagents.md`](notes/deepagents.md) |
| `letta` | runtime 内分层 memory | core / recall / archival / summary memory | CLI 输出压缩器 | [`notes/letta.md`](notes/letta.md) |
| `mem0` | 外部长期记忆服务 | scoped memory API + update loop + graph/rerank | 会话 compaction 引擎 | [`notes/mem0.md`](notes/mem0.md) |

## 面向自有 runtime 的拼装建议

### 方案 A：先挡住最痛的 prompt 污染

适合你已经有稳定 runtime，只想先减少上下文爆炸。

建议组合：

1. `rtk` 风格的 tool-result front-door compression
2. `context-mode` 风格的本地索引与 thin return

最小落地是：

- shell / build / test / grep / git 先走压缩器
- 大于阈值的输出不直接回 prompt
- 进入本地 store
- prompt 里只放摘要、section 导航、searchable terms

### 方案 B：如果你控制 LLM API 边界，优先二选一

不要一开始同时上 `Context-Gateway` 和 `headroom`，因为两者都在代理前做压缩。

优先这样选：

- 选 `Context-Gateway`
  - 如果你最在意“压缩别阻塞对话”
  - 如果你想做后台预计算 summary
  - 如果你还想顺手做工具清单瘦身与按需扩展

- 选 `headroom`
  - 如果你想要 `compress(messages)` 这种可嵌入 SDK 形态
  - 如果你更在意内容类型路由与可逆 retrieval
  - 如果你希望以后把 memory bridge 也接进去

### 方案 C：把 compact 升级成 runtime 事件

适合你已经开始遇到长任务恢复问题。

建议组合：

1. `context-mode` 的 session event + snapshot builder
2. `deepagents` 的显式 compact 工具和 subagent 分流模式

关键不是“生成一段摘要”，而是定义：

- `pre_compact`
- `post_compact`
- `resume`

这三个 runtime 边界。

### 方案 D：长期状态不要继续塞在聊天窗口里

适合你已经准备把 runtime 做成长生命周期 agent。

优先这样分工：

- **会话态工作状态**
  - active files
  - current task
  - recent decisions
  - recent errors
  - 用 `context-mode` 式 snapshot 或 `ReMeLight` 式文件记忆管理

- **长期业务记忆**
  - user facts
  - domain facts
  - long-term summaries
  - procedural hints
  - 用 `mem0` 或 `letta` 式 memory 层管理

## 当前最明显的缺口

和上一轮相比，现在最接近“稳定 handle”这一层的已经不只是 `context-mode` / `rtk`：

- `headroom` 有 CCR retrieval
- `Context-Gateway` 有 shadow ID + expand_context
- `ctx-zip` / `ReMe` 有文件落盘引用

但它们依然没有真正提供一个统一的、runtime 级别的 handle API，例如：

- `read(handle)`
- `slice(handle, start, end)`
- `search(handle, query)`
- `materialize(handle)`
- `attach(handle, policy=...)`

也就是说：

> 现在有若干“局部可逆”或“局部可回看”的实现，但还没有一个统一覆盖工具输出、检索、恢复、上下文注入策略的 runtime-wide stable handle layer。

如果你下一步要把 runtime 做深，这一层仍然值得自己补。

## 当前状态

- [x] 重新核对本地 9 个实际 Git 仓库
- [x] 修正总览里过期的仓库数量与结论
- [x] 补齐 `Context-Gateway`、`headroom`、`ReMe`、`ctx-zip` 的独立笔记
- [x] 把目录整理成可发布的 GitHub 文档仓库骨架
- [ ] 下一轮如果继续做：
  - 把笔记中的本地源码引用进一步改成 commit-pinned GitHub 链接
  - 或者抽一层统一的 handle-first 设计文档
