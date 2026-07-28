# H20 — 动作库、表情与角色适配

> 路线图：C1.1-C1.3、C2.1-C2.4、C3.1-C3.3、C6
> 建议分支：`feature/c2-motion-expression-library`
> 目标：不同模型通过 Adapter 使用同一动作/表情语义，不修改核心认知逻辑

## 文件所有权

允许主要修改：

- `motion_lab/**`（不含数据集、权重和 vendor）
- `scripts/characters/*motion*`
- `scripts/characters/*animation*`
- `scripts/characters/*expression*`
- `scripts/characters/character_*adapter*`
- `data/motion_catalog.json`
- `data/expression_catalog.json`
- `data/expression_library.json`
- `data/character_runtime_adapters.json`
- `tools/blender/**`
- C1/C2/C3 专项测试与文档

禁止修改：

- `scripts/core/cognitive_cycle.gd`
- `scripts/core/action_executor.gd`
- `scripts/directing/**`
- 场景物理和自主生活策略
- `assets/local_characters/` 内文件

`motion_intent_router.gd` 和 `character_pose_overlay.gd` 已接近/超过函数预算；增加能力前
先提取 catalog/ranker/skeleton resolver，不得让它们继续膨胀。

## 必须实现

### A. 统一动作元数据 C2.3

每个动作至少声明：

- `action_id`、中英文别名、来源和许可证；
- `loop`、`duration_seconds`、`body_layers`；
- `root_motion_policy`；
- 需要的目标/物体/手；
- 接触事件时间点；
- 支持的骨架族与质量状态；
- 是否允许用于碰撞关键行为。

建立 20-30 个核心动作目录，但没有真实剪辑的动作必须标记 `metadata_only`，不得伪装
为已接入。

### B. 路由数据 C1.1-C1.3

1. 记录 query、上下文、候选、分数、最终选择、fallback 原因和人工评价。
2. 日志默认不含完整聊天隐私，支持关闭和脱敏。
3. 建立小型可维护中文测试集，覆盖同义表达、否定、复合指令和模糊请求。
4. ECNU embedding 仅作为可选离线/本地工具；运行时无 Key 时使用确定性 fallback。
5. 输出统一 `PerformanceIntent`，不得直接播放 AnimationPlayer。

目标指标：

- 常用动作测试集 Top-1 ≥ 90%；
- 本地路由 P95 < 100 ms；
- 远程 embedding 超时后 500 ms 内进入本地 fallback。

### C. 骨骼重定向 C2

1. 完成 canonical 22-joint → 模型骨骼的可复用映射合同。
2. Baker 必须处理 rest pose、朝向、比例、关节限幅、足锁和循环边界。
3. 至少用一个可公开测试 fixture 验证企鹅和一个通用 humanoid adapter。
4. 本地受限 Q 角色只能在本机做额外验收，不能进入提交或截图。
5. 输出动作质量报告：脚滑、骨长误差、关节超限、穿模风险和接触误差。

### D. 表情与口型 C3

1. 生成每角色表情覆盖率报告。
2. 统一 `neutral/happy/sad/angry/surprised/shy/bored/confused/blink/talk`。
3. 无 Morph 模型使用头部/姿势 fallback，但不得把 fallback 计为真实 Morph 覆盖。
4. 实现自然眨眼和注视目标；演出动作不得覆盖持续表情状态。
5. 为 TTS 暴露振幅或时间片口型接口；没有音素时间戳时明确使用 amplitude fallback。

## 自动化验收

新增或扩展测试，至少覆盖：

- 同一语义对企鹅、公开占位 humanoid 和本地 MMD adapter 返回合法映射；
- 未知动作不崩溃并回退到 `idle`；
- 导航期间 `walk` 循环，到达后可靠停止；
- 表情混合权重归一化且不会跨 Agent 串线；
- 无 Morph/无骨骼/无本地资产路径；
- 动作元数据 schema 拒绝未知字段和非法接触时间。

必须运行：

```bash
godot --headless --path . --script scripts/debug/gesture_pipeline_check.gd
godot --headless --path . --script scripts/debug/expression_router_check.gd
godot --headless --path . --script scripts/debug/motion_expression_bridge_check.gd
godot --headless --path . --script scripts/debug/character_adapter_coverage_check.gd
godot --headless --path . --script scripts/debug/local_character_runtime_check.gd
```

Python/Blender 工具必须提供不需要真实数据集的 smoke fixture，并运行对应单元测试。

## 视觉验收

- 至少检查 idle、walk、wave、sit 和一个物体动作；
- 不允许 T Pose、反向行走、脚滑、身体横躺或手臂异常扭转；
- 动作切换无明显一帧跳变；
- 本地角色截图不得提交到公开仓库。

## 交付物

- 动作元数据 schema 与核心目录；
- 路由评测集和指标报告；
- 骨骼重定向质量报告；
- 表情覆盖率报告；
- 更新 C1/C2/C3 文档；
- 明确列出仍缺真实动作文件的条目。
