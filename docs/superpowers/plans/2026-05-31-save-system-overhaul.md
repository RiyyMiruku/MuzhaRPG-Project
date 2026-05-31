# 存檔系統重整 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把存檔邏輯抽成 `SaveManager` autoload，修正載入時序/era 濾鏡套不回的 bug，加 3 手動 + 1 自動存檔位、定時自動存檔、清單式存讀檔 UI。

**Architecture:** 新增 `SaveManager` autoload（註冊在所有依賴 manager 之後）。核心是把「依正確順序 deserialize」抽成純函式 `_apply_save_data(data)`（Story → Chapter → Quest → Era），可 headless 測試；`load_from_slot` 在重載主場景後呼叫它，再跳 zone + 套 era 濾鏡。GameManager 的 `save_game/load_game` 移除，呼叫點改走 SaveManager。

**Tech Stack:** Godot 4.6.1 / GDScript。測試沿用 headless `SceneTree` 模式。

**Godot 執行檔（不在 PATH）：** `C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe`
跑測試：`& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_save_system.gd`

**專案硬規則：** 絕不用 `:=`（Variant 推斷是專案錯誤）；所有變數顯式型別含 `for x: T in`。TAB 縮排。

**測試 harness 慣例：** autoload 不能 `load(...).new()`（相依其他 autoload 會炸）。測試 `extends SceneTree`、`_initialize()` 內 `call_deferred("_run_tests")`、用 `get_root().get_node("SaveManager")` 取真實 autoload；每測試開頭重置全域狀態。

---

## 參考：既有狀態（已審計確認）

各 manager 的 serialize 欄位（介面不改）：
- `StoryManager.serialize()` → unlocked_zones, completed_events, player_flags, npc_relationships, conversation_histories, current_zone, game_time_hours
- `ChapterManager.serialize()` → current_chapter_id
- `EraManager.serialize()` → current_era
- `QuestManager.serialize()` → active_quests, completed_quests
- 玩家位置 / time_played 由 SaveManager 直接收集

既有呼叫點（要改）：
- `PauseMenu.gd:46` `GameManager.save_game(1)`、`:52` `GameManager.load_game(1)`、`:39` `GameManager.has_save(1)`
- `MainMenu.gd:26` `GameManager.load_game(1)`、`:14` `GameManager.has_save(1)`

既有 bug（要修）：
- load 時 `QuestManager.deserialize`（含 reevaluate）跑在 `ChapterManager.deserialize`（re-register events 補回 `_relationship_triggers`）之前。
- `EraManager.deserialize` 只設變數沒套濾鏡。

GameManager 相關：`_time_played_sec`、`_pending_load_position`、`current_state`、`GameState` enum、`SAVE_DIR`/`SAVE_VERSION`（將移到 SaveManager）。

---

## File Structure

| 檔案 | 責任 | 動作 |
|---|---|---|
| `game/src/autoload/SaveManager.gd` | 存讀檔編排、slot 管理、自動存檔 timer | Create |
| `game/project.godot` | 註冊 SaveManager autoload（最後） | Modify |
| `game/src/autoload/GameManager.gd` | 移除 save_game/load_game/has_save/get_save_info/SAVE_*；加 `apply_loaded_runtime()`、公開 `collect_player_position()` | Modify |
| `game/src/ui/menus/SaveLoadPanel.gd` | 清單式存讀檔面板 | Create |
| `game/src/ui/menus/SaveLoadPanel.tscn` | 面板場景 | Create |
| `game/src/ui/menus/PauseMenu.gd` | 儲存/載入改開 SaveLoadPanel | Modify |
| `game/src/ui/menus/MainMenu.gd` | 載入改開 SaveLoadPanel（讀檔模式） | Modify |
| `game/src/maps/main_world.tscn` | 加 SaveLoadPanel 實例到 UILayer | Modify |
| `game/src/test/test_save_system.gd` | headless 測試 | Create |

---

## Task 1: GameManager 瘦身 — 加 runtime 還原 API、移除舊 save/load

