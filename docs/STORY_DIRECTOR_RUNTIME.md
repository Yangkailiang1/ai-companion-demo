# 剧情导演运行时

> 对应需求：D1（小剧本格式）、D2（导演系统基础）、C5（多角色记忆）
> 当前版本：v0.8 MVP

## 当前可见效果

在聊天输入框发送：

```text
!剧情 cozy_evening
```

也可使用英文命令 `!story cozy_evening`。系统会暂停角色的自主调度，依次安排
咕咕嘎嘎和诀走位、互相注视、播放动作与表情、说出台词；演出完成后恢复自主
生活，并给参与角色分别写入一条 `[剧情]` 情景记忆。

示例剧本位于 `data/stories/cozy_evening.json`。

## JSON 契约

```json
{
  "schema_version": 1,
  "story_id": "cozy_evening",
  "title": "客厅里的小小邀请",
  "cast": ["main_agent", "jue_agent"],
  "beats": [
    {
      "actor": "main_agent",
      "move_to": {"waypoint": "room_center"},
      "look_at_actor": "jue_agent",
      "gesture": "wave",
      "expression": "happy",
      "say": "要不要一起看看电视？",
      "pause_after": 1.5
    }
  ],
  "memory_summary": "一起在客厅看了电视。"
}
```

每个 Beat 按固定顺序执行：

1. `move_to`：移动到一个路点或语义物体交互点；
2. `look_at_actor` / `look_at_object`：调整朝向；
3. `gesture` / `expression`：向角色适配器发出表现提示；
4. `say`：显示对白，并进入角色自己的语音链路；
5. `pause_after`：留出演出节奏。

`move_to` 只能包含 `waypoint` 或 `object` 之一。角色、路点、物体、动作和表情
都经过白名单校验；未知字段和超过 80 个 Beat 的剧本会被拒绝。

## 运行时组成

| 组件 | 职责 |
|---|---|
| `StorySchemaValidator` | 纯数据校验与规范化，不访问场景树 |
| `StoryDirector` | 角色锁定、顺序执行、走位超时、取消、恢复与记忆 |
| `CharacterAdapterRegistry` | 提供可绑定角色清单及各模型的动作/表情适配 |
| `MessageBus` | 接收剧情命令，发送动作、表情、对白和 UI 状态 |

新增角色不应写死到导演中。角色完成场景实例化并在
`data/character_runtime_adapters.json` 注册后，便可进入剧本 `cast` 白名单。

## 失败、取消和恢复

- 同一时刻只播放一个剧本。
- 启动剧情会中断 cast 成员原有动作，但不会清除长期记忆。
- 走位超过 12 秒、角色丢失或目标无效时，演出失败并恢复原调度状态。
- `cancel_story(reason)` 会使旧的异步执行栈立即失效；取消后不会继续发对白、
  表情提示或成功记忆。
- 存档恢复坐标是一次性消费，后续创建动作执行器不会再把角色瞬移回旧位置。

## 验收

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --log-file /private/tmp/story_director_check.log \
  --path . --script scripts/debug/story_director_check.gd
```

验收覆盖：非法角色拒绝、完整演出顺序、走位与朝向、自主调度暂停/恢复、每角色
独立记忆、取消后无残留输出，以及取消后立即重播不会被旧异步栈污染。

## 下一阶段

- Beat 并行组、同步点、等待条件和真实墙钟级总超时；
- 镜头轨道、构图目标和对白说话者切镜；
- 语音时长驱动停顿，以及口型/表情与语音同步；
- 不可达走位的替代站位搜索与可视化诊断；
- 剧情结束后恢复被打断的可恢复日程，而不只是恢复调度器。
