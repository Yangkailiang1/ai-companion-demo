# cognitive_cycle.gd — Cognitive cycle orchestrator (Autoload)
# Roadmap: T1, X3, T4.5
# Responsibility: Orchestrates perception → memory → LLM/fallback → GOAP → execution;
#   delegates prompt construction, performance resolution and local policy to RefCounted
#   helpers.  Owns all cross-domain side effects (signals, GOAP creation, archive mutations).
# Collaborators: MessageBus, SemanticWorld, MemorySystem, CodifiedProfile, AgentPsycheSystem,
#   PromptBuilder, PerformanceResolver, LocalFallbackDecider, GOAPPlanner
# Tests: scripts/debug/headless_check.gd, scripts/debug/gesture_pipeline_check.gd,
#   scripts/debug/multi_agent_check.gd, scripts/debug/agent_psyche_check.gd,
#   scripts/debug/t4_5_cognitive_split_test.gd

extends Node

# Preload extracted helper classes
const PromptBuilderScript = preload("res://scripts/core/prompt_builder.gd")
const PerformanceResolverScript = preload("res://scripts/core/performance_resolver.gd")
const LocalFallbackDeciderScript = preload("res://scripts/core/local_fallback_decider.gd")
const MotionIntentRouterScript = preload("res://scripts/characters/motion_intent_router.gd")
const ExpressionIntentRouterScript = preload("res://scripts/characters/expression_intent_router.gd")

# LLM API configuration (public — consumed by tests)
var llm_api_url: String = ""
var llm_api_key: String = ""
var llm_model: String = "ecnu-max"
var llm_provider: String = "openai"  # "openai" | "anthropic"

# Current processing state
var is_processing: bool = false
var _pending_player_triggers: Array[Dictionary] = []
# Autonomous trigger cooldown (prevents spam)
var _last_auto_trigger_time: float = 0.0
const AUTO_TRIGGER_COOLDOWN: float = 15.0  # seconds

# HTTP request node
var http_request: HTTPRequest

# Current trigger context
var current_trigger: Dictionary = {}
var _motion_router
var _expression_router

# Extracted helpers (RefCounted, no autoload access beyond CodifiedProfile lookups)
var _prompt_builder       # PromptBuilder (RefCounted)
var _perf_resolver        # PerformanceResolver (RefCounted)
var _fallback_decider     # LocalFallbackDecider (RefCounted)


# === Initialization ===

## [T4.5] Initialize routers, config and extracted helpers; wire HTTP and trigger signal.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_motion_router = MotionIntentRouterScript.new()
	if not _motion_router.is_ready():
		push_warning("CognitiveCycle: motion router catalog unavailable: %s" % _motion_router.load_error)
	_expression_router = ExpressionIntentRouterScript.new()
	if not _expression_router.is_ready():
		push_warning("CognitiveCycle: expression router library unavailable: %s" % _expression_router.load_error)

	# Create extracted helper instances — RefCounted, no scene-tree coupling
	_prompt_builder = PromptBuilderScript.new()
	_perf_resolver = PerformanceResolverScript.new()
	_fallback_decider = LocalFallbackDeciderScript.new(_prompt_builder, _perf_resolver)

	_load_llm_config()

	# Create HTTP request node
	http_request = HTTPRequest.new()
	http_request.timeout = 20.0
	add_child(http_request)
	http_request.request_completed.connect(_on_llm_response)

	# Listen for all trigger sources
	MessageBus.agent_trigger_cycle.connect(_on_trigger)


## [X3][T4.5] Load LLM API configuration from json file; no effect if file missing.
func _load_llm_config() -> void:
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


# === Main entry: trigger source arrives ===

