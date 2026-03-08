# `letta` 详细调研

## 基本信息

- 本地目录：`research/letta`
- 远程仓库：`letta-ai/letta`
- 当前本地版本：`0.16.6`
- 前身：MemGPT
- 定位：stateful agent platform，重点是 memory blocks、archival memory、conversation search、持续状态

## 为什么它和 agent runtime 优化相关

`Letta` 不是工具输出压缩项目。

它真正强的是：

- 把“agent 记忆”分层
- 把可搜索的历史和长期知识显式做成工具
- 在 context window 压力下重建上下文窗口

如果你优化的是自己的 agent runtime，那么 `Letta` 最有价值的不是压缩算法，而是：

- **memory tiering**
- **memory tools**
- **system prompt 基于 memory state 重建**

## 关键源码入口

- agent 主循环：
  - [`research/letta/letta/agents/letta_agent.py`](../research/letta/letta/agents/letta_agent.py)
- base memory rebuild：
  - [`research/letta/letta/agents/base_agent.py`](../research/letta/letta/agents/base_agent.py)
- memory schema：
  - [`research/letta/letta/schemas/memory.py`](../research/letta/letta/schemas/memory.py)
- agent schema：
  - [`research/letta/letta/schemas/agent.py`](../research/letta/letta/schemas/agent.py)
- base memory tool definitions：
  - [`research/letta/letta/functions/function_sets/base.py`](../research/letta/letta/functions/function_sets/base.py)
- tool executor：
  - [`research/letta/letta/services/tool_executor/core_tool_executor.py`](../research/letta/letta/services/tool_executor/core_tool_executor.py)

## 核心机制

### 1. 记忆是分层的，不是单一聊天历史

从 [`schemas/memory.py`](../research/letta/letta/schemas/memory.py) 能看到它在上下文里区分：

- core memory
- summary memory
- recall memory
- archival memory
- external memory summary

这意味着 `Letta` 对 runtime 的假设不是：

- “把所有历史都塞 prompt”

而是：

- 哪些记忆必须常驻
- 哪些记忆可搜索
- 哪些记忆只保留摘要

### 2. memory 操作是显式工具

[`constants.py`](../research/letta/letta/constants.py) 和
[`functions/function_sets/base.py`](../research/letta/letta/functions/function_sets/base.py) 明确给了几类核心 memory tool：

- `conversation_search`
- `archival_memory_insert`
- `archival_memory_search`
- `core_memory_append`
- `core_memory_replace`

这很关键，因为它说明：

- memory 不是隐式后处理
- memory 本身就是 runtime 原语

### 3. system prompt 会随着 memory state 重建

[`BaseAgent._rebuild_memory_async()`](../research/letta/letta/agents/base_agent.py) 会：

1. 刷新 memory blocks
2. 计算新的 memory string
3. 判断 system prompt 是否变化
4. 必要时重建 system message

这和很多 agent runtime 最大的区别是：

- 不是“记忆存在数据库里”
- 而是“记忆变化会真实影响下一轮 prompt 结构”

### 4. context window 压力下会触发 summarizer

[`letta_agent.py`](../research/letta/letta/agents/letta_agent.py) 在 `_rebuild_context_window()` 中会根据 token 压力调用 summarizer。

它的目标不是工具输出压缩，而是：

- 控制对话消息窗口
- 维持长生命周期 agent 可持续运行

### 5. 某些搜索型 memory tool 不会被普通截断逻辑裁掉

在 `tool response` 处理里，`conversation_search`、`conversation_search_date`、`archival_memory_search` 被排除在常规 truncation 之外。

这很说明设计取向：

- 搜索结果在这个 runtime 里被视为高价值信息流

## 它最强的地方

### 强项 1：把 memory 做成 runtime 操作系统

这是 `Letta` 和很多“加个向量库”方案最大的不同。

### 强项 2：memory tool 语义清楚

它不是模糊的：

- “我会帮你记住”

而是明确分成：

- 改 core memory
- 查 recall/conversation
- 写 archival memory
- 查 archival memory

### 强项 3：system prompt 与 memory 联动

如果你自己的 runtime 也想做长期状态，这一点非常值得借鉴。

## 它不解决什么

### 1. 不是工具输出瘦身层

它没有把每次大工具输出变成稳定外部引用。

### 2. 不适合拿来做前置 CLI 压缩

它不是 `rtk` 那种工具链前门组件。

### 3. memory 强，不代表 prompt 压缩数据面也强

它在 memory 和 conversation state 上很强，但不等于它已经处理了“超大原始工具输出如何外置”的问题。

## 对自有 agent runtime 最值得借鉴的部分

### 最值得直接借鉴

1. memory tiering
2. memory tools 作为 runtime 原语
3. system prompt 基于 memory state 重建

### 最值得模仿

1. 区分：
   - core memory
   - searchable memory
   - summary memory
2. 不要把 memory 完全藏在系统背后，让 agent 显式调用 memory tool

### 不建议直接照搬

1. 把所有状态演化都耦合进完整平台
2. 用它替代工具输出虚拟化层

## 一个容易忽略但很重要的点

[`schemas/agent.py`](../research/letta/letta/schemas/agent.py) 里的 `message_buffer_autoclear` 写得很清楚：

- 即便不开历史消息缓冲
- agent 仍可通过 core / archival / recall memory 保持状态

这对 runtime 设计有启发：

- “消息历史”不应该和“记忆状态”是同一个概念

## 结论

`Letta` 最值得你 runtime 借鉴的是：

- **memory 的分层设计**
- **memory tool 的显式化**
- **memory state 反向塑造 prompt**

它不属于工具输出压缩路线，但在“长生命周期 agent 怎么继续保持状态”这件事上，本地仓库里它是非常强的参考对象。

