class_name ExpressionIntentRouter
extends RefCounted

const EXPRESSION_LIBRARY_PATH := "res://data/expression_library.json"

var _entries: Array[Dictionary] = []
var _dimensions := 1024
var _accept_threshold := 0.16
var _top_k := 2
var load_error := ""


func _init() -> void:
	var library := _load_json(EXPRESSION_LIBRARY_PATH)
	_dimensions = int(library.get("dimensions", 1024))
	_accept_threshold = float(library.get("accept_threshold", 0.16))
	_top_k = clampi(int(library.get("top_k", 2)), 1, 4)
	for value in library.get("expressions", []):
		if not value is Dictionary:
			continue
		var entry: Dictionary = value.duplicate(true)
		entry["_vector"] = _hash_char_ngram_vector(_entry_text(entry), _dimensions)
		_entries.append(entry)


func is_ready() -> bool:
	return load_error.is_empty() and not _entries.is_empty()


func route(query: String, fallback_expression: String = "neutral", intensity: float = 0.65) -> Dictionary:
	var normalized := _normalize(query)
	var fallback := _find_entry(fallback_expression)
	if normalized.is_empty():
		return _build_decision(fallback, intensity, "fallback", 1.0)

	var alias_match := _best_alias_match(normalized)
	if not alias_match.is_empty():
		return _build_decision(alias_match["entry"], intensity, "library_alias", float(alias_match["score"]))

	var query_vector := _hash_char_ngram_vector(normalized, _dimensions)
	var ranked: Array[Dictionary] = []
	for entry in _entries:
		ranked.append({
			"entry": entry,
			"score": _cosine_dense(query_vector, entry.get("_vector", PackedFloat32Array())),
		})
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.get("score", -1.0)) > float(right.get("score", -1.0))
	)
	if ranked.is_empty() or float(ranked[0].get("score", 0.0)) < _accept_threshold:
		return _build_decision(fallback, intensity, "fallback", 0.0)

	var selected := ranked.slice(0, mini(_top_k, ranked.size()))
	return _build_blend_decision(selected, intensity)


func _build_decision(entry: Dictionary, intensity: float, provider: String, confidence: float) -> Dictionary:
	var weights: Dictionary = entry.get("morph_weights", {})
	return {
		"expression": String(entry.get("id", "neutral")),
		"display_name": String(entry.get("display_name", entry.get("id", "neutral"))),
		"morph_weights": weights.duplicate(true),
		"bone_fallback": entry.get("bone_fallback", {}).duplicate(true),
		"fade_duration": float(entry.get("fade_duration", 0.16)),
		"hold_seconds": float(entry.get("hold_seconds", entry.get("transient_seconds", 0.0))),
		"transient_seconds": float(entry.get("transient_seconds", 0.0)),
		"intensity": clampf(intensity, 0.0, 1.0),
		"confidence": clampf(confidence, 0.0, 1.0),
		"provider": provider,
		"components": [{"id": String(entry.get("id", "neutral")), "weight": 1.0, "score": confidence}],
	}


func _build_blend_decision(selected: Array[Dictionary], intensity: float) -> Dictionary:
	var total := 0.0
	for item in selected:
		total += maxf(float(item.get("score", 0.0)), 0.0)
	if total <= 0.0001:
		return _build_decision(selected[0]["entry"], intensity, "expression_router", float(selected[0].get("score", 0.0)))

	var merged_weights: Dictionary = {}
	var merged_bones: Dictionary = {}
	var components: Array = []
	var fade := 0.0
	var hold := 0.0
	for item in selected:
		var entry: Dictionary = item["entry"]
		var score := maxf(float(item.get("score", 0.0)), 0.0)
		var weight := score / total
		components.append({"id": String(entry.get("id", "neutral")), "weight": weight, "score": score})
		for morph_name in entry.get("morph_weights", {}):
			merged_weights[morph_name] = float(merged_weights.get(morph_name, 0.0)) + float(entry["morph_weights"][morph_name]) * weight
		for bone_name in entry.get("bone_fallback", {}):
			merged_bones[bone_name] = float(merged_bones.get(bone_name, 0.0)) + float(entry["bone_fallback"][bone_name]) * weight
		fade += float(entry.get("fade_duration", 0.16)) * weight
		hold = maxf(hold, float(entry.get("hold_seconds", entry.get("transient_seconds", 0.0))))

	var primary: Dictionary = selected[0]["entry"]
	return {
		"expression": String(primary.get("id", "neutral")),
		"display_name": String(primary.get("display_name", primary.get("id", "neutral"))),
		"morph_weights": merged_weights,
		"bone_fallback": merged_bones,
		"fade_duration": fade,
		"hold_seconds": hold,
		"transient_seconds": float(primary.get("transient_seconds", 0.0)),
		"intensity": clampf(intensity, 0.0, 1.0),
		"confidence": clampf(float(selected[0].get("score", 0.0)), 0.0, 1.0),
		"provider": "expression_router",
		"components": components,
	}


func _best_alias_match(normalized: String) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 0.0
	for entry in _entries:
		for alias_value in entry.get("aliases", []):
			var alias := _normalize(String(alias_value))
			if alias.is_empty() or alias not in normalized:
				continue
			var score := 0.65 + minf(float(alias.length()) / 12.0, 0.35)
			if score > best_score:
				best_score = score
				best = {"entry": entry, "score": score}
	return best


func _find_entry(expression_id: String) -> Dictionary:
	var normalized := _normalize(expression_id)
	for entry in _entries:
		if _normalize(String(entry.get("id", ""))) == normalized:
			return entry
	for entry in _entries:
		if String(entry.get("id", "")) == "neutral":
			return entry
	return {"id": "neutral", "morph_weights": {}, "fade_duration": 0.16}


func _entry_text(entry: Dictionary) -> String:
	var parts: Array[String] = [
		String(entry.get("id", "")),
		String(entry.get("display_name", "")),
		String(entry.get("description", "")),
	]
	for alias in entry.get("aliases", []):
		parts.append(String(alias))
	return " ".join(parts)


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
				vector[int(hash_value % dimensions)] += 1.0 if hash_value % 2 == 0 else -1.0
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


func _cosine_dense(vector: PackedFloat32Array, centroid: Variant) -> float:
	if not centroid is PackedFloat32Array:
		return -1.0
	var total := 0.0
	var count = mini(vector.size(), centroid.size())
	for index in range(count):
		total += vector[index] * centroid[index]
	return total


func _normalize(text: String) -> String:
	return text.strip_edges().to_lower() \
		.replace("，", " ") \
		.replace("。", " ") \
		.replace("！", " ") \
		.replace("？", " ") \
		.replace(",", " ") \
		.replace(".", " ") \
		.replace("!", " ") \
		.replace("?", " ")


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		load_error = "missing expression library: %s" % path
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		load_error = "invalid expression library: %s" % path
		return {}
	return parsed
