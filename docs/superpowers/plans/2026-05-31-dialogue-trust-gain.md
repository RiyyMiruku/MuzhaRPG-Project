# 對話信任上升機制（AI 評分）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 NPC 在 AI 對話中依玩家發言由 LLM 評分調整信任值，串接既有 relationship→event hook，使 MQ03/SQ-E 可完成；玩家獲得微妙 ↑/↓ 回饋。

**Architecture:** NPC 回應內嵌隱藏 tag `<trust±N>`（沿用既有 `<think>` 剝除模式）。TrustGate 加評分指令進 system prompt + 兩個純函式解析/剝除 tag；AIClient 在 `_on_query_completed` 解析→clamp→`update_relationship`→發 `trust_changed` 訊號；DialogueUI 收訊號顯示方向提示。零額外 LLM request。

**Tech Stack:** Godot 4.6.1 / GDScript。測試沿用 headless `SceneTree` 模式（`game/src/test/`）。

**Godot 執行檔（不在 PATH）：** `C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe`
跑測試：`& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_trust_gain.gd`

**專案硬規則：** 絕不用 `:=`（Variant 推斷是專案錯誤）；所有變數顯式型別含 `for x: T in`。TAB 縮排。

**測試 harness 慣例：** TrustGate 是純 RefCounted（`class_name TrustGate`），static helper 可直接呼叫、不需 autoload。新測試檔 `extends SceneTree`，`_init()` 直接跑（不需 autoload 時不必 `call_deferred`）。

---

## 參考：既有整合點（已確認）

- `TrustGate.build_system_prompt(profile, trust, flags, chapter_overlay, stage_attitude)` 末段 `parts.append("[對玩家信任度] %d/100" % trust)` 後 `return "\n".join(parts)`（`core/classes/TrustGate.gd:70-72`）。
- `AIClient._on_query_completed`：`<think>` 剝除（`autoload/AIClient.gd:129-138`）→ `filter_forbidden`（:140-142）→ `add_conversation_turn`（:145）。信任解析插在 :142 之後、:145 之前。`_current_npc_id` 在此函式內仍有效。
- `DialogueUI` 已連 `AIClient.response_complete`（`ui/dialogue/DialogueUI.gd:62`）、有 `_on_ai_response_complete`（:206-210）。
- relationship→event hook：`StoryManager.update_relationship` 跨門檻自動 `record_event`（前一 feature 已實作）。

---

## File Structure

| 檔案 | 責任 | 動作 |
|---|---|---|
| `game/src/core/classes/TrustGate.gd` | 加評分指令進 prompt + `parse_trust_delta` / `strip_trust_tag` 純函式 | Modify |
| `game/src/autoload/AIClient.gd` | `_on_query_completed` 串接解析→update_relationship→發訊號；新 signal | Modify |
| `game/src/ui/dialogue/DialogueUI.gd` | 收 `trust_changed` 顯示微妙 ↑/↓ | Modify |
| `game/src/test/test_trust_gain.gd` | headless 測試 parse/strip/prompt | Create |
| `game/src/test/test_trust_gain.gd.uid` | Godot 自動產生（commit 進來） | Create (auto) |

---

## Task 1: TrustGate 解析純函式 + 評分指令

**Files:**
- Modify: `game/src/core/classes/TrustGate.gd`
- Create: `game/src/test/test_trust_gain.gd`

- [ ] **Step 1: 建立測試檔**

Create `game/src/test/test_trust_gain.gd`:

```gdscript
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
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_trust_gain.gd`
Expected: FAIL — `Nonexistent function 'parse_trust_delta'`。

- [ ] **Step 3: 加兩個 static 純函式**

在 `game/src/core/classes/TrustGate.gd` 末端（`resolve_stage_attitude` 之後）新增：

