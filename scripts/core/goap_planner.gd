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
	var available_ids = SemanticWorld.objects.keys()
	for goal in goal_blueprints:
		for action in goal_blueprints[goal]:
			var target = action.params.get("target", action.params.get("object", ""))
			if target != "" and target not in available_ids:
				push_warning("GOAP: goal '%s' references unknown object '%s'" % [goal, target])


# === 核心：将 Goal 展开为 Primitive Action 链 ===

func plan(goal: String) -> Array:
	# 1. 精确匹配
	if goal_blueprints.has(goal):
		return goal_blueprints[goal].duplicate()

	# 2. 模糊匹配（goal 中的关键词命中）
	for blueprint_goal in goal_blueprints:
		if blueprint_goal.contains(goal) or goal.contains(blueprint_goal):
			return goal_blueprints[blueprint_goal].duplicate()

	# 3. 没有匹配的 blueprint → 返回一个通用 navigate+idle
	push_warning("GOAP: no blueprint for goal '%s', using default" % goal)
	return [_pa(AffordanceTypes.Primitive.IDLE, {"duration": 1.0})]


# === 动态生成 Goal Blueprint（当 LLM 提出新 Goal，而映射表里没有时） ===

func register_blueprint(goal: String, object_id: String, verb: String) -> void:
	var actions=  []
	actions.append(_pa(AffordanceTypes.Primitive.NAVIGATE, {"target": object_id}))
	actions.append(_pa(AffordanceTypes.Primitive.INTERACT, {"object": object_id, "verb": verb}))
	goal_blueprints[goal] = actions


# 使用 affordance 表自动生成 blueprint
func auto_plan(goal: String, object_id: String) -> Array:
	var obj = SemanticWorld.get_object(object_id)
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
