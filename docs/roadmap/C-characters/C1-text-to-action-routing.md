# C1. 文本到动作/表情路由

> 所属分支：C. AI 角色
> 节点编号：C1
> 状态：`[ACTIVE]`
> 依赖：T1（PerformanceIntent 协议）
> 最后更新：2026-07-24 | 基线程：v0.7

## 当前链路

```
玩家输入
  -> LLM 输出 gesture / motion_query / expression_query
  -> 高置信场景规则
  -> 本地 hash n-gram 质心路由
  -> action_id / expression payload
  -> 角色适配器
```

并非所有动作都来自 LLM：导航状态机、GOAP、ActionExecutor 和自主需求也可以直接触发动作。

## 规划节点

### C1.1 `[NEXT]` 路由日志与数据集

记录 query、候选、分数、最终动作和人工评价，建立真实交互数据集。

### C1.2 `[NEXT]` Embedding 接入

把 ECNU embedding 接入可选本地后端；动作库 embedding 离线缓存，运行时只计算查询向量。

### C1.3 `[NEXT]` 轻量路由器训练

训练轻量双头/多头路由器：动作类别、表情混合、强度、目标和是否需要移动。

### C1.4 `[LATER]` 本地 ONNX 推理

本地 ONNX/小模型推理，网络不可用时仍能低延迟匹配。

### C1.5 `[LATER]` 上下文融合

融合上下文：角色当前姿势、手中物体、距离、情绪和动作冷却。

## 目标指标

| 指标 | 目标 |
|------|------|
| 路由 P95 延迟 | < 100 ms（本地）/ < 350 ms（远端 embedding） |
| 常用动作 Top-1 准确率 | > 90%（可维护测试集） |

## 相关节点

- [T1 认知与动作协议](../T-runtime/T1-cognition-action-protocol.md) — 统一 PerformanceIntent 格式
- [C2 动作库与骨骼重定向](./C2-motion-library-retargeting.md) — 动作库的检索与匹配
- [C3 表情和身体语言](./C3-expression-body-language.md) — 表情路由的并行链路

> 相关文档：[C 分支总览](./README.md) · [统一完成标准](../102-completion-standards.md)
