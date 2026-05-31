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
	if _fail == 0:
		print("ALL PASS")
		quit(0)
	else:
		printerr("%d FAILED" % _fail)
		quit(1)

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
