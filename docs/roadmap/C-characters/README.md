# C 分支：AI 角色 — 总览

> 所属系列：AI Living Town 开发规划树
> 分支代码：C
> 目标：让 AI 角色具备真实的身体表现、独立的内心世界和自然的生活感

## 子文档索引

| 节点 | 文档 | 状态 | 简介 |
|------|------|------|------|
| C1 | [C1-text-to-action-routing.md](./C1-text-to-action-routing.md) | `[ACTIVE]` | 文本/意图到动作与表情的实时路由 |
| C2 | [C2-motion-library-retargeting.md](./C2-motion-library-retargeting.md) | `[ACTIVE]` | 动作库、HumanML3D/Light-T2M 与骨骼重定向 |
| C3 | [C3-expression-body-language.md](./C3-expression-body-language.md) | `[ACTIVE]` | 表情、口型、视线与细粒度身体语言 |
| C4 | [C4-character-scene-interaction.md](./C4-character-scene-interaction.md) | `[ACTIVE]` | 导航、碰撞、抓取、IK 与场景交互 |
| C5 | [C5-memory-personality-schedule.md](./C5-memory-personality-schedule.md) | `[ACTIVE]` | 独立记忆、人格、日程和多角色社交 |
| C6 | [C6-character-import.md](./C6-character-import.md) | `[LATER]` | 玩家导入角色与人设定制 |
| C7 | [C7-real-time-voice.md](./C7-real-time-voice.md) | `[ACTIVE]` | 实时语音、音色、口型同步与听觉感知 |
| C8 | [C8-character-art.md](./C8-character-art.md) | `[ACTIVE]` | 角色建模、材质、服装和 LOD 精细化 |
| C9 | [C9-life-authenticity.md](./C9-life-authenticity.md) | `[NEXT]` | 生活感、效用决策、微行为与共同活动 |

## 分支概述

C 分支是 AI Living Town 的"灵魂"，定义了每个 AI 角色的外在表现和内在世界。从动作路由的毫秒级延迟，到跨天级别的记忆和关系演化，C 分支覆盖了角色动作、感知、决策和社交的全部能力。

**核心原则**：
- LLM 负责高层意图、自然语言和复杂社交判断，不负责碰撞关键行为
- 确定性逻辑（导航、碰撞、物体占用）由本地 Runtime 执行
- 每个角色的记忆、人格和行为完全隔离

## 依赖关系

- C1（动作路由）→ C2（动作库）、C3（表情）、D2（导演表现）
- C6（角色导入）+ T3（插件接口）→ 对外开放角色包
- C5（多角色社交）+ S2（多地点）→ 小镇居民生活

> 最后更新：2026-07-24 | 基线程：v0.7
