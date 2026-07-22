# AI Companion Demo — 主开发进展

> Godot 4.6.1 | GDScript | ECNU-Max (DeepSeek V4 Flash)（可选）

## 项目定位

**双层架构**：
- **Demo 层**：客厅养成陪伴游戏（AI 数字人"小叶子"）
- **Runtime 层**：Living Agent Runtime — 可复用智能体运行时

设计文档：`/Users/yangkailiang/Documents/ai_games/设计方案/AI养成陪伴游戏_设计方案.md`

## 当前状态（v0.5 — 离线动作库预览 + UI/场景美化准备）

| 模块 | 状态 | 文件 |
|------|------|------|
| MessageBus | done (含 performance_cue 信号) | `scripts/core/message_bus.gd` |
| WorldSimulator | done (含需求冷却) | `scripts/core/world_simulator.gd` |
| SemanticWorld | done | `scripts/core/semantic_world.gd` |
| MemorySystem | stub (Episode 存储 OK，Reflection 未实现) | `scripts/core/memory_system.gd` |
| CodifiedProfile | done (关键词匹配) | `scripts/core/codified_profile.gd` |
| CognitiveCycle | done (LLM + 本地 fallback + gesture) | `scripts/core/cognitive_cycle.gd` |
| GOAPPlanner | done (10 goal blueprints + validated dynamic plan) | `scripts/core/goap_planner.gd` |
| ActionExecutor | done (11 primitives + performance cues) | `scripts/core/action_executor.gd` |
| AgentBase | done (NavMesh + walk/idle cues) | `scripts/characters/agent_base.gd` |
| **CharacterAnimationDriver** | **new v0.2** | `scripts/characters/character_animation_driver.gd` |
| **PerformanceCueTypes** | **new v0.2** | `scripts/core/performance_cue_types.gd` |
| AnimationController | done (程序化 fallback) | `scripts/characters/animation_controller.gd` |
| InteractableObject | done | `scripts/objects/interactable_object.gd` |
| ChatInput + HUD | done (v0.6 visual pass) | `scripts/ui/chat_input.gd` |
| DialogueBubble | done | `scripts/ui/dialogue_bubble.gd` |
| 3D 场景 | done (企鹅 GLB + Poly Haven 家具/PBR 客厅美化) | `scenes/living_room.tscn` |
| **幻想庭院预览** | **new v0.2** | `scenes/environments/endless_garden_preview.tscn` |
| **晓光忆时摄影棚预览** | **new v0.6 candidate** | `scenes/environments/xiaoguang_yishi_preview.tscn` |
| **空间自主与导航** | **done v0.3** | `scripts/navigation/`, `docs/SPATIAL_AUTONOMY.md` |
| **动作/表情轻量路由** | **done v0.5** | `motion_intent_router.gd`, `expression_driver.gd`, `data/*catalog.json` |
| **Light-T2M / 离线动作库实验桥** | **offline retarget package + smoke clip done; real samples pending GPU** | `motion_lab/`, `docs/LIGHT_T2M_INTEGRATION.md`, `docs/OFFLINE_MOTION_LIBRARY.md` |
| **Blender 导出管线** | **new v0.2** | `tools/blender/` |
| **Smoke Test** | **new v0.2** | `scripts/debug/smoke_test_gestures.gd` |
| 主场景编排 | done (CanvasLayer UI + WorldRoot) | `scenes/main.tscn` |
| 数据配置 | done | `data/` |
| 架构文档 | done | `docs/PROJECT_ARCHITECTURE.md` |
| 资产需求 | done | `docs/ASSET_REQUIREMENTS.md` |
| **动作管线文档** | **new v0.2** | `docs/CHARACTER_ACTION_PIPELINE.md` |
| **资产来源文档** | **new v0.2** | `docs/ASSET_PROVENANCE.md` |

### v0.1 垂直切片关键修复

