# P2. 控制与镜头

> 所属分支：P. 玩家
> 节点编号：P2
> 状态：`[ACTIVE first-person baseline]`
> 依赖：无（基础控制器层）
> 最后更新：2026-07-29 | 基线程：v0.9

## 规划节点

### P2.1 `[DONE baseline]` 导演/布置模式

保留当前房间中心观察相机作为“导演/布置模式”；右键/中键环绕、滚轮缩放和
Q/E 键盘预览保持兼容，聊天输入聚焦时不会误转镜头。

### P2.2 `[NEXT]` 第三人称移动

增加第三人称模型、跟随镜头、上下楼和交互射线。当前刻意不显示胶囊占位人；
待 P1 提供可公开分发或用户导入的玩家模型后接入同一个 PlayerBody。

### P2.3 `[DONE baseline]` 第一人称视角

- `WorldRoot/PlayerBody` 是跨房间保留的隐形 `CharacterBody3D`，含胶囊碰撞、
  重力、地面吸附和相机相对 WASD，不混用任何 AI Agent。
- 第一人称使用玩家眼位并自动捕获鼠标；无需按键，直接移动鼠标即可转向。`Esc`
  释放系统光标但不退出第一人称，右键点击非 UI 场景可重新捕获；释放后仍可点击
  旅行门和聊天 UI。
- 地点入口声明位置及朝向；跨房旅行后玩家落在对应入口，AI Cast 仍使用各自
  `cast_spawns`，修复旧观察模式把主 Agent 当成玩家入口载体的问题。
- `[NEXT]` 增加灵敏度、减少镜头运动、键位重映射与 PlayerBody 存档。

### P2.4 `[DONE two-mode baseline]` 模式切换

V 键可在观察/第一人称间切换，模式与鼠标捕获提示同步变化；LineEdit/TextEdit
聚焦期间会释放系统光标，WASD、鼠标视角和 V 切换全部锁定。第三人称加入后扩展
为三模式。

## 自动验收

- `player_first_person_check.gd`：碰撞底座、无临时可见网格、移动/墙体约束、
  鼠标捕获/Esc 释放/右键重捕获、聊天焦点锁、双模式、入口位置和 AI 出生点解耦。
- `camera_orbit_check.gd`：观察模式环绕、UI 指针阻挡和文本焦点。
- `player_first_person_preview_check.gd`：1280×720 Metal 第一人称构图，并在真实
  macOS 窗口验证系统鼠标捕获、Esc 释放和重捕获。

## 相关节点

- [P3 玩家交互](./P3-player-interaction.md) — 控制与交互的配合
- [S2 多房间与小镇](../S-world/S2-multi-room-town.md) — 跨场景移动

> 相关文档：[P 分支总览](./README.md)
