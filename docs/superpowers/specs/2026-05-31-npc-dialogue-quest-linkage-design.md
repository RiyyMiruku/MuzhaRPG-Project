# 對話系統 × 任務系統關聯設計 + 第一章任務列表

- 日期：2026-05-31
- 範圍：建立 NPC 對話/劇情（StoryBeat/BeatRunner）與任務（QuestManager/QuestData）之間的正確關聯，並依第一章「鐵門後的那個人」劇情產出任務列表。
- 狀態：草案，待使用者 review。

---

## 1. 問題背景

第一輪調查（GDScript / Godot scene，不在 codegraph 內，以 Grep/Read 確認）結論：

- **對話系統**（`StoryBeat` + `BeatRunner` + `DialogueUI` + `TrustGate`）已完整實作並運作。
- **任務系統**（`QuestManager` autoload + `QuestData`）已完整實作：能載入任務、自動開始、自動完成、發 `quest_started/completed/available` 訊號。
- **兩者目前沒有任何刻意連結**。唯一的隱性耦合：兩者都監聽 `StoryManager.event_recorded`。
- `QuestManager` **只掃 `res://src/quests/` 全域資料夾**，完全不讀章節資料夾；第一章 `quests/` 只有 `.gitkeep`，`chapter.tres` 的 `quests = []`。
- 另確認關鍵事實：`ChapterManager._evaluate_stage()` **純粹從 `StoryManager.flags` 經 `stage_rules` 推導 stage**，且綁在 `event_recorded` + `flag_changed` 上自動執行。`TrustGate` 再用 stage 組 NPC system prompt。→「NPC 答話符合故事階段」在架構上已成立。

## 2. 目標 / 非目標

### 目標
1. 給「開放探索」的玩家一個**引導層**：自由探索後仍能找到主線推進方向（任務只指路、不擋路）。
2. 保證 NPC 在不同故事階段對玩家的答話狀態符合邏輯（沿用既有 stage 機制，不另造真相）。
3. 依第一章劇情產出一份可實作的任務列表，掛接既有事件。

### 非目標（YAGNI）
- 不做完整雙向整合（beat 發 `quest_offered`、任務反寫 beat 觸發條件、journal 即時雙向）。
- 不做戰鬥/物品系統相關任務。
- 第一章不做「對話 accept/decline 接任務」流程（與開放探索手感衝突）。

## 3. 核心設計：任務 = 事件真相的「玩家可見投影」

```
                StoryManager.flags / completed_events
                （唯一真相 SSOT；由 beat 完成 / 探索觸發 / cutscene 寫入）
                      │
        ┌─────────────┴─────────────┐
        ▼                            ▼
 stage_rules 推導 stage          quest required/completion_events 比對
 → TrustGate 組 NPC prompt       → QuestManager 自動開始 / 完成
 →「答話符合階段」               →「引導玩家找主線方向」
```

- stage 與 quest 是同一份事件真相的兩個**投影**，彼此不互相寫入。
- 任務**復用 beat 既有的 `on_complete_event` / stage flag**，不發明平行 flag。
- 完成任務所需事件被記錄時，stage 同步前進 → NPC 態度自動跟上，無需額外同步邏輯。
- 符合專案既定原則：SSOT、能從 authoritative source 推導者不另加手動 flag。

### 設計決策（採用的預設，待 review 可改）
- **觸發方式：自動麵包屑**。主線任務隨進度自動浮現/完成（`QuestManager` 已支援），journal 永遠顯示「現在往哪走」。
- **粒度：先不做子目標 objectives**。沿用現有 `completion_events` 陣列（全部達成才算完成）；任務 `description` 寫清楚即作引導。日後再評估是否加 objectives UI。
- **信任門檻 → 派生事件：現在就加**。讓「打底信任」這類步驟能用事件當完成條件（值是真相，事件是派生，非冗餘 flag）。

## 4. 架構改動

| # | 改動 | 檔案 | 為何 |
|---|---|---|---|
| 1 | `QuestManager` 除掃 `res://src/quests/`，也掃 `game/src/chapters/<id>/quests/*.tres` 並與全域池合併 | `game/src/autoload/QuestManager.gd` | 章節任務目前未被載入 |
| 2 | `StoryManager` 加「relationship 跨門檻 → `record_event` 派生事件」掛鉤（值變動時檢查門檻並記錄派生事件，去重） | `game/src/autoload/StoryManager.gd` | 讓信任步驟能當完成條件，不加平行 flag |
| 3 | 穿越觸發點記錄 `ch1_traveled_to_1983`（若尚未記） | 穿越/古地圖觸發處（待確認，可能在 cutscene 或 zone 互動物件） | 開場主線需明確事件 |
| 4 |（選配）`TrustGate.build_system_prompt()` 帶入「玩家當前主線任務」一行 | `game/src/core/classes/TrustGate.gd` | 讓 NPC 能順口提點方向，直接服務引導需求 |
| 5 | Quest journal 顯示 `description` 作 hint，善用既有 `giver_npc_id/target_zone/target_npc_id` | `game/src/ui/menus/QuestJournal.gd` | 麵包屑指路 |

改動 1、2、5 為核心；3 視現況補；4 為選配增益。

