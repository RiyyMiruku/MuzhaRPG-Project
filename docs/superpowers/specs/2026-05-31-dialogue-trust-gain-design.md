# 對話信任上升機制設計（AI 評分）

- 日期：2026-05-31
- 範圍：讓 NPC 的信任值能透過「自由/受限 AI 對話」上升或下降，由 LLM 依玩家發言評分。閉合 [[feature_quest_dialogue_linkage]] 留下的缺口（信任無 gameplay 上升管道，MQ03/SQ-E 無法完成）。
- 狀態：草案，待使用者 review。

---

## 1. 問題背景

前一個 feature（quest-dialogue linkage）讓任務能用「信任跨門檻派生事件」當完成條件（`ch1_rongchang_trust_ok` = lin_rongchang≥60、`ch1_atao_truth` = a_tao_yi≥50）。但目前 `StoryManager.update_relationship()` **唯一呼叫者是任務獎勵**——沒有任何 gameplay 機制會因玩家對話而提升信任，導致 MQ03（榮昌信任）與 SQ-E（阿桃姨）無法靠正常遊玩完成。

劇情設定（「別說錯話」「做對的回應」「身分洩漏會被踢回現代」）暗示：**玩家說什麼**應該影響 NPC 對他的信任。

## 2. 目標 / 非目標

### 目標
1. NPC 在 AI 對話中依玩家每輪發言調整信任（升/降）。
2. 沿用既有 `update_relationship` → relationship→event hook，讓 MQ03/SQ-E 能完成。
3. 玩家得到「微妙」回饋（方向感，不報數字），保留 1983 寫實氛圍。

### 非目標（YAGNI）
- 不做「身分洩漏踢回現代」（獨立機制，另議）。
- authored beat 不走此機制（beat 用 flag / set_relationship，已足夠且可控）。
- 不改 LLM 後端、不加第二次 request。
- 不做信任「衰退」（隨時間下降）。

## 3. 核心設計：回應內嵌信任 tag

採「同一回應內嵌 tag」——零額外 request、零延遲，沿用既有 `<think>` 剝除模式。

```
玩家輸入 → AIClient.query
  → TrustGate.build_system_prompt 末尾追加「信任評分指令 + rubric」
    （要 NPC 在回覆最後輸出隱藏標記 <trust±N>，N=0..3）
  → llama-server 回："…對話… <trust+2>"
  → AIClient._on_query_completed：
      1. 既有 <think> 剝除（不變）
      2. 既有 filter_forbidden（不變）
      3. 新增：解析最後一個 <trust±N>，clamp -3..+3，從顯示內容剝除
      4. delta≠0 → StoryManager.update_relationship(npc_id, delta)
         → 既有 relationship→event hook 自動觸發（信任到門檻 → 派生事件 → 任務完成）
      5. delta≠0 → 發新訊號 trust_changed(npc_id, direction)
  → DialogueUI 收 trust_changed → 顯示微妙 ↑/↓ 提示（不報數字）
```

### 設計決策（已與使用者確認）
- **評分取得**：NPC 回應內嵌 `<trust±N>` tag。
- **delta 範圍**：clamp **-3..+3**；中性對話 0。
- **負向**：允許扣分（冒犯/逼太緊/說錯話/暴露可疑知識）。
- **玩家回饋**：微妙提示（方向 ↑/↓，不報數字）。
- **門檻數值**：維持 lin_rongchang 60 / a_tao_yi 50（在 events.gd，可調）。

## 4. 架構改動

| # | 改動 | 檔案 | 說明 |
|---|---|---|---|
| 1 | `build_system_prompt` 末尾追加信任評分指令 + rubric（含 tag 格式說明） | `core/classes/TrustGate.gd` | 純函式，新增一段固定文字 |
| 2 | 新增 static `parse_trust_delta(text) -> int` 與 `strip_trust_tag(text) -> String` | `core/classes/TrustGate.gd` | 純函式，可獨立 headless 測試 |
| 3 | `_on_query_completed` 在剝 `<think>`、filter 後：parse delta → strip tag → update_relationship → 發訊號 | `autoload/AIClient.gd` | 串接 |
| 4 | 新增 signal `trust_changed(npc_id: String, direction: int)`（+1/-1） | `autoload/AIClient.gd` | 給 UI |
| 5 | 收 `trust_changed` 顯示微妙 ↑/↓ 提示 | `ui/dialogue/DialogueUI.gd` | 不報數字 |

改動 1、2、3 為核心；4、5 為回饋。

### tag 格式與 rubric（提案）
- **格式**：`<trust+2>` / `<trust-1>` / `<trust+0>`，放在回覆**最後**。正則 `<trust([+-]\d+)>`。
- **解析容錯**：找不到 tag → delta=0（不動信任，避免 LLM 漏輸出亂跳）；多個 tag 取最後一個；clamp -3..+3。
- **rubric（寫進 prompt）**：
  - 加分：玩家態度溫和有禮、尊重對方、展現可信、不過度逼問隱私、言行與「南部來打工的表親之子」身分一致。
  - 扣分：冒犯/質問逼太緊、自稱知道不該知道的事（暴露穿越者破綻）、說出與身分矛盾的話、態度輕浮。
  - 中性（0）：寒暄、問路、無關痛癢的閒聊。
  - 幅度：依玩家這一輪表現給 0~3（負向同理），多數情況 0~1。

## 5. 測試策略
- **parse_trust_delta**：`"…<trust+2>"`→2、`"…<trust-3>"`→-3、`"<trust+0>"`→0、無 tag→0、`"<trust+9>"`→clamp 3、多 tag 取最後。
- **strip_trust_tag**：移除 tag 後內容乾淨、無 tag 時原樣返回。
- **build_system_prompt**：輸出含信任評分指令標頭（確認 rubric 有注入）。
- **整合（沿用 test_quest_objectives 的 harness）**：模擬「AIClient 收到帶 `<trust+N>` 的回應」路徑會呼叫 update_relationship、發 trust_changed；連續加分跨 60 觸發 `ch1_rongchang_trust_ok` → MQ03 完成。
- DialogueUI 的 ↑/↓ 視覺非 headless 可測，列為手動驗證。

## 6. 待實作時確認
- tag 是否可能與 NPC 正常台詞衝突（`<...>` 在中文對話罕見，風險低；filter 用正則僅抓 `<trust±N>`）。
- 微妙提示的確切呈現（對話框角落小箭頭 / NPC 名字顏色閃動），實作時看 DialogueUI 結構定。
- rubric 文字最終潤飾（可隨第一章對話測試微調）。
