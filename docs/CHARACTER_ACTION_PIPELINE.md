# CHARACTER_ACTION_PIPELINE.md — 角色动作管线文档

> v0.2 | 最后更新: 2026-07-20

## 概述

本文档描述从玩家输入到角色骨骼动画的完整表现管线。设计原则是 **表现层与认知层解耦** —— CognitiveCycle 不直接操作 AnimationPlayer，而是通过统一的 performance cue 协议驱动。

## Pipeline

```
┌────────────────────────────────────────────────────────────────────┐
│ Player Input / World Event / Idle Timer                           │
└─────────────────────────┬──────────────────────────────────────────┘
                          ↓
┌────────────────────────────────────────────────────────────────────┐
│ CognitiveCycle (cognitive_cycle.gd)                               │
│                                                                    │
│ Input → Perception → Memory → Codified → LLM/Fallback             │
│                                                                    │
│ Output: { goal, speech, emotion, gesture }                        │
│   gesture ∈ { idle, walk, wave, nod, think, happy, sit, talk }    │
│                                                                    │
│ → MessageBus.performance_cue.emit(gesture, context)               │
│ → MessageBus.emit_actions.emit(agent_id, actions)                 │
└─────────────────────────┬──────────────────────────────────────────┘
                          ↓
┌─────────────────────────┴──────────────────────────────────────────┐
│                MessageBus (message_bus.gd)                          │
│  signal performance_cue(gesture: String, context: Dictionary)      │
└─────────────────────────┬──────────────────────────────────────────┘
                          ↓
┌────────────────────────────────────────────────────────────────────┐
│ CharacterAnimationDriver (character_animation_driver.gd)           │
│                                                                    │
│ - 监听 performance_cue 信号                                        │
│ - 校验 gesture 合法性（拒绝未知 gesture）                          │
│ - 查找 AnimationPlayer 中的对应动画                                │
│ - 执行 cross-fade 过渡                                             │
│                                                                    │
│ Walk/Idle 切换：由 AgentBase.is_moving 状态触发                    │
│ 其他 gesture：由 CognitiveCycle 决策 + ActionExecutor 动作触发     │
└────────────────────────────────────────────────────────────────────┘
                          ↓
┌────────────────────────────────────────────────────────────────────┐
│ AnimationPlayer (Godot 内置)                                       │
│                                                                    │
│ Animation Library 来源于 GLB import:                               │
│   idle  → 2.0s loop (breathing + sway)                            │
│   walk  → 1.5s loop (in-place cycle, no root motion)              │
│   wave  → 2.0s oneshot (raise + wave + lower)                     │
│   nod   → 1.5s oneshot (double nod)                               │
│   think → 2.5s oneshot (head tilt + hand to chin)                 │
│   happy → 2.0s oneshot (bounce + arms up)                         │
│   sit   → 3.0s oneshot (leg fold)                                 │
│   talk  → (uses idle animation as base, future: mouth blend)     │
└────────────────────────────────────────────────────────────────────┘
                          ↓
┌────────────────────────────────────────────────────────────────────┐
│ Godot Skeleton3D → Skinned Mesh(es) — 角色模型渲染                 │
└────────────────────────────────────────────────────────────────────┘
```

## 信号协议

### `MessageBus.performance_cue(gesture: String, context: Dictionary)`

| 字段 | 类型 | 说明 |
|------|------|------|
| `gesture` | String | gesture 名称，必须是 `idle`/`walk`/`wave`/`nod`/`think`/`happy`/`sit`/`talk` 之一 |
| `context` | Dictionary | 额外上下文，包含 `source`, `emotion` 等 |

### 校验规则

CharacterAnimationDriver 在 `_on_performance_cue` 中执行校验：
- 未知 gesture → 打印 warning，忽略（保持当前动画）
- 动画库中不存在 → 打印 warning，fallback 到 `idle`
- `talk` gesture → 使用 `idle` 动画作为基础（本轮不实现嘴部动画）

## Gesture 定义

在 `scripts/core/performance_cue_types.gd` 中定义：

| Enum 值 | 字符串 | 动画 | 触发条件 |
|---------|--------|------|---------|
| `Gesture.IDLE` | `"idle"` | idle loop | Agent 停止移动、IDLE primitive |
| `Gesture.WALK` | `"walk"` | walk loop | Agent `move_to()` 调用 |
| `Gesture.WAVE` | `"wave"` | wave oneshot | CognitiveCycle 决策（玩家说"挥挥手"→ local fallback；LLM 可能自主选择） |
| `Gesture.NOD` | `"nod"` | nod oneshot | CognitiveCycle 决策（玩家说"点点头"） |
| `Gesture.THINK` | `"think"` | think oneshot | CognitiveCycle 决策（玩家说"想一想"） |
| `Gesture.HAPPY` | `"happy"` | happy oneshot | CognitiveCycle 决策（玩家说"开心一点"、emotion=happy/happy） |
| `Gesture.SIT` | `"sit"` | sit oneshot | ActionExecutor SIT primitive |
| `Gesture.TALK` | `"talk"` | idle (base) | ActionExecutor SPEAK primitive |

## LLM JSON Schema

LLM 回复的 JSON 增加了 `gesture` 字段：

```json
{
  "thought": "...",
  "goal": "watch_tv",
  "goal_reason": "...",
  "emotion": "happy",
  "emotion_intensity": 0.5,
  "speech": "好呀，我们一起看电视！",
  "speech_tone": "cheerful",
  "gesture": "happy"
}
```

Runtime 校验：`_validate_and_sanitize_gesture()` 在 `cognitive_cycle.gd` 中执行。
未知 gesture → fallback 到 `"idle"`。

## 本地 Fallback Gesture 检测

在 `_use_local_fallback()` 中硬编码 4 个测试句：

| 玩家输入 | gesture | speech |
|---------|---------|--------|
| "挥挥手" | `wave` | "嗨嗨，我在挥手呢～" |
| "点点头" | `nod` | "嗯嗯！我点点头～" |
| "想一想" / "想想" | `think` | "让我想一想……（思考中）" |
| "开心一点" | `happy` | "好嘞！开心起来～" |

## FIFO 保护

玩家输入在 AI 忙碌时进入 `_pending_player_triggers` 队列，不会静默丢失。
此逻辑在 v0.1 已实现，v0.2 未修改。已验证：
- `_on_trigger()` 检查 `is_processing`
- 排队消息通过 `_finish_cycle()` → `_pending_player_triggers.pop_front()` 顺序处理
- UI 显示排队状态："AI 正忙，你的消息已排队（N）"

## 已知限制

1. **talk gesture** 本轮使用 idle 动画作为基础，未实现嘴部 blend shape 动画
2. **sit gesture** 依赖骨骼结构（upper_leg + lower_leg），如果 penguin 骨骼腿太短，视觉效果可能有限
3. **cross-fade 过渡** 当前使用固定 0.2s，未根据动画类型动态调整
4. **程序化动画控制器**（animation_controller.gd）保留作为 fallback，当 AnimationPlayer 没有动画时仍可使用颜色+浮动
5. 庭院源文件使用旧版 Blender/EEVEE 材质节点，Godot 预览仅保证几何可见，最终材质需要美术重制或转换

## 验收结果（2026-07-20）

- `penguin.glb`：1 个 Skeleton3D、14 个蒙皮网格、7 个动画
- `living_room.tscn`：已直接实例化 GLB，自带 AnimationPlayer，无需手工复制动画
- `headless_check.gd`：主场景实例化与 7 个动画存在性检查通过
- `gesture_pipeline_check.gd`：wave/nod/think/happy 以及“看电视”意图动作链检查通过
