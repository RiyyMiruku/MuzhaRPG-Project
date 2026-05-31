@tool
extends EditorScript

## 在當前場景的 TileMapLayer 畫等角圓形。
## 執行方式：File → Run 或 Ctrl+Shift+X

# ── 設定這裡 ──────────────────────────────
const CENTER_X  : int = 0   # 圓心 X（tile 座標）
const CENTER_Y  : int = 0   # 圓心 Y（tile 座標）
const RADIUS    : int = 15  # 半徑（tile 數）
const TERRAIN_SET: int = 0
const TERRAIN   : int = 1
const ERASE     : bool = false  # true = 改成清除模式
# ─────────────────────────────────────────

func _run() -> void:
	# 找場景裡第一個 TileMapLayer（parent，非 TileMapDual child）
	var scene := get_scene()
	if scene == null:
		printerr("沒有開啟的場景")
		return

	var tilemap: TileMapLayer = _find_tilemap(scene)
	if tilemap == null:
		printerr("找不到 TileMapLayer 節點")
		return

	var cells: Array[Vector2i] = []
	for x in range(CENTER_X - RADIUS, CENTER_X + RADIUS + 1):
		for y in range(CENTER_Y - RADIUS, CENTER_Y + RADIUS + 1):
			var dx: float = float(x - CENTER_X)
			var dy: float = float(y - CENTER_Y) * 2.0  # 等角 2:1 橢圓
			if dx * dx + dy * dy <= float(RADIUS * RADIUS) * 4.0:
				cells.append(Vector2i(x, y))

	if ERASE:
		for cell in cells:
			tilemap.erase_cell(cell)
		print("清除 %d 格完成" % cells.size())
	else:
		tilemap.set_cells_terrain_connect(cells, TERRAIN_SET, TERRAIN)
		print("畫圓 %d 格完成（圓心=%d,%d 半徑=%d）" % [cells.size(), CENTER_X, CENTER_Y, RADIUS])

func _find_tilemap(node: Node) -> TileMapLayer:
	if node is TileMapLayer and node.name == "TileMapLayer":
		return node as TileMapLayer
	for child in node.get_children():
		var result := _find_tilemap(child)
		if result != null:
			return result
	return null
