# X1. 存档和迁移

> 所属分支：X. 横向工程能力
> 节点编号：X1
> 状态：`[ACTIVE schema v2]`
> 依赖：T4（工程底座）
> 最后更新：2026-07-29 | 基线程：v0.8.9

## 当前状态

### X1.1 `[DONE baseline]` 单地点存档

Schema v1 已保存世界时间、需求、物体状态和已加载角色位置。

### X1.2 `[DONE v0.8.9]` 跨地点存档与迁移

- Schema v2 增加顶层 `location {world_mode, location_id}`，每个 Agent 快照同时
  记录 `location_id`，加载时先恢复地点，再恢复世界、对象和角色。
- 未加载房间的语义对象状态进入延迟队列，在对应 Recipe 实例化并注册对象时消费；
  已恢复的 Agent 坐标也只在目标地点新 Cast 生成后应用一次。
- 默认写入 `user://world_save_v2.json`；首次加载会回退读取 v1，并在内存中迁移为
  `legacy/living_room`，不会把旧客厅坐标错误套到参数化房间。
- 未知 Schema、非法地点和畸形 Agent/对象字段均在改变当前世界前 fail-closed。
- `cross_location_save_check.gd` 覆盖厨房/卧室对象、双 Agent 坐标、延迟恢复、
  跨房间/同房间读取、一次性应用、v1 迁移和坏存档保护。

## 后续方向

- `[NEXT P2/X1]` 保存 PlayerBody 的地点、入口后坐标、朝向和视角模式；本轮第一
  人称控制底座尚未写入 Schema v2，避免在控制协议未稳定前扩大迁移面。
- `[NEXT X1.3]` 原子写入、滚动备份、损坏恢复和中断写入故障注入测试
- `[NEXT X1.4]` 加入关系、记忆引用、日程、剧情进度和离屏角色状态
- 角色模型资源与角色身份/记忆分离

## 相关节点

- [T4 工程底座](../T-runtime/T4-engineering-foundation.md) — 存档 Schema 定义
- [C5 记忆、人格与日程](../C-characters/C5-memory-personality-schedule.md) — 记忆持久化
- [S2 多房间与小镇](../S-world/S2-multi-room-town.md) — 跨场景位置存档

> 相关文档：[X 分支总览](./README.md)
