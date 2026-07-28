# T3. 插件接口

> 所属分支：T. Runtime 主干
> 节点编号：T3
> 状态：`[NEXT]`
> 依赖：T1（认知协议）、T2（语义世界）
> 最后更新：2026-07-24 | 基线程：v0.7

## 职责

定义开放、稳定的插件接口，让创作者可以接入新角色、新场景和新能力，而无需修改核心 Runtime 代码。

## 规划节点

### 已定义的适配器接口

- `CharacterAdapter`：角色模型、骨骼、动画、表情的接入适配器
- `SceneAdapter`：场景加载、物体注册、导航区域的管理接口
- `MotionProvider`：动作生成/查询的标准接口
- `ExpressionProvider`：表情驱动的标准接口
- `VoiceProvider`：语音合成/识别的标准接口

### 核心约束

- 核心 Runtime 不直接依赖企鹅、诀、客厅或 ECNU 服务
- 所有扩展通过资源文件、注册表和稳定信号接入
- 插件不能绕过 T1（认知协议）直接操作角色状态

### T3.1 `[NEXT]` 插件注册与发现

定义插件 Manifest 格式、加载流程和冲突检测。

### T3.2 `[NEXT]` 适配器生命周期

插件加载、初始化、启用、禁用和卸载的生命周期管理。

### T3.3 `[LATER]` 插件沙箱

限制插件对文件系统、网络和 Godot 节点的访问权限。

## 依赖关系

```
T3 插件接口 + X1 迁移 + X2 测试 ──> O1 开源 Runtime
```

## 相关节点

- [O1 Godot 插件化 Runtime](../O-opensource/O1-runtime-plugin.md) — 插件化的外部发布实现
- [C6 角色导入与人设定制](../C-characters/C6-character-import.md) — 依赖 CharacterAdapter 接口
- [X5 发布与诊断](../X-engineering/X5-release-diagnostics.md) — 插件配置隔离

> 相关文档：[T 分支总览](./README.md) · [O 分支 开源与创作者生态](../O-opensource/)
