# UI 打磨設計（按鈕音效 + 中文化 + 視覺一致性）

- 日期：2026-06-01
- 範圍：(1) 所有按鈕加程式生成的點擊音效；(2) 所有 UI 文字中文化（寫死）；(3) 用共用 `.theme` 統一視覺（字型/字級/顏色/按鈕樣式），順帶讓中文以思源黑體顯示。
- 狀態：草案。使用者已授權直接寫 plan 執行（不再逐項確認）。

---

## 1. 背景（審計結論）

- UI 面板 8 個（MainMenu / PauseMenu / SaveLoadPanel / QuestJournal / KeybindSettings / AudioSettingsPanel / HUD / DialogueUI），約 30 個按鈕，**目前無任何按鈕音效**。
- 約 40 個英文/混雜字串散在 .tscn 與 .gd（按鈕、標題、區段標、狀態訊息）。
- 音訊基礎完備：bus = Master/Music/SFX；FootstepPlayer 示範了 one-shot SFX 模式（AudioStreamPlayer.bus="SFX" + play()）；AudioSettings autoload 管音量。
- **專案已有中文字型 `game/assets/fonts/NotoSansCJKtc-Regular.otf`（思源黑體繁中，uid `uid://wy3uk1o317pj`）但完全沒被使用**；專案無全域 theme（project.godot 無 gui/theme 設定），各面板用內嵌 `theme_override_font_sizes` 各自為政。

## 2. 目標 / 非目標

### 目標
1. 所有 UI 按鈕（含動態生成的）按下時播放點擊音，走 SFX bus（受音量/靜音控制）。
2. 所有玩家可見英文 UI 文字改中文（寫死於 .tscn/.gd）。
3. 建一個共用 `UITheme.theme`，設思源黑體為預設字型 + 統一字級/主色/按鈕樣式，設為全域預設 theme，移除各面板重複的 override。

### 非目標（YAGNI）
- 不做 hover/滑過音、不做音效分類（只一種點擊聲）。
- 不做排版重構/動畫互動（使用者選「視覺一致性」一面，不含體驗細節那塊）。
- 不做 i18n 框架（寫死中文即可，非目標 locale 切換）。
- 不改遊戲內敘事/對話內容文字（那些已是中文）。

## 3. 架構

三塊獨立、互不阻擋：

```
新增 game/src/audio/ui_sfx.gd          UISfx autoload：程式生成點擊音（AudioStreamGenerator/WAV），走 SFX bus
新增 game/src/audio/ui_sfx.gd.uid      （Godot 產生）
新增 game/src/ui/ui_theme.tres         共用 Theme 資源：default_font=思源黑體 + Button/Label/字級/顏色
改  game/project.godot                 [gui] gui/theme/custom 指向 ui_theme.tres；[autoload] 註冊 UISfx（在 AudioSettings 後）
改  8 個 UI .tscn / .gd                中文化字串 + 移除重複 theme_override + 按鈕接點擊音
```

### 3.1 UISfx autoload（點擊音）
- `extends Node`，`_ready` 建一個 `AudioStreamPlayer`（bus="SFX"），仿 FootstepPlayer 模式。
- 程式生成一段短促點擊音：用 `AudioStreamWAV`，runtime 合成一個 ~40ms 的衰減方波/正弦（含淡出避免爆音），快取一次。
- 公開 API：`func play_click() -> void`。
- 全域按鈕統一接法：提供 static helper `UISfx.attach(button)` 把 `button.pressed` 連到 `play_click`；或各面板在 `_ready` 對自己的按鈕呼叫。**採後者明確接法**（每個面板在 `_ready` 把自己的按鈕 `pressed.connect(UISfx.play_click)`），動態生成的按鈕（SaveLoadPanel/QuestJournal/KeybindSettings/DialogueUI choice）在建立時一併接。

