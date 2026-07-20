# Claude Code task: v0.2 character model and action pipeline

在现有 Godot 4.6.1 项目上直接实现。先阅读 `CLAUDE.md`、`docs/PROJECT_ARCHITECTURE.md` 和相关脚本。保留所有未提交工作，不要 reset、checkout 或 commit。禁止读取或修改 `data/.env`、`data/llm_config.json`。

## 外部资产

- 首选角色：`/Users/yangkailiang/Documents/ai_games/model/终末地小企鹅.zip`
- 备选高质量人形：`/Users/yangkailiang/Documents/ai_games/model/诀.7z`
- 备选环境：`/Users/yangkailiang/Documents/ai_games/scene/终幕喑哑之庭.zip`
- Blender：`/Applications/Blender.app/Contents/MacOS/Blender`
- Godot：`/Applications/Godot.app/Contents/MacOS/Godot`

已完成审计：

- 小企鹅 `.blend/.vrm`：约 1.21m，64 bones，18 meshes，脸部 Shape Keys；现有 Action 基本都是单帧 pose，没有可播放身体动作。
- 小企鹅完整主骨骼命名：`root, hips, spine, chest, neck, head, shoulder.L/R, upper_arm.L/R, lower_arm.L/R, hand.L/R, upper_leg.L/R, lower_leg.L/R, foot.L/R, toes.L/R`；另有 `eye.L/R`、35 根 hair bones、ring 和 hips.001-.004。
- “诀”校验版：约 1.793m，72,680 vertices，84,352 polygons，407 bones，41 Shape Keys，无身体动画；复杂装饰/长袖，不作为本轮主角色。
- “终幕喑哑之庭”：约 195m 范围，21 meshes、38 curves、17 materials；4 个 alpha 材质需调整。它是独立幻想庭院，不是客厅替代品。
- 资产许可证未确认，只能标记为 private prototype，不得声称可商用。

## 本轮目标

### A. Blender 资产管线

1. 安全解压/使用小企鹅源文件，编写可复现的 Blender Python 导出脚本，放在 `tools/blender/`。
2. 清理展示用 camera/light/helper，只导出角色 armature、skinned meshes、材质、贴图和需要的 Shape Keys。
3. 根据实际骨骼名生成或整理至少以下 in-place 动画：
   - `idle` loop
   - `walk` loop
   - `wave`
   - `nod`
   - `think`
   - `happy`
   - `sit`（如果骨骼允许）
4. 动画必须能在 Godot `AnimationPlayer` 中被识别；角色移动仍由 `AgentBase` 控制，Walk 不带 root motion。
5. 导出到 `assets/characters/penguin/`，不要把重复的 `.blend1` 或原始大包复制进项目。

### B. Godot 通用表现层

1. 用小企鹅替换当前 Capsule/Sphere 灰盒，但保留胶囊碰撞、姓名、对话气泡、导航和安全 fallback。
2. 建立独立的角色表现适配器，例如 `CharacterAnimationDriver`，不要让 CognitiveCycle 直接操作 AnimationPlayer。
3. 建立统一 performance cue 信号/协议：`idle`, `walk`, `wave`, `nod`, `think`, `happy`, `sit`, `talk`。
4. `AgentBase` 根据移动状态切换 idle/walk；`ActionExecutor` 根据 primitive/interaction 发 cue；情绪/对话可以触发 happy/think/talk。
5. LLM JSON schema 增加受限字段 `gesture`，只允许上述 enum。Runtime 必须校验未知 gesture。
6. 本地 fallback 支持明确测试句：
   - “挥挥手” → `wave`
   - “点点头” → `nod`
   - “想一想” → `think`
   - “开心一点” → `happy`
7. 玩家输入在 AI 忙时仍使用现有 FIFO，不得回归为丢消息。

### C. 幻想庭院场景

1. 将 `终幕喑哑之庭` 通过可复现 Blender 脚本导出为 Godot 可导入 GLB。
2. 新增独立 preview scene，例如 `scenes/environments/endless_garden_preview.tscn`；不要替换当前客厅主场景。
3. 修复或记录 4 个透明材质问题；设置合理 camera/light/world environment。
4. 本轮不要求为 195m 场景烘焙完整 NavMesh，但需记录后续导航方案。

### D. 文档与验收

1. 新增 `docs/CHARACTER_ACTION_PIPELINE.md`，说明：
   `Player text → Cognitive decision/gesture → validated performance cue → CharacterAnimationDriver → AnimationPlayer/AnimationTree`。
2. 新增 `docs/ASSET_PROVENANCE.md`，记录三个资产来源路径、技术信息及 `license: unknown/private prototype only`。
3. 更新 `CLAUDE.md` 的真实进度和限制。
4. 使用 Godot headless editor 验证无 parse/resource error。
5. 建立 smoke test：强制本地模式，从 UI 输入“挥挥手”，断言 cue=`wave` 且 AnimationPlayer 正在播放对应动画；输入“我们一起看电视”，仍断言 goal/action 目标为 TV。
6. 图形模式截取至少一张 1280×720 主场景截图，确认小企鹅可见、材质正常、不是 Capsule。
7. 如果环境 preview 可运行，再截一张场景图。

最后报告修改清单、导出结果、动画列表、验证命令/结果、已知限制。直接编辑并验证，不要只给建议。

## 当前执行方式补充

本次 Claude 会话不提供 Bash 工具。请完成 Blender Python 导出/动作生成脚本、Godot 代码、场景引用、smoke test 脚本和文档；不要因为不能执行 Blender/Godot 而停下。主控会在你完成编辑后亲自运行导出与验收，并修正 API 差异。报告中将未执行的验证明确标为 `pending main-agent execution`，不要虚构通过结果。
