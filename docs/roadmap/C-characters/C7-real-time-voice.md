# C7. 实时语音与听觉

> 所属分支：C. AI 角色
> 节点编号：C7
> 状态：`[ACTIVE]`
> 依赖：C1（动作路由）、C3（口型同步）
> 最后更新：2026-07-24 | 基线程：v0.7

## 当前状态

当前 ECNU TTS 已支持异步句子分块播放。

## 规划节点

### C7.1 `[NEXT]` 独立语音配置

每角色独立 voice、速度、音量、队列和打断策略。

### C7.2 `[NEXT]` 缓存与降级

TTS 缓存、失败降级、字幕与音频同步。

### C7.3 `[LATER]` 流式播放

真正 PCM/Opus 流式播放和口型同步。

### C7.4 `[LATER]` 玩家语音输入

玩家语音输入、VAD、ASR 和说话者指向。

### C7.5 `[RESEARCH]` 自定义音色

用户授权的自定义音色；必须包含隐私、同意和滥用防护。

## 相关节点

- [C3 表情和身体语言](./C3-expression-body-language.md) — 口型同步
- [X3 AI Provider 与成本](../X-engineering/X3-ai-provider-cost.md) — TTS 接口抽象

> 相关文档：[C 分支总览](./README.md)