## [T1][X3][T4.5] Handle an Agent trigger: perceive, retrieve, decide, route to LLM or fallback.
## Implements FIFO queue for player messages when busy; autonomous triggers respect cooldown.
## Side effects: reads SemanticWorld/Memory/Codified/Psyche snapshots; updates UI status.
func _on_trigger(agent_id: String, source: AffordanceTypes.TriggerSource, data: Dictionary) -> void:
	if is_processing:
		if source == AffordanceTypes.TriggerSource.PLAYER_INPUT:
			_pending_player_triggers.append({"agent_id": agent_id, "source": source, "data": data.duplicate(true)})
			MessageBus.ui_status_changed.emit("AI 正忙，你的消息已排队（%d）" % _pending_player_triggers.size(), "queued")
		return

	if source in [AffordanceTypes.TriggerSource.SIMULATION, AffordanceTypes.TriggerSource.IDLE_TIMER] and _is_agent_busy(agent_id):
		return

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
		MessageBus.ui_status_changed.emit("%s正在自主思考…" % CodifiedProfile.get_agent_display_name(agent_id), "thinking")

	var semantic_snapshot = SemanticWorld.generate_semantic_snapshot(agent_id)

	var player_message = ""
	if source == AffordanceTypes.TriggerSource.PLAYER_INPUT:
		player_message = data.get("text", "")
		if not player_message.is_empty():
			MemorySystem.add_episode_for_agent(agent_id, "玩家说: %s" % player_message, 6.0)

	var memory_context = MemorySystem.format_for_llm_for_agent(agent_id, player_message)

	var triggered = CodifiedProfile.parse_by_scene_for_agent(agent_id, semantic_snapshot, player_message)
	var codified_context = CodifiedProfile.get_triggered_log(triggered)
	var psychology_context = AgentPsycheSystem.build_cognitive_context(agent_id)

	# Step 4: Decide LLM vs local fallback
	if llm_api_url.is_empty() or llm_api_key.is_empty():
		MessageBus.ui_status_changed.emit("本地规则模式正在生成回复…", "local")
		_use_local_fallback(player_message, source, triggered)
	else:
		var prompt = build_prompt(
			semantic_snapshot,
			memory_context,
			codified_context,
			psychology_context,
			triggered,
			player_message,
			source,
			agent_id
		)
		MessageBus.ui_status_changed.emit("AI %s/%s 正在回复…" % [llm_provider, llm_model], "online")
		_send_llm_request(prompt)


# === Prompt construction (public facade — used by test suites) ===

## [T1][T4.5] Assemble the full LLM prompt from structured cognitive inputs.
## Delegates to PromptBuilder while preserving the original public signature.
func build_prompt(semantic: String, memory: String, codified: String, psychology: String, triggered: Array,
				  player_msg: String, source: AffordanceTypes.TriggerSource,
				  agent_id: String = "main_agent") -> String:
	return _prompt_builder.build_prompt(semantic, memory, codified, psychology, triggered,
		player_msg, source, agent_id)


# === LLM communication ===

