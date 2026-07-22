# ASSET_PROVENANCE.md — 资产来源记录

> v0.6 | 最后更新: 2026-07-22

## 免责声明

本地用户提供的角色/场景资产许可证仍按 **unknown / private prototype only** 处理。

Poly Haven 下载的家具模型与 PBR 贴图按 Poly Haven 公示许可证记录为 **CC0**，可用于当前 demo 原型与后续重混/改造；仍建议发布前保留来源清单与下载 manifest。

## 资产清单

### 1. 终末地小企鹅（Primary Character）

| 属性 | 值 |
|------|-----|
| **源文件** | `/Users/yangkailiang/Documents/ai_games/model/终末地小企鹅.zip` |
| **格式** | `.blend` / `.vrm` |
| **角色类型** | 企鹅拟人 |
| **尺码** | 约 1.21m 高 |
| **骨骼** | 64 bones: `root, hips, spine, chest, neck, head, shoulder.L/R, upper_arm.L/R, lower_arm.L/R, hand.L/R, upper_leg.L/R, lower_leg.L/R, foot.L/R, toes.L/R`；另有 `eye.L/R`、35 根 hair bones |
| **Mesh** | 18 meshes（含 skinned meshes） |
| **Shape Keys** | 脸部（blink, mouth 等 visemes） |
| **动画** | 原始 Action 为单帧 pose，无可播放身体动画 **（本轮通过 `generate_penguin_animations.py` 生成 7 个程序化动画）** |
| **导出** | `assets/characters/penguin/penguin.glb` |
| **脚本** | `tools/blender/export_penguin.py`（清理+导出）、`tools/blender/generate_penguin_animations.py`（动画生成） |
| **许可证** | `license: unknown / private prototype only` |
| **来源渠道** | 本地文件 |

### 2. 诀 — 备选人形角色（校验版）

| 属性 | 值 |
|------|-----|
| **源文件** | `/Users/yangkailiang/Documents/ai_games/model/诀.7z` |
| **格式** | `.blend` |
| **角色类型** | 人形女性 |
| **尺码** | 约 1.793m 高 |
| **顶点** | 72,680 |
| **面** | 84,352 |
| **骨骼** | 407 bones |
| **Shape Keys** | 41 |
| **动画** | 无身体动画 |
| **许可证** | `license: unknown / private prototype only` |
| **来源渠道** | 本地文件 |
| **状态** | **本轮不作为主角色使用**（骨骼数量过多，复杂装饰/长袖不适合程序化动画） |

### 3. 终幕喑哑之庭 — 幻想庭园场景

| 属性 | 值 |
|------|-----|
| **源文件** | `/Users/yangkailiang/Documents/ai_games/scene/终幕喑哑之庭.zip` |
| **格式** | `.blend` |
| **场景类型** | 幻想庭院 |
| **范围** | 约 195m 直径 |
| **Mesh** | 21 meshes |
| **Curve** | 38 curves |
| **Material** | 17 materials（含 4 个 alpha 材质） |
| **许可证** | `license: unknown / private prototype only` |
| **来源渠道** | 本地文件 |
| **导出** | `assets/environments/endless_garden/garden.glb` |
| **脚本** | `tools/blender/export_garden.py` |
| **Scale** | 已缩放到 0.1x 以适配 Godot 默认相机 clip planes |
| **Alpha 材质** | 4 个：`gan.001`, `gan.002`, `ye`, `ye.001`；旧版节点无法完整自动转换，需美术人工重制 |
| **导航** | 未烘焙 NavMesh，详见 `assets/environments/endless_garden/NAVIGATION_NOTES.md` |
| **验收状态** | 几何与独立预览可加载；源材质在 Godot 中偏黑白，仅作为技术预览，不作为正式游戏场景 |

### 4. Poly Haven — 客厅家具与 PBR 材质（CC0）