**Why:** 把存檔職責讓給 SaveManager；GameManager 只保留「執行期」資料（時間、玩家定位）的小介面供 SaveManager 呼叫。先做這步，後續 SaveManager 才有乾淨介面可用。

**Files:**
- Modify: `game/src/autoload/GameManager.gd`

- [ ] **Step 1: 移除舊存檔程式碼**

刪除 `GameManager.gd` 中以下成員（連同其 `# ── Save / Load ──` 區塊註解）：`const SAVE_DIR`、`const SAVE_VERSION`、`func save_game`、`func load_game`、`func has_save`、`func get_save_info`。
保留 `_time_played_sec`、`_pending_load_position`、`return_to_main_menu`、`_process` 中的玩家定位邏輯。

- [ ] **Step 2: 加公開 runtime 介面**

在 GameManager `return_to_main_menu` 之前新增：

```gdscript
# ── Runtime 狀態存取（給 SaveManager 用）────────────────────────────────────
## 收集玩家當前世界座標（無玩家時回 Vector2.ZERO）。
func collect_player_position() -> Vector2:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return Vector2.ZERO
	return players[0].global_position

## 目前累計遊玩秒數。
func get_time_played_sec() -> float:
	return _time_played_sec

## 載入存檔後還原執行期狀態：遊玩時間 + 待定位玩家座標。
func apply_loaded_runtime(time_played: float, player_pos: Vector2) -> void:
	_time_played_sec = time_played
	_pending_load_position = player_pos
```

- [ ] **Step 3: 語法檢查**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --check-only --script res://src/autoload/GameManager.gd`
Expected: 無 parse error（autoload identifier 警告可忽略）。

- [ ] **Step 4: 確認沒有殘留呼叫舊 API**

Run: `grep -rn "GameManager.save_game\|GameManager.load_game\|GameManager.has_save\|GameManager.get_save_info" game/src`
Expected: 只剩 `PauseMenu.gd` 與 `MainMenu.gd`（Task 6 會改）。先不動，下一 task 建 SaveManager。

- [ ] **Step 5: Commit**

```bash
git add game/src/autoload/GameManager.gd
git commit -m "refactor(save): remove save/load from GameManager, add runtime restore API

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: SaveManager — 存檔 + slot 查詢（檔案 I/O）

**Files:**
- Create: `game/src/autoload/SaveManager.gd`
- Modify: `game/project.godot`
- Test: `game/src/test/test_save_system.gd`

- [ ] **Step 1: 註冊 autoload（最後）**

在 `game/project.godot` 的 `[autoload]` 區塊，`EraManager=...` 之後新增一行：

```
SaveManager="*res://src/autoload/SaveManager.gd"
```

- [ ] **Step 2: 建立 SaveManager（存檔 + slot 查詢部分）**

Create `game/src/autoload/SaveManager.gd`:

```gdscript
## SaveManager — 存讀檔編排 autoload
## 職責：收集各 manager serialize → 寫檔；讀檔 → 重載場景 → 依序 deserialize → 套 zone/era。
## 註冊順序須在所有依賴 manager（Game/Story/Chapter/Quest/Era）之後。
extends Node

# ── Signals ─────────────────────────────────────────────────────────────────
signal save_completed(slot: Variant)
signal load_completed(slot: Variant)
signal save_failed(slot: Variant, reason: String)

# ── Constants ───────────────────────────────────────────────────────────────
const SAVE_DIR: String = "user://saves/"
const SAVE_VERSION: String = "0.2.0"
const MANUAL_SLOTS: Array = [1, 2, 3]
const AUTO_SLOT: String = "auto"
const AUTOSAVE_INTERVAL_SEC: float = 300.0

# ── State ───────────────────────────────────────────────────────────────────
var _autosave_timer: Timer = null

func _ready() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_SEC
	_autosave_timer.one_shot = false
	_autosave_timer.timeout.connect(_on_autosave_tick)
	add_child(_autosave_timer)
	_autosave_timer.start()

# ── Path helpers ────────────────────────────────────────────────────────────
func _slot_path(slot: Variant) -> String:
	return SAVE_DIR + "save_%s.json" % str(slot)

