# KB-02: 论文引用与设计决策映射

> 最后更新：2026-07-27
>
> 论文根目录：`../调研/论文/`

## 引用索引

| 标记 | 论文 | 来源 |
|------|------|------|
| **[GA]** | Generative Agents: Interactive Simulacra of Human Behavior (Park et al., 2023) | UIST 2023 |
| **[CAS]** | CASCADE: A Cascading Architecture for Social Coordination (Xu, 2026) | CHI EA 2026 |
| **[CCL]** | Codifying Character Logic in Role-Playing (Peng & Shang, 2025) | NeurIPS 2025 |
| **[CH]** | The Many Challenges of Human-Like Agents (Świechowski & Ślęzak, 2025) | AAMAS 2025 |
| **[SOL]** | SOLAMI: Social VLA for 3D Autonomous Characters (Jiang et al., 2025) | CVPR 2025 |
| **[LAMP]** | LaMP: Language-Motion Pretraining | 轻量 ML 与动作检索调研 |
| **[D2A]** | Simulating Human-like Daily Activities with Desire-driven Autonomy | 世界模拟与环境建模调研 |
| **[IBSEN]** | Director-Actor Agent Collaboration for Controllable Interactive Drama | 剧情与导演系统调研 |
| **[HAMLET]** | Hierarchical and Adaptive Multi-Agent Framework for Live Embodied Theatrics | 剧情与导演系统调研 |
| **[SCENEX]** | SceneX: LLM-driven Large-scale Procedural Scene Generation | 参数化场景调研 |
| **[ROOMPLANNER]** | Hierarchical LLM Room Generation | 参数化场景调研 |
| **[INTERCONTROL]** | Zero-shot Interaction by Controlling Every Joint | 实时交互与轻量化调研 |
| **[ENV-MM]** | Environment-aware Motion Matching | 实时交互与轻量化调研 |

## 研究目录到规划树的映射

| 研究目录 | 主要路线图节点 | 当前使用方式 |
|---|---|---|
| `01_AI拟人化行为与认知架构/` | C5、C9、T1.5、R5 | 记忆、反思、人格、ToM、共享 Agent 图 |
| `02_VLA模型与实时动作生成/` | C1、C2、C3、R5 | 动作检索、实时生成与 VLA 远期边界 |
| `03_世界模型/` | R1、R2、R3 | 研究储备，不直接控制 Godot 物理状态 |
| `04_参数化场景与模型生成/` | S4、R1 | 约束式房间/街区生成 |
| `05_实时交互与轻量化/` | C2、C3、C4、X2 | 重定向、IK、环境感知动画和 LOD |
| `06_剧情与导演系统/` | D1–D4 | Director/Actor 分层与剧本约束 |
| `07_轻量ML推理与边缘部署/` | C1.2–C1.4、X3 | Embedding 检索、轻量分类器和 ONNX |
| `08_世界模拟与环境建模/` | S5、C5.6、C9、R2–R3 | 日常活动、离屏模拟和环境状态 |

## 代码引用规则

- 代码首先引用路线图节点，例如 `[C5.1]`；论文只解释算法依据，不能替代需求。
- 只有确实实现或验证了论文中的方法时才写 `Research: [TAG]`。
- 若只是启发而非复现，写 `Research inspiration: [TAG]`，不得暗示复现论文指标。
- 新论文在进入代码注释前，先在本文件注册稳定标记和来源。
- 论文 PDF/翻译文档位于项目仓库外，不把 PDF、API Key 或论文全文复制进代码仓库。

## 设计决策 → 论文映射

| 设计决策 | 依据 | 实现位置 |
|---------|------|---------|
| 语义世界（AI 不看像素） | [GA §4.1] Perception 转自然语言 | `semantic_world.gd` |
| 记忆检索加权公式 | [GA §4.2.2] α·recency+β·importance+γ·relevance | `memory_system.gd:retrieve_relevant()` |
| 分层调用（LLM 非每帧调用） | [CAS §3] 三层架构 | `cognitive_cycle.gd` 事件驱动 |
| Action-Dialogue 解耦 | [CAS §3.4] 行为本地执行 | GOAP + ActionExecutor 本地 |
| Codified Profile | [CCL §3.2] parse_by_scene + check_condition | `codified_profile.gd` |
| 1B 模型即可高质量扮演 | [CCL §5.4] 关键发现 | 预留方案B |
| Agent 自主生活 | [GA §3.3] Day in the Life | IdleTimer + Sim triggers |
| Object Affordance | [CH] action-space complexity | `semantic_world.gd` affordance 表 |
| GOAP 规划 | [GA §4.4] 规划系统 | `goap_planner.gd` |
| VLA 预留（端到端社交） | [SOL §3.1] 数字人=VLA机器人 | 后续版本 |
| 文本到动作的轻量检索 | [LAMP] 跨模态动作检索 | `motion_intent_router.gd`, `motion_lab/router_training/` |
| 需求驱动的日常活动 | [D2A] desire-driven autonomy | `autonomous_behavior_system.gd` |
| Director / Actor 分层 | [IBSEN]、[HAMLET] | D1–D3 规划节点，尚未进入 Runtime |

## 关键发现备忘

- **[GA]** 消融实验：Observation/Planning/Reflection 缺一不可。最常错：检索失败、虚构记忆、语体过正式
- **[CCL]** 段落级(paragraph)分段最优；蒸馏分类器(0.1B)达 70.53% 一致性
- **[CCL]** 1B 模型 + Codified = 8B 模型 + Prompt
- **[CAS]** Token 成本：CASCADE 比每 Agent 调 LLM 低几个数量级
- **[SOL]** 数字人=具身机器人；VLA 延迟 <3s（2 H800）
- **[CH]** 13 大挑战：action-space complexity, superhuman behavior, human diversity 等
