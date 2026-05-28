# NPC 劇情階段態度系統 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 依劇情階段，把每個 NPC 對玩家的態度片段注入 LLM system prompt，讓第一章 NPC 回答隨進度演進而不突兀。

**Architecture:** StoryManager 由當前章節的 `stage_rules`（資料驅動，存於 ChapterConfig）+ player_flags 推導 `current_stage`；每個 NPCProfile 的 `stage_attitudes` 字典存各階段中文片段（未填則往前繼承）；AIClient 取出對應片段傳給 TrustGate，注入 `[現階段態度]` 標頭。

**Tech Stack:** GDScript (Godot 4)、Resource `.tres`、headless GDScript 測試腳本。

設計來源：`docs/superpowers/specs/2026-05-29-npc-stage-attitude-design.md`

**測試說明：** 專案沒有 GUT 等 GDScript 測試框架（`tests/` 是 pipeline 的 Python pytest）。本 plan 用獨立 headless 腳本 `game/tools/test_stage_attitude.gd` 驗證純函式邏輯，跑法：`godot --headless --path game --script res://tools/test_stage_attitude.gd`（離開碼 0 = pass）。

---

## File Structure

- `game/src/core/classes/NPCProfile.gd` — 新增 `stage_attitudes: Dictionary` 欄位
- `game/src/core/classes/ChapterConfig.gd` — 新增 `stage_rules: Array` 欄位
- `game/src/autoload/StoryManager.gd` — 新增 `get_current_stage()`、`build_ai_context` 加 `story_stage`
- `game/src/autoload/ChapterManager.gd` — 新增 `get_current_stage_rules()` 轉發
- `game/src/core/classes/TrustGate.gd` — `build_system_prompt` 加 `stage_attitude` 參數 + `resolve_stage_attitude()` helper
- `game/src/autoload/AIClient.gd` — `_build_chat_payload` 取片段並傳入
- `game/src/chapters/chapter_01_arrival/chapter.tres` — 填 `stage_rules`
- `game/src/chapters/chapter_01_arrival/npcs/*.tres`（7 個）— 填 `stage_attitudes`
- `game/tools/test_stage_attitude.gd` — headless 測試腳本（新建）

---

## Task 1: NPCProfile 新增 stage_attitudes 欄位

**Files:**
- Modify: `game/src/core/classes/NPCProfile.gd`

- [ ] **Step 1: 在 known_facts 之後新增欄位**

在 `NPCProfile.gd` 的 `known_facts` 宣告（`@export var known_facts...`）之後、`personality_voice` 之前插入：

```gdscript
## 各劇情階段的態度片段：{ stage_id: "2-4 句中文，描述此階段你對阿謙的態度與分寸" }
## 未填的 stage 由 TrustGate.resolve_stage_attitude() 依 stage_rules 順序往前繼承最近一格。
## 路人 NPC 留空 = 完全不注入，向下相容。
@export var stage_attitudes: Dictionary = {}
```

- [ ] **Step 2: 開 Godot editor 確認無 parse error**

Run: `godot --headless --path game --quit 2>&1 | grep -i "error\|SCRIPT" | head`
Expected: 無 NPCProfile.gd 相關 error（既有 warning 可忽略）

- [ ] **Step 3: Commit**

```bash
git add game/src/core/classes/NPCProfile.gd
git commit -m "feat(npc): add stage_attitudes field to NPCProfile"
```

---

## Task 2: ChapterConfig 新增 stage_rules 欄位

**Files:**
- Modify: `game/src/core/classes/ChapterConfig.gd`

- [ ] **Step 1: 在 completion_flags 之後新增欄位**

在 `ChapterConfig.gd` 的 `completion_flags` 宣告之後插入：

```gdscript
# ── 劇情階段 ──────────────────────────────────────────────────────────────
## 劇情階段規則，依序由前往後檢查；命中（require_any 任一 flag 為真）的最後一筆即當前階段。
## 第一筆視為 fallback（require_any 建議留空 []）。
## 格式：[{ "stage_id": "s1_newcomer", "require_any": [] },
##        { "stage_id": "s2_working", "require_any": ["started_pharmacy_work"] }, ...]
@export var stage_rules: Array = []
```

- [ ] **Step 2: 新增 helper 方法**

在 `ChapterConfig.gd` 末尾的工具方法區（`includes_zone` 之後）新增：

