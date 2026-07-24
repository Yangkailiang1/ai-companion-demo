# 拟人化 Agent 研究映射

> 依据：`../调研/AI拟人化游戏行为研究_论文综述_2024-2026.md`  
> 实现基线：2026-07-24

## 本轮采用的设计

| 调研方向 | 项目实现 | 当前边界 |
|---|---|---|
| Generative Agents：感知、记忆、反思、规划 | 已有 SemanticWorld、独立 Memory、CognitiveCycle、GOAP；新增统一认知图状态 | Reflection 仍待正式实现 |
| PANDA / 人格驱动策略 | OCEAN 大五人格和动机共同调制 Utility AI | 参数为设计配置，尚未用玩家数据训练 |
| Dual-Memory Sentiment / 动态情绪 | 每角色独立 valence/arousal，事件改变、随后回归人格基线 | 尚未加入长期情绪趋势总结 |
| ToM-agent / 心智理论 | 观察另一角色活动，保存“推测意图 + 置信度”，明确不是事实 | 目前只依据可见活动，不推断复杂错误信念 |
| Act-LLM / 规划仲裁 | Utility 候选、人格调制、重复厌倦、GOAP 验证、玩家抢占 | 日计划和中断后恢复尚待实现 |
| CASCADE / 标签化 NPC | LLM 与物理执行解耦；本地规则负责快速日常行为 | 尚未建立世界级 Macro Director |
| Codifying Character Logic | 身份规则、人格参数、活动偏好均为结构化配置 | 后续需要角色导入向导生成/校验配置 |
| 混合架构 | LangGraph/LLM 负责慢认知；Godot 负责导航、碰撞、动作和状态 | 外部 LangGraph 尚未接入游戏进程 |

## 当前两个角色的差异

咕咕嘎嘎：

- 更高外向性、亲和性和联结动机；
- 更倾向照顾植物、走动和主动回应；
- 基线唤醒度更高，身体表现更活泼。

诀：

- 更高开放性、尽责性、好奇心和自主性；
- 更倾向阅读和安静活动；
- 基线唤醒度较低，表达更克制。

角色差异不是只写在提示词里。OCEAN、动机、持续心境、近期活动和需求都会
进入 Utility 分数，心理状态也会进入 LLM 上下文。

## 已实现的可见拟人化

- 玩家点名某角色时，该角色立即把注意转向玩家并产生轻微动作/表情；
- 角色开始活动前形成当前意图，并平滑朝向目标；
- 另一角色能注意行动者，并保存带置信度的意图推测；
- 完成活动会改变心境，心境随后缓慢回到各自人格基线；
- 刚做过的活动会出现厌倦惩罚，减少机械重复；
- 私密想法与公开发言分离，私密状态不会自动显示为对白；
- 心境、意图、注意、信念和近期活动进入版本化存档。

## LangGraph 结论

不是为每个角色复制一套图，而是：

```text
共享认知图 + agent_id 配置 + 独立 thread/checkpoint + 独立长期记忆 namespace
```

`cognition_lab/agent_graph.py` 已验证同一张 LangGraph 能同时承载两个角色：

- `agent:main_agent` 在缺水世界状态下选择照顾植物；
- `agent:jue_agent` 在正常环境中因高好奇动机选择阅读；
- 两个 thread 的检查点状态相互隔离。

详细边界见 `docs/LANGGRAPH_AGENT_RUNTIME.md`。

## 后续研究实现顺序

1. Reflection：按重要性阈值总结近期活动、关系与情绪变化。
2. 日计划：长期目标 → 当日计划 → 当前活动，并支持玩家打断后恢复。
3. 更完整的 ToM：角色所见范围、信息来源、错误信念和反事实修正。
4. 社交共同活动：邀请、接受/拒绝、等待、座位预约和自然结束。
5. 本地 LangGraph 进程桥：SQLite checkpoint、超时、降级和存档迁移。
6. 最后才评估模仿学习/强化学习；客厅日常行为暂不需要 PPO/GAIL。

## 验收

```bash
python3 cognition_lab/smoke_test.py

/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/agent_psyche_check.gd
```
