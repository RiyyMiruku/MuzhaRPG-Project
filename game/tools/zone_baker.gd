@tool
extends Node2D

## [Deprecated] Cells were used by the removed Bake terrain button.
## Kept as inert @export to load old scenes without warnings; safe to ignore.
@export var terrain_cells: Array[Vector2i] = []
## [Deprecated] Companion to terrain_cells; see above.
@export var terrain_id: int = 1
## YAML 來源路徑(repo-relative)。builder 寫入,Lock/Unlock 按鈕用。
## Hybrid zone 會有多個(e.g. pharmacy/1983.yaml + pharmacy/modern.yaml)。
@export var yaml_paths: Array[String] = []

## 腳步聲節奏(像素為單位,每走 N px 觸發一聲)。0 = 用全域預設(40)。
## 在 Inspector 改完存場景,runtime 自動套用,不需要 rebuild。
@export var footstep_step_distance: float = 0.0

@export_tool_button("Lock YAML (frozen: true)") var _lock_action: Callable = _lock_yaml
@export_tool_button("Unlock YAML") var _unlock_action: Callable = _unlock_yaml

@export_tool_button("Era: Show 1983") var _show_1983_action: Callable = func() -> void: _show_era("1983")
@export_tool_button("Era: Show Modern") var _show_modern_action: Callable = func() -> void: _show_era("modern")
@export_tool_button("Era: Show Both") var _show_both_action: Callable = _show_both_eras

@export_tool_button("Refresh Showcase from tags") var _refresh_showcase_action: Callable = _refresh_showcase
@export_tool_button("Clear Showcase") var _clear_showcase_action: Callable = _clear_showcase


func _lock_yaml() -> void:
	_set_yaml_frozen(true)


func _unlock_yaml() -> void:
	_set_yaml_frozen(false)


## 把 `frozen: true` 加進或從 YAML 移除(用 regex,適用本專案的簡單 YAML)
func _set_yaml_frozen(target: bool) -> void:
	if yaml_paths.is_empty():
		push_error("[zone_baker] yaml_paths empty — re-run build_zone.py first")
		return
	var repo_root: String = ProjectSettings.globalize_path("res://").path_join("..")
	var processed: int = 0
	for rel: String in yaml_paths:
		var abs_path: String = repo_root.path_join(rel).simplify_path()
		if not FileAccess.file_exists(abs_path):
			push_warning("[zone_baker] YAML not found: %s" % abs_path)
			continue
		var f: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
		if f == null:
			push_warning("[zone_baker] cannot open %s" % abs_path)
			continue
		var text: String = f.get_as_text()
		f.close()

		var new_text: String = _toggle_frozen_line(text, target)
		if new_text == text:
			continue
		var wf: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
		if wf == null:
			push_warning("[zone_baker] cannot write %s" % abs_path)
			continue
		wf.store_string(new_text)
		wf.close()
		processed += 1

	var state_word: String = "locked" if target else "unlocked"
	print("[zone_baker] %s %d YAML file(s)." % [state_word, processed])


func _toggle_frozen_line(text: String, target: bool) -> String:
	# 用 regex 找 ^frozen:\s* 開頭的整行
	var re: RegEx = RegEx.new()
	re.compile("(?m)^frozen:\\s*\\w+\\s*$")
	var has_line: bool = re.search(text) != null

	if target:
		if has_line:
			# 已有 → 確保是 true
			return re.sub(text, "frozen: true", false)
		# 沒有 → 在第一個非註解非空行前插入
		var lines: PackedStringArray = text.split("\n")
		var insert_at: int = 0
		for i in range(lines.size()):
			var stripped: String = lines[i].strip_edges()
			if stripped.is_empty() or stripped.begins_with("#"):
				continue
			insert_at = i
			break
		lines.insert(insert_at, "frozen: true")
		return "\n".join(lines)
	else:
		# Unlock — 移除整行
		return re.sub(text, "", false).replace("\n\n\n", "\n\n")


# ── Era editor toggles ──────────────────────────────────────────────────────
## Show only nodes in group "era_<which>"; hide nodes in other "era_*" groups.
## Runtime EraManager 會在 _ready() 重設可見性，此操作只影響 editor view。
## 存場景後 visible 旗標會進 .tscn，可接受(runtime 會 override)。
func _show_era(which: String) -> void:
	var eras: Array[String] = ["1983", "modern"]
	for e in eras:
		var should_show: bool = (e == which)
		_set_era_visible(e, should_show)
	print("[zone_baker] Era view: %s only. Save (Ctrl+S) to persist." % which)


func _show_both_eras() -> void:
	_set_era_visible("1983", true)
	_set_era_visible("modern", true)
	print("[zone_baker] Era view: both visible.")


## Walk descendants of this zone root; toggle visible on any node in era_<e>.
## Constrained to current scene (avoids leaking across open scenes in editor).
func _set_era_visible(era: String, visible_flag: bool) -> void:
	var group_name: String = "era_" + era
	_apply_visible_recursive(self, group_name, visible_flag)


