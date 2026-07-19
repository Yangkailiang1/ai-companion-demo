# semantic_world.gd — 语义世界模型 (Autoload)
# 设计文档 §四：Object Affordance Graph + 自然语言描述生成
# LLM 不是"看"像素，而是"读"这个模块生成的语义快照

extends Node

# 场景物体字典: {object_id: ObjectData}
var objects: Dictionary = {}

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
	var affordances: Array[String] = []
	var position: Vector3
	var interaction_point: Vector3
	var needs_proximity: bool = true
	var consumable: bool = false
	var effects: Dictionary = {}  # 交互对需求的影响 {need_type: delta}
	var occupied_by: String = ""  # 当前占用者（null/agent_id）
	var godot_node: Node3D = null  # 指向 Godot 场景节点的引用

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"description": description,
			"state": state,
			"affordances": affordances,
		}

	func to_nl() -> String:
		var base = "%s（%s）" % [name, state]
		if description:
			base = "%s：%s" % [name, description]
		return base


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


# 获取物体
func get_object(obj_id: String) -> ObjectData:
	return objects.get(obj_id)


# 更新物体状态
func update_object_state(obj_id: String, new_state: String) -> void:
	if objects.has(obj_id):
		objects[obj_id].state = new_state
		MessageBus.world_state_changed.emit("object_state_changed", {
			"object_id": obj_id,
			"new_state": new_state
		})

# 查看某个 affordance 动词是否可用
func can_interact(obj_id: String, verb: String) -> bool:
	var obj = objects.get(obj_id)
	if not obj: return false
	return verb in obj.affordances

# 获取可见物体列表（Function Calling 风格）
func list_objects(filter_type: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for obj_id in objects:
		var obj = objects[obj_id]
		result.append(obj.to_dict())
	return result

# 获取交互效果
func get_interaction_effects(obj_id: String, verb: String) -> Dictionary:
	var obj = objects.get(obj_id)
	if not obj: return {}
	return obj.effects

# === 自然语言描述生成（给 LLM 的"视野"）===
# 设计文档 §四.2 — 语义快照

func generate_semantic_snapshot(agent_id: String = "main_agent") -> String:
	var sim = WorldSimulator.get_state_snapshot()
	var lines: Array[String] = []

	lines.append("[当前场景]")
	lines.append("%s，%s。" % [sim["time_of_day"], scene_info["description"]])

	# Agent 自身状态
	var needs = sim["needs"]
	lines.append("你的状态：饥饿感(%d/100) 精力(%d/100)" % [needs["hunger"] as float, needs["energy"] as float])

	# 场景中的物体
	var obj_descs: Array[String] = []
	for obj_id in objects:
		var obj = objects[obj_id]
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
