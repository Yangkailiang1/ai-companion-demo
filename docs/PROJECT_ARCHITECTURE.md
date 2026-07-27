# PROJECT_ARCHITECTURE.md — AI Companion Demo 架构文档

> v0.8 | Godot 4.6.1 | GDScript | 最后更新: 2026-07-27

## 一、项目定位

**双层架构**：

| 层 | 职责 | 文件 |
|----|------|------|
| **Living Agent Runtime** | 可复用的 AI Agent 运行时：事件总线、认知循环、记忆系统、GOAP 规划、动作执行 | `scripts/core/` |
| **Demo 表现层** | 以"小叶子"为主角的客厅养成陪伴 Demo：3D 场景、角色、UI | `scripts/characters/`, `scripts/ui/`, `scenes/` |

Runtime 层不依赖任何 Demo 层的表现细节，可单独提取为 Godot 插件。

---

## 二、模块总览与职责

### Autoload 服务（Runtime 层）

| 服务 | 文件 | 职责 |
|------|------|------|
| **MessageBus** | `scripts/core/message_bus.gd` | 统一事件总线：路由 Player/Simulation 触发到 CognitiveCycle，路由 Agent 输出到 UI，下发 GOAP 动作链到 Agent |
| **WorldSimulator** | `scripts/core/world_simulator.gd` | 确定性世界仿真：现实 5 分钟推进 1 游戏小时、Agent 需求衰减/恢复、需求阈值触发（带冷却） |
| **SemanticWorld** | `scripts/core/semantic_world.gd` | 语义世界模型：Object Affordance 表、场景物体管理、自然语言语义快照生成（供 LLM） |
| **MemorySystem** | `scripts/core/memory_system.gd` | 结构化记忆：Episode 记忆存储/检索（加权 recency+importance+relevance）、Semantic/Relationship 记忆、触发 Reflection |
| **CodifiedProfile** | `scripts/core/codified_profile.gd` | 角色逻辑编码 [CCL §3.2]：确定性角色规则匹配（送礼反应、奶茶依赖、情绪变化），生成角色身份提示 |
| **CognitiveCycle** | `scripts/core/cognitive_cycle.gd` | 认知循环主控：感知→记忆检索→Codified→LLM/fallback→GOAP→执行 的完整流程。无 LLM 时使用本地关键词 fallback |
| **AgentPsycheSystem** | `scripts/core/agent_psyche_system.gd` | 每角色 OCEAN/动机、持续心境、注意、意图、活动厌倦和简化 Theory of Mind；生成 LangGraph 兼容状态 |
| **AutonomousBehaviorSystem** | `scripts/core/autonomous_behavior_system.gd` | 环境状态驱动的自主任务调度：优先级、冷却、GOAP 组合任务、玩家打断与多角色结果记忆 |
| **CharacterAdapterRegistry** | `scripts/core/character_adapter_registry.gd` | 按 Agent 注册模型动作、骨骼和表情适配；提供剧情 cast 白名单 |
| **StoryDirector** | `scripts/directing/story_director.gd` | 执行已验证的小剧本 Beat：多角色走位、动作、表情、对白、取消与恢复 |

### 非 Autoload 类（Runtime 层）

| 类 | 文件 | 职责 |
|----|------|------|
| **GOAPPlanner** | `scripts/core/goap_planner.gd` | Goal→Primitive Chain 分解器：10 个 Goal Blueprint（含 patrol/wander），支持模糊匹配、动态 auto_plan 与安全结构化计划 |
| **ActionExecutor** | `scripts/core/action_executor.gd` | 原子动作执行器：顺序执行 NAVIGATE/INTERACT/SPEAK/IDLE/LOOK_AT/PICK_UP/PUT_DOWN/SIT，每步完成后触发下一步 |
| **AffordanceTypes** | `scripts/objects/affordance_types.gd` | 纯枚举/类定义：PrimitiveAction、NeedType、TimeOfDay、Emotion、TriggerSource、NeedsState |
| **StorySchemaValidator** | `scripts/directing/story_schema_validator.gd` | JSON 剧本的纯数据白名单校验与规范化 |

### Demo 层

