# H10 — 物理交互与动态导航

> 路线图：C4.1、C4.3-C4.5、C9.5、S3、T2
> 建议分支：`feature/c4-physical-interaction`
> 前置基线：v0.8.8 已有角色/家具碰撞、书与奶茶刚体、拿起/放下/投掷

## 目标

把当前“挂到 CarryAnchor”的物理基线升级为可靠的具身交互链：

`选择目标 → 预订物体 → 可达性检查 → 走近 → 身体对齐 → 抓取 → 携带/使用 →
准确放回 → 释放占用 → 写回世界状态`

同时为客厅启用真正的 NavigationAgent3D avoidance，解决角色互相穿行和多人堵路。

## 文件所有权

允许主要修改：

- `scripts/navigation/**`
- `scripts/objects/**`
- `scripts/core/action_executor.gd`
- `scripts/characters/agent_base.gd`
- `data/scene_config.json`
- `scenes/living_room.tscn`
- 新增的 C4/S3 专项测试与文档

禁止修改：

- `scripts/core/autonomous_behavior_system.gd`
- `scripts/core/agent_psyche_system.gd`
- `scripts/directing/**`
- `scripts/ui/**`
- LLM Prompt 与 Provider

若生活调度器需要新能力，只增加稳定的动作结果/失败事件，不把策略写进物理层。

## 必须实现

1. 为交互物体定义结构化锚点：
   - `approach`
   - `look`
   - `left_hand_grab` / `right_hand_grab`
   - `place`
   - `sit`（适用时）
2. `pick_up` 前必须验证：
   - Actor 与物体存在；
   - 距离满足阈值；
   - 路径可达；
   - 物体未被其他 Actor 占用；
   - Actor 当前没有持有另一件物体。
3. 增加物体占用协议，至少支持 `reserve / commit / release / timeout`。
4. 取消、Actor 删除、路径失败和动作超时都必须幂等释放占用。
5. 放下时使用目标 `place` 锚点；没有目标时使用角色前方安全落点并做碰撞检查。
6. 为书、奶茶、植物、水壶样板提供准确碰撞与交互锚点。
7. 建立浇水完整样板的非 IK 部分：
   - 找到水壶；
   - 预订并拿起；
   - 走到植物；
   - 倒水事件改变植物含水量；
   - 水壶放回原位。
8. NavMesh/avoidance：
   - 主要家具形成导航障碍；
   - 2-5 个角色同时移动时保持最小社交距离；
   - 被堵住时重新寻路，不瞬移；
   - 完成后恢复角色间碰撞或以 avoidance 代理实现等价阻挡。
9. 手部 IK 可作为下一小步，但必须先定义 `HandIKTarget` 合同；没有 IK 的模型应使用
   明确的近似抓握，不得隔空超过验收阈值。

## 失败合同

- 物体被占用：返回稳定原因 `occupied`，不播放成功动作。
- 路径不可达：返回 `unreachable`，物体状态不变。
- 距离过远直接调用：返回 `too_far`，不得自动传送。
- 交互中取消：刚体不能悬空，占用必须释放。
- Actor 消失：物体回到最近安全落点或原锚点。
- 无 NavMesh：保留受边界约束的安全 fallback，但诊断必须说明降级。

## 自动化验收

新增 `scripts/debug/embodied_interaction_check.gd`，至少验证：

1. 远距离拿取失败且状态不变；
2. 走近后拿取成功，持有者唯一；
3. 第二角色争抢同一物体失败；
4. 取消后占用释放且物体未穿过地面；
5. 水壶完成“拿取→浇水→归位”，植物含水量增加；
6. 两角色交叉移动不互穿，且都在超时前到达；
7. 不可达目标不会伪造完成。

必须运行：

```bash
godot --headless --path . --script scripts/debug/embodied_interaction_check.gd
godot --headless --path . --script scripts/debug/physics_interaction_check.gd
godot --headless --path . --script scripts/debug/spatial_autonomy_check.gd
godot --headless --path . --script scripts/debug/autonomous_life_check.gd
godot --headless --path . --script scripts/debug/experience_modes_check.gd
```

## 视觉验收

- 录制或截取拿书、放书、浇水和双角色交叉走位；
- 手与物体最大可见间距目标 `< 12 cm`；
- 物体不能悬空、穿桌、穿地或突然跳到手中；
- 角色不能穿过沙发、茶几、电视、书架和墙体；
- 角色被阻挡时必须停下或绕行，不能持续原地踏步。

## 交付物

- 锚点/占用/失败原因协议文档；
- 可视化调试开关，显示路径、目标锚点和占用者；
- 新合同测试；
- 更新 C4、S3、C9.5 路线图状态；
- 不包含任何角色模型或第三方动画资产。
