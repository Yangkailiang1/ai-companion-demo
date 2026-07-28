# D1. 小剧本格式

> 所属分支：D. 剧情与导演
> 节点编号：D1
> 状态：`[DONE MVP]`
> 依赖：C5（角色绑定）、T1（动作协议）
> 最后更新：2026-07-27 | 当前切片：v0.8

## 已实现的剧本格式（JSON）

```json
{
  "schema_version": 1,
  "story_id": "cozy_evening",
  "title": "一起看电视",
  "cast": ["main_agent", "jue_agent"],
  "beats": [
    {
      "actor": "main_agent",
      "move_to": {"waypoint": "room_center"},
      "look_at_actor": "jue_agent",
      "gesture": "wave",
      "expression": "happy",
      "say": "我们一起看电视吧。",
      "pause_after": 1.5
    }
  ],
  "memory_summary": "一起在客厅看了电视。"
}
```

## 基本要求

- 解析后只生成白名单内的对白、动作、地点和物体交互
- 缺失动作自动使用安全回退；不可达位置必须报告而不是跳过
- 剧本角色绑定 CharacterAdapterRegistry 中已注册的 Agent

## 已实现

- `StorySchemaValidator`：字段、角色、路点、对象、动作、表情和长度白名单
- `StoryDirector`：加载 `data/stories/<story_id>.json` 并执行
- 聊天命令：`!剧情 cozy_evening` / `!story cozy_evening`
- 示例与完整契约：[剧情导演运行时](../../STORY_DIRECTOR_RUNTIME.md)

临时角色槽位、创作 UI 和 AI 扩写仍属于后续版本。

## 相关节点

- [D2 导演系统](./D2-director-system.md) — 剧本的执行引擎
- [C5 记忆、人格与日程](../C-characters/C5-memory-personality-schedule.md) — 角色绑定与剧本结束后的恢复
- [D3 AI 辅助剧情](./D3-ai-assisted-plot.md) — LLM 扩写剧本

> 相关文档：[D 分支总览](./README.md)
