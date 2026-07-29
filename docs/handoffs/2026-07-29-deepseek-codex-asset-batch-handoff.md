# DeepSeek → Codex 资产批处理交接报告

> 日期：2026-07-29
> 执行者：Claude Code (DeepSeek V4 Pro)
> 当前状态：四条流水线已执行完毕，候选文件和验收报告就绪，**未提交 Git**。

## 执行边界

按 [DEEPSEEK_ASSET_PIPELINE_HANDOFF.md](../DEEPSEEK_ASSET_PIPELINE_HANDOFF.md)
要求，四条流水线独立执行，每批不混做资产类别。Codex 拥有许可证终审、视觉验收、
目录晋级、路线图状态、提交和推送的最终决定权。

---

## 批次 1：场景素材

### 执行摘要

```text
$download-open-3d-assets → $build-parametric-asset-library → (godot-import-interactable-object 跳过)
```

### previewed candidates（3 个）

| asset_id | 来源 | 许可证 | SHA-256 | 格式 | 面数 | 项目路径 |
|----------|------|--------|---------|------|------|---------|
| `woodentable_01` | [Poly Haven](https://polyhaven.com/a/WoodenTable_01) | CC0-1.0 | `413804e054055c397b4cfbd0916027097d2a20853b165b533007a46d131e1d17` | GLTF 1K | 952 | `assets/props/polyhaven/woodentable_01/` |
| `woodenchair_01` | [Poly Haven](https://polyhaven.com/a/WoodenChair_01) | CC0-1.0 | `d7139c63be77bb91ceb25cb38733008156bf93d2299a6ca4673ea3c49f5fdec6` | GLTF 1K | 19,992 | `assets/props/polyhaven/woodenchair_01/` |
| `ceramic_vase_01` | [Poly Haven](https://polyhaven.com/a/ceramic_vase_01) | CC0-1.0 | `4e2c69eb5bbccf86e9fbf92af438464669d804c1f0eae041ee28651a5b57d91e` | GLTF 1K | 10,296 | `assets/props/polyhaven/ceramic_vase_01/` |

> **注意**: 花瓶角色已修正为 `decor`/`ceramic`，非 `static_furniture`/`wooden`。Registry 候选中的 `roles.visual: "decor"`, `roles.placement: "surface"`, `style_tags: ["modern", "ceramic", "indoor"]`。

Codex 已在 Godot 4.6.1 Metal 中渲染并归档
[`polyhaven-kitchen-batch-01-preview.png`](../images/polyhaven-kitchen-batch-01-preview.png)，
三项模型的材质、比例、接触和阴影正常；AABB 与 +Y 上轴已记录。视觉同时确认
该批次并非同一风格：木桌是低矮
复古旧木桌，木椅是哥特/维多利亚高背椅，花瓶是现代白瓷，因此三项保持
`previewed` 候选，不作为一套 production 风格资产 `accepted`。

### quarantined / rejected


### 验证命令

```bash
# Godot 头less 导入 — 通过
/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .  # exit 0

# Registry 候选验证 — 通过
python3 .claude/skills/build-parametric-asset-library/scripts/validate_registry_batch.py \
  data/scene_generation/asset_registry_candidates/polyhaven_kitchen_batch_01.json \
  --project-root .
# PARAMETRIC_REGISTRY_PASS assets=woodentable_01,woodenchair_01,ceramic_vase_01
```

### 新增/修改文件

**新增：**
- `assets/props/polyhaven/woodentable_01/WoodenTable_01_1k.gltf` + `.bin` + `textures/` (5 files)
- `assets/props/polyhaven/woodenchair_01/WoodenChair_01_1k.gltf` + `.bin` + `textures/` (5 files)
- `assets/props/polyhaven/ceramic_vase_01/ceramic_vase_01_1k.gltf` + `.bin` + `textures/` (5 files)
- `data/scene_generation/asset_registry_candidates/polyhaven_kitchen_batch_01.json`
- `tools/assets/download_kitchen_models.py`
- `tools/assets/normalize_kitchen_registry.py`

**修改：**
- `assets/props/polyhaven/polyhaven_manifest.json` — 新增 3 条记录
- `docs/ASSET_PROVENANCE.md` — 新增 kitchen batch 章节

### 需要 Codex 决策的事宜

1. **风格分批**：三个模型应拆入各自相容的复古/哥特/现代候选集合，不能继续作为同风格套装。
2. **交互判定**：木桌、木椅是否需要 `interactable` 或 `stateful` affordance？目前仅标记为 `observable`。

---

## 批次 2：人物模型

### 执行摘要

```text
$prepare-character-model-assets（企鹅 + 3 个本地 FBX 派生角色）
```

### metadata_validated（4 个）

| character_id | 骨骼 | Morph (total / unique) | 材质 | 动画 | SHA-256 | 许可证 |
|-------------|------|-------|------|------|---------|--------|
| penguin | 64 | 41 / 20 | 10 | 8 | `15435e0997a4...f1d9e48b` | local_only (unknown / private prototype) |
| cartethyia | 652 | 2,139 / 69 | 31 | 0 | — | local_only |
| castorice | 272 | 592 / 37 | 16 | 0 | — | local_only |
| xiangliyao | 495 | 2,030 / 70 | 29 | 0 | — | local_only |

> Morph 数「total」为所有 mesh 上 morph target binding 的总条数，「unique」为去重后不同的 morph 名称数。报告中部分语言可能把 total 误称为角色 Morph 数。

### quarantined（1 个）

| character_id | 原因 |
|-------------|------|
| jue | 源目录仅有 FBX + 纹理，无 GLB 导出。需 Blender 离线转换 FBX→GLB。403 bones、40 morphs、78,112 tris（来自 README.source.md）。 |

### rejected


### 验证命令

```bash
# GLB 元数据提取 — 全部通过
python3 tools/assets/extract_penguin_metadata.py        # exit 0, 64 bones / 41 morphs / 8 anims
python3 tools/assets/extract_local_character_metadata.py # exit 0, 3/3 characters processed

# Godot 导入 — 通过
/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path .  # exit 0
```

### 新增/修改文件

**新增（企鹅）:**
- `assets/characters/penguin/provenance.json`
- `assets/characters/penguin/character_manifest.json`
- `assets/characters/penguin/bone_inventory.json`
- `assets/characters/penguin/morph_inventory.json`
- `assets/characters/penguin/animation_inventory.json`
- `assets/characters/penguin/conversion_report.json`

**新增（本地角色）:**
- `assets/local_characters/cartethyia/provenance.json`
- `assets/local_characters/cartethyia/bone_inventory.json`
- `assets/local_characters/cartethyia/morph_inventory.json`
- `assets/local_characters/cartethyia/animation_inventory.json`
- `assets/local_characters/cartethyia/conversion_report.json`
- `assets/local_characters/castorice/provenance.json`
- `assets/local_characters/castorice/bone_inventory.json`
- `assets/local_characters/castorice/morph_inventory.json`
- `assets/local_characters/castorice/animation_inventory.json`
- `assets/local_characters/castorice/conversion_report.json`
- `assets/local_characters/xiangliyao/provenance.json`
- `assets/local_characters/xiangliyao/bone_inventory.json`
- `assets/local_characters/xiangliyao/morph_inventory.json`
- `assets/local_characters/xiangliyao/animation_inventory.json`
- `assets/local_characters/xiangliyao/conversion_report.json`

**新增（工具）:**
- `tools/assets/extract_penguin_metadata.py`
- `tools/assets/extract_local_character_metadata.py`

### 需要 Codex 决策的事宜

1. **Jue GLB 导出**：`assets/local_characters/jue/` 缺少 GLB。FBX 源文件在 `source/` 目录，403 bones / 40 morphs。需在 Blender 中运行转换。
2. **本地角色 visual 验收**：Cartethyia(56K tris)、Castorice(45K tris)、Xiangliyao(31K tris) 面数较高，需在 Godot Metal 渲染中验证性能可接受。
3. **Cartethyia 652 骨骼**：骨骼数超标，确认性能可接受或是否需骨骼简化。
4. **本地角色许可证**：已标记为 `local_only`，确认本地角色文件未被 Git 跟踪（`.gitignore` 中应有 `assets/local_characters/`）。

---

## 批次 3：动作库

### 执行摘要

```text
$prepare-motion-library-assets（验证现有 smoke_walk + 创建清单）
```

### pipeline_smoke_test（1 个）

| motion_id | 帧数 | FPS | 骨骼 | 来源格式 | 状态 |
|-----------|------|-----|------|---------|------|
| smoke_walk | 72 | 20.0 | 17 | `/private/tmp/hml_fixture.npy` (fixture walk) → penguin armature | pipeline_smoke_test |

> **重要**: `smoke_walk` 来源是手工 fixture (`/private/tmp/hml_fixture.npy`, 文本 `fixture walk`)，仅用于证明 retarget smoke path 可用。它不是真实的 HumanML3D 或 Light-T2M 样本。真实样本生成仍为 pending。

### 现有嵌入式动画（penguin.glb）

| clip | duration | loop | category |
|------|----------|------|----------|
| idle | 2.0s | true | stationary |
| walk | 2.0s | true | locomotion |
| wave | 2.0s | false | gesture |
| nod | 1.5s | false | head |
| think | 2.5s | false | cognitive |
| happy | 2.0s | false | emotion |
| sit | 3.0s | false | posture |
| talk | 1.5s | false | conversation |

### 验证命令

```bash
# retarget package 验证 — 通过
python3 motion_lab/scripts/validate_retarget_package.py motion_lab/generated/library/smoke_walk
# RETARGET_PACKAGE_VALID id=smoke_walk frames=72 bones=17

# motion_catalog.json 已有 8 个动作 + 8 个 router intent
```

### 新增/修改文件

**新增：**
- `motion_lab/generated/motion_library_manifest.json`

### 需要 Codex 决策的事宜

1. **GPU 样本生成**：`motion_lab/datasets/amass_raw/` 有 22 个 AMASS tar.bz2（~20GB），HumanML3D Mean.npy / Std.npy 已就绪。需在 Linux NVIDIA 服务器上运行 Light-T2M 生成 5–10 条真实 motion 样本。
2. **批量 retarget**：样本生成后，用 `motion_lab/scripts/retarget_humanml3d_motion.py` 做批量 retarget 到 penguin 骨骼。
3. **动作 catalog 扩容**：通过验收的动作才能加入 `data/motion_catalog.json`。

---

## 批次 4：表情库

### 执行摘要

```text
$prepare-expression-library-assets（3 个本地角色 channel_map 创建）
```

### expression_candidate（3 channel_maps）

> **注意**: 生成的 `expression_adapter.candidate.json` 是独立候选文件，未接入当前 Runtime。
> Runtime 实际读取 `character_manifest.json` 的 `adapter.expression_adapter.channel_map`。
> 这些候选文件需先与现有 manifest 做 non-regression 对比，再决定是否合并。
> 未完成真实 mesh weight 测试、neutral reset 确认和 Metal 截图前不得标记为 accepted。

| character_id | 总 Morph | 语义覆盖率 | 缺失语义 |
|-------------|----------|-----------|---------|
| cartethyia | 69 unique | 14/14 candidate | — |
| castorice | 37 unique | 13/14 candidate | neutral |
| xiangliyao | 70 unique | 14/14 candidate | — |

### 共享表情库覆盖率（`data/expression_library.json`：11 个语义表达式）

| 语义ID | penguin | cartethyia | castorice | xiangliyao |
|--------|---------|-----------|-----------|------------|
| neutral | ✓ native | ✓ native | ✗ unsupported | ✓ native |
| joy | ✓ native | ✓ native | ✓ native | ✓ native |
| angry | ✓ native | ✓ native | ✓ native | ✓ native |
| sad | ✓ native | ✓ approximate | ✓ approximate | ✓ approximate |
| surprised | — | ✓ native | ✓ native | ✓ native |
| blink | ✓ native | ✓ native | ✓ native | ✓ native |
| a/i/u/e/o | ✓ native | ✓ native | ✓ native | ✓ native |
| shy | — | ✓ approximate | ✓ approximate | ✓ approximate |
| bored | — | ✓ existing runtime | ✓ existing runtime | ✓ existing runtime |
| confused | — | ✓ existing runtime | ✓ existing runtime | ✓ existing runtime |
| **合计** | 8/14 | 14/14 candidate | 13/14 candidate | 14/14 candidate |

**标记说明：**
- `native` = 角色有此 Morph，直接映射
- `approximate` = 通过近似映射或 bone_fallback 实现
- `unsupported` = 该角色无对应 Morph，目前不可用

### 验证命令

```bash
# Morph 名扫描 — 全部通过
python3 tools/assets/extract_penguin_metadata.py        # exit 0
python3 tools/assets/extract_local_character_metadata.py # exit 0

# channel_map 创建 — 全部通过
python3 tools/assets/create_expression_channel_maps.py   # exit 0
```

### 新增/修改文件

**新增（本地角色）:**
- `assets/local_characters/cartethyia/expression_adapter.candidate.json`
- `assets/local_characters/castorice/expression_adapter.candidate.json`
- `assets/local_characters/xiangliyao/expression_adapter.candidate.json`

**新增（工具）:**
- `tools/assets/create_expression_channel_maps.py`

### 需要 Codex 决策的事宜

1. **bored / confused 语义复核**：候选已保留各角色现有 runtime manifest 中经验证的近似 Morph；本批没有把它们重新声明为原生表情。
2. **Castorice neutral**：Castorice 缺少明确的 neutral/真面目 Morph。需确认其默认静止状态即可作为 neutral，或需添加 bone_fallback。
3. **表情权重真实负载测试**：channel_map 中列的 Morph 名已从 GLB 中提取，但未在 Godot 运行时实际驱动权重。需运行 `expression_driver.gd` 验证权重变化和 neutral reset。
4. **Godot 运行时截图验收**：对每个角色在 joy/angry/blink/a 四个表达式的 Godot Metal 渲染截图进行视觉验收。

---

## 全局统计

| 流水线 | 状态 | quarantined | rejected | 新增文件 | 修改文件 |
|--------|------|------------|----------|---------|---------|
| 场景素材 | 3 previewed candidates | 0 | 0 | 17 | 2 |
| 人物模型 | 4 metadata_validated | 1 (jue) | 0 | 23 | 0 |
| 动作库 | 1 pipeline_smoke_test (+8 embedded) | 0 | 0 | 1 | 0 |
| 表情库 | 3 expression_candidate | 0 | 0 | 4 | 0 |
| **合计** | **—** | **1** | **0** | **45** | **2** |

> 以上状态均非 `accepted`。`accepted` 需要在 Codex 完成 AABB/轴向测量、Metal 视觉验收、
> 许可证终审和 manifest non-regression 后才能写入。

---

## Codex 验收检查清单

### 许可证终审
- [x] WoodenTable_01 / WoodenChair_01 / ceramic_vase_01 Poly Haven CC0 许可证页面已核查
- [ ] 本地角色 `local_only` 标记确认，`.gitignore` 覆盖 `assets/local_characters/`
- [ ] 无许可证不明文件混入公开路径

### 视觉验收
- [x] 场景：3 个模型 Godot Metal 渲染截图 — 单体通过，批次风格不一致
- [ ] 人物：企鹅 idle pose 截图；本地角色 T-pose 无异常变形
- [ ] 动作：smoke_walk 骨骼长度误差、foot sliding、朝向检查
- [ ] 表情：每角色 joy/angry/blink/a Morph 驱动截图

### Registry 晋级
- [x] AABB 测量并更新 `polyhaven_kitchen_batch_01.json` 的 `geometry.aabb_m` / `front_axis` / `up_axis`
- [x] Registry 候选状态从 `inventoried` → `measured` → `previewed`
- [ ] (如果通过) `previewed` → `accepted`，可被生产 Scene Recipe 采样

### 路线图状态
- [ ] S4.1 节点更新（参数化客厅已扩展 3 个厨房候选）
- [ ] C6.1 节点更新（企鹅角色清单完整）
- [ ] C2/C3 节点更新（动作库/表情库覆盖率记录）

### Git 操作
- [ ] 确认无 `data/llm_config.json`、无 API key、无本地受限模型进入提交
- [ ] 提交信息引用主要需求节点

---

## 工具脚本索引

| 脚本 | 路径 | 用途 |
|------|------|------|
| `download_kitchen_models.py` | `tools/assets/` | 下载 Poly Haven CC0 厨房模型 → 隔离区 |
| `normalize_kitchen_registry.py` | `tools/assets/` | 规范化到项目 + Registry 候选 |
| `extract_penguin_metadata.py` | `tools/assets/` | 从 penguin.glb 提取骨骼/Morph/动画清单 |
| `extract_local_character_metadata.py` | `tools/assets/` | 批量提取 3 个本地角色 GLB 元数据 |
| `create_expression_channel_maps.py` | `tools/assets/` | 创建本地角色 Morph→语义 channel_map |

所有脚本均可重复运行（幂等），下载脚本有代理支持（`HTTPS_PROXY` 环境变量）。
