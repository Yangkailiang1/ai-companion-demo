# v0.8 Q版多角色剧情演出垂直切片

你在 `/Users/yangkailiang/Documents/ai_games/ai_companion_demo` 工作。

必须完整遵守项目根 `CLAUDE.md`，尤其是：

- 新增/修改函数必须在紧邻声明处标注路线图节点；
- 普通 GDScript 目标 300 行、硬上限 400 行；
- 单函数目标 40 行、硬上限 60 行；
- 不继续向已超长 Autoload 堆积职责；
- 不提交、不推送，不修改用户无关文件；
- 不把 `../model/Q版/` 中的 PMX 或贴图复制进仓库，这些模型禁止二次分发。

## 目标

实现 D1 + D2 的最小可用剧情导演，使当前 `main_agent`（咕咕嘎嘎）和
`jue_agent`（诀）能够按结构化剧本完成一段有走位、注视、动作、表情、对白、
停顿和结尾记忆的演出。架构必须允许后续把 cast 绑定到更多 Q 版角色，而无需
复制导演逻辑。

## 数据合同

新增一个 JSON 剧本资源，例如：

`data/stories/cozy_evening.json`

建议结构：

```json
{
  "schema_version": 1,
  "story_id": "cozy_evening",
  "title": "客厅里的小小邀请",
  "cast": ["main_agent", "jue_agent"],
  "beats": [
    {
      "actor": "main_agent",
      "move_to": {"waypoint": "sofa_front"},
      "look_at_actor": "jue_agent",
      "gesture": "wave",
      "expression": "happy",
      "say": "诀，要不要一起坐下来看看电视？",
      "pause_after": 0.35
    }
  ],
  "memory_summary": "和同伴在客厅完成了一次温馨的小演出。"
}
```

只允许白名单字段、角色、gesture、expression、物体和 RoomNavigation 路点。
错误数据必须返回结构化验证错误，不能静默跳过。

## 模块建议

保持模块小而清晰，可采用：

- `scripts/directing/story_schema_validator.gd`
  - 纯验证与规范化，不访问场景树。
- `scripts/directing/story_director.gd`
  - 执行已验证 beat，负责锁、超时、取消、恢复和演出事件。
- `data/stories/cozy_evening.json`
- `scripts/debug/story_director_check.gd`

如需 MessageBus 新信号，可最小修改 `message_bus.gd`，但不要让 MessageBus 执行
导演逻辑。将 `StoryDirector` 注册为 Autoload 是允许的。

## 必须具备的行为

1. `play_story(story_id)`、`play_story_document(document)`、`cancel_story(reason)`。
2. 同一时间只能播放一个故事；重复开始返回明确错误。
3. 开始时暂停 `AutonomousBehaviorSystem` 调度，并打断 cast 当前动作。
4. beat 顺序执行：
   - `move_to.waypoint` 或 `move_to.object`；
   - `look_at_actor` 或 `look_at_object`；
   - gesture 与 expression cue 必须包含正确 `agent_id` 和 `source=story_director`；
   - `say` 走现有 `MessageBus.route_agent_output`，保留气泡、聊天和 TTS；
   - `pause_after` 有范围限制，避免无限阻塞。
5. 走位不可达、角色缺失或超时必须终止故事并报告原因。
6. 成功或取消后都恢复自主调度；成功后分别向 cast 的独立记忆写入带
   `[剧情]` 标记的总结。
7. 公开诊断状态：当前 story、beat index、status、last_error。
8. 不要在启动场景后自动播放，以免每次运行打断玩家。

## 玩家入口

为 MessageBus 增加最小命令路由：

- `!剧情 cozy_evening`
- `!story cozy_evening`

命令只发出剧情请求，不进入 CognitiveCycle。普通对话行为保持不变。

## 验收

新增 `story_director_check.gd`，至少验证：

- 合法剧本通过、非法角色/动作/路点被拒绝；
- 两个角色的 cue 和对白顺序正确；
- 角色确实转向对方，且走位在安全范围；
- 演出过程中自主调度暂停，结束后恢复；
- 两个 Agent 都获得自己的 `[剧情]` 记忆；
- 运行结束没有悬挂的剧情状态；
- 测试不依赖玩家真实存档。

同时确保以下已有测试继续通过：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/headless_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/multi_agent_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/autonomous_life_check.gd
```

完成后输出：

- 修改文件清单；
- 模块职责说明；
- 实际运行的测试及结果；
- 仍存在的风险。
