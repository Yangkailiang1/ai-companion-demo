# AI Companion Demo — 主开发进展

> Godot 4.6.1 | GDScript | ECNU-Max (DeepSeek V4 Flash)（可选）

## 项目定位

**双层架构**：
- **Demo 层**：客厅养成陪伴游戏（AI 数字人"咕咕嘎嘎"）
- **Runtime 层**：Living Agent Runtime — 可复用智能体运行时

设计文档：`/Users/yangkailiang/Documents/ai_games/设计方案/AI养成陪伴游戏_设计方案.md`

## Claude / Codex 强制工程规范

本节是项目代码修改的最高优先级工程约束。项目状态以本文后续章节为快照，
需求定义以 [`docs/roadmap/`](./docs/roadmap/README.md) 为准，论文依据以
[`docs/KB-02-papers.md`](./docs/KB-02-papers.md) 和
`../调研/论文/` 为准。

### 1. 开工前必须建立需求追溯

每次修改代码前必须：

1. 从 `docs/roadmap/` 选择一个或多个稳定需求节点，例如 `C5.1`、`C9.3`。
2. 阅读该节点的依赖、验收条件和相关论文映射。
3. 在工作说明、代码注释、测试和提交信息中使用相同节点编号。
4. 如果找不到对应节点，先补充规划文档，禁止用“misc”“其他优化”代替需求。

一个文件最多承担 3 个主需求节点。超过 3 个通常说明职责混杂，应先拆分。

### 2. 每个代码文件必须声明职责

新建或进行实质修改的项目代码文件，文件头必须包含：

```gdscript
# Roadmap: C9.3, T1.2
# Responsibility: 管理自主活动的中断、保留和恢复；不执行具体动画。
# Collaborators: MessageBus, ActionExecutor, SemanticWorld
# Tests: scripts/debug/planning_reflection_check.gd
```

Python 文件使用模块 docstring：

```python
"""Text-to-motion retrieval policy.

Roadmap: C1.2, C2.4
Responsibility: Rank motion assets; never mutate Godot world state.
Tests: motion_lab/tests/test_motion_retrieval.py
"""
```

`Responsibility` 必须同时说明“做什么”和“不做什么”。测试、生成文件和第三方
vendor 代码可以不写 `Collaborators`，但仍应能追溯到测试或实验节点。

### 3. 每个函数必须对应路线图需求

所有新函数、被修改函数和逐步迁移的旧函数，都必须在紧邻函数声明的位置写明
需求节点。不能只在文件头写一次后让所有函数隐式继承。

GDScript 公共函数或有副作用的函数：

```gdscript
## [C9.3][T1.2] 玩家交互结束后尝试恢复被暂停的自主活动。
## 前置：角色空闲，活动条件仍成立，资源未被占用。
## 副作用：占用活动资源，并通过 MessageBus 发出动作队列。
## 失败：返回 false，不伪造完成状态。
func resume_suspended_now(agent_id: String) -> bool:
```

GDScript 简单私有函数和 getter：

```gdscript
## [C9.1] 返回角色当前活动 ID；纯读取。
func get_active_activity(agent_id: String) -> String:
```

Python：

```python
def rank_motion(query: str, candidates: list[Motion]) -> list[Motion]:
    """Rank motion candidates by semantic similarity.

    Roadmap: C1.2
    Research: [LAMP]
    Side effects: None.
    """
```

强制规则：

- 每个函数至少有 1 个路线图节点，最多 3 个。
- Godot 生命周期函数也必须标注，如 `_ready()` 可标为
  `[T4.2] 初始化 C5.1/C5.3 所需信号连接`。
- 信号回调说明事件来源、状态改变和可能发出的后续信号。
- 算法来源于论文时添加 `Research: [GA]`、`[CAS]`、`[SOL]` 等稳定标记；
  标记在 `docs/KB-02-papers.md` 注册，不能只粘贴临时 URL。
- 注释解释契约、原因、单位和副作用，不逐行翻译代码。
- 纯 getter 可用一行注释；网络、存档、状态变更、异步函数必须写完整契约。

