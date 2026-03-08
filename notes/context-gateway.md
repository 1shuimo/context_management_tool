# `Context-Gateway` 详细调研

## 基本信息

- 本地目录：`research/Context-Gateway`
- 远程仓库：[`Compresr-ai/Context-Gateway`](https://github.com/Compresr-ai/Context-Gateway)
- 当前本地 `HEAD`：`810171ef2b6348a915baa9bf76a2801f6249d92b`
- 语言：Go
- 模块名：`github.com/compresr/context-gateway`
- 定位：放在 agent 和 LLM API 之间的 gateway，主打 preemptive compaction、tool discovery filtering、tool output compression 和 dashboard/telemetry

## 为什么它和 agent runtime 优化直接相关

`Context-Gateway` 不是本地工具链里的一个 hook，也不是单纯的 memory 项目。

它更像是：

> **把上下文优化前移到 API 边界，在请求进模型之前做瘦身、在 compaction 真正发生之前先把 summary 算好。**

如果你的 runtime 自己控制：

- provider API 请求
- streaming response
- tool schema 注入

那它给出的很多设计都很值得拆看：

- 后台预压缩而不是前台等压缩
- 工具清单按相关性裁剪
- 工具输出压缩后保留 shadow 引用，并在需要时展开

## 关键源码入口

- 程序入口：
  - [`research/Context-Gateway/cmd/main.go`](https://github.com/Compresr-ai/Context-Gateway/blob/810171ef2b6348a915baa9bf76a2801f6249d92b/cmd/main.go)
    - 装配 gateway、provider adapter、dashboard 和配置加载，是整条代理链的启动入口。
- preemptive compaction 管理器：
  - [`research/Context-Gateway/internal/preemptive/manager.go`](https://github.com/Compresr-ai/Context-Gateway/blob/810171ef2b6348a915baa9bf76a2801f6249d92b/internal/preemptive/manager.go)
    - 管理“正常请求追踪 -> 后台 summary 预计算 -> compaction 请求命中缓存/等待/回退同步压缩”这条主流程。
- streaming 请求与 `expand_context`：
  - [`research/Context-Gateway/internal/gateway/handler_streaming.go`](https://github.com/Compresr-ai/Context-Gateway/blob/810171ef2b6348a915baa9bf76a2801f6249d92b/internal/gateway/handler_streaming.go)
    - 负责拦截流式响应、检测 `expand_context` 调用、重写历史并在需要时把请求二次发送给上游模型。
- tool output compression pipe：
  - [`research/Context-Gateway/internal/pipes/tool_output/tool_output.go`](https://github.com/Compresr-ai/Context-Gateway/blob/810171ef2b6348a915baa9bf76a2801f6249d92b/internal/pipes/tool_output/tool_output.go)
    - 提取工具输出、判断阈值、压缩、缓存原文与压缩结果，并给压缩内容打上 `SHADOW` 标记。
- tool discovery pipe：
  - [`research/Context-Gateway/internal/pipes/tool_discovery/tool_discovery.go`](https://github.com/Compresr-ai/Context-Gateway/blob/810171ef2b6348a915baa9bf76a2801f6249d92b/internal/pipes/tool_discovery/tool_discovery.go)
    - 对 tools schema 做相关性筛选，只保留当前最相关的工具，并把其余工具延期到 fallback 搜索流程。
- search fallback handler：
  - [`research/Context-Gateway/internal/gateway/search_tool_handler.go`](https://github.com/Compresr-ai/Context-Gateway/blob/810171ef2b6348a915baa9bf76a2801f6249d92b/internal/gateway/search_tool_handler.go)
    - 处理 `gateway_search_tools` 这类 phantom tool 调用，从 deferred tools 里搜索并回注真正需要的工具定义。
- deferred/expanded tool session：
  - [`research/Context-Gateway/internal/gateway/tool_session.go`](https://github.com/Compresr-ai/Context-Gateway/blob/810171ef2b6348a915baa9bf76a2801f6249d92b/internal/gateway/tool_session.go)
    - 为每个 session 维护 deferred tools 和 expanded tools 的状态，避免同一工具被反复过滤和反复搜索。

## 核心机制

### 1. 真正的插入点是“agent 和 provider 之间”

从 README 和 `internal/gateway/` 目录能看得很清楚，它不是把压缩做在：

- 某个单独 CLI 的 hook
- 某个工具返回之后的本地脚本

而是做成一个真正的 gateway：

- 收请求
- 改写请求
- 透传到上游 provider
- 拦截响应
- 必要时再二次发送

这意味着它更适合你自己的 runtime 在以下场景借鉴：

- 已经统一接管 OpenAI / Anthropic / Gemini / Bedrock 等 API
- 想把压缩逻辑放在 provider 无关的中间层

### 2. preemptive compaction 是它最值得看的点

[`manager.go`](../research/Context-Gateway/internal/preemptive/manager.go) 顶部注释已经把核心流程写得很直白：

1. 正常请求进入后追踪 token 使用
2. 达到阈值时触发后台 summarization
3. 真正碰到 compaction 请求时优先走：
   - 已有缓存 summary
   - 正在跑的 pending summary
   - 最后才同步压缩

也就是说，它想解决的不是“怎么压缩”，而是：

> **不要让用户在对话最卡的时候才开始等 compaction。**

这点和 `context-mode`、`deepagents` 的位置明显不同：

- `context-mode` 更偏本地检索 + resume snapshot
- `deepagents` 更偏 runtime 里的 summarization 事件
- `Context-Gateway` 更偏 API 前置的预计算

### 3. tool output compression 用了 shadow ID + selective expansion

[`tool_output.go`](../research/Context-Gateway/internal/pipes/tool_output/tool_output.go) 的实现重点不是简单摘要，而是：

- 抽取 tool outputs
- 跳过已经压过的内容
- 对满足阈值的输出做压缩
- 原文和压缩结果分不同 TTL 存储
- 给压缩后的内容加 `<<<SHADOW:...>>>` 标记

配合 [`handler_streaming.go`](../research/Context-Gateway/internal/gateway/handler_streaming.go)，它还支持：

- 先把 streaming response 缓住
- 检测模型是否请求 `expand_context`
- 只把被请求的那部分历史展开后重发

这比“整段压掉”和“整段恢复”都更实用，因为它更照顾：

- KV cache 前缀命中
- 对话历史干净度
- 精准扩展而不是全量回放

### 4. tool discovery filtering 不是简单删工具，而是“可搜索退场”

[`tool_discovery.go`](../research/Context-Gateway/internal/pipes/tool_discovery/tool_discovery.go) 会：

- 对工具做相关性打分
- 只保留 top N
- 把其余工具作为 deferred tools 存进 session
- 注入 `gateway_search_tools` 作为 fallback

随后 [`search_tool_handler.go`](../research/Context-Gateway/internal/gateway/search_tool_handler.go) 会在模型调用搜索工具时：

- 搜 deferred tools
- 把命中的工具 definition 返给模型
- 标记这些工具以后不要再过滤掉

[`tool_session.go`](../research/Context-Gateway/internal/gateway/tool_session.go) 还给 deferred / expanded tools 做了 TTL session store。

这套设计很重要，因为它解决的不是工具结果，而是另一个常见上下文浪费源：

> **工具清单本身太大。**

### 5. 它对“session”有追踪，但还不是完整 runtime state continuity

`manager.go` 里的 session matching 做得不差：

- 显式 `X-Session-ID`
- 首个 user message hash
- fuzzy match
- legacy fallback

但它的 session 主要还是围绕：

- preemptive summary
- tool session
- request detection

它不像 `context-mode` 那样明确抽 active files、decisions、rules、errors、git state 做 resume snapshot。

所以它很强，但强在 **gateway 层**，不是强在 **完整的工作状态恢复层**。

## 它最强的地方

### 强项 1：后台预压缩思路很务实

很多项目都在讨论 compaction，但它真正把“别等到爆了再压”做成了系统设计。

### 强项 2：工具清单和工具输出都考虑到了

很多项目只管一种污染源，它则同时处理：

- tools array 太大
- tool result 太大

### 强项 3：expand_context 设计比“整段回放”更细

shadow ID + selective replace 这条线，对真正的 API proxy 很有参考价值。

## 它不解决什么

### 1. 不是完整的本地检索式上下文外存

它有压缩、缓存、展开，但没有像 `context-mode` 那样把大量内容做成本地 FTS/BM25 检索平面。

### 2. 不是明确的 runtime state snapshot 系统

它跟踪 request/session，但不等于跟踪完整工作状态。

### 3. 更偏“你已经控制 API gateway”这一前提

如果你的 runtime 只是在本地工具链层做优化，它没有 `rtk` 那么轻，也没有 `ctx-zip` 那么小。

## 对自有 agent runtime 最值得借鉴的部分

### 最值得直接借鉴

1. preemptive compaction manager
2. tool discovery filtering + phantom search fallback
3. shadow ref + selective expand

### 最值得模仿

1. 把压缩逻辑前移到 API 边界
2. 不要只压 tool result，也要压 tools schema
3. 把 compaction 从同步阻塞动作改成后台预计算动作

### 不建议直接照搬

1. 把它误当成 session continuity 的完整替代品
2. 在没统一 provider API 的前提下强行搬整套 gateway

## 结论

`Context-Gateway` 最适合被当成：

> **agent runtime 的 API/gateway 侧上下文优化参考实现**

如果你控制的是 provider 边界，它比 `rtk` 更靠后、比 `context-mode` 更靠前，也比“压完再说”的同步 compaction 方案更务实。
