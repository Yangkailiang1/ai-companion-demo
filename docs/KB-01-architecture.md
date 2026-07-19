# KB-01: 系统架构

## Autoload 依赖图

```
MessageBus ←── WorldSimulator, SemanticWorld, CognitiveCycle, AgentBase, UI
    ↓
CognitiveCycle ←── SemanticWorld, MemorySystem, CodifiedProfile, GOAPPlanner
    ↓ SignalBus (+ GOAPPlanner, ActionExecutor)
AgentBase
```

**加载顺序**（project.godot autoload）：
1. `SignalBus` — 信号桥
2. `MessageBus` — 事件总线
3. `WorldSimulator` — 时间+需求引擎
4. `SemanticWorld` — 物体+affordance
5. `MemorySystem` — 四层记忆
6. `CognitiveCycle` — 认知循环主控

## 数据流全景

```
Player Input
    │ MessageBus.route_player_input(text)
    ▼
CognitiveCycle._on_trigger(agent, PLAYER_INPUT, data)
    │ 1. SemanticWorld.generate_semantic_snapshot() → NL description
    │ 2. MemorySystem.format_for_llm() → retrieved memories
    │ 3. CodifiedProfile.parse_by_scene() → triggered rules [CCL]
    │ 4. → LLM HTTP (ECNU-Max / OpenAI format)
    ▼
LLM Response {goal, speech, emotion}
    │ 5. GOAPPlanner.plan(goal) → PrimitiveAction chain
    │ 6. SignalBus.emit_actions()
    ▼
AgentBase → ActionExecutor.start_queue()
    │ navigate / interact / speak / idle
    ▼ back to idle, restart idle_timer (30-60s)
```

**Simulation 自主触发**：
```
WorldSimulator._process(delta)
    │ 每日小时: needs decay
    │ need < threshold → MessageBus.route_simulation_event()
    ▼ CognitiveCycle (same pipeline, SIMULATION source)
```

## 设计哲学

| 原则 | 来源 |
|------|------|
| AI 不看像素，读语义快照 | [GA §3.2, §4.1] |
| LLM 输出 Goal，GOAP 分解 Action | v3.0 原创 + [GA §4.4] |
| Simulation 管物理，LLM 管语义 | v3.0 原创 |
| 行为/对话解耦（Action-Dialogue Decoupling） | [CAS §3.4] |
| Agent 等权响应 World Changes + Player Input | [GA §3.3] |
| 角色逻辑本地化（Codified Profile） | [CCL §3.2] |
