# 存檔系統重整設計（修載入 bug + 多存檔位 + 自動存檔）

- 日期：2026-05-31
- 範圍：把存檔邏輯抽成 `SaveManager` autoload；修正載入時序/視覺狀態套不回的 bug；加 3 手動 + 1 自動存檔位；加定時自動存檔；加清單式存讀檔 UI。
- 狀態：草案，待使用者 review。

---

## 1. 問題背景（審計結果）

逐一比對每個 manager 的 runtime 狀態 vs `serialize()` 實際存的欄位，結論：

**核心狀態其實有存到**（劇情進度、角色位置、信任、對話歷史、時間、章節、era 都有）。真正的問題是：

1. **載入時序錯**：`GameManager.load_game` 原地依序呼叫 deserialize，但 `QuestManager.deserialize`（內含 `reevaluate()`）跑在 `ChapterManager.deserialize`（re-register events、補回 `_relationship_triggers`）**之前**——reevaluate 當下信任 triggers 還沒補回。
2. **漏套視覺狀態**：`EraManager.deserialize` 只設 `current_era` 變數，**沒呼叫 `apply_to_current_zone()`**——載入後濾鏡/era 可見性是錯的（會停在錯的時空色調），要等下次手動切換才正確。
3. **`_relationship_triggers` 不在存檔內**：它由 `events.gd` 的 `register()` 派生註冊，須靠載入時 ChapterManager re-register 補回——目前順序不保證，很脆弱。
4. **功能缺口**：只有 slot 1、無自動存檔、無存讀檔 UI（save/load 的 slot 參數存在但 UI 沒接）。

## 2. 目標 / 非目標

### 目標
1. 載入存檔後所有狀態（含 era 濾鏡、quest 進度）正確套回。
2. 3 個手動存檔位 + 1 個自動存檔位。
3. 定時自動存檔（只在安全狀態存）。
4. 清單式存讀檔 UI（顯示章節/遊玩時間/存檔時間，可存/讀/刪）。

### 非目標（YAGNI）
- 不做截圖縮圖。
- 不做雲端/跨裝置同步。
- 不做存檔版本遷移（保留 `version` 欄位，但不寫 migration 邏輯）。
- 各 manager 的 `serialize/deserialize` 介面不改（已正確）。

## 3. 架構

把存檔編排從肥大的 `GameManager`（還管 AI server + 狀態機）抽成獨立 **`SaveManager` autoload**（單一職責、可 headless 測試）。各 manager 的 serialize/deserialize 維持不動。

```
SaveManager (新 autoload)
  常數：SAVE_DIR="user://saves/"、SAVE_VERSION、AUTOSAVE_INTERVAL_SEC=300、
        MANUAL_SLOTS=[1,2,3]、AUTO_SLOT="auto"
  ├─ save_to_slot(slot: Variant) -> bool      收集所有 manager serialize → 寫 save_<slot>.json
  ├─ load_from_slot(slot: Variant) -> bool    讀檔 → reload 主場景 → 依序 deserialize → 套 zone/era
  ├─ delete_slot(slot: Variant) -> void       刪手動位檔案
  ├─ has_slot(slot) / get_slot_info(slot)     給 UI
  ├─ list_slots() -> Array[Dictionary]        4 個 slot 的 info
  └─ _autosave_timer: Timer                   定時 → 若 EXPLORING 才 save_to_slot(AUTO_SLOT)
```

autoload 註冊順序：SaveManager 放在 GameManager / StoryManager / ChapterManager / QuestManager / EraManager **之後**（它依賴它們）。

### autoload 依賴方向
SaveManager → 讀寫 StoryManager / QuestManager / ChapterManager / EraManager / GameManager（玩家位置、time_played、current_state）。不反向依賴。

## 4. 載入時序修復（核心）

`load_from_slot(slot)` 流程（重載場景再套）：

```
1. 讀 save_<slot>.json、解析 JSON。失敗 → 回報錯誤、保持現況、return false。
2. 暫存 _pending_save_data = data；GameManager.change_state(LOADING)。
3. reload 主場景（get_tree().reload_current_scene()，跟 return_to_main_menu 同機制，得到乾淨起始）。
4. 場景 _ready 後（SaveManager 監看一個 deferred hook 或 main_world 回呼）套狀態，順序：
     a. StoryManager.deserialize(data["story"])        # flags/events 先就位
     b. ChapterManager.deserialize(data["chapter"])    # 先於 quest！re-register events → 補回 _relationship_triggers
     c. QuestManager.deserialize(data["quests"])       # 後於 chapter！reevaluate 此時看得到完整 triggers
     d. EraManager.deserialize(data["era"])            # 設 current_era 變數
     e. GameManager 還原 _time_played_sec
5. 跳到存檔 zone：EventBus.zone_transition_requested.emit(zone_id, "default")；記 _pending_load_position 定位玩家。
6. zone 載完（ZoneManager 在 transition 尾端已呼叫 apply_to_current_zone）→ era 濾鏡/可見性正確套上。
   （保險：load 尾端再顯式呼叫一次 EraManager.apply_to_current_zone()。）
7. GameManager.change_state(EXPLORING)。
```