```gdscript
## 從 LLM 回應解析信任 delta。抓最後一個 <trust±N>，clamp 到 -3..3。無 tag 回 0。
static func parse_trust_delta(text: String) -> int:
	var re: RegEx = RegEx.new()
	re.compile("<trust([+-]\\d+)>")
	var matches: Array[RegExMatch] = re.search_all(text)
	if matches.is_empty():
		return 0
	var last: RegExMatch = matches[matches.size() - 1]
	var val: int = last.get_string(1).to_int()
	return clampi(val, -3, 3)

## 移除回應中所有 <trust±N> tag，回傳乾淨內容（前後去空白）。
static func strip_trust_tag(text: String) -> String:
	var re: RegEx = RegEx.new()
	re.compile("<trust[+-]\\d+>")
	return re.sub(text, "", true).strip_edges()
```

- [ ] **Step 4: 加評分指令進 prompt**

在 `build_system_prompt` 的 `parts.append("[對玩家信任度] %d/100" % trust)`（:70）之後、`return`（:72）之前插入：

```gdscript
	# 8. 信任評分指令：要 NPC 在回覆最後輸出隱藏 tag（client 會剝除）
	parts.append(
		"[信任評分] 在你回覆的最後，依玩家這一輪的態度附上一個隱藏標記 <trust±N>"
		+ "（N 為 0 到 3 的整數）。評分標準：玩家溫和有禮、尊重你、展現可信、不過度逼問隱私 → 正值；"
		+ "冒犯、逼問太緊、自稱知道不該知道的事、說出與『南部來打工的表親之子』身分矛盾的話 → 負值；"
		+ "一般寒暄問路給 <trust+0>。多數情況給 0 或 1。例：<trust+1>"
	)
```

- [ ] **Step 5: 跑測試確認通過**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_trust_gain.gd`
Expected: 全 PASS，`ALL PASS`，離開碼 0。

- [ ] **Step 6: Commit**

```bash
git add game/src/core/classes/TrustGate.gd game/src/test/test_trust_gain.gd game/src/test/test_trust_gain.gd.uid
git commit -m "feat(dialogue): trust-tag parsing + scoring rubric in TrustGate

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: AIClient 串接信任解析 + trust_changed 訊號

**Files:**
- Modify: `game/src/autoload/AIClient.gd`

- [ ] **Step 1: 加 signal**

在 `game/src/autoload/AIClient.gd` 的 signals 區（:4-6，`signal server_status_changed` 之後）新增：

```gdscript
## 信任值因對話變動（direction：+1 升 / -1 降；不帶數字，給 UI 微妙提示用）
signal trust_changed(npc_id: String, direction: int)
```

- [ ] **Step 2: 串接解析（在 filter_forbidden 後、add_conversation_turn 前）**

在 `_on_query_completed` 中，`content = TrustGate.filter_forbidden(...)`（:142）那行之後、`StoryManager.add_conversation_turn(...)`（:145）之前插入：

```gdscript
	# 信任評分：解析隱藏 tag → 更新 relationship → 發 UI 訊號 → 從顯示內容剝除
	var trust_delta: int = TrustGate.parse_trust_delta(content)
	content = TrustGate.strip_trust_tag(content)
	if trust_delta != 0:
		StoryManager.update_relationship(_current_npc_id, trust_delta)
		trust_changed.emit(_current_npc_id, signi(trust_delta))
```

注意：`parse_trust_delta` 要在 `strip_trust_tag` 之前呼叫（剝除後就抓不到 tag 了）。`signi()` 回 -1/0/+1。

- [ ] **Step 3: 語法檢查**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --check-only --script res://src/autoload/AIClient.gd`
Expected: 離開碼 0（autoload 相依的 identifier-not-found 警告可忽略，那是 --check-only 單檔限制；只要沒有語法 parse error）。

- [ ] **Step 4: 回歸測試**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_trust_gain.gd`
Expected: 仍 `ALL PASS`（此 task 不改 TrustGate，確認沒弄壞）。

- [ ] **Step 5: Commit**

```bash
git add game/src/autoload/AIClient.gd
git commit -m "feat(dialogue): wire trust-tag parsing into AIClient query completion

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: 整合測試（解析→update_relationship→跨門檻派生事件）

**Files:**
- Modify: `game/src/test/test_trust_gain.gd`

- [ ] **Step 1: 加整合測試**

此測試需 autoload（StoryManager），故改用 deferred 模式。將 `test_trust_gain.gd` 的 `_init()` 改為：

