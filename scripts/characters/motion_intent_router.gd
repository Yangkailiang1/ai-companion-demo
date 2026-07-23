class_name MotionIntentRouter
extends RefCounted

const MOTION_CATALOG_PATH := "res://data/motion_catalog.json"
const EXPRESSION_CATALOG_PATH := "res://data/expression_catalog.json"
const TRAINED_ROUTER_PATH := "res://data/router_model.json"

var _actions: Array = []
var _intents: Array = []
var _physical_terms: Array = []
var _expressions: Dictionary = {}
var _trained_router: Dictionary = {}
var load_error: String = ""


func _init() -> void:
	var motion_data := _load_json(MOTION_CATALOG_PATH)
	var expression_data := _load_json(EXPRESSION_CATALOG_PATH)
	_intents = motion_data.get("router_intents", [])
	_actions = motion_data.get("actions", [])
	_physical_terms = motion_data.get("generative_physical_terms", [])
	_expressions = expression_data.get("expressions", {})
	_trained_router = _load_optional_json(TRAINED_ROUTER_PATH)


func route(text: String, hints: Dictionary = {}) -> Dictionary:
	var normalized := _normalize(text)
	var negated := _contains_negation(normalized)
	var best_intent: Dictionary = {}
	var best_intent_score := 0.0
	for intent_value in _intents:
		if not intent_value is Dictionary:
			continue
		var intent: Dictionary = intent_value
		var score := _score_terms(normalized, intent.get("aliases", []))
		if score > best_intent_score:
			best_intent_score = score
			best_intent = intent

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

	if not best_intent.is_empty() and best_intent_score > 0.0 and not negated:
		return _build_intent_decision(best_intent, expression, minf(best_intent_score, 1.0), text)

	if not best_action.is_empty() and best_score > 0.0 and not negated:
		if expression == "neutral":
			expression = best_action.get("default_expression", "neutral")
		return _build_decision(best_action, expression, minf(best_score, 1.0), "library", text)

	var trained_decision := _route_with_trained_model(normalized, expression, negated, text)
	if not trained_decision.is_empty():
		return trained_decision

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
		"speech_act": "perform_gesture" if clip != "talk" else "converse",
		"action_id": String(action.get("id", "idle")),
		"clip": clip,
		"expression": expression,
		"confidence": confidence,
		"provider": provider,
		"fallback_clip": clip if clip != "talk" else "idle",
		"locomotion": "none",
		"target": "",
		"goal": "",
		"plan": [],
		"reply": "",
		"style": _style_for_expression(expression),
		"speed": 1.0,
		"duration": float(action.get("default_duration", 2.0)),
		"source_text": source_text,
		"generation_prompt": String(action.get("prompt_template", "")),
	}


func _route_with_trained_model(normalized: String, expression_hint: String, negated: bool, source_text: String) -> Dictionary:
	if negated or normalized.is_empty() or _trained_router.is_empty():
		return {}
	if String(_trained_router.get("feature_provider", "")) != "hash":
		return {}
	var dimensions := int(_trained_router.get("dimensions", 0))
	if dimensions <= 0:
		return {}
	var centroids: Dictionary = _trained_router.get("centroids", {})
	var action_centroids: Dictionary = centroids.get("actions", {})
	if action_centroids.is_empty():
		return {}
	var vector := _hash_char_ngram_vector(normalized, dimensions)
	var action_match := _nearest_centroid(vector, action_centroids)
	var action_id := String(action_match.get("label", ""))
	var confidence := float(action_match.get("score", 0.0))
	var accept_threshold := float(_trained_router.get("accept_threshold", 0.48))
	if action_id.is_empty() or confidence < accept_threshold:
		return {}
	if action_id in ["talk", "idle"]:
		return {}

	var expression := expression_hint
	var expression_match := _nearest_centroid(vector, centroids.get("expressions", {}))
	var model_expression := String(expression_match.get("label", "neutral"))
	if expression == "neutral" and not model_expression.is_empty():
		expression = model_expression
	var action := _find_action(action_id)
	if action.get("id", "idle") == "idle" and action_id != "idle":
		return {}
	if expression == "neutral":
		expression = String(action.get("default_expression", "neutral"))
	var decision := _build_decision(action, expression, clampf(confidence, 0.0, 1.0), "trained_router", source_text)
	decision["router_model"] = String(_trained_router.get("embedding_model", "hash_char_ngram_v1"))
	return decision


