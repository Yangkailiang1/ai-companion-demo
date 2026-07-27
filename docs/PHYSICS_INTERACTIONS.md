# 物理与场景交互架构

> 适用版本：v0.8.7

## 当前实现

项目直接使用 Godot Physics 3D。场景中的地面、墙体、沙发、电视、茶几、盆栽、
书架和灯光开关具有静态碰撞体；书和奶茶使用 `RigidBody3D`，可被角色拿起、
放下和投掷。每个运行时角色均具有胶囊碰撞体与 `CarryAnchor` 持有锚点。

碰撞层约定：

- Layer 1：场景、家具和可交互物体。
- Layer 2：角色；角色检测 Layer 1。
- 角色之间暂不互相阻挡，避免在尚未接入 NavMesh 局部避障时堵死走位。

## 语义物体与 Affordance

`data/scene_config.json` 是 LLM 与运行时共同读取的场景契约。当前登记八个物体：

| 物体 ID | 主要能力 |
|---|---|
| `sofa` | 坐下、休息 |
| `tv` | 开关、观看 |
| `coffee_table` | 查看、放置物品 |
| `book` | 查看、拿起、放下、投掷 |
| `milk_tea` | 饮用、拿起、放下、投掷 |
| `plant` | 查看、浇水 |
| `bookshelf` | 浏览、取书、放回 |
| `room_lights` | 开灯、关灯、调暗 |

完整调用链为：

`SceneObjectDescriptor → LLM 剧情规划 → 白名单校验 → ActionExecutor →
InteractableObject → Godot 物理/视觉状态`

LLM 只输出语义物体 ID 和交互动作，不保存绝对坐标。运行时负责找到对象、
执行动作并更新实际物理状态。

## 拿取与投掷

拿起物体时，运行时冻结刚体、关闭其碰撞并把它挂到角色的 `CarryAnchor`。
放下时恢复原场景父节点、碰撞与物理模拟，并将物体放到角色前方。
投掷会恢复刚体并施加线性与旋转冲量。

## 验收

```bash
godot --headless --path . --script scripts/debug/physics_interaction_check.gd
```

该检查覆盖角色碰撞体、持有锚点、场景碰撞、书本拿取/放下、奶茶投掷、
茶几/书架 Affordance，以及壁灯的真实光照和发光状态。

## 后续限制

- 仍需烘焙 NavMesh，并使用 `NavigationAgent3D` avoidance 恢复角色间实体阻挡。
- 当前持有锚点是通用位置，尚无手部 IK、抓握姿势和精确接触对齐。
- 物体占用、双角色递物、容器库存和路径失败后的重新规划仍待实现。
- 物理运动中的瞬时速度、持有关系还未进入完整存档协议。
