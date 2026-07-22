# cognitive_cycle.gd — 认知循环主控制器 (Autoload)
# 设计文档 §二：感知 → 记忆检索 → Codified Logic → LLM → GOAP → 执行
# 参考 [GA §4] + [CCL §3]

extends Node

const MotionIntentRouterScript = preload("res://scripts/characters/motion_intent_router.gd")

# LLM API 配置
var llm_api_url: String = ""
var llm_api_key: String = ""
var llm_model: String = "ecnu-max"
var llm_provider: String = "openai"  # "openai" | "anthropic"

# 当前是否正在处理
var is_processing: bool = false
var _pending_player_triggers: Array[Dictionary] = []
# 自动触发冷却（防止刷屏）
var _last_auto_trigger_time: float = 0.0
const AUTO_TRIGGER_COOLDOWN: float = 15.0  # 秒

# HTTP 请求节点
var http_request: HTTPRequest

# 当前触发上下文
var current_trigger: Dictionary = {}
var _motion_router

# 本地 fallback 响应库（无 LLM 时使用）
const FALLBACK_GREETINGS = [
	"你好呀！今天天气真好~",
	"嗨！你来啦！",
	"嘿嘿，正想找人聊聊天呢！",
	"哎呀，欢迎欢迎～"
]
const FALLBACK_IDLE_COMMENTS = [
	"嗯…有点无聊呢。",
	"（伸了个懒腰）",
	"要不要看会儿电视？",
	"那杯奶茶看起来好诱人啊…"
]
const FALLBACK_HUNGRY_COMMENTS = [
	"肚子有点饿了…那杯奶茶正好！",
	"好想喝点东西…",
]
const FALLBACK_BORED_COMMENTS = [
	"有点无聊，看看电视吧。",
	"找本书看看也不错。",
]


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_motion_router = MotionIntentRouterScript.new()
	if not _motion_router.is_ready():
		push_warning("CognitiveCycle: motion router catalog unavailable: %s" % _motion_router.load_error)
	_load_llm_config()

	# 创建 HTTP 请求节点
	http_request = HTTPRequest.new()
	http_request.timeout = 20.0
	add_child(http_request)
	http_request.request_completed.connect(_on_llm_response)

	# 监听所有触发源
	MessageBus.agent_trigger_cycle.connect(_on_trigger)


func _load_llm_config():
	var path = "res://data/llm_config.json"
	if not FileAccess.file_exists(path):
		print("[CognitiveCycle] llm_config.json not found, using local fallback mode")
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if not file: return
	var content = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(content) == OK:
		var cfg = json.get_data()
		llm_api_url = cfg.get("api_url", llm_api_url)
		llm_api_key = cfg.get("api_key", llm_api_key)
		llm_model = cfg.get("model", llm_model)
		llm_provider = cfg.get("provider", llm_provider)
		print("[CognitiveCycle] LLM configured: %s/%s" % [llm_provider, llm_model])


# === 主入口：触发源到达 ===

