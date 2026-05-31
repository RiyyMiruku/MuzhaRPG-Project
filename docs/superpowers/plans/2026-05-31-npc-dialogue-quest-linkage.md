# 對話系統 × 任務系統關聯 + 第一章任務列表 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓任務系統成為「劇情事件真相的玩家可見投影」——任務透過 objectives 掛接既有 beat/cutscene 事件與 flag，自動開始/逐項打勾/完成，為開放探索的玩家提供主線麵包屑；同時讓信任值能派生事件供任務使用。

**Architecture:** `StoryManager.flags` / `completed_events` 是唯一真相（SSOT），由 beat、cutscene、探索觸發寫入。stage 系統與 quest 系統是這份真相的兩個獨立投影，彼此不互寫。本次新增：(1) `StoryManager` 加 `flag_changed` 訊號 + 通用「relationship 跨門檻→派生事件」掛鉤；(2) `QuestData` 加 `objectives` 欄位 + 純函式判定；(3) `QuestManager` 改用 objectives 判定、監聽 flag 變動、掃描章節 quests 資料夾；(4) 第一章 6 主線 + 2 支線任務 `.tres`；(5) Journal 顯示 objectives 逐項打勾。

**Tech Stack:** Godot 4.6.1 / GDScript（autoload 單例 + Resource `.tres`）。測試採用既有 headless `SceneTree` 腳本模式（見 `game/tools/test_stage_attitude.gd`）。

**Godot 執行檔（不在 PATH）：** `C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe`
跑測試：`& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_quest_objectives.gd`

**測試 Harness 慣例（Task 1 實作後確立，覆蓋下方各 task 內 `load(...).new()` 寫法）：**
StoryManager / QuestManager 是 autoload，**不能**用 `load(...).new()` 獨立實例化（會因相依其他 autoload 而失敗）。測試一律：
1. `extends SceneTree`，在 `_initialize()` 內 `call_deferred("_run_tests")`（等 autoload 就緒），`_run_tests()` 跑各測試後 `quit(0/1)`。
2. 取真實 autoload：`var sm: Node = get_root().get_node("StoryManager")`、`var qm: Node = get_root().get_node("QuestManager")`。
3. 因 autoload 全域共用，**每個測試函式開頭重置狀態**，用 helper：
```gdscript
func _reset_story(sm: Node) -> void:
	sm.completed_events.clear()
	sm.player_flags.clear()
	sm.npc_relationships.clear()
	sm._relationship_triggers.clear()  # Task 2 之後存在
```
4. QuestData 是純 Resource，static helper 測試可直接 `load("res://src/core/classes/QuestData.gd")` 後呼叫，**不需** autoload（Task 3 沿用原寫法即可）。
5. 連訊號後記得在測試末 `disconnect`，避免跨測試殘留。

下方各 task 的測試碼若寫 `load("res://src/autoload/...").new()`，一律改成「取真實 autoload + `_reset_story`」。

**專案硬規則：** `project.godot` 把 `:=` Variant 推斷視為錯誤——所有變數一律顯式型別（含 `for x: T in ...`）。

---

## 參考：已確認的既有事件 / flag（實作時直接掛接，無需新增）

| 來源 beat/cutscene | set_flag | emit event |
|---|---|---|
| `ch1_open_iron_door.tres` (cutscene) | `saw_blacked_photo`, `first_time_traveled` | `ch1_first_travel_done` |
| `ch1_meet_lin_rongchang.tres` (beat) | `started_pharmacy_work`, … | `ch1_started_living_in_pharmacy` |
| `ch1_xiaowei_curiosity.tres` (beat) | `clue_locked_room`, … | `ch1_xiaowei_talked` |
| `ch1_ama_incense.tres` (cutscene) | `saw_ama_incense` | `ch1_saw_ama_incense` |
| `ch1_lawyer_documents.tres` (beat) | `clue_inheritance_document`, … | `ch1_lawyer_visited` |
| `ch1_ama_trust_key.tres` (beat) | `got_locked_room_key` | `ch1_got_key` |
| `ch1_enter_locked_room.tres` (cutscene) | `found_ronghua_relic` | `ch1_found_relic` |
| `ch1_show_relic_to_rongchang.tres` (beat) | `finale_night_ready` | `ch1_relic_shown` |
| `ch1_finale_say_name.tres` (beat) | — | `ch1_finale_said_brother_name` |
| `ch1_meet_lao_zhou.tres` (beat) | `lao_zhou_patient`/`lao_zhou_pressed` | `ch1_met_lao_zhou` |

**唯一需要新增的事件**（由本計畫的 relationship→event 掛鉤產生）：
- `ch1_rongchang_trust_ok`（lin_rongchang 信任 ≥ 60）
- `ch1_atao_truth`（a_tao_yi 信任 ≥ 50，支線）

---

## File Structure

| 檔案 | 責任 | 動作 |
|---|---|---|
| `game/src/autoload/StoryManager.gd` | 加 `flag_changed` 訊號、relationship→event 通用掛鉤 | Modify |
| `game/src/core/classes/QuestData.gd` | 加 `objectives` 欄位 + 純函式判定 helper | Modify |
| `game/src/autoload/QuestManager.gd` | objectives 判定完成、監聽 flag、掃章節資料夾、提供逐項狀態、測試注入 seam | Modify |
| `game/src/chapters/chapter_01_arrival/events.gd` | 註冊兩個信任門檻→事件 | Modify |
| `game/src/chapters/chapter_01_arrival/quests/*.tres` | 第一章 6 主線 + 2 支線任務資料 | Create ×8 |
| `game/src/ui/menus/QuestJournal.gd` | active 任務下逐項顯示 objectives（打勾/未完成） | Modify |
| `game/src/test/test_quest_objectives.gd` | headless 單元 + 整合測試 | Create |

