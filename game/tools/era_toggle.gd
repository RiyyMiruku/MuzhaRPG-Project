@tool
extends EditorScript

## 在編輯器裡一鍵切換時代顯示。
## 用法：Script Editor → File → Run (Ctrl+Shift+X)
##
## 用節點名稱前綴判斷時代：
##   "1983_" 開頭 = 1983 時代
##   "mod_"  開頭 = 現代
##   其他 = 不動

func _run() -> void:
	var root: Node = get_editor_interface().get_edited_scene_root()
	if root == null:
		print("[era_toggle] No scene open")
		return

	var nodes_1983: Array[Node] = []
	var nodes_modern: Array[Node] = []
	_collect(root, nodes_1983, nodes_modern)

	if nodes_1983.is_empty() and nodes_modern.is_empty():
		print("[era_toggle] No 1983_* or mod_* nodes found")
		return

	# 看第一個 1983 節點決定要切到哪個方向
	var show_1983: bool = true
	if not nodes_1983.is_empty():
		show_1983 = not (nodes_1983[0] as CanvasItem).visible

	for node: CanvasItem in nodes_1983:
		node.visible = show_1983

	for node: CanvasItem in nodes_modern:
		node.visible = not show_1983

	var era: String = "1983" if show_1983 else "modern"
	print("[era_toggle] -> %s (%d 1983 nodes, %d modern nodes)" % [era, nodes_1983.size(), nodes_modern.size()])


func _collect(node: Node, out_1983: Array[Node], out_modern: Array[Node]) -> void:
	var n: String = node.name
	if node is CanvasItem:
		if n.begins_with("1983_") or n.ends_with("_1983"):
			out_1983.append(node)
		elif n.begins_with("mod_") or n.ends_with("_modern"):
			out_modern.append(node)
	for child in node.get_children():
		_collect(child, out_1983, out_modern)
