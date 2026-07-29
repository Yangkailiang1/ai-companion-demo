# Roadmap: C5.3, C5.6, S2.5, S5
# Responsibility: Advance low-frequency symbolic activities for residents who
# are outside the player's active room. Does not instantiate characters,
# navigate meshes, animate models or call an LLM.
# Collaborators: AgentResidencyRegistry, WorldSimulator, MemorySystem,
# AgentPsycheSystem, WorldLocationLoader
# Tests: scripts/debug/offscreen_life_simulation_check.gd

class_name OffscreenLifeSimulator
extends Node

const BACKGROUND_TICK_SECONDS := 30.0
const MAX_EVENTS_PER_LOCATION := 8

var _journal_by_location: Dictionary = {}
var _round_robin_index := 0
var _enabled := true
var _timer: Timer
var _world_simulator: Node
var _memory_system: Node
var _profiles: Node
var _message_bus: Node


## [C5.6][S5] 连接游戏小时和玩家到达事件，并启动低频后台时钟。
func _ready() -> void:
	_world_simulator = get_node("/root/WorldSimulator")
	_memory_system = get_node("/root/MemorySystem")
	_profiles = get_node("/root/CodifiedProfile")
	_message_bus = get_node("/root/MessageBus")
	_world_simulator.game_hour_advanced.connect(_on_game_hour_advanced)
	var loader := get_parent() as WorldLocationLoader
	if loader != null:
		loader.world_location_loaded.connect(_on_player_arrived)
	_timer = Timer.new()
	_timer.name = "BackgroundLifeTimer"
	_timer.wait_time = BACKGROUND_TICK_SECONDS
	_timer.timeout.connect(_on_background_tick)
	add_child(_timer)
	_timer.start()


## [C5.6] 测试或演出工具可暂停后台 tick；不影响已保存状态。
func set_simulation_enabled(enabled: bool) -> void:
	_enabled = enabled
	if _timer != null:
		_timer.paused = not enabled


## [C5.6][S5] 对所有离屏居民执行一个游戏小时，并允许按作息迁移一跳。
func _on_game_hour_advanced(day: int, hour: float) -> void:
	if _enabled:
		simulate_now(true, day, hour)


## [C5.6] 现实时间低频 tick 只推进一名居民，防止后台日志和需求增长过快。
func _on_background_tick() -> void:
	if _enabled:
		simulate_now(
			false,
			int(_world_simulator.get("day_number")),
			float(_world_simulator.get("game_time")),
		)


## [C5.3][C5.6] 推进离屏生活；返回本轮生成事件，便于诊断与验收。
func simulate_now(
	simulate_all: bool = false,
	day: int = 1,
	hour: float = 8.0,
) -> Array[Dictionary]:
	if (
		has_node("/root/ExperienceModeManager")
		and get_node("/root/ExperienceModeManager").is_performance_mode()
	):
		return []
	var loader := get_parent() as WorldLocationLoader
	var residency := loader.get_residency_registry() if loader != null else null
	if loader == null or residency == null or loader.current_mode != "parametric":
		return []
	var candidates: Array[String] = []
	var locations := residency.get_agent_locations()
	for agent_id_value in locations:
		var agent_id := String(agent_id_value)
		if String(locations[agent_id]) != loader.current_location_id:
			candidates.append(agent_id)
	candidates.sort()
	if candidates.is_empty():
		return []
	if not simulate_all:
		var selected := candidates[_round_robin_index % candidates.size()]
		_round_robin_index += 1
		candidates = [selected]
	var events: Array[Dictionary] = []
	for agent_id in candidates:
		var event := _simulate_resident(loader, residency, agent_id, day, hour, simulate_all)
		if not event.is_empty():
			events.append(event)
	return events


## [C5.3][C5.6] 推进单个居民的位置、需求、心理完成记录和情景记忆。
func _simulate_resident(
	loader: WorldLocationLoader,
	residency: AgentResidencyRegistry,
	agent_id: String,
	day: int,
	hour: float,
	allow_relocation: bool,
) -> Dictionary:
	var location_id := residency.get_agent_location(agent_id)
	if allow_relocation:
		var destination := _desired_location(agent_id, hour)
		if destination != loader.current_location_id and destination != location_id:
			var next_hop := _next_hop(loader.get_location_catalog(), location_id, destination)
			if not next_hop.is_empty() and next_hop != loader.current_location_id:
				residency.move_agent(agent_id, next_hop)
				location_id = next_hop
	var activity := _activity_for(agent_id, location_id)
	_apply_activity_effect(agent_id, String(activity.id))
	var display_name := String(_profiles.get_agent_display_name(agent_id))
	var summary := "%s在%s%s。" % [
		display_name,
		_location_name(loader, location_id),
		String(activity.summary),
	]
	_memory_system.add_episode_for_agent(agent_id, "玩家不在场时，" + summary, 2.5)
	_message_bus.agent_activity_completed.emit(agent_id, String(activity.id), {
		"offscreen": true,
		"location_id": location_id,
		"day": day,
		"hour": hour,
	})
	var event := {
		"agent_id": agent_id,
		"location_id": location_id,
		"activity_id": String(activity.id),
		"summary": summary,
		"day": day,
		"hour": hour,
	}
	_append_journal(location_id, event)
	_message_bus.world_state_changed.emit("offscreen_activity_completed", event)
	return event


