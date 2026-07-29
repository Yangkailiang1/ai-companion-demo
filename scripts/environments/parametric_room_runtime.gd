# Roadmap: S1.2, S2.2, S4.1
# Responsibility: Assemble one playable generated room, its shared cast and
# visible travel portals; does not choose world mode or implement generation
# algorithms.
# Collaborators: ParametricSceneBuilder, WorldCastAssembler, WorldTravelPortal,
# SaveSystem
# Tests: scripts/debug/world_location_loader_check.gd,
# scripts/debug/cross_location_save_check.gd,
# scripts/debug/world_travel_portal_check.gd

extends Node3D

const WorldPortalAssemblerScript = preload("res://scripts/environments/world_portal_assembler.gd")
const RoomLightingScript = preload("res://scripts/environments/parametric_room_lighting.gd")

## [S2.2] 入口旅行请求；由 WorldLocationLoader 连接并处理。
signal portal_travel_requested(exit_id: String)
signal portal_walkthrough_requested(exit_id: String)

@export_file("*.json") var manifest_path := \
	"res://data/scene_generation/manifests/living_room_shadow.seed42.manifest.json"
@export_file("*.json") var registry_path := \
	"res://data/scene_generation/registries/living_room_shadow_registry.json"

var build_report: Dictionary = {}
var assembled_cast: Array[String] = []
var portal_paths: Array[String] = []
var location_id := "living_room"
var location_description := ""
var cast_spawns: Dictionary = {}
var cast_members: Array[String] = ["Agent", "JueAgent", "LocalCharacterSpawner"]
var local_character_manifests: Array[String] = []
var _location_spawns_restored := false
var _exits: Dictionary = {}
var _location_active := true
var _cast_retire_serial := 0
var _room_lighting: ParametricRoomLighting


## [S2.2] 在节点入树前注入地点资源、角色出生策略与出口入口数据。
func configure_location(location_data: Dictionary) -> void:
	location_id = String(location_data.get("location_id", location_id))
	set_meta("location_id", location_id)
	manifest_path = String(location_data.get("manifest_path", manifest_path))
	registry_path = String(location_data.get("registry_path", registry_path))
	location_description = String(location_data.get("scene_description", ""))
	cast_spawns = location_data.get("cast_spawns", {}).duplicate(true)
	cast_members.assign(location_data.get(
		"cast_members", WorldCastAssembler.CAST_NODE_NAMES
	))
	local_character_manifests.assign(
		location_data.get("local_character_manifests", [])
	)
	_exits = location_data.get("exits", {}).duplicate(true)
	_location_active = bool(location_data.get("runtime_active", true))


## [S1.2][S2.2][S4.1] 构建房间、数据驱动灯光、角色与可见入口。
func _ready() -> void:
	var manifest := _load_json(manifest_path)
	var registry := _load_json(registry_path)
	if manifest.is_empty() or registry.is_empty():
		push_error("ParametricRoomRuntime: manifest or registry unavailable")
		return
	build_report = ParametricSceneBuilder.new().build_room(self, manifest, registry)
	_configure_room_lighting(manifest.get("room", {}))
	assembled_cast = WorldCastAssembler.new().assemble_into(
		self, cast_members, local_character_manifests
	)
	_set_navigation_enabled(_location_active)
	call_deferred("_sync_navigation")
	_activate_portals()
	if not _location_active:
		deactivate_portals()


## [S4.1] 读取并解析项目内 JSON；失败返回空 Dictionary，不创建部分房间。
func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


