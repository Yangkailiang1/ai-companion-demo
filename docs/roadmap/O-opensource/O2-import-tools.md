# O2. 导入工具

> 所属分支：O. 开源与创作者生态
> 节点编号：O2
> 状态：`[ACTIVE tooling baseline]`
> 依赖：T3（插件接口）、C6（角色导入协议）
> 最后更新：2026-07-28 | 基线程：v0.8.9

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

### O2.2 `[NEXT]` 机器可读 intake schemas

为人物包、动作包、表情包及批处理结果建立正式 JSON Schema、CLI 校验器和
Godot 编辑器预览入口；当前 Skill 合同先作为可执行基线。

## 相关节点

- [C6 角色导入与人设定制](../C-characters/C6-character-import.md) — 角色导入的 UI 侧
- [T3 插件接口](../T-runtime/T3-plugin-interface.md) — 导入的接口标准

> 相关文档：[O 分支总览](./README.md)
