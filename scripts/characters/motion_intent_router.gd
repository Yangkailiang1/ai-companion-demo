class_name MotionIntentRouter
extends RefCounted

const MOTION_CATALOG_PATH := "res://data/motion_catalog.json"
const EXPRESSION_CATALOG_PATH := "res://data/expression_catalog.json"

var _actions: Array = []
var _physical_terms: Array = []
var _expressions: Dictionary = {}
var load_error: String = ""


func _init() -> void:
	var motion_data := _load_json(MOTION_CATALOG_PATH)
	var expression_data := _load_json(EXPRESSION_CATALOG_PATH)
	_actions = motion_data.get("actions", [])
	_physical_terms = motion_data.get("generative_physical_terms", [])
	_expressions = expression_data.get("expressions", {})


func route(text: String, hints: Dictionary = {}) -> Dictionary:
	var normalized := _normalize(text)
	var negated := _contains_negation(normalized)
	var best_action: Dictionary = {}
	var best_score := 0.0
	for action_value in _actions:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		var score := _score_terms(normalized, action.get("aliases", []))
		if score > best_score:
			best_score = score
			best_action = action

	var expression := _detect_expression(normalized)
	if expression == "neutral":
		expression = _normalize_expression(hints.get("emotion", "neutral"))

	if not best_action.is_empty() and best_score > 0.0 and not negated:
		if expression == "neutral":
			expression = best_action.get("default_expression", "neutral")
		return _build_decision(best_action, expression, minf(best_score, 1.0), "library", text)

	if _contains_any(normalized, _physical_terms) and _is_explicit_motion_request(normalized) and not negated:
		var fallback := _find_action("idle")
		var fallback_hint := String(hints.get("gesture", "idle"))
		if fallback_hint in ["walk", "think", "happy"]:
			fallback = _find_action(fallback_hint)
		var decision := _build_decision(fallback, expression, 0.45, "light_t2m", text)
		decision["action_id"] = "generated_motion"
		decision["generation_prompt"] = _build_generation_prompt(text, hints)
		return decision

	var conversation_action := _find_action("talk" if not normalized.is_empty() else "idle")
	if expression == "neutral" and not normalized.is_empty():
		expression = "talk"
	return _build_decision(conversation_action, expression, 0.25, "library", text)


func is_ready() -> bool:
	return load_error.is_empty() and not _actions.is_empty() and not _expressions.is_empty()


func get_expression_names() -> PackedStringArray:
	return PackedStringArray(_expressions.keys())


func _build_decision(action: Dictionary, expression: String, confidence: float, provider: String, source_text: String) -> Dictionary:
	var clip := String(action.get("clip", "idle"))
	return {
		"action_id": String(action.get("id", "idle")),
		"clip": clip,
		"expression": expression,
		"confidence": confidence,
		"provider": provider,
		"fallback_clip": clip if clip != "talk" else "idle",
		"style": _style_for_expression(expression),
		"speed": 1.0,
		"duration": float(action.get("default_duration", 2.0)),
		"source_text": source_text,
		"generation_prompt": String(action.get("prompt_template", "")),
	}


func _detect_expression(normalized: String) -> String:
	var best_name := "neutral"
	var best_score := 0.0
	for expression_name in _expressions:
		var entry: Dictionary = _expressions[expression_name]
		var score := _score_terms(normalized, entry.get("aliases", []))
		if score > best_score:
			best_name = expression_name
			best_score = score
	return best_name


func _score_terms(normalized: String, terms: Array) -> float:
	var score := 0.0
	for term_value in terms:
		var term := _normalize(String(term_value))
		if term.is_empty() or term not in normalized:
			continue
		var length_bonus := minf(float(term.length()) / 12.0, 0.4)
		score = maxf(score, 0.6 + length_bonus)
	return score


func _contains_any(normalized: String, terms: Array) -> bool:
	for term_value in terms:
		if _normalize(String(term_value)) in normalized:
			return true
	return false


func _contains_negation(normalized: String) -> bool:
	return _contains_any(normalized, ["不要", "别 ", "别再", "不许", "无需", "不用", "don't", "do not", "never"])


func _is_explicit_motion_request(normalized: String) -> bool:
	var command_markers := ["请", "帮我", "给我", "表演", "做一个", "来一个", "来个", "现在", "开始"]
	if _contains_any(normalized, command_markers):
		return true
	for prefix in ["dance", "kick", "jump", "hug", "crawl", "pick up", "do a", "perform"]:
		if normalized.begins_with(prefix):
			return true
	return false


func _find_action(action_id: String) -> Dictionary:
	for action_value in _actions:
		if action_value is Dictionary and action_value.get("id", "") == action_id:
			return action_value
	return {"id": "idle", "clip": "idle", "default_duration": 2.0, "prompt_template": ""}


func _normalize_expression(value: String) -> String:
	var normalized := _normalize(value)
	if normalized in _expressions:
		return normalized
	return "neutral"


func _style_for_expression(expression: String) -> String:
	match expression:
		"happy", "excited": return "energetic"
		"sad", "bored": return "subdued"
		"angry": return "tense"
	return "natural"


func _build_generation_prompt(text: String, hints: Dictionary) -> String:
	var style := _style_for_expression(_normalize_expression(hints.get("emotion", "neutral")))
	return "%s Style: %s. Keep the motion safe, balanced, and in place." % [text.strip_edges(), style]


func _normalize(text: String) -> String:
	return text.strip_edges().to_lower().replace("，", " ").replace("。", " ").replace("！", " ").replace("？", " ")


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		load_error = "missing catalog: %s" % path
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		load_error = "cannot open catalog: %s" % path
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		load_error = "invalid catalog: %s" % path
		return {}
	return parsed
