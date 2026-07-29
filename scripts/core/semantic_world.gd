# semantic_world.gd — 语义世界模型 (Autoload)
# 设计文档 §四：Object Affordance Graph + 自然语言描述生成
# LLM 不是"看"像素，而是"读"这个模块生成的语义快照

# Roadmap: T2, S2, S4, X1.2
# Responsibility: Register and query semantic objects with location-scoped
# visibility, deferred save-state persistence and structured properties;
# does not own navigation, animation, physics, cognition or UI.
# Collaborators: WorldSimulator, MessageBus, SaveSystem
# Tests: scripts/debug/save_plant_state_check.gd,
# scripts/debug/cross_location_save_check.gd

extends Node

# 场景物体字典: {object_id: ObjectData}
var objects: Dictionary = {}
var active_location_id := "living_room"
## [X1.2] 挂起的对象状态 (未实例化的房间对象)
var _pending_object_states: Dictionary = {}

# 场景定义
var scene_info: Dictionary = {
	"name": "客厅",
	"description": "一个温馨的客厅，阳光从窗户照进来，沙发柔软，茶几上摆着书，餐桌上有杯奶茶"
}


# ObjectData 内部类
class ObjectData:
	var id: String
	var name: String
	var description: String
	var state: String
	var affordances=  []
	var position: Vector3
	var interaction_point: Vector3
	var needs_proximity: bool = true
	var consumable: bool = false
	var effects: Dictionary = {}  # 交互对需求的影响 {need_type: delta}
	var properties: Dictionary = {}
	var occupied_by: String = ""  # 当前占用者（null/agent_id）
	var godot_node: Node3D = null  # 指向 Godot 场景节点的引用

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"description": description,
			"state": state,
			"affordances": affordances,
			"properties": properties.duplicate(true),
		}

	func to_nl() -> String:
		var base = "%s（%s）" % [name, state]
		if description:
			base = "%s（%s）：%s" % [name, state, description]
		return base


## [T2] 模块就绪时加载场景配置。
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_scene_config()


func _load_scene_config() -> void:
	var config = _load_json("res://data/scene_config.json")
	if not config or not config.has("objects"):
		_create_default_objects()
		return

	if config.has("scene_info"):
		scene_info = config["scene_info"]

	for obj_data in config["objects"]:
		var obj = ObjectData.new()
		obj.id = obj_data["id"]
		obj.name = obj_data["name"]
		obj.description = obj_data.get("description", "")
		obj.state = obj_data.get("state", "")
		obj.affordances.assign(obj_data.get("affordances", []))
		obj.position = _dict_to_vec3(obj_data.get("position", [0, 0, 0]))
		obj.interaction_point = _dict_to_vec3(obj_data.get("interaction_point", obj.position + Vector3(0, 0, -1)))
		obj.needs_proximity = obj_data.get("needs_proximity", true)
		obj.consumable = obj_data.get("consumable", false)
		obj.effects = obj_data.get("effects", {})
		obj.properties = obj_data.get("properties", {}).duplicate(true)
		objects[obj.id] = obj


func _create_default_objects() -> void:
	objects = {}
	var defaults = [
		{"id": "sofa", "name": "沙发", "description": "一张柔软的布艺沙发", "state": "空着",
		 "affordances": ["sit", "lie_down"], "pos": [0, 0, 2.5], "ip": [0, 0, 1.5]},
		{"id": "tv", "name": "电视机", "description": "40寸液晶电视", "state": "关闭",
		 "affordances": ["turn_on", "turn_off", "watch", "change_channel"], "pos": [0, 0.8, 5.0], "ip": [0, 0, 4.0]},
		{"id": "book", "name": "一本书", "description": "一本翻到第42页的小说", "state": "在茶几上",
		 "affordances": ["read", "pick_up", "put_down"], "pos": [0.5, 0.35, 2.0], "ip": [0.5, 0, 1.5],
		 "effects": {"fun": 20}},
		{"id": "milk_tea", "name": "奶茶", "description": "珍珠奶茶，杯壁挂着水珠", "state": "满满一杯",
		 "affordances": ["drink", "pick_up", "put_down", "throw"], "pos": [2.0, 0.7, 1.5], "ip": [2.0, 0, 1.0],
		 "consumable": true, "effects": {"hunger": -5, "fun": 10}},
		{"id": "plant", "name": "绿植", "description": "一盆翠绿的盆栽", "state": "需要浇水",
		 "affordances": ["water", "prune", "look_at"], "pos": [-2.0, 0, 3.5], "ip": [-2.0, 0, 2.8]},
		{"id": "coffee_table", "name": "茶几", "description": "一张结实的木质茶几", "state": "桌面整洁",
		 "affordances": ["inspect", "place_item"], "pos": [0.65, 0.19, 0.72], "ip": [0.65, 0, -0.05]},
		{"id": "bookshelf", "name": "书架", "description": "靠墙的白色书架", "state": "书籍排列整齐",
		 "affordances": ["browse", "take_book", "put_book_back"], "pos": [3.72, 1.1, -2.05], "ip": [3.05, 0, -1.75]},
		{"id": "room_lights", "name": "客厅壁灯开关", "description": "控制暖色壁灯", "state": "暖光已开启",
		 "affordances": ["turn_on", "turn_off", "dim"], "pos": [-3.82, 1.2, -0.65], "ip": [-3.15, 0, -0.65]},
	]
	for d in defaults:
		var obj = ObjectData.new()
		obj.id = d["id"]
		obj.name = d["name"]
		obj.description = d["description"]
		obj.state = d["state"]
		obj.affordances.assign(d["affordances"])
		obj.position = Vector3(d["pos"][0], d["pos"][1], d["pos"][2])
		obj.interaction_point = Vector3(d["ip"][0], d["ip"][1], d["ip"][2])
		obj.effects = d.get("effects", {})
		obj.consumable = d.get("consumable", false)
		objects[obj.id] = obj


