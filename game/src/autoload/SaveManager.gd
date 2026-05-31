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

# ── Load 編排 ───────────────────────────────────────────────────────────────
## 依正確順序把存檔資料套回各 manager（不含場景 reload — 供 load_from_slot 與測試共用）。
## 順序關鍵：Story（flags/events）→ Chapter（re-register events，補回 _relationship_triggers）
## → Quest（reevaluate 此時看得到完整 triggers）→ Era；最後還原 GameManager runtime。
func apply_save_data(data: Dictionary) -> void:
	if data.has("story"):
		StoryManager.deserialize(data["story"])
	if data.has("chapter"):
		ChapterManager.deserialize(data["chapter"])
	if data.has("quests"):
		QuestManager.deserialize(data["quests"])
	if data.has("era"):
		EraManager.deserialize(data["era"])
	var time_played: float = float(data.get("time_played_sec", 0.0))
	var player_data: Dictionary = data.get("player", {})
	var pos: Vector2 = Vector2(
		float(player_data.get("position_x", 0.0)),
		float(player_data.get("position_y", 0.0))
	)
	GameManager.apply_loaded_runtime(time_played, pos)


## 讀檔並解析 JSON。不存在/壞檔回空 Dictionary。
func read_slot_data(slot: Variant) -> Dictionary:
	if not has_slot(slot):
		return {}
	var file: FileAccess = FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		push_error("SaveManager: corrupt save slot %s" % str(slot))
		return {}
	file.close()
	return json.data

## 完整載入：讀檔 → 重載主場景 → 套狀態 → 跳 zone → 套 era 濾鏡。回是否成功。
func load_from_slot(slot: Variant) -> bool:
	var data: Dictionary = read_slot_data(slot)
	if data.is_empty():
		EventBus.hud_message_requested.emit("讀取存檔失敗", 2.0)
		save_failed.emit(slot, "讀檔失敗")
		return false
	GameManager.change_state(GameManager.GameState.LOADING)
	get_tree().reload_current_scene()
	await get_tree().process_frame
	await get_tree().process_frame
	apply_save_data(data)
	var player_data: Dictionary = data.get("player", {})
	var zone_id: String = player_data.get("zone", "zone_apartment_muzha")
	EventBus.zone_transition_requested.emit(zone_id, "default")
	EraManager.apply_to_current_zone()
	GameManager.change_state(GameManager.GameState.EXPLORING)
	print("SaveManager: loaded slot %s" % str(slot))
	load_completed.emit(slot)
	EventBus.hud_message_requested.emit("遊戲已載入", 2.0)
	return true

## 刪除手動 slot 檔案（auto slot 不開放刪除由 UI 控制）。
func delete_slot(slot: Variant) -> void:
	if has_slot(slot):
		DirAccess.remove_absolute(_slot_path(slot))


# ── Autosave ────────────────────────────────────────────────────────────────
func _on_autosave_tick() -> void:
	# 只在探索狀態存，避免存到 cutscene/對話/載入中的中間狀態
	if GameManager.current_state == GameManager.GameState.EXPLORING:
		if save_to_slot(AUTO_SLOT):
			EventBus.hud_message_requested.emit("已自動存檔", 2.0)
