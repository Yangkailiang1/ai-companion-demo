# C6. 角色导入与人设定制

> 所属分支：C. AI 角色
> 节点编号：C6
> 状态：`[ACTIVE]`
> 依赖：T3（插件接口）、O2（导入工具）
> 最后更新：2026-07-28 | 基线程：v0.8.9

## 职责

让玩家可以导入自定义角色模型并创建人设包。

## 规划方向

### 模型格式

- 支持 GLB/GLTF，后续可选 VRM
- FBX/MMD 通过离线转换工具进入标准格式
- PMX 不直接进入 Godot；仅允许在本机隔离目录转换后验证
- 开源仓库只接收许可证允许修改和再分发的模型、贴图及动画

### 导入向导

- 检查比例、朝向、骨骼、材质、BlendShapes、动画和许可证
- 自动生成骨骼候选映射，用户可在 UI 中修正
- 导入后写入 `character_runtime_adapters.json`，剧情/认知层只使用语义动作和表情

### C6.2 运行时角色 manifest（v0.8.5 已完成三角色本地目录）

- version-1 manifest 声明 `agent_id`、显示名、身份、模型族、动作 clip、骨骼和 morph 映射
- `CharacterRuntimeBinding` 可在场景加载/卸载时动态注册/撤销角色
- ECNU 编剧提示和 StoryDirector cast 白名单从注册表动态读取角色
- 已验证共享 `idle/walk/wave/nod/think/happy/sit/talk` 与表情通道映射
- 已完成 22 个本地 Q 版包的逐包授权审计：9 个明确禁止游戏用途、12 个禁止
  再分发/商业使用、1 个授权不完整；全部移入本地隔离目录，未进入仓库
- 已验证 MMD Tools 4.5.10 + Blender 5 的 PMX → GLB、MMD 材质重建，以及
  272/652/495 骨骼和 37/69/70 Morph；受限转换产物由 Git 忽略
- `LocalCharacterSpawner` 只加载存在的本地 manifest，公开检出不会引用缺失资产
- 本地角色可自动进入 ECNU cast、通用 `@显示名` 路由和独立记忆分区
- 遐蝶、卡提希娅和相里要已经同时进入客厅，并通过多角色剧本闭环验收
- 尚未完成：PMX 批量转换 UI、自动骨骼候选生成和正式可再分发 Q 角色资产采购

### C6.3 `[DONE batch skill baseline]` 解耦人物资产接入

- `$prepare-character-model-assets` 已定义 GLB/GLTF/FBX/PMX/MMD/VRM/Blend 输入
  分流、公开/本地隔离、依赖审计、Blender 转换和 Godot 验收流程。
- 标准输出为 `model.glb + character manifest + provenance + 骨骼/Morph/动画清单
  + conversion report`；人物流水线只登记嵌入动作和 Morph，不在同一批次处理动作
  重定向或表情语义。
- DeepSeek/Claude Code 可按最多三个同格式/同骨架族角色批处理；Codex 负责许可证
  终审、近景视觉验收、公开目录晋级和 Git。
- `[NEXT]` 将清单和覆盖率报告固化为正式 JSON Schema，并增加自动骨骼候选生成器
  与 Godot 导入向导 UI。

### 人设包

- 包含身份、说话风格、边界、关系初始值、兴趣、日程和语音配置
- 角色包必须与存档分离，使升级模型不会清空角色记忆

## 相关节点

- [T3 插件接口](../T-runtime/T3-plugin-interface.md) — CharacterAdapter 导入接口
- [O2 导入工具](../O-opensource/O2-import-tools.md) — 角色导入向导
- [O4 开源治理与安全](../O-opensource/O4-governance-security.md) — 许可证和资产来源
- [Q 版角色资产审计](../../Q_CHARACTER_ASSET_AUDIT.md) — 当前 PMX 资产的本机使用边界

> 相关文档：[C 分支总览](./README.md)