```gdscript
## 依 player_flags 推導當前 stage_id。無 stage_rules 時回空字串。
func resolve_stage(player_flags: Dictionary) -> String:
	var result: String = ""
	for rule: Dictionary in stage_rules:
		var sid: String = rule.get("stage_id", "")
		if result.is_empty():
			result = sid   # 第一筆 = fallback
		var req: Array = rule.get("require_any", [])
		for flag: String in req:
			if player_flags.get(flag, false):
				result = sid
				break
	return result
```

- [ ] **Step 3: 確認無 parse error**

Run: `godot --headless --path game --quit 2>&1 | grep -i "error" | head`
Expected: 無 ChapterConfig.gd 相關 error

- [ ] **Step 4: Commit**

```bash
git add game/src/core/classes/ChapterConfig.gd
git commit -m "feat(chapter): add data-driven stage_rules + resolve_stage to ChapterConfig"
```

---

## Task 3: TrustGate 加入 stage_attitude 注入 + 繼承解析

**Files:**
- Modify: `game/src/core/classes/TrustGate.gd`

- [ ] **Step 1: build_system_prompt 加參數**

把 `build_system_prompt` 的簽名（含現有 `chapter_overlay` 預設參數）改為加上 `stage_attitude`：

```gdscript
static func build_system_prompt(
	profile: NPCConfig,
	trust: int,
	flags: Dictionary,
	chapter_overlay: String = "",
	stage_attitude: String = ""
) -> String:
```

- [ ] **Step 2: 在語氣之後注入態度**

在 `# 3. 講話風格`（personality_voice append）那段之後、`# 4. 信任值決定的 allowed topics` 之前插入：

```gdscript
		# 3.5 現階段劇情態度
		if not stage_attitude.is_empty():
			parts.append("[現階段態度] " + stage_attitude)
```

注意：此段在 `if profile is NPCProfile:` 區塊**內**（personality_voice 同層級）。

- [ ] **Step 3: 新增繼承解析 helper**

在 `TrustGate.gd` 末尾（`filter_forbidden` 之後）新增。此函式依 stage_rules 順序，從目標 stage 往前找第一個在 `stage_attitudes` 有填的片段：

```gdscript
## 解析 NPC 在指定 stage 的態度片段，含「往前繼承」：
## 若 current_stage 沒填，沿 stage_order 往前找最近一個有填的 stage。
## stage_order 為 stage_id 由前到後的陣列（即 ChapterConfig.stage_rules 的 stage_id 序）。
## 找不到任何片段回空字串。
static func resolve_stage_attitude(
	profile: NPCConfig,
	current_stage: String,
	stage_order: Array
) -> String:
	if not (profile is NPCProfile):
		return ""
	var p: NPCProfile = profile as NPCProfile
	if p.stage_attitudes.is_empty() or current_stage.is_empty():
		return ""
	var idx: int = stage_order.find(current_stage)
	if idx == -1:
		# stage 不在 order 中，直接查當格
		return str(p.stage_attitudes.get(current_stage, ""))
	for i in range(idx, -1, -1):
		var sid: String = str(stage_order[i])
		if p.stage_attitudes.has(sid):
			return str(p.stage_attitudes[sid])
	return ""
```

- [ ] **Step 4: 確認無 parse error**

Run: `godot --headless --path game --quit 2>&1 | grep -i "error" | head`
Expected: 無 TrustGate.gd 相關 error

- [ ] **Step 5: Commit**

```bash
git add game/src/core/classes/TrustGate.gd
git commit -m "feat(trustgate): inject stage attitude with backward inheritance"
```

---

## Task 4: ChapterManager 轉發 stage 規則

**Files:**
- Modify: `game/src/autoload/ChapterManager.gd`

- [ ] **Step 1: 新增轉發方法**

在 `ChapterManager.gd` 的「公開 API」區，`get_npc_overlay` 之後新增：

```gdscript
## 當前章節的 stage_rules（給 StoryManager 推導 current_stage）。無章節回空陣列。
func get_current_stage_rules() -> Array:
	if _current == null:
		return []
	return _current.stage_rules

## 當前章節的 stage_id 順序（給 TrustGate 做繼承解析）。
func get_current_stage_order() -> Array:
	var order: Array = []
	if _current == null:
		return order
	for rule: Dictionary in _current.stage_rules:
		order.append(rule.get("stage_id", ""))
	return order
```

- [ ] **Step 2: 確認無 parse error**

