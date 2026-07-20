# ASSET_PROVENANCE.md — 资产来源记录

> v0.2 | 最后更新: 2026-07-20

## 免责声明

所有第三方资产 **许可证未确认**。仅用于 private prototype development，不得声称可商用。

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

## 导出脚本

| 脚本 | 位置 | 说明 |
|------|------|------|
| `export_penguin.py` | `tools/blender/export_penguin.py` | 清理 helper objects、Shape Keys，导出 penguin.glb |
| `generate_penguin_animations.py` | `tools/blender/generate_penguin_animations.py` | 生成 7 个程序化骨骼动画并导出 |
| `export_garden.py` | `tools/blender/export_garden.py` | 清理灯光/相机、修复 alpha 材质、缩放导出 garden.glb |

运行方式（Blender headless）：
```bash
/Applications/Blender.app/Contents/MacOS/Blender --background <source.blend> --python <script.py>
```

## 预期 Godot 导入产物

| 源 GLB | 导入路径 | Godot 产物 |
|---------|---------|-----------|
| `assets/characters/penguin/penguin.glb` | `res://assets/characters/penguin/` | `.import` 文件 + 可实例化的 packed scene |
| `assets/environments/endless_garden/garden.glb` | `res://assets/environments/endless_garden/` | `.import` 文件 + 可实例化的 packed scene |

## 审查人员

- 初版实现: Claude Code (2026-07-20)
- 最终导出与验收: Codex (2026-07-20)
- Blender 解压/审计：已完成 .blend / .vrm 内部结构检查
- 第三方 model/scene 文件仅存储于本地，未纳入 Git
