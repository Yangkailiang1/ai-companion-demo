# S4. 参数化建模与自动场景生成

> 所属分支：S. 场景与世界
> 节点编号：S4
> 状态：`[ACTIVE DESIGN]`
> 依赖：S2（多房间场景结构）、T2（语义世界）
> 最后更新：2026-07-28 | 基线程：v0.8.9

## 职责

通过参数驱动和约束求解自动生成住宅和场景布局，降低手工建造的工作量。

## 规划节点

### S4.0 `[DONE design baseline]` 生成合同与资产许可分层

- 采用 `Scene Recipe → Asset Registry → Semantic/Interaction Layer` 三层架构。
- 视觉、碰撞和语义能力正交，禁止用单一 `is_interactable` 表示对象类型。
- 生成结果必须由 `recipe + registry_version + seed` 确定性重建。
- LLM 只提供风格、用途和高层约束，确定性求解器负责坐标、净空和导航。
- 免费资产与工具调研见
  [S4 免费参数化室内资产与生成工具调研](../../research/S4_FREE_PROCEDURAL_ASSET_LIBRARIES.md)。

### S4.1 `[NEXT v0.8.9]` 参数化单房间

参数化单房间：尺寸、门窗、墙体、地板、家具槽位。

- `[NEXT contract]` 定义 `scene_recipe.schema.json`、`asset_registry.schema.json`
  和 `generated_scene_manifest.schema.json`。
- `[NEXT migration]` 将当前客厅转写为 shadow Recipe，保留现有
  `living_room.tscn` 作为视觉与行为基准。
- `[NEXT preview]` 创建独立 ParametricLivingRoomPreview；未通过对比验收前
  不替换主场景。

### S4.2 `[PLANNED]` 约束式家具布置

约束式家具布置：通道宽度、可达性、视线、碰撞和风格约束。

- 约束至少覆盖：门口净空、最小通道、家具不重叠、靠墙槽位、座位朝向、
  电视视线、每个交互锚点可达和角色出生点安全。
- 每个 seed 自动运行结构、碰撞、NavMesh、SemanticWorld 和截图验收。

### S4.3 `[PLANNED]` 模块化住宅生成

模块化住宅生成：房间连接图、楼层和功能分区。

首个目标为客厅、卧室、厨房三房间住宅，输出可编辑 Recipe 和生成 Manifest。

### S4.4 `[LATER]` 街区生成

街区生成：道路图、地块、建筑模块和公共空间。

### S4.5 `[LATER]` 自然语言场景配置

自然语言生成场景配置，但必须经过确定性约束求解与导航验收。

## 技术原则

生成结果应保存为可编辑的参数和场景资源，而不是一次性不可复现的网格。

高成本程序化网格、材质烘焙和 LOD 在 Blender 离线完成；Godot 运行时只生成简单
结构、实例化规范化资产、建立物理/语义节点并执行约束验收。

## 迁移门槛

参数化 Preview 同时满足以下条件后才能替换当前客厅：

1. 五个现有角色、自由模式和演出模式测试不回退；
2. 所有现有语义对象 ID 与剧情锚点保持兼容；
3. 导航覆盖率、最小通道和交互可达性通过；
4. 1280×720 Metal 截图的构图与视觉质量不低于基准；
5. 相同 seed 生成 Manifest 哈希一致，不同 seed 只改变声明为可变的内容；
6. 所有进入公共仓库的资产许可证与来源可追溯。

## 研究参考

- 相关论文目录：`/Users/yangkailiang/Documents/ai_games/调研/论文/04_参数化场景与模型生成/`

## 相关节点

- [S2 多房间与小镇](./S2-multi-room-town.md) — 场景生成的扩展基础
- [R1 程序化小镇](../R-research/R1-procedural-town.md) — 远期研究协同

> 相关文档：[S 分支总览](./README.md)
