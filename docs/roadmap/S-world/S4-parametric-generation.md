# S4. 参数化建模与自动场景生成

> 所属分支：S. 场景与世界
> 节点编号：S4
> 状态：`[ACTIVE v0.8.9]`
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

### S4.1 `[DONE v0.8.9]` 参数化单房间

参数化单房间：尺寸、门窗、墙体、地板、家具槽位。

- `[DONE contract]` 已定义 `scene_recipe.schema.json`、`asset_registry.schema.json`
  和 `generated_scene_manifest.schema.json`，并提供无第三方依赖的严格校验器、
  确定性编译器和 33 个正/负例测试。
- `[DONE pipeline baseline]` 建立 `$download-open-3d-assets` 与
  `$build-parametric-asset-library` 两项批处理 Skill，覆盖来源许可、下载哈希、
  ZIP 安全审计、Godot 导入、注册表校验与 Metal 预览。
- `[DONE asset batch 01]` KayKit Furniture Bits 的扶手椅、沙发和落地灯已完成
  GLTF 依赖提取、哈希核对、真实 AABB/轴向登记及 1280×720 画面验收；
  仍保持为 Registry candidate，尚未替换客厅家具。
- `[DONE shadow migration]` 当前客厅已转写为 Recipe、Registry 与 seed 42/43
  Manifest；原 12 个 SemanticWorld 对象、交互坐标和剧情锚点保持兼容，
  另增加扶手椅、落地灯和地毯三个模型库槽位。
- `[DONE runtime builder]` `ParametricSceneBuilder` 会从 Manifest 构建地板、墙体、
  门窗开口、15 个模型实例、14 个物理体、交互锚点和 910+ 个导航三角形；
  15/15 槽位均加载许可可追溯的 Poly Haven/KayKit 模型，fallback 为 0。
- `[DONE semantic binding]` 生成物体会自动携带 `InteractableObject`，并把位置、
  状态、affordance、属性和 Godot 节点写入 `SemanticWorld`；视觉专用地毯也作为
  observable 对象登记但不制造无意义碰撞。
- `[DONE visual acceptance]` seed 42 与 43 均通过 1280×720 Metal 双截图验收；
  落地灯按 Registry 视觉角色自动生成暖色局部光。
- `living_room.tscn` 暂保留为角色演出与行为回归基准；参数化 Preview 已是可独立
  运行的完整房间。切换主场景需先把五个角色从旧房间资源中解耦为独立 Spawner，
  避免以“换房间”为名破坏现有演出测试。

### S4.2 `[ACTIVE v0.8.9]` 约束式家具布置

约束式家具布置：通道宽度、可达性、视线、碰撞和风格约束。

- 约束至少覆盖：门口净空、最小通道、家具不重叠、靠墙槽位、座位朝向、
  电视视线、每个交互锚点可达和角色出生点安全。
- 每个 seed 自动运行结构、碰撞、NavMesh、SemanticWorld 和截图验收。
- `[DONE deterministic sampling]` `uniform_offset` 与 `follow` 两种生成器已经可用；
  seed 42 保留手工基线，其他 seed 只改变 `variable_fields`，书本和饮料始终跟随
  茶几，新增字段不会扰动其他字段的随机序列。
- `[DONE baseline constraints]` 编译时 fail-closed 检查房间边界、落地家具 AABB
  重叠、桌面物体父级和交互点安全边界；连续 32 个 seed（42–73）通过。
- `[NEXT]` 增加门口净空、家具朝向/视线评分、多开口切割和失败后的确定性重采样，
  再把相同生成合同扩展到卧室与厨房 Recipe。

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
- 本地 itch.io 下载包的逐项结论见
  [S4 本地 itch.io 资产审计](../../research/S4_LOCAL_ITCH_ASSET_AUDIT.md)。

## 相关节点

- [S2 多房间与小镇](./S2-multi-room-town.md) — 场景生成的扩展基础
- [R1 程序化小镇](../R-research/R1-procedural-town.md) — 远期研究协同

> 相关文档：[S 分支总览](./README.md)
