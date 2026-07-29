# D2. 导演系统

> 所属分支：D. 剧情与导演
> 节点编号：D2
> 状态：`[ACTIVE baseline]`
> 依赖：D1（剧本格式）、C5（多角色）、T2（空间查询）
> 最后更新：2026-07-29 | 当前切片：v0.8.13

## 规划方向

## v0.8 已实现基线

- 双角色顺序 Beat：走位、互相/物体注视、动作、表情、对白和停顿
- 演出期间暂停自主调度，中断 cast 当前队列
- 走位超时、取消和异步 epoch 隔离，旧演出不会污染立即重播
- 成功后为每个角色写入独立 `[剧情]` 记忆并恢复原调度开关
- `story_director_check.gd` 覆盖成功、拒绝、取消和重播契约

### 时间线与同步

- `[DONE baseline]` 顺序 Beat 和单步走位超时
- `[NEXT]` 并行 Beat、同步点、等待条件和墙钟总超时

### 演出编排

- `[DONE baseline]` 多角色走位、朝向、动作、表情与对白
- `[DONE D2.2 baseline]` StoryDirector 广播稳定的开始/Beat/结束语义事件；
  `PerformanceCameraDirector` 根据当前演员、注视角色或交互物体自动生成单人/
  双主体构图，无需在 LLM 剧本中写死镜头坐标。
- `[DONE D2.2 baseline]` 镜头使用阻尼平滑切换和 FOV 变化；演出中临时隐藏姓名牌、
  启用低强度暖色面部补光，结束后恢复原观察构图。第一人称不被接管。
- `[DONE D2.3 baseline]` Beat 语义自动选择 `movement_wide`、
  `dialogue_two_shot`、`dialogue_close`、`interaction_medium` 和
  `action_medium`；不要求 LLM 输出镜头坐标。
- `[DONE D2.3 baseline]` 每个机位对首选、镜像和左右旋转候选执行物理射线检测，
  选择第一条无遮挡视线。启用 TTS 时按文本长度和 `tts.speed` 延长最低对白镜头
  停留时间；关闭 TTS 时保持原剧本节奏。
- `[DONE D2.3/C4.4]` 演出走位期间角色可穿过拥挤居民；结束时仅对已经安全分离的
  角色恢复碰撞，仍重叠的配对保留例外，避免物理解算把最终站位/入座推出数米。
- `[NEXT]` 真实音频播放完成同步、镜头轨道、越轴保护、角色包围盒构图与景深。

### 状态管理

- `[DONE baseline]` 全局自主调度锁与每角色剧情记忆
- `[NEXT]` 恢复被打断的可恢复日程、局部锁和失败替代站位

## 相关节点

- [D1 小剧本格式](./D1-script-format.md) — 剧本数据格式
- [T2 语义世界与空间协议](../T-runtime/T2-semantic-world.md) — 走位需要的空间查询
- [C5 记忆、人格与日程](../C-characters/C5-memory-personality-schedule.md) — 角色社交调度

> 相关文档：[D 分支总览](./README.md)