**關鍵改動 vs 現況**：
- chapter **早於** quest（修信任 trigger 時序）。
- 明確保證 era 視覺在 zone 載入後套上。
- 重載場景 → 無殘留節點/狀態。

### 場景重載後如何接續套狀態
`reload_current_scene()` 是非同步的（下一幀才完成）。SaveManager 用 `call_deferred` 或等一幀後，確認 main_world 的 ZoneManager 已 `_ready`，再跑步驟 4。實作時以 `await get_tree().process_frame` 等到場景樹就緒（細節在 plan 定）。

## 5. 自動存檔
- SaveManager 內建 `Timer`，`AUTOSAVE_INTERVAL_SEC = 300`（5 分鐘，常數可調）。
- `_ready` 啟動 timer；`timeout` 時：
  - 若 `GameManager.current_state == GameState.EXPLORING` → `save_to_slot(AUTO_SLOT)`，發 HUD「已自動存檔」。
  - 否則（DIALOGUE/PAUSED/LOADING/cutscene）→ 跳過，等下一個間隔。
- AUTO_SLOT 永不被手動存檔覆蓋；UI 上 auto 位唯讀（只能讀、不能存/刪）。

## 6. 存讀檔 UI（清單式面板）
- 新場景 `SaveLoadPanel`（Control），透過 UIManager push/pop。
- 列出 4 列：slot 1/2/3（手動）+ auto（自動）。每列顯示：
  - 章節 display_name、遊玩時間（時:分）、存檔時間戳；空位顯示「（空）」。
- 兩種模式（開啟時指定）：
  - **存檔模式**（PauseMenu「儲存」）：點手動位 → `save_to_slot`。auto 位唯讀。
  - **讀檔模式**（PauseMenu/MainMenu「載入」）：點任一位（含 auto）→ `load_from_slot`。
- 刪除：手動位可刪（`delete_slot`）；auto 位不可刪。
- 接線：PauseMenu 的「儲存」「載入」改開此面板（取代現在直接存 slot 1）；MainMenu「載入」開讀檔模式。

## 7. 補漏存欄位
- `_relationship_triggers` **不寫入存檔**——由 events.gd `register()` 派生，靠載入時 ChapterManager re-register 補回（§4 已保證順序）。符合 SSOT：可重新推導者不另存。
- 其餘狀態審計皆已存，無需新增欄位。

## 8. 錯誤處理
- 讀檔失敗（檔案不存在/JSON 壞）：回報 false + HUD 訊息，不改變現況（不要把遊戲弄到半殘狀態）。
- 寫檔失敗（目錄建不出/磁碟）：push_error + HUD 訊息，回 false。
- 載入舊版存檔（version 不符）：本版不做 migration；偵測到不同 version 時照常嘗試載入（欄位用 `.get(..., default)` 容錯，已是現況寫法）。

## 9. 測試策略
- **save/load round-trip（headless）**：設定 StoryManager/Quest/Chapter/Era 一組已知狀態 → `save_to_slot(1)` → 改動狀態 → `load_from_slot(1)`（測試模式下跳過場景 reload，直接跑 deserialize 順序）→ 斷言狀態還原。
- **載入順序**：驗證 chapter 先於 quest——構造一個「信任已達門檻」的存檔，載入後 `_relationship_triggers` 已補回且對應 quest 完成。
- **autosave 安全閘**：current_state 非 EXPLORING 時 timer timeout → auto 檔不被寫。
- **slot 隔離**：存 slot 1 不影響 slot 2/auto；`list_slots` 回正確 info。
- **空位/壞檔容錯**：`get_slot_info` 對不存在/壞 JSON 回空 dict 不崩。
- UI 互動（點存/讀/刪）非 headless，列為手動驗證。
- 測試沿用既有 headless `SceneTree` harness（`game/src/test/`）。

## 10. 待實作時確認
- 場景 reload 後接續套狀態的確切 hook（`await process_frame` vs main_world 回呼）——plan 階段定，需確認 ZoneManager `_ready` 完成時機。
- SaveLoadPanel 的實際節點結構（沿用 QuestJournal 的程式生成 row 風格 vs .tscn 排版）。
- 為可測性，`load_from_slot` 是否拆出「純 deserialize 編排」子函式（不含場景 reload），讓 headless 測試直接驗證順序。