---

## Task 1: StoryManager 加 `flag_changed` 訊號

**Why:** `set_flag()` 目前不發訊號，flag-only 的 objective 無法即時重評。新增訊號讓 QuestManager 能在 flag 變動時 reactively 重評。

**Files:**
- Modify: `game/src/autoload/StoryManager.gd:4`（signals 區）與 `:91-92`（`set_flag`）
- Test: `game/src/test/test_quest_objectives.gd`

- [ ] **Step 1: 建立測試檔，寫第一個失敗測試**

Create `game/src/test/test_quest_objectives.gd`:

```gdscript
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

func _init() -> void:
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
	var sm: Node = load("res://src/autoload/StoryManager.gd").new()
	_flag_events = []
	sm.flag_changed.connect(_on_flag_changed)
	sm.set_flag("clue_locked_room", true)
	_assert(_flag_events.size() == 1, "set_flag 發出一次 flag_changed")
	_assert(_flag_events[0]["key"] == "clue_locked_room", "訊號帶正確 key")
	_assert(_flag_events[0]["value"] == true, "訊號帶正確 value")
	_assert(sm.get_flag("clue_locked_room", false) == true, "flag 確實寫入")
	sm.free()
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `godot --headless --path game --script res://src/test/test_quest_objectives.gd`
Expected: FAIL — `Invalid access to property or key 'flag_changed'`（訊號尚未定義）。

- [ ] **Step 3: 加訊號與發送**

In `game/src/autoload/StoryManager.gd`, 在 signals 區（目前只有一行 `signal event_recorded`）下方新增：

```gdscript
signal event_recorded(event_id: String)
signal flag_changed(key: String, value: Variant)
```

修改 `set_flag`（原 `:91-92`）為：

```gdscript
func set_flag(key: String, value: Variant) -> void:
	player_flags[key] = value
	flag_changed.emit(key, value)
```

- [ ] **Step 4: 跑測試確認通過**

Run: `godot --headless --path game --script res://src/test/test_quest_objectives.gd`
Expected: `[StoryManager.flag_changed]` 4 個 PASS，`ALL PASS`，離開碼 0。

- [ ] **Step 5: Commit**

```bash
git add game/src/autoload/StoryManager.gd game/src/test/test_quest_objectives.gd
git commit -m "feat(story): add flag_changed signal to StoryManager"
```

---

## Task 2: StoryManager relationship→event 通用掛鉤

**Why:** 任務 MQ03 / SQ-E 用「信任達門檻」當完成條件。信任值是真相，門檻事件是派生——以通用掛鉤把 relationship 跨門檻轉成一次性事件，不另加平行 flag（符合 SSOT 原則）。

**Files:**
- Modify: `game/src/autoload/StoryManager.gd`（State 區加欄位、加 `register_relationship_event`、改 `update_relationship`）
- Test: `game/src/test/test_quest_objectives.gd`

- [ ] **Step 1: 寫失敗測試**

在 `test_quest_objectives.gd` 的 `_run_tests()` 內，`_test_flag_changed_signal()` 後加一行 `_test_relationship_event_hook()`。並在檔案新增一個共用重置 helper（之後各測試都用它清掉全域 autoload 狀態），以及本測試方法：

```gdscript
# ── 共用：重置 StoryManager 全域狀態（autoload 跨測試共用，每個測試開頭呼叫）──
func _reset_story(sm: Node) -> void:
	sm.completed_events.clear()
	sm.player_flags.clear()
	sm.npc_relationships.clear()
	sm._relationship_triggers.clear()

var _recorded_events: Array = []

func _on_event_recorded(event_id: String) -> void:
	_recorded_events.append(event_id)

func _test_relationship_event_hook() -> void:
	print("[StoryManager relationship→event]")
	var sm: Node = get_root().get_node("StoryManager")
	_reset_story(sm)
	_recorded_events = []
	sm.event_recorded.connect(_on_event_recorded)
	sm.register_relationship_event("lin_rongchang", 60, "ch1_rongchang_trust_ok")
	# 未達門檻：不觸發
	sm.update_relationship("lin_rongchang", 30)
	_assert(not _recorded_events.has("ch1_rongchang_trust_ok"), "30 < 60 不觸發")
	# 跨過門檻：觸發一次
	sm.update_relationship("lin_rongchang", 40)  # 累積 70
	_assert(_recorded_events.has("ch1_rongchang_trust_ok"), "70 ≥ 60 觸發派生事件")
	# 再加：不重複觸發（record_event 去重）
	var count_before: int = _recorded_events.count("ch1_rongchang_trust_ok")
	sm.update_relationship("lin_rongchang", 10)
	var count_after: int = _recorded_events.count("ch1_rongchang_trust_ok")
	_assert(count_before == count_after, "跨門檻後再加不重複記錄")
	# 重複註冊同一條：不應產生兩條 trigger
	sm.register_relationship_event("lin_rongchang", 60, "ch1_rongchang_trust_ok")
	_assert(sm._relationship_triggers.size() == 1, "重複註冊去重")
	sm.event_recorded.disconnect(_on_event_recorded)
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `godot --headless --path game --script res://src/test/test_quest_objectives.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'register_relationship_event'`。

- [ ] **Step 3: 實作掛鉤**

In `game/src/autoload/StoryManager.gd`，於 State 區（`npc_relationships` 那行附近）新增：

```gdscript
## relationship 跨門檻時派生的一次性事件設定。每項：{npc_id, threshold, event_id}
var _relationship_triggers: Array[Dictionary] = []
```

新增公開方法（放在 `update_relationship` 上方）：

