# O1. Runtime 插件化

> 所属分支：O. 开源与创作者生态
> 节点编号：O1
> 状态：`[NEXT]`
> 依赖：T3（插件接口）、X1（迁移）、X2（测试）
> 最后更新：2026-07-24 | 基线程：v0.7

## 规划方向

### 分层

- 将 `Living Agent Runtime` 与 Demo 资产彻底分层

### 语义版本

- 定义语义版本、弃用周期和插件兼容矩阵

### 示例工程

- 提供最小 Godot 示例：单 Agent、双 Agent、交互物体、剧情导演

## 依赖关系

```
T3 插件接口 + X1 迁移 + X2 测试 ──> O1 开源 Runtime
```

## 相关节点

- [T3 插件接口](../T-runtime/T3-plugin-interface.md) — 插件的接口定义
- [X2 测试和性能](../X-engineering/X2-testing-performance.md) — 开源需保证测试覆盖
- [O4 开源治理与安全](./O4-governance-security.md) — 同时推进的安全工作

> 相关文档：[O 分支总览](./README.md)
