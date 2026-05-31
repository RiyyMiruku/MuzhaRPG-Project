## Headless 測試：UISfx 點擊音 autoload。
## 跑法：godot --headless --path game --script res://src/test/test_ui_sfx.gd
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
	_test_ui_sfx()
	if _fail == 0:
		print("ALL PASS")
		quit(0)
	else:
		printerr("%d FAILED" % _fail)
		quit(1)

func _test_ui_sfx() -> void:
	print("[UISfx]")
	var sfx: Node = get_root().get_node("UISfx")
	_assert(sfx != null, "UISfx autoload 存在")
	_assert(sfx._player != null, "內部 AudioStreamPlayer 已建立")
	_assert(sfx._player.bus == "SFX", "走 SFX bus")
	_assert(sfx._click != null, "點擊音已合成")
	_assert(sfx._click is AudioStreamWAV, "stream 為 AudioStreamWAV")
	_assert(sfx._click.data.size() > 0, "波形資料非空")
	sfx.play_click()
	_assert(true, "play_click() 執行不崩")