### 3.2 UITheme.tres（視覺一致性）
- `Theme` 資源，設 `default_font = 思源黑體`、`default_font_size`（如 16）。
- 定義 `Button`、`Label`、`PanelContainer` 的基本樣式（字級、字色、可選 StyleBox）使各面板外觀一致。
- project.godot `[gui]` 加 `theme/custom="res://src/ui/ui_theme.tres"` → 全域預設，所有 Control 自動繼承。
- 各面板移除重複的 `theme_override_font_sizes/font_size`（改由 theme 提供）；保留有意義的個別差異（如標題 36、副標 14）—— 標題類可保留 override 或在 theme 定 variation，本版以「移除一般按鈕/標籤的 override、保留標題等特意大小」為原則。

### 3.3 中文化
逐檔把英文串改中文（寫死）。保留：快捷鍵提示 `[J]`/`[M]` 等、keybind 按鍵名（W/A/S/D…）、品牌副標 `Project Muzha`。對照表見 §5。

## 4. 資料流 / 介面
- 按鈕按下 → `pressed` 訊號 → `UISfx.play_click()` → AudioStreamPlayer(SFX bus).play() → 受 AudioSettings 的 SFX 音量/Master 靜音控制。
- Theme：全域 `gui/theme/custom` → 所有 Control 繼承 → 個別面板只在需要時 override。

## 5. 中文化對照表（寫死）

| 檔案 | 原文 | 中文 |
|---|---|---|
| MainMenu.tscn | New Game / Load Game / Quit | 新遊戲 / 讀取進度 / 離開 |
| MainMenu.tscn | Project Muzha（副標） | （保留） |
| PauseMenu.tscn | PAUSED | 暫停 |
| PauseMenu.tscn | Resume/Save/Load/Settings/Audio/Main Menu | 繼續/儲存/讀取/設定/音效/回主選單 |
| PauseMenu.tscn/.gd | Location: / Time: | 地點：/ 時間： |
| QuestJournal.tscn | Quest Journal [J] | 任務日誌 [J] |
| QuestJournal.tscn | Active / Completed | 進行中 / 已完成 |
| QuestJournal.gd | (none) | （無） |
| KeybindSettings.tscn | Key Bindings / Close | 按鍵設定 / 關閉 |
| KeybindSettings.gd | Move Up/Down/Left/Right, Interact, Pause, Map, Journal | 上移/下移/左移/右移、互動、暫停、地圖、任務日誌 |
| KeybindSettings.gd | Press a key... / Press any key to rebind / Saved! | 按任意鍵… / 按任意鍵重新綁定 / 已儲存！ |
| AudioSettingsPanel.tscn | Audio / Close | 音效設定 / 關閉 |
| AudioSettingsPanel.tscn | Master/Music/SFX Volume | 主音量 / 音樂 / 音效 |
| AudioSettingsPanel.tscn | Mute All Audio | 全部靜音 |
| HUD.tscn | Quest | 任務 |
| HUD.gd | "- " 前綴 | （保留符號） |
| 各面板既有中文（SaveLoadPanel/DialogueUI） | — | 不動 |

keybind 按鍵名（W/A/S/D/Space…）保留原樣。

## 6. 錯誤處理
- UISfx：合成失敗或 stream 為 null 時 `play_click` 直接 return（不崩）。
- Theme：字型 uid 失效時 Godot 退回內建字型（中文仍可顯示但不美）——以 `res://assets/fonts/...` 路徑引用，較穩。

## 7. 測試策略
- **UISfx headless**：取 autoload，呼叫 `play_click()` 不崩、`AudioStreamPlayer.stream` 非 null、bus=="SFX"。
- **Theme 載入**：headless 開機（`--quit-after`）零腳本錯誤，確認 `gui/theme/custom` 指的資源能載入。
- **中文化**：grep 確認目標英文串已不在 .tscn/.gd（對照表逐項）；開機無 parse error。
- UI 實際外觀/字型/音效播放需編輯器目視驗證（headless 測不到畫面與聲音）。
- 沿用既有 headless `SceneTree` 測試模式。

## 8. 待實作時確認
- 點擊音合成參數（頻率/長度/音量）——先給保守預設，目視/聽感可調。
- theme 是否對 PanelContainer 加 StyleBox——先做字型+字級+字色統一，StyleBox 視覺微調列為次要。
