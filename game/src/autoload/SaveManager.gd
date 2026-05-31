## SaveManager — 存讀檔編排 autoload
## 職責：收集各 manager serialize → 寫檔；讀檔 → 重載場景 → 依序 deserialize → 套 zone/era。
## 註冊順序須在所有依賴 manager（Game/Story/Chapter/Quest/Era）之後。
extends Node

# ── Signals ─────────────────────────────────────────────────────────────────
signal save_completed(slot: Variant)
signal load_completed(slot: Variant)
signal save_failed(slot: Variant, reason: String)

# ── Constants ───────────────────────────────────────────────────────────────
const SAVE_DIR: String = "user://saves/"
const SAVE_VERSION: String = "0.2.0"
const MANUAL_SLOTS: Array = [1, 2, 3]
const AUTO_SLOT: String = "auto"
const AUTOSAVE_INTERVAL_SEC: float = 300.0

# ── State ───────────────────────────────────────────────────────────────────
var _autosave_timer: Timer = null

func _ready() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_SEC
	_autosave_timer.one_shot = false
	_autosave_timer.timeout.connect(_on_autosave_tick)
	add_child(_autosave_timer)
	_autosave_timer.start()

# ── Path helpers ────────────────────────────────────────────────────────────
func _slot_path(slot: Variant) -> String:
	return SAVE_DIR + "save_%s.json" % str(slot)

func has_slot(slot: Variant) -> bool:
	return FileAccess.file_exists(_slot_path(slot))

# ── Save ────────────────────────────────────────────────────────────────────
## 收集所有 manager 狀態寫入指定 slot。回傳是否成功。
func save_to_slot(slot: Variant) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var player_pos: Vector2 = GameManager.collect_player_position()
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"timestamp": int(Time.get_unix_time_from_system()),
		"player": {
			"zone": StoryManager.current_zone,
			"position_x": player_pos.x,
			"position_y": player_pos.y,
		},
		"story": StoryManager.serialize(),
		"quests": QuestManager.serialize(),
		"chapter": ChapterManager.serialize(),
		"era": EraManager.serialize(),
		"time_played_sec": GameManager.get_time_played_sec(),
	}
	var file: FileAccess = FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write slot %s" % str(slot))
		save_failed.emit(slot, "寫檔失敗")
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("SaveManager: saved slot %s" % str(slot))
	save_completed.emit(slot)
	return true

# ── Slot info (給 UI) ───────────────────────────────────────────────────────
## 回 slot 的摘要：{exists, chapter_id, time_played_sec, timestamp}。不存在/壞檔回 {"exists": false}。
func get_slot_info(slot: Variant) -> Dictionary:
	if not has_slot(slot):
		return {"exists": false}
	var file: FileAccess = FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		return {"exists": false}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {"exists": false}
	file.close()
	var data: Dictionary = json.data
	var chapter: Dictionary = data.get("chapter", {})
	return {
		"exists": true,
		"chapter_id": chapter.get("current_chapter_id", ""),
		"time_played_sec": float(data.get("time_played_sec", 0.0)),
		"timestamp": int(data.get("timestamp", 0)),
	}

## 回所有 slot（3 手動 + auto）的 info，附 slot 與 is_auto 欄位。
func list_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for s: int in MANUAL_SLOTS:
		var info: Dictionary = get_slot_info(s)
		info["slot"] = s
		info["is_auto"] = false
		result.append(info)
	var auto_info: Dictionary = get_slot_info(AUTO_SLOT)
	auto_info["slot"] = AUTO_SLOT
	auto_info["is_auto"] = true
	result.append(auto_info)
	return result

# ── Autosave ────────────────────────────────────────────────────────────────
func _on_autosave_tick() -> void:
	# 只在探索狀態存，避免存到 cutscene/對話/載入中的中間狀態
	if GameManager.current_state == GameManager.GameState.EXPLORING:
		if save_to_slot(AUTO_SLOT):
			EventBus.hud_message_requested.emit("已自動存檔", 2.0)
