# H00 — 通用执行规范

本规范适用于所有 Claude Code / DeepSeek 交接任务。目标不是输出建议，而是在当前
工作区直接实现、测试并交付可审查的改动。

## 1. 开始前必须阅读

1. 根目录 `CLAUDE.md`，尤其是路线图追溯、文件长度和模块边界。
2. 目标任务列出的 `docs/roadmap/` 节点。
3. `docs/PROJECT_ARCHITECTURE.md` 与相关专项文档。
4. 目标模块的现有测试，先理解已有合同再修改。

若任务文档与代码现状冲突，以“已通过的运行时合同 + 最新路线图节点”为准，并在
报告中记录冲突，不得静默删除现有能力。

## 2. 安全边界

- 禁止读取、打印、修改或提交：
  - `data/llm_config.json`
  - `data/.env`
  - GitHub Token、ECNU Key、聊天记录和语音样本
- 禁止提交：
  - `assets/local_characters/`
  - `motion_lab/checkpoints/`、数据集、生成权重
  - 许可证不明、禁止再分发或仅限本地非商业的模型和截图
- 不执行 `git reset --hard`、`git checkout -- <file>` 或清理整个工作树。
- 不修改与任务无关的用户文件，不自动 push，不强推远端。
- 网络依赖必须是可选能力；无网络、无 Key 时项目仍应启动并明确降级。

## 3. 工程规则

- 每个新增/修改函数必须在声明前标注真实路线图编号。
- 新文件头必须声明 Roadmap、Responsibility、Collaborators、Tests。
- Runtime/角色/UI 文件目标不超过 300 行，硬上限 400 行。
- Autoload 硬上限 500 行；测试硬上限 250 行；单函数硬上限 60 行。
- 当前超限文件不得继续增长：
  - `autonomous_behavior_system.gd`：约 532 行
  - `agent_psyche_system.gd`：约 452 行
  - `story_director.gd`：约 440 行
- 修改超限文件时先提取一个有明确职责的模块，再添加功能。
- LLM 只能返回结构化候选，不能直接修改坐标、碰撞、库存、物体状态或存档。
- UI 不得直接读取 Autoload 私有字段。
- 所有异步流程必须具备 timeout、取消 epoch 和过期结果保护。

## 4. Git 工作方式

开始时记录：

```bash
git status --short
git branch --show-current
git log -1 --oneline
```

执行期间：

- 保留任务开始前的所有未跟踪文件和修改；
- 每份任务只修改声明的“拥有文件”；
- 如果必须跨边界，先在报告中列出，不要顺手重构；
- 默认不提交、不推送；主控明确要求提交时，提交信息必须包含路线图编号。

建议提交格式：

```text
feat(C4.4,S3.3): align carried props with interaction anchors
fix(D2.2): cancel stale parallel story beats
refactor(C9.3): extract autonomous activity runtime
```

## 5. 公共回归

所有方向至少运行：

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --log-file /private/tmp/handoff_headless.log \
  --path . --script scripts/debug/headless_check.gd

/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --log-file /private/tmp/handoff_multi_agent.log \
  --path . --script scripts/debug/multi_agent_check.gd

git diff --check
```

若 Godot 报 macOS CA、editor settings 或退出时 ObjectDB leak，但目标测试退出码为 0，
应作为环境噪声记录；不得用它掩盖 GDScript、资源或断言错误。

## 6. 无本地资产验收

涉及角色、场景、README 或开源发布时，必须临时隐藏整个
`assets/local_characters/`，运行 `headless_check.gd` 和目标合同测试，随后无论成功
失败都恢复目录。不得删除或提交该目录。

公开检出必须满足：

- 主场景可加载；
- 本地角色缺失时安全跳过或显示无第三方内容的占位外观；
- 核心 Agent、剧情和存档合同不依赖受限模型文件；
- 日志不得连续刷出资源错误。

## 7. 最终报告模板

```text
任务：
路线图节点：
修改文件：
新增合同：
测试命令与退出码：
视觉验收：
失败/降级路径：
行数与函数数：
未解决风险：
没有读取或提交密钥/受限资产：是/否
建议主控重点审查：
```

不得把“代码看起来正确”“无法运行所以推测通过”写成验收通过。
