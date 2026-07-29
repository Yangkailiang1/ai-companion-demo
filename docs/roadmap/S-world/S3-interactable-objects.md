# S3. 可交互物体与状态变化

> 所属分支：S. 场景与世界
> 节点编号：S3
> 状态：`[ACTIVE]`
> 依赖：T2（SceneObjectDescriptor）
> 最后更新：2026-07-28 | 基线程：v0.8.8

## 职责

为场景中的物体定义完整的状态机、交互方式和视觉反馈。

## 第一批物体状态机

### S3.1 `[DONE baseline]` 盆栽

含水量、健康、成长阶段、枯萎、浇水、恢复、语义同步和存档。

### S3.2 `[ACTIVE physics baseline]` 奶茶/食物

容量、新鲜度、持有者、饮用次数和空杯状态。

- `[DONE]` 奶茶已使用 `RigidBody3D`，支持拿起、放下和投掷。
- `[DONE parametric reuse]` 厨房参数化 Manifest 新增餐桌饮料，直接复用统一
  `milk_tea_cup` 资产、碰撞、语义 affordance 和刚体交互，无需房间专用代码。
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

### S3.7 `[ACTIVE H10 pipeline]` 可交互 3D 资产接入流水线

- `[DONE golden object]` Poly Haven CC0 `hanging_picture_frame_01` 已作为
  `wall_art` 完成 AABB/朝向测量、StaticBody3D、碰撞、approach/look 锚点、
  SemanticWorld、inspect/look_at、状态存档、headless 和 Metal 视觉验收。
- `[DONE skill]` 黄金流程已凝练为
  `.claude/skills/godot-import-interactable-object/`；包含对象 Spec、确定性校验器、
  许可/AABB/锚点/失败合同和批量上限，可交给 Claude/DeepSeek 批量执行。
- `[DONE H10-B5]` 以同一静态装饰 archetype 完成三个兄弟对象接入：
  `window`（WindowGlow 窗户）、`back_wall_shelf`（BackWallShelf 墙面搁板 +
  ShelfBookA/B + ShelfVase）、`leaf_art`（LeafArtPanel 叶子装饰画）。每对象均包含
  StaticBody3D 代理、碰撞体、approach/look 锚点、spec JSON、
  scene_config 描述符和 headless 合同检查 `decor_interactable_batch_check.gd`。
- `[NEXT]` 静态家具 archetype（coffee_table, bookshelf 已有视觉 mesh，需新建
  StaticBody3D 代理、碰撞和锚点）；视觉验收待 Codex.

## 每个物体必须同时具备

1. 可持久化状态 → 连接 [X1 存档和迁移](../X-engineering/X1-save-migration.md)
2. 场景视觉反馈 → 连接 [S1 场景美术](./S1-art-ui-presentation.md)
3. SemanticWorld 描述 → 连接 [T2 语义世界](../T-runtime/T2-semantic-world.md)
4. 可执行 Affordance → 连接 [C4 角色场景交互](../C-characters/C4-character-scene-interaction.md)
5. 碰撞与交互锚点
6. 自动化状态转换测试
7. 资产来源、许可、原始 AABB 与正面轴记录

## 相关节点

- [C4 角色与场景交互](../C-characters/C4-character-scene-interaction.md) — 交互的具体实现
- [S5 世界模拟](./S5-world-simulation.md) — 缓慢状态变化（如植物生长）

> 相关文档：[S 分支总览](./README.md) · [统一完成标准](../102-completion-standards.md)
