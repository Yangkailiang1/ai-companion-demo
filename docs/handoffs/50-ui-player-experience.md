# H50 — UI、镜头与玩家体验

> 路线图：S1.1-S1.5、P2、P3
> 建议分支：`feature/s1-player-experience`
> 目标：让项目从调试 Demo 变成可理解、可操作、响应式的游戏界面

## 文件所有权

允许主要修改：

- `scripts/ui/**`
- `scripts/camera/**`
- 新增 `scripts/player/**`
- `scenes/main.tscn`
- 新增 UI/玩家场景和主题资源
- S1/P2/P3 专项测试与文档

禁止修改：

- `scripts/core/cognitive_cycle.gd`
- `scripts/core/autonomous_behavior_system.gd`
- `scripts/directing/**`
- `scripts/navigation/**`
- `scripts/objects/**`
- `scenes/living_room.tscn` 的物理和语义节点

`chat_input.gd` 约 350 行。本任务先拆成 controller、presenter、theme/animation 等明确
职责，公共信号和节点路径保持兼容。

## 必须实现

### A. 响应式聊天 UI S1.1/S1.3

1. 消息按玩家/角色气泡显示，支持折叠历史。
2. 增加目标角色选择器，并显示当前对话对象。
3. 输入框获得焦点时：
   - 光标清晰闪动；
   - 键盘输入不控制相机/玩家；
   - 鼠标拖动不旋转房间；
   - Enter 发送、Esc 取消焦点。
4. AI 处理中显示非阻塞状态；错误和降级可读，不刷技术日志。
5. 支持 1280×720、1440×900、1920×1080、2560×1440、16:10 和高 DPI。
6. 文本与边框保持安全内边距，不裁切中文。

### B. 镜头模式 P2

1. 保留当前房间中心环绕相机作为 Director 模式。
2. 为后续第三人称建立独立 PlayerController 场景和输入映射。
3. 支持 Director/第三人称模式安全切换；第一人称可只建立接口与设置项。
4. 相机有碰撞、缩放限制、灵敏度和晕动减缓选项。
5. 切换模式时不改变角色世界状态，不丢失 UI 焦点状态。

### C. 玩家交互 P3 基线

1. 第三人称/导演模式提供统一交互射线或屏幕点选。
2. 高亮可交互物体，显示本地化动作提示。
3. 玩家拿取/放置调用与角色相同的物体交互公共协议。
4. 对角色点击/靠近可设为对话目标，不直接修改其记忆或关系。
5. 角色邀请发送结构化请求，由角色策略接受/拒绝，不强制执行。

## 自动化验收

新增 UI 和输入合同测试，至少验证：

1. 输入框聚焦后相机角度保持不变；
2. 失焦后相机输入恢复；
3. 目标选择只影响指定 Agent；
4. 连续快速发送不丢消息、不重复消息；
5. 窗口尺寸切换后关键控件仍在可视区域；
6. 模式切换不会保留错误的输入捕获；
7. 射线只返回已注册、可交互且未被 UI 遮挡的目标；
8. 无在线 AI 时错误状态可见且仍能退出/继续输入。

必须运行：

```bash
godot --headless --path . --script scripts/debug/camera_orbit_check.gd
godot --headless --path . --script scripts/debug/headless_check.gd
godot --headless --path . --script scripts/debug/multi_agent_check.gd
godot --headless --path . --script scripts/debug/experience_modes_check.gd
```

## 视觉验收

必须提交公开安全截图，不含本地受限模型：

- 1280×720；
- 1440×900；
- 2560×1440；
- 聊天历史展开/折叠；
- 角色目标选择；
- Director 与第三人称模式。

检查：

- 字体、边距、按钮热区和对比度；
- UI 与房间暖色风格一致；
- 控件动画 150-250 ms，不能妨碍输入；
- 不显示调试窗口标题、绝对文件路径、Key 或模型内部名。

## 交付物

- 拆分后的 UI 控制层；
- 响应式布局和主题资源；
- 玩家/镜头模式合同；
- 输入焦点回归测试；
- 多分辨率截图；
- 更新 S1/P2/P3 文档。
