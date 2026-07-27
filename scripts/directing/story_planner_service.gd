# Roadmap: D3, X3
# Responsibility: 请求 LLM 将自然语言剧本编译为 Story JSON，校验后交给导演。
# Collaborators: MessageBus, StoryPlanningPromptBuilder, StorySchemaValidator, StoryDirector
# Tests: scripts/debug/experience_modes_check.gd

extends Node

const PromptBuilderScript = preload("res://scripts/directing/story_planning_prompt_builder.gd")
const ValidatorScript = preload("res://scripts/directing/story_schema_validator.gd")
const MAX_REPAIR_ATTEMPTS := 1
const MAX_TRANSPORT_RETRIES := 1
const REQUEST_TIMEOUT_SECONDS := 60.0

var is_planning := false
var _http: HTTPRequest
var _source_script := ""
var _last_prompt := ""
var _repair_attempts := 0
var _transport_retries := 0
var _pending_prompt := ""
var _last_error := ""


## [D3][X3] 初始化独立 HTTP 客户端并监听自然语言剧本请求。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	MessageBus.performance_script_requested.connect(plan_script)


## [D3] 提交自然语言剧本；只在演出模式且 LLM 已配置时开始规划。
func plan_script(script_text: String) -> bool:
	var clean := script_text.strip_edges()
	if clean.is_empty():
		return _fail("剧本内容不能为空")
	if not ExperienceModeManager.is_performance_mode():
		return _fail("请先进入演出模式")
	if is_planning:
		return _fail("上一份剧本仍在规划中")
	if not _is_llm_configured():
		return _fail("演出编排需要配置 llm_config.json 中的语言模型")
	is_planning = true
	_source_script = clean
	_repair_attempts = 0
	_transport_retries = 0
	_last_error = ""
	_last_prompt = PromptBuilderScript.new().build(clean)
	MessageBus.story_plan_started.emit(clean)
	MessageBus.ui_status_changed.emit("导演 AI 正在编排角色、动作和对白…", "planning")
	return _send_request(_last_prompt)


## [D3][T4.5] 取消当前规划请求；返回自由模式时不得让旧结果启动演出。
func cancel_request(reason: String) -> void:
	if not is_planning:
		return
	is_planning = false
	_last_error = reason
	if _http:
		_http.cancel_request()


## [D3] 返回最近一次规划错误，供 UI 和验收诊断。
func get_last_error() -> String:
	return _last_error


## [D3][X3] 返回不包含密钥或完整玩家文本的规划诊断摘要。
func get_diagnostics() -> Dictionary:
	return {
		"is_planning": is_planning,
		"repair_attempts": _repair_attempts,
		"transport_retries": _transport_retries,
		"last_error": _last_error,
		"source_chars": _source_script.length(),
	}


## [D3][T4.5] 接受可注入的 LLM 文本输出，供离线验收与未来本地模型复用。
## allow_repair 仅供真实网络响应使用；测试或本地模型失败时直接返回错误。
func accept_planner_output(content: String, allow_repair: bool = false) -> bool:
	var document := _parse_json_object(content)
	if document.is_empty():
		if allow_repair:
			return _request_repair("输出不是 JSON 对象")
		return _fail("编剧输出不是合法 JSON 对象")
	return _validate_and_play(document, allow_repair)


## [D3][X3] 发送 OpenAI/Anthropic 兼容的结构化编剧请求。
func _send_request(prompt: String, reset_transport_retry: bool = true) -> bool:
	_pending_prompt = prompt
	if reset_transport_retry:
		_transport_retries = 0
	var body: Dictionary
	var headers: PackedStringArray
	if CognitiveCycle.llm_provider == "anthropic":
		body = {
			"model": CognitiveCycle.llm_model,
			"max_tokens": 1800,
			"messages": [{"role": "user", "content": prompt}],
		}
		headers = PackedStringArray([
			"Content-Type: application/json",
			"x-api-key: " + CognitiveCycle.llm_api_key,
			"anthropic-version: 2023-06-01",
		])
	else:
		body = {
			"model": CognitiveCycle.llm_model,
			"messages": [
				{"role": "system", "content": "你是游戏演出编剧，只输出严格 JSON。"},
				{"role": "user", "content": prompt},
			],
			"max_tokens": 1800,
			"temperature": 0.45,
		}
		headers = PackedStringArray([
			"Content-Type: application/json",
			"Authorization: Bearer " + CognitiveCycle.llm_api_key,
		])
	var error := _http.request(
		CognitiveCycle.llm_api_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)
	)
	if error != OK:
		return _fail("无法发送编剧请求，错误码 %d" % error)
	return true