### 4. 文件和函数长度预算

以下限制只针对项目自有源代码，不包括 `motion_lab/vendor/`、Godot 自动生成文件、
导入资源和第三方代码：

| 类型 | 目标上限 | 硬上限 | 超限处理 |
|---|---:|---:|---|
| GDScript Runtime / UI / Character 文件 | 300 行 | 400 行 | 拆分策略、状态存储、Provider 或 Presenter |
| GDScript Autoload 编排器 | 350 行 | 500 行 | 只保留编排；算法和 I/O 移入普通类 |
| GDScript 测试脚本 | 200 行 | 250 行 | 按需求或场景拆成多个验收 |
| Python 项目模块 | 300 行 | 400 行 | 拆分数据、训练、推理、适配器 |
| Blender / 资产工具 | 400 行 | 500 行 | 拆分几何、材质、导出和校验 |
| 单个函数 | 40 行 | 60 行 | 提取命名良好的纯函数或阶段对象 |

补充限制：

- 每文件目标不超过 20 个函数，硬上限 25 个。
- 单函数参数目标不超过 5 个；复杂上下文使用有类型的 `Resource`、`RefCounted`
  数据类或明确 Schema，而不是无限增长的匿名 `Dictionary`。
- 嵌套深度不超过 3 层；优先使用 guard clause。
- 超过硬上限不能继续追加功能。紧急修复可临时例外，但必须在相应路线图节点记录
  拆分任务、原因和截止版本。
- 行数不是追求碎片化的目标；按“变化原因”拆分，不创建只有转发作用的无意义文件。

### 5. 命名规范

GDScript：

- 文件：`snake_case.gd`。
- `class_name`、`Resource`、数据类型：`PascalCase`。
- 函数、变量、信号：`snake_case`；信号使用已经发生或请求语义，
  如 `activity_completed`、`speech_requested`。
- 常量和枚举成员：`UPPER_SNAKE_CASE`。
- 私有函数和私有状态：前缀 `_`。
- 布尔值：`is_`、`has_`、`can_`、`should_` 开头。
- 回调：`_on_<source>_<event>`；不要使用 `_handle1()`、`do_stuff()`。
- 单位必须进入名称：`timeout_seconds`、`started_at_msec`、`distance_meters`。
- ID 后缀统一：`agent_id`、`object_id`、`activity_id`，禁止同一概念混用
  `name/key/id`。

Python：

- 模块、函数、变量使用 `snake_case`；类型使用 `PascalCase`；常量使用
  `UPPER_SNAKE_CASE`。
- 公开函数和跨模块数据必须有类型标注。
- 训练、推理、数据预处理不得在 import 时自动执行。

### 6. 模块边界与依赖方向

当前允许的依赖方向：

```text
UI / Scene
  -> MessageBus / 公共 Runtime API
  -> Cognition / Utility / Planning
  -> GOAP / Action validation
  -> Navigation / Animation / Object interaction
  -> Godot world state

Provider / LLM / Embedding
  -> 只能返回结构化候选
  -> 不能直接改坐标、节点、碰撞、库存或存档
```

目录职责：

| 目录 | 主要路线图 | 允许职责 |
|---|---|---|
| `scripts/core/` | T1、T2、T4、X1、X3 | 稳定协议、编排、存档、Provider 边界 |
| `scripts/characters/` | C1–C8 | 角色表现、骨骼/动作/表情适配 |
| `scripts/navigation/` | C4、T2 | 可达性、导航和交互点 |
| `scripts/objects/` | S3、T2 | 可交互物体状态与 affordance |
| `scripts/ui/` | S1、P3、P4 | 输入和展示；不得包含认知决策 |
| `cognition_lab/` | T1.5、C5、R5 | LangGraph 实验；不拥有 Godot 物理状态 |
| `motion_lab/` | C1、C2、R5 | 离线训练、检索、重定向与评测 |
| `tools/` | O2、X2、X5 | 资产导入、生成、校验和发布工具 |

跨模块通信优先使用：