func _on_trigger(agent_id: String, source: AffordanceTypes.TriggerSource, data: Dictionary) -> void:
	if is_processing:
		# 玩家输入不能静默丢失；自主触发在忙碌时可以安全跳过。
		if source == AffordanceTypes.TriggerSource.PLAYER_INPUT:
			_pending_player_triggers.append({"agent_id": agent_id, "source": source, "data": data.duplicate(true)})
			MessageBus.ui_status_changed.emit("AI 正忙，你的消息已排队（%d）" % _pending_player_triggers.size(), "queued")
		return

	# Autonomous thoughts never interrupt a physical task selected by the player.
	# Player messages remain allowed and use AgentBase's latest-decision-wins policy.
	if source in [AffordanceTypes.TriggerSource.SIMULATION, AffordanceTypes.TriggerSource.IDLE_TIMER] and _is_agent_busy(agent_id):
		return

	# 自动触发冷却（玩家输入不受限制）
	if source in [AffordanceTypes.TriggerSource.SIMULATION, AffordanceTypes.TriggerSource.IDLE_TIMER]:
		var now = Time.get_unix_time_from_system()
		if now - _last_auto_trigger_time < AUTO_TRIGGER_COOLDOWN:
			return
		_last_auto_trigger_time = now

	is_processing = true
	current_trigger = {"agent_id": agent_id, "source": source, "data": data}
	if source == AffordanceTypes.TriggerSource.PLAYER_INPUT:
		MessageBus.ui_status_changed.emit("AI 正在理解：%s" % data.get("text", "").left(24), "thinking")
	else:
		MessageBus.ui_status_changed.emit("小叶子正在自主思考…", "thinking")

	# Step 1: Perception — 世界语义快照
	var semantic_snapshot = SemanticWorld.generate_semantic_snapshot(agent_id)

	# Step 2: Memory Retrieval — 检索相关记忆
	var player_message = ""
	if source == AffordanceTypes.TriggerSource.PLAYER_INPUT:
		player_message = data.get("text", "")
		if not player_message.is_empty():
			MemorySystem.add_episode("玩家说: %s" % player_message, 6.0)

	var memory_context = MemorySystem.format_for_llm(player_message)

	# Step 3: Codified Profile — 角色逻辑触发
	var triggered = CodifiedProfile.parse_by_scene(semantic_snapshot, player_message)
	var codified_context = CodifiedProfile.get_triggered_log(triggered)

	# Step 4: 决定使用 LLM 还是本地 fallback
	if llm_api_url.is_empty() or llm_api_key.is_empty():
		MessageBus.ui_status_changed.emit("本地规则模式正在生成回复…", "local")
		_use_local_fallback(player_message, source, triggered)
	else:
		var prompt = build_prompt(semantic_snapshot, memory_context, codified_context, triggered, player_message, source)
		MessageBus.ui_status_changed.emit("AI %s/%s 正在回复…" % [llm_provider, llm_model], "online")
		_send_llm_request(prompt)


# === Prompt 构造 ===

func build_prompt(semantic: String, memory: String, codified: String, triggered: Array,
				  player_msg: String, source: AffordanceTypes.TriggerSource) -> String:

	var identity = CodifiedProfile.get_identity()

	var explicit_instruction = _build_explicit_player_instruction(player_msg)
	var prompt = """%s

%s

%s

%s

[本轮玩家消息]
%s

[本轮约束]
%s

请根据以上信息，决定你现在要做什么。
如果当前是因为需求触发（饿了/渴了/无聊），优先满足自己的需求。
如果玩家跟你说话了，本轮玩家消息拥有最高优先级。先直接回应玩家当前所说的内容，不要被角色偏好或旧记忆带偏，也不要无故转移到奶茶。

你必须回复一个 JSON 对象，格式如下：
{"thought": "你的内心想法", "goal": "一个简洁的目标名称(如drink_milk_tea/watch_tv/read_book/rest_on_sofa/patrol_room/wander_room/chat_with_player)", "goal_reason": "为什么做这个决定", "emotion": "情绪(happy/sad/angry/surprised/neutral/bored/excited)", "emotion_intensity": 0.5, "speech": "你说的话（可以为空字符串）", "speech_tone": "语气(cheerful/neutral/nervous/sad/angry)", "gesture": "身体动作(必须从以下选择一个:idle/walk/wave/nod/think/happy/sit/talk)", "plan": [{"action": "patrol", "route": "room_perimeter", "laps": 1}]}

plan 是可选字段，最多 6 步。action 只能是 navigate_object/navigate_waypoint/patrol/wander/look_at/interact/wait；目标只能引用当前场景已有物体或已知路径点。不要输出坐标。"""

	# 对自主触发，强调优先满足需求
	if source == AffordanceTypes.TriggerSource.SIMULATION:
		prompt += "\n\n重要提示：你需要优先满足自己的生理需求。"

	var formatted = prompt % [
		identity,
		semantic,
		memory,
		codified if not codified.is_empty() else "[没有特殊的角色反应]",
		player_msg if not player_msg.is_empty() else "[无，本轮为自主行为]",
		explicit_instruction,
	]

	return formatted


# === LLM 通信 ===

