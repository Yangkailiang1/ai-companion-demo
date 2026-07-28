# H10 Batch 1 — 交互锚点与占用预订协议

> 路线图：C4.3、C4.4、C4.5、S3.3、T2.1
> 最后更新：2026-07-28

## 1. 交互锚点合同

每个 `InteractableObject` 提供六个命名的交互锚点，通过 `get_anchor(anchor_name: String) -> Vector3` 查询。

| 锚点名称 | 语义 | 来源 | 缺失回退 |
|----------|------|------|----------|
| `approach` | 角色走近后站立的位置 | `interaction_point` Marker3D（现有） | `global_position + (0, 0, -1)` |
| `look` | 观察目标时的注视点 | `AnchorLook` Marker3D 子节点 | → `approach` |
| `left_hand_grab` | 左手抓取位置 | `AnchorLeftHandGrab` Marker3D 子节点 | → 另一只手 → `approach` |
| `right_hand_grab` | 右手抓取位置 | `AnchorRightHandGrab` Marker3D 子节点 | → 另一只手 → `approach` |
| `place` | 放下物体的目标位置 | `AnchorPlace` Marker3D 子节点 | → `approach` |
| `sit` | 坐下的位置 | `AnchorSit` Marker3D 子节点 | → `approach`（无坐姿物体回退到 approach） |

### 使用方式

```gdscript
var book: InteractableObject = room.get_node("Book")
var grab_pos: Vector3 = book.get_anchor("right_hand_grab")
```

调用方不需要知道物体的场景路径结构；所有回退逻辑封装在对象组件内部。

### 向后兼容

- 现有场景中 `@export var interaction_point: Marker3D` 继续作为 `approach` 锚点。
- 没有定义手部锚点的旧场景自动回退到 `approach`，不会报错或返回零向量。
- 场景作者可以逐步添加 `AnchorLook`、`AnchorPlace`、`AnchorSit` 等 Marker3D 子节点来启用更精确的定位，不影响已有行为。

## 2. 占用预订协议

由 `InteractionReservation`（`RefCounted`）管理单物体生命周期：

```
空闲 ──reserve──▶ 已预订 ──commit──▶ 已确认
  ▲                  ▲                   │
  │                  │ release           │ release
  │                  └───────────────────┘
  └────────────────── 超时（未确认）─────┘
```

### 公开 API（`InteractableObject` 方法）

| 方法 | 签名 | 契约 |
|------|------|------|
| `reserve_interaction` | `(actor_id: String, timeout_seconds: float) -> Dictionary` | 预订物体。重复预订同一角色仅刷新超时。返回 `{success, reason}` |
| `commit_interaction` | `(actor_id: String) -> Dictionary` | 确认占用。只能由当前预订者调用 |
| `release_interaction` | `(actor_id: String) -> Dictionary` | 释放占用/预订，幂等。未预订时亦成功 |
| `get_reserved_by` | `() -> String` | 返回当前预订者 ID；空闲返回 `""` |

### 失败原因

| 原因 | 出现场景 |
|------|----------|
| `occupied` | 物体已被另一个角色预订/确认 |
| `not_reserved` | 调用 `commit` 或 `release` 但预订者不是此角色 |
| `too_far` | `pick_up` 时角色距离超过 `PICK_UP_DISTANCE_THRESHOLD_METERS`（2.0m） |
| `invalid_actor` | 预订、确认或释放时角色 ID 为空 |
| `invalid_timeout` | 预订超时小于等于零或不是有限数值 |

### 与物理拿取的集成

- `pick_up` 成功时自动进行 `reserve → commit` 两阶段确认。
- `put_down` / `throw` 时自动 `release`。
- `pick_up` 时如果角色超出 2.0m 或物体已被占用，返回 `too_far` 或 `occupied`，不改变物理状态和占用状态。

## 3. 文件

| 文件 | 职责 |
|------|------|
| `scripts/objects/interaction_reservation.gd` | `InteractionReservation` 类（RefCounted） |
| `scripts/objects/interactable_object.gd` | 锚点查询、物理交互、占用委托 |
| `scripts/debug/interaction_contract_check.gd` | 头less 合同测试 |
| `scripts/debug/physics_interaction_check.gd` | 已有物理验收（已适配距离合约） |

## 4. 不在本批次范围

- NavMesh 避障和多人路径交叉
- 浇水序列
- 手部 IK
- 新视觉资产
- `ActionExecutor` 或 `AgentBase` 大范围重构
- 移动 `ActionExecutor` 到标准化 `reserve → navigate → commit → release` 流程（Batch 2）
