# 解耦资产流水线合同

> Roadmap：S4、C2、C3、C6、O2、O4
> 最后更新：2026-07-28

项目把外部素材拆成四类独立输入。素材下载、转换、语义映射和 Godot 接入不能在
一个批处理中混做；四条流水线只能通过版本化 Manifest、Registry 和 Adapter 合同
连接。

## 总体边界

```text
场景素材 -> Asset Registry -> Scene Recipe -> Generated Manifest
人物模型 -> Character Manifest -> Skeleton/Material Runtime Adapter
动作素材 -> Canonical Motion Package -> Skeleton Retarget -> clip_map
表情素材 -> Semantic Expression Library -> character channel_map
```

LLM、记忆、人格、剧情导演和物理世界只消费稳定语义 ID，不依赖文件名、模型骨骼
名或 Morph 名。更换角色、动作库或房间素材时，不得修改认知主链路。

## 输入和输出矩阵

| 流水线 | 首选输入 | 可转换输入 | 禁止直接运行 | 标准输出 |
|---|---|---|---|---|
| 场景 | GLB；GLTF+BIN+贴图；PNG/PBR | FBX、OBJ、Blend | ZIP、未知脚本、角色骨架 | provenance、Asset Registry、碰撞/锚点、预览 |
| 人物 | 带骨架/材质/Morph 的 GLB | GLTF、FBX、PMX/MMD、VRM、Blend | PMX/VRM 原包直接进 Godot | model.glb、Character Manifest、骨骼/Morph/动画清单 |
| 动作 | HumanML3D `(T,22,3)` NPY | BVH、body VMD、动画 FBX/GLB | 未重定向数组直接写目标骨骼 | Motion Package、目标骨架烘焙 clip、catalog 元数据 |
| 表情 | GLB Morph/BlendShape | VRM 表情、FBX Morph、PMX Morph、facial VMD | 模型专属 Morph 名进入共享库 | expression entry、每角色 channel_map、覆盖率报告 |

## 许可分层

- `public_redistributable`：许可证明确允许修改和再分发，可进入公开仓库。
- `local_only`：用户本机可以使用，但源文件、转换产物和贴图必须位于 Git 忽略目录。
- `rejected`：游戏用途、转换、再分发或来源不明确，不进入任何自动化接入步骤。

“免费下载”不等于可再分发。每个文件必须保留官方页面、许可证、作者/提供方、
访问日期、源文件 SHA-256 和转换输出 SHA-256。

## 批处理原则

1. 每批只处理一种资产类别、一个来源、一个许可证和一个格式族。
2. 场景/人物每批最多 3 个；动作最多 5 条；表情最多 3 个角色或 1 个表情包。
3. 失败按单个资产隔离，输出 downloaded/inventoried/candidate/quarantined/rejected
   列表；DeepSeek 不输出 accepted。
4. DeepSeek/Claude Code 只负责审计、提取、转换、生成候选配置和测试证据。
5. Codex 负责许可证终审、视觉验收、目录晋级、路线图状态、提交和推送。
6. 测量、轴向与预览状态必须绑定源 SHA-256；同名文件内容变化后退回 inventoried。

## 对应 Skills

| 资产类别 | Skill 链 |
|---|---|
| 场景 | `$download-open-3d-assets` → `$build-parametric-asset-library` → 可选 `$godot-import-interactable-object` |
| 人物 | `$prepare-character-model-assets` |
| 动作 | `$prepare-motion-library-assets` |
| 表情 | `$prepare-expression-library-assets` |

## 验收证据

每批必须提供机器可读或清晰文本报告，至少包含：

- 输入与输出路径、字节数、SHA-256、许可证分类；
- 依赖/贴图/骨骼/Morph/动画清单；
- 坐标系、单位、前向轴、上轴、FPS 等适用元数据；
- 执行命令、退出码、测试结果和失败原因；
- 可视资产的截图路径；
- 未解决风险和需要 Codex 判断的项目。