## [S4.2][X1.2] 用生成场景 Manifest 的 placement 新增或刷新语义物体。
## 保留相同 object_id 已有的存档状态，仅同步空间、能力和 Godot 节点引用。
## 若该 id 存在挂起状态则消费并应用。
func upsert_generated_object(data: Dictionary, godot_node: Node3D) -> void:
	var object_id := String(data.get("semantic_id", ""))
	if object_id.is_empty():
		return
	var obj: ObjectData = objects.get(object_id)
	if obj == null:
		obj = ObjectData.new()
		obj.id = object_id
		obj.state = String(data.get("initial_state", ""))
		objects[object_id] = obj
	obj.name = String(data.get("display_name", object_id))
	obj.description = String(data.get("description", ""))
	obj.affordances.assign(data.get("affordances", []))
	obj.position = _dict_to_vec3(data.get("position", [0, 0, 0]))
	obj.interaction_point = _dict_to_vec3(
		data.get("interaction_point", data.get("position", [0, 0, 0]))
	)
	obj.needs_proximity = bool(data.get("needs_proximity", true))
	obj.consumable = bool(data.get("consumable", false))
	obj.effects = data.get("effects", {}).duplicate(true)
	var generated_properties: Dictionary = data.get("properties", {}).duplicate(true)
	generated_properties["location_id"] = String(
		data.get("location_id", active_location_id)
	)
	obj.properties.merge(generated_properties, true)
	obj.godot_node = godot_node
	# [X1.2] 如果有该物体之前的挂起状态，消费并应用到新注册的物体
	if _pending_object_states.has(object_id):
		var pending: Dictionary = _pending_object_states[object_id]
		_apply_pending_state(obj, pending)
		_pending_object_states.erase(object_id)


## [S2.2] 切换 AI 当前可见地点，并更新自然语言场景描述。
func set_active_location(location_id: String, description: String = "") -> void:
	active_location_id = location_id
	if not description.is_empty():
		scene_info = {
			"name": location_id,
			"description": description,
		}


# 获取物体
func get_object(obj_id: String) -> ObjectData:
	var obj: ObjectData = objects.get(obj_id)
	return obj if obj != null and _is_object_in_active_location(obj) else null


## [S2.2] 返回当前地点可见对象 ID，供规划器禁止跨房间幻觉目标。
func get_active_object_ids() -> Array[String]:
	var result: Array[String] = []
	for obj_id in objects:
		if _is_object_in_active_location(objects[obj_id]):
			result.append(String(obj_id))
	return result


## [T2.2][C9.1] 将旧蓝图中的功能引用解析为当前房间具备相同 affordance 的对象。
## 精确 ID 优先；找不到时按能力与少量稳定语义条件选择，不依赖具体模型路径。
func resolve_object_reference(reference_id: String) -> String:
	if get_object(reference_id) != null:
		return reference_id
	var required_affordance := _reference_affordance(reference_id)
	if required_affordance.is_empty():
		return ""
	for item in list_objects():
		var affordances: Array = item.get("affordances", [])
		if required_affordance not in affordances:
			continue
		var candidate_id := String(item.get("id", ""))
		var candidate_name := String(item.get("name", ""))
		var properties: Dictionary = item.get("properties", {})
		if reference_id == "tv" and not (
			"tv" in candidate_id.to_lower() or "电视" in candidate_name
		):
			continue
		if reference_id == "watering_can" and not properties.has("water_amount"):
			continue
		return candidate_id
	return ""


## [T2.2] 返回传统功能引用对应的最低能力合同。
func _reference_affordance(reference_id: String) -> String:
	match reference_id:
		"plant": return "water"
		"sofa": return "sit"
		"book": return "read"
		"milk_tea": return "drink"
		"tv": return "turn_on"
		"watering_can": return "pick_up"
	return ""


# 更新物体状态
func update_object_state(obj_id: String, new_state: String) -> void:
	if objects.has(obj_id):
		objects[obj_id].state = new_state
		MessageBus.world_state_changed.emit("object_state_changed", {
			"object_id": obj_id,
			"new_state": new_state
		})