- 修复 `living_room.tscn` 12 处 `Transform3D` 退化基矩阵
- 合并 `SignalBus` → `MessageBus`（7→6 Autoloads）
- 移除 `agent_base.gd` 中不存在的 `AnimationTree` 引用
- 重构主场景：`CanvasLayer` + HUD + 紧凑聊天面板 + 底部输入栏
- `CognitiveCycle` 本地 fallback：关键词匹配回复 + 需求驱动决策
- 自主事件冷却：自动触发 15s 间隔，需求阈值 120s 冷却（防刷屏）
- 修正时间单位：现实 5 分钟 = 游戏 1 小时（不再错误地每秒推进 12 游戏小时）
- `AgentBase` NavMesh fallback：无 NavMesh 时直接位置插值移动（不卡死）
- `ActionExecutor` 每轮完成后释放，避免长时间聊天产生节点泄漏
- 玩家输入忙时进入 FIFO 队列，不再静默丢失；UI 明确显示在线 AI、本地规则、排队和思考状态
- 明确指令由 Runtime 约束 Goal（如“看电视”固定为 `watch_tv`），LLM 负责自然回复
- 修正奶茶效果方向（恢复饱腹度而非让角色更饿），自主发言间隔调整为 90–150 秒
- 移除遮挡摄像机的天花板，重新布局家具、补充环境光和 4× MSAA

## 数据流

```
WorldSimulator(_process) → needs decay → MessageBus (cooldown-gated)
Player Input → ChatInput → MessageBus
Agent IdleTimer 30-60s → MessageBus
    ↓
CognitiveCycle: Perception → Memory → Codified → LLM/Fallback → GOAP → ActionExecutor
    ↓
AgentBase: navigate (NavMesh or direct-fallback) / interact / speak / idle
    ↓
UI: ChatLog + HUD (needs bars) + 3D Bubble
```

## Autoload（6 个）

```
MessageBus → WorldSimulator → SemanticWorld → MemorySystem → CodifiedProfile → CognitiveCycle
```

## 已完成验证

- [x] GDScript parse error 修复（chat_input dead code 移除）
- [x] Scene Transform3D degenerate basis 修复（12 处）
- [x] affordance_types.gd `socail` typo → `social`
- [x] 灰盒客厅可渲染（8m×8m, 3墙+地板+天花板, 5 物体, 1 Agent）
- [x] 玩家输入 → Agent fallback 回复
- [x] 自动化 fallback smoke test：输入框提交 → ChatLog → Agent 回复 → 动作队列
- [x] 需求系统运行（hunger/energy/fun/social decay + HUD 实时更新）
- [x] Agent 移动（直接插值 fallback, 无需 NavMesh）
- [x] Godot headless 主场景实例化与 7 个动画检查
- [x] Blender 5.0 导出 + Godot GLB 导入（企鹅、庭院）
- [x] 中文动作指令 → performance cue → AnimationPlayer 自动化验收
- [x] 1280×720 主场景截图验收：企鹅模型、HUD、输入框可见

## v0.2 新能力

- [x] Performance Cue 统一协议：`MessageBus.performance_cue`（idle/walk/wave/nod/think/happy/sit/talk）
- [x] CharacterAnimationDriver 独立适配器（跨入 CognitiveCycle 和 ActionExecutor）
- [x] LLM JSON schema 增加 `gesture` 字段，Runtime 校验未知 gesture
- [x] 本地 fallback 支持 4 个显式测试句（挥挥手→wave, 点点头→nod, 想一想→think, 开心一点→happy）
- [x] AgentBase 根据 is_moving 自动切换 idle/walk cue
- [x] ActionExecutor 在 SPEAK/SIT 时发出对应 cue（IDLE 不抢占显式 one-shot 动作）
- [x] Blender 导出管线：`export_penguin.py` + `generate_penguin_animations.py` + `export_garden.py`
- [x] 7 个程序化骨骼动画生成脚本（idle/walk/wave/nod/think/happy/sit）
- [x] 幻想庭院预览场景 `scenes/environments/endless_garden_preview.tscn`
- [x] 文档：CHARACTER_ACTION_PIPELINE.md, ASSET_PROVENANCE.md
- [x] FIFO 队列保留（v0.1 已有，v0.2 未退化）

