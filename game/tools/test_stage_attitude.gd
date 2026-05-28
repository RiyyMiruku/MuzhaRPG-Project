## Headless 測試：stage 推導 + 態度繼承解析。
## 跑法：godot --headless --path game --script res://tools/test_stage_attitude.gd
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
	_test_resolve_stage()
	_test_inherit()
	_test_passthrough_compat()
	if _fail == 0:
		print("ALL PASS")
		quit(0)
	else:
		printerr("%d FAILED" % _fail)
		quit(1)

func _make_rules() -> Array:
	return [
		{"stage_id": "s1_newcomer", "require_any": []},
		{"stage_id": "s2_working", "require_any": ["started_pharmacy_work"]},
		{"stage_id": "s3_secret", "require_any": ["clue_locked_room", "saw_ama_incense"]},
		{"stage_id": "s4_finale", "require_any": ["found_ronghua_relic", "ending_finale_active"]},
	]

func _test_resolve_stage() -> void:
	print("[resolve_stage]")
	var cfg: ChapterConfig = ChapterConfig.new()
	cfg.stage_rules = _make_rules()
	_assert(cfg.resolve_stage({}) == "s1_newcomer", "空 flags → s1 fallback")
	_assert(cfg.resolve_stage({"started_pharmacy_work": true}) == "s2_working", "打工 → s2")
	_assert(cfg.resolve_stage({"saw_ama_incense": true}) == "s3_secret", "燒香線索 → s3")
	_assert(
		cfg.resolve_stage({"started_pharmacy_work": true, "ending_finale_active": true}) == "s4_finale",
		"多 flag → 取最高 s4"
	)
	var empty_cfg: ChapterConfig = ChapterConfig.new()
	_assert(empty_cfg.resolve_stage({"x": true}) == "", "無 stage_rules → 空字串")

func _test_inherit() -> void:
	print("[resolve_stage_attitude 繼承]")
	var order: Array = ["s1_newcomer", "s2_working", "s3_secret", "s4_finale"]
	var p: NPCProfile = NPCProfile.new()
	p.stage_attitudes = {"s1_newcomer": "A1", "s3_secret": "A3"}
	_assert(TrustGate.resolve_stage_attitude(p, "s1_newcomer", order) == "A1", "s1 → A1")
	_assert(TrustGate.resolve_stage_attitude(p, "s2_working", order) == "A1", "s2 未填 → 繼承 A1")
	_assert(TrustGate.resolve_stage_attitude(p, "s3_secret", order) == "A3", "s3 → A3")
	_assert(TrustGate.resolve_stage_attitude(p, "s4_finale", order) == "A3", "s4 未填 → 繼承 A3")

func _test_passthrough_compat() -> void:
	print("[向下相容]")
	var order: Array = ["s1_newcomer", "s2_working"]
	var p: NPCProfile = NPCProfile.new()  # 空 stage_attitudes
	_assert(TrustGate.resolve_stage_attitude(p, "s1_newcomer", order) == "", "無 stage_attitudes → 空字串")
	var base: NPCConfig = NPCConfig.new()  # 非 NPCProfile
	_assert(TrustGate.resolve_stage_attitude(base, "s1_newcomer", order) == "", "NPCConfig → 空字串")
	# build_system_prompt 空 stage_attitude 不注入標頭
	var prompt: String = TrustGate.build_system_prompt(p, 0, {}, "", "")
	_assert(not prompt.contains("[現階段態度]"), "空片段不注入標頭")
	var prompt2: String = TrustGate.build_system_prompt(p, 0, {}, "", "他在試探你")
	_assert(prompt2.contains("[現階段態度] 他在試探你"), "有片段則注入標頭")
