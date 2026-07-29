# O2/C2/C3/C6 — 资产元数据合同测试（小任务）

只完成一个小任务：新增一个 Python unittest，验证当前资产批次的机器可读合同。
不要修改模型、场景、Runtime、现有资产元数据或 Git。

## 必读

- `CLAUDE.md`
- `docs/ASSET_PIPELINE_CONTRACTS.md`
- `docs/handoffs/2026-07-29-deepseek-codex-asset-batch-handoff.md`
- `.claude/skills/prepare-character-model-assets/SKILL.md`
- `.claude/skills/prepare-expression-library-assets/SKILL.md`
- `.claude/skills/prepare-motion-library-assets/SKILL.md`

## 唯一允许新增

`tools/assets/test_asset_metadata_contracts.py`

使用标准库 `unittest`，不得增加依赖。文件和每个函数遵守 `CLAUDE.md` 的 Roadmap
注释、类型和长度规范。

## 必须覆盖

1. `assets/characters/penguin/provenance.json`：
   - `license` 不能是 `Project-authored`；
   - `redistribution` 必须为 `local_only`；
   - 不能包含 `your-org` 占位 URL。
2. 三个本地角色：
   - 从 ignored 的 `morph_inventory.json` 计算 unique morph name；
   - 结果必须分别为 cartethyia=69、castorice=37、xiangliyao=70；
   - 测试缺少本机受限角色时应 skip，而不是失败，保证公开 checkout 可运行。
3. 三个 `expression_adapter.candidate.json`：
   - `status == candidate`；
   - `has_runtime_regressions == false`；
   - `channel_map_patch` 不能把同角色现有 `character_manifest.json` 已映射的非空语义
     降级或删除；
   - 缺少本机角色时 skip。
4. `motion_lab/generated/library/smoke_walk/motion_package.json`：
   - 文本/源路径表明它是 fixture；
   - 若 `motion_lab/generated/motion_library_manifest.json` 存在，smoke_walk 状态必须
     是 `pipeline_smoke_test`，不能是 `accepted`/`validated`；
   - ignored 产物缺失时 skip。
5. `assets/props/polyhaven/polyhaven_manifest.json` 和厨房 Registry：
   - 所有 `entry`/`resource_path` 均为 `res://`，不能含 `/Users/` 或 `/private/tmp/`；
   - 三个厨房候选状态只能是 `previewed`，不能是 `accepted`；
   - reviewed geometry 必须为正数且 source SHA-256 非空。

## 验收

运行：

```bash
python3 -m py_compile tools/assets/test_asset_metadata_contracts.py
python3 -m unittest tools.assets.test_asset_metadata_contracts -v
git diff --check
```

最终仅报告新增文件、测试结果和 skip 数。不要提交或推送 Git。
