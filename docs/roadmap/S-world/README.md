# S 分支：场景与世界 — 总览

> 所属系列：AI Living Town 开发规划树
> 分支代码：S
> 目标：从单一客厅场景演进为多房间、多地点、参数化生成的完整世界

## 子文档索引

| 节点 | 文档 | 状态 | 简介 |
|------|------|------|------|
| S1 | [S1-art-ui-presentation.md](./S1-art-ui-presentation.md) | `[ACTIVE]` | 场景美术、UI 与视听表现 |
| S2 | [S2-multi-room-town.md](./S2-multi-room-town.md) | `[ACTIVE v0.8.9]` | WorldLocation 基线、多房间、街道、小镇与场景流送 |
| S3 | [S3-interactable-objects.md](./S3-interactable-objects.md) | `[ACTIVE]` | 可交互物体与状态变化 |
| S4 | [S4-parametric-generation.md](./S4-parametric-generation.md) | `[ACTIVE v0.8.9]` | 参数化建模与自动场景生成 |
| S5 | [S5-world-simulation.md](./S5-world-simulation.md) | `[LATER]` | 时间、天气、生态和世界模拟 |

## 分支概述

S 分支负责所有"视觉和空间"层面：从客厅家具的摆放和材质，到整个小镇的街道布局。场景不仅好看，还要支持 AI 角色的空间理解和交互。

**核心原则**：
- 所有物体必须同时具备：视觉表现 + 语义描述 + 可执行交互 + 碰撞体
- 场景加载采用流式，避免大世界一次性加载
- 参数化生成的结果可编辑，不是一次性不可复现的网格

> 最后更新：2026-07-28 | 基线程：v0.8.9