## [T1][X3] Send an LLM API request with provider-appropriate envelope.
## Side effects: initiates async HTTP request.
func _send_llm_request(prompt: String) -> void:
	if llm_api_url.is_empty() or llm_api_key.is_empty():
		_use_local_fallback("", AffordanceTypes.TriggerSource.IDLE_TIMER, [])
		return

	# OpenAI-compatible envelope (ECNU-Max, GPT, DeepSeek etc.)
	var body = {
		"model": llm_model,
		"messages": [
			{"role": "system", "content": "你是一个游戏角色的AI大脑。你必须回复严格的JSON格式。回复中不要有任何markdown代码块或其他文字，只输出纯JSON。"},
			{"role": "user", "content": prompt}
		],
		"max_tokens": 300,
		"temperature": 0.7,
	}

	# Anthropic format requires a different envelope
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
		headers = [
			"Content-Type: application/json",
			"Authorization: Bearer " + llm_api_key,
		]

	print("[CognitiveCycle] → Sending request to %s (%s)" % [llm_provider, llm_model])
	var request_error = http_request.request(llm_api_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if request_error != OK:
		MessageBus.ui_status_changed.emit("AI 连接失败，已切换本地规则", "error")
		_use_local_fallback(current_trigger.get("data", {}).get("text", ""), current_trigger.get("source", AffordanceTypes.TriggerSource.IDLE_TIMER), [])


## [T1] Handle LLM HTTP response: extract content, parse JSON, dispatch to decision handler.
## Falls back to local rules on any failure.
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


## [T1] Extract the raw text content from a provider-specific API response.
## Pure parsing; no side effects.
func _extract_content(response: Dictionary) -> String:
	# OpenAI-compatible format
	if response.has("choices") and response["choices"] is Array and response["choices"].size() > 0:
		var msg = response["choices"][0].get("message", {})
		return msg.get("content", "")

	# Anthropic format
	if response.has("content") and response["content"] is Array:
		for block in response["content"]:
			if block is Dictionary and block.get("type") == "text":
				return block["text"]

	return ""


## [T1] Parse JSON object from (possibly markdown-wrapped) LLM text output.
## Pure parsing; no side effects.
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


# === Decision handling ===

## [T1][C1][T4.5] Convert a parsed LLM decision into world actions and performance cues.
## Reads current_trigger for agent/player context; delegates motion/expression resolution
## to PerformanceResolver and GOAP decomposition to _resolve_actions_from_goal.
## Side effects: emits MessageBus signals, creates GOAPPlanner, updates memory.
func _handle_decision(decision: Dictionary) -> void:
	var agent_id: String = current_trigger.get("agent_id", "main_agent")
	var goal: String = decision.get("goal", "idle")
	var speech: String = decision.get("speech", "")
	var emotion: String = decision.get("emotion", "neutral")
	var thought: String = decision.get("thought", "")
	var gesture: String = decision.get("gesture", "idle")
	var emotion_intensity: float = clampf(float(decision.get("emotion_intensity", 0.65)), 0.0, 1.0)
	var player_message: String = current_trigger.get("data", {}).get("text", "")
	var motion_query: String = decision.get("motion_query", player_message)
	var expression_query: String = decision.get("expression_query", "")

	gesture = _perf_resolver.validate_and_sanitize_gesture(gesture)

	var performance: Dictionary = _perf_resolver.resolve_player_performance(
		player_message, gesture, emotion, emotion_intensity, motion_query, _motion_router)
	gesture = performance["gesture"]
	var expression_performance: Dictionary = _perf_resolver.resolve_expression_performance(
		expression_query,
		String(performance.get("expression", emotion)),
		emotion_intensity,
		player_message,
		speech,
		_expression_router)

	# Determine goal from router or explicit player instruction
	var router_goal := String(performance.get("goal", ""))
	var explicit_goal = router_goal if not router_goal.is_empty() else _prompt_builder.infer_explicit_player_goal(player_message)
	var compiled_plan: Array = []
	if not explicit_goal.is_empty():
		goal = explicit_goal
		var router_reply := String(performance.get("reply", ""))
		speech = router_reply if not router_reply.is_empty() else _prompt_builder.ensure_goal_acknowledgement(explicit_goal, speech)
	elif performance.get("plan", []) is Array and not performance.get("plan", []).is_empty():
		compiled_plan = PlanValidator.new().compile(performance.get("plan", []))
		var router_reply := String(performance.get("reply", ""))
		if not router_reply.is_empty():
			speech = router_reply
	else:
		compiled_plan = PlanValidator.new().compile(decision.get("plan", []))

	# Record memory
	if not thought.is_empty():
		MemorySystem.add_episode_for_agent(agent_id, "[思考] " + thought, 4.0)

	# Emit dialogue and performance cues
	MessageBus.route_agent_output(agent_id, speech, emotion)
	_emit_performance_cues(gesture, emotion, agent_id, performance, expression_performance, "llm")

	# GOAP decomposition and dispatch
	var actions := _resolve_actions_from_goal(goal, compiled_plan)
	MessageBus.emit_actions.emit(agent_id, actions)

	MessageBus.ui_status_changed.emit("AI 已回复（%s/%s）" % [llm_provider, llm_model], "done")
	_finish_cycle()


## [T1][T4.5] Infer GOAP actions from a goal keyword when formal planning fails.
## Creates a temporary GOAPPlanner for auto_plan resolution.
## Side effects: creates and frees a GOAPPlanner node.
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


# === Extracted helpers (shared between LLM and fallback paths) ===

## [T1][T4.5] Emit a MessageBus performance cue and delegate expression emission to PerformanceResolver.
## Shared between _handle_decision and _use_local_fallback to avoid duplicated emission blocks.
## Side effects: emits MessageBus.performance_cue and delegates to _perf_resolver.emit_expression_performance.
func _emit_performance_cues(gesture: String, emotion: String, agent_id: String,
							performance: Dictionary, expression_performance: Dictionary,
							source_label: String) -> void:
	MessageBus.performance_cue.emit(gesture, {
		"source": source_label,
		"agent_id": agent_id,
		"emotion": emotion,
		"motion_provider": performance["provider"],
		"generation_prompt": performance["generation_prompt"],
		"router_action_id": performance.get("action_id", ""),
		"router_target": performance.get("target", ""),
	})
	_perf_resolver.emit_expression_performance(expression_performance, {
		"source": source_label,
		"agent_id": agent_id,
		"motion_provider": performance["provider"],
		"router_action_id": performance.get("action_id", ""),
	})


## [T1][T4.5] Resolve GOAP actions from a goal; prefers compiled_plan, falls back to GOAPPlanner.
## Includes _infer_actions_from_goal fallback when formal planning returns only IDLE.
## Side effects: creates and frees a GOAPPlanner node when formal planning is attempted.
func _resolve_actions_from_goal(goal: String, compiled_plan: Array) -> Array:
	if not compiled_plan.is_empty():
		return compiled_plan
	if goal == "idle" or goal == "chat_with_player":
		return [AffordanceTypes.PrimitiveAction.new(AffordanceTypes.Primitive.IDLE, {"duration": 1.0})]
	var goap = GOAPPlanner.new()
	add_child(goap)
	var actions = goap.plan(goal)
	if actions.is_empty() or (actions.size() == 1 and actions[0].type == AffordanceTypes.Primitive.IDLE):
		actions = _infer_actions_from_goal(goal)
	goap.queue_free()
	return actions


# === Local fallback: deterministic rules when no LLM ===

## [T1][C1][X3] Execute local-rule fallback decision path.
## Gets a structured decision from LocalFallbackDecider, then resolves performance
## and emits side effects (signals, GOAP).
## Side effects: emits speech, performance cues, GOAP actions, status.
func _use_local_fallback(player_message: String, source: AffordanceTypes.TriggerSource, triggered: Array) -> void:
	var agent_id: String = current_trigger.get("agent_id", "main_agent")
	var sim = WorldSimulator.get_state_snapshot()
	var needs = sim["needs"]

	# Get a pure decision from the extracted fallback policy — no side effects yet
	var trigger_need_type = current_trigger.get("data", {}).get("need_type")
	var decision: Dictionary = _fallback_decider.decide(
		player_message, source, triggered, needs, _motion_router, trigger_need_type)

	var speech: String = decision["speech"]
	var emotion: String = decision["emotion"]
	var goal: String = decision["goal"]
	var gesture: String = decision["gesture"]
	var emotion_intensity: float = decision["emotion_intensity"]
	var compiled_plan: Array = decision["compiled_plan"]

	# Resolve performance
	var performance: Dictionary = _perf_resolver.resolve_player_performance(
		player_message, gesture, emotion, emotion_intensity, "", _motion_router)
	gesture = performance["gesture"]
	var expression_performance: Dictionary = _perf_resolver.resolve_expression_performance(
		player_message,
		String(performance.get("expression", emotion)),
		emotion_intensity,
		player_message,
		speech,
		_expression_router)

	# Emit speech
	if not speech.is_empty():
		MessageBus.route_agent_output(agent_id, speech, emotion)

	# Emit performance cues and actions
	_emit_performance_cues(gesture, emotion, agent_id, performance, expression_performance, "local")
	var actions := _resolve_actions_from_goal(goal, compiled_plan)
	MessageBus.emit_actions.emit(agent_id, actions)

	MessageBus.ui_status_changed.emit("已使用本地规则回复", "done")
	_finish_cycle()


# === Cycle lifecycle ===

## [T4.5] Complete the current processing cycle; dequeue next pending player trigger if any.
## Side effects: may call _on_trigger deferred.
func _finish_cycle() -> void:
	is_processing = false
	if _pending_player_triggers.is_empty():
		return
	var next_trigger = _pending_player_triggers.pop_front()
	call_deferred("_on_trigger", next_trigger["agent_id"], next_trigger["source"], next_trigger["data"])


## [T4.5] Check whether an agent is currently performing a non-idle activity.
## Pure query; no side effects.
func _is_agent_busy(agent_id: String) -> bool:
	for node in get_tree().get_nodes_in_group("agents"):
		if node.agent_name == agent_id and node.current_activity != "idle":
			return true
	return false
