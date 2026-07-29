# Roadmap: C4.4, C9.5b, S3.1
# Responsibility: Present a watering can pouring through local tilt, water
# particles and procedural sound. Never changes plant state or owns physics.
# Collaborators: InteractableObject, ActionExecutor
# Tests: scripts/debug/embodied_watering_check.gd

extends Node3D

signal tool_use_started(verb: String)
signal tool_use_finished(verb: String)

const POUR_TILT_DEGREES := -38.0
const TILT_SECONDS := 0.24
const STREAM_SECONDS := 0.82

var is_pouring := false
var _stream: CPUParticles3D
var _audio: AudioStreamPlayer3D


## [C9.5b] 在模型就绪时创建本地水流与可循环的轻量水声。
func _ready() -> void:
	_stream = _create_stream()
	add_child(_stream)
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "PourAudio"
	_audio.stream = _create_water_audio()
	_audio.volume_db = -17.0
	_audio.max_distance = 5.0
	add_child(_audio)


## [C4.4][C9.5b] 播放白名单工具表现；不支持的动词安全返回 false。
func play_tool_use(verb: String, _target_position := Vector3.ZERO) -> bool:
	if verb != "water" or is_pouring or not is_inside_tree():
		return false
	is_pouring = true
	tool_use_started.emit(verb)
	var base_rotation := rotation
	var pour_rotation := base_rotation + Vector3(
		0.0, 0.0, deg_to_rad(POUR_TILT_DEGREES)
	)
	var tilt := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tilt.tween_property(self, "rotation", pour_rotation, TILT_SECONDS)
	await tilt.finished
	if not is_inside_tree():
		return false
	_stream.emitting = true
	_audio.play()
	await get_tree().create_timer(STREAM_SECONDS).timeout
	if not is_inside_tree():
		return false
	_stream.emitting = false
	_audio.stop()
	var restore := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	restore.tween_property(self, "rotation", base_rotation, TILT_SECONDS)
	await restore.finished
	is_pouring = false
	tool_use_finished.emit(verb)
	return true


## [S3.1] 创建从壶嘴向前下方落下的半透明水滴粒子。
func _create_stream() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "WaterStream"
	particles.position = Vector3(0.58, 0.2, 0.0)
	particles.amount = 44
	particles.lifetime = 0.62
	particles.local_coords = true
	particles.direction = Vector3(0.62, -1.0, 0.0).normalized()
	particles.spread = 7.0
	particles.gravity = Vector3(0.0, -2.4, 0.0)
	particles.initial_velocity_min = 1.15
	particles.initial_velocity_max = 1.55
	particles.scale_amount_min = 0.65
	particles.scale_amount_max = 1.0
	particles.color = Color(0.36, 0.78, 1.0, 0.82)
	var drop := SphereMesh.new()
	drop.radius = 0.018
	drop.height = 0.065
	drop.radial_segments = 8
	drop.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.72, 1.0, 0.78)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = material
	particles.mesh = drop
	particles.emitting = false
	return particles


## [S3.1] 生成确定性的短循环柔和水声，避免绑定外部音频资产。
func _create_water_audio() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var sample_count := 11025
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in range(sample_count):
		var phase := float(index) / float(stream.mix_rate)
		var noise := fposmod(
			sin(float(index) * 12.9898) * 43758.5453, 1.0
		) * 2.0 - 1.0
		var ripple := sin(phase * TAU * 420.0) * 0.16
		var sample := int(clampf(
			(noise * 0.22 + ripple) * 32767.0, -32767.0, 32767.0
		))
		bytes.encode_s16(index * 2, sample)
	stream.data = bytes
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream
