# Notes Index

这份索引把当前仓库里的文档分成两类：

- **当前有效笔记**：对应 `research/` 里这一轮重新核对过的 9 个真实仓库
- **历史残留笔记**：旧草稿或过期说明，不再纳入当前主比较矩阵

## 当前有效笔记

| 项目 | 说明 | 笔记 |
|---|---|---|
| `context-mode` | 本地检索式上下文虚拟化 + session continuity | [`context-mode.md`](context-mode.md) |
| `Context-Gateway` | API gateway + preemptive compaction + tool discovery filtering | [`context-gateway.md`](context-gateway.md) |
| `headroom` | 通用压缩中间层 + 可逆 CCR + memory bridge | [`headroom.md`](headroom.md) |
| `rtk` | shell / CLI 输出前门压缩 | [`rtk.md`](rtk.md) |
| `ctx-zip` | 轻量文件落盘式 tool result compaction 库 | [`ctx-zip.md`](ctx-zip.md) |
| `ReMe` | 文件记忆 + 向量记忆 + tool result compact | [`reme.md`](reme.md) |
| `deepagents` | orchestration / subagent / compact runtime | [`deepagents.md`](deepagents.md) |
| `letta` | stateful memory runtime | [`letta.md`](letta.md) |
| `mem0` | 外部长期记忆服务层 | [`mem0.md`](mem0.md) |


## 使用说明

这些笔记里的源码路径默认按本地工作区组织，通常会引用 `research/<repo>/...`。

如果你本地还没有这些上游仓库，先运行：

```bash
bash scripts/bootstrap_research.sh
```

这样就能把引用到的本地路径补齐。