func update_object_properties(obj_id: String, properties: Dictionary, new_state: String = "") -> void:
	if not objects.has(obj_id):
		return
	objects[obj_id].properties.merge(properties, true)
	if not new_state.is_empty():
		objects[obj_id].state = new_state
	MessageBus.world_state_changed.emit("object_properties_changed", {
		"object_id": obj_id,
		"state": objects[obj_id].state,
		"properties": objects[obj_id].properties.duplicate(true),
	})


## [X1.2] 导出当前已注册物体的状态及仍挂起的未实例化房间物体状态。
func export_save_state() -> Dictionary:
	var result := {}
	for obj_id in objects:
		result[obj_id] = {
			"state": objects[obj_id].state,
			"properties": objects[obj_id].properties.duplicate(true),
		}
	# 合并挂起状态，避免旅途中保存丢失未加载房间的物体状态
	for pending_id in _pending_object_states:
		if not result.has(pending_id):
			result[pending_id] = _pending_object_states[pending_id].duplicate(true)
	return result


## [X1.2] 导入存档物体状态；已注册物体直接应用，未注册的保留为挂起状态。
## 形式错误条目按物体跳过，不清除有效挂起状态。
func import_save_state(data: Dictionary) -> void:
	for obj_id in data:
		var saved := _normalize_saved_object_state(data[obj_id])
		if saved.is_empty():
			continue
		if objects.has(obj_id):
			var obj: ObjectData = objects[obj_id]
			_apply_pending_state(obj, saved)
		else:
			_pending_object_states[obj_id] = saved


## [X1.2] 供测试专用：清空已注册物体和挂起状态以模拟全新运行时。
## 不影响已实例化的 Godot 节点。
func reset_for_testing() -> void:
	objects.clear()
	_pending_object_states.clear()


# 查看某个 affordance 动词是否可用
func can_interact(obj_id: String, verb: String) -> bool:
	var obj = get_object(obj_id)
	if not obj: return false
	return verb in obj.affordances

# 获取可见物体列表（Function Calling 风格）
func list_objects(filter_type: String = "") -> Array:
	var result=  []
	for obj_id in objects:
		var obj = objects[obj_id]
		if not _is_object_in_active_location(obj):
			continue
		result.append(obj.to_dict())
	return result

# 获取交互效果
func get_interaction_effects(obj_id: String, verb: String) -> Dictionary:
	var obj = get_object(obj_id)
	if not obj: return {}
	return obj.effects

# === 自然语言描述生成（给 LLM 的"视野"）===
# 设计文档 §四.2 — 语义快照

func generate_semantic_snapshot(agent_id: String = "main_agent") -> String:
	var sim = WorldSimulator.get_state_snapshot()
	var lines=  []

	lines.append("[当前场景]")
	lines.append("%s，%s。" % [sim["time_of_day"], scene_info["description"]])

	# Agent 自身状态
	var needs = sim["needs"]
	lines.append("你的状态：饥饿感(%d/100) 精力(%d/100)" % [needs["hunger"] as float, needs["energy"] as float])

	# 场景中的物体
	var obj_descs=  []
	for obj_id in objects:
		var obj = objects[obj_id]
		if not _is_object_in_active_location(obj):
			continue
		obj_descs.append(obj.to_nl())
	lines.append("可见物体：" + "、".join(obj_descs))

	return "\n".join(lines)


# === 工具函数 ===

func _dict_to_vec3(dict_or_array) -> Vector3:
	if dict_or_array is Array and dict_or_array.size() >= 3:
		return Vector3(dict_or_array[0] as float, dict_or_array[1] as float, dict_or_array[2] as float)
	if dict_or_array is Dictionary:
		return Vector3(dict_or_array.get("x", 0.0) as float, dict_or_array.get("y", 0.0) as float, dict_or_array.get("z", 0.0) as float)
	return Vector3.ZERO


## [S2.2] 未标记的旧对象只属于兼容客厅；生成对象按 location_id 隔离。
func _is_object_in_active_location(obj: ObjectData) -> bool:
	var location_id := String(obj.properties.get("location_id", "living_room"))
	return location_id == active_location_id


## [X1.2] 将保存的状态和属性应用到已注册物体，只覆盖可持久化字段；
## 不覆盖空间坐标、affordance 和模型元数据。
func _apply_pending_state(obj: ObjectData, saved: Dictionary) -> void:
	if saved.has("state"):
		obj.state = saved.state
	if saved.has("properties"):
		obj.properties.merge(saved.properties, true)


## [X1.2] 严格提取可持久化字段；畸形条目返回空且不影响已有 pending。
func _normalize_saved_object_state(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var normalized := {}
	if value.has("state"):
		if not value.state is String:
			return {}
		normalized["state"] = value.state
	if value.has("properties"):
		if not value.properties is Dictionary:
			return {}
		normalized["properties"] = value.properties.duplicate(true)
	return normalized


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if not file: return null
	var content = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(content) == OK:
		return json.get_data()
	return null
