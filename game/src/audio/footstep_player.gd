## FootstepPlayer — autoload
## 依 surface_id 播放對應資料夾的隨機腳步聲。lazy-load + cache。
## 各 zone 可在 root node 設 metadata "footstep_step_distance" 覆寫節奏。
extends Node

const DEFAULT_STEP_DISTANCE: float = 40.0

## 當前 step 距離；Player 每次走路前透過 get_step_distance() 取值。
## Zone 切換時優先讀 current_scene.get_meta("footstep_step_distance")。
func get_step_distance() -> float:
	var scene: Node = get_tree().current_scene
	if scene != null and scene.has_meta("footstep_step_distance"):
		return float(scene.get_meta("footstep_step_distance"))
	return DEFAULT_STEP_DISTANCE

var _player: AudioStreamPlayer
## surface_id -> AudioStreamRandomizer (or null if no clips found)
var _streams_by_surface: Dictionary = {}

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)

func play(surface_id: String) -> void:
	if surface_id == "":
		print("[FootstepPlayer] play skipped (empty surface_id)")
		return
	var stream: AudioStreamRandomizer = _get_stream(surface_id)
	if stream == null:
		print("[FootstepPlayer] no stream for '%s'" % surface_id)
		return
	_player.stream = stream
	_player.play()
	print("[FootstepPlayer] playing '%s'" % surface_id)

func _get_stream(surface_id: String) -> AudioStreamRandomizer:
	if _streams_by_surface.has(surface_id):
		return _streams_by_surface[surface_id]

	var dir_path: String = "res://assets/audio/footsteps/" + surface_id + "/"
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		print("[FootstepPlayer] dir not found: %s" % dir_path)
		_streams_by_surface[surface_id] = null
		return null

	var randomizer: AudioStreamRandomizer = AudioStreamRandomizer.new()
	var added: int = 0
	for fname in dir.get_files():
		if not (fname.ends_with(".ogg") or fname.ends_with(".wav") or fname.ends_with(".mp3")):
			continue
		var s: AudioStream = load(dir_path + fname)
		if s == null:
			print("[FootstepPlayer] failed load %s%s" % [dir_path, fname])
			continue
		randomizer.add_stream(-1, s)
		added += 1

	if added == 0:
		print("[FootstepPlayer] no clips in %s" % dir_path)
		_streams_by_surface[surface_id] = null
		return null

	print("[FootstepPlayer] loaded %d clips for '%s'" % [added, surface_id])
	_streams_by_surface[surface_id] = randomizer
	return randomizer
