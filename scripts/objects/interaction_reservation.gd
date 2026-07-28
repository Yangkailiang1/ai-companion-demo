# Roadmap: C4.5, S3.3
# Responsibility: 管理单个物体的占用/预订生命周期；不拥有物理状态，不处理动画或导航。
# Collaborators: InteractableObject
# Tests: scripts/debug/interaction_contract_check.gd

class_name InteractionReservation
extends RefCounted

var _reserved_by: String = ""
var _reserved_until_msec: int = 0
var _committed: bool = false

const ERROR_OCCUPIED := "occupied"
const ERROR_NOT_RESERVED := "not_reserved"
const ERROR_INVALID_ACTOR := "invalid_actor"
const ERROR_INVALID_TIMEOUT := "invalid_timeout"


## [C4.5] 检查当前预订是否已超时。
func _is_expired() -> bool:
	if _reserved_by.is_empty():
		return false
	if _committed:
		return false
	return Time.get_ticks_msec() > _reserved_until_msec


## [C4.5] 预订此物体供指定角色使用。重复预订同一角色仅刷新超时。
## 返回 {success: bool, reason: String}。
func reserve(actor_id: String, timeout_seconds: float) -> Dictionary:
	if actor_id.strip_edges().is_empty():
		return {"success": false, "reason": ERROR_INVALID_ACTOR}
	if timeout_seconds <= 0.0 or not is_finite(timeout_seconds):
		return {"success": false, "reason": ERROR_INVALID_TIMEOUT}
	_cleanup_if_expired()
	if not _reserved_by.is_empty() and _reserved_by != actor_id:
		return {"success": false, "reason": ERROR_OCCUPIED}
	_reserved_by = actor_id
	_reserved_until_msec = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	_committed = false
	return {"success": true}


## [C4.5] 确认预订，将占用固定。只能由当前预订者调用。
func commit(actor_id: String) -> Dictionary:
	if actor_id.strip_edges().is_empty():
		return {"success": false, "reason": ERROR_INVALID_ACTOR}
	_cleanup_if_expired()
	if _reserved_by != actor_id:
		return {"success": false, "reason": ERROR_NOT_RESERVED}
	_committed = true
	return {"success": true}


## [C4.5] 释放占用/预订，幂等。
## 未被预订时返回 success=true；被其他角色占用时返回 not_reserved。
func release(actor_id: String) -> Dictionary:
	if actor_id.strip_edges().is_empty():
		return {"success": false, "reason": ERROR_INVALID_ACTOR}
	if _reserved_by.is_empty():
		return {"success": true}
	if _reserved_by != actor_id:
		return {"success": false, "reason": ERROR_NOT_RESERVED}
	_reserved_by = ""
	_reserved_until_msec = 0
	_committed = false
	return {"success": true}


## [C4.5] 返回当前预订者 ID；未被预订时返回空字符串。
func get_reserved_by() -> String:
	_cleanup_if_expired()
	return _reserved_by


## [C4.5] 返回是否已确认占用。
func is_committed() -> bool:
	_cleanup_if_expired()
	return _committed and not _reserved_by.is_empty()


## [C4.5] 如果未确认的预订已超时，静默清除。
func _cleanup_if_expired() -> void:
	if _is_expired():
		_reserved_by = ""
		_reserved_until_msec = 0
		_committed = false