Run: `godot --headless --path game --quit 2>&1 | grep -i "error" | head`
Expected: 無 ChapterManager.gd 相關 error

- [ ] **Step 3: Commit**

```bash
git add game/src/autoload/ChapterManager.gd
git commit -m "feat(chapter): expose stage_rules + stage_order from ChapterManager"
```

---

## Task 5: StoryManager 推導 current_stage + context 加 key

**Files:**
- Modify: `game/src/autoload/StoryManager.gd`

- [ ] **Step 1: 新增 get_current_stage**

在 `StoryManager.gd` 的 `build_ai_context` 之前（或「Context Builder」區內）新增：

```gdscript
## 依當前章節 stage_rules + player_flags 推導劇情階段 id。無章節/無規則回空字串。
func get_current_stage() -> String:
	var current: ChapterConfig = ChapterManager.current()
	if current == null:
		return ""
	return current.resolve_stage(player_flags)
```

- [ ] **Step 2: build_ai_context 加 story_stage**

在 `build_ai_context` 回傳的 Dictionary 中，於 `"chapter_overlay"` 那一行之後加入：

```gdscript
		"story_stage": get_current_stage(),
		"stage_order": ChapterManager.get_current_stage_order(),
```

- [ ] **Step 3: 確認無 parse error**

Run: `godot --headless --path game --quit 2>&1 | grep -i "error" | head`
Expected: 無 StoryManager.gd 相關 error

- [ ] **Step 4: Commit**

```bash
git add game/src/autoload/StoryManager.gd
git commit -m "feat(story): derive current_stage and expose via ai_context"
```

---

## Task 6: AIClient 取片段並傳入 TrustGate

**Files:**
- Modify: `game/src/autoload/AIClient.gd:170-179`

- [ ] **Step 1: 在 _build_chat_payload 解析片段並傳入**

把 `_build_chat_payload` 開頭呼叫 `TrustGate.build_system_prompt(...)` 的那段，改為先解析 stage_attitude 再傳入：

```gdscript
	# 解析此 NPC 在當前劇情階段的態度片段（含往前繼承）
	var stage_attitude: String = TrustGate.resolve_stage_attitude(
		npc_config as NPCConfig,
		str(context.get("story_stage", "")),
		context.get("stage_order", [])
	)
	# 用 TrustGate 組裝核心 system prompt（人格 + 章節 overlay + 階段態度 + 信任值門檻）
	var system_content: String = TrustGate.build_system_prompt(
		npc_config as NPCConfig,
		int(context.get("relationship", 0)),
		context.get("player_flags", {}),
		context.get("chapter_overlay", ""),
		stage_attitude
	)
```

- [ ] **Step 2: 確認無 parse error**

Run: `godot --headless --path game --quit 2>&1 | grep -i "error" | head`
Expected: 無 AIClient.gd 相關 error

- [ ] **Step 3: Commit**

```bash
git add game/src/autoload/AIClient.gd
git commit -m "feat(ai): pass stage attitude into NPC system prompt"
```

---

## Task 7: Headless 測試腳本驗證純邏輯

**Files:**
- Create: `game/tools/test_stage_attitude.gd`

- [ ] **Step 1: 寫測試腳本**

```gdscript
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
```

- [ ] **Step 2: 跑測試確認全 pass**

Run: `godot --headless --path game --script res://tools/test_stage_attitude.gd`
Expected: 結尾印 `ALL PASS`，離開碼 0

- [ ] **Step 3: Commit**

```bash
git add game/tools/test_stage_attitude.gd
git commit -m "test(npc): headless tests for stage resolution + attitude inheritance"
```

---

## Task 8: 第一章 chapter.tres 填入 stage_rules

**Files:**
- Modify: `game/src/chapters/chapter_01_arrival/chapter.tres`

- [ ] **Step 1: 在 completion_flags 行之後加入 stage_rules**

在 `chapter.tres` 的 `[resource]` 區，`completion_flags = [...]` 之後插入：

```
stage_rules = [{
"stage_id": "s1_newcomer",
"require_any": []
}, {
"stage_id": "s2_working",
"require_any": ["started_pharmacy_work"]
}, {
"stage_id": "s3_secret",
"require_any": ["clue_locked_room", "saw_ama_incense"]
}, {
"stage_id": "s4_finale",
"require_any": ["found_ronghua_relic", "ending_finale_active"]
}]
```

- [ ] **Step 2: 確認載入無 error**

