# 對話系統 × 任務系統關聯設計 + 第一章任務列表

- 日期：2026-05-31
- 範圍：建立 NPC 對話/劇情（StoryBeat/BeatRunner）與任務（QuestManager/QuestData）之間的正確關聯，並依第一章「鐵門後的那個人」劇情產出任務列表。
- 狀態：草案，待使用者 review。

---

## 1. 問題背景

調查結論（GDScript / Godot scene，不在 codegraph 內，以 Grep/Read 確認）：

- **對話系統**（`StoryBeat` + `BeatRunner` + `DialogueUI` + `TrustGate`）已完整實作並運作。
- **任務系統**（`QuestManager` autoload + `QuestData`）已完整實作：載入、自動開始/完成、發 `quest_started/completed/available` 訊號。
- **兩者目前沒有刻意連結**。唯一隱性耦合：都監聽 `StoryManager.event_recorded`。
- `QuestManager` **只掃 `res://src/quests/` 全域資料夾**，不讀章節資料夾；第一章 `quests/` 只有 `.gitkeep`，`chapter.tres` 的 `quests = []`。
- `ChapterManager.get_current_stage()` → `ChapterConfig.resolve_stage(player_flags)`：stage **純由 `StoryManager.flags` 經 `stage_rules` 推導**，綁在 `event_recorded` / `flag_changed` 自動更新；`TrustGate.build_system_prompt()` 再用 `story_stage` + `stage_order` 組 NPC prompt。→「NPC 答話符合故事階段」架構上已成立。

### 兩個狀態存放區（重要）
- `StoryManager.flags`：Dictionary（beat 的 `trigger_flags` / `set_flags` / `on_complete_flags`、stage_rules 都用這個）。
- `StoryManager.completed_events`：Set（beat 的 `on_complete_event`、`QuestData.completion_events` 用這個）。
- 設計需同時相容兩者（見 §4 objectives 條件）。

## 2. 目標 / 非目標

### 目標
1. 給「開放探索」玩家一個**引導層**：自由探索後仍能找到主線推進方向（只指路、不擋路）。
2. 保證 NPC 在不同階段答話符合邏輯（沿用既有 stage 機制，不另造真相）。
3. 依第一章劇情產出可實作的任務列表，掛接既有事件/flag。

### 非目標（YAGNI）
- 不做完整雙向整合（beat 主動發 `quest_offered`、任務反寫 beat 觸發條件）。
- 不做戰鬥/物品任務。
- 第一章不做「對話 accept/decline 接任務」流程（與開放探索手感衝突）。

## 3. 核心設計：任務 = 事件真相的「玩家可見投影」

```
            StoryManager.flags / completed_events
            （唯一真相 SSOT；由 beat 完成 / 探索觸發 / cutscene 寫入）
                  │
    ┌─────────────┴─────────────┐
    ▼                            ▼
 stage_rules 推導 stage      quest objectives 比對
 → TrustGate 組 NPC prompt   → QuestManager 自動開始 / 完成 / 逐項打勾
 →「答話符合階段」           →「引導玩家找主線方向」
```

- stage 與 quest 是同一份事件真相的兩個**投影**，彼此不互相寫入。
- 任務**復用 beat 既有的 event / flag**，不發明平行 flag。
- 完成任務所需條件被滿足時，stage 同步前進 → NPC 態度自動跟上，無需額外同步邏輯。
- 符合專案原則：SSOT、能從 authoritative source 推導者不另加手動 flag。

### 採用的設計決策
- **觸發方式：自動麵包屑**。主線任務隨進度自動浮現/完成（`QuestManager` 已支援），journal 永遠顯示「現在往哪走」。
- **粒度：多步驟 objectives**。每個任務含一串 objective，逐項在 journal 打勾，作為自由探索的明確指引。
- **信任門檻 → 派生事件：現在就加**通用掛鉤（值是真相、事件是派生，非冗餘 flag）。

## 4. 架構改動

