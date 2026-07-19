# cognitive_cycle.gd — 认知循环主控制器 (Autoload)
# 设计文档 §二：感知 → 记忆检索 → Codified Logic → LLM → GOAP → 执行
# 参考 [GA §4] + [CCL §3]

extends Node

# LLM API 配置
var llm_api_url: String = ""
var llm_api_key: String = ""
var llm_model: String = "ecnu-max"
var llm_provider: String = "openai"  # "openai" | "anthropic"

# 当前是否正在处理
var is_processing: bool = false

# HTTP 请求节点
var http_request: HTTPRequest

# 当前触发上下文
var current_trigger: Dictionary = {}


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_llm_config()

	# 创建 HTTP 请求节点
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_llm_response)

	# 监听所有触发源
	MessageBus.agent_trigger_cycle.connect(_on_trigger)


func _load_llm_config():
	var path = "res://data/llm_config.json"
	if not FileAccess.file_exists(path):
		push_warning("CognitiveCycle: llm_config.json not found, using defaults")
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


# === 主入口：触发源到达 ===

func _on_trigger(agent_id: String, source: AffordanceTypes.TriggerSource, data: Dictionary) -> void:
	if is_processing:
		# 当前正在处理中，缓存 → 可以用队列优化，Demo 先忽略
		return

	is_processing = true
	current_trigger = {"agent_id": agent_id, "source": source, "data": data}

	# Step 1: Perception — 世界语义快照
	var semantic_snapshot = SemanticWorld.generate_semantic_snapshot(agent_id)

	# Step 2: Memory Retrieval — 检索相关记忆
	var player_message = ""
	if source == AffordanceTypes.TriggerSource.PLAYER_INPUT:
		player_message = data.get("text", "")
	MemorySystem.add_episode("玩家说: %s" % player_message, 6.0) if not player_message.is_empty() else void

	var memory_context = MemorySystem.format_for_llm(player_message)

	# Step 3: Codified Profile — 角色逻辑触发
	var triggered = CodifiedProfile.parse_by_scene(semantic_snapshot, player_message)
	var codified_context = CodifiedProfile.get_triggered_log(triggered)

	# Step 4: 构造 Prompt → 发送 LLM 请求
	var prompt = build_prompt(semantic_snapshot, memory_context, codified_context, triggered, player_message, source)
	_send_llm_request(prompt)


# === Prompt 构造 ===

func build_prompt(semantic: String, memory: String, codified: String, triggered: Array,
				  player_msg: String, source: AffordanceTypes.TriggerSource) -> String:

	var identity = CodifiedProfile.get_identity()

	var prompt = """%s

%s

%s

%s

请根据以上信息，决定你现在要做什么。
如果当前是因为需求触发（饿了/渴了/无聊），优先满足自己的需求。
如果玩家跟你说话了，给一个自然的回应。

你必须回复一个 JSON 对象，格式如下：
{"thought": "你的内心想法", "goal": "一个简洁的目标名称(如drink_milk_tea/watch_tv/read_book/rest_on_sofa/look_out_window/stretch/wave_at_player/chat_with_player)", "goal_reason": "为什么做这个决定", "emotion": "情绪(happy/sad/angry/surprised/neutral/bored/excited)", "emotion_intensity": 0.5, "speech": "你说的话（可以为空字符串）", "speech_tone": "语气(cheerful/neutral/nervous/sad/angry)"}"""

	# 对自主触发，强调优先满足需求
	if source == AffordanceTypes.TriggerSource.SIMULATION:
		prompt += "\n\n重要提示：你需要优先满足自己的生理需求。"

	var formatted = prompt % [identity, semantic, memory, codified if not codified.is_empty() else "[没有特殊的角色反应]"]

	return formatted


# === LLM 通信 ===

func _send_llm_request(prompt: String) -> void:
	if llm_api_url.is_empty() or llm_api_key.is_empty():
		_use_local_fallback()
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
	http_request.request(llm_api_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))


func _on_llm_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var raw_body = body.get_string_from_utf8()
	print("[CognitiveCycle] ← Response code=%d, body preview=%s" % [response_code, raw_body.substr(0, 200)])

	if response_code != 200:
		push_warning("CognitiveCycle: LLM request failed, code=%d, body=%s" % [response_code, raw_body])
		_use_local_fallback()
		return

	var json = JSON.new()
	if json.parse(raw_body) != OK:
		push_warning("CognitiveCycle: failed to parse LLM response")
		_use_local_fallback()
		return

	var response = json.get_data()
	var content = _extract_content(response)

	print("[CognitiveCycle] ← Extracted content: %s" % content.substr(0, 200))

	var parsed = _parse_llm_output(content)
	if parsed.is_empty():
		push_warning("CognitiveCycle: failed to parse JSON from LLM output")
		_use_local_fallback()
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
	# 尝试多种方式提取 JSON
	# 1. 去除 markdown 代码块标记
	var cleaned = content.replace("```json", "").replace("```", "").strip_edges()

	# 2. 查找 JSON
	var start = cleaned.find("{")
	var end = cleaned.rfind("}")
	if start >= 0 and end > start:
		var json_str = cleaned.substr(start, end - start + 1)
		var json = JSON.new()
		var err = json.parse(json_str)
		if err == OK:
			var result = json.get_data()
			# 验证必要字段
			if result.has("goal") or result.has("speech"):
				return result

	# 3. 尝试直接解析完整内容
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

	# 记录记忆
	if not thought.is_empty():
		MemorySystem.add_episode("[思考] " + thought, 4.0)

	# 如果有对话内容 → 先输出对话
	if not speech.is_empty():
		var agent_name = CodifiedProfile.profile_name
		MessageBus.route_agent_output("main_agent", speech, emotion)

	# Goal → GOAP 分解
	var actions: Array[AffordanceTypes.PrimitiveAction]
	var goap = GOAPPlanner.new()
	add_child(goap)

	if goal == "chat_with_player" or goal == "idle":
		actions = [AffordanceTypes.PrimitiveAction.new(AffordanceTypes.Primitive.IDLE, {"duration": 1.0})]
	else:
		# 先尝试精确匹配
		actions = goap.plan(goal)
		if actions.is_empty() or (actions.size() == 1 and actions[0].type == AffordanceTypes.Primitive.IDLE):
			# 尝试从 object 推断
			actions = _infer_actions_from_goal(goal)

	# 发送给 ActionExecutor
	SignalBus.emit_actions("main_agent", actions)

	# 完成后重置
	goap.queue_free()
	is_processing = false


func _infer_actions_from_goal(goal: String) -> Array[AffordanceTypes.PrimitiveAction]:
	# 从 goal 名称猜测相关物体
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

func _use_local_fallback() -> void:
	push_warning("CognitiveCycle: using local fallback (no LLM available)")
	var sim = WorldSimulator.get_state_snapshot()
	var needs = sim["needs"]

	# 简单需求驱动的本地决策
	var goal = "idle"
	if needs["hunger"] < 40 and SemanticWorld.get_object("milk_tea") and SemanticWorld.get_object("milk_tea").state.contains("满"):
		goal = "drink_milk_tea"
	elif needs["fun"] < 30:
		goal = "watch_tv"

	MessageBus.route_agent_output("main_agent", "", "neutral")

	var goap = GOAPPlanner.new()
	add_child(goap)
	var actions = goap.plan(goal)
	SignalBus.emit_actions("main_agent", actions)
	goap.queue_free()
	is_processing = false
