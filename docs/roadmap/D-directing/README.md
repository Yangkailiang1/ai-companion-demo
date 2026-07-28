# D 分支：剧情与导演 — 总览

> 所属系列：AI Living Town 开发规划树
> 分支代码：D
> 目标：提供剧本输入和演出编排能力，让开发者/玩家可以导演角色之间的故事

## 子文档索引

| 节点 | 文档 | 状态 | 简介 |
|------|------|------|------|
| D1 | [D1-script-format.md](./D1-script-format.md) | `[DONE MVP]` | JSON 小剧本格式、白名单校验与角色绑定 |
| D2 | [D2-director-system.md](./D2-director-system.md) | `[ACTIVE baseline]` | 双角色走位、动作、表情、对白和状态恢复 |
| D3 | [D3-ai-assisted-plot.md](./D3-ai-assisted-plot.md) | `[ACTIVE MVP]` | 自然语言转安全 Story JSON 与双模式入口 |
| D4 | [D4-creation-export.md](./D4-creation-export.md) | `[LATER]` | 回放、时间线编辑、录制与内容导出 |

## 分支概述

D 分支为 AI Living Town 增加了"叙事层"。开发者和玩家可以编写结构化剧本，让 AI 角色按剧本演出，同时 LLM 可以在安全受控的槽位内即兴创作。

**核心原则**：
- 剧本只生成白名单内的行为，不可达位置必须报告而非跳过
- 剧情结束后角色恢复自主日程和记忆
- AI 生成的剧情必须可预览、编辑和重放

## 依赖关系

```
D1 剧本格式 + C5 多 Agent + S2 多地点 ──> D2 完整剧情导演
```

> 最后更新：2026-07-27 | 当前切片：v0.8