```gdscript
## 註冊「某 NPC 信任值 ≥ threshold 時記錄 event_id」。重複註冊（相同三元組）會被忽略。
func register_relationship_event(npc_id: String, threshold: int, event_id: String) -> void:
	for trig: Dictionary in _relationship_triggers:
		if trig["npc_id"] == npc_id and int(trig["threshold"]) == threshold and trig["event_id"] == event_id:
			return
	_relationship_triggers.append({"npc_id": npc_id, "threshold": threshold, "event_id": event_id})
```

修改 `update_relationship`（原 `:101-103`）為：

```gdscript
func update_relationship(npc_id: String, delta: int) -> void:
	var current: int = npc_relationships.get(npc_id, 0)
	var new_val: int = clamp(current + delta, -100, 100)
	npc_relationships[npc_id] = new_val
	for trig: Dictionary in _relationship_triggers:
		if trig["npc_id"] == npc_id and new_val >= int(trig["threshold"]):
			record_event(trig["event_id"])  # record_event 內含去重
```

- [ ] **Step 4: 跑測試確認通過**

Run: `godot --headless --path game --script res://src/test/test_quest_objectives.gd`
Expected: `[StoryManager relationship→event]` 全 PASS，`ALL PASS`。

- [ ] **Step 5: Commit**

```bash
git add game/src/autoload/StoryManager.gd game/src/test/test_quest_objectives.gd
git commit -m "feat(story): relationship-threshold to derived-event hook"
```

---

## Task 3: QuestData 加 `objectives` + 純函式判定

**Why:** 多步驟 objectives 是引導核心。判定邏輯抽成 static 純函式，可獨立 headless 測試，且讓 QuestManager 與 Journal 共用同一份判定（DRY）。

**Files:**
- Modify: `game/src/core/classes/QuestData.gd`
- Test: `game/src/test/test_quest_objectives.gd`

- [ ] **Step 1: 寫失敗測試**

在 `_run_tests()` 加 `_test_objective_eval()`，並新增：

```gdscript
func _test_objective_eval() -> void:
	print("[QuestData objectives 判定]")
	var QD: GDScript = load("res://src/core/classes/QuestData.gd")
	var objs: Array = [
		{"id": "a", "desc": "事件型", "event": "evt_a"},
		{"id": "b", "desc": "旗標型", "flag": "flag_b"},
		{"id": "c", "desc": "選配", "event": "evt_c", "optional": true},
	]
	var events: Array = ["evt_a"]
	var flags: Dictionary = {}
	# event 達成、flag 未達成
	_assert(QD.is_objective_done(objs[0], events, flags) == true, "event 在 completed → done")
	_assert(QD.is_objective_done(objs[1], events, flags) == false, "flag 未設 → not done")
	# 非選配未全達 → 任務未完成
	_assert(QD.all_required_objectives_done(objs, events, flags) == false, "b 未達 → 整體未完成")
	# 設 flag_b → 非選配全達（c 是 optional 不影響）
	flags["flag_b"] = true
	_assert(QD.is_objective_done(objs[1], events, flags) == true, "flag 設 true → done")
	_assert(QD.all_required_objectives_done(objs, events, flags) == true, "非選配全達 → 完成（忽略 optional c）")
	# 空 objectives → 視為已達（保留舊行為，交給 completion_events）
	_assert(QD.all_required_objectives_done([], events, flags) == true, "空 objectives → true")
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `godot --headless --path game --script res://src/test/test_quest_objectives.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'is_objective_done'`。

- [ ] **Step 3: 實作欄位與純函式**

In `game/src/core/classes/QuestData.gd`，在 `completion_events`（`:18`）下方新增欄位：

```gdscript
## 多步驟子目標。每項：{
##   "id": String, "desc": String,          # desc 顯示於 journal
##   "event": String,  (二選一) 此事件在 completed_events 即達成
##   "flag":  String,  (二選一) 此 flag 在 player_flags 為 true 即達成
##   "optional": bool   # 預設 false；true 不影響任務完成，只作支線提示
## }
@export var objectives: Array[Dictionary] = []
```

在檔案末端新增 static helper：

```gdscript
## 單一 objective 是否達成：event 在 completed_events，或 flag 在 flags 為 true。
static func is_objective_done(obj: Dictionary, completed_events: Array, flags: Dictionary) -> bool:
	var ev: String = obj.get("event", "")
	if ev != "" and completed_events.has(ev):
		return true
	var fl: String = obj.get("flag", "")
	if fl != "" and flags.get(fl, false):
		return true
	return false

## 所有「非 optional」objective 是否全部達成。空陣列回 true（交由 completion_events 判定）。
static func all_required_objectives_done(objectives: Array, completed_events: Array, flags: Dictionary) -> bool:
	for obj: Dictionary in objectives:
		if obj.get("optional", false):
			continue
		if not is_objective_done(obj, completed_events, flags):
			return false
	return true
```

- [ ] **Step 4: 跑測試確認通過**

Run: `godot --headless --path game --script res://src/test/test_quest_objectives.gd`
Expected: `[QuestData objectives 判定]` 全 PASS，`ALL PASS`。

- [ ] **Step 5: Commit**

```bash
git add game/src/core/classes/QuestData.gd game/src/test/test_quest_objectives.gd
git commit -m "feat(quest): add objectives field + pure evaluation helpers to QuestData"
```

---

## Task 4: QuestManager — objectives 判定 + 監聽 flag + 章節掃描

**Why:** 把完成判定改為 objectives 導向、加 flag 變動重評、掃描章節 `quests/` 資料夾（目前章節任務從未被載入）、提供 journal 逐項狀態。加 `register_quest()` 供測試/程式手動註冊任務，加公開 `reevaluate()` 供章節開場初次評估與測試用。

> **Harness 註：** Task 1 已確立 QuestManager 是 autoload、測試取真實節點 `get_root().get_node("QuestManager")`。因此原計畫的 `story` 注入 seam / `autoscan_on_ready` 不再需要（autoload 啟動時 `_ready` 已連好訊號、載好任務），直接用 `StoryManager` autoload。測試靠 `_reset_story` + 重置 QuestManager 狀態確保確定性。

