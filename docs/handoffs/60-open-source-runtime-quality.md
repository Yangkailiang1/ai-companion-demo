# H60 — 开源 Runtime 与质量工程

> 路线图：T3.1-T3.2、O1、O4、X2、X5
> 建议分支：`feature/o1-runtime-quality`
> 目标：让公开仓库可以被第三方安全检出、测试、扩展和贡献

## 文件所有权

允许主要修改：

- 新增 `addons/living_agent_runtime/**`
- 新增 `.github/**`
- `tools/**` 中的校验/发布工具
- `scripts/debug/**` 的发布/性能测试
- `docs/**`、`README.md`
- `.gitignore`
- 配置 schema 和公开 example

禁止修改玩家可见行为：

- 不改认知 Prompt；
- 不改自主生活评分；
- 不改剧情内容；
- 不改动作表现；
- 不把现有 Runtime 全量搬目录后留下大量断链。

先定义边界与兼容 facade，再渐进提取插件。

## 必须实现

### A. 公开仓库治理 O4

1. 由项目所有者选择代码许可证后添加 `LICENSE`；Agent 不得擅自选择。
2. 添加：
   - `CONTRIBUTING.md`
   - `CODE_OF_CONDUCT.md`
   - `SECURITY.md`
   - Issue/PR 模板
3. 资产来源检查：
   - 公开树禁止 `assets/local_characters/`；
   - 禁止许可证不明模型、原包和受限截图；
   - 新资产必须有 provenance、license、source URL/hash。
4. 密钥扫描覆盖 Git tracked tree 和待提交 diff。
5. README 明确公开版与本地可选资产的差异。

### B. 插件 Manifest 与生命周期 T3

定义 versioned manifest，至少包含：

- plugin ID/version/runtime compatibility；
- adapters：character/scene/motion/expression/voice；
- capabilities 和依赖；
- 配置 schema；
- 资产许可证摘要；
- 初始化入口；
- 冲突和优先级。

实现注册、发现、重复 ID 拒绝、版本不兼容拒绝、初始化失败隔离和只读诊断。
第一阶段不实现安全沙箱，不得宣称第三方 GDScript 已隔离。

### C. Runtime 插件化 O1

1. 定义公共 API 列表、语义版本和弃用策略。
2. 建立最小示例：
   - 单 Agent；
   - 双 Agent；
   - 一个语义物体；
   - 一个固定 Story。
3. Demo 通过 facade 使用 Runtime；核心 Runtime 不反向依赖企鹅、诀、客厅或 ECNU。
4. 迁移必须分小步，每步保持主场景和现有测试通过。

### D. CI、公开检出与性能 X2/X5

CI 至少执行：

- JSON/schema 校验；
- GDScript 解析/主场景 headless；
- multi-agent、story、physics、save 合同；
- 无本地资产测试；
- 密钥和受限路径扫描；
- `git diff --check` 或格式检查。

增加基线指标：

- 主场景启动耗时；
- 2/10/30 Agent CPU 与内存；
- 路由、LLM、TTS、导航延迟分开统计；
- 无网络 fallback 时间；
- 测试日志作为 CI artifact，不包含 Key。

## 自动化验收

新增发布审计脚本，例如：

```bash
tools/release/audit_public_tree.sh
```

必须失败于：

- tracked `data/llm_config.json`；
- `ghp_` / 长 API Key 模式；
- `assets/local_characters/`；
- 未声明 provenance 的大型模型；
- 超过 GitHub 单文件限制；
- README 本地链接缺失。

必须通过：

```bash
godot --headless --path . --script scripts/debug/headless_check.gd
godot --headless --path . --script scripts/debug/multi_agent_check.gd
godot --headless --path . --script scripts/debug/story_director_check.gd
godot --headless --path . --script scripts/debug/physics_interaction_check.gd
godot --headless --path . --script scripts/debug/save_plant_state_check.gd
tools/release/audit_public_tree.sh
```

还必须在一个不含 `assets/local_characters/`、不含 `data/llm_config.json` 的临时检出中
运行核心测试，不能只在开发者缓存完整的工作区验收。

## 禁止的“伪插件化”

- 只把文件移动到 `addons/`，但仍硬编码 Demo 路径；
- 插件直接读写 Autoload 私有字段；
- 为每个角色复制一份认知循环；
- 用任意 Dictionary 代替 versioned schema；
- 发生错误时让整个项目启动失败；
- 声称拥有沙箱但实际加载任意 GDScript。

## 交付物

- 插件 manifest schema、loader 和诊断；
- 公共 API/兼容矩阵；
- 开源治理文件；
- CI 工作流与公开树审计脚本；
- 最小示例工程；
- 性能基线报告；
- 更新 T3/O1/O4/X2/X5 路线图。
