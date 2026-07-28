# parametric_shadow_recipe_check.gd — verify the shadow recipe matches the
# current living room scene configuration.
# Run with: Godot --headless --path . --script scripts/debug/parametric_shadow_recipe_check.gd
#
# Verifies: S4.1
# Responsibility: Ensure the parameterized recipe preserves every legacy
# semantic object ID/position while allowing additional generated ambience.

extends SceneTree


func _init() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	print("\n=== [Parametric Shadow Recipe Check] ===")

	# -----------------------------------------------------------------------
	# 1. Load the scene config (authoritative source for current scene)
	# -----------------------------------------------------------------------
	var config_file := FileAccess.open("res://data/scene_config.json", FileAccess.READ)
	if config_file == null:
		printerr("FAIL: could not open data/scene_config.json")
		quit(1)
		return

	var config_text := config_file.get_as_text()
	config_file.close()

	var config_json := JSON.new()
	var parse_err := config_json.parse(config_text)
	if parse_err != OK:
		printerr("FAIL: could not parse scene_config.json: %d" % parse_err)
		quit(1)
		return

	var config_data: Dictionary = config_json.get_data()
	if config_data == null:
		printerr("FAIL: scene_config.json parsed to null")
		quit(1)
		return

	var config_objects = config_data.get("objects", []) as Array
	if config_objects.is_empty():
		printerr("FAIL: scene_config.json has no objects array")
		quit(1)
		return

	# Build lookup from config: semantic_id -> config entry
	var config_lookup: Dictionary = {}
	for obj in config_objects:
		var sid: String = obj.get("id", "")
		if sid.is_empty():
			printerr("FAIL: object in scene_config.json missing 'id' field")
			quit(1)
			return
		if config_lookup.has(sid):
			printerr("FAIL: duplicate semantic id '%s' in scene_config.json" % sid)
			quit(1)
			return
		config_lookup[sid] = obj

	print("  scene_config.json: %d objects loaded" % config_lookup.size())

	# -----------------------------------------------------------------------
	# 2. Load the shadow recipe
	# -----------------------------------------------------------------------
	var recipe_file := FileAccess.open("res://data/scene_generation/recipes/living_room_shadow.recipe.json", FileAccess.READ)
	if recipe_file == null:
		printerr("FAIL: could not open shadow recipe")
		quit(1)
		return

	var recipe_text := recipe_file.get_as_text()
	recipe_file.close()

	var recipe_json := JSON.new()
	parse_err = recipe_json.parse(recipe_text)
	if parse_err != OK:
		printerr("FAIL: could not parse shadow recipe: %d" % parse_err)
		quit(1)
		return

	var recipe_data: Dictionary = recipe_json.get_data()
	if recipe_data == null:
		printerr("FAIL: shadow recipe parsed to null")
		quit(1)
		return

	var recipe_slots = recipe_data.get("object_slots", []) as Array
	if recipe_slots.is_empty():
		printerr("FAIL: shadow recipe has no object_slots")
		quit(1)
		return

	# Build lookup from recipe: semantic_id -> slot
	var recipe_lookup: Dictionary = {}
	for slot in recipe_slots:
		var sid: String = slot.get("semantic_id", "")
		if sid.is_empty():
			printerr("FAIL: recipe slot missing semantic_id")
			quit(1)
			return
		if recipe_lookup.has(sid):
			printerr("FAIL: duplicate semantic_id '%s' in recipe object_slots" % sid)
			quit(1)
			return
		recipe_lookup[sid] = slot

	print("  shadow recipe: %d object_slots loaded" % recipe_lookup.size())

	# -----------------------------------------------------------------------
	# 3. Verify all legacy semantic object IDs remain compatible.
	# -----------------------------------------------------------------------
	var config_ids: Array = config_lookup.keys()
	var recipe_ids: Array = recipe_lookup.keys()

	# Sort for comparison
	config_ids.sort()
	recipe_ids.sort()

	print("\n  config IDs (%d): %s" % [config_ids.size(), config_ids])
	print("  recipe IDs (%d): %s" % [recipe_ids.size(), recipe_ids])

	for sid in config_ids:
		if not recipe_lookup.has(sid):
			printerr("FAIL: semantic_id '%s' is in scene_config.json but NOT in recipe" % sid)
			quit(1)
			return

	print("\n  Legacy semantic compatibility: OK (%d preserved, %d generated additions)" % [
		config_ids.size(), recipe_ids.size() - config_ids.size(),
	])

	# -----------------------------------------------------------------------
	# 4. Verify positions agree within 0.001 m
	# -----------------------------------------------------------------------
	var tolerance := 0.001
	var failed_positions := 0

	for sid in config_ids:
		var cfg_obj: Dictionary = config_lookup[sid]
		var rcp_slot: Dictionary = recipe_lookup[sid]

		var cfg_pos = cfg_obj.get("position", []) as Array
		var rcp_pos = rcp_slot.get("position", []) as Array

		if cfg_pos.size() < 3 or rcp_pos.size() < 3:
			printerr("FAIL: '%s': position array too short — config=%s, recipe=%s" % [sid, cfg_pos, rcp_pos])
			quit(1)
			return

		for i in range(3):
			var diff: float = float(cfg_pos[i]) - float(rcp_pos[i])
			var delta: float = abs(diff)
			if delta > tolerance:
				printerr(
					"FAIL: '%s': position[%d] mismatch — config=%s, recipe=%s (delta=%.6f)"
					% [sid, i, cfg_pos, rcp_pos, delta]
				)
				failed_positions += 1

		# Also check interaction_point
		var cfg_ip = cfg_obj.get("interaction_point", []) as Array
		var rcp_ip = rcp_slot.get("interaction_point", []) as Array

		if cfg_ip.size() >= 3 and rcp_ip.size() >= 3:
			for i in range(3):
				var diff2: float = float(cfg_ip[i]) - float(rcp_ip[i])
				var delta2: float = abs(diff2)
				if delta2 > tolerance:
					printerr(
						"FAIL: '%s': interaction_point[%d] mismatch — config=%s, recipe=%s (delta=%.6f)"
						% [sid, i, cfg_ip, rcp_ip, delta2]
					)
					failed_positions += 1

	if failed_positions > 0:
		printerr("FAIL: %d position mismatches found" % failed_positions)
		quit(1)
		return

	print("  Position match: OK (all within %.3f m tolerance)" % tolerance)

	# -----------------------------------------------------------------------
	# 5. Load the living_room.tscn to verify it exists and is loadable
	# -----------------------------------------------------------------------
	var packed := load("res://scenes/living_room.tscn") as PackedScene
	if packed == null:
		printerr("FAIL: could not load living_room.tscn")
		quit(1)
		return

	var scene_instance := packed.instantiate()
	if scene_instance == null:
		printerr("FAIL: could not instantiate living_room.tscn")
		quit(1)
		return
	var scene_ids: Array[String] = []
	_collect_scene_object_ids(scene_instance, scene_ids)
	scene_ids.sort()
	for scene_id in scene_ids:
		if not recipe_lookup.has(scene_id):
			printerr("FAIL: legacy scene ID missing from recipe: %s" % scene_id)
			scene_instance.free()
			quit(1)
			return
	scene_instance.free()

	print("  living_room.tscn: loadable; all legacy semantic IDs preserved")

	print("\n=== PASS ===\n")
	quit(0)


## [S4.1] 递归收集场景中声明 object_id 的交互节点，不触发其 _ready 副作用。
func _collect_scene_object_ids(node: Node, output: Array[String]) -> void:
	for property in node.get_property_list():
		if String(property.get("name", "")) == "object_id":
			var object_id := String(node.get("object_id"))
			if not object_id.is_empty():
				output.append(object_id)
			break
	for child in node.get_children():
		_collect_scene_object_ids(child, output)