**Files:**
- Modify: `game/src/autoload/QuestManager.gd`（整檔改寫，見下）
- Test: `game/src/test/test_quest_objectives.gd`

- [ ] **Step 1: 寫失敗整合測試**

在 `_run_tests()` 加 `_test_questmanager_integration()`，並新增（含重置 QuestManager 狀態的 helper）：

```gdscript
# ── 共用：重置 QuestManager 全域狀態 ──
func _reset_quests(qm: Node) -> void:
	qm._active_quests.clear()
	qm._completed_quests.clear()

func _test_questmanager_integration() -> void:
	print("[QuestManager 整合：objectives + 自動開始/完成]")
	var sm: Node = get_root().get_node("StoryManager")
	var qm: Node = get_root().get_node("QuestManager")
	_reset_story(sm)
	_reset_quests(qm)

	# 手動建立一個兩步驟任務（required: evt_start；obj: evt_x + flag_y）
	var QD: GDScript = load("res://src/core/classes/QuestData.gd")
	var q: Resource = QD.new()
	q.quest_id = "t_quest"
	q.title = "測試任務"
	q.required_events = ["evt_start"]
	q.objectives = [
		{"id": "x", "desc": "做 X", "event": "evt_x"},
		{"id": "y", "desc": "做 Y", "flag": "flag_y"},
	]
	qm.register_quest(q)

	# 前置未達 → 不自動開始（手動觸發一次初評）
	qm.reevaluate()
	_assert(not qm.is_quest_active("t_quest"), "前置未達不開始")
	# 滿足前置 → 透過真實訊號自動開始（record_event 會觸發 _reevaluate）
	sm.record_event("evt_start")
	_assert(qm.is_quest_active("t_quest"), "前置達成自動開始")
	# 完成第一個 objective（不應完成整體）
	sm.record_event("evt_x")
	_assert(qm.is_quest_active("t_quest"), "只完成一步 → 仍進行中")
	var status: Array = qm.get_objective_status("t_quest")
	_assert(status[0]["done"] == true and status[1]["done"] == false, "逐項狀態正確")
	# 完成第二個 objective（flag）→ set_flag 觸發 flag_changed → 整體完成
	sm.set_flag("flag_y", true)
	_assert(qm.is_quest_completed("t_quest"), "兩步全達 → 完成")
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_quest_objectives.gd`
Expected: FAIL — `Nonexistent function 'register_quest'`（或 `reevaluate` / `get_objective_status` 未定義）。

- [ ] **Step 3: 改寫 QuestManager**

將 `game/src/autoload/QuestManager.gd` 改為以下內容（整檔替換）：

