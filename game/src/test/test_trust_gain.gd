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
	_test_prompt_has_player_identity()
	# 需 autoload 的整合測試延後到 autoload 就緒
	call_deferred("_run_deferred")

func _run_deferred() -> void:
	_test_trust_crosses_threshold()
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
	_assert(TrustGate.strip_trust_tag("你好。</trust>") == "你好。", "剝除閉合式 </trust>")
	_assert(TrustGate.strip_trust_tag("第一行<br><br>第二行") == "第一行\n\n第二行", "<br> 轉換行")

func _test_prompt_has_rubric() -> void:
	print("[build_system_prompt 含評分指令]")
	var p: NPCProfile = NPCProfile.new()
	p.system_prompt = "測試人格"
	var prompt: String = TrustGate.build_system_prompt(p, 0, {})
	_assert(prompt.contains("<trust"), "prompt 含 tag 格式說明")
	_assert(prompt.contains("[信任評分]"), "prompt 含評分指令標頭")

func _test_prompt_has_player_identity() -> void:
	# 回歸測試（修復「NPC 把自己身分鏡射給玩家」bug）：
	# 有傳 player_identity 時，prompt 必須含「對話對象」區塊，模型才知道在跟誰說話。
	print("[build_system_prompt 含對話對象區塊]")
	var p: NPCProfile = NPCProfile.new()
	p.system_prompt = "你是一位 72 歲的長者"
	var ident: String = "阿謙,一個年輕後生,不是你本人"
	var prompt: String = TrustGate.build_system_prompt(p, 0, {}, "", "", ident)
	_assert(prompt.contains("[對話對象]"), "有 identity → 含對話對象標頭")
	_assert(prompt.contains(ident), "有 identity → 含注入的玩家身分原文")
	var prompt_empty: String = TrustGate.build_system_prompt(p, 0, {})
	_assert(not prompt_empty.contains("[對話對象]"), "無 identity → 不憑空注入標頭")

func _test_trust_crosses_threshold() -> void:
	print("[信任跨門檻 → 派生事件]")
	var sm: Node = get_root().get_node("StoryManager")
	sm.completed_events.clear()
	sm.player_flags.clear()
	sm.npc_relationships.clear()
	sm._relationship_triggers.clear()
	sm.register_relationship_event("lin_rongchang", 60, "ch1_rongchang_trust_ok")
	# 模擬多輪 +3 對話：解析 + 累加，第 20 輪跨 60
	var total: int = 0
	for i: int in range(20):
		var delta: int = TrustGate.parse_trust_delta("回應 <trust+3>")
		sm.update_relationship("lin_rongchang", delta)
		total += delta
	_assert(sm.npc_relationships.get("lin_rongchang", 0) == 60, "20×3 = 60")
	_assert(sm.completed_events.has("ch1_rongchang_trust_ok"), "跨門檻派生事件已記錄")
