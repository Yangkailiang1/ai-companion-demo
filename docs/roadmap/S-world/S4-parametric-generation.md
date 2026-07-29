# S4. 参数化建模与自动场景生成

> 所属分支：S. 场景与世界
> 节点编号：S4
> 状态：`[ACTIVE v0.8.9]`
> 依赖：S2（多房间场景结构）、T2（语义世界）
> 最后更新：2026-07-29 | 基线程：v0.8.9

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
- `[DONE main integration baseline]` 参数化房间已通过 `WorldLocationLoader` 接入
  真实 `main.tscn`，保留 CanvasLayer UI、环绕相机和五名角色；可用
  `AI_GAMES_WORLD_MODE=parametric` 启动，默认仍以 legacy 客厅作为回归基准。
- `[DONE stateful generated objects baseline]` Registry 中声明 `has_states` 的生成
  物体会自动获得通用 `GeneratedObjectState`；植物浇水会改变 moisture/health 和
  可见状态，灯具开关/调光会改变实际光照，不按具体模型路径写分支。
- `[DONE cast decoupling]` 固定角色与本地 Q 版生成器已成为独立场景，legacy 与
  parametric 通过同一 `WorldCastAssembler` 挂载；生成地点不再依赖旧客厅资源。
- `[DONE performance compatibility]` 生成语义物体会按通用 snake_case→公共节点名
  规则提升到 WorldLocation 根（如 `tv`→`TV`），生成电视具有状态光反馈；参数化
  模式已通过完整双角色走位、注视、动作、表情、物体交互、对白和记忆演出合同。
- `[DONE navigation contract]` 运行时 NavMesh 入树后显式上传，测试覆盖两个固定
  角色到七个关键剧情路点的连通性，避免家具 AABB 形成不可见封路。

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
- `[DONE room-type extension baseline]` 相同 Registry/编译合同已扩展到厨房与卧室；
  厨房 8 个槽位、卧室 7 个槽位均通过边界、家具重叠与桌面跟随约束；卧室已用
  KayKit CC0 双人床替换临时沙发占位。
- `[NEXT]` 增加门口净空、家具朝向/视线评分、多开口切割和失败后的确定性重采样。

### S4.3 `[ACTIVE baseline]` 模块化住宅生成

模块化住宅生成：房间连接图、楼层和功能分区。

- `[DONE data baseline]` 客厅、厨房、卧室均由可编辑 Recipe 和确定性 Manifest
  描述，并通过版本化 `world_locations.json` 组成有向房间连接图。
- `[DONE study manifest baseline]` seed 303 书房以独立 Manifest 接入同一 Registry
  和地点图；下一轮补对应 Recipe 与确定性编译哈希，使来源合同与前三房间同级。
- `[DONE runtime baseline]` 同一个参数化房间运行时按地点元数据加载不同 Manifest，
  应用独立根节点、语义可见域、入口和 Cast 出生点。
- `[DONE visual baseline]` 厨房和卧室使用适配玩偶屋相机的三面墙表现，真实模型
  覆盖率分别为 8/8 与 7/7、fallback 为 0，并通过 Metal 1280×720 截图验收。
- `[DONE portal module baseline]` Recipe 开口与地点图 portal 数据已映射为四个可见
  门模块；门框、门扇、碰撞、标签、点击旅行和 `traverse` 语义合同均由通用装配器
  创建，不按厨房/卧室硬编码节点。
- `[NEXT]` 加入门口净空约束、真实走廊模块、房间级流送、楼层坐标和整套住宅
  预览；完成玩家连续穿越及角色自主跨房导航后再标记完成。

### S4.4 `[LATER]` 街区生成

街区生成：道路图、地块、建筑模块和公共空间。

### S4.5 `[LATER]` 自然语言场景配置

自然语言生成场景配置，但必须经过确定性约束求解与导航验收。

## 技术原则

生成结果应保存为可编辑的参数和场景资源，而不是一次性不可复现的网格。

高成本程序化网格、材质烘焙和 LOD 在 Blender 离线完成；Godot 运行时只生成简单
结构、实例化规范化资产、建立物理/语义节点并执行约束验收。

## 迁移门槛

参数化模式已进入真实主场景的可选验收阶段；升为默认模式前仍须满足：

1. 五个现有角色、自由模式和演出模式测试不回退；
2. 所有现有语义对象 ID 与剧情锚点保持兼容；
3. 导航覆盖率、最小通道和交互可达性通过；
4. 1280×720 Metal 截图的构图与视觉质量不低于基准；
5. 相同 seed 生成 Manifest 哈希一致，不同 seed 只改变声明为可变的内容；
6. 所有进入公共仓库的资产许可证与来源可追溯。

当前 1–6 已具备单房间基线，Cast 抽取桥已经移除，带 `location_id` 的 Schema v2
跨房间存档及可点击门闭环也已通过。剩余默认切换阻塞项是真实走廊、玩家实体的
连续穿越、角色自主跨房间，以及参数化住宅中自由/演出模式的长时间回归。

## 研究参考

- 相关论文目录：`/Users/yangkailiang/Documents/ai_games/调研/论文/04_参数化场景与模型生成/`
- 本地 itch.io 下载包的逐项结论见
  [S4 本地 itch.io 资产审计](../../research/S4_LOCAL_ITCH_ASSET_AUDIT.md)。

## 相关节点

- [S2 多房间与小镇](./S2-multi-room-town.md) — 场景生成的扩展基础
- [R1 程序化小镇](../R-research/R1-procedural-town.md) — 远期研究协同

> 相关文档：[S 分支总览](./README.md)
