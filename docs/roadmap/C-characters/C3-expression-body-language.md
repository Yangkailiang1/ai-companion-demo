# C3. 表情和身体语言

> 所属分支：C. AI 角色
> 节点编号：C3
> 状态：`[ACTIVE]`
> 依赖：C1（表情路由）、C7（语音驱动口型）
> 最后更新：2026-07-27 | 基线程：v0.8.6

## 当前进展

- `[DONE baseline] C3.1` 运行时 manifest 可为每个角色声明独立 Morph 别名。
- 三名本机 MMD 样板分别保留 37/69/70 个 Morph，并已验证开心表情实际驱动 `笑い`；
  `怒り/まばたき/あいうえお` 已映射到共享表情协议。
- `[DONE local library]` 共享 `sad/surprised/shy/bored/confused` 通道已分别映射到
  `悲しい/驚き/なごみ` 或 `困る/びっくり/照れ2/じと目` 等模型原生 Morph，
  并逐角色验证真实权重变化。
- 无 Morph 模型支持头部骨骼 fallback；尚未完成 TTS 音素级口型同步。

## 规划节点

### C3.1 `[ACTIVE baseline]` BlendShape 适配

为每个角色建立 BlendShape/骨骼表情适配表和覆盖率报告。

### C3.2 `[NEXT]` 基础表情行为

眨眼、视线、注视目标、头部朝向和说话口型。

### C3.3 `[NEXT]` TTS 口型同步

TTS 音素/振幅驱动的基础口型同步。

### C3.4 `[LATER]` 标准化表情协议

采用 VRM/ARKit 风格表情协议，支持更丰富模型。

### C3.5 `[LATER]` 情绪连续性

表情、姿势和语音语气的统一情绪连续性。

## 相关节点

- [C1 文本到动作/表情路由](./C1-text-to-action-routing.md) — 表情路由的输入端
- [C7 实时语音与听觉](./C7-real-time-voice.md) — 语音驱动口型同步
- [C9 角色生活感](./C9-life-authenticity.md) — 微行为层的表情管理

> 相关文档：[C 分支总览](./README.md)
