# P 分支：玩家 — 总览

> 所属系列：AI Living Town 开发规划树
> 分支代码：P
> 目标：为玩家提供第一人称和第三人称的活动体验，与 AI 角色自然互动

## 子文档索引

| 节点 | 文档 | 状态 | 简介 |
|------|------|------|------|
| P1 | [P1-player-avatar.md](./P1-player-avatar.md) | `[LATER]` | 玩家形象选择与模型导入 |
| P2 | [P2-control-camera.md](./P2-control-camera.md) | `[ACTIVE baseline]` | 观察/第一人称控制、相机和碰撞；第三人称待玩家模型 |
| P3 | [P3-player-interaction.md](./P3-player-interaction.md) | `[NEXT]` | 对话、指向、赠送、协作等交互 |
| P4 | [P4-personalization.md](./P4-personalization.md) | `[LATER]` | 个性化、无障碍、输入设备和成长记录 |

## 分支概述

P 分支让玩家从"观察者"变为"参与者"。从基础的移动和对话，到赠送礼物和共同活动，P 分支构建玩家与 AI 角色之间的自然交互通道。

**核心原则**：
- 玩家使用与 AI 角色相同的空间、碰撞和交互协议
- 角色应基于关系、人设和当前计划接受、协商或拒绝玩家请求

## 依赖关系

```
P2 玩家控制 + P3 交互 + C4 接触系统 ──> 玩家与角色共同活动
```

> 最后更新：2026-07-29 | 基线程：v0.9
