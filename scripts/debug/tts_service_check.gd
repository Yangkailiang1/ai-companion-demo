# Verifies: C7.1, C7.2, D2.3
# Covers: ECNU-compatible runtime defaults, sentence chunks and speech timing.

extends SceneTree


## [C7.1][C7.2] Starts the TTS contract after Autoload initialization.
func _init() -> void:
	call_deferred("_run")


## [C7.2][D2.3] Validates configuration, chunking and speed-aware duration.
func _run() -> void:
	var tts = root.get_node_or_null("TTSService")
	_assert(tts != null, "TTSService autoload must exist")
	var summary: Dictionary = tts.get_config_summary()
	_assert(summary.has("enabled"), "TTS summary must expose enabled")
	_assert(summary.get("model", "") == "ecnu-tts", "TTS model default/config must be ecnu-tts")
	_assert(summary.get("format", "") == "mp3", "Runtime TTS playback should use mp3")
	var chunks: PackedStringArray = tts._split_text("第一句话。第二句话！第三句话？", 8)
	_assert(chunks.size() >= 3, "TTS text splitter should chunk by sentence punctuation")
	var normal_duration: float = tts.estimate_speech_duration("我们一起去看电视吧", 1.0)
	var fast_duration: float = tts.estimate_speech_duration("我们一起去看电视吧", 2.0)
	_assert(normal_duration > fast_duration, "TTS timing estimate ignored speed")
	_assert(normal_duration >= 0.8, "TTS timing estimate below presentation floor")
	print("TTS_SERVICE_CHECK_PASS enabled=%s configured=%s voice=%s" % [
		summary.get("enabled", false),
		summary.get("configured", false),
		summary.get("voice", ""),
	])
	quit(0)


## [T4.2] Stops on the first deterministic TTS contract failure.
func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("TTS_SERVICE_CHECK_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
