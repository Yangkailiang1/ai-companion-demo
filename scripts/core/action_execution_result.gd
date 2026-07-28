# Roadmap: C4.5, T1.2
# Responsibility: 构造和规范化动作执行结果；不执行动作或修改世界状态。
# Collaborators: ActionExecutor, ActionObjectInteractor
# Tests: scripts/debug/action_failure_contract_check.gd

class_name ActionExecutionResult
extends RefCounted


## [C4.5][T1.2] 构造稳定成功结果。
static func success(context: Dictionary = {}) -> Dictionary:
	return {"success": true, "reason": "", "context": context.duplicate(true)}


## [C4.5][T1.2] 构造稳定失败结果；空原因归一化为 action_failed。
static func failure(reason: String, context: Dictionary = {}) -> Dictionary:
	var stable_reason := reason.strip_edges()
	if stable_reason.is_empty():
		stable_reason = "action_failed"
	return {"success": false, "reason": stable_reason, "context": context.duplicate(true)}


## [C4.5] 将物体组件的 handled/success 返回值规范化为动作结果。
static func from_interaction(raw: Dictionary, context: Dictionary = {}) -> Dictionary:
	var merged := context.duplicate(true)
	merged["interaction_result"] = raw.duplicate(true)
	if not bool(raw.get("handled", false)):
		return failure("unsupported_interaction", merged)
	if raw.has("success") and not bool(raw.get("success", false)):
		return failure(String(raw.get("reason", "interaction_failed")), merged)
	return success(merged)


## [C4.5] 查询规范化结果是否成功；纯读取。
static func is_success(result: Dictionary) -> bool:
	return bool(result.get("success", false))
