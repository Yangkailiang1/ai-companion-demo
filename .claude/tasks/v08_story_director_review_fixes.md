# v0.8 剧情导演审查修正

第一版可以解析并运行，但尚未达到验收标准。请修正以下问题；继续完整遵守根
`CLAUDE.md`，不要提交或推送。

## 1. 长度硬违规

当前：

- `story_schema_validator.gd::_validate_beat` 约 125 行；
- `story_director_check.gd::_test_story_execution` 约 104 行。

拆成语义明确的小函数，所有函数声明到下一个函数声明的跨度必须 `<= 60`，
目标 `<= 40`。修改过的函数仍需紧邻路线图注释。

## 2. 模块位置

把 `scripts/core/story_director.gd` 移到：

`scripts/directing/story_director.gd`

并更新 `project.godot`。导演是 D 分支模块，不属于核心认知 Autoload 目录。

## 3. 取消与异步竞态

当前 `cancel_story()` 在角色走位或等待时调用后，旧的异步栈仍可能继续执行
后续 cue/对白，并可能二次 `_finish_story()`。

增加 run epoch/token：

- 每次启动获得唯一 token；
- `_execute_story`、`_execute_beat`、`_await_move`、`_safe_wait` 在 await 后校验；
- cancel 立即使旧 token 失效，取消 cast 动作/移动，只清理一次；
- 取消后不得再发出对白、cue 或剧情记忆；
- 取消后允许立即启动新故事，旧栈不得污染新故事。

## 4. 正确恢复自主状态

当前结束时无条件 `set_scheduler_enabled(true)`，会破坏调用者原本禁用调度的状态。

- 暂停前记录 `AutonomousBehaviorSystem._scheduler_enabled` 当前值；
- 只在确实获得剧情锁后恢复该原值；
- cast 解析失败时不要修改自主调度；
- 成功、失败、取消都必须走统一幂等清理。

不要向已经超长的 `autonomous_behavior_system.gd` 新增函数。

## 5. 可扩展 cast，不得硬编码两个 Agent

`StorySchemaValidator.VALID_CAST` 会阻塞后续新增 Q 版人物。

- 给 `CharacterAdapterRegistry` 增加一个小型只读公共方法，例如
  `get_registered_agent_ids() -> Array[String]`，带 `[C6][D1]` 注释；
- Validator 构造时接收允许角色列表，默认值仅用于独立测试；
- StoryDirector 用 registry 返回值创建 validator；
- beat.actor、look_at_actor 必须不仅是已注册角色，还必须属于当前 document.cast；
- 顶层字段也要白名单校验；
- Validator 保持纯逻辑，不访问场景树/Autoload。

## 6. 诊断一致性

- 每次成功启动前清空 `_last_error`；
- 成功结束后 `last_error` 为空；
- 失败/取消保留稳定错误；
- 诊断增加 `run_id` 或等价字段，便于定位异步演出。

## 7. 真正覆盖任务合同

重写/拆分 `story_director_check.gd`，不要只测“无走位对白”。

必须增加：

1. 测试剧本让 main 移动到 `stage_left`、Jue 移动到 `stage_right`；
2. 完成后验证两者接近目标点；
3. 验证两者最后互相朝向（用水平 forward 与目标方向 dot product）；
4. 启动前显式启用自主调度，PLAYING 期间验证它为 false，成功后为 true；
5. 再用一个长 pause 或走位故事验证 cancel：
   - cancel 后为 IDLE；
   - 自主调度恢复；
   - cancel 后不再新增对白/cue/[剧情] 记忆；
   - 随后可立即播放短故事且不受旧异步栈污染；
6. 记忆断言不要依赖数组 size 增长，因为 500 项环形上限时 size 不变；
7. 所有断言失败必须最终退出码非 0。

## 8. MessageBus 注释

`route_player_input()` 已修改，必须在函数声明紧邻处补 `[D1][T1]` 合同注释。
保持普通输入与现有 `!` 非剧情命令行为兼容。

## 验收命令

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path . --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/story_director_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/headless_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/multi_agent_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/autonomous_life_check.gd
```

输出修改清单、测试结果和未解决风险。