## [D3][X3] 解析供应商响应，拒绝过期请求，并进入校验/修复流程。
func _on_request_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if not is_planning or not ExperienceModeManager.is_performance_mode():
		return
	if response_code != 200:
		if (
			(response_code == 0 or response_code >= 500)
			and _transport_retries < MAX_TRANSPORT_RETRIES
		):
			_transport_retries += 1
			MessageBus.ui_status_changed.emit("编剧连接中断，正在重试一次…", "retrying")
			_send_request(_pending_prompt, false)
			return
		_fail("编剧模型请求失败，HTTP %d" % response_code)
		return
	var envelope = JSON.parse_string(body.get_string_from_utf8())
	if not envelope is Dictionary:
		_fail("编剧模型响应格式无效")
		return
	var content := _extract_provider_content(envelope)
	accept_planner_output(content, true)


## [D3] 以注册角色白名单校验 LLM 文档，成功后启动确定性导演。
func _validate_and_play(document: Dictionary, allow_repair: bool) -> bool:
	if document.has("story") and document["story"] is Dictionary:
		document = document["story"]
	document = _sanitize_optional_fields(document)
	var validator = ValidatorScript.new(CharacterAdapterRegistry.get_registered_agent_ids())
	if not validator.validate(document):
		var errors: Array = validator.get_errors()
		var reason := "剧本校验失败"
		if not errors.is_empty():
			reason = "%s: %s" % [errors[0].get("path", ""), errors[0].get("message", "")]
		if allow_repair:
			return _request_repair(reason)
		return _fail(reason)
	var normalized: Dictionary = validator.normalize(document)
	var result := StoryDirector.play_story_document(normalized)
	if result != 0:
		return _fail("导演拒绝剧本: %s" % StoryDirector.get_diagnostics().last_error)
	is_planning = false
	_last_error = ""
	MessageBus.story_plan_ready.emit(normalized)
	MessageBus.ui_status_changed.emit("AI 编排完成，开始演出《%s》" % normalized.title, "playing")
	return true


## [D3] 删除 LLM 常见的空可选字段；不修正角色、能力、地点或交互语义。
## 这一步只把 `say: ""` 等价转换为“该 Beat 没有此字段”。
func _sanitize_optional_fields(document: Dictionary) -> Dictionary:
	var sanitized := document.duplicate(true)
	var beats = sanitized.get("beats", [])
	if not beats is Array:
		return sanitized
	for index in range(beats.size()):
		if not beats[index] is Dictionary:
			continue
		var beat: Dictionary = beats[index]
		for field in ["say", "gesture", "expression", "look_at_actor", "look_at_object"]:
			if beat.has(field) and beat[field] is String and String(beat[field]).strip_edges().is_empty():
				beat.erase(field)
		beats[index] = beat
	sanitized["beats"] = beats
	return sanitized


## [D3] 将校验错误连同原始契约反馈给 LLM，最多自动修复一次。
func _request_repair(reason: String) -> bool:
	if _repair_attempts >= MAX_REPAIR_ATTEMPTS:
		return _fail("自动修复失败: %s" % reason)
	_repair_attempts += 1
	var repair_prompt := """
上一份 Story JSON 未通过运行时校验：
%s

请重新输出完整 JSON。不得解释、不得使用 Markdown，并严格遵守原始能力清单。

原始编排要求：
%s
""" % [reason, _last_prompt]
	MessageBus.ui_status_changed.emit("编排结果不安全，导演 AI 正在自动修复…", "repairing")
	return _send_request(repair_prompt)


## [D3][X3] 从 OpenAI 或 Anthropic 兼容响应中提取文本。
func _extract_provider_content(response: Dictionary) -> String:
	if response.get("choices") is Array and not response["choices"].is_empty():
		return String(response["choices"][0].get("message", {}).get("content", ""))
	if response.get("content") is Array:
		for block in response["content"]:
			if block is Dictionary and block.get("type") == "text":
				return String(block.get("text", ""))
	return ""


## [D3] 从纯 JSON 或 Markdown 包裹文本中提取第一个完整 JSON 对象。
func _parse_json_object(content: String) -> Dictionary:
	var cleaned := content.replace("```json", "").replace("```", "").strip_edges()
	var start := cleaned.find("{")
	var finish := cleaned.rfind("}")
	if start >= 0 and finish > start:
		cleaned = cleaned.substr(start, finish - start + 1)
	var parsed = JSON.parse_string(cleaned)
	return parsed if parsed is Dictionary else {}


## [D3][X3] 查询现有 CognitiveCycle 的共享模型配置，不复制密钥文件。
func _is_llm_configured() -> bool:
	return not CognitiveCycle.llm_api_url.is_empty() and not CognitiveCycle.llm_api_key.is_empty()


## [D3] 统一结束失败状态并通知 UI/诊断监听者。
func _fail(reason: String) -> bool:
	is_planning = false
	_last_error = reason
	MessageBus.story_plan_failed.emit(reason)
	MessageBus.ui_status_changed.emit("演出编排失败: %s" % reason, "error")
	return false