| 模块 | 文件 | 职责 |
|------|------|------|
| **AgentBase** | `scripts/characters/agent_base.gd` | 3D 角色控制器：接收 GOAP 动作链，执行导航（NavAgent3D + 无 NavMesh fallback 直移），包含 IdleTimer 自主唤醒 |
| **AnimationController** | `scripts/characters/animation_controller.gd` | 程序化动画：待机上下浮动，情绪驱动的颜色变化（happy=绿, sad=蓝, angry=红） |
| **InteractableObject** | `scripts/objects/interactable_object.gd` | 可交互物体：挂载到 StaticBody3D，自动注册到 SemanticWorld |
| **ChatInput** | `scripts/ui/chat_input.gd` | UI 控制器：聊天输入/发送、聊天记录显示（RichTextLabel）、HUD 状态条更新 |
| **DialogueBubble** | `scripts/ui/dialogue_bubble.gd` | 3D 世界空间对话气泡：Sprite3D + Label3D + Timer 自动消失 |
| **CharacterAnimationDriver** | `scripts/characters/character_animation_driver.gd` | 把统一动作/表情 cue 映射到各模型自己的动画与表情通道 |

---

## 三、数据流图

```
┌─────────────────────────────────────────────────────────────┐
│                     World Simulator                          │
│  _process → time_accumulator → game_time + needs decay      │
│  _check_need_thresholds → MessageBus (cooldown: 120s)       │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│                      MessageBus                              │
│                                                              │
│  route_player_input()      ←  ChatInput UI                  │
│  route_simulation_event()  ←  WorldSimulator                │
│  route_idle_wake()         ←  AgentBase IdleTimer           │
│  player_message_received   →  autonomous task interruption  │
│                                                              │
│  agent_trigger_cycle       →  CognitiveCycle                │
│  emit_actions              →  AgentBase                     │
│  action_queue_completed    →  AutonomousBehaviorSystem      │
│  activity lifecycle        →  AgentPsycheSystem             │
│  ui_add_chat_entry         →  ChatInput UI                  │
│  ui_show_bubble            →  DialogueBubble                │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│               AutonomousBehaviorSystem                       │
│  Semantic object change → policy/priority check → GOAP chain │
│  completion → per-Agent episode + relationship observation   │
└──────────────────────────┬───────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│                    CognitiveCycle                             │
│                                                              │
│  1. Perception → SemanticWorld.generate_semantic_snapshot   │
│  2. Memory → MemorySystem.retrieve + CodifiedProfile        │
│  3. Psyche → mood + attention + intention + social beliefs  │
│  4. Decision → LLM API (if configured) else local fallback  │
│  5. GOAP → GOAPPlanner.plan(goal)                           │
│  6. Execute → MessageBus.emit_actions → AgentBase           │
│                                                              │
│  Player input: FIFO queue + explicit-intent goal constraint    │
│  Auto trigger: cooldown gated; idle speech every 90-150s       │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│                      AgentBase                               │
│                                                              │
│  _on_emit_actions → ActionExecutor.start_queue              │
│  _physics_process → NavAgent3D or direct-lerp fallback      │
│  arrived signal → next action in queue                      │
│  IdleTimer 90-150s → MessageBus.route_idle_wake             │
└──────────────────────────────────────────────────────────────┘
```

---

## 四、场景树

```
Main (Node3D)
├── WorldRoot (Node3D)
│   ├── Camera3D (top-down angled: 30° pitch, fov=60)
│   └── LivingRoom (instance: scenes/living_room.tscn)
│       ├── DirectionalLight3D (shadows on)
│       ├── Floor (MeshInstance3D, 8x8)
│       ├── WallBack, WallLeft, WallRight, Ceiling
│       ├── Sofa (StaticBody3D + interactable_object.gd)
│       ├── TV (StaticBody3D + interactable_object.gd)
│       ├── Book (StaticBody3D + interactable_object.gd)
│       ├── MilkTea (StaticBody3D + interactable_object.gd)
│       ├── Plant (StaticBody3D + interactable_object.gd)
│       └── Agent (CharacterBody3D + agent_base.gd)
│           ├── AgentBody (CapsuleMesh)
│           ├── AgentCollision (CapsuleShape3D)
│           ├── AnimationController (Node3D + animation_controller.gd)
│           │   └── AgentHead (SphereMesh)
│           ├── NavigationAgent3D
│           ├── IdleTimer
│           └── DialogueBubble (Sprite3D + Label3D, billboard)
└── UILayer (CanvasLayer)
    └── UI (Control + chat_input.gd)
        ├── HUD (Panel, top-left)
        │   └── HUDLayout (VBoxContainer)
        │       ├── AgentName
        │       ├── TimeDisplay
        │       ├── HungerBar, EnergyBar, FunBar, SocialBar
        │       └── (each with Label + ProgressBar)
        ├── ChatPanel (Panel, bottom-left, ~400x300)
        │   └── ChatLog (RichTextLabel, scroll-following)
        └── InputArea (Panel, bottom edge)
            ├── LineEdit
            └── SendButton
```

