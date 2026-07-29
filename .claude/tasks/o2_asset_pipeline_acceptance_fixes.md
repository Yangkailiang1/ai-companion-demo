# O2/C2/C3/C6 — 资产流水线验收返工

你正在修复 2026-07-29 资产批处理的验收问题。执行者可以修改代码、文档和
`.claude/skills/`，但不得提交或推送 Git。

## 必读

- `CLAUDE.md`
- `docs/DEEPSEEK_ASSET_PIPELINE_HANDOFF.md`
- `docs/handoffs/2026-07-29-deepseek-codex-asset-batch-handoff.md`
- `docs/ASSET_PIPELINE_CONTRACTS.md`
- `docs/ASSET_PROVENANCE.md`
- `docs/roadmap/O-opensource/O2-import-tools.md`
- `docs/roadmap/C-characters/C2-motion-library-retargeting.md`
- `docs/roadmap/C-characters/C3-expression-body-language.md`
- `docs/roadmap/C-characters/C6-character-import.md`
- `.claude/skills/*/SKILL.md`

## 边界

- 保留用户和其他任务的所有现有改动。
- 不修改 `data/llm_config.json`、任何 `.uid`、Godot 核心 Runtime、场景、模型二进制
  或 Git 历史。
- 不下载新资产；只修复现有批次的工具、元数据、报告、测试和 Skill。
- `assets/local_characters/` 和 `motion_lab/generated/` 必须继续保持 Git ignored。
- 不把任何候选自动晋级为视觉 accepted。

## 必须修复

### 1. 许可证 fail-closed

`tools/assets/extract_penguin_metadata.py` 不得把企鹅声明为
`Project-authored / redistribution allowed`。现有人工来源记录为
`unknown / private prototype only`，因此生成的 provenance 必须保持
`local_only` 或等价的禁止公开再分发状态。

- 删除占位的 `github.com/your-org/...`。
- 未知许可不得由脚本自动提升。
- 在验证脚本/测试中增加断言：unknown/private 资产不能输出
  `redistribution=allowed`。

### 2. 场景规范化可重复且非破坏

修复 `tools/assets/normalize_kitchen_registry.py` 的大小写目录错误：
manifest 中 `WoodenTable_01`/`WoodenChair_01` 是源 ID，公开目录 ID 才是小写。

- 源 ID 和规范化 ID 必须分开。
- 完整验证源目录、GLTF 和 provenance 后，才能替换目标。
- 不得先 `rmtree(target)` 再尝试读取可能不存在的源。
- 使用任务临时目录复制并原子替换，或实现等价的可恢复机制。
- 连续运行两次必须得到相同输出和哈希。
- 不得把 `/Users/...`、`/private/tmp/...` 等机器路径写入公开 manifest。

### 3. 状态语义准确

下载完成只能是 `downloaded`/`quarantined`，Registry 当前只能是
`inventoried`。在 AABB、轴向、Metal 预览和 Codex 视觉验收前不得写
`accepted`。

- 修复三个 Poly Haven provenance 的状态。
- 花瓶应为 `decor`/`ceramic`，不能是 `static_furniture`/`wooden`。
- 修复交接报告的 accepted/quarantined/rejected 汇总；可以增加
  `metadata_validated` 或 `candidate`。
- 修复报告中的相对链接。

### 4. 人物统计与诀说明

- 区分 morph binding 总数和 unique morph name 数，不要把
  `2139/592/2030` 直接写成角色 Morph 数。
- 诀当前源是 FBX，Godot 已有本地 FBX fallback。若目标是标准化 GLB，写成
  FBX→GLB；不要写成当前不存在输入的 PMX→GLB。
- 企鹅、本地角色在视觉验收前只能是 inventory/metadata candidate。

### 5. 动作 fixture 不冒充真实 HumanML3D 样本

`smoke_walk` 来源是 `/private/tmp/hml_fixture.npy`，文本是 `fixture walk`。
它只能证明 retarget smoke path 可用：

- 在 manifest/报告中标为 `pipeline_smoke_test` 或等价状态。
- 明确真实 HumanML3D/Light-T2M 样本仍为 pending。
- 不把 ignored 的 `motion_lab/generated/motion_library_manifest.json` 当成可移交的
  tracked 项目产物；如需可复现摘要，放入允许跟踪的轻量 metadata 路径。

### 6. 表情候选不得覆盖现有能力

当前 Runtime 从角色 `character_manifest.json` 的
`adapter.expression_adapter.channel_map` 读取，不读取独立
`expression_adapter.json`。

- 将独立文件明确标为 candidate，不声称已接入 Runtime。
- 比较现有 manifest；不得把已经映射的 bored/confused 降级成 unsupported。
- 生成结构必须能明确转换成现有 manifest schema，或输出 machine-readable patch。
- 未完成真实 mesh weight、neutral reset 和截图前不得 accepted。

### 7. 将教训固化到 Skills

更新最小必要的 `.claude/skills/*/SKILL.md`，至少加入：

- 许可证只能保持或收紧，自动化不得从 unknown/local_only 晋级到 allowed。
- source ID 与 normalized ID 分离；批量脚本必须在临时目录验证后原子发布。
- accepted 必须满足对应视觉/runtime 验收，不能把脚本 exit 0 当 accepted。
- motion fixture 与真实数据动作分离。
- expression candidate 必须与当前 runtime manifest 做 non-regression 对比。

保持 Skill 精简，不创建 README/CHANGELOG 等旁支文档。

## 验收命令

至少执行并报告：

```bash
python3 -m py_compile \
  tools/assets/download_kitchen_models.py \
  tools/assets/normalize_kitchen_registry.py \
  tools/assets/extract_penguin_metadata.py \
  tools/assets/extract_local_character_metadata.py \
  tools/assets/create_expression_channel_maps.py

python3 .claude/skills/build-parametric-asset-library/scripts/validate_registry_batch.py \
  data/scene_generation/asset_registry_candidates/polyhaven_kitchen_batch_01.json \
  --project-root .

python3 motion_lab/scripts/validate_retarget_package.py \
  motion_lab/generated/library/smoke_walk

git diff --check
git status --short
```

此外新增或运行一个不触碰真实目标目录的测试，证明场景规范化连续执行两次：

- 不删除已存在输出；
- 两次输出哈希一致；
- 大小写源 ID 可正确解析；
- 缺失源时不会修改目标。

最终报告按实际状态列出：

1. 修复文件；
2. 测试和退出码；
3. 仍需 Codex 人工完成的许可证/视觉事项；
4. 不得声称提交 Git。
