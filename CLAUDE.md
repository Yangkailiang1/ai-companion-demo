# AI Companion Demo — 主开发进展

> Godot 4.6.1 | GDScript | ECNU-Max (DeepSeek V4 Flash)

## 项目定位

**双层架构**：
- **Demo 层**：客厅养成陪伴游戏（AI 数字人"小叶子"）
- **Runtime 层**：Living Agent Runtime — 可复用智能体运行时

设计文档：`/Users/yangkailiang/Documents/ai_games/设计方案/AI养成陪伴游戏_设计方案.md`

## 当前状态（v0.1 — 核心闭环）

| 模块 | 状态 | 文件 |
|------|------|------|
| MessageBus | done | `scripts/core/message_bus.gd` |
| WorldSimulator | done | `scripts/core/world_simulator.gd` |
| SemanticWorld | done | `scripts/core/semantic_world.gd` |
| MemorySystem | done | `scripts/core/memory_system.gd` |
| CodifiedProfile | done | `scripts/core/codified_profile.gd` |
| CognitiveCycle | done | `scripts/core/cognitive_cycle.gd` |
| GOAPPlanner | done | `scripts/core/goap_planner.gd` |
| ActionExecutor | done | `scripts/core/action_executor.gd` |
| AgentBase | done | `scripts/characters/agent_base.gd` |
| UI (chat + bubble) | done | `scripts/ui/` |
| 3D 场景 | done | `scenes/living_room.tscn` |
| 数据配置 | done | `data/` |

## 数据流

```
WorldSimulator(_process) → needs decay → MessageBus
Player Input → ChatInput → MessageBus
    ↓
CognitiveCycle: Perception → Memory → Codified → LLM → GOAP → ActionExecutor
    ↓
AgentBase: navigate / interact / speak / idle
```

## 待完成 (v0.1)

- [ ] Godot 中打开项目验证场景渲染
- [ ] NavigationRegion3D 烘焙导航网格
- [ ] 首次端到端测试 (玩家输入 → LLM → Agent 动作)
- [ ] `data/llm_config.json` 已加入 .gitignore，本地配置

## 后续版本路线

| 版本 | 内容 |
|------|------|
| v0.1 | 核心闭环（当前） |
| v0.2 | 长期记忆 + Reflection 反思 + 情绪系统 |
| v0.3 | 多 Agent + CASCADE 协调 + 本地小模型 |

## 知识库

详细架构/论文/实现见知识库索引：
- [KB-00 总索引](./docs/KB-00-overview.md)
- [KB-01 系统架构](./docs/KB-01-architecture.md)
- [KB-02 论文引用](./docs/KB-02-papers.md)
- [KB-03 实现细节](./docs/KB-03-implementation.md)

## LLM 配置

- **API**: `https://chat.ecnu.edu.cn/open/api/v1` (OpenAI 兼容)
- **模型**: `ecnu-max` → DeepSeek V4 Flash
- **格式**: OpenAI Chat Completions