```gdscript
func _init() -> void:
	_test_parse_trust_delta()
	_test_strip_trust_tag()
	_test_prompt_has_rubric()
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
```

並移除原 `_init()` 末端的 `if _fail == 0 ... quit()` 區塊（移到 `_run_deferred`）。新增測試方法：

```gdscript
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
```

- [ ] **Step 2: 跑測試確認通過**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_trust_gain.gd`
Expected: 所有區塊 PASS，`ALL PASS`，離開碼 0。

- [ ] **Step 3: Commit**

```bash
git add game/src/test/test_trust_gain.gd
git commit -m "test(dialogue): trust accumulation crosses threshold to fire derived event

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: DialogueUI 微妙信任提示

**Files:**
- Modify: `game/src/ui/dialogue/DialogueUI.gd`

- [ ] **Step 1: 連訊號**

在 `_ready()` 中，`AIClient.request_failed.connect(_on_ai_request_failed)`（:63）之後新增：

```gdscript
	AIClient.trust_changed.connect(_on_trust_changed)
```

- [ ] **Step 2: 加 handler**

在 AI Response Handlers 區（`_on_ai_request_failed` 之後，:215 後）新增：

```gdscript
## 信任變動的微妙回饋：在對話框尾端附一個小箭頭（不報數字），保留推理空間。
func _on_trust_changed(npc_id: String, direction: int) -> void:
	if npc_id != _current_npc_id:
		return
	var arrow: String = "  ﹙↑﹚" if direction > 0 else "  ﹙↓﹚"
	var col: String = "#7fb37f" if direction > 0 else "#b37f7f"
	_dialogue_text.text += "[color=%s]%s[/color]" % [col, arrow]
```

注意：`_dialogue_text` 是 RichTextLabel（見 :25），需確認 `bbcode_enabled`。若未啟用，改用純文字 `_dialogue_text.text += arrow`。實作時先檢查 .tscn 的 RichTextLabel 設定。

- [ ] **Step 3: 確認 RichTextLabel bbcode 設定**

Read `game/src/ui/dialogue/DialogueUI.tscn`，搜尋 DialogueText 節點是否 `bbcode_enabled = true`。若否，Step 2 的 handler 改為純文字版：

```gdscript
func _on_trust_changed(npc_id: String, direction: int) -> void:
	if npc_id != _current_npc_id:
		return
	_dialogue_text.text += "  ﹙↑﹚" if direction > 0 else "  ﹙↓﹚"
```

- [ ] **Step 4: 語法檢查**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --check-only --script res://src/ui/dialogue/DialogueUI.gd`
Expected: 無語法 parse error（autoload identifier 警告可忽略）。

- [ ] **Step 5: 回歸 + Commit**

Run trust test 確認沒壞：`& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_trust_gain.gd`（ALL PASS）。

```bash
git add game/src/ui/dialogue/DialogueUI.gd
git commit -m "feat(ui): subtle trust-change arrow in dialogue box

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: 手動驗證（編輯器，非 headless）**

開專案、與 NPC AI 對話幾輪，確認：(a) 對話框不再出現 `<trust±N>` 原文；(b) 信任變動時出現小 ↑/↓；(c) 多輪好對話後 journal 的 MQ03「取得林榮昌信任」打勾。

---

## Self-Review 紀錄

- **Spec 覆蓋：** §3 流程→Task 1-4；§4 改動 #1 rubric→Task 1 Step4、#2 解析函式→Task 1 Step3、#3 AIClient 串接→Task 2、#4 trust_changed→Task 2 Step1、#5 UI→Task 4。§5 測試→Task 1/3（parse/strip/prompt/整合）。
- **型別一致：** `parse_trust_delta(text)->int`、`strip_trust_tag(text)->String`、`trust_changed(npc_id, direction)` 在各 task 引用一致。
- **與 spec 一致：** clamp -3..3、無 tag→0、多 tag 取最後、負向允許、微妙提示不報數字。
- **無 placeholder：** 所有步驟含完整程式碼與指令；Task 4 的 bbcode 分支有明確 fallback。
- **待實作確認：** DialogueUI.tscn 的 bbcode_enabled（Task 4 Step3 已含檢查與 fallback）。
