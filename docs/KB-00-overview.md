# KB-00: 知识库总索引

> AI Companion Demo — Living Agent Runtime 知识库

## 导航

| 文件 | 内容 | 行数 |
|------|------|------|
| [KB-01 系统架构](./KB-01-architecture.md) | Autoload 依赖图、数据流、设计来源 | ~60 |
| [KB-02 论文引用](./KB-02-papers.md) | 10 篇核心论文与设计决策映射 | ~80 |
| [KB-03 实现细节](./KB-03-implementation.md) | 各模块关键实现、数据结构、协议 | ~80 |

## 关键概念速查

| 概念 | 含义 | 详见 |
|------|------|------|
| Semantic World | AI 看世界的方式 — 不是像素，是 JSON→自然语言 | KB-01 |
| GOAP | Goal-Oriented Action Planning: LLM 输出 Goal，GOAP 分解 | KB-03 |
| Codified Profile | 角色逻辑编译为可执行函数 [CCL] | KB-03 |
| Memory Stream | 短期 + 长期 + 反思 三层记忆 [GA] | KB-03 |
| Message Bus | 统一事件总线，等权处理 Simulation / Player / Agent 事件 | KB-01 |
| Action-Dialogue Decoupling | LLM 只负责自然语言，行为执行本地化 [CAS] | KB-01 |

## 文件组织

```
ai_companion_demo/
├── CLAUDE.md              ← 主开发进展
├── docs/                  ← 知识库
│   ├── KB-00-overview.md
│   ├── KB-01-architecture.md
│   ├── KB-02-papers.md
│   └── KB-03-implementation.md
├── scripts/
│   ├── core/              ← Autoload 系统
│   ├── characters/        ← Agent 节点脚本
│   ├── objects/           ← 物体交互
│   └── ui/                ← UI 组件
├── scenes/                ← .tscn 场景
└── data/                  ← 配置文件（llm_config 已 gitignore）
```
