# 参数化场景合同

> 对应规划：S4.1
> 状态：合同与 shadow Recipe 基线完成
> 最后更新：2026-07-28

## 数据流

```text
Scene Recipe
    + Asset Registry 的精确 ID / 版本
    + seed
        ↓ 严格校验与交叉引用
Generated Scene Manifest
        ↓ Godot ParametricSceneBuilder
隔离 ParametricLivingRoomPreview
        ↓ 碰撞 / 导航 / 语义 / Metal 画面验收
候选场景版本
```

LLM 只负责房间用途、风格和高层约束。它不能直接给出未经验证的资源路径或任意
世界坐标。坐标、净空、碰撞、导航与锚点由确定性生成器和约束求解器处理。

## 三个合同

- `scene_recipe.schema.json`：房间尺寸、墙体、开口、家具槽位、路径点、
  不可变剧情锚点和允许变化的字段。
- `asset_registry.schema.json`：资源来源、尺寸、朝向、视觉类型、物理类型、
  语义能力和摆放约束。视觉、物理与交互能力相互独立。
- `generated_scene_manifest.schema.json`：一次确定性生成的完整摆放结果与
  generation hash。

Recipe 必须精确匹配 Registry 的 `registry_id` 和 `registry_version`。未知字段、
缺失资产、重复语义 ID、不存在的路径点以及覆盖不可变锚点的变量都会被拒绝。

## 当前 shadow 基线

`living_room_shadow.recipe.json` 记录当前客厅：

- 8 × 8 × 3 米房间合同与三面现有墙体；
- 12 个现有 SemanticWorld 对象；
- 16 个路径点和客厅环绕路线；
- 当前交互坐标；
- 8 个不可变剧情/结构锚点；
- 10 个未来可由 seed 改变的字段。

seed 42 的 generation hash：

`7981ed2f08ff4c80594dd7af029e57599fecd25820a0c377711eb7d61adb62bd`

这份 shadow 数据不会替换 `living_room.tscn`。当前隔离 Preview 已能从 Manifest
生成地板、墙体、12 个物体槽位、物理体和交互锚点，并按 Registry 加载 6 个
Poly Haven 模型；剩余项目自有对象暂时使用明确标记的参数化基本体。

## 验收命令

```bash
python3 -m unittest discover -s tests/scene_generation -p 'test_*.py'
python3 tools/scene_generation/compile_scene_recipe.py \
  --recipe data/scene_generation/recipes/living_room_shadow.recipe.json \
  --registry data/scene_generation/registries/living_room_shadow_registry.json
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script scripts/debug/parametric_shadow_recipe_check.gd
```

Godot 检查会同时比对 Recipe、`scene_config.json` 和 `living_room.tscn` 节点中的
12 个 `object_id`，并要求对象位置与交互位置误差不超过 0.001 米。