func has_slot(slot: Variant) -> bool:
	return FileAccess.file_exists(_slot_path(slot))

# ── Save ────────────────────────────────────────────────────────────────────
## 收集所有 manager 狀態寫入指定 slot。回傳是否成功。
func save_to_slot(slot: Variant) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"timestamp": int(Time.get_unix_time_from_system()),
		"player": {
			"zone": StoryManager.current_zone,
			"position_x": GameManager.collect_player_position().x,
			"position_y": GameManager.collect_player_position().y,
		},
		"story": StoryManager.serialize(),
		"quests": QuestManager.serialize(),
		"chapter": ChapterManager.serialize(),
		"era": EraManager.serialize(),
		"time_played_sec": GameManager.get_time_played_sec(),
	}
	var file: FileAccess = FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write slot %s" % str(slot))
		save_failed.emit(slot, "寫檔失敗")
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("SaveManager: saved slot %s" % str(slot))
	save_completed.emit(slot)
	return true

# ── Slot info (給 UI) ───────────────────────────────────────────────────────
## 回 slot 的摘要：{exists, chapter_id, time_played_sec, timestamp}。不存在/壞檔回 {"exists": false}。
func get_slot_info(slot: Variant) -> Dictionary:
	if not has_slot(slot):
		return {"exists": false}
	var file: FileAccess = FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		return {"exists": false}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {"exists": false}
	file.close()
	var data: Dictionary = json.data
	var chapter: Dictionary = data.get("chapter", {})
	return {
		"exists": true,
		"chapter_id": chapter.get("current_chapter_id", ""),
		"time_played_sec": float(data.get("time_played_sec", 0.0)),
		"timestamp": int(data.get("timestamp", 0)),
	}

## 回所有 slot（3 手動 + auto）的 info，附 slot 與 is_auto 欄位。
func list_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for s: int in MANUAL_SLOTS:
		var info: Dictionary = get_slot_info(s)
		info["slot"] = s
		info["is_auto"] = false
		result.append(info)
	var auto_info: Dictionary = get_slot_info(AUTO_SLOT)
	auto_info["slot"] = AUTO_SLOT
	auto_info["is_auto"] = true
	result.append(auto_info)
	return result

# ── Autosave ────────────────────────────────────────────────────────────────
func _on_autosave_tick() -> void:
	# 只在探索狀態存，避免存到 cutscene/對話/載入中的中間狀態
	if GameManager.current_state == GameManager.GameState.EXPLORING:
		if save_to_slot(AUTO_SLOT):
			EventBus.hud_message_requested.emit("已自動存檔", 2.0)
```

- [ ] **Step 3: 建立測試檔，寫存檔 round-trip 測試**

Create `game/src/test/test_save_system.gd`:

```gdscript
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
	var ok: bool = save.save_to_slot(99)  # 用 99 當測試專用 slot
	_assert(ok, "save_to_slot 成功")
	_assert(save.has_slot(99), "存檔檔案存在")
	var info: Dictionary = save.get_slot_info(99)
	_assert(info.get("exists", false) == true, "get_slot_info exists")
	# 清掉測試檔
	DirAccess.remove_absolute(save._slot_path(99))
	_assert(not save.has_slot(99), "測試檔已刪除")
```

- [ ] **Step 4: 跑測試確認通過**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_save_system.gd`
Expected: `[save round-trip]` 全 PASS，`ALL PASS`，離開碼 0。

- [ ] **Step 5: Commit**

