# C4. 角色与场景交互

> 所属分支：C. AI 角色
> 节点编号：C4
> 状态：`[ACTIVE]`
> 依赖：T2（SceneObjectDescriptor、语义世界空间查询）、S3（可交互物体）
> 最后更新：2026-07-29 | 基线程：v0.8.10

## 当前状态

- `C4.0 [DONE baseline]` 缺水盆栽触发 `走近 → 浇水 → 走到沙发 → 坐下休息`，玩家输入可抢占。
- `C4.4 [DONE physics baseline]` 角色具有碰撞体与持有锚点，书和奶茶已打通
  真实拿起、放下和投掷；茶几、书架和壁灯接入统一 Affordance。
- `C4.5 [ACTIVE H10-B1]` 交互距离校验和占用预订协议已实现（`InteractionReservation`）；
  远距离拿取返回 `too_far`，并发抢占用返回 `occupied`。参见
  [交互锚点与占用预订协议](../../INTERACTION_ANCHORS_AND_RESERVATION.md)。

## 规划节点

### C4.1 `[ACTIVE baseline]` 碰撞与避障

所有角色具备准确碰撞体、导航半径和动态避障。

- `[DONE temporary]` 五角色客厅仍与墙体、家具保持实体碰撞，但角色之间暂时使用
  独立碰撞层互相穿行，避免无 NavMesh/局部避障时因放大 Q 角色而堵死自主路线。
- `[DONE baseline]` 每个角色已有胶囊碰撞体；地面、墙体和主要家具已有静态碰撞体。
- `[DONE H10-B2]` NavigationAgent3D 动态 avoidance 已启用，包括：命名 m/s 配置
  （radius=0.36, neighbor_distance=1.8, max_neighbors=6, time_horizon_agents=1.5,
  time_horizon_obstacles=0.5, max_speed=3.0）、desired velocity 提交到
  NavigationAgent、safe velocity 回调驱动 CharacterBody3D motion、移动角色稳定优先级、
  静止角色小幅互惠让路和无 NavMesh 匀速 fallback。取消时 velocity 归零。
- `[NEXT]` 恢复角色间实体碰撞层（当前代理碰撞可保证安全距离）并验证演员同屏社交
  距离不超过物理区域空间。

### C4.2 `[DONE baseline]` 语义物体交互

行为计划引用语义物体 ID 与 interaction point，不让 LLM 保存绝对坐标。

### C4.3 `[ACTIVE baseline]` 交互锚点

目标物体提供 approach/grab/look/sit 等交互锚点；盆栽和沙发已接入。

- `[DONE H10-B1]` `get_anchor(anchor_name) → Vector3` 统一锚点查询 API 已实现；
  支持 approach/look/left_hand_grab/right_hand_grab/place/sit 六种锚点，
  缺失时确定性回退到 approach。
- `[NEXT]` 场景中为家具添加具体 AnchorLeftHandGrab 等 Marker3D 子节点。

### C4.4 `[ACTIVE baseline]` 完整交互链路

实现 `走近 → 对齐 → 伸手 IK → 抓取 → 持有 → 使用 → 放回`。

- `[DONE baseline]` `ActionExecutor → InteractableObject → RigidBody3D` 已打通；
  书和奶茶会实际挂到 `CarryAnchor`，放下/投掷后恢复物理模拟。
- `[DONE watering-tool baseline]` 参数化客厅的浇水活动会寻找并走近独立
  `watering_can` 刚体，拿到 CarryAnchor 后再走向盆栽、执行浇水并在植物旁放下；
  没有水壶的旧房间确定性降级为原直接浇水链。
- `[DONE H10-B1]` 走近距离校验（`PICK_UP_DISTANCE_THRESHOLD_METERS = 2.0`）
  和 `InteractionReservation` 占用锁已接入 pick_up/put_down 链路。
- `[NEXT]` 增加身体对齐、手部 IK、抓握姿势、倒水动画和精确归位锚点。

### C4.5 `[ACTIVE H10-B1]` 失败处理

失败处理：物体被占用、路径阻塞、目标移动、动作取消和重新规划。

- `[DONE H10-B1]` `InteractionReservation` 占用预订协议已实现：
  reserve/commit/release 生命周期、超时自动清除、幂等 release、
  稳定失败原因 `occupied`/`not_reserved`/`too_far`。
  pick_up 失败时不改变父节点、碰撞层、位置和占用状态。
- `[DONE H10-B2 baseline]` 动态堵塞触发有限次安全 waypoint 绕行，到达临时点后恢复
  原目标；候选点避开当前角色占用位置。仍失败时返回 `stuck`。
