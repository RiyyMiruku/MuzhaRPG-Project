## Headless 測試：信任 tag 解析 / 剝除 / 評分指令注入。
## 跑法：godot --headless --path game --script res://src/test/test_trust_gain.gd
## 全 pass 離開碼 0，任一 fail 離開碼 1。
extends SceneTree

var _fail: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: ", msg)
	else:
		_fail += 1
		printerr("  FAIL: ", msg)

func _init() -> void:
	_test_parse_trust_delta()
	_test_strip_trust_tag()
	_test_prompt_has_rubric()
	if _fail == 0:
		print("ALL PASS")
		quit(0)
	else:
		printerr("%d FAILED" % _fail)
		quit(1)

func _test_parse_trust_delta() -> void:
	print("[parse_trust_delta]")
	_assert(TrustGate.parse_trust_delta("你好啊。<trust+2>") == 2, "正值 +2")
	_assert(TrustGate.parse_trust_delta("哼。<trust-3>") == -3, "負值 -3")
	_assert(TrustGate.parse_trust_delta("<trust+0>") == 0, "零值 +0")
	_assert(TrustGate.parse_trust_delta("沒有標記") == 0, "無 tag → 0")
	_assert(TrustGate.parse_trust_delta("<trust+9>") == 3, "超量上限 clamp 3")
	_assert(TrustGate.parse_trust_delta("<trust-9>") == -3, "超量下限 clamp -3")
	_assert(TrustGate.parse_trust_delta("<trust+1>嗯<trust+2>") == 2, "多 tag 取最後")

func _test_strip_trust_tag() -> void:
	print("[strip_trust_tag]")
	_assert(TrustGate.strip_trust_tag("你好。<trust+2>") == "你好。", "剝除尾端 tag")
	_assert(TrustGate.strip_trust_tag("乾淨內容") == "乾淨內容", "無 tag 原樣")
	_assert(TrustGate.strip_trust_tag("a<trust+1>b<trust-2>c") == "abc", "剝除多個 tag")

func _test_prompt_has_rubric() -> void:
	print("[build_system_prompt 含評分指令]")
	var p: NPCProfile = NPCProfile.new()
	p.system_prompt = "測試人格"
	var prompt: String = TrustGate.build_system_prompt(p, 0, {})
	_assert(prompt.contains("<trust"), "prompt 含 tag 格式說明")
	_assert(prompt.contains("[信任評分]"), "prompt 含評分指令標頭")
