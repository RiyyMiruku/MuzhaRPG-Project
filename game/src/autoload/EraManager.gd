## EraManager — 時空切換管理器
##
## Chapter 1 核心 mechanic:同一 zone 內透過 hybrid Era group 切 1983 ↔ modern。
##
## 與 ZoneManager 的分工:
##   - ZoneManager 處理「不同 zone 之間」的場景切換(load 新 .tscn、定位 player)
##   - EraManager 處理「同 zone 內 era 切換」(toggle group visible + tween tint),
##     不換 .tscn,player 位置不動
##
## Hybrid zone 識別:`get_tree().get_nodes_in_group("era_modern")` 不為空就是。
## 單時空 zone(group 不存在)切 era 等於 no-op 視覺上,但 `current_era` 狀態仍會更新。
##
## EraTint mood:
##   1983 → 暖黃 sepia(回憶感) Color(1.0, 0.96, 0.82)
##   modern → 冷藍灰(現實感)   Color(0.78, 0.82, 0.88)
##
## 觸發:玩家對 old_map_paper 互動 → events.gd 呼叫 `EraManager.travel_to("1983")`
extends Node

# ── Signals ─────────────────────────────────────────────────────────────────
signal era_changed(from_era: String, to_era: String)
signal era_transition_started(to_era: String)
signal era_transition_finished(to_era: String)

# ── State ───────────────────────────────────────────────────────────────────
var current_era: String = "1983"

# ── Constants ───────────────────────────────────────────────────────────────
const TINT_PRESETS: Dictionary = {
	"1983":   Color(1.0, 0.96, 0.82),
	"modern": Color(0.78, 0.82, 0.88),
}
const ERA_GROUP_PREFIX: String = "era_"
## 全暗顏色 — CanvasModulate × 黑 = 0,真正把畫面遮黑遮住 era swap
const BLACKOUT_COLOR: Color = Color.BLACK
## 燈泡 flicker 短暫亮起的微白色(不用純白 — 偏暖一點比較像舊燈泡)
const FLICKER_PEAK_COLOR: Color = Color(0.95, 0.92, 0.85)

# ── Public API ──────────────────────────────────────────────────────────────
func travel_to(target_era: String) -> void:
	if target_era == current_era:
		return
	if not TINT_PRESETS.has(target_era):
		push_error("EraManager: unknown era %s" % target_era)
		return

	var old_era: String = current_era
	era_transition_started.emit(target_era)

	# 1. 找當前 zone 的 EraTint 節點(可能不存在 — 單時空 zone)
	var tint: CanvasModulate = _find_era_tint()

	# 2. 短促閃白 → 切 visibility → 漸到目標 tint(燈泡閃感)
	if tint != null:
		await _flash_and_swap(tint, target_era)
	else:
		_swap_visibility(target_era)

	current_era = target_era
	era_changed.emit(old_era, target_era)
	era_transition_finished.emit(target_era)

## 給新 zone 載入完後手動呼叫:套用當前 era 的可見性 + tint
## (因為 zone .tscn 預設可見的 era 可能跟 current_era 不一致)
func apply_to_current_zone() -> void:
	_swap_visibility(current_era)
	var tint: CanvasModulate = _find_era_tint()
	if tint != null:
		tint.color = TINT_PRESETS[current_era]

