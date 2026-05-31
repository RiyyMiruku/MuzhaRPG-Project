## Headless 測試：MusicPlayer 淡出 / 淡入（劇情穿越轉場用）。
## 跑法：godot --headless --path game --script res://src/test/test_music_fade.gd
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
	call_deferred("_run_tests")

func _run_tests() -> void:
	await _test_fade_out_then_in()
	if _fail == 0:
		print("ALL PASS")
		quit(0)
	else:
		printerr("%d FAILED" % _fail)
		quit(1)

func _test_fade_out_then_in() -> void:
	print("[MusicPlayer fade_out / fade_in]")
	var mp: Node = get_root().get_node("MusicPlayer")
	var player: AudioStreamPlayer = mp._player
	player.volume_db = 0.0

	# 淡出：0.1s 後 volume 應明顯下降（趨近 FADE_MIN_DB）
	mp.fade_out(0.1)
	await create_timer(0.25).timeout
	_assert(player.volume_db <= -20.0, "fade_out 後音量明顯下降 (%.1f dB)" % player.volume_db)

	# 淡入：0.1s 後 volume 應回到接近 0
	mp.fade_in(0.1)
	await create_timer(0.25).timeout
	_assert(player.volume_db >= -1.0, "fade_in 後音量回到接近 0 (%.1f dB)" % player.volume_db)

	# 連續呼叫 fade_out 不應殘留舊 tween 打架（kill 舊的）
	mp.fade_out(0.1)
	mp.fade_out(0.1)
	await create_timer(0.25).timeout
	_assert(player.volume_db <= -20.0, "重複 fade_out 仍正確淡出 (%.1f dB)" % player.volume_db)
	mp.fade_in(0.05)
	await create_timer(0.15).timeout
