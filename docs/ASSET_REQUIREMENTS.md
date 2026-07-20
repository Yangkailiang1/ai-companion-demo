# ASSET_REQUIREMENTS.md — AI Companion Demo 资产需求清单

> v0.1 → v0.2 阶段所需外部资产 | 按优先级排列

---

## P0 — 必须（完善游戏基本观感）

### 角色模型：小叶子

| 规格 | 要求 |
|------|------|
| 格式 | `.glb` 或 `.gltf`（Godot 原生支持） |
| 类型 | 青年女性角色，日系/韩系风格 |
| 高度 | 约 1.6m（世界单位，Godot 1 单位 = 1m） |
| 三角面数 | 10K-30K |
| 绑定 | 需含 Mixamo 兼容骨骼或 Godot Skeleton3D |
| 动画 | 需含 Idle、Walk、Sit、Wave、Drink、PickUp 动画 |
| 材质 | 需含基础 PBR 贴图（Albedo、Normal、Roughness） |
| 参考 | "活泼开朗的年轻女孩，20岁左右" |

**替换位置**：`scenes/living_room.tscn` → Agent 节点下的 AgentBody、AgentHead MeshInstance3D

**代码对接**：`AnimationController` 替换为 `AnimationTree` + AnimationNodeStateMachine，动画名称映射：
- `idle` → Idle loop
- `walk` → Walk loop（agent_base 自动触发 `is_moving`）
- `sit` → SIT primitive
- `wave` → wave_at_player goal
- `drink` → DRINK/INTERACT with milk_tea

### 休息/待机动画

如果无法获取完整骨骼动画，至少需要：
- **Idle**：站立呼吸循环（可用程序化浮动临时替代，当前已实现）
- **Walk**：行走循环（可用纯位移替代，当前已实现）

---

### 3D 环境：客厅场景

| 规格 | 要求 |
|------|------|
| 格式 | `.glb` 单个场景文件 或 Godot `.tscn` |
| 面积 | 约 8m × 8m（匹配当前灰盒尺寸） |
| 必需元素 | 地板、墙壁（3面+天花板）、窗户（可选） |
| 家具 | 沙发、茶几、电视柜、餐桌（至少 4 件核心家具） |
| 三角面数 | 合计 < 100K |
| 材质 | PBR 贴图套装 |

**物体对齐**（世界坐标需匹配 SemanticWorld 的位置配置）：

| 物体 | 当前 semantic 位置 | 3D 资产放置位置 |
|------|-------------------|----------------|
| 沙发 (sofa) | (-1.5, 0.25, 1.8) | 客厅前部 |
| 电视 (tv) | (-1.5, 0.85, -3.82) | 后墙 |
| 茶几/书 (book) | (0.55, 0.4, 0.7) | 茶几上 |
| 茶几/奶茶 (milk_tea) | (1.55, 0.52, 0.7) | 茶几上 |
| 绿植 (plant) | (2.75, 0.3, -2.65) | 客厅右后角 |

---

### 物体模型（P0 子集）

| 物体 | 当前 Mesh | 需要资产 |
|------|----------|---------|
| 电视 | BoxMesh (2.5x1.2) | 液晶电视模型 (.glb) |
| 沙发 | BoxMesh (2x0.5) | 布艺沙发模型 (.glb) |
| 奶茶/杯子 | CylinderMesh | 奶茶杯模型 (.glb)，可选带珍珠 |
| 书本 | BoxMesh (0.3x0.05) | 书本模型 (.glb) |
| 绿植 | CylinderMesh | 盆栽模型 (.glb) |

---

## P1 — 推荐（提升沉浸感）

### 角色动画扩展

| 动画 | 触发 | 优先级原因 |
|------|------|-----------|
| Greet/Wave | wave_at_player goal | 自然社交互动 |
| Sit down / Stand up | SIT primitive | 沙发交互的前提 |
| Pick up / Put down | PICK_UP/PUT_DOWN | 物体交互视觉反馈 |
| Drink | INTERACT drink | 奶茶饮用表现 |
| Read | INTERACT read | 读书表现 |
| Look around | LOOK_AT | 环顾环境 |

