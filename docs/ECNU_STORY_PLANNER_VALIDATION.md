# ECNU 动态剧情编排真实验证

> 对应需求：D3（自然语言转剧本）、D2（导演执行）、X3（AI Provider）
> 验证日期：2026-07-27
> 模型：`ecnu-max`，OpenAI 兼容接口

## 结论

真实 ECNU 请求已经完成“自然语言剧本 → 动态 Story JSON → 本地安全校验 →
Godot 双角色演出 → 每角色剧情记忆”的端到端闭环。验证使用的剧本没有预先
保存在 `data/stories/`，模型需要自行选择角色、Beat、走位、动作、表情、
对白与物体交互。

API Key 只从 `data/llm_config.json` 读取，测试日志和本文件均不记录密钥。

## 验证场景

### 电视邀约

输入描述诀有点累，咕咕嘎嘎邀请她一起看电视。

一次成功输出：

- 标题：`傍晚的电视邀约`
- cast：`jue_agent`、`main_agent`
- 14 个 Beat
- 包含挥手、思考、点头、开电视、双人不同沙发站位、坐下和回应
- Schema 自动修复 1 次
- 导演成功完成，双角色分别写入剧情记忆

### 浇水与读书

输入明确要求诀提醒植物缺水、咕咕嘎嘎浇水、诀随后读一会儿书。

成功输出：

- 标题：`小绿浇水记`
- cast：`jue_agent`、`main_agent`
- 10 个 Beat
- 明确包含 `plant.water`
- 明确包含 `book.read`
- 两名角色选择不同的沙发站位
- Schema 自动修复 0 次，网络重试 0 次
- 世界物体状态和双角色剧情记忆均由真实导演链路更新

## 真实输出暴露并修复的问题

| 问题 | 原因 | 处理 |
|---|---|---|
| `"say": ""` 被 Schema 拒绝 | ECNU 会把未使用字段输出为空字符串 | Schema 前仅删除空的可选字段，能力和目标仍严格校验 |
| 角色走向沙发时卡住 | 语义交互点过于靠近碰撞边界 | 沙发交互点移到可导航的前方站位 |
| 两名角色临时互相挡路 | 顺序规划可能让先到角色站在后到角色路径上 | 演出期间仅对 cast 角色添加彼此碰撞例外，结束/取消后恢复 |
| 剧情对白触发额外社交 LLM | SocialSystem 不知道导演拥有对白控制权 | 演出模式禁止自发社交回复和 Idle/Simulation 认知旁路 |
| ECNU 偶发 `HTTP 0` | 服务响应或连接瞬时超时 | 单次 60 秒窗口，最多一次独立传输重试 |

## 规划质量验收

真实测试不仅检查 JSON 可解析，还检查：

- 两名指定角色都进入 cast 且至少各有一个 Beat；
- 计划包含走位、身体/表情表现和对白；
- `memory_summary` 非空；
- 输入明确要求“浇水”时必须存在 `plant.water`；
- 输入明确要求“读一会儿书”时必须存在 `book.read`；
- Director 最终无错误，并在每名角色的定长记忆中找到本次剧情总结。

## 运行方式

使用内置电视邀约：

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path . \
  --script scripts/debug/ecnu_live_story_check.gd
```

使用任意新剧本：

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path . \
  --script scripts/debug/ecnu_live_story_check.gd -- \
  "咕咕嘎嘎邀请诀一起照顾盆栽，然后两人去沙发休息。"
```

该脚本会产生真实 API 请求，日常 CI 应继续使用
`experience_modes_check.gd` 的离线注入验收，避免网络和成本导致不稳定。