1. 有类型的公共方法用于同步查询；
2. `MessageBus` 用于跨域事件；
3. 明确 Schema 的 JSON/Resource 用于数据驱动配置。

禁止：

- UI 直接访问 Autoload 私有字段。
- LLM 输出直接调用 `Node3D.global_position` 或场景树路径。
- 为一个新角色复制 CognitiveCycle、MemorySystem 或 GOAP。
- 从核心 Runtime 反向依赖具体 UI、具体角色模型或某个房间。
- 用字符串拼接临时协议替代已有信号、枚举或 Schema。

### 7. 当前架构审查与重构队列

当前代码已经具备目录分层、MessageBus、SemanticWorld、GOAP、角色适配器和
数据驱动配置，整体方向符合规划树。但以下文件超过预算，不能继续无条件追加：

| 文件 | 当前规模（审查时） | 混合职责 | 建议拆分 |
|---|---:|---|---|
| `cognitive_cycle.gd` | 482 行 / 15 函数（首轮已拆） | Provider、解析、周期编排 | 下一轮提取 `llm_client`、`decision_parser`；已提取 `prompt_builder`、`performance_resolver`、`local_fallback_decider` |
| `autonomous_behavior_system.gd` | 500 行（H10 已提取活动结算） | 调度、评分、恢复、微行为、社交输出 | 下一轮提取 `utility_scorer`、`interruption_coordinator`；已提取 `autonomous_activity_outcome` |
| `agent_psyche_system.gd` | 452 行 / 34 函数 | 心境、人格、日程、ToM、反思 | `psyche_state_store`、`daily_planner`、`social_belief_model` |
| `motion_intent_router.gd` | 341 行 / 24 函数 | 目录、特征、分类、检索、回退 | `motion_catalog`、`feature_provider`、`motion_ranker` |
| `chat_input.gd` | 333 行 / 22 函数 | 输入、聊天展示、主题、焦点动画 | `chat_controller`、`chat_presenter`、`warm_ui_theme` |
| `character_pose_overlay.gd` | 281 行 / 26 函数 | 姿势、手势、表情骨骼回退、骨骼解析 | 按 pose / expression / skeleton resolver 拆分 |

这是渐进重构队列，不要求一次性重写。执行规则：

- 修改上述文件时采用“先提取再新增”，净新增不得让文件继续增长。
- 每次只拆一个清晰职责，并保持现有 headless 合同测试通过。
- 不在重构中顺便改变玩家可见行为；行为变化使用独立提交。

### 8. 类型、状态和异步规范

- 所有公共函数必须声明参数和返回类型；无返回值写 `-> void`。
- 核心状态不得使用平行数组；按 `agent_id` / `object_id` 使用有边界的数据对象。
- Dictionary 跨模块时必须在 `data/*.schema.json` 或文档中定义字段、默认值和版本。
- 存档字段变化必须同步 X1 Schema、迁移逻辑和回归测试。
- `await` 前后假设世界可能变化；恢复后重新验证节点存在、角色状态、资源所有权和
  请求 epoch。
- 网络请求必须有 timeout、状态码校验、取消/过期保护和本地降级。
- 信号连接不得在重复初始化时叠加；释放节点前取消仍在运行的请求或回调。
- LLM、Embedding、TTS 的密钥只从用户配置或环境读取，永不写入仓库、日志和测试夹具。

### 9. 测试与完成标准

每个需求节点至少包含：

- 正常路径；
- 一个失败或降级路径；
- 一个边界或中断路径；
- 若涉及角色，验证 `main_agent` 与 `jue_agent` 状态不串线；
- 若涉及视觉，增加截图或人工视觉验收；
- 若涉及异步，验证超时、重复请求和过期结果；
- 若涉及新角色/物体，证明通过标准接口接入，不修改核心认知分支。

测试文件头使用：

```gdscript
# Verifies: C9.3, T1.2
# Covers: interrupt -> respond -> revalidate -> resume/abandon
```

`[DONE]` 仍以
[`docs/roadmap/102-completion-standards.md`](./docs/roadmap/102-completion-standards.md)
为最终标准。只写代码、没有测试与路线图更新，不算完成。

