# headless_check.gd — load and instantiate the real startup scene.
# Run with: Godot --headless --path . --script scripts/debug/headless_check.gd

extends SceneTree

func _init() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	# Autoloads must finish initializing before scripts that reference their global
	# names are compiled. Running this deferred prevents false compile failures.
	await process_frame
	print("\n=== [Headless Check] Startup scene ===")
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("FAILED to load res://scenes/main.tscn")
		quit(1)
		return
	var scene := packed.instantiate()
	if scene == null:
		push_error("FAILED to instantiate res://scenes/main.tscn")
		quit(1)
		return
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		push_error("Penguin AnimationPlayer not found")
		quit(1)
		return
	var required := ["idle", "walk", "wave", "nod", "think", "happy", "sit"]
	for animation_name in required:
		if not player.has_animation(animation_name):
			push_error("Missing penguin animation: %s" % animation_name)
			quit(1)
			return
	var garden_packed := load("res://scenes/environments/endless_garden_preview.tscn") as PackedScene
	var garden := garden_packed.instantiate() if garden_packed else null
	if garden == null:
		push_error("Garden preview failed to instantiate")
		quit(1)
		return
	garden.free()
	print("  Startup scene instantiated successfully")
	print("  Penguin animations: ", required)
	print("  Garden preview instantiated successfully")
	print("=== PASS ===\n")
	quit(0)