```bash
git add game/src/autoload/SaveManager.gd game/project.godot game/src/test/test_save_system.gd
git commit -m "feat(save): SaveManager autoload with save + slot query + autosave timer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: 載入編排 `_apply_save_data` — 修順序 bug（核心）

**Why:** 修「chapter 早於 quest」「era 濾鏡要套」的 bug。抽成不含場景 reload 的純編排函式，可 headless 測試順序。

**Files:**
- Modify: `game/src/autoload/SaveManager.gd`
- Test: `game/src/test/test_save_system.gd`

- [ ] **Step 1: 寫失敗測試（驗證載入後 chapter 先於 quest，信任 trigger 補回）**

在 `test_save_system.gd` 的 `_run_tests()` 加 `_test_apply_order()`，並新增方法：

```gdscript
func _test_apply_order() -> void:
	print("[apply_save_data 載入順序]")
	var save: Node = get_root().get_node("SaveManager")
	var sm: Node = get_root().get_node("StoryManager")
	var qm: Node = get_root().get_node("QuestManager")
	_reset_story(sm)
	qm._active_quests.clear()
	qm._completed_quests.clear()
	# 構造一份「lin_rongchang 信任已達 60」的存檔狀態：
	# 載入後 ChapterManager re-register 會補回 trigger，Quest reevaluate 應看到 ch1_rongchang_trust_ok。
	var data: Dictionary = {
		"story": {
			"completed_events": ["ch1_first_travel_done", "ch1_started_living_in_pharmacy"],
			"player_flags": {"started_pharmacy_work": true},
			"npc_relationships": {"lin_rongchang": 60},
			"unlocked_zones": ["zone_apartment_muzha"],
			"conversation_histories": {},
			"current_zone": "zone_pharmacy",
			"game_time_hours": 14.0,
		},
		"chapter": {"current_chapter_id": "ch01_arrival"},
		"quests": {"active_quests": [], "completed_quests": []},
		"era": {"current_era": "1983"},
		"time_played_sec": 123.0,
	}
	save.apply_save_data(data)
	# chapter 已載 → events.gd re-register → trigger 補回；但信任事件要在 update 時才 record。
	# 這裡驗證：載入後 story 狀態正確、章節正確、時間正確。
	_assert(sm.player_flags.get("started_pharmacy_work", false) == true, "flags 還原")
	_assert(sm.completed_events.has("ch1_started_living_in_pharmacy"), "events 還原")
	_assert(sm.npc_relationships.get("lin_rongchang", 0) == 60, "信任值還原")
	var cm: Node = get_root().get_node("ChapterManager")
	_assert(cm.current() != null and cm.current().chapter_id == "ch01_arrival", "章節還原")
	_assert(sm._relationship_triggers.size() > 0, "章節 re-register 補回信任 trigger")
	_assert(GameManager.get_time_played_sec() == 123.0, "遊玩時間還原")
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_save_system.gd`
Expected: FAIL — `Nonexistent function 'apply_save_data'`。

- [ ] **Step 3: 實作 apply_save_data（純編排，正確順序）**

在 `SaveManager.gd` 的 Autosave 區塊之前新增：

```gdscript
# ── Load 編排 ───────────────────────────────────────────────────────────────
## 依正確順序把存檔資料套回各 manager（不含場景 reload — 供 load_from_slot 與測試共用）。
## 順序關鍵：Story（flags/events）→ Chapter（re-register events，補回 _relationship_triggers）
## → Quest（reevaluate 此時看得到完整 triggers）→ Era；最後還原 GameManager runtime。
func apply_save_data(data: Dictionary) -> void:
	if data.has("story"):
		StoryManager.deserialize(data["story"])
	if data.has("chapter"):
		ChapterManager.deserialize(data["chapter"])
	if data.has("quests"):
		QuestManager.deserialize(data["quests"])
	if data.has("era"):
		EraManager.deserialize(data["era"])
	var time_played: float = float(data.get("time_played_sec", 0.0))
	var player_data: Dictionary = data.get("player", {})
	var pos: Vector2 = Vector2(
		float(player_data.get("position_x", 0.0)),
		float(player_data.get("position_y", 0.0))
	)
	GameManager.apply_loaded_runtime(time_played, pos)
```

- [ ] **Step 4: 跑測試確認通過**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_save_system.gd`
Expected: `[apply_save_data 載入順序]` 全 PASS，`ALL PASS`。

- [ ] **Step 5: Commit**