| # | 改動 | 檔案 | 為何 |
|---|---|---|---|
| 1 | `QuestData` 加 `objectives` 欄位（見下）；`QuestManager` 改以 objectives 判定完成 + 對外提供逐項完成狀態 | `core/classes/QuestData.gd`, `autoload/QuestManager.gd` | 多步驟引導需求 |
| 2 | `QuestManager` 除掃 `res://src/quests/`，也掃 `game/src/chapters/<id>/quests/*.tres` 並與全域池合併 | `autoload/QuestManager.gd` | 章節任務目前未被載入 |
| 3 | `StoryManager` 加「relationship 跨門檻 → `record_event` 派生事件」通用掛鉤（去重） | `autoload/StoryManager.gd` | 信任步驟能當 objective 條件，不加平行 flag |
| 4 | 補記錄目前只有 flag、缺對應引導錨的開場/關鍵節點事件（見 §6） | 穿越觸發處 / locked-room cutscene | objective 需可觀測條件 |
| 5 | Quest journal 顯示任務 `description` + objectives 逐項打勾，善用 `giver_npc_id/target_zone/target_npc_id` | `ui/menus/QuestJournal.gd` | 麵包屑指路 |
| 6 |（選配）`TrustGate.build_system_prompt()` 帶入「玩家當前主線任務」一行 | `core/classes/TrustGate.gd` | 讓 NPC 順口提點方向 |

### QuestData.objectives schema（提案）
```gdscript
@export var objectives: Array = []
# 每項：{
#   "id":   "talk_xiaowei",          # 任務內唯一
#   "desc": "向堂叔林小威打聽家裡沒人提的叔叔",  # journal 顯示
#   "event": "ch1_xiaowei_talked",   # 滿足條件(二選一)：completed_events 含此
#   "flag":  "saw_ama_incense",      # 或 flags 內此鍵為 true
#   "optional": false                # true=不影響完成，只作支線提示
# }
```
- 一個 objective 提供 `event` 或 `flag` 其一即可（相容兩個存放區，避免為已是 flag 的里程碑硬加事件）。
- 任務完成 = 所有非 `optional` objective 滿足。`completion_events` 保留為選配額外條件（通常空）。
- `QuestManager` 在 `event_recorded` / `flag_changed` 時重評 objectives，發既有 `quest_completed`；逐項狀態供 journal 查詢。

## 5. 第一章任務列表

✅=事件/flag 已存在　▲=需新增（見 §6）。字串均已對照 beat `.tres` 確認。

### 5.1 主線（自動麵包屑）

**MQ01 ｜鐵門後** — stage s1_newcomer，開章自動開始
- obj 進入塵封四十年的榮昌中藥行（現代） — `flag: ch1_entered_pharmacy_modern` ▲
- obj 找到櫃台抽屜的古地圖、觸碰紅點穿越 — `flag: first_time_traveled` ✅

**MQ02 ｜1983 的陌生人** — s1→s2，required `first_time_traveled`
- target: lin_rongchang @ zone_pharmacy(1983)
- obj 跟櫃台後的中年男子攀談，編個身分留下來 — `event: ch1_started_living_in_pharmacy` ✅
  （beat `ch1_meet_lin_rongchang`，同時 set `started_pharmacy_work` → stage 進 s2）

**MQ03 ｜榮昌中藥行的學徒** — s2_working，required `started_pharmacy_work`
- giver/target: lin_rongchang；跑腿 @ zone_market
- obj 取得林榮昌的基礎信任 — `event: ch1_rongchang_trust_ok` ▲（信任門檻派生）
- obj（optional）替祖父跑腿送藥 — `event: ch1_errand_done` ▲（可選，做不做都行）

**MQ04 ｜不對勁的三件事** — s2→s3，required `started_pharmacy_work`（調查任務，多 objective 主場）
- obj 向堂叔林小威打聽沒人提的叔叔 — `event: ch1_xiaowei_talked` ✅（beat 同時 set `clue_locked_room`）
- obj 撞見阿嬤在後院燒香 — `flag: saw_ama_incense` ✅（AMA_INCENSE cutscene）
- obj（optional）找律師對質「祖父林榮昌」的矛盾 — `event: ch1_lawyer_visited` ✅