## v0.3 空间自主状态

- [x] Blender 导出脚本已生成 penguin.glb + garden.glb
- [x] penguin.glb 已替换主场景 Capsule/Sphere 灰盒
- [x] GLB 自带 AnimationPlayer 已由 CharacterAnimationDriver 自动发现
- [ ] 配置 `data/llm_config.json` 后端到端 LLM + gesture 测试
- [x] 客厅程序化 NavigationRegion3D（家具障碍、巡逻和闲逛路径）
- [ ] 庭院 NavigationRegion3D 烘焙
- [ ] 添加外部 3D 资产替换灰盒家具（沙发、电视、茶几等）

## v0.4 动作与表情桥

- [x] 动作库/表情库 JSON 与中英文确定性路由
- [x] HumanML3D 22 关节到企鹅核心骨骼映射（仅重定向输入，不可直接赋值播放）
- [x] Godot Morph Target 表情驱动：joy/angry/blink/基础口型
- [x] 未知明确动作生成请求保留 Light-T2M prompt，并使用安全动作回退
- [x] `motion_lab/` 服务器合同、环境探测、输入/输出校验和官方采样批处理包装
- [x] 完成 `(T,22,3)` 到角色无关离线 retarget package 的第一版
- [x] 烘焙 `offline_smoke_walk` 到 `penguin.glb` 并接入 Router/Godot 白名单
- [ ] 在 Linux NVIDIA 服务器用官方 `hml3d.ckpt` 生成 5–10 条真实样本
- [ ] 将真实样本批量 retarget、视觉验收并扩充 `motion_catalog.json`

## 动作库后续任务记录

- [ ] 用真实 HumanML3D/Light-T2M `.npy` 替换 smoke fixture，生成 5–10 个语义明确的动作包
- [ ] 增强 `tools/blender/bake_retarget_package.py`：目标骨骼 rest-pose 对齐、关节限幅、足锁、root motion 选择
- [ ] 建立动作验收清单：骨骼长度误差、脚滑、朝向、穿模、循环衔接、表情搭配
- [ ] 将通过验收的动作加入 `data/motion_catalog.json` 与 `PerformanceCueTypes`
- [ ] 后续若切换角色/动作模型，只新增对应 bone map 与 baker adapter，不改 Godot Runtime 主链路

## UI/场景美化方向

- [x] 验证 `终幕喑哑之庭` / `endless_garden_preview.tscn` 在 Godot 中可导入、实例化、渲染
- [x] 验证 `晓光忆时.zip`：源 `.blend` 可用 Blender 5 打开并导出 GLB，Godot 4.6.1 可导入/实例化/基础渲染
- [x] 改造主场景 UI：更清晰的聊天面板、状态栏、输入框层级、可读字体与分辨率适配
- [x] 客厅第一轮美化：暖光、补光、窗光、地毯、柔和材质、相机微调
- [x] 客厅第二轮美化：默认隐藏空聊天面板、电视屏幕微光、墙面装饰、初始画面更干净
- [x] 客厅第三轮美化：下载 Poly Haven CC0 家具与 PBR 贴图，替换灰盒沙发/茶几/电视/绿植，新增书架/吊灯/相框，地板/墙面/地毯绑定 1K PBR
- [ ] 评估是否把客厅灰盒替换为庭院/晓光忆时新场景，或先作为独立预览/约会地点切换
- [ ] 处理庭院材质：透明叶片、贴图色彩、灯光、相机 framing、导航区域/手工 waypoint
- [ ] 处理晓光忆时材质：源包标注 Blender 3.6 专用；当前 Blender 5 → GLB 只能保留基础几何/部分材质，若要接近原始预览图，需要用 Blender 3.6 重导、烘焙贴图/光照，或在 Godot 手工重建灯光/体积光/窗光
- [ ] 下一轮 UI：聊天面板折叠/展开、消息气泡化、场景切换入口、移动端比例检查