```gdscript
## QuestManager — 任務追蹤系統
## 管理任務的接取、進度追蹤、完成判定。
## 任務 = 劇情事件真相（StoryManager flags/events）的玩家可見投影：
## objectives 掛接既有 beat/cutscene 事件與 flag，自動開始/逐項打勾/完成。
extends Node

# ── Signals ─────────────────────────────────────────────────────────────────
signal quest_started(quest_id: String)
signal quest_completed(quest_id: String)
signal quest_available(quest_id: String)

# ── State ───────────────────────────────────────────────────────────────────
var _all_quests: Dictionary = {}           # quest_id -> QuestData
var _active_quests: Array[String] = []     # 進行中的任務
var _completed_quests: Array[String] = []  # 已完成的任務

func _ready() -> void:
	_load_all_quests()
	# 監聽事件與旗標變動，自動重評任務開始/完成條件
	StoryManager.event_recorded.connect(_on_story_event)
	StoryManager.flag_changed.connect(_on_story_flag)

# ── Loading ───────────────────────────────────────────────────────────────────
func _load_all_quests() -> void:
	_load_quests_from_dir("res://src/quests/")
	_load_chapter_quests()
	print("QuestManager: loaded %d quests" % _all_quests.size())

func _load_quests_from_dir(quest_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(quest_dir):
		return
	var dir: DirAccess = DirAccess.open(quest_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var quest: QuestData = load(quest_dir + file_name) as QuestData
			if quest and not quest.quest_id.is_empty():
				_all_quests[quest.quest_id] = quest
		file_name = dir.get_next()
	dir.list_dir_end()

## 掃描 res://src/chapters/<id>/quests/ 下所有任務，與全域池合併。
func _load_chapter_quests() -> void:
	var base: String = "res://src/chapters/"
	if not DirAccess.dir_exists_absolute(base):
		return
	var dir: DirAccess = DirAccess.open(base)
	if dir == null:
		return
	dir.list_dir_begin()
	var sub: String = dir.get_next()
	while sub != "":
		if dir.current_is_dir() and not sub.begins_with("."):
			_load_quests_from_dir(base + sub + "/quests/")
		sub = dir.get_next()
	dir.list_dir_end()

## 測試/程式用：手動註冊一筆任務資料。
func register_quest(quest: QuestData) -> void:
	if quest and not quest.quest_id.is_empty():
		_all_quests[quest.quest_id] = quest

# ── Public API ──────────────────────────────────────────────────────────────
func start_quest(quest_id: String) -> bool:
	if _active_quests.has(quest_id) or _completed_quests.has(quest_id):
		return false
	if not _all_quests.has(quest_id):
		push_warning("QuestManager: Unknown quest: " + quest_id)
		return false
	var quest: QuestData = _all_quests[quest_id]
	if not _can_start(quest):
		return false
	_active_quests.append(quest_id)
	quest_started.emit(quest_id)
	print("QuestManager: quest started - ", quest.title)
	return true

func complete_quest(quest_id: String) -> void:
	if not _active_quests.has(quest_id):
		return
	_active_quests.erase(quest_id)
	_completed_quests.append(quest_id)
	var quest: QuestData = _all_quests[quest_id]
	_apply_rewards(quest)
	quest_completed.emit(quest_id)
	print("QuestManager: quest completed - ", quest.title)

func is_quest_active(quest_id: String) -> bool:
	return _active_quests.has(quest_id)

func is_quest_completed(quest_id: String) -> bool:
	return _completed_quests.has(quest_id)

func get_active_quests() -> Array[QuestData]:
	var result: Array[QuestData] = []
	for qid: String in _active_quests:
		if _all_quests.has(qid):
			result.append(_all_quests[qid])
	return result

func get_quest(quest_id: String) -> QuestData:
	return _all_quests.get(quest_id, null)

## 給 journal：回每個 objective 的 {desc, optional, done}。
func get_objective_status(quest_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var quest: QuestData = _all_quests.get(quest_id, null)
	if quest == null:
		return result
	for obj: Dictionary in quest.objectives:
		result.append({
			"desc": obj.get("desc", ""),
			"optional": obj.get("optional", false),
			"done": QuestData.is_objective_done(obj, StoryManager.completed_events, StoryManager.player_flags),
		})
	return result

# ── Internal ────────────────────────────────────────────────────────────────
func _on_story_event(_event_id: String) -> void:
	reevaluate()

func _on_story_flag(_key: String, _value: Variant) -> void:
	reevaluate()

## 重評所有任務的開始/完成條件。訊號自動呼叫；章節開場或測試也可手動呼叫一次初評。
func reevaluate() -> void:
	# 先檢查完成
	for qid: String in _active_quests.duplicate():
		var quest: QuestData = _all_quests[qid]
		if _check_completion(quest):
			complete_quest(qid)
	# 再檢查可自動接取
	for qid: String in _all_quests:
		if _active_quests.has(qid) or _completed_quests.has(qid):
			continue
		var quest: QuestData = _all_quests[qid]
		if _can_start(quest):
			start_quest(qid)

func _can_start(quest: QuestData) -> bool:
	for req: String in quest.required_events:
		if not StoryManager.completed_events.has(req):
			return false
	return true

func _check_completion(quest: QuestData) -> bool:
	if not QuestData.all_required_objectives_done(quest.objectives, StoryManager.completed_events, StoryManager.player_flags):
		return false
	for evt: String in quest.completion_events:
		if not StoryManager.completed_events.has(evt):
			return false
	return true

func _apply_rewards(quest: QuestData) -> void:
	for npc_id: String in quest.reward_relationship:
		var delta: int = quest.reward_relationship[npc_id]
		StoryManager.update_relationship(npc_id, delta)
	if not quest.reward_unlock_zone.is_empty():
		StoryManager.unlock_zone(quest.reward_unlock_zone)
	if not quest.reward_event.is_empty():
		StoryManager.record_event(quest.reward_event)

# ── Persistence ─────────────────────────────────────────────────────────────
func serialize() -> Dictionary:
	return {
		"active_quests": _active_quests.duplicate(),
		"completed_quests": _completed_quests.duplicate(),
	}

func deserialize(data: Dictionary) -> void:
	_active_quests.assign(data.get("active_quests", []))
	_completed_quests.assign(data.get("completed_quests", []))
```

- [ ] **Step 4: 跑測試確認通過**

Run: `godot --headless --path game --script res://src/test/test_quest_objectives.gd`
Expected: `[QuestManager 整合...]` 全 PASS，`ALL PASS`，離開碼 0。

- [ ] **Step 5: 回歸——確認既有全域任務仍相容**

確認 `game/src/quests/quest_visit_market.tres`、`quest_temple_mystery.tres` 無 `objectives` 欄位時，`all_required_objectives_done([], …)` 回 true，完成判定退回 `completion_events`（舊行為）。此情境已被 Task 3 的「空 objectives → true」測試涵蓋，無需改任務檔。

- [ ] **Step 6: Commit**

```bash
git add game/src/autoload/QuestManager.gd game/src/test/test_quest_objectives.gd
git commit -m "feat(quest): objective-based completion, flag-change reeval, chapter quest scan"
```

---

## Task 5: 第一章 events.gd 註冊信任門檻→事件

**Why:** 讓 MQ03（榮昌信任）與 SQ-E（阿桃姨信任）的 objective 有可觀測的完成事件。

**Files:**
- Modify: `game/src/chapters/chapter_01_arrival/events.gd:23-25`（`register`）

- [ ] **Step 1: 修改 `register`**

將 `register`（`:23-25`）改為：

```gdscript
func register(_manager: Node) -> void:
	EventBus.zone_loaded.connect(_on_zone_loaded)
	StoryManager.event_recorded.connect(_on_event_recorded)
	# 信任門檻 → 派生事件（供任務 objective 使用；重複註冊會被去重）
	StoryManager.register_relationship_event("lin_rongchang", 60, "ch1_rongchang_trust_ok")
	StoryManager.register_relationship_event("a_tao_yi", 50, "ch1_atao_truth")
```

（`unregister` 不需改：trigger 留著無害且去重；relationship→event 為一次性記錄。）

- [ ] **Step 2: 語法檢查**

Run: `godot --headless --path game --check-only --script res://src/chapters/chapter_01_arrival/events.gd`
Expected: 無錯誤輸出（離開碼 0）。

- [ ] **Step 3: Commit**

```bash
git add game/src/chapters/chapter_01_arrival/events.gd
git commit -m "feat(ch01): register trust-threshold derived events for quests"
```

---

## Task 6: 撰寫第一章 6 主線 + 2 支線任務 `.tres`

**Why:** 把劇情轉成玩家可見的麵包屑任務，全部掛接既有事件/flag（除 Task 5 的兩個信任事件）。

