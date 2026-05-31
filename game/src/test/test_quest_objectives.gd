## Headless 測試：任務 objectives 判定 + StoryManager 事件/旗標/信任掛鉤 + QuestManager 整合。
## 跑法：godot --headless --path game --script res://src/test/test_quest_objectives.gd
## 全 pass 離開碼 0，任一 fail 離開碼 1。
extends SceneTree

var _fail: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: ", msg)
	else:
		_fail += 1
		printerr("  FAIL: ", msg)

func _initialize() -> void:
	# Autoloads are children of root but not yet added during _initialize.
	# Defer execution until the first process frame so all autoloads are ready.
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_flag_changed_signal()
	_test_relationship_event_hook()
	if _fail == 0:
		print("ALL PASS")
		quit(0)
	else:
		printerr("%d FAILED" % _fail)
		quit(1)

# ── 共用：重置 StoryManager 全域狀態（autoload 跨測試共用，每個測試開頭呼叫）──
func _reset_story(sm: Node) -> void:
	sm.completed_events.clear()
	sm.player_flags.clear()
	sm.npc_relationships.clear()
	sm._relationship_triggers.clear()

# ── 測試用：捕捉訊號 ───────────────────────────────────────────────────────
var _flag_events: Array = []

func _on_flag_changed(key: String, value: Variant) -> void:
	_flag_events.append({"key": key, "value": value})

func _test_flag_changed_signal() -> void:
	print("[StoryManager.flag_changed]")
	# StoryManager is registered as an autoload in project.godot; it lives as a child of root.
	var sm: Node = get_root().get_node("StoryManager")
	_flag_events = []
	sm.flag_changed.connect(_on_flag_changed)
	sm.set_flag("clue_locked_room", true)
	_assert(_flag_events.size() == 1, "set_flag 發出一次 flag_changed")
	_assert(_flag_events[0]["key"] == "clue_locked_room", "訊號帶正確 key")
	_assert(_flag_events[0]["value"] == true, "訊號帶正確 value")
	_assert(sm.get_flag("clue_locked_room", false) == true, "flag 確實寫入")
	sm.flag_changed.disconnect(_on_flag_changed)

var _recorded_events: Array = []

func _on_event_recorded(event_id: String) -> void:
	_recorded_events.append(event_id)

func _test_relationship_event_hook() -> void:
	print("[StoryManager relationship→event]")
	var sm: Node = get_root().get_node("StoryManager")
	_reset_story(sm)
	_recorded_events = []
	sm.event_recorded.connect(_on_event_recorded)
	sm.register_relationship_event("lin_rongchang", 60, "ch1_rongchang_trust_ok")
	# 未達門檻：不觸發
	sm.update_relationship("lin_rongchang", 30)
	_assert(not _recorded_events.has("ch1_rongchang_trust_ok"), "30 < 60 不觸發")
	# 跨過門檻：觸發一次
	sm.update_relationship("lin_rongchang", 40)  # 累積 70
	_assert(_recorded_events.has("ch1_rongchang_trust_ok"), "70 ≥ 60 觸發派生事件")
	# 再加：不重複觸發（record_event 去重）
	var count_before: int = _recorded_events.count("ch1_rongchang_trust_ok")
	sm.update_relationship("lin_rongchang", 10)
	var count_after: int = _recorded_events.count("ch1_rongchang_trust_ok")
	_assert(count_before == count_after, "跨門檻後再加不重複記錄")
	# 重複註冊同一條：不應產生兩條 trigger
	sm.register_relationship_event("lin_rongchang", 60, "ch1_rongchang_trust_ok")
	_assert(sm._relationship_triggers.size() == 1, "重複註冊去重")
	sm.event_recorded.disconnect(_on_event_recorded)
