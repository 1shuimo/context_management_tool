# `rtk` 详细调研

## 基本信息

- 本地目录：`research/rtk`
- 远程仓库：`rtk-ai/rtk`
- 当前本地版本：`0.27.2`
- 语言：Rust
- 定位：CLI output compression proxy，强调在命令输出进入 LLM 上下文之前先做过滤与压缩

## 为什么它和 agent runtime 优化相关

`rtk` 不解决长期 memory，也不解决 session continuity。

它解决的是更靠前的一层：

> 大量高噪声 shell / git / test / lint / gh 输出，根本就不该原样进入上下文。

如果你的 runtime 有 shell、测试器、构建器、代码搜索器这类工具，那么 `rtk` 的价值很直接：

- 在工具结果进入 prompt 之前先压一层
- 把“高频但低价值”的输出直接砍掉 60%-90%

## 关键源码入口

- 重写入口：
  - [`research/rtk/src/rewrite_cmd.rs`](../research/rtk/src/rewrite_cmd.rs)
- 重写规则：
  - [`research/rtk/src/discover/registry.rs`](../research/rtk/src/discover/registry.rs)
- 原始输出 tee：
  - [`research/rtk/src/tee.rs`](../research/rtk/src/tee.rs)
- token / 历史 tracking：
  - [`research/rtk/src/tracking.rs`](../research/rtk/src/tracking.rs)
- 架构文档：
  - [`research/rtk/ARCHITECTURE.md`](../research/rtk/ARCHITECTURE.md)

## 核心机制

### 1. 命令重写层

[`rewrite_cmd.rs`](../research/rtk/src/rewrite_cmd.rs) 本身很薄，核心逻辑都委托给
[`discover/registry.rs`](../research/rtk/src/discover/registry.rs)。

它支持的重写模式不是简单字符串替换，而是有明确语义约束：

- 普通单命令重写
- `&&` / `||` / `;` compound command
- pipe 只重写第一段
- heredoc 场景跳过
- 已经是 `rtk ...` 的命令不重复改写
- 特定命令可通过配置排除

对 runtime 的意义是：

- 这是一套“进入 shell 前的规范化层”
- 很适合变成你自己的 tool adapter registry

### 2. 命令族特化压缩

`rtk` 不做“一种通用压缩器”，而是按命令族分模块：

- `git`
- `gh`
- `pytest`
- `cargo`
- `tsc`
- `ruff`
- `golangci-lint`
- `playwright`
- `logs`

这种设计的价值非常高，因为很多输出如果不理解领域结构，就压不准：

- `git status` 适合目录聚合
- `pytest` 适合只保留 failure
- `lint` 适合按文件 / rule 分组
- `logs` 适合按模式 dedupe

如果你的 runtime 有固定工具集，这种“命令族 parser”是比通用摘要更有性价比的路线。

### 3. 原始输出 fallback：`tee`

[`tee.rs`](../research/rtk/src/tee.rs) 是这个仓库非常关键但经常被忽略的一层。

默认行为：

- 输出小于 `500` bytes 不 tee
- 默认只 tee `failure`
- 默认最多保留 `20` 个文件
- 单文件默认上限 `1MB`
- 返回给模型的是提示行：
  - `[full output: ~/.../xxx.log]`

它的意义不是“检索”，而是：

- 让压缩器更敢压
- 因为失败场景至少还有完整输出的回看口

### 4. Tracking 层

[`tracking.rs`](../research/rtk/src/tracking.rs) 用 SQLite 记录：

- 原始 tokens
- 压缩后 tokens
- 节省比例
- 执行时间
- 命令历史
- 项目路径维度

这里有一个实现细节要注意：

- 注释里有 `tracking.db`
- 但 `get_db_path()` 实际返回的是 `history.db`

即：

- 真正路径是 `~/.local/share/rtk/history.db`

这不影响功能，但说明它的文字文档和实现有过一次命名漂移。

## 它最强的地方

### 强项 1：插入点非常靠前

在 runtime 架构里，越靠前压缩，收益越稳。

`rtk` 最强的地方不是 parser 本身，而是：

- **它把压缩放在命令执行入口**

这和很多“生成后再摘要”的方案相比，更贴近真实工具链。

### 强项 2：面向真实开发命令集优化

这个仓库不是泛 agent 研究原型，而是非常明确地面向：

- coding agent
- shell-heavy agent
- test/build-heavy workflow

所以它对工程型 runtime 的参考价值很高。

### 强项 3：fallback 很务实

很多压缩系统最大的问题是“压过头以后看不回去”。

`tee` 虽然不是完整 retrieval system，但至少给了：

- 可恢复
- 可审计
- 可人工回看

## 它不解决什么

### 1. 没有稳定 handle 抽象

它没有把工具输出抽象成：

- `rtk://...`
- content hash
- explicit handle

这种稳定引用。

### 2. 没有全文索引层

tee 文件只是文件，不是检索层。

它没有：

- `search(handle, query)`
- BM25
- chunk 索引
- prompt 内引用恢复

### 3. 没有 runtime state continuity

它追踪的是：

- metrics
- history

不是：

- active files
- tasks
- decisions
- compact / resume state

## 对自有 agent runtime 最值得借鉴的部分

### 最值得直接借鉴

1. rewrite registry
2. command-family specific compressor
3. tee fallback

### 最值得在你的 runtime 里重写成通用组件

1. “tool type -> compressor” 映射表
2. 进入 prompt 前的结果裁剪层
3. 失败场景原始输出保留策略

### 最需要自己补的部分

1. retrieval / index layer
2. stable handle layer
3. session continuity layer

## 适合放在你 runtime 的哪一层

最适合的插入点是：

- tool executor 后
- prompt assembler 前

具体就是：

1. tool 真正执行，得到 raw output
2. 先过 `rtk` 风格压缩器
3. 再决定：
   - 直接返回压缩结果
   - 或者外置保存并只回传引用

## 结论

`rtk` 不是一个完整 runtime memory 系统，但它是这批本地仓库里最值得借鉴的“工具输出前置压缩层”。

如果你的 agent runtime 里有大量 shell / git / build / test 工具，它几乎一定值得作为前门压缩层参考。

