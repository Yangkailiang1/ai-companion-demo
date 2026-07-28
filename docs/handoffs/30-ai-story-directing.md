# H30 — AI 剧情导演与演出工具

> 路线图：D2、D3、D4、C7
> 建议分支：`feature/d2-parallel-story-director`
> 基线：自然语言 → LLM Story JSON → 白名单 → 顺序 Beat 已通过 ECNU 实测

## 文件所有权

允许主要修改：

- `scripts/directing/**`
- `data/stories/**`
- Story schema/prompt 专项文件
- `scripts/debug/story_*`
- `scripts/debug/experience_modes_check.gd`
- D2/D3/D4 专项文档

只允许通过公共接口调用：

- `MessageBus`
- `SemanticWorld`
- `CharacterAdapterRegistry`
- `MemorySystem`
- `TTSService`

禁止修改：

- `scripts/core/cognitive_cycle.gd`
- `scripts/core/autonomous_behavior_system.gd`
- `scripts/core/action_executor.gd`
- `scripts/characters/**`
- `scripts/ui/**`

`story_director.gd` 已约 440 行；实现前必须提取 timeline runner、lock manager 或
beat executor，使 orchestrator 降到 400 行以内。

## 必须实现

### A. 并行 Beat 与同步点

1. Story schema 支持有限的 `parallel_group` 和 `sync_point`。
2. 每组最大 Actor/Beat 数和总墙钟时间有硬限制。
3. 同一 Actor 不能同时执行两个身体动作。
4. 任一关键 Beat 失败时，根据策略：
   - 取消整组；
   - 使用替代站位/动作；
   - 或明确跳过非关键 Beat。
5. 所有 await 都受 `run_id/epoch` 保护，旧演出不得污染新演出。

### B. 预览、确认与版本化 D3/D4

1. LLM 生成后先进入 `PLANNED`，不得立即改变世界。
2. 输出可读摘要：演员、时长、物体、危险/缺失能力和预计 AI 请求数。
3. 支持确认、取消和有限字段编辑后再校验。
4. 保存 Story JSON 时包含 schema version、生成模型和本地能力快照，但不含 Key。
5. 回放不需要再次调用 LLM。

### C. 语音与镜头

1. 对白 Beat 可等待实际 TTS 时长或使用估算 fallback。
2. TTS 失败时继续字幕演出，不能卡死时间线。
3. 建立有限镜头 cue：wide、two_shot、speaker_closeup、object_focus。
4. 镜头只调用公共 Camera Director，不直接写 UI 输入焦点。
5. 玩家取消、窗口失焦或返回自由模式时立即恢复原相机状态。

### D. 受约束即兴

- 只在 schema 标记的 `improv_slot` 中生成对白；
- 角色人设和记忆作为上下文，不得改变关键剧情结果；
- 即兴失败使用原占位对白；
- 每个演出设置请求次数和 token/字符预算。

## 自动化验收

新增 `parallel_story_check.gd`，至少验证：

1. 两角色并行走位后在同步点汇合；
2. 同一 Actor 并发冲突被 schema 拒绝；
3. 一方不可达时执行明确失败策略；
4. 取消后不再产生对白、动作或剧情记忆；
5. 取消后可立即运行新 Story；
6. 预览未确认时世界状态不变；
7. TTS 失败时字幕和后续 Beat 继续；
8. 保存重放不发起网络请求。

必须运行：

```bash
godot --headless --path . --script scripts/debug/story_director_check.gd
godot --headless --path . --script scripts/debug/experience_modes_check.gd
godot --headless --path . --script scripts/debug/ecnu_live_story_check.gd
godot --headless --path . --script scripts/debug/multi_agent_check.gd
```

`ecnu_live_story_check.gd` 只有在用户明确允许联网且本地已配置 Key 时运行；不得输出
请求头、Key 或完整私人聊天。

## 验收场景

使用固定自然语言剧本：

```text
夜深了。咕咕嘎嘎邀请诀一起收拾客厅：一个人把书放回书架，
另一个人关掉壁灯；两人在沙发旁会合、互道晚安，然后安静离场。
```

验收：

- 规划不是硬编码剧本；
- 两项物体交互可并行但不会争抢；
- 同步会合后才开始最后对白；
- 关灯产生真实光照变化；
- 每个角色只写入自己的剧情记忆；
- 返回自由模式后自主生活可恢复。

## 交付物

- versioned Story schema；
- timeline/parallel runner；
- 预览确认数据合同；
- 失败策略表；
- 固定回归 Story 与测试；
- 更新 D2/D3/D4 文档和示例。
