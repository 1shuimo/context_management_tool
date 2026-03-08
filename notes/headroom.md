# `headroom` 详细调研

## 基本信息

- 本地目录：`research/headroom`
- 远程仓库：[`chopratejas/headroom`](https://github.com/chopratejas/headroom)
- 当前本地 `HEAD`：`3945c02aa5a1dcbb25bc5b3b39d3684ef38d0d49`
- 当前本地版本：`0.3.7`
- 语言：Python
- 定位：通用 context optimization layer，既能做 `compress(messages)`，也能做 proxy / MCP / memory / evals / CCR

## 为什么它和 agent runtime 优化直接相关

`headroom` 是这批仓库里最“野心大”的一个。

它不只想做：

- 单一压缩器
- 单一 memory 层
- 单一代理框架

它的方向更像：

> **把上下文优化变成一个可嵌入 SDK、可做 proxy、可做可逆 retrieval、还能带 memory 的通用中间层。**

如果你自己的 runtime 比较复杂，或者你不想只盯着 coding agent 场景，它值得认真看。

## 关键源码入口

- 一函数压缩入口：
  - [`research/headroom/headroom/compress.py`](https://github.com/chopratejas/headroom/blob/3945c02aa5a1dcbb25bc5b3b39d3684ef38d0d49/headroom/compress.py)
    - 提供最小 API `compress(messages)`，并负责初始化单例 pipeline、调用 hooks、回传 token 节省指标。
- transform pipeline：
  - [`research/headroom/headroom/transforms/pipeline.py`](https://github.com/chopratejas/headroom/blob/3945c02aa5a1dcbb25bc5b3b39d3684ef38d0d49/headroom/transforms/pipeline.py)
    - 决定 transform 执行顺序，串起 `CacheAligner`、`ContentRouter`、`IntelligentContext` 等步骤。
- CCR response handler：
  - [`research/headroom/headroom/ccr/response_handler.py`](https://github.com/chopratejas/headroom/blob/3945c02aa5a1dcbb25bc5b3b39d3684ef38d0d49/headroom/ccr/response_handler.py)
    - 检测模型返回的 `headroom_retrieve` 工具调用，执行检索并自动续跑后续轮次直到拿到最终响应。
- hierarchical memory：
  - [`research/headroom/headroom/memory/core.py`](https://github.com/chopratejas/headroom/blob/3945c02aa5a1dcbb25bc5b3b39d3684ef38d0d49/headroom/memory/core.py)
    - `HierarchicalMemory` 的核心编排层，统一管理存储、向量索引、文本索引、缓存和 bubbling 策略。
- direct mem0 adapter：
  - [`research/headroom/headroom/memory/backends/direct_mem0.py`](https://github.com/chopratejas/headroom/blob/3945c02aa5a1dcbb25bc5b3b39d3684ef38d0d49/headroom/memory/backends/direct_mem0.py)
    - 在 facts/entities 已预抽取时跳过 Mem0 内部多轮 LLM 维护，直接写向量库和图存储。
- markdown <-> memory bridge：
  - [`research/headroom/headroom/memory/bridge.py`](https://github.com/chopratejas/headroom/blob/3945c02aa5a1dcbb25bc5b3b39d3684ef38d0d49/headroom/memory/bridge.py)
    - 提供 markdown 文件与 Headroom memory 之间的导入、导出和双向同步能力。

## 核心机制

### 1. 最小接入面非常清楚：`compress(messages)`

[`compress.py`](../research/headroom/headroom/compress.py) 把最简单的使用方式压缩成了一个函数：

- 输入 `messages`
- 输出压缩后的 `messages`
- 同时给出 tokens before/after、saving ratio、transforms_applied

这点的价值很直接：

- 你不必先上 proxy
- 你不必先接完整 memory
- 你可以先把它当成一个纯 SDK 试起来

### 2. transform pipeline 是 content-aware 的，不是单一摘要器

[`pipeline.py`](../research/headroom/headroom/transforms/pipeline.py) 默认顺序很明确：

1. `CacheAligner`
2. `ContentRouter`
3. `IntelligentContextManager` 或 `RollingWindow`

其中 `ContentRouter` 不是一个 compressor，而是一个路由器，会按内容类型选不同的压缩方式。

这和很多“把所有输入都丢给一个 summarizer”方案不一样。

它更像是在说：

- JSON 用 `SmartCrusher`
- 代码用 `CodeCompressor`
- 文本用 `LLMLingua` 或文本压缩器
- 其余内容按类型走不同 transform

这对自有 runtime 的启发很大，因为真实上下文污染源本来就不是同一种数据。

### 3. CCR 是这批仓库里最接近“可逆 handle”味道的实现之一

[`response_handler.py`](../research/headroom/headroom/ccr/response_handler.py) 处理的是：

- 模型输出里出现 `headroom_retrieve`
- 系统自动拦截这个工具调用
- 从 compression store 里把原文或 query 搜索结果取回
- 再继续对话

也就是说，它不是只做：

- 压缩完就算了

而是在尝试做：

> **压缩后仍可按 hash/query 取回原始内容。**

这离“统一 handle 层”还差一点，但已经比单纯截断或文件回看更进一步。

### 4. 它自带 memory，而且不是浅层包装

[`memory/core.py`](../research/headroom/headroom/memory/core.py) 的 `HierarchicalMemory` 会统一管理：

- store
- vector index
- text index
- embedder
- cache

并支持：

- user / session / agent / turn 这些 scope
- auto embedding
- text/vector index 同步更新
- memory bubbling

所以它不是“压缩器 + 顺便带点记忆”，而是真的想把 memory 也纳入统一中间层。

### 5. 它甚至考虑了和 `mem0`、markdown memory 的连接

[`direct_mem0.py`](../research/headroom/headroom/memory/backends/direct_mem0.py) 的思路很有意思：

- 如果主 LLM 已经提取了 facts/entities/relationships
- 就直接写向量库 / 图库
- 跳过 Mem0 内部那几轮额外 LLM 抽取

[`bridge.py`](../research/headroom/headroom/memory/bridge.py) 又提供了：

- markdown memory 文件导入
- Headroom memory 导出回 markdown
- 双向 sync

这说明它在想的不是“压缩完就没了”，而是：

- 压缩
- 可逆 retrieval
- 记忆桥接

这三层怎么一起工作。

## 它最强的地方

### 强项 1：通用性很强

它不是只面向某一种 CLI 或某一种 agent 壳。

### 强项 2：content-aware pipeline 设计很成熟

不是一刀切摘要，而是按内容形态做不同策略。

### 强项 3：CCR 让“压完还能找回去”这件事更像系统能力

这是它和普通压缩库差别最大的地方之一。

### 强项 4：memory 不是外挂，是体系内能力

这点也比很多“单独接个向量库”的方案更完整。

## 它不解决什么

### 1. 它不是 coding-agent 特化的 session continuity 系统

它的 memory 很强，但不等于它有 `context-mode` 那种面向工作状态恢复的 snapshot builder。

### 2. 系统面比较大，接入成本不低

你可以只用 `compress()`，但如果想吃到 proxy + CCR + memory 全套，复杂度明显高于 `rtk`、`ctx-zip`。

### 3. 它更像“通用中间层”，不是固定产品形态

这意味着它很灵活，也意味着你需要自己定义边界。

## 对自有 agent runtime 最值得借鉴的部分

### 最值得直接借鉴

1. `compress(messages)` 这种超低门槛接入面
2. content-aware transform pipeline
3. CCR retrieval loop

### 最值得模仿

1. 把不同内容类型路由到不同压缩器
2. 压缩和 retrieval 一起设计，而不是只设计压缩
3. memory 和 markdown/file memory 之间做 bridge

### 不建议直接照搬

1. 在需求还不清楚时一次性搬整套系统
2. 把它误当成完整 coding-agent runtime

## 结论

`headroom` 最适合被当成：

> **一个覆盖 SDK、proxy、可逆压缩、memory bridge 的通用上下文优化中间层。**

如果你想看的不是“某个具体 CLI 怎么省 token”，而是“上下文优化层本身应该长什么样”，它是这批仓库里非常值得深入拆的一个。
