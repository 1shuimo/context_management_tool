# `ReMe` 详细调研

## 基本信息

- 本地目录：`research/ReMe`
- 远程仓库：[`agentscope-ai/ReMe`](https://github.com/agentscope-ai/ReMe)
- 当前本地 `HEAD`：`f408d6ec4a6141aeddd3a76f943bcec83714a503`
- Python 包名：`reme_ai`
- 定位：面向 AI agents 的 memory toolkit，同时提供 file-based memory 和 vector-based memory

## 为什么它和 agent runtime 优化相关

`ReMe` 不是只做长期向量记忆，也不是只做一个工具输出压缩器。

它更像是在回答这个问题：

> **如果 agent 既要在有限上下文里继续工作，又要把有价值的信息和大 tool result 放到文件或检索层里，该怎么组织？**

它的特别之处在于：

- 文件记忆路线是显式的、可读的
- tool result compact 被纳入了 memory pipeline
- 向量记忆和 procedural memory 也被保留了扩展路线

## 关键源码入口

- file-based 入口：
  - [`research/ReMe/reme/reme_light.py`](../research/ReMe/reme/reme_light.py)
    - `ReMeLight` 主入口，负责把 file memory、tool result compact、summary task 和 search 组装成一套轻量运行流。
- tool result compactor：
  - [`research/ReMe/reme/memory/file_based/components/tool_result_compactor.py`](../research/ReMe/reme/memory/file_based/components/tool_result_compactor.py)
    - 超阈值工具结果写入 `tool_result/`，正文只留截断版与文件引用，并负责过期文件清理。
- context checker：
  - [`research/ReMe/reme/memory/file_based/components/context_checker.py`](../research/ReMe/reme/memory/file_based/components/context_checker.py)
    - 按 token 预算拆分“保留消息”和“待压缩消息”，并尽量保证 turn 与 tool pair 不被截断。
- conversation compactor：
  - [`research/ReMe/reme/memory/file_based/components/compactor.py`](../research/ReMe/reme/memory/file_based/components/compactor.py)
    - 用结构化摘要模板压缩长对话，保留目标、进度、决策和待办等可恢复信息。
- memory search：
  - [`research/ReMe/reme/memory/file_based/tools/memory_search.py`](../research/ReMe/reme/memory/file_based/tools/memory_search.py)
    - 对 `MEMORY.md` 和 `memory/*.md` 做 hybrid search，并把结果格式化为可直接给模型消费的片段列表。
- vector-based retrieval 编排：
  - [`research/ReMe/reme/memory/vector_based/reme_retriever.py`](../research/ReMe/reme/memory/vector_based/reme_retriever.py)
    - 统一调度多个 memory agent，把 query 驱动的检索结果、工具调用和命中节点聚合回来。

## 核心机制

### 1. `ReMeLight` 把文件记忆做成了一条可直接落地的工作流

[`reme_light.py`](../research/ReMe/reme/reme_light.py) 里最关键的不是单个函数，而是整个目录模型：

- `MEMORY.md`
- `memory/YYYY-MM-DD.md`
- `tool_result/<uuid>.txt`

这条路线非常适合想做“透明记忆”的 runtime，因为它的状态默认就是：

- 可读
- 可编辑
- 可复制迁移

而不是一开始就藏进数据库。

### 2. pre-reasoning hook 是一条完整的前处理链

从 README 和 `ReMeLight` 的接口可以看出，它在一次推理前会把这几步串起来：

1. `compact_tool_result`
2. `check_context`
3. `compact_memory`
4. `summary_memory`

这说明它并不是“有几个工具，自己挑着用”，而是在尝试把 memory 管理变成 agent reasoning loop 的固定环节。

### 3. tool result compact 走的是“落文件 + 截断 + 引用”

[`tool_result_compactor.py`](../research/ReMe/reme/memory/file_based/components/tool_result_compactor.py) 做得很直接：

- 超过阈值的内容写进 `tool_result/<uuid>.txt`
- 文件头带上 `tool_name` 和 `created_at`
- 原消息里只保留截断结果和文件引用
- 过期文件按 retention 清理

这和 `ctx-zip` 有相似之处，但 `ReMe` 的不同点是：

- 它把 tool result compact 明确放进了 memory pipeline
- 而不是只做一个独立小库

### 4. file-based memory search 是 hybrid search

[`memory_search.py`](../research/ReMe/reme/memory/file_based/tools/memory_search.py) 不是简单 grep。

它会基于 `file_store.hybrid_search()` 去查：

- `MEMORY.md`
- `memory/*.md`
- 其他配置好的 memory source

还支持：

- `min_score`
- `max_results`
- `vector_weight`
- `candidate_multiplier`

这说明它在 file memory 路线上并没有放弃 semantic retrieval。

### 5. vector-based 路线也没有被砍掉

[`reme_retriever.py`](../research/ReMe/reme/memory/vector_based/reme_retriever.py) 展示的是另一条更 agentic 的路线：

- 由 `ReMeRetriever` 统一编排多个 memory agent
- 在 query / messages 基础上构建检索上下文
- 聚合工具结果和 retrieved nodes

再结合 `procedural_memory/` 目录可以看出，它还在尝试做：

- personal memory
- procedural memory
- tool call memory

所以 `ReMe` 不是一个单一 memory backend，而是两条路线并行：

- file-based
- vector-based

## 它最强的地方

### 强项 1：文件记忆路线非常透明

对于自有 runtime 来说，这比一开始就把所有状态塞进黑盒数据库更容易落地和调试。

### 强项 2：tool result compact 被纳入了 memory pipeline

这让它在“有限上下文 + 可回看文件”这件事上比纯 memory 项目更贴 runtime。

### 强项 3：file memory 和 semantic retrieval 没有割裂

它不是只能看文件，也不是只能查向量库，而是两边都留了路。

## 它不解决什么

### 1. 不是统一 handle-first 的原始输出层

它有文件引用，但没有统一的 `read/slice/search(handle)` 抽象。

### 2. 不是最轻的集成形态

相比 `ctx-zip` 这种小库，它更像一个完整 memory toolkit。

### 3. 工作状态恢复没有 `context-mode` 那么明确

它更偏 memory 管理，不是 resume snapshot 系统。

## 对自有 agent runtime 最值得借鉴的部分

### 最值得直接借鉴

1. `MEMORY.md + memory/ + tool_result/` 这种目录模型
2. 推理前固定跑的 compact / summarize pipeline
3. hybrid memory search

### 最值得模仿

1. 把可读文件记忆作为第一层落地形式
2. 把 tool result compact 放进 memory 流程，而不是单独补丁

### 不建议误判

1. 不要把它当成 shell 前门压缩器
2. 不要把它当成完整 session continuity runtime

## 结论

`ReMe` 最适合被当成：

> **一套把文件记忆、tool result compact、hybrid retrieval 和 agent memory pipeline 接起来的 memory toolkit。**

如果你想做的是“透明、可查、能落文件的 agent memory”，它比纯向量记忆项目更贴近实际工程。
