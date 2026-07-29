# Roadmap: S2.2, S2.5, C5.3, X1.2
# Responsibility: Persist each agent's logical WorldLocation and resolve which
# character scenes should be materialized in one loaded room. Does not load
# rooms, move the player, run navigation or choose autonomous goals.
# Collaborators: WorldLocationCatalog, WorldLocationLoader, WorldCastAssembler
# Tests: scripts/debug/agent_residency_check.gd

class_name AgentResidencyRegistry
extends Node

signal residency_changed(agent_id: String, from_location: String, to_location: String)

const FIXED_CAST_NODES := {
	"main_agent": "Agent",
	"jue_agent": "JueAgent",
}

var _agent_locations: Dictionary = {}
var _companions: Array[String] = []
var _local_manifests: Dictionary = {}
var _valid_locations: Array[String] = []
var _configured := false


## [S2.2][C5.3] 首次加载地点目录时建立稳定居民归属；重复调用不覆盖运行时迁移。
func configure(
	agent_locations: Dictionary,
	companion_ids: Array,
	local_manifests: Dictionary,
	valid_locations: Array,
) -> bool:
	if _configured:
		return true
	var valid: Array[String] = []
	for location_id in valid_locations:
		valid.append(String(location_id))
	if not _validate_locations(agent_locations, valid):
		return false
	_valid_locations = valid
	_agent_locations = agent_locations.duplicate(true)
	_companions.assign(companion_ids)
	_local_manifests = local_manifests.duplicate(true)
	_configured = true
	return true


## [S2.2] 返回某地点应实体化的固定 Cast 与本地角色 manifest。
func get_cast_policy(location_id: String) -> Dictionary:
	var members: Array[String] = []
	var manifests: Array[String] = []
	for agent_id in FIXED_CAST_NODES:
		if _is_present(agent_id, location_id):
			members.append(String(FIXED_CAST_NODES[agent_id]))
	for agent_id in _local_manifests:
		if _is_present(String(agent_id), location_id):
			manifests.append(String(_local_manifests[agent_id]))
	if not manifests.is_empty():
		members.append("LocalCharacterSpawner")
	return {"cast_members": members, "local_character_manifests": manifests}


## [C5.3][S2.2] 原子更新单个角色的逻辑地点，并广播迁移。
func move_agent(agent_id: String, target_location: String) -> bool:
	if not _configured or agent_id not in _agent_locations:
		return false
	if target_location not in _valid_locations:
		return false
	var previous := String(_agent_locations[agent_id])
	if previous == target_location:
		return true
	_agent_locations[agent_id] = target_location
	residency_changed.emit(agent_id, previous, target_location)
	return true


## [P2.3][S2.2] 玩家旅行时只迁移明确声明的随行角色。
func move_companions(target_location: String) -> void:
	for agent_id in _companions:
		move_agent(agent_id, target_location)


## [C5.3] 返回角色当前逻辑地点；未知角色返回空字符串。
func get_agent_location(agent_id: String) -> String:
	return String(_agent_locations.get(agent_id, ""))


## [X1.2] 导出纯数据居民位置，供存档和离屏模拟复用。
func export_save_state() -> Dictionary:
	return {"agent_locations": _agent_locations.duplicate(true)}


## [X1.2] 校验后导入居民位置；坏条目不覆盖当前有效状态。
func import_save_state(state: Dictionary) -> bool:
	var locations = state.get("agent_locations", {})
	if not locations is Dictionary or not _validate_locations(locations, _valid_locations):
		return false
	for agent_id in locations:
		if agent_id in _agent_locations:
			_agent_locations[agent_id] = String(locations[agent_id])
	return true


## [S2.2] 随行角色和固定居民使用同一实体化查询。
func _is_present(agent_id: String, location_id: String) -> bool:
	return (
		agent_id in _companions
		or String(_agent_locations.get(agent_id, "")) == location_id
	)


## [S2.2][X1.2] 所有 agent/location 必须是非空字符串且地点存在。
func _validate_locations(locations: Dictionary, valid: Array[String]) -> bool:
	for agent_id in locations:
		if String(agent_id).is_empty():
			return false
		var location_id := String(locations[agent_id])
		if location_id.is_empty() or location_id not in valid:
			return false
	return true