### 10. 提交与审查

提交信息引用主要需求节点：

```text
feat(C9.3,T1.2): resume autonomous activity after player interaction
fix(S1.2): preserve camera lock while chat input is focused
refactor(T4.5): extract LLM provider from cognitive cycle
```

提交前必须检查：

1. 没有无关用户文件进入提交。
2. 没有 API Key、聊天记录、模型许可证不明资产。
3. 文件/函数未超过预算，或已登记例外。
4. 所有新增/修改函数都有路线图注释。
5. 对应 headless、Python 或资产测试通过。
6. 更新路线图状态、模块文档和必要的论文映射。

## 当前状态（v0.8.9 参数化客厅接入迭代）

| 模块 | 状态 | 文件 |
|------|------|------|
| MessageBus | done (含 performance_cue 信号) | `scripts/core/message_bus.gd` |
| WorldSimulator | done (含需求冷却) | `scripts/core/world_simulator.gd` |
| SemanticWorld | done | `scripts/core/semantic_world.gd` |
| MemorySystem | done baseline（每角色 Episode + 重要性阈值 Reflection） | `scripts/core/memory_system.gd` |
| **AgentPsycheSystem** | **v0.7（OCEAN、动机、心境、注意、意图、简化 ToM、分时段日计划）** | `agent_psyche_system.gd`, `agent_psychology.json` |
| CodifiedProfile | done (关键词匹配) | `scripts/core/codified_profile.gd` |
| CognitiveCycle | done (LLM + 本地 fallback + gesture) | `scripts/core/cognitive_cycle.gd` |
| GOAPPlanner | done (10 goal blueprints + validated dynamic plan) | `scripts/core/goap_planner.gd` |
| ActionExecutor | done (11 primitives + performance cues) | `scripts/core/action_executor.gd` |
| AgentBase | done (NavMesh + walk/idle cues) | `scripts/characters/agent_base.gd` |
| **CharacterAnimationDriver** | **new v0.2** | `scripts/characters/character_animation_driver.gd` |
| **PerformanceCueTypes** | **new v0.2** | `scripts/core/performance_cue_types.gd` |
| AnimationController | done (程序化 fallback) | `scripts/characters/animation_controller.gd` |
| InteractableObject | done | `scripts/objects/interactable_object.gd` |
| ChatInput + HUD | done (v0.6 visual pass) | `scripts/ui/chat_input.gd` |
| DialogueBubble | done | `scripts/ui/dialogue_bubble.gd` |
| 3D 场景 | v0.8.9（legacy 客厅 + 15/15 模型库驱动参数化客厅） | `scenes/living_room.tscn`, `scenes/environments/parametric_living_room_runtime.tscn` |
| **幻想庭院预览** | **new v0.2** | `scenes/environments/endless_garden_preview.tscn` |
| **晓光忆时摄影棚预览** | **new v0.6 candidate** | `scenes/environments/xiaoguang_yishi_preview.tscn` |
| **空间自主与导航** | **done v0.3** | `scripts/navigation/`, `docs/SPATIAL_AUTONOMY.md` |
| **动作/表情轻量路由** | **done v0.5** | `motion_intent_router.gd`, `expression_driver.gd`, `data/*catalog.json` |
| **双角色与角色适配器** | **done baseline，持续扩展** | `character_runtime_adapters.json`, `CHARACTER_ADAPTERS.md` |
| **异步 TTS** | **done baseline（句子分块近流式播放）** | `tts_service.gd`, `docs/TTS_INTEGRATION.md` |
| **版本化存档 + 盆栽状态机** | **new v0.6 baseline** | `save_system.gd`, `plant_state.gd`, `docs/SAVE_AND_OBJECT_STATE.md` |
| **Utility AI 自主生活** | **v0.7 baseline（多活动、个性/日程评分、资源锁、微行为、打断后恢复）** | `autonomous_behavior_system.gd`, `autonomous_life_config.json`, `docs/AUTONOMOUS_LIFE_RUNTIME.md` |
| **LangGraph 共享认知图实验** | **v0.7 prototype（双 thread 隔离、反思节点、日计划加权已验收）** | `cognition_lab/`, `docs/LANGGRAPH_AGENT_RUNTIME.md` |
| **Light-T2M / 离线动作库实验桥** | **offline retarget package + smoke clip done; real samples pending GPU** | `motion_lab/`, `docs/LIGHT_T2M_INTEGRATION.md`, `docs/OFFLINE_MOTION_LIBRARY.md` |
| **Blender 导出管线** | **new v0.2** | `tools/blender/` |
| **Smoke Test** | **new v0.2** | `scripts/debug/smoke_test_gestures.gd` |
| 主场景编排 | v0.8.9（CanvasLayer UI + WorldLocationLoader；legacy/parametric 可切换） | `scenes/main.tscn`, `scripts/environments/world_location_loader.gd` |
| 数据配置 | done | `data/` |
| 架构文档 | done | `docs/PROJECT_ARCHITECTURE.md` |
| 资产需求 | done | `docs/ASSET_REQUIREMENTS.md` |
| **动作管线文档** | **new v0.2** | `docs/CHARACTER_ACTION_PIPELINE.md` |
| **资产来源文档** | **new v0.2** | `docs/ASSET_PROVENANCE.md` |

