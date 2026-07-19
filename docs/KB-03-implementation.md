# KB-03: 实现细节

## Primitive Actions (8个)

| # | Action | 参数 | 说明 |
|---|--------|------|------|
| 1 | NAVIGATE | target: object_id | NavAgent3D 寻路 |
| 2 | INTERACT | object, verb | verb 来自 affordance 表 |
| 3 | SPEAK | text, tone | 对话气泡 (非阻塞) |
| 4 | IDLE | duration: sec | 待机动画 |
| 5 | LOOK_AT | target: id | 转向 |
| 6 | PICK_UP | object | 拿起 |
| 7 | PUT_DOWN | object | 放下 |
| 8 | SIT | object | 坐下/站起 |

## GOAP Goal 蓝图（goal_blueprints）

| Goal | Action Chain |
|------|-------------|
| drink_milk_tea | NAVIGATE→PICK_UP→INTERACT(drink)→PUT_DOWN |
| watch_tv | NAVIGATE→INTERACT(turn_on)→IDLE(5s)→INTERACT(turn_off) |
| read_book | NAVIGATE→PICK_UP→INTERACT(read)→PUT_DOWN |
| water_plant | NAVIGATE→INTERACT(water) |
| rest_on_sofa | NAVIGATE→SIT→IDLE(8s) |

new Goal → GOAP 自动生成 `auto_plan()` 或 fallback 到 IDLE

## LLM 协议

**请求** (OpenAI 兼容):
```json
{
  "model": "ecnu-max",
  "messages": [
    {"role": "system", "content": "你是游戏角色AI大脑。只输出纯JSON。"},
    {"role": "user", "content": "<prompt>"}
  ],
  "max_tokens": 300, "temperature": 0.7
}
```

**期望响应**:
```json
{"thought":"...","goal":"watch_tv","goal_reason":"...","emotion":"happy","emotion_intensity":0.6,"speech":"好的呀~","speech_tone":"cheerful"}
```

容错：自动去除 `\`\`\`json` 标记、提取{...}子串、验证 goal/speech 字段

## 记忆检索公式 [GA §4.2.2]

```
score(m) = α × exp(-age/24h) + β × importance/10 + γ × word_overlap(query, content)
```

默认 α=β=γ=1.0。反思阈值 = 150（累计 importance）

## Needs 系统 [WorldSimulator]

| Need | 方向 | 衰减/增长 | 阈值 |
|------|------|----------|------|
| hunger | ↓ | -5/游戏小时 | <30 触发 |
| energy | ↓ | -3/游戏小时 | <20 触发 |
| social | ↓ | -2/游戏小时 | <20 触发 |
| fun | ↓ | -3/游戏小时 | <20 触发 |
| bladder | ↑ | +8/游戏小时 | >80 触发 |

交互效果：`{hunger: -15, fun: +10}` → Simulator.apply_effect()

## Codified Profile 规则

角色配置：`data/character_config.json`
- 5 条确定性规则 (if-then-else)
- 1 条概率规则 (random_prob=0.3 奶茶情结)
- 8 条种子记忆 (seed_memories)
- check_condition 用关键词匹配（不调LLM）