---

## 五、Autoload 加载顺序

```
MessageBus → WorldSimulator → SemanticWorld → MemorySystem → CodifiedProfile
→ AgentPsycheSystem → CognitiveCycle → Social/Save/Autonomous services
```

依赖关系：
- MessageBus: 无依赖
- WorldSimulator: → MessageBus
- SemanticWorld: → MessageBus, WorldSimulator
- MemorySystem: → MessageBus
- CodifiedProfile: 无依赖（独立）
- AgentPsycheSystem: → MessageBus, SemanticWorld, MemorySystem, CodifiedProfile
- CognitiveCycle: → MessageBus, SemanticWorld, MemorySystem, CodifiedProfile, AgentPsycheSystem, WorldSimulator

---

## 六、可扩展点设计模式

| 扩展点 | 当前状态 | 扩展方式 |
|--------|---------|---------|
| 新 Agent | AgentBase 通过 event `agent_id` 过滤 | 场景中添加新 CharacterBody3D+AgentBase，设置不同 `agent_name`；记忆按相同 ID 隔离 |
| 新角色模型 | 语义表现 cue 与模型解耦 | 在 `character_runtime_adapters.json` 注册动作、骨骼、表情映射 |
| 新剧情 | JSON Beat 白名单 | 在 `data/stories/` 添加剧本；参考 `docs/STORY_DIRECTOR_RUNTIME.md` |
| 新角色心理 | OCEAN + motive + baseline mood | 在 `agent_psychology.json` 添加同一 `agent_id` 配置 |
| 新物体 | SemanticWorld 的 ObjectData 表 | scene_config.json 添加条目 + 场景添加 StaticBody3D+InteractableObject |
| 新 Goal | GOAP Goal Blueprint | GOAPPlanner._build_blueprints() 添加新映射 |
| 新自主活动 | 状态策略 + GOAP + 完成条件 | 参考 `docs/AUTONOMOUS_LIFE_RUNTIME.md`，必须有冷却、打断和验收 |
| 新角色反应 | Codified Profile Rules | character_config.json 规则数组添加新规则 |
| LLM 切换 | CognitiveCycle._send_llm_request | 修改 provider/url，支持 OpenAI & Anthropic 格式 |
| 导航升级 | 客厅完成 | 程序化 NavigationRegion3D + 家具障碍 + patrol/wander；庭院待烘焙 |

---

## 七、阶段路线图

项目已不再使用单一线性路线表。权威规划入口为：

- [AI Living Town 长期开发规划树](./DEVELOPMENT_ROADMAP_TREE.md)

规划树使用稳定节点编号，并允许每个版本同时从场景、角色、玩家、剧情和
工程底座等分支选择任务，组成可独立验收的版本切片。本文件只描述系统
架构，不再重复维护版本优先级。

---

## 八、资产接入点

### 3D 模型替换

| 节点路径 | 当前 | 替换为 |
|----------|------|--------|
| `Agent/AgentBody` | CapsuleMesh | 骨骼角色模型 |
| `Agent/AgentHead` | SphereMesh | 头部（成为骨骼模型的一部分） |
| `Agent/AnimationController` | Node3D+程序化浮动 | AnimationTree+骨骼动画 |
| `Sofa/SofaMesh` | BoxMesh | 沙发模型 |
| `TV/TVMesh` | BoxMesh | 电视模型 |
| `Floor/WallBack/Left/Right/Ceiling` | BoxMesh | 完整客厅场景 |

### UI 资产

| 位置 | 说明 |
|------|------|
| `scenes/main.tscn` UILayer | 可添加自定义字体、主题样式、背景面板 |
| ChatPanel | 聊天框背景、头像 |
| HUD | 需求图标替代文字标签 |

### 音频

| 触发点 | 文件位置建议 |
|--------|-------------|
| Agent 对话 | `assets/audio/voice/` |
| 环境背景音 | `assets/audio/ambient/` |
| UI 交互音效 | `assets/audio/ui/` |

---

## 九、已知限制

1. **剧情为顺序时间线**：尚无并行 Beat、镜头轨道和语音时长同步
2. **角色资产许可受限**：现有第三方 PMX 只能本机验证，不能随开源仓库发布
3. **本地 fallback 决策简单**：仅关键词匹配，无上下文理解；配置 LLM 后切换完整推理
4. **动作覆盖取决于模型**：缺少某动作的角色会走适配器回退，表现精度不一致
5. **聊天记录不持久化**：结构化角色记忆会保存，但 UI 聊天记录重开后清空
