# goap_planner.gd — Goal → Task Tree → Primitive Actions
# 设计文档 §五.2: LLM 输出 Goal，GOAP 分解为 Primitive Chain
class_name GOAPPlanner

extends Node

# Goal 到 Primitive Chain 的映射表
# 格式: "goal_name": [PrimitiveAction, PrimitiveAction, ...]
var goal_blueprints: Dictionary = {}


func _ready():
	_build_blueprints()


func _build_blueprints():
	# 所有 Goal 的 Primitive Action 分解
	# 动词来自 affordance 表，PA = PrimitiveAction

	goal_blueprints = {
		"drink_milk_tea": [
			_pa(AffordanceTypes.Primitive.NAVIGATE, {"target": "milk_tea"}),
			_pa(AffordanceTypes.Primitive.PICK_UP, {"object": "milk_tea"}),
			_pa(AffordanceTypes.Primitive.INTERACT, {"object": "milk_tea", "verb": "drink"}),
			_pa(AffordanceTypes.Primitive.PUT_DOWN, {"object": "milk_tea"}),
		],
		"watch_tv": [
			_pa(AffordanceTypes.Primitive.NAVIGATE, {"target": "tv"}),
			_pa(AffordanceTypes.Primitive.INTERACT, {"object": "tv", "verb": "turn_on"}),
			_pa(AffordanceTypes.Primitive.IDLE, {"duration": 5.0}),
			_pa(AffordanceTypes.Primitive.INTERACT, {"object": "tv", "verb": "turn_off"}),
		],
		"read_book": [
			_pa(AffordanceTypes.Primitive.NAVIGATE, {"target": "book"}),
			_pa(AffordanceTypes.Primitive.PICK_UP, {"object": "book"}),
			_pa(AffordanceTypes.Primitive.INTERACT, {"object": "book", "verb": "read"}),
			_pa(AffordanceTypes.Primitive.PUT_DOWN, {"object": "book"}),
		],
		"water_plant": [
			_pa(AffordanceTypes.Primitive.NAVIGATE, {"target": "plant"}),
			_pa(AffordanceTypes.Primitive.INTERACT, {"object": "plant", "verb": "water"}),
		],
		"rest_on_sofa": [
			_pa(AffordanceTypes.Primitive.NAVIGATE, {"target": "sofa"}),
			_pa(AffordanceTypes.Primitive.SIT, {"object": "sofa"}),
			_pa(AffordanceTypes.Primitive.IDLE, {"duration": 8.0}),
		],
		"look_out_window": [
			_pa(AffordanceTypes.Primitive.IDLE, {"duration": 3.0}),
		],
		"stretch": [
			_pa(AffordanceTypes.Primitive.IDLE, {"duration": 2.0}),
		],
		"wave_at_player": [
			_pa(AffordanceTypes.Primitive.IDLE, {"duration": 1.5}),
		],
		"patrol_room": [
			_pa(AffordanceTypes.Primitive.PATROL, {"route": "room_perimeter", "laps": 1}),
		],
		"wander_room": [
			_pa(AffordanceTypes.Primitive.WANDER, {}),
		],
	}

	# 验证：所有 Goal 引用的 object 都在 SemanticWorld 中存在
	_validate_blueprints()


func _pa(type: AffordanceTypes.Primitive, params: Dictionary = {}) -> AffordanceTypes.PrimitiveAction:
	return AffordanceTypes.PrimitiveAction.new(type, params)


func _validate_blueprints():
	var semantic_world := _semantic_world()
	if semantic_world == null:
		return
	for goal in goal_blueprints:
		for action in goal_blueprints[goal]:
			var target = action.params.get("target", action.params.get("object", ""))
			if (
				target != ""
				and not semantic_world.objects.has(String(target))
				and semantic_world.resolve_object_reference(String(target)).is_empty()
			):
				push_warning("GOAP: goal '%s' references unknown object '%s'" % [goal, target])


# === 核心：将 Goal 展开为 Primitive Action 链 ===