### v0.1 垂直切片关键修复

- 修复 `living_room.tscn` 12 处 `Transform3D` 退化基矩阵
- 合并 `SignalBus` → `MessageBus`（7→6 Autoloads）
- 移除 `agent_base.gd` 中不存在的 `AnimationTree` 引用
- 重构主场景：`CanvasLayer` + HUD + 紧凑聊天面板 + 底部输入栏
- `CognitiveCycle` 本地 fallback：关键词匹配回复 + 需求驱动决策
- 自主事件冷却：自动触发 15s 间隔，需求阈值 120s 冷却（防刷屏）
- 修正时间单位：现实 5 分钟 = 游戏 1 小时（不再错误地每秒推进 12 游戏小时）
- `AgentBase` NavMesh fallback：无 NavMesh 时直接位置插值移动（不卡死）
- `ActionExecutor` 每轮完成后释放，避免长时间聊天产生节点泄漏
- 玩家输入忙时进入 FIFO 队列，不再静默丢失；UI 明确显示在线 AI、本地规则、排队和思考状态
- 明确指令由 Runtime 约束 Goal（如“看电视”固定为 `watch_tv`），LLM 负责自然回复
- 修正奶茶效果方向（恢复饱腹度而非让角色更饿），自主发言间隔调整为 90–150 秒
- 移除遮挡摄像机的天花板，重新布局家具、补充环境光和 4× MSAA

## 数据流

```
WorldSimulator(_process) → needs decay → MessageBus (cooldown-gated)
Player Input → ChatInput → MessageBus
Agent IdleTimer 30-60s → MessageBus
    ↓
CognitiveCycle: Perception → Memory → Codified → LLM/Fallback → GOAP → ActionExecutor
    ↓
AgentBase: navigate (NavMesh or direct-fallback) / interact / speak / idle
    ↓
UI: ChatLog + HUD (needs bars) + 3D Bubble
```

## 核心 Autoload

```
MessageBus → WorldSimulator → SemanticWorld → MemorySystem → CodifiedProfile → AgentPsycheSystem
→ CognitiveCycle / SocialSystem / AutonomousBehaviorSystem
→ TTSService / CharacterAdapterRegistry / SaveSystem
```

## 已完成验证

