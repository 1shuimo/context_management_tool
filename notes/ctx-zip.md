# `ctx-zip` 详细调研

## 基本信息

- 本地目录：`research/ctx-zip`
- 远程仓库：`karthikscale3/ctx-zip`
- 当前本地 `HEAD`：`76580f7ba1555c891928702743ac74412c7fac60`
- 当前本地版本：`1.0.6`
- 语言：TypeScript
- 定位：轻量级 context 管理库，主打把大 tool results 落到文件/沙箱，再用读取工具按需取回

## 为什么它和 agent runtime 优化相关

`ctx-zip` 不是一个完整 runtime，也不是一个 memory 平台。

它解决的是一个非常具体但非常常见的问题：

> **工具结果太大时，别直接塞进对话；先落存储，再给模型一个轻引用。**

这类设计的价值在于：

- 集成面很小
- 不要求你换整套 agent 框架
- 能快速给现有 runtime 增加“progressive discovery”能力

## 关键源码入口

- 包入口：
  - [`research/ctx-zip/src/index.ts`](../research/ctx-zip/src/index.ts)
- 对话压缩入口：
  - [`research/ctx-zip/src/tool-results-compactor/compact.ts`](../research/ctx-zip/src/tool-results-compactor/compact.ts)
- write-to-file 策略与 boundary 逻辑：
  - [`research/ctx-zip/src/tool-results-compactor/strategies/index.ts`](../research/ctx-zip/src/tool-results-compactor/strategies/index.ts)
- sandbox manager：
  - [`research/ctx-zip/src/sandbox-code-generator/sandbox-manager.ts`](../research/ctx-zip/src/sandbox-code-generator/sandbox-manager.ts)
- 示例：
  - [`research/ctx-zip/examples/ctx-management/email_management.ts`](../research/ctx-zip/examples/ctx-management/email_management.ts)

## 核心机制

### 1. API 非常薄：`compact(messages, options)`

[`compact.ts`](../research/ctx-zip/src/tool-results-compactor/compact.ts) 暴露的主入口就一个：

- `compact(messages, options)`

它支持的核心策略目前主要是两种：

- `write-tool-results-to-file`
- `drop-tool-results`

这说明它的设计目标非常明确：

- 做一个可嵌入的小型 context 管理层
- 不抢你的 agent 主循环

### 2. compaction window 是显式可控的

[`strategies/index.ts`](../research/ctx-zip/src/tool-results-compactor/strategies/index.ts) 定义了 `Boundary`：

- `"all"`
- `{ type: "keep-first", count: N }`
- `{ type: "keep-last", count: N }`

这很实用，因为真实对话里你通常不想无脑压整段：

- 有时要保留最前面的系统设定
- 有时要保留最近几轮上下文

而且它默认不会去压最后一条 assistant message，这避免了很多正在生成中的上下文被误处理。

### 3. write-to-file 策略本质是“把 payload 变成引用”

`writeToolResultsToFileStrategy()` 会把 tool results：

- 写入由 `FileAdapter` 管理的存储
- 按 `sessionId/tool-results/...` 组织
- 再把原消息里的大块内容换成轻量引用

它还会区分：

- 真正应该落盘的 tool result
- 本来就是“读存储”的 tool result

后者不会被反复重写，这点很关键，因为否则会形成“读取结果再落盘、再读取”的循环污染。

### 4. 它把“按需回看”交给 sandbox 工具

从 `compact.ts` 和示例可以看到，它默认配合这些 reader 工具：

- `sandbox_ls`
- `sandbox_cat`
- `sandbox_grep`
- `sandbox_find`

这背后的哲学不是全文索引，而是：

> **先把大结果踢出 prompt，再让模型通过文件工具按需查。**

这就是典型的 progressive discovery：

- 首轮只看轻引用
- 需要细节时再读文件

### 5. storage / sandbox backend 是可替换的

项目支持：

- local
- E2B
- Vercel

对应 `FileAdapter` 和 `SandboxManager` 的抽象。

这点的现实意义是：

- 你的 runtime 不一定要绑定本地磁盘
- 可以把“上下文外置”做在本地，也可以做在远端沙箱

## 它最强的地方

### 强项 1：集成面小

相比 `Context-Gateway`、`headroom` 这种更重的系统，`ctx-zip` 更像一个好嵌入的小库。

### 强项 2：文件化引用很直白

没有太多复杂协议，就是：

- 写出去
- 给引用
- 需要时读回来

### 强项 3：很适合做现有 runtime 的第一步实验

如果你还不确定要不要上完整 proxy / retrieval / memory 系统，它是低成本试验入口。

## 它不解决什么

### 1. 没有真正的全文索引层

它更偏文件回看，而不是：

- BM25
- FTS5
- query-to-chunk retrieval

### 2. 没有 session continuity

它不负责：

- active files
- task state
- compact/resume snapshot

### 3. 不会替你管理长期 memory

它解决的是 tool result 膨胀，不是长期记忆。

## 对自有 agent runtime 最值得借鉴的部分

### 最值得直接借鉴

1. `compact(messages, options)` 这种超薄接入面
2. file-backed tool result compaction
3. boundary 控制

### 最值得模仿

1. 先落盘，再按需 `cat/grep/find`
2. 让“工具读取工具结果”这件事显式化

### 不建议误判

1. 不要把它当成完整 retrieval system
2. 不要把它当成完整 runtime

## 结论

`ctx-zip` 最适合被当成：

> **一个很小、很实用的“先把大工具结果移出 prompt，再靠文件工具按需读回”的库。**

如果你想先在自有 runtime 里快速试“工具结果文件化外置”这条路线，它是这批仓库里最轻的切入点之一。
