## SurfaceRegistry — autoload
## 讀 res://assets/audio/surface_map.json 並提供 tileset → surface_id 查詢。
extends Node

const _MAP_PATH: String = "res://assets/audio/surface_map.json"

var _tileset_to_surface: Dictionary = {}

func _ready() -> void:
	_load()

func _load() -> void:
	var f: FileAccess = FileAccess.open(_MAP_PATH, FileAccess.READ)
	if f == null:
		push_warning("[SurfaceRegistry] %s missing — footsteps will be silent" % _MAP_PATH)
		return
	var text: String = f.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_tileset_to_surface = parsed
		print("[SurfaceRegistry] loaded %d entries: %s" % [_tileset_to_surface.size(), _tileset_to_surface])
	else:
		push_warning("[SurfaceRegistry] %s is not a JSON object" % _MAP_PATH)

func surface_for_tileset(tileset_name: String) -> String:
	return _tileset_to_surface.get(tileset_name, "")
