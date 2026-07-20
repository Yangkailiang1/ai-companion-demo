# Claude Code task: v0.1 playable vertical slice

你现在在一个 Godot 4.6.1 项目中。请直接检查并实现一个“可运行的 v0.1 垂直切片”，不要只给建议。

项目目标的最高优先级来源是 `CLAUDE.md`、`docs/KB-*.md`，以及上级目录的 `../设计方案/AI养成陪伴游戏_设计方案.md`。请先完整阅读这些文件，再检查 `project.godot`、所有 scenes 和 scripts。

## 已知问题与约束

1. `scripts/ui/chat_input.gd:39` 的函数只有注释，Godot 报 `Expected indented block`。
2. `living_room.tscn` 中多处 `Transform3D` 基矩阵奇异，Godot 报 `det == 0`。
3. 目前运行效果只是日志/聊天文字占屏，输入体验和场景呈现不合格。
4. git worktree 已有未提交修改，这些是用户的工作。必须保留并在现状上谨慎修改，不要 reset、checkout 或 commit。
5. `data/.env` 和 `data/llm_config.json` 可能含密钥，禁止读取、打印或修改。

## 交付要求

- 修复所有 GDScript 解析错误、场景资源错误和明显运行时错误。
- 将主场景编排成清晰的演示结构：WorldRoot（3D 世界）、Agent、UI（CanvasLayer）、聊天面板、基础状态 HUD/提示。聊天记录不能覆盖整个画面，输入框和发送按钮必须可操作。没有外部资产时用 Godot primitive mesh 做一个整洁、可辨认的灰盒客厅。
- 保持 Living Agent Runtime 与 Demo 表现层分离：Runtime 负责事件、认知、记忆、规划、执行；Demo 负责场景、角色表现和 UI。避免继续增加全局 Autoload，只让真正跨场景的服务留在 Autoload。
- 优先完成稳定闭环：玩家输入 -> UI 显示 -> MessageBus -> CognitiveCycle（无 LLM 配置时可靠 fallback）-> agent speech/bubble -> 行为队列。自主事件不能疯狂刷屏，调试日志应有限且不占 UI。
- 导航在没有 NavMesh 时也不能卡死；可以提供安全 fallback。不要依赖任何新外部模型或插件。
- 新增 `docs/PROJECT_ARCHITECTURE.md`，说明目标结构、模块职责、数据流、场景树、阶段路线图、后续资产接入点。
- 新增 `docs/ASSET_REQUIREMENTS.md`，列出建议由用户寻找的角色、动画、环境、UI、音频资产，并按 P0/P1/P2 标优先级和技术规格。
- 更新 `CLAUDE.md`，使其真实反映状态和下一步，不要把未经验证的模块标为 done。
- 使用 `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path . --quit` 验证；然后用 headless 运行主场景做短时 smoke test，修到无项目级 parse/resource/runtime error。macOS 证书或 editor settings 写权限类环境噪声可记录，但不要误判为项目错误。
- 最后输出：修改文件清单、验证命令和结果、仍需用户提供的资产、已知限制。

请直接编辑文件并验证。
