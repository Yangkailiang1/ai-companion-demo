# X3. AI Provider 与成本

> 所属分支：X. 横向工程能力
> 节点编号：X3
> 状态：`[ACTIVE]`
> 依赖：无（独立的 AI 接口层）
> 最后更新：2026-07-24 | 基线程：v0.7

## 规划方向

### 接口抽象

- Chat、Embedding、TTS、ASR、Motion Provider 使用独立接口
- 支持远端 ECNU、其他 OpenAI 兼容接口和本地模型

### 弹性与降级

- 超时、重试、熔断、缓存、配额和本地降级必须统一

### 线程安全

- 任何远端 AI 都不能阻塞 Godot 主线程

## 相关节点

- [C7 实时语音与听觉](../C-characters/C7-real-time-voice.md) — TTS 接口的抽象
- [C1 文本到动作路由](../C-characters/C1-text-to-action-routing.md) — Embedding 和 LLM 接口

> 相关文档：[X 分支总览](./README.md)
