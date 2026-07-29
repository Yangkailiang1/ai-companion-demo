# Roadmap: C7.1, C7.2, D2.3
# Responsibility: Request and asynchronously play ECNU-compatible speech, expose
# conservative timing estimates; does not choose dialogue or direct camera shots.
# Collaborators: MessageBus, StoryWorldBridge, AudioStreamPlayer
# Tests: scripts/debug/tts_service_check.gd

extends Node

const DEFAULT_TTS_URL := "https://chat.ecnu.edu.cn/open/api/v1/audio/speech"
const DEFAULT_MODEL := "ecnu-tts"
const DEFAULT_VOICE := "liwa"
const DEFAULT_FORMAT := "mp3"
const MAX_CHARS_PER_CHUNK := 120

var enabled: bool = false
var api_url: String = DEFAULT_TTS_URL
var api_key: String = ""
var model: String = DEFAULT_MODEL
var voice: String = DEFAULT_VOICE
var response_format: String = DEFAULT_FORMAT
var speed: float = 1.0
var interrupt_current: bool = true

var _http_request: HTTPRequest
var _player: AudioStreamPlayer
var _queue: Array[Dictionary] = []
var _request_in_flight: bool = false
var _playing: bool = false
var _last_error: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()

	_http_request = HTTPRequest.new()
	_http_request.timeout = 30.0
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_player.finished.connect(_on_playback_finished)

	if MessageBus.has_signal("tts_speech_requested"):
		MessageBus.tts_speech_requested.connect(_on_tts_speech_requested)


func speak(text: String, options: Dictionary = {}) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return
	if not enabled or api_key.is_empty():
		return

	var chosen_voice := String(options.get("voice", voice))
	var chosen_speed := clampf(float(options.get("speed", speed)), 0.25, 4.0)
	var chunks := _split_text(clean_text, int(options.get("max_chars", MAX_CHARS_PER_CHUNK)))
	if chunks.is_empty():
		return

	if bool(options.get("interrupt", interrupt_current)):
		_queue.clear()
		_request_in_flight = false
		if _player.playing:
			_player.stop()
			_playing = false

	for chunk in chunks:
		_queue.append({
			"text": chunk,
			"voice": chosen_voice,
			"speed": chosen_speed,
		})
	_pump_queue()


func stop() -> void:
	_queue.clear()
	_request_in_flight = false
	if _player and _player.playing:
		_player.stop()
	_playing = false


func is_ready() -> bool:
	return enabled and not api_key.is_empty() and not api_url.is_empty()


func get_last_error() -> String:
	return _last_error


func get_config_summary() -> Dictionary:
	return {
		"enabled": enabled,
		"configured": not api_key.is_empty(),
		"url": api_url,
		"model": model,
		"voice": voice,
		"format": response_format,
		"speed": speed,
	}


## [C7.2][D2.3] Estimates a safe camera/dialogue hold from text and voice speed.
## ECNU returns complete MP3 files without word timestamps, so this is advisory.
func estimate_speech_duration(text: String, requested_speed: float = -1.0) -> float:
	var active_speed := speed if requested_speed <= 0.0 else requested_speed
	active_speed = clampf(active_speed, 0.25, 4.0)
	var spoken_units := 0
	for index in range(text.length()):
		var character := text.substr(index, 1)
		if not character.strip_edges().is_empty():
			spoken_units += 1
	return clampf(0.35 + float(spoken_units) / (4.8 * active_speed), 0.8, 12.0)


func _on_tts_speech_requested(text: String, context: Dictionary) -> void:
	speak(text, context)


func _pump_queue() -> void:
	if _request_in_flight or _playing or _queue.is_empty():
		return
	var item: Dictionary = _queue.pop_front()
	_request_chunk(item)


func _request_chunk(item: Dictionary) -> void:
	var body := {
		"model": model,
		"input": String(item.get("text", "")),
		"voice": String(item.get("voice", voice)),
		"response_format": response_format,
		"speed": float(item.get("speed", speed)),
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	])
	_request_in_flight = true
	var err := _http_request.request(api_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_request_in_flight = false
		_last_error = "TTS request failed to start: %s" % err
		push_warning("TTSService: %s" % _last_error)
		_pump_queue()


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_request_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_last_error = "TTS request failed: result=%s code=%s" % [result, response_code]
		push_warning("TTSService: %s" % _last_error)
		_pump_queue()
		return
	if response_format != "mp3":
		_last_error = "runtime playback currently supports mp3 only, got %s" % response_format
		push_warning("TTSService: %s" % _last_error)
		_pump_queue()
		return

	var stream := AudioStreamMP3.new()
	stream.data = body
	_player.stream = stream
	_playing = true
	_player.play()


func _on_playback_finished() -> void:
	_playing = false
	_pump_queue()


func _load_config() -> void:
	var path := "res://data/llm_config.json"
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var tts_cfg: Dictionary = parsed.get("tts", {})
	if tts_cfg.is_empty():
		enabled = bool(parsed.get("tts_enabled", false))
		api_key = String(parsed.get("tts_api_key", parsed.get("api_key", "")))
		api_url = String(parsed.get("tts_api_url", DEFAULT_TTS_URL))
		model = String(parsed.get("tts_model", DEFAULT_MODEL))
		voice = String(parsed.get("tts_voice", DEFAULT_VOICE))
		response_format = String(parsed.get("tts_response_format", DEFAULT_FORMAT))
		speed = clampf(float(parsed.get("tts_speed", 1.0)), 0.25, 4.0)
	else:
		enabled = bool(tts_cfg.get("enabled", false))
		api_key = String(tts_cfg.get("api_key", parsed.get("api_key", "")))
		api_url = String(tts_cfg.get("api_url", DEFAULT_TTS_URL))
		model = String(tts_cfg.get("model", DEFAULT_MODEL))
		voice = String(tts_cfg.get("voice", DEFAULT_VOICE))
		response_format = String(tts_cfg.get("response_format", DEFAULT_FORMAT))
		speed = clampf(float(tts_cfg.get("speed", 1.0)), 0.25, 4.0)
		interrupt_current = bool(tts_cfg.get("interrupt_current", true))


func _split_text(text: String, max_chars: int) -> PackedStringArray:
	var chunks := PackedStringArray()
	var normalized := text.strip_edges()
	if normalized.length() <= max_chars:
		chunks.append(normalized)
		return chunks

	var current := ""
	for index in range(normalized.length()):
		var ch := normalized.substr(index, 1)
		current += ch
		if ch in ["。", "！", "？", "；", ".", "!", "?", ";"] or current.length() >= max_chars:
			var piece := current.strip_edges()
			if not piece.is_empty():
				chunks.append(piece)
			current = ""
	var tail := current.strip_edges()
	if not tail.is_empty():
		chunks.append(tail)
	return chunks