## 后续版本路线

| 版本 | 内容 |
|------|------|
| v0.1 | 核心闭环 → done（可运行垂直切片） |
| v0.2 | **角色模型集成 + 动作管线** → **完成并通过 Godot 自动化与截图验收** |
| v0.3 | **空间自主：NavMesh、巡逻、闲逛、结构化计划** → done |
| v0.4 | **动作/表情库路由 + Light-T2M 服务器实验桥** → baseline done |
| v0.5 | Light-T2M 离线重定向闭环 + 动作库预览 → smoke done，真实样本 pending |
| v0.6 | UI/场景美化 + 长期记忆/Reflection |
| v0.7 | 多 Agent + CASCADE 协调 + 本地小模型 |

## 知识库

- [KB-00 总索引](./docs/KB-00-overview.md)
- [KB-01 系统架构](./docs/KB-01-architecture.md)
- [KB-02 论文引用](./docs/KB-02-papers.md)
- [KB-03 实现细节](./docs/KB-03-implementation.md)
- **[PROJECT_ARCHITECTURE](./docs/PROJECT_ARCHITECTURE.md)** — 完整架构文档 (v0.1 新增)
- **[ASSET_REQUIREMENTS](./docs/ASSET_REQUIREMENTS.md)** — 资产需求清单 (v0.1 新增)

## LLM 配置（可选）

无 `data/llm_config.json` 时使用本地 fallback。配置后自动切换完整 LLM 推理：

- **API**: `https://chat.ecnu.edu.cn/open/api/v1` (OpenAI 兼容)
- **模型**: `ecnu-max` → DeepSeek V4 Flash
- **格式**: OpenAI Chat Completions
- 配置模板见 `data/llm_config.json.example`

## 快速启动

### Godot 运行

1. 用 Godot 4.6.1 打开 `project.godot`
2. 按 F5 运行，看到企鹅角色 + 灰盒客厅 + 左上角 HUD + 左下聊天面板 + 底部输入栏
3. 在底部输入框打字并回车或点"发送"
4. 小叶子会回复并可能执行动作（喝奶茶、看电视等）
5. 可选：创建 `data/llm_config.json` 启用完整 AI 推理

### v0.2: Blender 资产管线（已执行）

```bash
# 1. 导出企鹅模型 + 生成动画
/Applications/Blender.app/Contents/MacOS/Blender --background /Users/yangkailiang/Documents/ai_games/model/extracted/penguin.blend --python tools/blender/export_penguin.py
/Applications/Blender.app/Contents/MacOS/Blender --background /Users/yangkailiang/Documents/ai_games/model/extracted/penguin.blend --python tools/blender/generate_penguin_animations.py

# 2. 导出庭院场景
/Applications/Blender.app/Contents/MacOS/Blender --background /Users/yangkailiang/Documents/ai_games/scene/extracted/garden.blend --python tools/blender/export_garden.py

# 3. Godot 会自动导入 GLB；两个 PackedScene 已在对应 .tscn 中完成实例化

# 3b. 导出/预览晓光忆时摄影棚（源包 readme 标注 Blender 3.6 专用，Blender 5 导出只作为几何验证）
/Applications/Blender.app/Contents/MacOS/Blender --background "/private/tmp/xiaoguang_yishi_extract/撮影スタジオblender版 配布用.blend" --python tools/blender/export_xiaoguang_yishi.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /private/tmp/ai_companion_godot_xiaoguang.log --path . --script scripts/debug/xiaoguang_scene_check.gd

# 3c. 下载客厅家具与 PBR 贴图（Poly Haven CC0, 1K）
python3 tools/assets/download_polyhaven_models.py
python3 tools/assets/download_polyhaven_textures.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /private/tmp/ai_companion_polyhaven_bounds.log --path . --script scripts/debug/polyhaven_asset_bounds_check.gd

# 4. 验证
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script scripts/debug/headless_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script scripts/debug/gesture_pipeline_check.gd
```