- [x] GDScript parse error 修复（chat_input dead code 移除）
- [x] Scene Transform3D degenerate basis 修复（12 处）
- [x] affordance_types.gd `socail` typo → `social`
- [x] 灰盒客厅可渲染（8m×8m, 3墙+地板+天花板, 5 物体, 1 Agent）
- [x] 玩家输入 → Agent fallback 回复
- [x] 自动化 fallback smoke test：输入框提交 → ChatLog → Agent 回复 → 动作队列
- [x] 需求系统运行（hunger/energy/fun/social decay + HUD 实时更新）
- [x] Agent 移动（直接插值 fallback, 无需 NavMesh）
- [x] Godot headless 主场景实例化与 7 个动画检查
- [x] Blender 5.0 导出 + Godot GLB 导入（企鹅、庭院）
- [x] 中文动作指令 → performance cue → AnimationPlayer 自动化验收
- [x] 1280×720 主场景截图验收：企鹅模型、HUD、输入框可见
- [x] OCEAN/动机调制、持续心境、注意、意图、活动厌倦与简化 Theory of Mind
- [x] 一张共享 LangGraph 使用 `agent:main_agent` / `agent:jue_agent` 独立 checkpoint
- [x] 每角色分时段日计划、玩家打断后条件式恢复、重要性阈值反思

## v0.2 新能力

- [x] Performance Cue 统一协议：`MessageBus.performance_cue`（idle/walk/wave/nod/think/happy/sit/talk）
- [x] CharacterAnimationDriver 独立适配器（跨入 CognitiveCycle 和 ActionExecutor）
- [x] LLM JSON schema 增加 `gesture` 字段，Runtime 校验未知 gesture
- [x] 本地 fallback 支持 4 个显式测试句（挥挥手→wave, 点点头→nod, 想一想→think, 开心一点→happy）
- [x] AgentBase 根据 is_moving 自动切换 idle/walk cue
- [x] ActionExecutor 在 SPEAK/SIT 时发出对应 cue（IDLE 不抢占显式 one-shot 动作）
- [x] Blender 导出管线：`export_penguin.py` + `generate_penguin_animations.py` + `export_garden.py`
- [x] 7 个程序化骨骼动画生成脚本（idle/walk/wave/nod/think/happy/sit）
- [x] 幻想庭院预览场景 `scenes/environments/endless_garden_preview.tscn`
- [x] 文档：CHARACTER_ACTION_PIPELINE.md, ASSET_PROVENANCE.md
- [x] FIFO 队列保留（v0.1 已有，v0.2 未退化）

## v0.3 空间自主状态

- [x] Blender 导出脚本已生成 penguin.glb + garden.glb
- [x] penguin.glb 已替换主场景 Capsule/Sphere 灰盒
- [x] GLB 自带 AnimationPlayer 已由 CharacterAnimationDriver 自动发现
- [ ] 配置 `data/llm_config.json` 后端到端 LLM + gesture 测试
- [x] 客厅程序化 NavigationRegion3D（家具障碍、巡逻和闲逛路径）
- [ ] 庭院 NavigationRegion3D 烘焙
- [ ] 添加外部 3D 资产替换灰盒家具（沙发、电视、茶几等）

## v0.4 动作与表情桥

- [x] 动作库/表情库 JSON 与中英文确定性路由
- [x] HumanML3D 22 关节到企鹅核心骨骼映射（仅重定向输入，不可直接赋值播放）
- [x] Godot Morph Target 表情驱动：joy/angry/blink/基础口型
- [x] 未知明确动作生成请求保留 Light-T2M prompt，并使用安全动作回退
- [x] `motion_lab/` 服务器合同、环境探测、输入/输出校验和官方采样批处理包装
- [x] 完成 `(T,22,3)` 到角色无关离线 retarget package 的第一版
- [x] 烘焙 `offline_smoke_walk` 到 `penguin.glb` 并接入 Router/Godot 白名单
- [ ] 在 Linux NVIDIA 服务器用官方 `hml3d.ckpt` 生成 5–10 条真实样本
- [ ] 将真实样本批量 retarget、视觉验收并扩充 `motion_catalog.json`

## 动作库后续任务记录

- [ ] 用真实 HumanML3D/Light-T2M `.npy` 替换 smoke fixture，生成 5–10 个语义明确的动作包
- [ ] 增强 `tools/blender/bake_retarget_package.py`：目标骨骼 rest-pose 对齐、关节限幅、足锁、root motion 选择
- [ ] 建立动作验收清单：骨骼长度误差、脚滑、朝向、穿模、循环衔接、表情搭配
- [ ] 将通过验收的动作加入 `data/motion_catalog.json` 与 `PerformanceCueTypes`
- [ ] 后续若切换角色/动作模型，只新增对应 bone map 与 baker adapter，不改 Godot Runtime 主链路

