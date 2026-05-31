## Headless 測試：SaveManager 存檔/slot 查詢/載入順序/autosave 閘。
## 跑法：godot --headless --path game --script res://src/test/test_save_system.gd
extends SceneTree

var _fail: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: ", msg)
	else:
		_fail += 1
		printerr("  FAIL: ", msg)

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_save_roundtrip()
	_test_apply_order()
	_test_load_parse()
	if _fail == 0:
		print("ALL PASS")
		quit(0)
	else:
		printerr("%d FAILED" % _fail)
		quit(1)

func _test_apply_order() -> void:
	print("[apply_save_data 載入順序]")
	var save: Node = get_root().get_node("SaveManager")
	var sm: Node = get_root().get_node("StoryManager")
	var qm: Node = get_root().get_node("QuestManager")
	_reset_story(sm)
	qm._active_quests.clear()
	qm._completed_quests.clear()
	var data: Dictionary = {
		"story": {
			"completed_events": ["ch1_first_travel_done", "ch1_started_living_in_pharmacy"],
			"player_flags": {"started_pharmacy_work": true},
			"npc_relationships": {"lin_rongchang": 60},
			"unlocked_zones": ["zone_apartment_muzha"],
			"conversation_histories": {},
			"current_zone": "zone_pharmacy",
			"game_time_hours": 14.0,
		},
		"chapter": {"current_chapter_id": "ch01_arrival"},
		"quests": {"active_quests": [], "completed_quests": []},
		"era": {"current_era": "1983"},
		"time_played_sec": 123.0,
	}
	save.apply_save_data(data)
	_assert(sm.player_flags.get("started_pharmacy_work", false) == true, "flags 還原")
	_assert(sm.completed_events.has("ch1_started_living_in_pharmacy"), "events 還原")
	_assert(sm.npc_relationships.get("lin_rongchang", 0) == 60, "信任值還原")
	var cm: Node = get_root().get_node("ChapterManager")
	_assert(cm.current() != null and cm.current().chapter_id == "ch01_arrival", "章節還原")
	_assert(sm._relationship_triggers.size() > 0, "章節 re-register 補回信任 trigger")
	var gm: Node = get_root().get_node("GameManager")
	_assert(gm.get_time_played_sec() == 123.0, "遊玩時間還原")


func _test_load_parse() -> void:
	print("[load 讀檔解析]")
	var save: Node = get_root().get_node("SaveManager")
	_assert(save.read_slot_data(98).is_empty(), "不存在 slot 回空 dict")
	var sm: Node = get_root().get_node("StoryManager")
	_reset_story(sm)
	sm.set_flag("rk", true)
	save.save_to_slot(97)
	var d: Dictionary = save.read_slot_data(97)
	_assert(not d.is_empty(), "讀回非空")
	_assert(d.get("story", {}).get("player_flags", {}).get("rk", false) == true, "讀回內容正確")
	DirAccess.remove_absolute(save._slot_path(97))

func _reset_story(sm: Node) -> void:
	sm.completed_events.clear()
	sm.player_flags.clear()
	sm.npc_relationships.clear()
	sm._relationship_triggers.clear()
	sm.unlocked_zones.assign(["zone_apartment_muzha"])
	sm.conversation_histories.clear()

func _test_save_roundtrip() -> void:
	print("[save round-trip]")
	var save: Node = get_root().get_node("SaveManager")
	var sm: Node = get_root().get_node("StoryManager")
	_reset_story(sm)
	sm.set_flag("test_flag_x", true)
	sm.record_event("evt_roundtrip")
	sm.current_zone = "zone_pharmacy"
	var ok: bool = save.save_to_slot(99)
	_assert(ok, "save_to_slot 成功")
	_assert(save.has_slot(99), "存檔檔案存在")
	var info: Dictionary = save.get_slot_info(99)
	_assert(info.get("exists", false) == true, "get_slot_info exists")
	DirAccess.remove_absolute(save._slot_path(99))
	_assert(not save.has_slot(99), "測試檔已刪除")