func _send_llm_request(prompt: String) -> void:
	if llm_api_url.is_empty() or llm_api_key.is_empty():
		_use_local_fallback("", AffordanceTypes.TriggerSource.IDLE_TIMER, [])
		return

	# OpenAI 兼容格式 (ECNU-Max, GPT, DeepSeek 等)
	var body = {
		"model": llm_model,
		"messages": [
			{"role": "system", "content": "你是一个游戏角色的AI大脑。你必须回复严格的JSON格式。回复中不要有任何markdown代码块或其他文字，只输出纯JSON。"},
			{"role": "user", "content": prompt}
		],
		"max_tokens": 300,
		"temperature": 0.7,
	}

	# Anthropic 格式需要特殊处理
	var headers: PackedStringArray
	if llm_provider == "anthropic":
		body = {
			"model": llm_model,
			"max_tokens": 300,
			"messages": [{"role": "user", "content": prompt}]
		}
		headers = [
			"Content-Type: application/json",
			"x-api-key: " + llm_api_key,
			"anthropic-version: 2023-06-01",
		]
	else:
		# OpenAI 兼容格式
		headers = [
			"Content-Type: application/json",
			"Authorization: Bearer " + llm_api_key,
		]

	print("[CognitiveCycle] → Sending request to %s (%s)" % [llm_provider, llm_model])
	var request_error = http_request.request(llm_api_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if request_error != OK:
		MessageBus.ui_status_changed.emit("AI 连接失败，已切换本地规则", "error")
		_use_local_fallback(current_trigger.get("data", {}).get("text", ""), current_trigger.get("source", AffordanceTypes.TriggerSource.IDLE_TIMER), [])


func _on_llm_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var raw_body = body.get_string_from_utf8()
	print("[CognitiveCycle] ← Response code=%d" % response_code)

	if response_code != 200:
		push_warning("CognitiveCycle: LLM request failed, code=%d" % response_code)
		MessageBus.ui_status_changed.emit("AI 请求失败，已使用本地规则回复", "error")
		_use_local_fallback(current_trigger.get("data", {}).get("text", ""), current_trigger.get("source", AffordanceTypes.TriggerSource.IDLE_TIMER), [])
		return

	var json = JSON.new()
	if json.parse(raw_body) != OK:
		push_warning("CognitiveCycle: failed to parse LLM response")
		_use_local_fallback(current_trigger.get("data", {}).get("text", ""), current_trigger.get("source", AffordanceTypes.TriggerSource.IDLE_TIMER), [])
		return

	var response = json.get_data()
	var content = _extract_content(response)

	var parsed = _parse_llm_output(content)
	if parsed.is_empty():
		push_warning("CognitiveCycle: failed to parse JSON from LLM output")
		_use_local_fallback(current_trigger.get("data", {}).get("text", ""), current_trigger.get("source", AffordanceTypes.TriggerSource.IDLE_TIMER), [])
		return

	_handle_decision(parsed)


func _extract_content(response: Dictionary) -> String:
	# OpenAI 兼容格式
	if response.has("choices") and response["choices"] is Array and response["choices"].size() > 0:
		var msg = response["choices"][0].get("message", {})
		return msg.get("content", "")

	# Anthropic 格式
	if response.has("content") and response["content"] is Array:
		for block in response["content"]:
			if block is Dictionary and block.get("type") == "text":
				return block["text"]

	return ""


func _parse_llm_output(content: String) -> Dictionary:
	var cleaned = content.replace("```json", "").replace("```", "").strip_edges()
	var start = cleaned.find("{")
	var end = cleaned.rfind("}")
	if start >= 0 and end > start:
		var json_str = cleaned.substr(start, end - start + 1)
		var json = JSON.new()
		var err = json.parse(json_str)
		if err == OK:
			var result = json.get_data()
			if result.has("goal") or result.has("speech"):
				return result

	var json = JSON.new()
	if json.parse(cleaned) == OK:
		return json.get_data()

	return {}


# === 决策处理 ===

func _handle_decision(decision: Dictionary) -> void:
	var goal: String = decision.get("goal", "idle")
	var speech: String = decision.get("speech", "")
	var emotion: String = decision.get("emotion", "neutral")
	var thought: String = decision.get("thought", "")
	var gesture: String = decision.get("gesture", "idle")
	var emotion_intensity: float = clampf(float(decision.get("emotion_intensity", 0.65)), 0.0, 1.0)
	var player_message: String = current_trigger.get("data", {}).get("text", "")

	# 校验并净化 gesture
	gesture = _validate_and_sanitize_gesture(gesture)

	var performance := _resolve_player_performance(player_message, gesture, emotion, emotion_intensity)
	gesture = performance["gesture"]

	var router_goal := String(performance.get("goal", ""))
	var explicit_goal = router_goal if not router_goal.is_empty() else _infer_explicit_player_goal(player_message)
	var compiled_plan: Array = []
	if not explicit_goal.is_empty():
		goal = explicit_goal
		var router_reply := String(performance.get("reply", ""))
		speech = router_reply if not router_reply.is_empty() else _ensure_relevant_acknowledgement(explicit_goal, speech)
	elif performance.get("plan", []) is Array and not performance.get("plan", []).is_empty():
		compiled_plan = PlanValidator.new().compile(performance.get("plan", []))
		var router_reply := String(performance.get("reply", ""))
		if not router_reply.is_empty():
			speech = router_reply
	else:
		compiled_plan = PlanValidator.new().compile(decision.get("plan", []))

	# 记录记忆
	if not thought.is_empty():
		MemorySystem.add_episode("[思考] " + thought, 4.0)

	# 如果有对话内容 → 先输出对话
	MessageBus.route_agent_output("main_agent", speech, emotion)

	# 发出表现层 cue
	MessageBus.performance_cue.emit(gesture, {
		"source": "llm",
		"emotion": emotion,
		"motion_provider": performance["provider"],
		"generation_prompt": performance["generation_prompt"],
		"router_action_id": performance.get("action_id", ""),
		"router_target": performance.get("target", ""),
	})
	MessageBus.expression_cue.emit(performance["expression"], emotion_intensity, {
		"source": "llm",
		"motion_provider": performance["provider"],
		"router_action_id": performance.get("action_id", ""),
	})

	# Goal → GOAP 分解
	var goap = GOAPPlanner.new()
	add_child(goap)

	var actions: Array
	if not compiled_plan.is_empty():
		actions = compiled_plan
	elif goal == "chat_with_player" or goal == "idle":
		actions = [AffordanceTypes.PrimitiveAction.new(AffordanceTypes.Primitive.IDLE, {"duration": 1.0})]
	else:
		actions = goap.plan(goal)
		if actions.is_empty() or (actions.size() == 1 and actions[0].type == AffordanceTypes.Primitive.IDLE):
			actions = _infer_actions_from_goal(goal)

	# 发送给 Agent
	MessageBus.emit_actions.emit("main_agent", actions)

	goap.queue_free()
	MessageBus.ui_status_changed.emit("AI 已回复（%s/%s）" % [llm_provider, llm_model], "done")
	_finish_cycle()


func _infer_actions_from_goal(goal: String) -> Array:
	var goal_keywords = {
		"drink": "milk_tea", "eat": "milk_tea",
		"watch": "tv", "tv": "tv",
		"read": "book", "book": "book",
		"water": "plant", "plant": "plant",
		"rest": "sofa", "sit": "sofa", "sofa": "sofa",
	}
	for keyword in goal_keywords:
		if keyword in goal.to_lower():
			var goap = GOAPPlanner.new()
			add_child(goap)
			var result = goap.auto_plan(goal, goal_keywords[keyword])
			goap.queue_free()
			return result

	return [AffordanceTypes.PrimitiveAction.new(AffordanceTypes.Primitive.IDLE, {"duration": 1.0})]


# === Fallback：无 LLM 时用本地规则 ===

func _use_local_fallback(player_message: String, source: AffordanceTypes.TriggerSource, triggered: Array) -> void:
	var speech = ""
	var emotion = "neutral"
	var goal = "idle"
	var gesture = "idle"
	var emotion_intensity := 0.65
	var compiled_plan: Array = []

	var sim = WorldSimulator.get_state_snapshot()
	var needs = sim["needs"]

	# 玩家说话 → 给一个温和回应
	if source == AffordanceTypes.TriggerSource.PLAYER_INPUT and not player_message.is_empty():
		var msg_lower = player_message.to_lower()
		var routed := _route_player_intent(player_message, gesture, emotion, emotion_intensity)
		var routed_is_actionable := _is_actionable_router_decision(routed)

		# 检查触发规则中的情绪
		if not triggered.is_empty():
			emotion = triggered[0].get("emotion", "neutral")

		# B7: 显式 gesture 测试句
		if routed_is_actionable:
			speech = String(routed.get("reply", ""))
			if speech.is_empty():
				speech = _ensure_relevant_acknowledgement(String(routed.get("goal", "")), "")
			goal = String(routed.get("goal", goal))
			gesture = String(routed.get("clip", gesture))
			emotion = String(routed.get("expression", emotion))
			emotion_intensity = clampf(float(routed.get("intensity", emotion_intensity)), 0.0, 1.0)
			if routed.get("plan", []) is Array and not routed.get("plan", []).is_empty():
				compiled_plan = PlanValidator.new().compile(routed.get("plan", []))
		elif ("绕" in msg_lower or "转" in msg_lower) and "房间" in msg_lower and ("一圈" in msg_lower or "巡逻" in msg_lower):
			speech = "好呀，我去绕房间走一圈！"
			goal = "patrol_room"
			gesture = "walk"
			emotion = "happy"
		elif "巡逻" in msg_lower:
			speech = "收到，我去房间里巡逻一圈。"
			goal = "patrol_room"
			gesture = "walk"
		elif "随便走走" in msg_lower or "逛逛" in msg_lower or "走一走" in msg_lower:
			speech = "好呀，我在房间里随便逛逛～"
			goal = "wander_room"
			gesture = "walk"
		elif "挥挥" in msg_lower and "手" in msg_lower:
			speech = "嗨嗨，我在挥手呢～"
			gesture = "wave"
			emotion = "happy"
		elif "点点" in msg_lower and "头" in msg_lower:
			speech = "嗯嗯！我点点头～"
			gesture = "nod"
			emotion = "happy"
		elif "想一想" in msg_lower or "想想" in msg_lower:
			speech = "让我想一想……（思考中）"
			gesture = "think"
			emotion = "neutral"
		elif "开心" in msg_lower and "一点" in msg_lower:
			speech = "好嘞！开心起来～"
			gesture = "happy"
			emotion = "happy"
		elif "你好" in msg_lower or "嗨" in msg_lower or "hi" in msg_lower:
			speech = FALLBACK_GREETINGS[randi() % FALLBACK_GREETINGS.size()]
			emotion = "happy"
		elif "饿" in msg_lower or "吃" in msg_lower:
			speech = "对呀对呀，要不要一起喝杯奶茶？"
			goal = "drink_milk_tea"
			emotion = "excited"
		elif "玩" in msg_lower or "无聊" in msg_lower:
			speech = "嗯嗯！我们找点事情做吧！"
			emotion = "happy"
		elif "再见" in msg_lower or "拜拜" in msg_lower:
			speech = "好的，下次再来找我玩哦～"
			emotion = "neutral"
		elif "开电视" in msg_lower or "看电视" in msg_lower or "tv" in msg_lower:
			speech = "好呀！我们一起看电视，我来找找遥控器～"
			goal = "watch_tv"
			emotion = "happy"
		elif "浇" in msg_lower and "植物" in msg_lower or "花" in msg_lower:
			speech = "对哦，小绿好像缺水了，我来浇一下！"
			goal = "water_plant"
			emotion = "happy"
		elif "看书" in msg_lower or "读书" in msg_lower:
			speech = "好呀，一起看看书！"
			goal = "read_book"
			emotion = "happy"
		elif "坐" in msg_lower or "休息" in msg_lower:
			speech = "好的，休息一下～"
			goal = "rest_on_sofa"
			emotion = "neutral"
		else:
			speech = "嗯嗯，我听到了！" if randi() % 2 == 0 else "哈哈，你说得对～"
			emotion = "happy" if randf() > 0.5 else "neutral"

	# 自主触发 → 需求驱动 + 随机闲话
	elif source == AffordanceTypes.TriggerSource.SIMULATION:
		var need_type = current_trigger.get("data", {}).get("need_type")
		if need_type == AffordanceTypes.NeedType.HUNGER and needs["hunger"] < 40:
			speech = FALLBACK_HUNGRY_COMMENTS[randi() % FALLBACK_HUNGRY_COMMENTS.size()]
			goal = "drink_milk_tea"
		elif need_type == AffordanceTypes.NeedType.FUN and needs["fun"] < 30:
			speech = FALLBACK_BORED_COMMENTS[randi() % FALLBACK_BORED_COMMENTS.size()]
			goal = "watch_tv"
		elif not triggered.is_empty():
			speech = triggered[0].get("reaction", "")
			emotion = triggered[0].get("emotion", "neutral")

	# 空闲触发 → 随机闲话
	elif source == AffordanceTypes.TriggerSource.IDLE_TIMER:
		if needs["hunger"] < 40:
			speech = FALLBACK_HUNGRY_COMMENTS[randi() % FALLBACK_HUNGRY_COMMENTS.size()]
			goal = "drink_milk_tea"
		elif needs["fun"] < 30:
			speech = FALLBACK_BORED_COMMENTS[randi() % FALLBACK_BORED_COMMENTS.size()]
			goal = "watch_tv"
		elif randf() < 0.12:
			goal = "wander_room"
		elif randf() < 0.1:
			speech = FALLBACK_IDLE_COMMENTS[randi() % FALLBACK_IDLE_COMMENTS.size()]

	var performance := _resolve_player_performance(player_message, gesture, emotion, emotion_intensity)
	gesture = performance["gesture"]

	# 输出
	if not speech.is_empty():
		MessageBus.route_agent_output("main_agent", speech, emotion)

	# 发出表现层 cue
	MessageBus.performance_cue.emit(gesture, {
		"source": "local",
		"emotion": emotion,
		"motion_provider": performance["provider"],
		"generation_prompt": performance["generation_prompt"],
		"router_action_id": performance.get("action_id", ""),
		"router_target": performance.get("target", ""),
	})
	MessageBus.expression_cue.emit(performance["expression"], emotion_intensity, {
		"source": "local",
		"motion_provider": performance["provider"],
		"router_action_id": performance.get("action_id", ""),
	})

	# GOAP 分解。纯聊天/无决定时只短暂停顿，不交给规划器制造未知 Goal 警告。
	var actions: Array
	if not compiled_plan.is_empty():
		actions = compiled_plan
	elif goal == "idle" or goal == "chat_with_player":
		actions = [AffordanceTypes.PrimitiveAction.new(AffordanceTypes.Primitive.IDLE, {"duration": 1.0})]
	else:
		var goap = GOAPPlanner.new()
		add_child(goap)
		actions = goap.plan(goal)
		goap.queue_free()
	MessageBus.emit_actions.emit("main_agent", actions)

	MessageBus.ui_status_changed.emit("已使用本地规则回复", "done")
	_finish_cycle()


func _finish_cycle() -> void:
	is_processing = false
	if _pending_player_triggers.is_empty():
		return
	var next_trigger = _pending_player_triggers.pop_front()
	call_deferred("_on_trigger", next_trigger["agent_id"], next_trigger["source"], next_trigger["data"])


func _is_agent_busy(agent_id: String) -> bool:
	for node in get_tree().get_nodes_in_group("agents"):
		if node.agent_name == agent_id and node.current_activity != "idle":
			return true
	return false


# 校验并净化 LLM 返回的 gesture 字段
func _validate_and_sanitize_gesture(gesture: String) -> String:
	var normalized = gesture.strip_edges().to_lower()
	if not PerformanceCueTypes.is_valid_gesture(normalized):
		push_warning("CognitiveCycle: unknown gesture '%s' from LLM, falling back to idle" % gesture)
		return "idle"
	return normalized


func _resolve_player_performance(player_message: String, fallback_gesture: String, emotion: String, intensity: float) -> Dictionary:
	var safe_gesture := _validate_and_sanitize_gesture(fallback_gesture)
	var safe_expression := emotion.strip_edges().to_lower()
	if safe_expression not in ["neutral", "happy", "angry", "sad", "surprised", "excited", "bored", "blink", "talk"]:
		safe_expression = "neutral"
	if player_message.strip_edges().is_empty() or not _motion_router or not _motion_router.is_ready():
		return {
			"gesture": safe_gesture,
			"expression": safe_expression,
			"provider": "library",
			"generation_prompt": "",
			"goal": "",
			"plan": [],
			"reply": "",
			"target": "",
			"action_id": "",
		}

	var routed: Dictionary = _route_player_intent(player_message, safe_gesture, safe_expression, intensity)
	var routed_clip := String(routed.get("clip", safe_gesture))
	if routed.get("action_id", "") == "talk" and float(routed.get("confidence", 0.0)) <= 0.25:
		routed_clip = safe_gesture
	if routed.get("provider", "library") == "light_t2m":
		routed_clip = String(routed.get("fallback_clip", safe_gesture))
	if not PerformanceCueTypes.is_valid_gesture(routed_clip):
		routed_clip = safe_gesture
	return {
		"gesture": routed_clip,
		"expression": String(routed.get("expression", safe_expression)),
		"provider": String(routed.get("provider", "library")),
		"generation_prompt": String(routed.get("generation_prompt", "")),
		"goal": String(routed.get("goal", "")),
		"plan": routed.get("plan", []),
		"reply": String(routed.get("reply", "")),
		"target": String(routed.get("target", "")),
		"action_id": String(routed.get("action_id", "")),
	}


func _route_player_intent(player_message: String, fallback_gesture: String, emotion: String, intensity: float) -> Dictionary:
	if player_message.strip_edges().is_empty() or not _motion_router or not _motion_router.is_ready():
		return {}
	return _motion_router.route(player_message, {
		"gesture": fallback_gesture,
		"emotion": emotion,
		"intensity": intensity,
	})


func _is_actionable_router_decision(routed: Dictionary) -> bool:
	if routed.is_empty() or float(routed.get("confidence", 0.0)) < 0.5:
		return false
	if not String(routed.get("goal", "")).is_empty():
		return true
	if routed.get("plan", []) is Array and not routed.get("plan", []).is_empty():
		return true
	var locomotion := String(routed.get("locomotion", "none"))
	return locomotion not in ["", "none"]


func _infer_explicit_player_goal(player_message: String) -> String:
	var routed := _route_player_intent(player_message, "idle", "neutral", 0.5)
	var routed_goal := String(routed.get("goal", ""))
	if not routed_goal.is_empty() and float(routed.get("confidence", 0.0)) >= 0.5:
		return routed_goal
	var message = player_message.to_lower()
	if (("绕" in message or "转" in message) and "房间" in message and "一圈" in message) or "巡逻" in message:
		return "patrol_room"
	if "随便走走" in message or "房间逛逛" in message or "走一走" in message:
		return "wander_room"
	if "看电视" in message or "开电视" in message or "电视节目" in message or "tv" in message:
		return "watch_tv"
	if "看书" in message or "读书" in message or "读小说" in message:
		return "read_book"
	if "浇花" in message or "浇水" in message or "浇植物" in message:
		return "water_plant"
	if "休息" in message or "坐沙发" in message:
		return "rest_on_sofa"
	if "喝奶茶" in message:
		return "drink_milk_tea"
	return ""


func _build_explicit_player_instruction(player_message: String) -> String:
	var goal = _infer_explicit_player_goal(player_message)
	if goal.is_empty():
		return "自然、直接地回应本轮玩家消息。"
	return "玩家提出了明确可执行意图，goal 必须为 '%s'，speech 必须直接回应这项活动。" % goal


func _ensure_relevant_acknowledgement(goal: String, speech: String) -> String:
	var required_keywords = {
		"patrol_room": ["绕", "巡逻", "一圈"],
		"wander_room": ["走走", "逛"],
		"watch_tv": ["电视", "节目"],
		"read_book": ["书", "小说"],
		"water_plant": ["浇", "小绿", "植物"],
		"rest_on_sofa": ["休息", "沙发", "坐"],
		"drink_milk_tea": ["奶茶", "喝"],
	}
	for keyword in required_keywords.get(goal, []):
		if keyword in speech:
			return speech
	match goal:
		"patrol_room": return "好呀，我去绕房间走一圈！"
		"wander_room": return "好呀，我在房间里随便走走～"
		"watch_tv": return "好呀，我们一起看电视吧！"
		"read_book": return "好呀，我们一起看会儿书吧！"
		"water_plant": return "好呀，我们一起给小绿浇水吧！"
		"rest_on_sofa": return "好呀，我们去沙发上休息一下吧。"
		"drink_milk_tea": return "好呀，我们一起喝奶茶吧！"
	return speech
