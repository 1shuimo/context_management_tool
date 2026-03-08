# `deepagents` 详细调研

## 基本信息

- 本地目录：`research/deepagents`
- 远程仓库：[`langchain-ai/deepagents`](https://github.com/langchain-ai/deepagents)
- 核心包：`deepagents`
- CLI 包：`deepagents-cli`
- 定位：带 planning、filesystem、shell、subagents、summarization 的 agent harness

## 为什么它和 agent runtime 优化相关

`deepagents` 的重点不是“工具输出句柄化”，而是：

- agent orchestration
- subagent 隔离上下文
- 长会话自动 / 手动 compact
- checkpoint / resume

如果你的 runtime 已经存在，`deepagents` 最值得看的不是整套框架，而是这些模式：

- **什么时候 compact**
- **compact 后如何继续干活**
- **什么时候把问题切给子代理，隔离上下文污染**

## 关键源码入口

- 核心 agent 组装：
  - [`research/deepagents/libs/deepagents/deepagents/graph.py`](https://github.com/langchain-ai/deepagents/blob/eb0b26c9578c8ed9f20aea3b2d8b852af1a4a6ac/libs/deepagents/deepagents/graph.py)
    - `create_deep_agent()` 的核心实现，决定默认 middleware 栈、状态图和长任务运行原语。
- summarization 中间件：
  - [`research/deepagents/libs/deepagents/deepagents/middleware/summarization.py`](https://github.com/langchain-ai/deepagents/blob/eb0b26c9578c8ed9f20aea3b2d8b852af1a4a6ac/libs/deepagents/deepagents/middleware/summarization.py)
    - 负责自动和手动 compact，把旧消息写到 `conversation_history` 文件，再把 summary 注回上下文。
- subagent 中间件：
  - [`research/deepagents/libs/deepagents/deepagents/middleware/subagents.py`](https://github.com/langchain-ai/deepagents/blob/eb0b26c9578c8ed9f20aea3b2d8b852af1a4a6ac/libs/deepagents/deepagents/middleware/subagents.py)
    - 定义 `task` 工具，把子任务放进隔离状态里执行，并把结果压成单条返回给主代理。
- CLI agent 组装：
  - [`research/deepagents/libs/cli/deepagents_cli/agent.py`](https://github.com/langchain-ai/deepagents/blob/eb0b26c9578c8ed9f20aea3b2d8b852af1a4a6ac/libs/cli/deepagents_cli/agent.py)
    - 把 SDK 级 agent、thread resume、checkpointer 和 CLI 交互壳拼到一起。
- CLI 本地上下文刷新：
  - [`research/deepagents/libs/cli/deepagents_cli/local_context.py`](https://github.com/langchain-ai/deepagents/blob/eb0b26c9578c8ed9f20aea3b2d8b852af1a4a6ac/libs/cli/deepagents_cli/local_context.py)
    - 在 compact 或恢复后刷新本地工作集，让 CLI 层重新知道当前文件、状态和上下文摘要。

## 核心机制

### 1. 默认中间件栈本身就体现了它的运行哲学

在 [`graph.py`](../research/deepagents/libs/deepagents/deepagents/graph.py) 里，`create_deep_agent()` 默认中间件栈包括：

- `TodoListMiddleware`
- `FilesystemMiddleware`
- `create_summarization_middleware(...)`
- `SubAgentMiddleware`
- `AnthropicPromptCachingMiddleware`
- `PatchToolCallsMiddleware`

这说明它默认假设的是一个“长期工作型 agent”：

- 有任务列表
- 要读写文件
- 会话会膨胀
- 需要子代理隔离上下文

### 2. summarization 是一等公民

[`summarization.py`](../research/deepagents/libs/deepagents/deepagents/middleware/summarization.py) 做了两件事：

1. **自动 compact**
- 达到触发阈值时自动 summarization

2. **手动 compact**
- 暴露 `compact_conversation` 工具

它的存储策略是：

- 被挤出上下文的旧消息先落到 `/conversation_history/{thread_id}.md`
- 然后生成 summary message
- summary message 会把这个文件路径一起放进上下文

这是很典型的“摘要 + 文件路径回看”路线。

### 3. subagent 是真正的隔离上下文窗口

[`subagents.py`](../research/deepagents/libs/deepagents/deepagents/middleware/subagents.py) 的 `task` 工具不是装饰性的。

它会：

- 构造子代理 runnable
- 过滤部分父状态
- 把子任务放进独立上下文
- 最终只返回单条结果给主代理

这对 runtime 优化非常重要，因为：

- 很多上下文污染不是来自工具，而是来自任务拆分不干净

`deepagents` 给出的答案是：

- 用子代理来隔离任务局部工作集

### 4. CLI 层补了 checkpoint / resume / local context

CLI 部分还有几个和 runtime 很相关的点：

- thread resume
- checkpointer
- summarization event 之后刷新 local context

这意味着它不只是“有个 summarizer”，而是把 summarization 事件真的接到了运行时状态更新逻辑里。

## 它最强的地方

### 强项 1：长任务 orchestration 很完整

相比只做 memory 或只做 compression 的项目，`deepagents` 更像一个真正跑长任务的 runtime。

### 强项 2：subagent 边界很清楚

这是它最值得你 runtime 借鉴的点之一：

- **不是一味往主线程上下文里加东西**
- **而是尽可能把任务分配给隔离窗口**

### 强项 3：compact 事件不是黑箱

很多框架只做 summarization，但不暴露清晰事件边界。

`deepagents` 则明确有：

- summarization middleware
- compact tool
- summarization event state

## 它不解决什么

### 1. 不是工具输出虚拟化系统

它没有为每个大工具输出建立：

- 稳定 handle
- 检索接口
- 句柄式恢复

### 2. conversation history 回看主要是文件路径

这比纯摘要强，但仍不是检索系统。

### 3. 它更偏“自带 runtime”，不是给你现有 runtime 拆模块的最小件

虽然内部模块可借鉴，但整体设计更偏自成体系。

## 对自有 agent runtime 最值得借鉴的部分

### 最值得直接借鉴

1. `compact_conversation` 作为显式工具
2. summarization event state
3. subagent 隔离上下文的边界设计

### 最值得模仿

1. orchestration 中默认存在 todo / filesystem / subagent / compact 这几类原语
2. compact 不只是摘要文本，而是一个 runtime 事件

### 不建议直接照搬的部分

1. conversation history 仅用文件路径回看
2. 过于依赖框架内建 middleware 组合

## 结论

`deepagents` 最适合被当成：

> 长任务 agent runtime 的 orchestration 参考

如果你自己的 runtime 已经存在，它最值得你拿走的是：

- **subagent 隔离上下文**
- **显式 compact 工具**
- **summarization 事件接运行时状态**

而不是“工具输出外置”那一层。