func _nearest_centroid(vector: PackedFloat32Array, centroids: Dictionary) -> Dictionary:
	var best_label := ""
	var best_score := -1.0
	for label in centroids:
		var score := _cosine_dense(vector, centroids[label])
		if score > best_score:
			best_label = String(label)
			best_score = score
	return {"label": best_label, "score": best_score}


func _cosine_dense(vector: PackedFloat32Array, centroid: Variant) -> float:
	if not centroid is Array:
		return -1.0
	var total := 0.0
	var count = mini(vector.size(), centroid.size())
	for index in range(count):
		total += vector[index] * float(centroid[index])
	return total


func _hash_char_ngram_vector(text: String, dimensions: int) -> PackedFloat32Array:
	var vector := PackedFloat32Array()
	vector.resize(dimensions)
	var normalized := _normalize(text)
	var compact := normalized.replace(" ", "")
	var sources: Array[String] = [compact]
	for token in normalized.split(" ", false):
		if not token.is_empty():
			sources.append(token)
	var added := false
	for source in sources:
		for ngram_size in [1, 2, 3]:
			if source.length() < ngram_size:
				continue
			for index in range(0, source.length() - ngram_size + 1):
				var gram := source.substr(index, ngram_size)
				var hash_value := _fnv_hash(gram)
				var bucket := int(hash_value % dimensions)
				var sign := 1.0 if hash_value % 2 == 0 else -1.0
				vector[bucket] += sign
				added = true
	if not added and not normalized.is_empty():
		var hash_value := _fnv_hash(normalized)
		vector[int(hash_value % dimensions)] += 1.0
	var norm := 0.0
	for value in vector:
		norm += value * value
	norm = sqrt(norm)
	if norm <= 0.000001:
		return vector
	for index in range(vector.size()):
		vector[index] = vector[index] / norm
	return vector


func _fnv_hash(value: String) -> int:
	var hash_value := 2166136261
	for index in range(value.length()):
		hash_value = int((hash_value ^ value.unicode_at(index)) * 16777619) % 2147483647
	return hash_value


func _build_intent_decision(intent: Dictionary, expression_hint: String, confidence: float, source_text: String) -> Dictionary:
	var gesture := String(intent.get("gesture", "talk"))
	var action := _find_action(gesture)
	var expression := String(intent.get("expression", expression_hint))
	if expression == "neutral" and expression_hint != "neutral":
		expression = expression_hint
	if expression == "neutral":
		expression = String(action.get("default_expression", "neutral"))
	var decision := _build_decision(action, expression, confidence, "library", source_text)
	decision["speech_act"] = String(intent.get("speech_act", decision.get("speech_act", "perform_gesture")))
	decision["action_id"] = String(intent.get("id", decision.get("action_id", "idle")))
	decision["goal"] = String(intent.get("goal", ""))
	decision["locomotion"] = String(intent.get("locomotion", "none"))
	decision["target"] = String(intent.get("target", ""))
	decision["plan"] = _duplicate_array(intent.get("plan", []))
	decision["reply"] = String(intent.get("reply", ""))
	decision["intensity"] = clampf(float(intent.get("intensity", 0.5)), 0.0, 1.0)
	decision["duration"] = float(intent.get("duration", decision.get("duration", 2.0)))
	return decision


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


func _duplicate_array(value: Variant) -> Array:
	if value is Array:
		return value.duplicate(true)
	return []


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


func _load_optional_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("invalid optional router model: %s" % path)
		return {}
	return parsed