# ── Internal ────────────────────────────────────────────────────────────────
func _flash_and_swap(tint: CanvasModulate, target_era: String) -> void:
	# 預先算好幾個色階,避免 tween 中重複計算。alpha 一律設 1 避免 CanvasModulate 透明度跑掉。
	var start_color: Color = tint.color
	var dim: Color = Color(start_color.r * 0.25, start_color.g * 0.25, start_color.b * 0.25, 1.0)
	var gasp: Color = Color(start_color.r * 0.55, start_color.g * 0.55, start_color.b * 0.55, 1.0)
	var weak: Color = Color(FLICKER_PEAK_COLOR.r * 0.4, FLICKER_PEAK_COLOR.g * 0.4, FLICKER_PEAK_COLOR.b * 0.4, 1.0)
	var mid: Color = Color(FLICKER_PEAK_COLOR.r * 0.7, FLICKER_PEAK_COLOR.g * 0.7, FLICKER_PEAK_COLOR.b * 0.7, 1.0)

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)  # flicker 階段用線性 — 硬切才有電流感

	# ── Phase 1:跳電前 stutter(~0.36s) — 燈光快速忽明忽暗、最後嘆息一下熄滅 ──
	tween.tween_property(tint, "color", dim, 0.05)
	tween.tween_property(tint, "color", start_color, 0.03)
	tween.tween_property(tint, "color", dim, 0.04)
	tween.tween_property(tint, "color", start_color, 0.06)
	tween.tween_property(tint, "color", dim, 0.03)
	tween.tween_property(tint, "color", BLACKOUT_COLOR, 0.04)
	tween.tween_property(tint, "color", gasp, 0.05)        # 一聲嘆息(回光返照)
	tween.tween_property(tint, "color", BLACKOUT_COLOR, 0.06)

	# ── Phase 2:黑屏 hold + swap(~0.25s)── 玩家看不到內容跳變
	tween.tween_interval(0.10)
	tween.tween_callback(_swap_visibility.bind(target_era))
	tween.tween_interval(0.15)

	# ── Phase 3:重啟混亂 flicker(~0.36s) — 多段亮度試圖恢復 ──
	tween.tween_property(tint, "color", weak, 0.04)
	tween.tween_property(tint, "color", BLACKOUT_COLOR, 0.05)
	tween.tween_property(tint, "color", FLICKER_PEAK_COLOR, 0.03)
	tween.tween_property(tint, "color", BLACKOUT_COLOR, 0.07)
	tween.tween_property(tint, "color", mid, 0.04)
	tween.tween_property(tint, "color", FLICKER_PEAK_COLOR, 0.05)
	tween.tween_property(tint, "color", mid, 0.04)
	tween.tween_property(tint, "color", FLICKER_PEAK_COLOR, 0.04)

	# ── Phase 4:穩定 settle(0.6s) — 光線穩下來溶到目標 era tint ──
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(tint, "color", TINT_PRESETS[target_era], 0.60)

	await tween.finished

func _swap_visibility(target_era: String) -> void:
	# 遍歷所有 era_* group,只留 target_era 的可見 + 碰撞啟用
	# 先收集所有 era 節點,若節點同時屬於目標 era group 則保持可見
	var target_group: String = ERA_GROUP_PREFIX + target_era
	var seen: Dictionary = {}  # node instance id → bool (should be active)
	for era_key: String in TINT_PRESETS:
		var group_name: String = ERA_GROUP_PREFIX + era_key
		var nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)
		var is_target: bool = (era_key == target_era)
		for n: Node in nodes:
			var id: int = n.get_instance_id()
			# 只要節點屬於目標 era group 就標記為 active
			if is_target:
				seen[id] = true
			elif not seen.has(id):
				seen[id] = false
	for era_key: String in TINT_PRESETS:
		var group_name: String = ERA_GROUP_PREFIX + era_key
		for n: Node in get_tree().get_nodes_in_group(group_name):
			var active: bool = seen.get(n.get_instance_id(), false)
			if n is CanvasItem:
				(n as CanvasItem).visible = active
			# 停用/啟用碰撞體，避免隱藏物件擋路
			_set_physics_enabled(n, active)
			# 停用 _process / _physics_process，避免隱藏 NPC 仍跑 AI 浪費 CPU
			n.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _set_physics_enabled(node: Node, enabled: bool) -> void:
	for child in node.get_children():
		if child is CollisionShape2D:
			child.disabled = not enabled
		elif child is StaticBody2D or child is Area2D:
			_set_physics_enabled(child, enabled)
		elif child is CollisionPolygon2D:
			child.disabled = not enabled

func _find_era_tint() -> CanvasModulate:
	# 假設 EraTint 在當前 zone 內名為 "EraTint",透過 group 找最穩
	# 但 builder 沒幫 EraTint 加 group,改用 scene tree 搜尋
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	var found: Node = root.find_child("EraTint", true, false)
	if found is CanvasModulate:
		return found as CanvasModulate
	return null

# ── Serialization(GameManager.save_game 用) ────────────────────────────────
func serialize() -> Dictionary:
	return {"current_era": current_era}

func deserialize(data: Dictionary) -> void:
	current_era = data.get("current_era", "modern")