## [S2.1][S4.2][X1.2] 等待地点进入 World3D 后上传运行时 NavigationMesh 并强制同步。
## 生成网格在入树前逐多边形构造，不能依赖 Godot 的隐式上传时序。
## 出生点阶段后触发 SaveSystem 延迟应用，使存档位置覆盖声明出生点。
func _sync_navigation() -> void:
	await get_tree().physics_frame
	_restore_location_spawns()
	_location_spawns_restored = true
	# [X1.2] 出生点已恢复，若存在匹配当前位置的存档 Agent 状态则覆盖出生点
	var save_system := get_node_or_null("/root/SaveSystem")
	if save_system != null and save_system.has_method(
		"apply_pending_agent_states_for_location"
	):
		save_system.apply_pending_agent_states_for_location(location_id)
	var region := get_node_or_null(
		"GeneratedRoom/Structure/NavigationRegion3D"
	) as NavigationRegion3D
	if region == null or region.navigation_mesh == null:
		return
	if not _location_active:
		return
	NavigationServer3D.region_set_navigation_mesh(region.get_rid(), region.navigation_mesh)
	var map_rid := region.get_navigation_map()
	if map_rid != RID():
		NavigationServer3D.map_force_update(map_rid)


## [X1.2] 返回地点声明出生点是否已经写入 Cast；纯读取。
func are_location_spawns_restored() -> bool:
	return _location_spawns_restored


## [S2.2][C5.3] 按居民注册表增删当前房间表现节点，不重建几何或移动玩家。
func reconcile_cast(policy: Dictionary) -> void:
	var next_members: Array = policy.get("cast_members", [])
	var next_manifests: Array = policy.get("local_character_manifests", [])
	for node_name in WorldCastAssembler.CAST_NODE_NAMES:
		var existing := get_node_or_null(node_name)
		var should_exist: bool = node_name in next_members
		if (
			node_name == "LocalCharacterSpawner"
			and existing != null
			and should_exist
			and existing.get_meta("residency_manifest_paths", []) != next_manifests
		):
			should_exist = false
		if existing != null and not should_exist:
			_cast_retire_serial += 1
			existing.name = "RetiringCast_%d" % _cast_retire_serial
			if existing is Node3D:
				(existing as Node3D).visible = false
			_free_cast_after_grace(existing)
	var added := WorldCastAssembler.new().assemble_into(
		self, next_members, next_manifests
	)
	cast_members.assign(next_members)
	local_character_manifests.assign(next_manifests)
	_restore_location_spawns(added)


## [C5.3][T4.2] 给角色动画初始化协程两帧收尾，避免跨房时恢复到已释放实例。
func _free_cast_after_grace(actor: Node) -> void:
	for _frame in range(2):
		await get_tree().process_frame
	if is_instance_valid(actor):
		actor.queue_free()


## [S2.1][X1] 在存档尚未包含 location_id 时恢复当前地点声明的出生点。
## 避免把 legacy 客厅坐标直接套到参数化布局；X1 v2 后由位置迁移器替代。
func _restore_location_spawns(node_names: Array = ["Agent", "JueAgent"]) -> void:
	for node_name in node_names:
		var actor := get_node_or_null(node_name) as Node3D
		if actor == null:
			continue
		var spawn = cast_spawns.get(node_name, {})
		if spawn is Dictionary and not spawn.is_empty():
			actor.position = _array_to_vector3(spawn.get("position", []), actor.position)
			var degrees := _array_to_vector3(spawn.get("rotation_deg", []), Vector3.ZERO)
			actor.rotation_degrees = degrees
		elif actor.has_meta("location_spawn_position"):
			actor.position = actor.get_meta("location_spawn_position")
			actor.rotation = actor.get_meta("location_spawn_rotation")


## [S2.2] 从已校验出口数据创建可见入口，并将每个入口的 travel_requested
## 信号转发为当前房间的 portal_travel_requested 信号。
## 副作用：在房间下创建 WorldTravelPortal 节点。
func _activate_portals() -> void:
	if _exits.is_empty():
		return
	var portals: Array = WorldPortalAssemblerScript.new().assemble(self, _exits, location_id)
	for portal in portals:
		portal.travel_requested.connect(_on_portal_travel_requested)
		portal.walkthrough_requested.connect(_on_portal_walkthrough_requested)
		portal_paths.append(String(portal.name))


## [S2.2] 入口旅行转发；简单委托该房间的信号发出请求。
func _on_portal_travel_requested(exit_id: String) -> void:
	portal_travel_requested.emit(exit_id)