### 环境资产扩展

| 资产 | 说明 |
|------|------|
| 窗户 + 室外景色 | 天光变化可感知 |
| 灯具 (吊灯/台灯) | 夜晚照明变化 |
| 地毯 | 视觉分区 |
| 装饰品 (相框、抱枕) | 生活气息 |

### UI 资产

| 资产 | 格式 | 说明 |
|------|------|------|
| 聊天框背景 | `.png`, 9-slice | 替换 Panel 默认样式 |
| 心情图标 | `.svg`/`.png` 32x32 | 用于 HUD 需求条旁边 |
| 字体 | `.ttf`/`.otf` | 中文字体（推荐思源黑体或站酷快乐体） |
| 发送按钮样式 | Theme 资源 | 替换默认 Button 样式 |
| 进度条主题 | Theme 资源 | 需求条着色（红→黄→绿渐变） |

---

### 音频资产

| 类型 | 格式 | 触发点 |
|------|------|--------|
| 背景音乐 | `.ogg`/`.mp3` 循环 | 游戏全程 |
| 环境音（时钟、窗外） | `.ogg` 循环 | 客厅场景 |
| UI 点击音效 | `.wav` 短音 | 发送按钮 |
| 走路音效 | `.wav` | Agent 移动时 |
| 喝水/翻书音效 | `.wav` | INTERACT 动作 |

---

## P2 — 可选（后续版本）

### 角色扩展

| 资产 | 说明 |
|------|------|
| 衣服/配饰变体 | 不同心情/场景换装 [CCL §3.3] |
| 表情 BlendShapes | 眼睛、眉毛、嘴形变化 → 情绪可视化 |
| 口型同步 | 对话时嘴唇动画 |

### 粒子/特效

| 效果 | 触发 |
|------|------|
| 喝奶茶时珍珠浮动 | INTERACT drink |
| 浇水时水滴粒子 | INTERACT water |
| 心情变化时头顶图标 | Emotion 变化 |

### 环境扩展

| 资产 | 说明 |
|------|------|
| 厨房/卧室额外房间 | 扩展 Agent 活动范围 |
| 室外阳台 | 阳光、雨天氛围 |
| 日夜循环天空 | WorldSimulator time_of_day 驱动 |

---

## 技术规格摘要

| 类别 | 推荐规格 |
|------|---------|
| **3D 格式** | `.glb` (GLTF 2.0 binary) — Godot 4 原生导入，保留材质、骨骼、动画 |
| **贴图分辨率** | Diffuse 2048² max, Normal/Roughness 1024² |
| **骨骼动画** | Mixamo 标准骨架 或 Godot Skeleton3D |
| **UI 图标** | SVG（可缩放）或 PNG 32×32 / 64×64 |
| **音频** | OGG Vorbis 用于音乐/环境，WAV 用于 UI 音效 |
| **字体** | 含中文字符集的 TTF/OTF |

---

## 资产获取建议

1. **3D 模型市场**：Sketchfab（CC0 免费）、CGTrader、Unity Asset Store → 转换为 glb
2. **Mixamo**：Adobe 免费角色动画库，可直接下载带骨骼动画的 FBX → Blender → .glb
3. **Blender**：免费 3D 建模软件，可搭配建筑插件做室内场景
4. **Freesound.org**：免费音效库（CC0/CC-BY）
5. **Google Fonts**：免费可商用中文字体
6. **VRoid Studio**：快速生成日系风格角色模型 → 导出为 VRM → 转换为 glb

---

## 当前灰盒资产说明

v0.1 使用 Godot primitive meshes 构建了可辨认的灰盒客厅：

- **地板**：8m×8m 米色平面
- **墙壁**：3面 + 天花板，淡暖色
- **沙发**：2m 长棕色方块
- **电视**：2.5m 宽黑色扁方块
- **Agent**：蓝色胶囊体身体 + 球体头部
- **物体**：彩色方块/圆柱（书=蓝色，奶茶=白色圆柱，植物=绿色圆柱）

所有物体位置已与 `SemanticWorld` 配置同步，换模型后无需修改代码。