**Files:**
- Create: `game/src/chapters/chapter_01_arrival/quests/mq01_iron_door.tres`
- Create: `…/mq02_stranger_1983.tres`
- Create: `…/mq03_apprentice.tres`
- Create: `…/mq04_three_wrong_things.tres`
- Create: `…/mq05_locked_room.tres`
- Create: `…/mq06_finale_name.tres`
- Create: `…/sq_b_lao_zhou.tres`
- Create: `…/sq_e_atao_truth.tres`

- [ ] **Step 1: MQ01 鐵門後**

Create `game/src/chapters/chapter_01_arrival/quests/mq01_iron_door.tres`:

```
[gd_resource type="Resource" script_class="QuestData" load_steps=2 format=3 uid="uid://muzha_quest_ch1_mq01"]

[ext_resource type="Script" path="res://src/core/classes/QuestData.gd" id="1_quest_data"]

[resource]
script = ExtResource("1_quest_data")
quest_id = "ch1_mq01_iron_door"
title = "鐵門後"
description = "整理這間塵封四十年的榮昌中藥行，看看裡面藏了什麼。"
target_zone = "zone_pharmacy"
required_events = []
objectives = Array[Dictionary]([{
"id": "see_photo",
"desc": "看清楚牆上那張全家福",
"flag": "saw_blacked_photo"
}, {
"id": "travel",
"desc": "翻找櫃台抽屜，觸碰古地圖上的紅點",
"event": "ch1_first_travel_done"
}])
```

- [ ] **Step 2: MQ02 1983 的陌生人**

Create `…/mq02_stranger_1983.tres`:

```
[gd_resource type="Resource" script_class="QuestData" load_steps=2 format=3 uid="uid://muzha_quest_ch1_mq02"]

[ext_resource type="Script" path="res://src/core/classes/QuestData.gd" id="1_quest_data"]

[resource]
script = ExtResource("1_quest_data")
quest_id = "ch1_mq02_stranger_1983"
title = "1983 的陌生人"
description = "櫃台後那個皺眉看你的中年男子是誰？想辦法在這裡待下來。"
giver_npc_id = "lin_rongchang"
target_npc_id = "lin_rongchang"
target_zone = "zone_pharmacy"
required_events = ["ch1_first_travel_done"]
objectives = Array[Dictionary]([{
"id": "stay",
"desc": "向林榮昌攀談，編個身分留在藥行打工",
"event": "ch1_started_living_in_pharmacy"
}])
```

- [ ] **Step 3: MQ03 榮昌中藥行的學徒**

Create `…/mq03_apprentice.tres`:

```
[gd_resource type="Resource" script_class="QuestData" load_steps=2 format=3 uid="uid://muzha_quest_ch1_mq03"]

[ext_resource type="Script" path="res://src/core/classes/QuestData.gd" id="1_quest_data"]

[resource]
script = ExtResource("1_quest_data")
quest_id = "ch1_mq03_apprentice"
title = "榮昌中藥行的學徒"
description = "在藥行幹活、跑腿、別說錯話——慢慢取得林榮昌的信任。"
giver_npc_id = "lin_rongchang"
target_npc_id = "lin_rongchang"
target_zone = "zone_market"
required_events = ["ch1_started_living_in_pharmacy"]
objectives = Array[Dictionary]([{
"id": "trust",
"desc": "取得林榮昌的基礎信任",
"event": "ch1_rongchang_trust_ok"
}])
```

- [ ] **Step 4: MQ04 不對勁的三件事**

Create `…/mq04_three_wrong_things.tres`:

```
[gd_resource type="Resource" script_class="QuestData" load_steps=2 format=3 uid="uid://muzha_quest_ch1_mq04"]

[ext_resource type="Script" path="res://src/core/classes/QuestData.gd" id="1_quest_data"]

[resource]
script = ExtResource("1_quest_data")
quest_id = "ch1_mq04_three_wrong_things"
title = "不對勁的三件事"
description = "全家福被塗黑的臉、後院上鎖的房間、阿嬤的燒香——這個家在隱瞞什麼。"
target_zone = "zone_pharmacy"
required_events = ["ch1_started_living_in_pharmacy"]
objectives = Array[Dictionary]([{
"id": "xiaowei",
"desc": "向堂叔林小威打聽家裡沒人提的叔叔",
"event": "ch1_xiaowei_talked"
}, {
"id": "incense",
"desc": "撞見林阿嬤在後院燒香",
"event": "ch1_saw_ama_incense"
}, {
"id": "lawyer",
"desc": "（選擇）找律師對質「祖父林榮昌」的矛盾",
"event": "ch1_lawyer_visited",
"optional": true
}])
```

- [ ] **Step 5: MQ05 後院上鎖的房間**

Create `…/mq05_locked_room.tres`:

```
[gd_resource type="Resource" script_class="QuestData" load_steps=2 format=3 uid="uid://muzha_quest_ch1_mq05"]

[ext_resource type="Script" path="res://src/core/classes/QuestData.gd" id="1_quest_data"]

[resource]
script = ExtResource("1_quest_data")
quest_id = "ch1_mq05_locked_room"
title = "後院上鎖的房間"
description = "那扇門後面是誰的房間？先取得阿嬤的信任，拿到鑰匙。"
giver_npc_id = "lin_ama"
target_npc_id = "lin_ama"
target_zone = "zone_pharmacy_backyard"
required_events = ["ch1_xiaowei_talked", "ch1_saw_ama_incense"]
objectives = Array[Dictionary]([{
"id": "key",
"desc": "取得林阿嬤的信任，拿到後院鑰匙",
"event": "ch1_got_key"
}, {
"id": "relic",
"desc": "進入房間，找到林榮華留下的遺物",
"event": "ch1_found_relic"
}])
```

