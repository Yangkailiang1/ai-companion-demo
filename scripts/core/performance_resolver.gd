# performance_resolver.gd — Performance cue resolution helper (RefCounted)
# Roadmap: C1, C3, T4.5
# Responsibility: Resolves motion, gesture and expression routing from player messages
#   and LLM output; owns gesture validation, expression cue emission and the routing
#   bridge between natural-language input and motion/expression routers.  Never mutates
#   scene nodes, positions, memories or UI.
# Collaborators: MessageBus, PerformanceCueTypes, motion_intent_router, expression_intent_router
# Tests: scripts/debug/gesture_pipeline_check.gd, scripts/debug/t4_5_cognitive_split_test.gd

class_name PerformanceResolver
extends RefCounted


## [C1][T4.5] Validate and sanitize a gesture name from LLM output.
## Falls back to "idle" for unknown gestures.
## Pure validation; no side effects.
func validate_and_sanitize_gesture(gesture: String) -> String:
	var normalized = gesture.strip_edges().to_lower()
	if not PerformanceCueTypes.is_valid_gesture(normalized):
		push_warning("PerformanceResolver: unknown gesture '%s', falling back to idle" % gesture)
		return "idle"
	return normalized


## [C1][C3][T4.5] Resolve the player-facing performance (gesture, expression, goal, plan)
## from the player message and routing context.
## Requires a ready motion_router; returns a default dict when unavailable.
## Side effects: none.
func resolve_player_performance(player_message: String, fallback_gesture: String, emotion: String, intensity: float,
								motion_query: String, motion_router) -> Dictionary:
	var safe_gesture := validate_and_sanitize_gesture(fallback_gesture)
	var safe_expression := _sanitize_expression(emotion)
	if player_message.strip_edges().is_empty() or not motion_router or not motion_router.is_ready():
		return _empty_performance(safe_gesture, safe_expression)

	var route_text := motion_query.strip_edges() if not motion_query.strip_edges().is_empty() else player_message
	var routed: Dictionary = route_player_intent(route_text, safe_gesture, safe_expression, intensity, motion_router)
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


## [C3][T4.5] Resolve expression performance through the expression router.
## Falls back when the router is unavailable.
## Side effects: none.
func resolve_expression_performance(expression_query: String, fallback_expression: String, intensity: float,
									 player_message: String, speech: String, expression_router) -> Dictionary:
	var safe_expression := _sanitize_expression(fallback_expression)
	if not expression_router or not expression_router.is_ready():
		return {
			"expression": safe_expression,
			"intensity": clampf(intensity, 0.0, 1.0),
			"morph_weights": {},
			"provider": "fallback",
		}
	var query := expression_query.strip_edges()
	if query.is_empty():
		query = player_message.strip_edges()
	if query.is_empty():
		query = speech.strip_edges()
	if query.is_empty():
		query = safe_expression
	return expression_router.route(query, safe_expression, intensity)


## [C3][T4.5] Emit expression performance cues to MessageBus.
## Dispatches to either expression_cue or expression_blend_cue depending on payload.
## Side effects: emits MessageBus signals.
func emit_expression_performance(expression_performance: Dictionary, context: Dictionary) -> void:
	var merged_context := context.duplicate(true)
	merged_context["expression_provider"] = String(expression_performance.get("provider", "fallback"))
	merged_context["expression_components"] = expression_performance.get("components", [])
	var weights: Dictionary = expression_performance.get("morph_weights", {})
	if weights.is_empty():
		MessageBus.expression_cue.emit(
			String(expression_performance.get("expression", "neutral")),
			float(expression_performance.get("intensity", 1.0)),
			merged_context
		)
	else:
		MessageBus.expression_blend_cue.emit(expression_performance, merged_context)


## [C1][T4.5] Route a player message through the motion intent router.
## Thin wrapper that marshals the context dict expected by the router.
## Side effects: none.
func route_player_intent(player_message: String, fallback_gesture: String, emotion: String,
						  intensity: float, motion_router) -> Dictionary:
	if player_message.strip_edges().is_empty() or not motion_router or not motion_router.is_ready():
		return {}
	return motion_router.route(player_message, {
		"gesture": fallback_gesture,
		"emotion": emotion,
		"intensity": intensity,
	})


## [C1][T4.5] Decide whether a routed decision is actionable (high-confidence goal/plan/locomotion).
## Pure inspection; no side effects.
func is_actionable_router_decision(routed: Dictionary) -> bool:
	if routed.is_empty() or float(routed.get("confidence", 0.0)) < 0.5:
		return false
	if not String(routed.get("goal", "")).is_empty():
		return true
	if routed.get("plan", []) is Array and not routed.get("plan", []).is_empty():
		return true
	var locomotion := String(routed.get("locomotion", "none"))
	return locomotion not in ["", "none"]


# === internal helpers ===

## [C3] Clamp an expression name to a known whitelist; fall back to "neutral".
## Pure validation; no side effects.
func _sanitize_expression(expression: String) -> String:
	var safe = expression.strip_edges().to_lower()
	if safe not in ["neutral", "happy", "angry", "sad", "surprised", "excited", "bored", "blink", "talk"]:
		return "neutral"
	return safe


## [C1][T4.5] Return a safe default performance dict when no router is available.
## Pure factory; no side effects.
func _empty_performance(gesture: String, expression: String) -> Dictionary:
	return {
		"gesture": gesture,
		"expression": expression,
		"provider": "library",
		"generation_prompt": "",
		"goal": "",
		"plan": [],
		"reply": "",
		"target": "",
		"action_id": "",
	}
