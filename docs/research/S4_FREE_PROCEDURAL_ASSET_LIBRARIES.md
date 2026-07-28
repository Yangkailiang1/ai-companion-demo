# S4 免费参数化室内资产与生成工具调研

> 调研日期：2026-07-28
> 目标：为 Godot 参数化住宅生成建立可公开再分发的资产来源和离线工具边界。

## 结论

本项目不应寻找一个“包办一切的参数化模型库”，而应组合三类来源：

1. **确定性 Scene Recipe**：记录 seed、房间拓扑、尺寸、开口、风格和布局约束；
2. **许可可审计的 Asset Registry**：保存模型、材质、尺寸、朝向、LOD 和来源；
3. **独立 Semantic Layer**：决定对象是否仅渲染、是否阻挡、是否进入 Agent 感知、
   是否可交互、是否有状态、是否可携带。

参数化生成器只生成候选布局。碰撞、最小通道、交互锚点、角色可达性和许可证检查
全部通过后，场景才可保存或发布。LLM 可以写高层需求，但不能直接输出任意节点路径
和未经约束的世界坐标。

## 可直接进入白名单

| 来源 | 许可与能力 | 建议用途 |
|---|---|---|
| [Poly Haven](https://polyhaven.com/license) | 全站 HDRI、材质和模型 CC0；允许商业使用、修改和再分发。[官方 API](https://polyhaven.com/our-api) 提供分类、尺寸、LOD、文件、哈希和下载地址 | 写实 PBR 材质、HDRI、少量高质量家具与装饰；首选自动化来源 |
| [ambientCG](https://ambientcg.com/) | 官方声明全部材质、HDRI 和模型为 CC0 | 墙面、地板、木材、织物等 PBR 表面；模型作为补充 |
| [Kenney](https://kenney.nl/support) | 官方资产页均为 CC0，允许商业使用且无需署名；[Furniture Kit](https://kenney.nl/assets/furniture-kit) 有 140 个 3D 文件 | 统一低多边形风格的家具、建筑模块和占位资产 |
| [Quaternius](https://quaternius.com/faq.html) | 官方 FAQ 声明模型均为 CC0，可商业使用、修改、组合且无需署名；常见 Blend/FBX | Q 版/低多边形住宅、道具和小镇资产 |
| [Infinigen](https://github.com/princeton-vl/infinigen) | 生成代码 BSD-3-Clause；支持程序化室内资产、约束布局和外部格式导出 | 离线研究、约束语言和 Blender 生成器参考；不直接作为 Godot 运行时依赖 |

白名单仍需为每个落盘资产保存来源 URL、下载日期、哈希和许可证快照。CC0 只解决
版权许可，不代表模型已经满足面数、碰撞、正面轴、物理尺寸和性能要求。

## 黄名单：必须逐资产审计

| 来源 | 风险 | 使用条件 |
|---|---|---|
| [Blendkit / BlenderKit](https://www.blendkit.com/docs/licenses/) | 同时包含 CC0 与 Royalty Free；后者不允许把模型作为独立模型/资产包再销售或开放提取 | 只自动接入明确标记 CC0 的条目；其他条目不得进入公共模型库 |
| [Sketchfab Download API](https://sketchfab.com/developers/download-api) | 每个模型许可证不同；开发者条款要求显示许可证和作者信息 | 逐资产保存作者、原页面、许可证和署名；公共仓库默认拒绝非 CC0 |
| [Objaverse-XL](https://github.com/allenai/objaverse-xl) | 数据集整体为 ODC-By，但单个对象许可证不同，部分来源仅限非商业研究 | 只适合许可过滤后的离线研究；不得把整个集合当成可发布资产库 |
| Archipack | 可用于 Blender 建筑建模，但社区版、商业版、代码和输出资产边界需要按具体版本确认 | 先审查所用版本源码许可证，再作为离线墙体/门窗生成工具 |
| [Bonsai](https://bonsaibim.org/) | 开源 OpenBIM/IFC 工具，功能重、依赖多，目标是 BIM 而非游戏关卡 | 仅在未来需要 IFC/真实建筑数据时评估，不进入当前 MVP |

## 研究隔离名单

| 来源 | 原因 |
|---|---|
| [3D-FRONT](https://gw.alicdn.com/bao/uploaded/TB1ZJUfK.z1gK0jSZLeXXb9kVXa.pdf) | 官方协议明确限定 scientific research purpose only，许可可撤销、不可转让且不可再许可；不能随公开游戏发布 |
| ProcTHOR / AI2-THOR | ProcTHOR 代码为 Apache-2.0，适合研究房间图与约束，但代码许可不自动覆盖 Unity/AI2-THOR 的全部模型资产 |
| Objaverse / Objaverse-XL 原始全集 | 许可混合，只能在逐对象许可过滤和隔离存储后用于研究或训练 |

## 参数化工具选择

- [Blender Geometry Nodes](https://docs.blender.org/manual/en/latest/modeling/geometry_nodes/introduction.html)
  适合离线生成墙体、踢脚线、窗框和重复装饰，并可把节点组保存为资产。
- Infinigen Indoors 的核心价值是“约束描述 + 求解器 + 程序化资产”，不是直接复制
  整个研究栈。其 2.0 仍为 preview，官方也说明室内物体种类和布局仍有限。
- Godot 运行时只负责读取 Recipe、实例化已规范化 GLB/PackedScene、生成简单结构网格、
  建立碰撞和导航。高成本网格生成、贴图烘焙、LOD 制作放在 Blender 离线流水线。

## 三层架构

### Scene Recipe

保存 `recipe_id`、`schema_version`、`seed`、房间连接图、房间尺寸、门窗开口、表面
材质、家具槽位和约束。相同 Recipe、Registry 版本与 seed 必须生成同一结果。

### Asset Registry

每个 `asset_id` 记录资源路径、来源、许可、哈希、物理尺寸、front/up 轴、风格标签、
预算、碰撞模板、默认锚点和兼容房间类型。生成器只能使用 Registry 中的资产 ID，
不能使用任意磁盘路径或 URL。

### Semantic / Interaction Layer

视觉分类与交互能力必须正交：

- `visual_only`：地毯花纹、小摆件，只渲染；
- `obstacle`：墙、柜体等参与碰撞/导航，但不进入 Agent 语义快照；
- `observable`：角色可以看见/描述，但没有改变世界的动作；
- `interactable`：具备白名单 affordance 和 approach/look 等锚点；
- `stateful`：灯、电视、植物、门等具有状态组件与存档；
- `portable`：书、杯子等具有刚体、抓取/放置锚点和持有者状态。

一个物体可以同时是 `obstacle + stateful + interactable`，因此不可用单个
`is_interactable` 布尔值替代能力集合。

## 两阶段 MVP

### 阶段 A：参数化复刻当前客厅

1. 把当前客厅转写为 Recipe 与 Asset Registry，但保留 `living_room.tscn` 作为基准。
2. 生成独立 Preview 场景，与基准做节点、AABB、导航、语义对象和截图对比。
3. 支持 3 个 seed，只改变装饰、材质和允许变化的家具槽位，不改变剧情锚点合同。
4. Preview 通过全部测试后，主场景才切换到生成器；旧场景保留一个版本作为回退。

### 阶段 B：三种住宅房间

生成客厅、卧室、厨房三类房间，支持房间连接图、门口净空、家具靠墙、座位朝向、
电视视线、交互锚点可达以及跨房间导航。生成结果保存为 Recipe + Manifest，
而不是只保存不可复现的 `.tscn`。

## DeepSeek 批处理与 Codex 验收

DeepSeek/Claude Code 适合：

- 从白名单 API 提取候选元数据，每批最多 3 个同类资产；
- 生成 Registry 草案和下载清单；
- 调用已有 `godot-import-interactable-object` Skill 处理已确认许可的模型；
- 为同 archetype 生成碰撞、锚点和合约测试草案。

Codex 必须负责：

- 复核官方许可、来源和哈希；
- 检查真实 AABB、front/up 轴、比例和材质；
- Metal 画面验收、导航/碰撞/交互锚点验收；
- 决定是否进入公共仓库并提交关键版本。

2026-07-28 已重新验证 DeepSeek 接入的 Claude Code 可用：它读取项目 Skill 后，
从本地 KayKit Furniture Bits 精确提取三件 GLTF 资产、依赖贴图和 provenance，
并生成 Registry candidate。Codex 随后完成源文件哈希比对、真实 AABB/轴向测量、
Godot 4.6.1 导入及 1280×720 Metal 预览。后续继续保持“DeepSeek 每批最多三件，
Codex 负责许可、画面和提交验收”的边界。
