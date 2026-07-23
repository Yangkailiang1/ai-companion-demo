extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tts = root.get_node_or_null("TTSService")
	_assert(tts != null, "TTSService autoload must exist")
	var summary: Dictionary = tts.get_config_summary()
	_assert(summary.has("enabled"), "TTS summary must expose enabled")
	_assert(summary.get("model", "") == "ecnu-tts", "TTS model default/config must be ecnu-tts")
	_assert(summary.get("format", "") == "mp3", "Runtime TTS playback should use mp3")
	var chunks: PackedStringArray = tts._split_text("第一句话。第二句话！第三句话？", 8)
	_assert(chunks.size() >= 3, "TTS text splitter should chunk by sentence punctuation")
	print("TTS_SERVICE_CHECK_PASS enabled=%s configured=%s voice=%s" % [
		summary.get("enabled", false),
		summary.get("configured", false),
		summary.get("voice", ""),
	])
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("TTS_SERVICE_CHECK_FAIL: %s" % message)
	quit(1)
	assert(condition, message)
