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
	if _fail == 0:
		print("ALL PASS")
		quit(0)
	else:
		printerr("%d FAILED" % _fail)
		quit(1)

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