| 用途 | Asset | 项目路径 | 来源 |
|------|-------|----------|------|
| 沙发 | `Sofa_01` | `assets/props/polyhaven/Sofa_01/Sofa_01_1k.gltf` | `https://polyhaven.com/a/Sofa_01` |
| 茶几 | `modern_coffee_table_01` | `assets/props/polyhaven/modern_coffee_table_01/modern_coffee_table_01_1k.gltf` | `https://polyhaven.com/a/modern_coffee_table_01` |
| 电视 | `Television_01` | `assets/props/polyhaven/Television_01/Television_01_1k.gltf` | `https://polyhaven.com/a/Television_01` |
| 盆栽 | `potted_plant_01` | `assets/props/polyhaven/potted_plant_01/potted_plant_01_1k.gltf` | `https://polyhaven.com/a/potted_plant_01` |
| 书架 | `Shelf_01` | `assets/props/polyhaven/Shelf_01/Shelf_01_1k.gltf` | `https://polyhaven.com/a/Shelf_01` |
| 吊灯 | `modern_ceiling_lamp_01` | `assets/props/polyhaven/modern_ceiling_lamp_01/modern_ceiling_lamp_01_1k.gltf` | `https://polyhaven.com/a/modern_ceiling_lamp_01` |
| 相框 | `hanging_picture_frame_01` | `assets/props/polyhaven/hanging_picture_frame_01/hanging_picture_frame_01_1k.gltf` | `https://polyhaven.com/a/hanging_picture_frame_01` |
| 木地板 PBR | `herringbone_parquet` | `assets/materials/polyhaven/herringbone_parquet/` | `https://polyhaven.com/a/herringbone_parquet` |
| 墙面 PBR | `plastered_wall_04` | `assets/materials/polyhaven/plastered_wall_04/` | `https://polyhaven.com/a/plastered_wall_04` |
| 地毯 PBR | `dirty_carpet` | `assets/materials/polyhaven/dirty_carpet/` | `https://polyhaven.com/a/dirty_carpet` |

下载脚本：

- `tools/assets/download_polyhaven_models.py`
- `tools/assets/download_polyhaven_textures.py`

Manifest：

- `assets/props/polyhaven/polyhaven_manifest.json`
- `assets/materials/polyhaven/polyhaven_texture_manifest.json`

Godot 接入状态：

- `scenes/living_room.tscn` 已用真实模型替换灰盒视觉；原交互节点/碰撞保持不变。
- 地板、墙面、地毯已绑定 1K PBR diffuse / normal / ARM 贴图。

### 5. Codex ImageGen — 客厅外部暖色背景图

| 属性 | 值 |
|------|-----|
| **生成文件** | `assets/environments/backdrops/cozy_morning_backdrop.png` |
| **用途** | 替换房间外部黑色背景，提供温暖晨景氛围 |
| **生成方式** | Codex built-in `image_gen` |
| **提示词摘要** | warm painterly morning exterior backdrop, pastel sky, soft trees, cozy apartment mood, no text/watermark |
| **状态** | 已作为项目本地资产引用到 `scenes/living_room.tscn` |

## 导出脚本

| 脚本 | 位置 | 说明 |
|------|------|------|
| `export_penguin.py` | `tools/blender/export_penguin.py` | 清理 helper objects、Shape Keys，导出 penguin.glb |
| `generate_penguin_animations.py` | `tools/blender/generate_penguin_animations.py` | 生成 7 个程序化骨骼动画并导出 |
| `export_garden.py` | `tools/blender/export_garden.py` | 清理灯光/相机、修复 alpha 材质、缩放导出 garden.glb |
| `download_polyhaven_models.py` | `tools/assets/download_polyhaven_models.py` | 下载 Poly Haven 1K glTF 家具模型 |
| `download_polyhaven_textures.py` | `tools/assets/download_polyhaven_textures.py` | 下载 Poly Haven 1K PBR 纹理 |

运行方式（Blender headless）：
```bash
/Applications/Blender.app/Contents/MacOS/Blender --background <source.blend> --python <script.py>
```

## 预期 Godot 导入产物

| 源 GLB | 导入路径 | Godot 产物 |
|---------|---------|-----------|
| `assets/characters/penguin/penguin.glb` | `res://assets/characters/penguin/` | `.import` 文件 + 可实例化的 packed scene |
| `assets/environments/endless_garden/garden.glb` | `res://assets/environments/endless_garden/` | `.import` 文件 + 可实例化的 packed scene |
| `assets/props/polyhaven/**/*.gltf` | `res://assets/props/polyhaven/` | `.import` 文件 + 可实例化 furniture packed scenes |

## 审查人员

- 初版实现: Claude Code (2026-07-20)
- 最终导出与验收: Codex (2026-07-20)
- Blender 解压/审计：已完成 .blend / .vrm 内部结构检查
- 第三方 model/scene 文件仅存储于本地，未纳入 Git