- `[DONE H10-B3]` ActionExecutor 已消费导航与物体交互的稳定失败结果，在首个失败
  处停止队列；失败不会执行后续动作、应用需求/消耗效果或发出 success completion。
  AgentActionRuntime 分离成功/失败生命周期，自主活动失败会释放资源、写入失败记忆
  并发出 interruption，禁止伪装成功。
- `[NEXT]` 将 `occupied/stuck/target_moved` 连接到有限次数重新规划，而不是只结束活动。

### C4.6 `[LATER]` 多角色接触

多角色接触：握手、递物、并排坐、共同观看和保持社交距离。

## Navigation Avoidance 协议（C4.1）

> 最后更新：2026-07-28 | 实现批次：H10-B2

### 架构

每个 `CharacterBody3D`（main_agent, jue_agent, 以及通过 `local_runtime_character.tscn`
动态生成的角色）在其子节点树中持有一个 `NavigationAgent3D`。
`NavigationAvoidanceController` 独立配置 avoidance 参数和互惠让路策略；
`agent_base.gd` 在 `_physics_process` 中提交 desired velocity。

NavigationAgent 的输出由 `velocity_computed(safe_velocity)` 信号传回；信号回调在
`CharacterBody3D` 上设置 `velocity = safe_velocity` 并调用 `move_and_slide()`。
这个提交-回调循环让 NavigationServer 在每个物理帧计算角色间避让。移动角色使用
稳定哈希优先级；静止角色在安全位置内以不超过 0.65 m/s 小幅让路。

### 配置（agent_base.gd）

| 参数 | 值 | 说明 |
|---|---|---|
| `AGENT_RADIUS_METERS` | 0.36 | 匹配胶囊碰撞体半径 |
| `NEIGHBOR_DISTANCE_METERS` | 1.8 | 角色间 avoidance 查找范围 |
| `MAX_NEIGHBORS` | 6 | 同时避免的最大邻居数 |
| `TIME_HORIZON_AGENTS` | 1.5s | 角色间碰撞推测时长 |
| `TIME_HORIZON_OBSTACLES` | 0.5s | 障碍物回避推测时长 |
| `MAX_SPEED_METERS` | 3.0 | avoidance 计算的最大速度 |
| `SOCIAL_CLEARANCE_METERS` | 0.6 | 预期最小角色间安全距离 |
| `IDLE_YIELD_MAX_SPEED_METERS` | 0.65 | 静止角色互惠让路速度上限 |
| `MOVE_SPEED` | 3.0 | 常速移动速度 m/s |
| `ARRIVE_THRESHOLD` | 0.5 | 判定到达的距离阈值 |
| `STUCK_TIMEOUT` | 2.5s | 判定卡死的时间阈值 |
| moving priority | `0.5 + hash(agent_name) * 0.4` | 移动角色稳定优先级 |
| idle priority | `0.1` | 允许静止角色小幅让路 |

### 确定性防死锁

- 移动角色的 `avoidance_priority` 由 `agent_name` 稳定哈希派生，范围 0.5–0.9。
- 静止角色使用 0.1，在预测碰撞且候选位置可行走时执行小幅互惠让路。
- 速度长时间没有进展时，`NavigationRecovery` 最多选择 3 个未使用安全绕行点；
  绕行完成后继续原目标，耗尽后报告 `stuck`，不无限等待。

### Fallback 行为

- 无 NavMesh 时（如未烘焙或运行在缺少 NavigationRegion 的环境中）：
  `_physics_process` 使用匀速直接线性运动及 `move_and_slide()`；avoidance 完全跳过。
- `cancel_movement` 向 NavigationAgent 提交零 velocity 以防止悬挂的
  velocity_computed 回调产生残留移动。在 fallback 路径上直接对
  CharacterBody3D velocity 归零。

### 合同测试

`scripts/debug/navigation_avoidance_check.gd` 验证：

1. 所有活跃角色的 `_avoidance_enabled` 设为 true 且 NavMesh 就绪。
2. 两个移动角色的稳定优先级互不相同。
3. 两角色沿相交路径移动时的最小间距 >= `SOCIAL_CLEARANCE_METERS`。
4. 两轨迹均不穿过 `scene_config.json` 中定义的障碍物。
5. 两角色均在超时前到达，或反馈稳定的未完成原因。
6. 取消后 velocity 归零、is_moving 置否、NavMesh 和 fallback 路径均通过。

## 验收标准

角色不能隔空拿取、穿过家具或在目标不可达时假装成功。

## 相关节点

- [T2 语义世界与空间协议](../T-runtime/T2-semantic-world.md) — 提供交互锚点和空间查询
- [S3 可交互物体与状态变化](../S-world/S3-interactable-objects.md) — 物体的状态机和 Affordance
- [C9 角色生活感](./C9-life-authenticity.md) — 浇水样板等生活关联行为

> 相关文档：[C 分支总览](./README.md) · [统一完成标准](../102-completion-standards.md)