- [ ] **Step 6: MQ06 通關之夜：那個名字**

Create `…/mq06_finale_name.tres`:

```
[gd_resource type="Resource" script_class="QuestData" load_steps=2 format=3 uid="uid://muzha_quest_ch1_mq06"]

[ext_resource type="Script" path="res://src/core/classes/QuestData.gd" id="1_quest_data"]

[resource]
script = ExtResource("1_quest_data")
quest_id = "ch1_mq06_finale_name"
title = "通關之夜：那個名字"
description = "帶著遺物去找林榮昌。引導他走過情緒，讓他親口說出那個被抹除的名字。"
giver_npc_id = "lin_rongchang"
target_npc_id = "lin_rongchang"
required_events = ["ch1_found_relic"]
objectives = Array[Dictionary]([{
"id": "show_relic",
"desc": "把林榮華的遺物拿給林榮昌看",
"event": "ch1_relic_shown"
}, {
"id": "say_name",
"desc": "在長對話中讓林榮昌說出弟弟的名字",
"event": "ch1_finale_said_brother_name"
}])
```

- [ ] **Step 7: SQ-B 老周的繞圈話**

Create `…/sq_b_lao_zhou.tres`:

```
[gd_resource type="Resource" script_class="QuestData" load_steps=2 format=3 uid="uid://muzha_quest_ch1_sqb"]

[ext_resource type="Script" path="res://src/core/classes/QuestData.gd" id="1_quest_data"]

[resource]
script = ExtResource("1_quest_data")
quest_id = "ch1_sq_b_lao_zhou"
title = "老周的繞圈話"
description = "市場入口的耆老老周認識整個林家。去現代的市場跟他聊聊。"
giver_npc_id = "lao_zhou"
target_npc_id = "lao_zhou"
target_zone = "zone_market"
required_events = ["ch1_first_travel_done"]
objectives = Array[Dictionary]([{
"id": "ask_lao_zhou",
"desc": "向老周打聽林家的舊事",
"event": "ch1_met_lao_zhou"
}])
```

- [ ] **Step 8: SQ-E 阿桃姨知道的事**

Create `…/sq_e_atao_truth.tres`:

```
[gd_resource type="Resource" script_class="QuestData" load_steps=2 format=3 uid="uid://muzha_quest_ch1_sqe"]

[ext_resource type="Script" path="res://src/core/classes/QuestData.gd" id="1_quest_data"]

[resource]
script = ExtResource("1_quest_data")
quest_id = "ch1_sq_e_atao_truth"
title = "阿桃姨知道的事"
description = "隔壁賣菜的阿桃姨跟林榮華從小一起長大。取得她的信任，也許能問出 1976 年那年的真相。"
giver_npc_id = "a_tao_yi"
target_npc_id = "a_tao_yi"
target_zone = "zone_market"
required_events = ["ch1_started_living_in_pharmacy"]
objectives = Array[Dictionary]([{
"id": "atao_trust",
"desc": "取得阿桃姨的信任，聽她說出 1976 年的事",
"event": "ch1_atao_truth"
}])
```

- [ ] **Step 9: 確認載入（手動 headless 檢查）**

建立暫時檢查或在編輯器啟動遊戲，確認 console 印出 `QuestManager: loaded N quests`（N ≥ 既有 2 + 新增 8 = 10）。若用編輯器：開啟專案、執行主場景、觀察輸出面板。

- [ ] **Step 10: Commit**

```bash
git add game/src/chapters/chapter_01_arrival/quests/
git commit -m "feat(ch01): author 6 main + 2 side quests wired to existing beat/cutscene events"
```

---

## Task 7: QuestJournal 顯示 objectives 逐項打勾

**Why:** 麵包屑要看得到。active 任務下逐項列出 objective，完成打勾、未完成顯示待辦，optional 標示（選擇）。

**Files:**
- Modify: `game/src/ui/menus/QuestJournal.gd:20-39`（`_refresh`）

- [ ] **Step 1: 改寫 `_refresh` 的 active 區塊**

將 `_refresh()`（`:20-39`）中 active 任務的迴圈改為：

```gdscript
func _refresh() -> void:
	_clear_list(_active_list)
	_clear_list(_completed_list)

	var active: Array[QuestData] = QuestManager.get_active_quests()
	if active.is_empty():
		_add_item(_active_list, "(none)", Color(0.5, 0.5, 0.5))
	else:
		for q: QuestData in active:
			_add_item(_active_list, q.title, Color.WHITE)
			_add_item(_active_list, "  " + q.description, Color(0.7, 0.7, 0.7), 10)
			for obj: Dictionary in QuestManager.get_objective_status(q.quest_id):
				var mark: String = "☑" if obj["done"] else "☐"
				var suffix: String = "（選擇）" if obj["optional"] else ""
				var col: Color = Color(0.5, 0.8, 0.5) if obj["done"] else Color(0.85, 0.85, 0.6)
				_add_item(_active_list, "    %s %s%s" % [mark, obj["desc"], suffix], col, 10)

	var completed: Array[String] = QuestManager._completed_quests
	if completed.is_empty():
		_add_item(_completed_list, "(none)", Color(0.5, 0.5, 0.5))
	else:
		for qid: String in completed:
			var q: QuestData = QuestManager.get_quest(qid)
			if q:
				_add_item(_completed_list, "✓ " + q.title, Color(0.5, 0.8, 0.5))
```

- [ ] **Step 2: 語法檢查**

Run: `godot --headless --path game --check-only --script res://src/ui/menus/QuestJournal.gd`
Expected: 無錯誤輸出（離開碼 0）。

- [ ] **Step 3: 目視驗證（編輯器）**

開啟專案執行主場景，穿越後按 journal 鍵（`toggle_journal`），確認 active 任務下出現 ☐/☑ 子目標、optional 顯示「（選擇）」。