## 5. 第一章任務列表

格式：✅=完成/觸發事件已存在　▲=需新增事件或掛鉤。所有事件字串需於實作時對照 beat `.tres` 與 `events.gd` 最終確認。

### 5.1 主線（自動麵包屑）

| ID | 標題 | Stage | required_events | completion_events | 指路 (target) | 備註 |
|---|---|---|---|---|---|---|
| MQ01 | 鐵門後 | s1_newcomer | （開章自動，空陣列） | `ch1_traveled_to_1983` ▲ | zone_pharmacy（現代）/ 找古地圖 | 打開鐵門整理藥行，找到古地圖觸碰紅點穿越 |
| MQ02 | 1983 的陌生人 | s1→s2 | `ch1_traveled_to_1983` | `ch1_started_living_in_pharmacy` ✅(beat `ch1_meet_lin_rongchang`) | lin_rongchang / zone_pharmacy(1983) | 完成同時 set `started_pharmacy_work` → stage 進 s2 |
| MQ03 | 榮昌中藥行的學徒 | s2_working | `ch1_started_living_in_pharmacy` | `ch1_rongchang_trust_ok` ▲(信任門檻派生) | lin_rongchang / zone_market 跑腿 | 自由探索/信任打底的引導錨 |
| MQ04 | 後院那扇鎖著的門 | s2→s3 | `ch1_started_living_in_pharmacy` | `clue_locked_room` ✅(stage flag) | lin_ama / zone_pharmacy_backyard | 關聯 beat `ch1_ama_trust_key`（取得鑰匙） |
| MQ05 | 鑰匙與遺物 | s3_secret | `clue_locked_room` | `found_ronghua_relic` ✅(stage flag) | zone_pharmacy_backyard 上鎖房間 | 進房找到林榮華遺物 → stage 進 s4 |
| MQ06 | 通關之夜：那個名字 | s4_finale | `found_ronghua_relic` | `ch1_finale_said_brother_name` ✅(beat `ch1_finale_say_name`) | lin_rongchang | 關聯 beat `ch1_show_relic_to_rongchang`；reward_event `ch1_chapter_complete` |

### 5.2 支線（選配麵包屑，餵信任 / 線索）

| ID | 標題 | 關聯 beat / 事件 | 備註 |
|---|---|---|---|
| SQ-A | 阿嬤的香 | `saw_ama_incense` ✅ / AMA_INCENSE cutscene | 撞見阿嬤後院燒香 → 查那天是誰的生日 |
| SQ-B | 老周的繞圈話（現代） | beat `ch1_meet_lao_zhou` | 跟市場耆老打聽林家舊事 |
| SQ-C | 繼承文件的矛盾 | beat `ch1_lawyer_documents` | 律師揭「祖父林榮昌」名字矛盾 |
| SQ-D | 小威想逃去台北 | beat `ch1_xiaowei_curiosity` | 與堂叔林小威結盟 |
| SQ-E | 阿桃姨知道的事 | `a_tao_yi` 信任門檻 ▲ | 信任夠時說出 1976 那年真相 |

三條謎題暗線（塗黑全家福 / 上鎖房間 / 阿嬤燒香）以 clue 事件餵 stage，不一定做成顯式任務。

## 6. 需新增的事件 / 掛鉤（▲ 清單）

| 事件 / 掛鉤 | 記錄於（authoritative source） | 用途 |
|---|---|---|
| `ch1_traveled_to_1983` | 古地圖穿越觸發處（cutscene 或互動物件） | MQ01 完成 / MQ02 出現 |
| `ch1_rongchang_trust_ok` | StoryManager relationship→event 掛鉤（lin_rongchang 達門檻） | MQ03 完成 |
| `a_tao_yi` 真相事件（命名待定） | StoryManager relationship→event 掛鉤（a_tao_yi 達門檻） | SQ-E 完成 |

`relationship→event` 掛鉤為通用機制：以 `{npc_id: {threshold: event_id}}` 設定，relationship 跨門檻時 `record_event` 一次（去重）。

## 7. 測試策略

- **QuestManager 章節掃描**：放一個 chapter quest `.tres`，啟動後確認被載入、`required_events` 滿足時 `quest_started` 發出。
- **事件→完成**：模擬 `StoryManager.record_event("ch1_started_living_in_pharmacy")`，確認 MQ02 完成、MQ03 出現。
- **stage 同步**：完成 MQ02 後確認 `ChapterManager.get_current_stage()` == `s2_working`，TrustGate 取到 s2 attitude。
- **relationship→event**：把 lin_rongchang relationship 推過門檻，確認派生事件記錄一次、MQ03 完成、重複跨門檻不重記。
- 以 Godot 內既有測試方式（GUT 或場景測試，依專案現況）撰寫。

## 8. 未決 / 待實作時確認
- 各事件/flag 確切字串需對照 beat `.tres`、`events.gd`、`chapter.tres` 最終定版。
- 穿越觸發點目前是否已記錄事件（決定改動 #3 是否需要）。
- 信任門檻數值（MQ03 / SQ-E）。
- 選配改動 #4（NPC prompt 帶入當前任務）是否本章納入。