## UI/场景美化方向

- [x] 验证 `终幕喑哑之庭` / `endless_garden_preview.tscn` 在 Godot 中可导入、实例化、渲染
- [x] 验证 `晓光忆时.zip`：源 `.blend` 可用 Blender 5 打开并导出 GLB，Godot 4.6.1 可导入/实例化/基础渲染
- [x] 改造主场景 UI：更清晰的聊天面板、状态栏、输入框层级、可读字体与分辨率适配
- [x] 客厅第一轮美化：暖光、补光、窗光、地毯、柔和材质、相机微调
- [x] 客厅第二轮美化：默认隐藏空聊天面板、电视屏幕微光、墙面装饰、初始画面更干净
- [x] 客厅第三轮美化：下载 Poly Haven CC0 家具与 PBR 贴图，替换灰盒沙发/茶几/电视/绿植，新增书架/吊灯/相框，地板/墙面/地毯绑定 1K PBR
- [x] 客厅第四轮修正：茶几可见性、桌面物体高度、沙发落地毯、右侧柜靠墙、电视暖暗屏、房间外暖色背景、墙脚线、靠垫、角色改名“咕咕嘎嘎”、右键/滚轮/QE 房间中心环绕相机、轻量待机呼吸
- [x] 客厅第五轮交互/UI：相机输入从 `_unhandled_input` 改为 `_input`，右键/中键拖拽、滚轮、Q/E、A/D、方向键均可绕房间中心调整；UI 改成奶油木色温馨主题，新增视角操作提示
- [x] 客厅第六轮 UI 尺寸：HUD、状态栏、底部输入区与按钮增加留白和宽高，修正文字贴边/框体比例不协调问题
- [x] 客厅第七轮墙面/灯光：隐藏误读为桌边悬空灯的吊灯模型，改为左右墙暖色壁灯；后墙新增画框组合、木质搁板、小书与花瓶，提升墙面温馨质感
- [x] 客厅第八轮布景修正：修正电视机朝向，隐藏旧黑色屏幕底板；明确白色发光板为窗户/窗光，并把搁板与装饰物移到窗户左侧，避免“架子钉在窗户上”的误读
- [x] 客厅第九轮输入焦点：输入框显式 I-beam 光标与高亮焦点边框；相机键盘旋转在文本输入聚焦时停用，鼠标在 UI 区域时不会触发右键/滚轮视角旋转
- [ ] 评估是否把客厅灰盒替换为庭院/晓光忆时新场景，或先作为独立预览/约会地点切换
- [ ] 处理庭院材质：透明叶片、贴图色彩、灯光、相机 framing、导航区域/手工 waypoint
- [ ] 处理晓光忆时材质：源包标注 Blender 3.6 专用；当前 Blender 5 → GLB 只能保留基础几何/部分材质，若要接近原始预览图，需要用 Blender 3.6 重导、烘焙贴图/光照，或在 Godot 手工重建灯光/体积光/窗光
- [ ] 下一轮 UI：聊天面板折叠/展开、消息气泡化、场景切换入口、移动端比例检查

## 后续版本路线

长期路线不再维护为单一线性表格。统一规划入口：

- **[AI Living Town 开发规划文档](./docs/roadmap/README.md)**

规划树使用稳定分支编号组织场景、AI 角色、玩家、剧情导演、开源生态和
横向工程能力。每个版本从多个分支选择节点组成一个可交付的"版本切片"。
文档结构已按分支拆分，每个开发方向独立成文，便于并行推进。

> 详细规划树索引 → [docs/roadmap/README.md](./docs/roadmap/README.md)
> 文档维护规范 → [docs/roadmap/CLAUDE.md](./docs/roadmap/CLAUDE.md)

当前 `v0.8.9` 已打通 S4 参数化单房间与 S2 WorldLocation 基线；下一步优先把
Cast/Spawner 从旧客厅资源中解耦，再扩展厨房、卧室和地点连接图。

