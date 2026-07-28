# T2. 语义世界与空间协议

> 所属分支：T. Runtime 主干
> 节点编号：T2
> 状态：`[ACTIVE]`
> 依赖：T1（认知协议）
> 最后更新：2026-07-28 | 基线程：v0.8.8

## 职责

为所有"地点中的物体"提供统一的语义描述和空间查询能力，让角色能理解"什么东西在哪里、可以做什么、如何交互"。

## 规划节点

### T2.1 `[ACTIVE H10-B1]` SceneObjectDescriptor 统一描述

统一 `SceneObjectDescriptor`：语义 ID、类型、状态、交互点、抓取点、观察点、碰撞范围和权限。

- `[DONE H10-B1]` `get_anchor(anchor_name) → Vector3` 锚点查询 API 已实现；
  物体组件自身提供 approach/look/grab/place/sit 锚点，
  调用方无需硬编码场景路径。参见
  [交互锚点与占用预订协议](../../INTERACTION_ANCHORS_AND_RESERVATION.md)。
- `[DONE H10 golden object]` `data/interactable_objects/*.json` 建立可审查的
  SceneObject 接入 Spec；首个 `wall_art` 验证场景节点、语义描述、真实锚点和
  存档状态的一致性。
- `[DONE H10-B5]` 第二批三件静态装饰物 `window`、`back_wall_shelf`、`leaf_art`
  已接入统一 Spec、SemanticWorld 描述符绑定、scene_config 交互点和 headless
  验证 `decor_interactable_batch_check.gd`。

### T2.2 `[ACTIVE golden object]` 场景注册与空间查询

将物体位置从硬编码坐标升级为场景注册和运行时空间查询。

- `[DONE baseline]` InteractableObject 进入场景后会把 Godot 节点绑定到 descriptor。
- `[NEXT]` 由场景锚点自动回写/校验 descriptor 空间数据，逐步消除 scene_config
  和 `.tscn` 的重复坐标。

### T2.3 `[LATER]` 跨场景位置图

支持跨房间位置图、门、楼层、街区和交通节点。

### T2.4 `[LATER]` 对象关系

支持对象所有权、容器关系和位置关系，例如"书在书架第二层"。

## 依赖关系

```
T2 语义世界 ───┬──> S3 物体状态
               ├──> C4 角色场景交互
               └──> D2 剧情走位
```

## 相关节点

- [S3 可交互物体与状态变化](../S-world/S3-interactable-objects.md)
- [C4 角色与场景交互](../C-characters/C4-character-scene-interaction.md)
- [T4 工程底座](./T4-engineering-foundation.md) — 存档与迁移依赖语义世界 Schema

> 相关文档：[T 分支总览](./README.md) · [分支依赖关系](../99-dependencies.md)
