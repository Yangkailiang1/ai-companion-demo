# DeepSeek / Claude Code 资产批处理交接

DeepSeek 每次只接收一个小批次，并显式调用对应 Skill。不要让一个任务同时下载
场景、转换人物、重定向动作和映射表情。

## 场景素材批次

```text
使用 $download-open-3d-assets 审计并下载 3 个同风格 CC0 室内模型。
通过后使用 $build-parametric-asset-library 规范化为 Godot Asset Registry 候选。
如果物体可交互，再使用 $godot-import-interactable-object。
只输出候选文件和验收报告，不提交 Git。
```

需要：官方许可页面、GLB/GLTF/贴图或可转换 FBX/OBJ、目标用途和风格标签。

## 人物模型批次

```text
使用 $prepare-character-model-assets 处理指定目录中最多 3 个同格式角色包。
逐个分类 public_redistributable/local_only/rejected，生成 GLB、角色 manifest、
骨骼/Morph/动画清单和转换报告。不要修改动作库、表情库或核心 Runtime。
```

需要：完整压缩包、readme/许可证、贴图、PMX/FBX/VRM/GLB 主文件。PMX 与授权
受限模型只能输出到 `assets/local_characters/`。

## 动作库批次

```text
使用 $prepare-motion-library-assets 处理最多 5 条同源动作。
输出角色无关 Motion Package、元数据和验证报告；按指定目标骨架生成烘焙候选，
但不要直接加入 motion_catalog 或覆盖角色模型。
```

需要：HumanML3D NPY、BVH、body VMD 或动画 FBX/GLB；还需许可证、FPS、骨架
说明、动作文本、循环/root motion 预期和目标骨架 map。

## 表情库批次

```text
使用 $prepare-expression-library-assets 提取最多 3 个角色的 Morph/BlendShape。
输出共享语义覆盖率和每角色 channel_map 候选，验证真实权重变化与 neutral reset。
不要修改身体动作、人物网格或 LLM 提示。
```

需要：带 Morph 的 GLB/FBX/PMX/VRM 或 facial VMD、许可证、Morph 名单、目标
语义表情与口型集合。

## DeepSeek 返回格式

每个任务最终必须返回：

1. accepted / quarantined / rejected 文件清单；
2. 许可证证据和 SHA-256；
3. 新增/修改文件；
4. 执行的验证命令及退出码；
5. 截图或预览路径；
6. 未猜测、需要 Codex 决策的事项。

禁止事项：提交或推送 Git、读取 `data/llm_config.json`、把本地受限模型移入公开
目录、按文件名猜骨骼/Morph 语义、绕过许可证或视觉验收。
