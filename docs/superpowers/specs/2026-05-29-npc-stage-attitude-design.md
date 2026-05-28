# NPC 劇情階段態度系統 — 設計

日期：2026-05-29
分支：test-isometric-view

## 問題

第一章 NPC 的 LLM 回答「太突兀」。現況 prompt 只有：基底 `system_prompt` + 章節 `npc_overlays`（ch01 為空）+ `personality_voice` + trust 數字門檻的 `trust_revelations` + `known_facts`。缺少「玩家目前在劇情哪個階段」這個維度——阿謙第一天剛騙進藥行時，NPC 的 prompt 跟跑完五趟腿之後幾乎一樣，導致態度不隨劇情推進，回答顯得突兀。

目標：依劇本推斷玩家在不同遊戲階段時，每個 NPC 對玩家應有的態度，並把它注入給 LLM 的 system prompt。

## 設計決策（已與使用者確認）

- 階段粒度：**粗粒度 3-4 段**（非 per-quest）。
- 態度表達：**手寫中文描述片段**（非結構化數值 tags）。
- 階段判定：**StoryManager 由 flag/event 推導**；階段表為**資料驅動**，放在 ChapterConfig。
- 態度片段：寫在**各 NPC 的 NPCProfile `.tres`**。

## §1 第一章四階段

階段邊界完全綁現有 flag/event（見 `game/src/chapters/chapter_01_arrival/events.gd`），不新增劇情狀態機。

| stage_id | 階段 | 進入條件 | NPC 整體基調 |
|---|---|---|---|
| `s1_newcomer` | 初來乍到・隱瞞身份 | 預設（fallback） | 陌生、試探、半信半疑 |
| `s2_working` | 打工適應・建立日常 | `started_pharmacy_work` | 漸熟、公事公辦轉家常 |
| `s3_secret` | 觸碰秘密 | `clue_locked_room` 或 `saw_ama_incense` | 對禁忌主題繃緊、信任高者微鬆口 |
| `s4_finale` | 通關之夜・揭露 | `found_ronghua_relic` 或 `ending_finale_active` | 情緒臨界，林榮昌準備說出名字 |

判定規則：由後往前檢查，命中最高階段即回傳；單向前進、不回退。

**待辦**：`s2_working` 需要的 `started_pharmacy_work` flag 目前不存在，需在打工教學關卡觸發處 `StoryManager.set_flag("started_pharmacy_work", true)`，或先用既有 event 代替。實作時確認。

## §2 資料模型與注入機制

### (a) NPCProfile 新增欄位
`game/src/core/classes/NPCProfile.gd`：
```gdscript
## 各劇情階段的態度片段：{ stage_id: "2-4 句中文，描述此階段你對阿謙的態度與分寸" }
## 未填的 stage 自動 fallback 到前一個有填的階段（單向繼承）。
@export var stage_attitudes: Dictionary = {}
```

### (b) ChapterConfig 新增階段規則（資料驅動）
`game/src/core/classes/ChapterConfig.gd`：
```gdscript
## 劇情階段規則，依序檢查（由後往前命中最高階段）。
## 格式：[{ "stage_id": "s2_working", "require_any": ["started_pharmacy_work"] }, ...]
## 第一筆視為 fallback（require_any 可為空）。
@export var stage_rules: Array = []
```
ch01 `chapter.tres` 填入四階段規則（順序由 s1→s4）。

### (c) StoryManager 推導 current_stage
`game/src/autoload/StoryManager.gd`：
```gdscript
func get_current_stage() -> String:
    var rules: Array = ChapterManager.get_current_stage_rules()  # 回傳當前章節 stage_rules
    var result: String = ""
    for rule: Dictionary in rules:
        var sid: String = rule.get("stage_id", "")
        if result.is_empty():
            result = sid   # 第一筆當 fallback
        var req: Array = rule.get("require_any", [])
        if req.is_empty():
            continue
        for flag: String in req:
            if player_flags.get(flag, false):
                result = sid
                break
    return result
```
（精確實作於 plan 階段定案；ChapterManager 需補 `get_current_stage_rules()` 轉發。）