```bash
git add game/src/autoload/SaveManager.gd game/src/test/test_save_system.gd
git commit -m "feat(save): apply_save_data orchestrates deserialize in correct order

Fixes load-order bug: ChapterManager (re-registers events, restores
_relationship_triggers) now runs before QuestManager (reevaluate needs them).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `load_from_slot` — 重載場景 + 套 zone/era

**Why:** 完整載入流程：讀檔 → 重載主場景（乾淨起始）→ apply_save_data → 跳存檔 zone → 套 era 濾鏡。場景 reload 非 headless 可測，故把可測的讀檔/解析跟不可測的 reload 分開。

**Files:**
- Modify: `game/src/autoload/SaveManager.gd`
- Test: `game/src/test/test_save_system.gd`

- [ ] **Step 1: 寫測試（讀檔解析容錯）**

在 `_run_tests()` 加 `_test_load_parse()`，並新增：

```gdscript
func _test_load_parse() -> void:
	print("[load 讀檔解析]")
	var save: Node = get_root().get_node("SaveManager")
	# 不存在的 slot → read_slot_data 回空 dict
	_assert(save.read_slot_data(98).is_empty(), "不存在 slot 回空 dict")
	# 存一份再讀回
	var sm: Node = get_root().get_node("StoryManager")
	_reset_story(sm)
	sm.set_flag("rk", true)
	save.save_to_slot(97)
	var d: Dictionary = save.read_slot_data(97)
	_assert(not d.is_empty(), "讀回非空")
	_assert(d.get("story", {}).get("player_flags", {}).get("rk", false) == true, "讀回內容正確")
	DirAccess.remove_absolute(save._slot_path(97))
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_save_system.gd`
Expected: FAIL — `Nonexistent function 'read_slot_data'`。

- [ ] **Step 3: 實作 read_slot_data + load_from_slot + delete_slot**

在 SaveManager 的 `apply_save_data` 之後新增：

```gdscript
## 讀檔並解析 JSON。不存在/壞檔回空 Dictionary。
func read_slot_data(slot: Variant) -> Dictionary:
	if not has_slot(slot):
		return {}
	var file: FileAccess = FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		push_error("SaveManager: corrupt save slot %s" % str(slot))
		return {}
	file.close()
	return json.data

## 完整載入：讀檔 → 重載主場景 → 套狀態 → 跳 zone → 套 era 濾鏡。回是否成功。
func load_from_slot(slot: Variant) -> bool:
	var data: Dictionary = read_slot_data(slot)
	if data.is_empty():
		EventBus.hud_message_requested.emit("讀取存檔失敗", 2.0)
		save_failed.emit(slot, "讀檔失敗")
		return false
	GameManager.change_state(GameManager.GameState.LOADING)
	# 重載主場景取得乾淨起始（與 return_to_main_menu 同機制）
	get_tree().reload_current_scene()
	# 等一幀讓場景樹（含 ZoneManager）_ready 完成
	await get_tree().process_frame
	await get_tree().process_frame
	# 依正確順序套回狀態
	apply_save_data(data)
	# 跳到存檔 zone（ZoneManager transition 尾端會 apply_to_current_zone 套 era）
	var player_data: Dictionary = data.get("player", {})
	var zone_id: String = player_data.get("zone", "zone_apartment_muzha")
	EventBus.zone_transition_requested.emit(zone_id, "default")
	# 保險：再顯式套一次 era 視覺
	EraManager.apply_to_current_zone()
	GameManager.change_state(GameManager.GameState.EXPLORING)
	print("SaveManager: loaded slot %s" % str(slot))
	load_completed.emit(slot)
	EventBus.hud_message_requested.emit("遊戲已載入", 2.0)
	return true

## 刪除手動 slot 檔案（auto slot 不開放刪除由 UI 控制）。
func delete_slot(slot: Variant) -> void:
	if has_slot(slot):
		DirAccess.remove_absolute(_slot_path(slot))
```

- [ ] **Step 4: 跑測試確認通過**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_save_system.gd`
Expected: `[load 讀檔解析]` 全 PASS，`ALL PASS`。

- [ ] **Step 5: Commit**

