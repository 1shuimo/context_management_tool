# `mem0` 详细调研

## 基本信息

- 本地目录：`research/mem0`
- 远程仓库：[`mem0ai/mem0`](https://github.com/mem0ai/mem0)
- 当前本地版本：`1.0.5`
- 定位：memory layer / memory SDK，面向用户、agent、run 维度的长期记忆管理

## 为什么它和 agent runtime 优化相关

`mem0` 的重点不是会话 compaction，而是：

- 从消息里抽取长期可复用事实
- 在外部存储里做增量维护
- 查询时再按语义和 metadata 拉回

所以它和你自己的 agent runtime 的关系不是：

- 替你处理 prompt 瘦身

而是：

- 给你的 runtime 提供一层“外部长期记忆服务”

## 关键源码入口

- memory 主入口：
  - [`research/mem0/mem0/memory/main.py`](https://github.com/mem0ai/mem0/blob/34c797d2850c33b45ec28d6f8748bda05473b637/mem0/memory/main.py)
    - `Memory.add/search/get/delete` 的主编排层，负责作用域过滤、事实抽取、维护决策和存储更新。
- config：
  - [`research/mem0/mem0/configs/base.py`](https://github.com/mem0ai/mem0/blob/34c797d2850c33b45ec28d6f8748bda05473b637/mem0/configs/base.py)
    - 定义 LLM、embedder、vector store、graph store 等核心组件的配置结构和默认项。
- client API：
  - [`research/mem0/mem0/client/main.py`](https://github.com/mem0ai/mem0/blob/34c797d2850c33b45ec28d6f8748bda05473b637/mem0/client/main.py)
    - 暴露更接近 SDK/服务化边界的调用方式，方便把 Mem0 当作独立 memory service 来接入。
- graph 相关：
  - [`research/mem0/mem0/graphs/`](https://github.com/mem0ai/mem0/tree/34c797d2850c33b45ec28d6f8748bda05473b637/mem0/graphs)
    - 放图存储与关系构建逻辑，展示 Mem0 如何把 memory 从向量召回扩展到图关系召回。
- vector store 工厂：
  - [`research/mem0/mem0/utils/factory.py`](https://github.com/mem0ai/mem0/blob/34c797d2850c33b45ec28d6f8748bda05473b637/mem0/utils/factory.py)
    - 负责按配置实例化不同 vector store、embedder、LLM 和相关后端，是可插拔能力的装配点。

## 核心机制

### 1. 每个 memory 操作都要求作用域

`main.py` 里的 `_build_filters_and_metadata()` 明确要求至少提供一个：

- `user_id`
- `agent_id`
- `run_id`

这点很关键，因为它让 memory 操作天然具备多租户 / 多会话边界。

如果你的 runtime 本身有：

- user
- agent
- thread / run

这些维度，`mem0` 这种建模方式非常容易接进去。

### 2. `add()` 不是直接写向量库，而是“抽取 -> 对比 -> 决策”

`Memory.add()` 的主流程大致是：

1. 规范化消息输入
2. 从消息中抽取 facts
3. 用 embedding 查旧记忆
4. 让 LLM 决定每条记忆该：
   - `ADD`
   - `UPDATE`
   - `DELETE`
   - `NONE`
5. 再更新向量库

这意味着它并不是简单 append-only memory，而是：

- **LLM 驱动的 memory maintenance loop**

### 3. graph 是可选并行层

如果 graph store 开启，`add()` 会并行做两件事：

- `_add_to_vector_store(...)`
- `_add_to_graph(...)`

所以 `mem0` 的结构不是单层向量存储，而是：

- 向量记忆
- 图关系记忆

并行存在。

### 4. `search()` 支持比较强的 metadata filters

`Memory.search()` 支持：

- 简单 filter
- 高级 operator
- 逻辑组合
- rerank

这说明它的目标场景不是“对话历史摘要”，而是：

- 真正当业务 memory service 使用

## 它最强的地方

### 强项 1：memory API 边界清楚

`add` / `search` / `get_all` / `delete` 这些接口都很清楚。

对自有 runtime 来说，这比一个耦合很深的 agent 框架更容易接入。

### 强项 2：session / actor / metadata 建模成熟

这对生产里的 agent runtime 很重要，因为真正上线后你一定会遇到：

- 不同 user
- 不同 agent
- 不同 run
- 不同 actor

`mem0` 在这一层的接口设计是成熟的。

### 强项 3：支持 graph + rerank

如果你的 runtime 未来要把 memory 从“向量召回”升级成“关系召回”，它已经留好了路径。

## 它不解决什么

### 1. 不是上下文压缩层

它不会主动处理：

- prompt 过长
- tool output 太大
- compact / resume

### 2. 不替你做 runtime state continuity

它更像一个外部记忆库，而不是 session runtime manager。

### 3. 不能替代工具输出虚拟化

它保存的是 memory item，不是某次具体 tool output 的完整原文句柄。

## 对自有 agent runtime 最值得借鉴的部分

### 最值得直接借鉴

1. `user_id / agent_id / run_id` 作用域建模
2. `ADD / UPDATE / DELETE / NONE` 的 memory maintenance loop
3. metadata filters 和 rerank 接口

### 最值得模仿

1. 把长期记忆做成外部服务，而不是塞进聊天上下文
2. memory 不只是 append，而要能更新和删除

### 不建议误用的地方

1. 不要把它当 prompt compaction 替代物
2. 不要把它当 shell/tool 输出压缩层

## 适合放在你 runtime 的哪一层

最适合放在：

- conversation turn 完成之后
- 或者 task 完成之后
- 作为长期记忆写入和检索层

不适合放在：

- tool execution 结果进入 prompt 的前门

## 结论

`mem0` 在这批本地仓库里最像：

> 可插拔的长期记忆服务层

如果你的目标是优化自己的 agent runtime，它最值得借鉴的是：

- **作用域化 memory API**
- **增量 memory maintenance**
- **vector + graph + rerank 的可扩展边界**

但它不负责会话压缩，也不负责工具输出外置。