## [C5.3] 根据需求和房间能力选择低成本符号活动。
func _activity_for(agent_id: String, location_id: String) -> Dictionary:
	var needs: AffordanceTypes.NeedsState = _world_simulator.get_needs_for_agent(agent_id)
	if needs.energy < 28.0:
		return {"id": "rest_offscreen", "summary": "安静地休息了一会儿"}
	if needs.hunger < 35.0 and location_id == "kitchen":
		return {"id": "prepare_meal", "summary": "给自己准备了一份简单的食物"}
	match location_id:
		"kitchen": return {"id": "prepare_meal", "summary": "收拾了餐桌并准备了一点吃的"}
		"bedroom": return {"id": "rest_offscreen", "summary": "整理床铺后坐着休息"}
		"study": return {"id": "read_offscreen", "summary": "翻了几页书，记下新的想法"}
		_: return {"id": "tidy_room", "summary": "把周围的小东西整理了一遍"}


## [C5.6][S5] 将符号活动结果写入该角色独立需求。
func _apply_activity_effect(agent_id: String, activity_id: String) -> void:
	match activity_id:
		"prepare_meal":
			_world_simulator.apply_effect(AffordanceTypes.NeedType.HUNGER, 14.0, agent_id)
			_world_simulator.apply_effect(AffordanceTypes.NeedType.FUN, 2.0, agent_id)
		"rest_offscreen":
			_world_simulator.apply_effect(AffordanceTypes.NeedType.ENERGY, 12.0, agent_id)
		"read_offscreen":
			_world_simulator.apply_effect(AffordanceTypes.NeedType.FUN, 10.0, agent_id)
		"tidy_room":
			_world_simulator.apply_effect(AffordanceTypes.NeedType.FUN, 4.0, agent_id)


## [C5.3] 按时间段和稳定 agent_id 分流日常目的地，避免所有居民同步移动。
func _desired_location(agent_id: String, hour: float) -> String:
	var lane := absi(agent_id.hash()) % 3
	if hour >= 22.0 or hour < 6.0:
		return "bedroom"
	if hour < 10.0:
		return "kitchen" if lane != 0 else "living_room"
	if hour < 17.0:
		return "study" if lane != 1 else "living_room"
	if hour < 22.0:
		return "living_room" if lane != 2 else "kitchen"
	return "living_room"


## [S2.5][C5.3] 在地点图上广度优先查找目标方向的第一跳。
func _next_hop(catalog: WorldLocationCatalog, source: String, target: String) -> String:
	if source == target:
		return source
	var queue: Array[Dictionary] = [{"location": source, "first": ""}]
	var visited := {source: true}
	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		var location := catalog.get_location(String(item.location))
		for exit_id in location.get("exits", {}):
			var edge: Dictionary = location.exits[exit_id]
			var next_id := String(edge.get("target_location_id", ""))
			if next_id.is_empty() or visited.has(next_id):
				continue
			var first := next_id if String(item.first).is_empty() else String(item.first)
			if next_id == target:
				return first
			visited[next_id] = true
			queue.append({"location": next_id, "first": first})
	return ""


## [C5.6] 玩家进入房间时把后台生活痕迹显示为折叠聊天与状态提示。
func _on_player_arrived(location_id: String, _room: Node3D) -> void:
	var events: Array = _journal_by_location.get(location_id, [])
	if events.is_empty():
		return
	var event: Dictionary = events[-1]
	var summary := String(event.get("summary", ""))
	if summary.is_empty():
		return
	_message_bus.ui_add_chat_entry.emit("life_trace", summary, false)
	_message_bus.ui_status_changed.emit("生活痕迹：%s" % summary, "ready")


## [C5.6] 追加有界地点日志。
func _append_journal(location_id: String, event: Dictionary) -> void:
	var events: Array = _journal_by_location.get(location_id, [])
	events.append(event.duplicate(true))
	while events.size() > MAX_EVENTS_PER_LOCATION:
		events.pop_front()
	_journal_by_location[location_id] = events


## [C5.6][X1.2] 返回指定地点日志副本。
func get_location_journal(location_id: String) -> Array:
	return _journal_by_location.get(location_id, []).duplicate(true)


## [C5.6][X1.2] 导出/导入有界离屏生活日志。
func export_save_state() -> Dictionary:
	return {"journal_by_location": _journal_by_location.duplicate(true)}


func import_save_state(data: Dictionary) -> void:
	var incoming = data.get("journal_by_location", {})
	if incoming is Dictionary:
		_journal_by_location = incoming.duplicate(true)


## [S2.5] 返回地点显示名。
func _location_name(loader: WorldLocationLoader, location_id: String) -> String:
	return String(
		loader.get_location_catalog().get_location(location_id).get("display_name", location_id)
	)