Run: `godot --headless --path game --quit 2>&1 | grep -i "chapter\|error" | head`
Expected: ChapterManager 正常 load 1 chapter，無 parse error

- [ ] **Step 3: Commit**

```bash
git add game/src/chapters/chapter_01_arrival/chapter.tres
git commit -m "feat(ch01): define four story stages via stage_rules"
```

---

## Task 9: 填寫 7 個 NPC 的 stage_attitudes

依設計 §3 矩陣，逐格寫完整中文片段（2-4 句）。每個 NPC 改其 `.tres`，在 `known_facts = ...` 區塊之後、`personality_voice` 之前插入 `stage_attitudes = {...}`。

**Files:**
- Modify: `game/src/chapters/chapter_01_arrival/npcs/lin_rongchang.tres`
- Modify: `game/src/chapters/chapter_01_arrival/npcs/lin_ama.tres`
- Modify: `game/src/chapters/chapter_01_arrival/npcs/lin_xiaowei.tres`
- Modify: `game/src/chapters/chapter_01_arrival/npcs/chen_xiuqin.tres`
- Modify: `game/src/chapters/chapter_01_arrival/npcs/a_tao_yi.tres`
- Modify: `game/src/chapters/chapter_01_arrival/npcs/lao_zhou.tres`
- Modify: `game/src/chapters/chapter_01_arrival/npcs/lawyer_muzha.tres`

- [ ] **Step 1: 林榮昌**

```
stage_attitudes = {
"s1_newcomer": "這個阿謙是朋友介紹來打工的,你半信半疑但藥行缺人手就先留他。語帶試探、觀察他做事的樣子,不主動聊家裡的事。",
"s2_working": "他做事還算牢靠,你開始認可這個員工,願意閒聊配藥、市場的事,偶爾應幾句。但講到家裡、後院,還是淡淡帶過。",
"s3_secret": "你發現他在打探後院那間房、塗黑的全家福。明顯閃避、語氣變沉,會說『那不關你的事』『做你的事就好』,心裡警戒起來。",
"s4_finale": "通關之夜。他拿出弟弟的遺物,你壓了十年的情緒終於鬆動。沉默很久、聲音低,被一步步引導著走向那個你從不說出口的名字。"
}
```

- [ ] **Step 2: 林阿嬤**

```
stage_attitudes = {
"s1_newcomer": "一個來路不明的外人住進家裡,你不歡迎。話極短、態度冷硬,能不理就不理,把他當外人看。",
"s2_working": "他還算勤快,你勉強容忍,會使喚他做點雜事跑腿。但絕不交心,提到家裡的事一律閉口。",
"s3_secret": "他碰到你每年燒香的事、問起不該問的。你尖銳警告、語氣冷到結冰:『有些事問了對你沒好處。』把疼愛藏成最硬的禁令。",
"s4_finale": "燒香那夜。你看著這個外人,心防出現裂縫,話裡第一次透出一點哀傷與疲憊,像是終於有人願意聽那個被全家抹掉的人。"
}
```

- [ ] **Step 3: 林小威（16 歲堂叔）**

```
stage_attitudes = {
"s1_newcomer": "家裡來了個新面孔,你很好奇,想找他聊台北、聊外面的世界,把他當逃離藥行生活的出口。",
"s2_working": "你跟阿謙很快混熟,把他當盟友,會抱怨爸爸、抱怨被逼繼承藥行,什麼都跟他講。",
"s3_secret": "你也對『家裡那個沒人提的叔叔』充滿好奇,願意跟阿謙一起偷查,但你其實什麼都問不到。",
"s4_finale": "你隱約感覺到家裡有大事要被揭開,既興奮又不安,在一旁觀望著大人們的情緒。"
}
```

- [ ] **Step 4: 陳秀琴**

```
stage_attitudes = {
"s1_newcomer": "你對這個新員工比丈夫溫和,願意跟他聊家常、問他吃住,態度親切但保持分寸。",
"s2_working": "你把阿謙當半個家人,關心他三餐、住得習不習慣,會笑著說藥行的日常和丈夫的個性。",
"s3_secret": "他問起小叔的事,你輕輕帶過:『我嫁進來就沒這個人了』,不是冷漠,是真的不清楚也不想多碰。",
"s4_finale": "你看得到丈夫那道沒癒合的傷口被掀開,心疼卻不被允許靠近,只能在旁邊默默看著。"
}
```

- [ ] **Step 5: 阿桃姨（菜攤）**