### (d) context 與 TrustGate
- `StoryManager.build_ai_context` 加 key：`"story_stage": get_current_stage()`。
- `TrustGate.build_system_prompt` 多收參數 `stage_attitude: String`，在 `[語氣]` 之後、`[你願意聊]` 之前注入 `[現階段態度] <片段>`。空字串時不注入。
- caller（AIClient `_build_chat_payload`）：從 context 取 `story_stage` → 查 `profile.stage_attitudes` →（含 fallback 繼承：往前找最近一格已填）→ 傳入 TrustGate。

fallback 繼承：依 stage_rules 的順序，從目標 stage 往前找第一個在 `stage_attitudes` 有填的 key。

## §3 NPC × 階段態度矩陣（一句話基調）

完整中文片段在實作時逐格寫進各 `.tres`。

| NPC | s1 初來 | s2 打工 | s3 觸碰秘密 | s4 通關之夜 |
|---|---|---|---|---|
| 林榮昌 | 半信半疑、缺人手才收留、語帶試探 | 認可員工、開始閒聊、不碰家事 | 你打探後院/塗黑照→明顯閃避、語氣沉 | 情緒臨界、被遺物觸動、終於肯說 |
| 林阿嬤 | 冷硬、不歡迎外人、話極短 | 勉強容忍、使喚做事 | 碰到燒香/禁忌→尖銳警告 | 燒香那夜微鬆、疼愛藏在禁令裡 |
| 林小威 | 好奇新來的、想聊台北 | 最快親近、當盟友、抱怨家裡 | 一起好奇「沒人提的叔叔」、想查 | 隱約知道大事將揭、不安 |
| 陳秀琴 | 比丈夫溫和、願聊家常 | 當半個家人、關心吃住 | 「我嫁進來就沒這人」輕輕帶過 | 看得到丈夫的痛但不被允許靠近 |
| 阿桃姨 | 市場八卦、對林家謹慎 | 漸熟、願講市場舊事 | 信任夠才鬆口 1976 片段 | 知道全貌、看阿謙下決定 |
| 老周（現代） | 繞圈子、打量你 | 願講藥行歷史但留一手 | 暗示「有些事不該主動講」 | 默認你已知、點到為止 |
| 律師（現代） | 公事公辦、交付文件 | 中性、補充繼承細節 | 中性 | 中性 |

提醒：
1. 老周、律師為 modern era，階段仍跟全域 stage 走（現代線也推進）。
2. `chapter.tres` 的 `npcs_present` 未列陳秀琴、阿桃姨，但 `.tres` 與劇本皆有。實作時確認本章是否出場，再決定是否補進 present 清單。

## §4 測試

- TrustGate 單元測試：給定 `stage_attitude` 字串，驗證 `[現階段態度]` 注入到正確位置；空字串不注入空標頭。
- fallback 繼承測試：`stage_attitudes` 只填 s1、s3 時，查 s2 回 s1 片段。
- `get_current_stage` 測試：不同 flag 組合驗證回傳最高命中階段、單向不回退、空 stage_rules 回 fallback。
- 向下相容：NPC 無任何 `stage_attitudes`（路人）→ 跳過注入，行為與現況一致。

## 影響檔案

- `game/src/core/classes/NPCProfile.gd`（+欄位）
- `game/src/core/classes/ChapterConfig.gd`（+欄位）
- `game/src/autoload/StoryManager.gd`（+get_current_stage、build_ai_context +key）
- `game/src/autoload/ChapterManager.gd`（+get_current_stage_rules 轉發）
- `game/src/core/classes/TrustGate.gd`（+參數、注入點）
- `game/src/autoload/AIClient.gd`（_build_chat_payload 傳 stage_attitude）
- `game/src/chapters/chapter_01_arrival/chapter.tres`（+stage_rules）
- `game/src/chapters/chapter_01_arrival/npcs/*.tres`（+stage_attitudes，7 個）
- 測試檔（TrustGate / StoryManager）
