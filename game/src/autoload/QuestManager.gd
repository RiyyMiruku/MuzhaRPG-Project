## QuestManager — 任務追蹤系統
## 管理任務的接取、進度追蹤、完成判定。
## 任務 = 劇情事件真相（StoryManager flags/events）的玩家可見投影：
## objectives 掛接既有 beat/cutscene 事件與 flag，自動開始/逐項打勾/完成。
extends Node

# ── Signals ─────────────────────────────────────────────────────────────────
signal quest_started(quest_id: String)
signal quest_completed(quest_id: String)
signal quest_available(quest_id: String)

# ── State ───────────────────────────────────────────────────────────────────
var _all_quests: Dictionary = {}           # quest_id -> QuestData
var _active_quests: Array[String] = []     # 進行中的任務
var _completed_quests: Array[String] = []  # 已完成的任務

func _ready() -> void:
	_load_all_quests()
	# 監聽事件與旗標變動，自動重評任務開始/完成條件
	StoryManager.event_recorded.connect(_on_story_event)
	StoryManager.flag_changed.connect(_on_story_flag)

# ── Loading ───────────────────────────────────────────────────────────────────
func _load_all_quests() -> void:
	_load_quests_from_dir("res://src/quests/")
	_load_chapter_quests()
	print("QuestManager: loaded %d quests" % _all_quests.size())

func _load_quests_from_dir(quest_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(quest_dir):
		return
	var dir: DirAccess = DirAccess.open(quest_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var quest: QuestData = load(quest_dir + file_name) as QuestData
			if quest and not quest.quest_id.is_empty():
				_all_quests[quest.quest_id] = quest
		file_name = dir.get_next()
	dir.list_dir_end()

## 掃描 res://src/chapters/<id>/quests/ 下所有任務，與全域池合併。
func _load_chapter_quests() -> void:
	var base: String = "res://src/chapters/"
	if not DirAccess.dir_exists_absolute(base):
		return
	var dir: DirAccess = DirAccess.open(base)
	if dir == null:
		return
	dir.list_dir_begin()
	var sub: String = dir.get_next()
	while sub != "":
		if dir.current_is_dir() and not sub.begins_with("."):
			_load_quests_from_dir(base + sub + "/quests/")
		sub = dir.get_next()
	dir.list_dir_end()

## 測試/程式用：手動註冊一筆任務資料。
func register_quest(quest: QuestData) -> void:
	if quest and not quest.quest_id.is_empty():
		_all_quests[quest.quest_id] = quest

# ── Public API ──────────────────────────────────────────────────────────────
func start_quest(quest_id: String) -> bool:
	if _active_quests.has(quest_id) or _completed_quests.has(quest_id):
		return false
	if not _all_quests.has(quest_id):
		push_warning("QuestManager: Unknown quest: " + quest_id)
		return false
	var quest: QuestData = _all_quests[quest_id]
	if not _can_start(quest):
		return false
	_active_quests.append(quest_id)
	quest_started.emit(quest_id)
	print("QuestManager: quest started - ", quest.title)
	return true

func complete_quest(quest_id: String) -> void:
	if not _active_quests.has(quest_id):
		return
	_active_quests.erase(quest_id)
	_completed_quests.append(quest_id)
	var quest: QuestData = _all_quests[quest_id]
	_apply_rewards(quest)
	quest_completed.emit(quest_id)
	print("QuestManager: quest completed - ", quest.title)

func is_quest_active(quest_id: String) -> bool:
	return _active_quests.has(quest_id)

func is_quest_completed(quest_id: String) -> bool:
	return _completed_quests.has(quest_id)

func get_active_quests() -> Array[QuestData]:
	var result: Array[QuestData] = []
	for qid: String in _active_quests:
		if _all_quests.has(qid):
			result.append(_all_quests[qid])
	return result

func get_quest(quest_id: String) -> QuestData:
	return _all_quests.get(quest_id, null)

## 給 journal：回每個 objective 的 {desc, optional, done}。
func get_objective_status(quest_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var quest: QuestData = _all_quests.get(quest_id, null)
	if quest == null:
		return result
	for obj: Dictionary in quest.objectives:
		result.append({
			"desc": obj.get("desc", ""),
			"optional": obj.get("optional", false),
			"done": QuestData.is_objective_done(obj, StoryManager.completed_events, StoryManager.player_flags),
		})
	return result

# ── Internal ────────────────────────────────────────────────────────────────
func _on_story_event(_event_id: String) -> void:
	reevaluate()

func _on_story_flag(_key: String, _value: Variant) -> void:
	reevaluate()

## 重評所有任務的開始/完成條件。訊號自動呼叫；章節開場或測試也可手動呼叫一次初評。
func reevaluate() -> void:
	# 先檢查完成
	for qid: String in _active_quests.duplicate():
		var quest: QuestData = _all_quests[qid]
		if _check_completion(quest):
			complete_quest(qid)
	# 再檢查可自動接取
	for qid: String in _all_quests:
		if _active_quests.has(qid) or _completed_quests.has(qid):
			continue
		var quest: QuestData = _all_quests[qid]
		if _can_start(quest):
			start_quest(qid)

func _can_start(quest: QuestData) -> bool:
	for req: String in quest.required_events:
		if not StoryManager.completed_events.has(req):
			return false
	return true

func _check_completion(quest: QuestData) -> bool:
	if not QuestData.all_required_objectives_done(quest.objectives, StoryManager.completed_events, StoryManager.player_flags):
		return false
	for evt: String in quest.completion_events:
		if not StoryManager.completed_events.has(evt):
			return false
	return true

func _apply_rewards(quest: QuestData) -> void:
	for npc_id: String in quest.reward_relationship:
		var delta: int = quest.reward_relationship[npc_id]
		StoryManager.update_relationship(npc_id, delta)
	if not quest.reward_unlock_zone.is_empty():
		StoryManager.unlock_zone(quest.reward_unlock_zone)
	if not quest.reward_event.is_empty():
		StoryManager.record_event(quest.reward_event)

# ── Persistence ─────────────────────────────────────────────────────────────
func serialize() -> Dictionary:
	return {
		"active_quests": _active_quests.duplicate(),
		"completed_quests": _completed_quests.duplicate(),
	}

func deserialize(data: Dictionary) -> void:
	_active_quests.assign(data.get("active_quests", []))
	_completed_quests.assign(data.get("completed_quests", []))
	# 任務的 objective 進度不另存，靠 reevaluate 從 StoryManager 已還原的
	# events/flags 重算；載入後立即對帳一次，避免已滿足的任務卡在 active。
	reevaluate()
