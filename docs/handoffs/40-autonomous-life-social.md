# H40 — 自主生活、记忆与社交

> 路线图：C5.1-C5.5、C9.2-C9.8、X1
> 建议分支：`feature/c9-life-continuity`
> 目标：让角色形成连续生活，而不是轮询事件后播放随机动作/台词

## 文件所有权

允许主要修改：

- `scripts/core/autonomous_*` 新模块
- `scripts/core/agent_psyche_*` 新模块
- `scripts/core/memory_system.gd`
- `scripts/core/social_system.gd`
- `data/autonomous_life_config.json`
- `data/agent_psychology.json`
- C5/C9/X1 专项测试和文档

禁止修改：

- `scripts/core/action_executor.gd`
- `scripts/characters/agent_base.gd`
- `scripts/navigation/**`
- `scripts/objects/**`
- `scripts/directing/**`
- `scripts/ui/**`

物理能力只能通过现有公共动作/结果合同使用。缺能力时记录 `blocked_reason`，不得在
生活系统中直接移动节点或改刚体。

`autonomous_behavior_system.gd` 约 532 行、`agent_psyche_system.gd` 约 452 行。
本任务第一步必须分别提取至少一个职责模块，例如：

- `activity_runtime`
- `utility_scorer`
- `interruption_coordinator`
- `daily_plan_store`
- `social_belief_model`

## 必须实现

### A. 行为连续性 C9.2/C9.3

1. 活动状态至少包含：
   - proposed
   - reserved
   - transitioning
   - executing
   - verifying
   - completed/failed/suspended
2. 每个活动记录开始原因、预期结果、资源、步骤、当前承诺和失败原因。
3. 玩家打断后区分：
   - 可立即取消；
   - 需安全收尾；
   - 暂停后可恢复；
   - 世界条件已改变，应重新规划。
4. 增加安静停顿、转身、起身/坐下过渡和完成后的结果检查。
5. 微行为受当前姿势、关注对象、附近物体和冷却约束，不发送随机对白刷屏。

### B. 共同活动 C9.6

先实现“共同看电视”完整协议：

1. 发起邀请；
2. 被邀请者根据关系、人格、日程和当前承诺接受/协商/拒绝；
3. 预订两个不同座位；
4. 双方走位并等待；
5. 开电视、共同观看、可选短对白；
6. 自然结束并释放座位；
7. 各自写入不同视角的记忆和关系变化。

不得硬编码“所有邀请必定接受”。

### C. 关系与记忆 C5

1. 关系图至少区分 familiarity、trust、affection、respect、conflict。
2. 更新必须有来源事件、幅度上限和衰减/冷却。
3. Theory of Mind 仅作为角色信念，不得覆盖世界事实。
4. Reflection 产生的长期事实需要冲突检测和来源追踪。
5. 存档迁移保持旧存档可读。

### D. 生活节奏与诊断

- 活动重复惩罚和安静时段；
- 角色化活动时长、速度和社交阈值；
- 诊断快照输出候选分数、选择理由、资源、步骤、失败和恢复决定；
- 正式 UI 不显示调试日志。

## 自动化验收

新增 `shared_activity_check.gd` 和 `five_minute_life_simulation_check.gd`（测试可加速时间）：

1. 邀请可接受、拒绝和协商；
2. 两角色不会预订同一座位；
3. 共同活动完成后电视/座位/活动锁均释放；
4. 玩家插话在 500 ms 内产生目标角色注意力 cue；
5. 可恢复任务在条件仍成立时恢复；
6. 条件改变时放弃旧任务并记录原因；
7. 五分钟等价模拟出现至少三类活动，不连续重复；
8. 至少一次物体活动和一次共同活动；
9. 两角色记忆、私密想法和关系视角不串线；
10. 保存/加载后活动承诺与关系数据符合迁移策略。

必须运行：

```bash
godot --headless --path . --script scripts/debug/utility_life_check.gd
godot --headless --path . --script scripts/debug/autonomous_life_check.gd
godot --headless --path . --script scripts/debug/planning_reflection_check.gd
godot --headless --path . --script scripts/debug/agent_psyche_check.gd
godot --headless --path . --script scripts/debug/save_plant_state_check.gd
godot --headless --path . --script scripts/debug/story_director_check.gd
```

## 人工验收

连续观察实际运行五分钟：

- 角色有安静时间，不持续走动或说话；
- 行为有开始、过渡、执行、检查和结束；
- 两角色表现出不同偏好和节奏；
- 共同活动失败时有自然反应，不原地卡住；
- 玩家介入后角色能回应并合理恢复/放弃原活动。

## 交付物

- 拆分后的生活调度/心理模块；
- 共同活动状态机；
- 关系图和存档迁移；
- 五分钟诊断报告；
- 更新 C5/C9/X1 路线图。
