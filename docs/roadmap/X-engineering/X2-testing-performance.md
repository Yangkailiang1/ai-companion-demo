# X2. 测试和性能

> 所属分支：X. 横向工程能力
> 节点编号：X2
> 状态：`[ACTIVE]`
> 依赖：T4（工程底座）
> 最后更新：2026-07-24 | 基线程：v0.7

## 当前状态

现有 headless 合同测试。

## 后续方向

### 测试体系

- 保留现有 headless 合同测试并增加视觉基准截图
- 新模型导入必须通过朝向、比例、T Pose、骨骼、动画和材质检查

### 压力测试

- 建立多 Agent 压力测试：2、10、30 个离屏/在屏 Agent

### 延迟监控

- 记录 AI、路由、TTS、导航、动画和场景加载延迟

## 相关节点

- [T4 工程底座](../T-runtime/T4-engineering-foundation.md) — 测试和性能预算
- [O1 Runtime 插件化](../O-opensource/O1-runtime-plugin.md) — 开源需要完善的测试

> 相关文档：[X 分支总览](./README.md)
