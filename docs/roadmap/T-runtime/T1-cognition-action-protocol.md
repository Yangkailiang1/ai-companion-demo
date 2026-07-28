# T1. 认知与动作协议

> 所属分支：T. Runtime 主干
> 节点编号：T1
> 状态：`[ACTIVE]`
> 依赖：无（基础协议）
> 最后更新：2026-07-24 | 基线程：v0.7

## 当前基础

- `MessageBus → CognitiveCycle → GOAPPlanner → ActionExecutor → AgentBase` 已可运行。
- LLM 可以返回 `goal`、`gesture`、`motion_query`、`expression_query` 和受限 `plan`。
- 本地规则与本地路由模型可在 LLM 不可用时降级运行。

## 规划节点

### T1.1 `[NEXT]` 统一 PerformanceIntent

将动作结果统一为结构化 `PerformanceIntent`：动作、表情、视线、速度、强度、目标物体、持续时间。

### T1.2 `[NEXT]` 动作中断与优先级

为动作增加中断、优先级、互斥组和恢复策略，防止说话、走路、挥手相互抢占。

### T1.3 `[LATER]` 层级计划

支持层级计划：长期目标、日程、短期行为和即时反应。

### T1.4 `[LATER]` 可解释决策日志

增加可解释决策日志，让开发者看到"为什么选择这个动作"。

### T1.5 `[DONE prototype]` LangGraph 认知图

建立 LangGraph 兼容 AgentState 与共享认知图；按 `thread_id=agent:<agent_id>` 隔离角色 checkpoint，Godot 保持物理执行权。

## 目标指标

- 路由 P95 延迟 < 100 ms（本地）或 < 350 ms（远端 embedding）
- 常用动作 Top-1 准确率 > 90%（可维护测试集）

## 相关节点

- [C1 文本到动作/表情路由](../C-characters/C1-text-to-action-routing.md) — 动作路由的具体实现
- [C9 角色生活感](../C-characters/C9-life-authenticity.md) — 基于本协议的效用决策与行为连续性
- [T3 插件接口](./T3-plugin-interface.md) — 允许扩展提供自定义 Action

> 相关文档：[T 分支总览](./README.md) · [统一完成标准](../102-completion-standards.md)
