## AudioSettings — autoload
## 管理 Master / Music / SFX 三條 bus 音量 + 一鍵靜音(套在 Master)。
## 狀態存 user://audio_settings.json，讓下次開遊戲記住。
extends Node

signal volume_changed(channel: String, linear: float)
signal mute_changed(muted: bool)

const SAVE_PATH: String = "user://audio_settings.json"

## 音量頻道常數 (對外 API 用)
const MASTER: String = "master"
const MUSIC: String = "music"
const SFX: String = "sfx"

## channel -> AudioServer bus 名稱
const _BUS_NAMES: Dictionary = {
	MASTER: "Master",
	MUSIC: "Music",
	SFX: "SFX",
}

## channel -> 線性音量 0.0–1.0
var _volumes: Dictionary = {
	MASTER: 1.0,
	MUSIC: 1.0,
	SFX: 1.0,
}
var _muted: bool = false

func _ready() -> void:
	_load()
	_apply_all()

# ── Public API ────────────────────────────────────────────────────────────────

func get_volume(channel: String) -> float:
	return float(_volumes.get(channel, 1.0))

func set_volume(channel: String, linear: float) -> void:
	if not _volumes.has(channel):
		push_warning("[AudioSettings] unknown channel '%s'" % channel)
		return
	_volumes[channel] = clamp(linear, 0.0, 1.0)
	_apply_channel(channel)
	_save()
	volume_changed.emit(channel, _volumes[channel])

func is_muted() -> bool:
	return _muted

func set_muted(muted: bool) -> void:
	_muted = muted
	_apply_mute()
	_save()
	mute_changed.emit(_muted)

func toggle_mute() -> void:
	set_muted(not _muted)

# ── Internals ────────────────────────────────────────────────────────────────

func _apply_all() -> void:
	for channel in _volumes:
		_apply_channel(channel)
	_apply_mute()

func _apply_channel(channel: String) -> void:
	var bus_name: String = _BUS_NAMES[channel]
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		push_warning("[AudioSettings] bus '%s' not found" % bus_name)
		return
	var linear: float = float(_volumes[channel])
	# 線性 → 分貝 (0 = silent special case)
	var db: float = -80.0 if linear <= 0.0 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)

func _apply_mute() -> void:
	var idx: int = AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, _muted)

func _save() -> void:
	var data: Dictionary = {
		"master": _volumes[MASTER],
		"music": _volumes[MUSIC],
		"sfx": _volumes[SFX],
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
	# 向後相容：舊存檔只有單一 "volume" → 視為 master
	if d.has("volume") and not d.has("master"):
		_volumes[MASTER] = clamp(float(d.get("volume", 1.0)), 0.0, 1.0)
	else:
		_volumes[MASTER] = clamp(float(d.get("master", 1.0)), 0.0, 1.0)
	_volumes[MUSIC] = clamp(float(d.get("music", 1.0)), 0.0, 1.0)
	_volumes[SFX] = clamp(float(d.get("sfx", 1.0)), 0.0, 1.0)
	_muted = bool(d.get("muted", false))
