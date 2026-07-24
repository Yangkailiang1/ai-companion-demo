# KB-01: 系统架构

## Autoload 依赖图

```
MessageBus ←── WorldSimulator, SemanticWorld, Psyche, CognitiveCycle, AgentBase, UI
    ↓
AgentPsycheSystem ←── OCEAN, motives, mood, attention, beliefs
    ↓
CognitiveCycle ←── SemanticWorld, MemorySystem, CodifiedProfile, Psyche, GOAPPlanner
    ↓ MessageBus (+ GOAPPlanner, ActionExecutor)
AgentBase
```

**加载顺序**（project.godot autoload）：
1. `MessageBus` — 事件总线
2. `WorldSimulator` — 时间+每角色需求引擎
3. `SemanticWorld` — 物体+affordance
4. `MemorySystem` / `CodifiedProfile` — 记忆与角色规则
5. `AgentPsycheSystem` — 人格、心境、注意、意图、社会信念
6. `CognitiveCycle` — 认知循环主控
7. Social / Save / Autonomous 等外围服务

## 数据流全景

```
Player Input
    │ MessageBus.route_player_input(text)
    ▼
CognitiveCycle._on_trigger(agent, PLAYER_INPUT, data)
    │ 1. SemanticWorld.generate_semantic_snapshot() → NL description
    │ 2. MemorySystem.format_for_llm() → retrieved memories
    │ 3. CodifiedProfile.parse_by_scene() → triggered rules [CCL]
    │ 4. AgentPsycheSystem → mood / attention / intention / beliefs
    │ 5. → LLM HTTP (ECNU-Max / OpenAI format)
    ▼
LLM Response {goal, speech, emotion}
    │ 6. GOAPPlanner.plan(goal) → PrimitiveAction chain
    │ 7. MessageBus.emit_actions()
    ▼
AgentBase → ActionExecutor.start_queue()
    │ navigate / interact / speak / idle
    ▼ back to idle, update psyche/memory, restart idle timer
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