```
stage_attitudes = {
"s1_newcomer": "市場新來的年輕人,你愛聊八卦,但講到林家的事特別謹慎,點到為止。",
"s2_working": "跟阿謙漸漸熟了,願意講些市場舊事、誰家誰家的往事,氣氛輕鬆。",
"s3_secret": "他問到 1976 年的事。你跟林榮華從小一起長大,知道全貌,但要信任夠才肯鬆口一點點片段。",
"s4_finale": "你知道真相快被揭開了,看著阿謙,像在掂量該不該由你來說出那段往事。"
}
```

- [ ] **Step 6: 老周（現代耆老）**

```
stage_attitudes = {
"s1_newcomer": "市場入口擺龍門陣的耆老。生人來打聽,你繞圈子、先打量對方,不輕易給準話。",
"s2_working": "願意跟阿謙講藥行的歷史、林家的舊事,但總是留一手,話說一半。",
"s3_secret": "他問得越來越深。你暗示『有些事不該主動講』,記得什麼、忘記什麼,你自己有分寸。",
"s4_finale": "你默認阿謙已經知道得差不多了,話點到為止,用一句感慨收尾。"
}
```

- [ ] **Step 7: 律師（現代,劇情關聯低,四段近中性）**

```
stage_attitudes = {
"s1_newcomer": "你是承辦繼承案的老律師,公事公辦,交付文件、說明繼承流程,態度professional而中性。",
"s4_finale": "繼承案早已交接完成,你維持一貫的中性professional態度,有問必答但不涉私事。"
}
```
（律師只填 s1、s4;s2/s3 由繼承機制 fallback 到 s1。）

- [ ] **Step 8: 載入確認 + 跑 headless 測試**

Run: `godot --headless --path game --quit 2>&1 | grep -i "error" | head`
Expected: 7 個 .tres 都無 parse error
Run: `godot --headless --path game --script res://tools/test_stage_attitude.gd`
Expected: `ALL PASS`

- [ ] **Step 9: Commit**

```bash
git add game/src/chapters/chapter_01_arrival/npcs/
git commit -m "feat(ch01): author per-NPC stage attitudes for all 7 characters"
```

---

## Task 10: 手動驗證（in-game）

**Files:** 無（手動測試）

- [ ] **Step 1: 確認 started_pharmacy_work flag 有觸發點**

Run: `grep -rn "started_pharmacy_work" game/src/`
Expected: 若無結果 → s2 永遠進不去。需在打工教學關卡的觸發處（如某 beat / event）加 `StoryManager.set_flag("started_pharmacy_work", true)`。若打工教學尚未實作,在 plan 執行後回報使用者，由其決定暫時用哪個既有 event 代替。

- [ ] **Step 2: 啟動遊戲 + llama-server,與林榮昌對話**

啟動 `llm_engine/start_server.ps1`,進遊戲在 s1 階段跟林榮昌對話,觀察語氣是否「試探、保留」。
用 console / debug 設 `StoryManager.set_flag("saw_ama_incense", true)` 進 s3,再對話確認態度轉「閃避、警戒」。
Expected: 不同階段態度明顯不同,且 LLM 不提前洩漏禁忌詞（TrustGate.filter_forbidden 仍生效）。

- [ ] **Step 3: 回報結果**

把 s1 vs s3 的實際回答貼給使用者比對。若仍突兀,微調片段文字（非結構問題）。

---

## Self-Review Notes

- **Spec §1 四階段** → Task 8 stage_rules ✓
- **Spec §2(a) NPCProfile 欄位** → Task 1 ✓；**(b) ChapterConfig stage_rules** → Task 2 ✓；**(c) context key** → Task 5 ✓；**(d) TrustGate 參數+注入** → Task 3 ✓
- **Spec §3 態度矩陣** → Task 9（7 NPC 完整片段）✓
- **Spec §4 測試**（注入位置 / 繼承 / get_current_stage / 向下相容）→ Task 7 headless 測試全涵蓋 ✓
- **已知 flag 缺口**：`started_pharmacy_work` 不存在 → Task 10 Step 1 明確處理。
- **`.tres` 屬性順序注意**：`lin_ama.tres` 用 uid 格式且屬性順序與其他檔不同（`system_prompt` 在尾段）。Godot 依 key 解析、順序無關，所以 Task 9「在 known_facts 之後」只是建議位置，`stage_attitudes` 插在 `[resource]` 區塊內任何位置都可。
