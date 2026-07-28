# S3. 可交互物体与状态变化

> 所属分支：S. 场景与世界
> 节点编号：S3
> 状态：`[ACTIVE]`
> 依赖：T2（SceneObjectDescriptor）
> 最后更新：2026-07-27 | 基线程：v0.8.7

## 职责

为场景中的物体定义完整的状态机、交互方式和视觉反馈。

## 第一批物体状态机

### S3.1 `[DONE baseline]` 盆栽

含水量、健康、成长阶段、枯萎、浇水、恢复、语义同步和存档。

### S3.2 `[ACTIVE physics baseline]` 奶茶/食物

容量、新鲜度、持有者、饮用次数和空杯状态。

- `[DONE]` 奶茶已使用 `RigidBody3D`，支持拿起、放下和投掷。
- `[NEXT]` 增加容量、新鲜度、饮用次数、空杯视觉与存档。

### S3.3 `[ACTIVE physics baseline]` 书

所在位置、阅读进度、当前读者和放回位置。

- `[DONE]` 书已使用 `RigidBody3D`，支持拿起、放下和投掷；书架支持浏览、取书和放回。
- `[DONE H10-B1]` 交互锚点查询 API 和 `InteractionReservation` 占用预订协议已接入；
  pick_up 时自动 reserve→commit，put_down/throw 时自动 release。
  参见 [交互锚点与占用预订协议](../../INTERACTION_ANCHORS_AND_RESERVATION.md)。
- `[NEXT]` 增加阅读进度、读者占用、准确书架插槽和存档。

### S3.4 `[NEXT]` 电视

开关、频道、音量、观看者和节目事件。

### S3.5 `[ACTIVE baseline]` 门/灯/柜子

开关、阻挡状态、容器内容和使用权限。

- `[DONE baseline]` 壁灯开关可切换开启、关闭和调暗，并同步真实灯光与发光材质。
- `[NEXT]` 门和柜子需要动态阻挡、开合动画、容器内容与权限。

### S3.6 `[DONE baseline]` 茶几与书架

茶几支持查看和放置物品，书架支持浏览、取书和放回；两者均具有实体碰撞体。

## 每个物体必须同时具备

1. 可持久化状态 → 连接 [X1 存档和迁移](../X-engineering/X1-save-migration.md)
2. 场景视觉反馈 → 连接 [S1 场景美术](./S1-art-ui-presentation.md)
3. SemanticWorld 描述 → 连接 [T2 语义世界](../T-runtime/T2-semantic-world.md)
4. 可执行 Affordance → 连接 [C4 角色场景交互](../C-characters/C4-character-scene-interaction.md)
5. 碰撞与交互锚点
6. 自动化状态转换测试

## 相关节点

- [C4 角色与场景交互](../C-characters/C4-character-scene-interaction.md) — 交互的具体实现
- [S5 世界模拟](./S5-world-simulation.md) — 缓慢状态变化（如植物生长）

> 相关文档：[S 分支总览](./README.md) · [统一完成标准](../102-completion-standards.md)
