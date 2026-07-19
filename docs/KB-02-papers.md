# KB-02: 论文引用与设计决策映射

## 引用索引

| 标记 | 论文 | 来源 |
|------|------|------|
| **[GA]** | Generative Agents: Interactive Simulacra of Human Behavior (Park et al., 2023) | UIST 2023 |
| **[CAS]** | CASCADE: A Cascading Architecture for Social Coordination (Xu, 2026) | CHI EA 2026 |
| **[CCL]** | Codifying Character Logic in Role-Playing (Peng & Shang, 2025) | NeurIPS 2025 |
| **[CH]** | The Many Challenges of Human-Like Agents (Świechowski & Ślęzak, 2025) | AAMAS 2025 |
| **[SOL]** | SOLAMI: Social VLA for 3D Autonomous Characters (Jiang et al., 2025) | CVPR 2025 |

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

## 关键发现备忘

- **[GA]** 消融实验：Observation/Planning/Reflection 缺一不可。最常错：检索失败、虚构记忆、语体过正式
- **[CCL]** 段落级(paragraph)分段最优；蒸馏分类器(0.1B)达 70.53% 一致性
- **[CCL]** 1B 模型 + Codified = 8B 模型 + Prompt
- **[CAS]** Token 成本：CASCADE 比每 Agent 调 LLM 低几个数量级
- **[SOL]** 数字人=具身机器人；VLA 延迟 <3s（2 H800）
- **[CH]** 13 大挑战：action-space complexity, superhuman behavior, human diversity 等
