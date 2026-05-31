## FootstepPlayer — autoload
## 依 surface_id 播放對應資料夾的隨機腳步聲。lazy-load + cache。
## 各 zone 在 Inspector 改 root node 的 `footstep_step_distance` 欄位
## (zone_baker.gd 的 @export)覆寫節奏；0 = 用 DEFAULT_STEP_DISTANCE。
extends Node

const DEFAULT_STEP_DISTANCE: float = 40.0

## 當前 step 距離；Player 每次走路前透過 get_step_distance() 取值。
func get_step_distance() -> float:
	var scene: Node = get_tree().current_scene
	if scene != null:
		var v: Variant = scene.get("footstep_step_distance")
		# Accept float OR int — Inspector enforces float on the @export, but
		# metadata-driven overrides (e.g. via scene.set_meta) may come as int.
		if (v is float or v is int) and float(v) > 0.0:
			return float(v)
	return DEFAULT_STEP_DISTANCE

var _player: AudioStreamPlayer
## surface_id -> AudioStreamRandomizer (or null if no clips found)
var _streams_by_surface: Dictionary = {}

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "SFX"
	add_child(_player)

func play(surface_id: String) -> void:
	if surface_id == "":
		return
	var stream: AudioStreamRandomizer = _get_stream(surface_id)
	if stream == null:
		return
	_player.stream = stream
	_player.play()

func _get_stream(surface_id: String) -> AudioStreamRandomizer:
	if _streams_by_surface.has(surface_id):
		return _streams_by_surface[surface_id]

	var dir_path: String = "res://assets/audio/footsteps/" + surface_id + "/"
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		_streams_by_surface[surface_id] = null
		return null

	var randomizer: AudioStreamRandomizer = AudioStreamRandomizer.new()
	var added: int = 0
	for fname in dir.get_files():
		if not (fname.ends_with(".ogg") or fname.ends_with(".wav") or fname.ends_with(".mp3")):
			continue
		var s: AudioStream = load(dir_path + fname)
		if s == null:
			continue
		randomizer.add_stream(-1, s)
		added += 1

	if added == 0:
		_streams_by_surface[surface_id] = null
		return null

	_streams_by_surface[surface_id] = randomizer
	return randomizer
