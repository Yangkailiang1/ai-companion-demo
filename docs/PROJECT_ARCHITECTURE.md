# PROJECT_ARCHITECTURE.md — AI Companion Demo 架构文档

> v0.1 | Godot 4.6.1 | GDScript | 最后更新: 2026-07-20

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

### 非 Autoload 类（Runtime 层）

| 类 | 文件 | 职责 |
|----|------|------|
| **GOAPPlanner** | `scripts/core/goap_planner.gd` | Goal→Primitive Chain 分解器：10 个 Goal Blueprint（含 patrol/wander），支持模糊匹配、动态 auto_plan 与安全结构化计划 |
| **ActionExecutor** | `scripts/core/action_executor.gd` | 原子动作执行器：顺序执行 NAVIGATE/INTERACT/SPEAK/IDLE/LOOK_AT/PICK_UP/PUT_DOWN/SIT，每步完成后触发下一步 |
| **AffordanceTypes** | `scripts/objects/affordance_types.gd` | 纯枚举/类定义：PrimitiveAction、NeedType、TimeOfDay、Emotion、TriggerSource、NeedsState |

### Demo 层

| 模块 | 文件 | 职责 |
|------|------|------|
| **AgentBase** | `scripts/characters/agent_base.gd` | 3D 角色控制器：接收 GOAP 动作链，执行导航（NavAgent3D + 无 NavMesh fallback 直移），包含 IdleTimer 自主唤醒 |
| **AnimationController** | `scripts/characters/animation_controller.gd` | 程序化动画：待机上下浮动，情绪驱动的颜色变化（happy=绿, sad=蓝, angry=红） |
| **InteractableObject** | `scripts/objects/interactable_object.gd` | 可交互物体：挂载到 StaticBody3D，自动注册到 SemanticWorld |
| **ChatInput** | `scripts/ui/chat_input.gd` | UI 控制器：聊天输入/发送、聊天记录显示（RichTextLabel）、HUD 状态条更新 |
| **DialogueBubble** | `scripts/ui/dialogue_bubble.gd` | 3D 世界空间对话气泡：Sprite3D + Label3D + Timer 自动消失 |

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
│                                                              │
│  agent_trigger_cycle       →  CognitiveCycle                │
│  emit_actions              →  AgentBase                     │
│  ui_add_chat_entry         →  ChatInput UI                  │
│  ui_show_bubble            →  DialogueBubble                │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│                    CognitiveCycle                             │
│                                                              │
│  1. Perception → SemanticWorld.generate_semantic_snapshot   │
│  2. Memory → MemorySystem.retrieve + CodifiedProfile        │
│  3. Decision → LLM API (if configured) else local fallback  │
│  4. GOAP → GOAPPlanner.plan(goal)                           │
│  5. Execute → MessageBus.emit_actions → AgentBase           │
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
MessageBus → WorldSimulator → SemanticWorld → MemorySystem → CodifiedProfile → CognitiveCycle
```

依赖关系：
- MessageBus: 无依赖
- WorldSimulator: → MessageBus
- SemanticWorld: → MessageBus, WorldSimulator
- MemorySystem: → MessageBus
- CodifiedProfile: 无依赖（独立）
- CognitiveCycle: → MessageBus, SemanticWorld, MemorySystem, CodifiedProfile, WorldSimulator

---

## 六、可扩展点设计模式

| 扩展点 | 当前状态 | 扩展方式 |
|--------|---------|---------|
| 新 Agent | AgentBase 通过 event `agent_id` 过滤 | 场景中添加新 CharacterBody3D+AgentBase，设置不同 `agent_name` |
| 新物体 | SemanticWorld 的 ObjectData 表 | scene_config.json 添加条目 + 场景添加 StaticBody3D+InteractableObject |
| 新 Goal | GOAP Goal Blueprint | GOAPPlanner._build_blueprints() 添加新映射 |
| 新角色反应 | Codified Profile Rules | character_config.json 规则数组添加新规则 |
| LLM 切换 | CognitiveCycle._send_llm_request | 修改 provider/url，支持 OpenAI & Anthropic 格式 |
| 导航升级 | 客厅完成 | 程序化 NavigationRegion3D + 家具障碍 + patrol/wander；庭院待烘焙 |

---

## 七、阶段路线图

| 版本 | 目标 | 新增内容 |
|------|------|---------|
| **v0.1** (current) | 核心闭环 可运行 | 6 Autoload Runtime + Demo 3D 灰盒 + 聊天 UI + 本地 fallback 决策 |
| v0.2 | 长期记忆 + 情绪 | Reflection 反思模块、Emotion 系统积分、Semantic Memory 生成 |
| v0.3 | 空间自主 | NavigationMesh、动态位置导航、巡逻、闲逛、结构化计划 |
| v0.4 | 长期记忆 | Reflection、情绪连续性、日程与好奇心目标 |
| v0.5 | 多 Agent | CASCADE 协调、Agent 间自发对话、Social Events |

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

1. **无 NavMesh**：导航使用直接位置插值 fallback，Agent 可能穿墙
2. **无骨骼动画**：角色表现仅限于程序化上下浮动 + 颜色变化
3. **本地 fallback 决策简单**：仅关键词匹配，无上下文理解；配置 LLM 后自动切换完整推理
4. **单 Agent**：GOAP/ActionExecutor 为单 Agent 设计，多 Agent 运行时需要实例隔离
5. **无输入历史**：聊天记录不持久化，重开会清空
6. **无 Reflection**：MemorySystem 保留了触发接口但未实现 LLM 反思生成