**MQ05 ｜後院上鎖的房間** — s3_secret，required `clue_locked_room` + `saw_ama_incense`
- target: lin_ama → zone_pharmacy_backyard
- obj 取得阿嬤信任、拿到後院鑰匙 — `event: ch1_got_key` ✅（beat `ch1_ama_trust_key`，set `got_locked_room_key`）
- obj 進入房間找到林榮華的遺物 — `flag: found_ronghua_relic` ✅（ENTER_LOCKED_ROOM cutscene；▲ 確認此 flag 確由 cutscene 寫入）→ stage 進 s4

**MQ06 ｜通關之夜：那個名字** — s4_finale，required `found_ronghua_relic`
- target: lin_rongchang
- obj 帶遺物去找祖父 — `event: ch1_relic_shown` ✅（beat `ch1_show_relic_to_rongchang`，set `finale_night_ready`）
- obj 在長對話中引導他親口說出名字 — `event: ch1_finale_said_brother_name` ✅（beat `ch1_finale_say_name`）
- reward_event: `ch1_chapter_complete`

### 5.2 支線（選配，可獨立或併入 MQ04）
- **SQ-B 老周的繞圈話**（現代）— `event: ch1_met_lao_zhou` ✅（beat `ch1_meet_lao_zhou`）
- **SQ-E 阿桃姨知道的事** — `event: ch1_atao_truth` ▲（a_tao_yi 信任門檻派生）

## 6. 需新增的事件 / 掛鉤（▲ 清單）

| 項目 | 記錄於（authoritative source） | 用途 |
|---|---|---|
| `ch1_entered_pharmacy_modern` | OPEN_IRON_DOOR cutscene / 現代藥行 zone 首入 | MQ01 obj1 |
| `ch1_rongchang_trust_ok` | StoryManager relationship→event 掛鉤（lin_rongchang 達門檻） | MQ03 完成 |
| `ch1_errand_done`（選配） | 跑腿送藥互動完成處 | MQ03 optional obj |
| `ch1_atao_truth`（選配） | relationship→event 掛鉤（a_tao_yi 達門檻） | SQ-E |
| 確認 `found_ronghua_relic` 確由 locked-room cutscene 寫入 | ENTER_LOCKED_ROOM cutscene | MQ05 obj2 |

`relationship→event` 掛鉤為通用機制：以 `{npc_id: [{threshold, event_id}]}` 設定，relationship 跨門檻時 `record_event` 一次。

## 7. 測試策略
- **章節掃描**：放章節 quest `.tres`，啟動後確認被載入；`required_events` 滿足時 `quest_started` 發出。
- **objective 逐項**：依序 record `ch1_xiaowei_talked` / set `saw_ama_incense`，確認 MQ04 對應項打勾、全達成才 `quest_completed`，`optional` 不影響完成。
- **flag 或 event 二選一**：分別用 flag-only 與 event-only objective 驗證皆能滿足。
- **stage 同步**：完成 MQ02 後 `get_current_stage()` == `s2_working`，TrustGate 取到 s2 attitude。
- **relationship→event**：lin_rongchang relationship 推過門檻 → 派生事件記錄一次、MQ03 完成、重複跨門檻不重記。
- 以專案既有 Godot 測試方式撰寫。

## 8. 待實作時確認
- `found_ronghua_relic` / `saw_ama_incense` 確切由哪個 cutscene/zone 觸發寫入（決定 ▲ 是否只是「確認」而非「新增」）。
- 現代藥行首入是否已記錄事件（決定 `ch1_entered_pharmacy_modern` 是新增或復用）。
- 信任門檻數值（MQ03 / SQ-E）。
- 選配改動 #6（NPC prompt 帶入當前任務）是否本章納入。