func _apply_visible_recursive(node: Node, group_name: String, visible_flag: bool) -> void:
	if node.is_in_group(group_name):
		if node is CanvasItem:
			(node as CanvasItem).visible = visible_flag
	for child in node.get_children():
		_apply_visible_recursive(child, group_name, visible_flag)


# ── Showcase (asset visibility tool) ────────────────────────────────────────
## Refresh `Showcase` child node with every prop in art_source/objects/<id>/
## tagged `zone:<this_zone_slug>`. Useful to see what art is available for
## this scene without drag-dropping each one. Visible toggle in Inspector.
##
## Showcase is created on first refresh; its content is destroyed and rebuilt
## each refresh. Live scene content (YSortRoot, etc.) is untouched.

const _SHOWCASE_COLS: int = 6
const _SHOWCASE_SPACING_X: float = 96.0
const _SHOWCASE_SPACING_Y: float = 80.0
## Offset relative to zone root; placed to upper-right out of typical play area.
const _SHOWCASE_ORIGIN: Vector2 = Vector2(400.0, -400.0)


func _refresh_showcase() -> void:
	var slug: String = _zone_slug_from_name()
	if slug == "":
		push_error("[showcase] could not derive zone slug from node name '%s'" % self.name)
		return
	var prop_ids: PackedStringArray = _find_props_tagged_with_zone(slug)
	var sc: Node2D = _ensure_showcase()
	# Clear existing content
	for child in sc.get_children():
		child.queue_free()
	# Place each prop in grid
	var col: int = 0
	var row: int = 0
	var added: int = 0
	for id in prop_ids:
		var tscn_path: String = "res://src/maps/props/%s.tscn" % id
		if not ResourceLoader.exists(tscn_path):
			push_warning("[showcase] no prop tscn for %s" % id)
			continue
		var ps: PackedScene = load(tscn_path)
		if ps == null:
			continue
		var inst: Node = ps.instantiate()
		sc.add_child(inst)
		inst.owner = self  # required so child saves into scene file
		if inst is Node2D:
			(inst as Node2D).position = Vector2(col * _SHOWCASE_SPACING_X, row * _SHOWCASE_SPACING_Y)
		col += 1
		if col >= _SHOWCASE_COLS:
			col = 0
			row += 1
		added += 1
	print("[showcase] populated %d / %d props for zone '%s'. Save (Ctrl+S) to persist." % [added, prop_ids.size(), slug])


func _clear_showcase() -> void:
	var sc: Node2D = get_node_or_null("Showcase") as Node2D
	if sc == null:
		print("[showcase] no Showcase node to clear.")
		return
	for child in sc.get_children():
		child.queue_free()
	print("[showcase] cleared. Save (Ctrl+S) to persist.")


func _ensure_showcase() -> Node2D:
	var sc: Node2D = get_node_or_null("Showcase") as Node2D
	if sc != null:
		return sc
	sc = Node2D.new()
	sc.name = "Showcase"
	sc.position = _SHOWCASE_ORIGIN
	sc.visible = false  # default hidden so editor view stays clean
	add_child(sc)
	sc.owner = self
	return sc


## "ZoneApartmentMuzha" → "zone_apartment_muzha"
func _zone_slug_from_name() -> String:
	var s: String = self.name
	var out: String = ""
	for i in s.length():
		var ch: String = s[i]
		var is_upper: bool = ch >= "A" and ch <= "Z"
		if is_upper and i > 0:
			out += "_"
		out += ch.to_lower()
	return out


func _find_props_tagged_with_zone(slug: String) -> PackedStringArray:
	var repo_root: String = ProjectSettings.globalize_path("res://").path_join("..")
	var objects_dir_path: String = repo_root.path_join("art_source/objects")
	var ids: Array[String] = []
	var dir: DirAccess = DirAccess.open(objects_dir_path)
	if dir == null:
		push_warning("[showcase] cannot open %s" % objects_dir_path)
		return PackedStringArray()
	dir.list_dir_begin()
	var name_entry: String = dir.get_next()
	var target_tag: String = "zone:" + slug
	while name_entry != "":
		if dir.current_is_dir() and not name_entry.begins_with("."):
			var asset_json_path: String = objects_dir_path.path_join(name_entry).path_join("asset.json")
			if FileAccess.file_exists(asset_json_path):
				var af: FileAccess = FileAccess.open(asset_json_path, FileAccess.READ)
				if af != null:
					var parsed: Variant = JSON.parse_string(af.get_as_text())
					if parsed is Dictionary:
						var tags: Variant = parsed.get("tags", [])
						if tags is Array:
							for t in tags:
								if t == target_tag:
									ids.append(name_entry)
									break
		name_entry = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	return PackedStringArray(ids)
