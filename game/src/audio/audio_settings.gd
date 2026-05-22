## AudioSettings — autoload
## 管理 Master bus 音量 + 一鍵靜音。狀態存 user://audio_settings.json
## 讓下次開遊戲記住。
extends Node

signal volume_changed(linear: float)
signal mute_changed(muted: bool)

const SAVE_PATH: String = "user://audio_settings.json"

var _volume_linear: float = 1.0   # 0.0–1.0
var _muted: bool = false

func _ready() -> void:
	_load()
	_apply_to_bus()

# ── Public API ────────────────────────────────────────────────────────────────

func get_volume() -> float:
	return _volume_linear

func set_volume(linear: float) -> void:
	_volume_linear = clamp(linear, 0.0, 1.0)
	_apply_to_bus()
	_save()
	volume_changed.emit(_volume_linear)

func is_muted() -> bool:
	return _muted

func set_muted(muted: bool) -> void:
	_muted = muted
	_apply_to_bus()
	_save()
	mute_changed.emit(_muted)

func toggle_mute() -> void:
	set_muted(not _muted)

# ── Internals ────────────────────────────────────────────────────────────────

func _apply_to_bus() -> void:
	var master: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master, _muted)
	# 線性 → 分貝 (0 = silent special case)
	var db: float = -80.0 if _volume_linear <= 0.0 else linear_to_db(_volume_linear)
	AudioServer.set_bus_volume_db(master, db)

func _save() -> void:
	var data: Dictionary = {
		"volume": _volume_linear,
		"muted": _muted,
	}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[AudioSettings] failed to open %s for write" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.get_open_error() != OK:
		push_warning("[AudioSettings] write error for %s" % SAVE_PATH)

func _load() -> void:
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return  # first run, use defaults
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[AudioSettings] %s is not a JSON object" % SAVE_PATH)
		return
	var d: Dictionary = parsed
	_volume_linear = clamp(float(d.get("volume", 1.0)), 0.0, 1.0)
	_muted = bool(d.get("muted", false))