func plan(goal: String) -> Array:
	var semantic_world := _semantic_world()
	var watering_can_id: String = (
		semantic_world.resolve_object_reference("watering_can")
		if semantic_world != null else ""
	)
	if (
		goal == "water_plant"
		and not watering_can_id.is_empty()
		and is_instance_valid(semantic_world.get_object(watering_can_id).godot_node)
	):
		return _plan_embodied_watering(watering_can_id)
	# 1. 精确匹配
	if goal_blueprints.has(goal):
		return _resolve_actions(goal_blueprints[goal])

	# 2. 模糊匹配（goal 中的关键词命中）
	for blueprint_goal in goal_blueprints:
		if blueprint_goal.contains(goal) or goal.contains(blueprint_goal):
			return _resolve_actions(goal_blueprints[blueprint_goal])

	# 3. 没有匹配的 blueprint → 返回一个通用 navigate+idle
	push_warning("GOAP: no blueprint for goal '%s', using default" % goal)
	return [_pa(AffordanceTypes.Primitive.IDLE, {"duration": 1.0})]


## [C4.4][C9.5b] Builds the visible watering chain when the current room owns
## a portable watering can; legacy rooms keep the direct-interaction fallback.
func _plan_embodied_watering(watering_can_id: String) -> Array:
	var plant_id: String = _semantic_world().resolve_object_reference("plant")
	return [
		_pa(AffordanceTypes.Primitive.NAVIGATE, {"target": watering_can_id}),
		_pa(AffordanceTypes.Primitive.PICK_UP, {"object": watering_can_id}),
		_pa(AffordanceTypes.Primitive.NAVIGATE, {"target": plant_id}),
		_pa(AffordanceTypes.Primitive.INTERACT, {
			"object": plant_id, "verb": "water", "held_tool": watering_can_id,
		}),
		_pa(AffordanceTypes.Primitive.PUT_DOWN, {"object": watering_can_id}),
	]


## [C9.1][T2.2] 复制蓝图，并把传统功能 ID 替换为当前房间的能力等价对象。
func _resolve_actions(blueprint: Array) -> Array:
	var semantic_world := _semantic_world()
	var resolved: Array = []
	for action in blueprint:
		var params: Dictionary = action.params.duplicate(true)
		for field in ["target", "object", "held_tool"]:
			var reference_id := String(params.get(field, ""))
			if reference_id.is_empty():
				continue
			var object_id: String = semantic_world.resolve_object_reference(reference_id)
			if not object_id.is_empty():
				params[field] = object_id
		resolved.append(_pa(action.type, params))
	return resolved


# === 动态生成 Goal Blueprint（当 LLM 提出新 Goal，而映射表里没有时） ===

func register_blueprint(goal: String, object_id: String, verb: String) -> void:
	var actions=  []
	actions.append(_pa(AffordanceTypes.Primitive.NAVIGATE, {"target": object_id}))
	actions.append(_pa(AffordanceTypes.Primitive.INTERACT, {"object": object_id, "verb": verb}))
	goal_blueprints[goal] = actions


# 使用 affordance 表自动生成 blueprint
func auto_plan(goal: String, object_id: String) -> Array:
	var semantic_world := _semantic_world()
	var obj = semantic_world.get_object(object_id) if semantic_world != null else null
	if not obj:
		return [_pa(AffordanceTypes.Primitive.IDLE, {"duration": 1.0})]

	var actions=  []

	# 需要接近的物体 → navigate
	if obj.needs_proximity:
		actions.append(_pa(AffordanceTypes.Primitive.NAVIGATE, {"target": object_id}))

	# 选择第一个可用的 affordance 动词
	if obj.affordances.size() > 0:
		var verb = obj.affordances[0]
		# 对于坐/喝/读 需要特殊处理
		match verb:
			"sit", "lie_down":
				actions.append(_pa(AffordanceTypes.Primitive.SIT, {"object": object_id}))
			"drink", "read":
				actions.append(_pa(AffordanceTypes.Primitive.PICK_UP, {"object": object_id}))
				actions.append(_pa(AffordanceTypes.Primitive.INTERACT, {"object": object_id, "verb": verb}))
				actions.append(_pa(AffordanceTypes.Primitive.PUT_DOWN, {"object": object_id}))
			_:
				actions.append(_pa(AffordanceTypes.Primitive.INTERACT, {"object": object_id, "verb": verb}))

	# 注册到 blueprint 供后续使用
	goal_blueprints[goal] = actions
	return actions


## [T2][T4.2] Resolves the semantic service without a compile-time singleton
## dependency, allowing standalone contract scripts to load the planner.
func _semantic_world() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("SemanticWorld") if tree != null else null