## [S2.2][P2.3] 转发玩家身体穿门事件，不触发点击传送。
func _on_portal_walkthrough_requested(exit_id: String) -> void:
	portal_walkthrough_requested.emit(exit_id)


## [S2.2] 地点退役前停用所有门廊，避免两帧宽限期内陈旧点击触发旅行。
func deactivate_portals() -> void:
	for portal_path in portal_paths:
		var portal := get_node_or_null(portal_path)
		if portal != null and portal.has_method("deactivate"):
			portal.deactivate()


## [S2.5] 房间重新成为活动地点时恢复门的点击与身体穿越。
func reactivate_portals() -> void:
	for portal_path in portal_paths:
		var portal := get_node_or_null(portal_path)
		if portal != null and portal.has_method("reactivate"):
			portal.reactivate()


## [S2.5][C5.3] 几何与碰撞始终常驻，仅当前语义房间参与导航寻路。
func set_location_active(active: bool) -> void:
	_location_active = active
	_set_navigation_enabled(active)
	if is_instance_valid(_room_lighting):
		_room_lighting.set_active(active)
	if active:
		reactivate_portals()
		refresh_semantic_registration()
	else:
		deactivate_portals()


## [S1.2][S4.1] 用 Manifest 灯光块替换模板场景中的固定灯光。
## 旧灯节点先删除，避免拼接住宅出现四盏无限 DirectionalLight 叠加。
func _configure_room_lighting(room_data: Dictionary) -> void:
	for legacy_name in ["DirectionalLight3D", "WarmFillLight"]:
		var legacy_light := get_node_or_null(legacy_name)
		if legacy_light != null:
			legacy_light.free()
	_room_lighting = RoomLightingScript.new()
	_room_lighting.name = "RoomLighting"
	add_child(_room_lighting)
	_room_lighting.configure(room_data.get("lighting", {}))
	_room_lighting.set_active(_location_active)


## [S2.5] 切换生成房间导航区；不存在导航区时安全跳过。
func _set_navigation_enabled(enabled: bool) -> void:
	var region := get_node_or_null(
		"GeneratedRoom/Structure/NavigationRegion3D"
	) as NavigationRegion3D
	if region != null:
		region.enabled = enabled


## [S2.5][X1.2] 常驻房间再次激活时重发语义绑定，支持存档模拟重启和节点替换。
func refresh_semantic_registration() -> void:
	var semantic_world := get_node_or_null("/root/SemanticWorld")
	if semantic_world == null:
		return
	for child in get_children():
		if not child.has_meta("semantic_payload"):
			continue
		var interaction_node := child as Node3D
		var body := child.get_node_or_null("PhysicsBody") as Node3D
		if body != null:
			interaction_node = body
		semantic_world.upsert_generated_object(
			child.get_meta("semantic_payload", {}).duplicate(true),
			interaction_node,
		)
	for portal_path in portal_paths:
		var portal := get_node_or_null(portal_path)
		if portal != null and portal.has_method("refresh_semantic_registration"):
			portal.refresh_semantic_registration()


## [S2.5][P2.3] 让最靠近玩家的目标房门保持开启，隐藏成对门切换的视觉跳变。
func open_nearest_portal(world_position: Vector3) -> void:
	var nearest: Node3D
	var nearest_distance := INF
	for portal_path in portal_paths:
		var portal := get_node_or_null(portal_path) as Node3D
		if portal == null:
			continue
		var distance := portal.global_position.distance_to(world_position)
		if distance < nearest_distance:
			nearest = portal
			nearest_distance = distance
	if nearest != null and nearest.has_method("open_temporarily"):
		nearest.open_temporarily()


## [S2.2] 激活当前房间的语义可见域，使 AI 只读取所在地点物体。
func _activate_semantic_location() -> void:
	var semantic_world := get_node_or_null("/root/SemanticWorld")
	if semantic_world != null and semantic_world.has_method("set_active_location"):
		semantic_world.set_active_location(location_id, location_description)


## [S2.2] 将 JSON 三元数组安全转换为 Vector3。
func _array_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