```bash
git add game/src/autoload/SaveManager.gd game/src/test/test_save_system.gd
git commit -m "feat(save): load_from_slot reloads scene then applies state + era tint

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: autosave 安全閘測試

**Why:** 驗證「只在 EXPLORING 存」——非探索狀態 timer timeout 不寫 auto 檔。

**Files:**
- Modify: `game/src/test/test_save_system.gd`

- [ ] **Step 1: 寫測試**

在 `_run_tests()` 加 `_test_autosave_gate()`，並新增：

```gdscript
func _test_autosave_gate() -> void:
	print("[autosave 安全閘]")
	var save: Node = get_root().get_node("SaveManager")
	save.delete_slot(SaveManagerAuto())
	# 非 EXPLORING（PAUSED）→ tick 不應寫檔
	GameManager.change_state(GameManager.GameState.PAUSED)
	save._on_autosave_tick()
	_assert(not save.has_slot("auto"), "PAUSED 時不自動存檔")
	# EXPLORING → tick 應寫檔
	GameManager.change_state(GameManager.GameState.EXPLORING)
	save._on_autosave_tick()
	_assert(save.has_slot("auto"), "EXPLORING 時自動存檔")
	save.delete_slot("auto")

func SaveManagerAuto() -> String:
	return "auto"
```

- [ ] **Step 2: 跑測試確認通過**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_save_system.gd`
Expected: `[autosave 安全閘]` 全 PASS，`ALL PASS`。

- [ ] **Step 3: Commit**

```bash
git add game/src/test/test_save_system.gd
git commit -m "test(save): autosave gate only writes in EXPLORING state

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: SaveLoadPanel UI 場景

**Why:** 清單式存讀檔面板，列 3 手動 + 1 auto，可存/讀/刪。

**Files:**
- Create: `game/src/ui/menus/SaveLoadPanel.tscn`
- Create: `game/src/ui/menus/SaveLoadPanel.gd`

- [ ] **Step 1: 建立場景 .tscn**

Create `game/src/ui/menus/SaveLoadPanel.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://muzha_saveload_panel"]

[ext_resource type="Script" path="res://src/ui/menus/SaveLoadPanel.gd" id="1_saveload"]