## 知识库

- [KB-00 总索引](./docs/KB-00-overview.md)
- [KB-01 系统架构](./docs/KB-01-architecture.md)
- [KB-02 论文引用](./docs/KB-02-papers.md)
- [KB-03 实现细节](./docs/KB-03-implementation.md)
- **[PROJECT_ARCHITECTURE](./docs/PROJECT_ARCHITECTURE.md)** — 完整架构文档 (v0.1 新增)
- **[ASSET_REQUIREMENTS](./docs/ASSET_REQUIREMENTS.md)** — 资产需求清单 (v0.1 新增)
- **[开发规划文档树](./docs/roadmap/README.md)** — 长期规划树与版本切片（已拆分为多文档结构）
- **[HUMANLIKE_AGENT_RESEARCH_MAPPING](./docs/HUMANLIKE_AGENT_RESEARCH_MAPPING.md)** — 调研结论到当前实现的映射
- **[LANGGRAPH_AGENT_RUNTIME](./docs/LANGGRAPH_AGENT_RUNTIME.md)** — 共享认知图、角色状态与 Godot 边界

## LLM 配置（可选）

无 `data/llm_config.json` 时使用本地 fallback。配置后自动切换完整 LLM 推理：

- **API**: `https://chat.ecnu.edu.cn/open/api/v1` (OpenAI 兼容)
- **模型**: `ecnu-max` → DeepSeek V4 Flash
- **格式**: OpenAI Chat Completions
- 配置模板见 `data/llm_config.json.example`

## 快速启动

### Godot 运行

1. 用 Godot 4.6.1 打开 `project.godot`
2. 按 F5 运行，看到角色、温馨客厅、左上角 HUD、聊天面板和底部输入栏
3. 在底部输入框打字并回车或点"发送"
4. 咕咕嘎嘎会回复并可能执行动作（喝奶茶、看电视等）
5. 可选：创建 `data/llm_config.json` 启用完整 AI 推理

默认使用稳定的 legacy 客厅。开发者可直接验证模型库驱动的参数化客厅：

```bash
AI_GAMES_WORLD_MODE=parametric \
  /Applications/Godot.app/Contents/MacOS/Godot --path .
```

参数化模式使用相同 `main.tscn`、UI、相机和角色 Runtime，不是独立效果预览。

### v0.2: Blender 资产管线（已执行）

```bash
# 1. 导出企鹅模型 + 生成动画
/Applications/Blender.app/Contents/MacOS/Blender --background /Users/yangkailiang/Documents/ai_games/model/extracted/penguin.blend --python tools/blender/export_penguin.py
/Applications/Blender.app/Contents/MacOS/Blender --background /Users/yangkailiang/Documents/ai_games/model/extracted/penguin.blend --python tools/blender/generate_penguin_animations.py

# 2. 导出庭院场景
/Applications/Blender.app/Contents/MacOS/Blender --background /Users/yangkailiang/Documents/ai_games/scene/extracted/garden.blend --python tools/blender/export_garden.py

# 3. Godot 会自动导入 GLB；两个 PackedScene 已在对应 .tscn 中完成实例化

# 3b. 导出/预览晓光忆时摄影棚（源包 readme 标注 Blender 3.6 专用，Blender 5 导出只作为几何验证）
/Applications/Blender.app/Contents/MacOS/Blender --background "/private/tmp/xiaoguang_yishi_extract/撮影スタジオblender版 配布用.blend" --python tools/blender/export_xiaoguang_yishi.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /private/tmp/ai_companion_godot_xiaoguang.log --path . --script scripts/debug/xiaoguang_scene_check.gd

# 3c. 下载客厅家具与 PBR 贴图（Poly Haven CC0, 1K）
python3 tools/assets/download_polyhaven_models.py
python3 tools/assets/download_polyhaven_textures.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /private/tmp/ai_companion_polyhaven_bounds.log --path . --script scripts/debug/polyhaven_asset_bounds_check.gd

# 4. 验证
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script scripts/debug/headless_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script scripts/debug/gesture_pipeline_check.gd
```
