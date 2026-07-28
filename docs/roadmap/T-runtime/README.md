# T 分支：Runtime 主干 — 总览

> 所属系列：AI Living Town 开发规划树
> 分支代码：T
> 目标：建立 Living Agent Runtime 的统一协议、语义世界、插件接口与工程底座

## 子文档索引

| 节点 | 文档 | 状态 | 简介 |
|------|------|------|------|
| T1 | [T1-cognition-action-protocol.md](./T1-cognition-action-protocol.md) | `[ACTIVE]` | 事件、认知、计划、动作执行协议 |
| T2 | [T2-semantic-world.md](./T2-semantic-world.md) | `[ACTIVE]` | 语义世界、空间锚点与场景注册 |
| T3 | [T3-plugin-interface.md](./T3-plugin-interface.md) | `[NEXT]` | 角色/场景/玩家插件接口 |
| T4 | [T4-engineering-foundation.md](./T4-engineering-foundation.md) | `[ACTIVE]` | 存档、测试、性能预算、代码治理与需求追溯 |

## 分支概述

T 分支是整个 AI Living Town 的"神经系统"。它定义了所有角色、场景和玩家共享的基础协议。任何扩展（新角色类型、新场景、新交互方式）都在 T 分支定义的接口范围内实现，不修改核心 Runtime 代码。

**核心原则**：
- 核心 Runtime 不直接依赖特定角色、特定场景或特定 AI 服务
- 所有扩展通过资源文件、注册表和稳定信号接入
- 确定性逻辑（碰撞、导航、物体所有权）由本地 Runtime 执行

## 依赖关系

T 分支被所有其他分支依赖，是系统的"主干"。

- T1（认知协议） → C1 动作路由、C9 生活感
- T2（语义世界） → S3 物体状态、C4 角色场景交互、D2 剧情走位
- T3（插件接口）+ X1（迁移）+ X2（测试） → O1 开源 Runtime

> 最后更新：2026-07-27 | 基线程：v0.7