[node name="SaveLoadPanel" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
process_mode = 3
script = ExtResource("1_saveload")

[node name="Panel" type="Panel" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -220.0
offset_top = -180.0
offset_right = 220.0
offset_bottom = 180.0
grow_horizontal = 2
grow_vertical = 2

[node name="VBox" type="VBoxContainer" parent="Panel"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 16.0
offset_top = 12.0
offset_right = -16.0
offset_bottom = -12.0

[node name="Title" type="Label" parent="Panel/VBox"]
layout_mode = 2
text = "存檔"
theme_override_font_sizes/font_size = 18

[node name="Sep" type="HSeparator" parent="Panel/VBox"]
layout_mode = 2

[node name="SlotList" type="VBoxContainer" parent="Panel/VBox"]
layout_mode = 2
size_flags_vertical = 3

[node name="CloseButton" type="Button" parent="Panel/VBox"]
layout_mode = 2
text = "關閉"
```

- [ ] **Step 2: 建立面板程式**

Create `game/src/ui/menus/SaveLoadPanel.gd`:

```gdscript
## SaveLoadPanel — 清單式存讀檔面板
## 模式：SAVE（點手動位存）/ LOAD（點任一位讀）。auto 位唯讀。
class_name SaveLoadPanel
extends Control

enum Mode { SAVE, LOAD }

@onready var _title: Label = $Panel/VBox/Title
@onready var _slot_list: VBoxContainer = $Panel/VBox/SlotList
@onready var _close_btn: Button = $Panel/VBox/CloseButton

var _mode: Mode = Mode.SAVE

func _ready() -> void:
	UIManager.register("SaveLoadPanel", self)
	_close_btn.pressed.connect(func() -> void: UIManager.pop())

## 開啟面板（指定模式）。由 PauseMenu / MainMenu 呼叫。
func open(mode: Mode) -> void:
	_mode = mode
	_title.text = "存檔" if mode == Mode.SAVE else "讀檔"
	_refresh()
	UIManager.push("SaveLoadPanel")

func _refresh() -> void:
	for child: Node in _slot_list.get_children():
		child.queue_free()
	for info: Dictionary in SaveManager.list_slots():
		_slot_list.add_child(_make_row(info))

func _make_row(info: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var slot: Variant = info["slot"]
	var is_auto: bool = info["is_auto"]
	var label: Label = Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	label.text = _row_text(info)
	row.add_child(label)

	# SAVE 模式：手動位給「存」鈕（auto 唯讀）
	if _mode == Mode.SAVE and not is_auto:
		var save_btn: Button = Button.new()
		save_btn.text = "存"
		save_btn.pressed.connect(func() -> void:
			SaveManager.save_to_slot(slot)
			_refresh()
		)
		row.add_child(save_btn)
	# LOAD 模式：有存檔才給「讀」鈕
	if _mode == Mode.LOAD and info.get("exists", false):
		var load_btn: Button = Button.new()
		load_btn.text = "讀"
		load_btn.pressed.connect(func() -> void:
			UIManager.pop_all()
			SaveManager.load_from_slot(slot)
		)
		row.add_child(load_btn)
	# 手動位有存檔可刪
	if not is_auto and info.get("exists", false):
		var del_btn: Button = Button.new()
		del_btn.text = "刪"
		del_btn.pressed.connect(func() -> void:
			SaveManager.delete_slot(slot)
			_refresh()
		)
		row.add_child(del_btn)
	return row

func _row_text(info: Dictionary) -> String:
	var slot: Variant = info["slot"]
	var name_part: String = "自動存檔" if info["is_auto"] else "存檔 %s" % str(slot)
	if not info.get("exists", false):
		return "%s ：（空）" % name_part
	var chapter_id: String = info.get("chapter_id", "")
	var secs: int = int(info.get("time_played_sec", 0.0))
	var hh: int = secs / 3600
	var mm: int = (secs % 3600) / 60
	return "%s ：%s ｜遊玩 %02d:%02d" % [name_part, chapter_id, hh, mm]
```

- [ ] **Step 3: 語法檢查**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --check-only --script res://src/ui/menus/SaveLoadPanel.gd`
Expected: 無 parse error（autoload identifier 警告可忽略）。

- [ ] **Step 4: Commit**

```bash
git add game/src/ui/menus/SaveLoadPanel.gd game/src/ui/menus/SaveLoadPanel.tscn
git commit -m "feat(ui): SaveLoadPanel list-style save/load panel

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: 接線 — main_world 加面板、PauseMenu/MainMenu 改走 SaveLoadPanel

**Why:** 把新面板掛進場景樹並讓選單開它，移除舊的直接存 slot 1。

**Files:**
- Modify: `game/src/maps/main_world.tscn`
- Modify: `game/src/ui/menus/PauseMenu.gd`
- Modify: `game/src/ui/menus/MainMenu.gd`

- [ ] **Step 1: main_world 加 SaveLoadPanel 實例**

在 `game/src/maps/main_world.tscn`，找到 `[ext_resource ... QuestJournal.tscn ...]` 那行下方加：

```
[ext_resource type="PackedScene" path="res://src/ui/menus/SaveLoadPanel.tscn" id="12_saveload"]
```

並在 `[node name="QuestJournal" parent="UILayer" ...]` 區塊後加（id 用上面的）：

```
[node name="SaveLoadPanel" parent="UILayer" instance=ExtResource("12_saveload")]
```

（注意：實作時對照檔案實際的 ext_resource id 命名慣例與 UILayer 節點路徑；若 QuestJournal 的 instance 行有 `unique_id=...` 屬性則比照，沒有則省略。）

- [ ] **Step 2: PauseMenu 改走面板**

修改 `game/src/ui/menus/PauseMenu.gd` 的 `_on_save` 與 `_on_load`：

```gdscript
func _on_save() -> void:
	var panel: SaveLoadPanel = UIManager.get_panel("SaveLoadPanel") as SaveLoadPanel
	if panel != null:
		panel.open(SaveLoadPanel.Mode.SAVE)

func _on_load() -> void:
	var panel: SaveLoadPanel = UIManager.get_panel("SaveLoadPanel") as SaveLoadPanel
	if panel != null:
		panel.open(SaveLoadPanel.Mode.LOAD)
```

並把 `_update_info`（:39）的 `_load_btn.disabled = not GameManager.has_save(1)` 改為：

```gdscript
	_load_btn.disabled = false
```

（載入面板自己會顯示空位，不需在這裡擋。）

- [ ] **Step 3: MainMenu 改走面板**

修改 `game/src/ui/menus/MainMenu.gd`：把 `_on_load`（:24-26）改為：

```gdscript
func _on_load() -> void:
	var panel: SaveLoadPanel = UIManager.get_panel("SaveLoadPanel") as SaveLoadPanel
	if panel != null:
		panel.open(SaveLoadPanel.Mode.LOAD)
```

並把 `_ready`（:14）的 `_load_btn.disabled = not GameManager.has_save(1)` 改為：

```gdscript
	_load_btn.disabled = not (SaveManager.has_slot(1) or SaveManager.has_slot(2) or SaveManager.has_slot(3) or SaveManager.has_slot("auto"))
```

- [ ] **Step 4: 確認沒有殘留舊 API 呼叫**

Run: `grep -rn "GameManager.save_game\|GameManager.load_game\|GameManager.has_save\|GameManager.get_save_info" game/src`
Expected: 無輸出（全部已改走 SaveManager / SaveLoadPanel）。

- [ ] **Step 5: 語法檢查 + 回歸測試**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --check-only --script res://src/ui/menus/PauseMenu.gd`
Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --script res://src/test/test_save_system.gd`
Expected: 無 parse error；測試 `ALL PASS`。

- [ ] **Step 6: Commit**

```bash
git add game/src/maps/main_world.tscn game/src/ui/menus/PauseMenu.gd game/src/ui/menus/MainMenu.gd
git commit -m "feat(ui): wire PauseMenu/MainMenu to SaveLoadPanel; drop direct slot-1 save/load

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: 手動驗證（編輯器）

**Why:** UI 互動與場景 reload 載入流程 headless 測不到，需目視確認。

- [ ] **Step 1: 存讀檔流程**

開遊戲 → 新遊戲 → 走到藥行（記住位置/章節）→ 暫停選單「儲存」→ 存到存檔 1 → 繼續玩、換 zone → 暫停「載入」→ 讀存檔 1 → 確認：(a) 回到存檔時的 zone 與位置；(b) era 濾鏡正確（不是錯的時空色調）；(c) journal 任務進度一致。

- [ ] **Step 2: 自動存檔**

玩超過 5 分鐘（或暫時把 `AUTOSAVE_INTERVAL_SEC` 改小測試）→ 確認 HUD 跳「已自動存檔」、存讀檔面板 auto 位有資料、auto 位無「存」「刪」鈕只有「讀」。

- [ ] **Step 3: 主選單載入**

回主選單 → 「載入」→ 面板列出所有存檔 → 讀任一檔 → 確認正確進入。

---

## Self-Review 紀錄

- **Spec 覆蓋：** §3 SaveManager autoload→Task 2；§4 載入時序修復→Task 3（apply_save_data 順序）+Task 4（reload+era）；§5 autosave→Task 2（timer）+Task 5（閘測試）；§6 UI→Task 6+7；§7 _relationship_triggers 不存（靠 chapter re-register）→Task 3 驗證；§8 錯誤處理→Task 4（read_slot_data 容錯）；§9 測試→Task 2-5。
- **型別一致：** `save_to_slot`/`load_from_slot`/`apply_save_data`/`read_slot_data`/`get_slot_info`/`list_slots`/`has_slot`/`delete_slot` 簽章各 task 一致；GameManager `collect_player_position`/`get_time_played_sec`/`apply_loaded_runtime` 在 Task 1 定義、Task 2/3 引用一致。
- **與 spec 一致：** 3 手動+auto、只 EXPLORING autosave、auto 唯讀、chapter 早於 quest、era 顯式套。
- **無 placeholder：** 各步驟含完整程式碼與指令。Task 7 Step1 的 .tscn id 命名標註「對照實際慣例」是因 scene 檔 id 需配合現有檔案，非 placeholder。
- **YAGNI：** 無截圖、無雲端、無 migration（spec 非目標）。
