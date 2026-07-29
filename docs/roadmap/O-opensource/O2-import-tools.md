# O2. 导入工具

> 所属分支：O. 开源与创作者生态
> 节点编号：O2
> 状态：`[ACTIVE tooling baseline]`
> 依赖：T3（插件接口）、C6（角色导入协议）
> 最后更新：2026-07-29 | 基线程：v0.8.9

## 规划方向

### 角色导入

- 角色导入向导、骨骼映射、动画覆盖率和表情预览

### 场景扫描

- 场景扫描器自动发现门、地面、障碍和可交互物体

### 检查报告

- 资产检查报告可在命令行和 Godot 编辑器中运行

### O2.1 `[DONE skill baseline]` 四类资产批处理

- 场景：`$download-open-3d-assets` → `$build-parametric-asset-library` → 可选
  `$godot-import-interactable-object`。
- 人物：`$prepare-character-model-assets`。
- 动作：`$prepare-motion-library-assets`。
- 表情：`$prepare-expression-library-assets`。
- 四类资产通过 Registry/Manifest/Adapter 解耦，批处理器不得直接修改认知、
  剧情、场景物理或 Git 历史。
- 统一格式矩阵和 DeepSeek 任务模板见
  [`ASSET_PIPELINE_CONTRACTS.md`](../../ASSET_PIPELINE_CONTRACTS.md) 与
  [`DEEPSEEK_ASSET_PIPELINE_HANDOFF.md`](../../DEEPSEEK_ASSET_PIPELINE_HANDOFF.md)。

### O2.2 `[ACTIVE character slice]` 机器可读 intake schemas

为人物包、动作包、表情包及批处理结果建立正式 JSON Schema、CLI 校验器和
Godot 编辑器预览入口。

- `[DONE character intake]` 人物包已有 Draft 2020-12 Schema、无第三方依赖 CLI
  和真实企鹅 intake；`public_redistributable` / `local_only` / `rejected`
  与 pipeline 状态分离，禁止自动化输出 `accepted`。
- 9 项正负例覆盖许可证 fail-closed、redistribution、SHA、缺文件、坏 JSON、
  `..`、反斜杠与符号链接越界、rejected 规则；真实企鹅包通过且保持
  `local_only`。
- `[NEXT]` 以相同结构补动作、表情和批处理结果 schema，再增加 Godot 编辑器
  只读预览入口。

### O2.3 `[DONE golden pipeline]` 安全资产发布黄金样例

- Poly Haven 三项 CC0 候选已验证 source ID 与 normalized ID 分离，大小写不会造成
  隔离目录解析失败。
- 发布器先验证许可证、provenance、GLTF 和依赖，再通过同文件系统 staging 与
  rollback 原子替换；缺失源不会破坏旧目标。
- 隔离 unittest 覆盖连续运行哈希一致、公开路径可迁移、`local_only` fail-closed
  和失败保留旧目标。真实三资产批次连续运行两次也得到相同 manifest/hash。
- 自动化只允许生成 `downloaded`/`inventoried` 候选；AABB、轴向和 Metal 视觉
  验收仍由 Codex 完成后才能晋级 `accepted`。
- 三个真实 Poly Haven 候选已完成 1280×720 Metal 批次预览和米制 AABB 测量；
  模型各自可用，但预览识别出复古桌、哥特椅、现代花瓶的风格不一致，因此停在
  `previewed`，验证了视觉门槛能够阻止“技术通过即生产 accepted”。
- `test_asset_metadata_contracts.py` 将人物 provenance、Morph 数量、表情候选
  非回退、动作 fixture、公开路径与三资产 AABB/SHA 状态纳入 203 行的参数化
  回归测试；与原子发布器测试合计 12 项通过。DeepSeek 首次压缩曾弱化 AABB
  断言，Codex 验收后已改为缺字段即失败，作为后续批处理的强制质量门。

## 相关节点

- [C6 角色导入与人设定制](../C-characters/C6-character-import.md) — 角色导入的 UI 侧
- [T3 插件接口](../T-runtime/T3-plugin-interface.md) — 导入的接口标准

> 相关文档：[O 分支总览](./README.md)