- [ ] **Step 4: Commit**

```bash
git add game/src/ui/menus/QuestJournal.gd
git commit -m "feat(ui): show quest objectives with checkmarks in journal"
```

---

## Task 8: 全鏈整合驗證（headless 模擬第一章主線）

**Why:** 確保六個主線任務依劇情事件序列正確開始/打勾/完成、stage 同步前進，沒有掛接字串錯字。

**Files:**
- Test: `game/src/test/test_quest_objectives.gd`（新增 `_test_chapter1_mainline_flow`）

- [ ] **Step 1: 寫整合測試**

在 `_init()` 加 `_test_chapter1_mainline_flow()`，並新增：

```gdscript
func _test_chapter1_mainline_flow() -> void:
	print("[第一章主線全鏈]")
	var sm: Node = load("res://src/autoload/StoryManager.gd").new()
	get_root().add_child(sm)
	# 註冊信任門檻（模擬 events.gd register）
	sm.register_relationship_event("lin_rongchang", 60, "ch1_rongchang_trust_ok")
	var qm: Node = load("res://src/autoload/QuestManager.gd").new()
	qm.story = sm
	qm.autoscan_on_ready = false
	get_root().add_child(qm)
	# 載入第一章任務檔
	qm._load_quests_from_dir("res://src/chapters/chapter_01_arrival/quests/")

	# MQ01 開章自動開始（required 空）
	qm.reevaluate_for_test()
	_assert(qm.is_quest_active("ch1_mq01_iron_door"), "MQ01 自動開始")
	# 穿越流程
	sm.set_flag("saw_blacked_photo", true)
	sm.set_flag("first_time_traveled", true)
	sm.record_event("ch1_first_travel_done")
	_assert(qm.is_quest_completed("ch1_mq01_iron_door"), "MQ01 完成")
	_assert(qm.is_quest_active("ch1_mq02_stranger_1983"), "MQ02 自動開始")
	# 留下打工
	sm.set_flag("started_pharmacy_work", true)
	sm.record_event("ch1_started_living_in_pharmacy")
	_assert(qm.is_quest_completed("ch1_mq02_stranger_1983"), "MQ02 完成")
	_assert(qm.is_quest_active("ch1_mq03_apprentice"), "MQ03 自動開始")
	_assert(qm.is_quest_active("ch1_mq04_three_wrong_things"), "MQ04 自動開始")
	# 信任達標 → MQ03 完成
	sm.update_relationship("lin_rongchang", 60)
	_assert(qm.is_quest_completed("ch1_mq03_apprentice"), "MQ03 由信任事件完成")
	# MQ04 兩個非選配
	sm.set_flag("clue_locked_room", true)
	sm.record_event("ch1_xiaowei_talked")
	sm.set_flag("saw_ama_incense", true)
	sm.record_event("ch1_saw_ama_incense")
	_assert(qm.is_quest_completed("ch1_mq04_three_wrong_things"), "MQ04 完成（不需 optional 律師）")
	_assert(qm.is_quest_active("ch1_mq05_locked_room"), "MQ05 自動開始")
	# MQ05
	sm.set_flag("got_locked_room_key", true)
	sm.record_event("ch1_got_key")
	sm.set_flag("found_ronghua_relic", true)
	sm.record_event("ch1_found_relic")
	_assert(qm.is_quest_completed("ch1_mq05_locked_room"), "MQ05 完成")
	_assert(qm.is_quest_active("ch1_mq06_finale_name"), "MQ06 自動開始")
	# MQ06
	sm.set_flag("finale_night_ready", true)
	sm.record_event("ch1_relic_shown")
	sm.record_event("ch1_finale_said_brother_name")
	_assert(qm.is_quest_completed("ch1_mq06_finale_name"), "MQ06 完成（章節主線走完）")
```

並在 `_run_tests()` 的測試呼叫序列尾端加入 `_test_chapter1_mainline_flow()`（在 `quit()` 之前）。

- [ ] **Step 2: 跑全部測試**

Run: `godot --headless --path game --script res://src/test/test_quest_objectives.gd`
Expected: 全部區塊 PASS，最後 `ALL PASS`，離開碼 0。若某步 FAIL，多半是任務 `.tres` 的事件字串與本計畫「已確認事件表」不符——對照修正 `.tres`，不要改測試期望值。

- [ ] **Step 3: Commit**

```bash
git add game/src/test/test_quest_objectives.gd
git commit -m "test(quest): chapter 1 mainline full-chain integration test"
```

---

## Self-Review 紀錄

- **Spec 覆蓋：** §3 投影模型→Task 3/4；§4 改動 #1 objectives→Task 3、#2 章節掃描→Task 4、#3 relationship hook→Task 2+5、#5 journal→Task 7；§5 任務列表→Task 6；§6 新增事件→Task 5（兩個信任事件，其餘改用既有事件，較 spec 更省）；§7 測試→Task 1/2/3/4/8。spec §4 改動 #6（NPC prompt 帶當前任務）為選配，本計畫不納入（YAGNI，需要時另開）。
- **與 spec 的有意差異：** spec 曾列 `ch1_entered_pharmacy_modern`、`ch1_errand_done` 為待新增；實作發現開鐵門 cutscene 已設 `saw_blacked_photo`，故 MQ01 改用既有 flag/event，跑腿 optional 目標移除（無既有觸發點，避免發明無歸屬的觸發）。淨新增事件由 4-5 個降為 2 個。
- **型別一致：** `is_objective_done` / `all_required_objectives_done` 兩處簽章在 Task 3 定義、Task 4 與 Task 7 沿用一致；`_story()` seam 命名一致；quest_id 字串在 Task 6 定義、Task 8 引用一致。
- **無 placeholder：** 所有步驟含完整程式碼與確切指令。
```
