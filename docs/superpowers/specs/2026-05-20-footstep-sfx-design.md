# Footstep SFX by Tile Surface — Design

> **狀態**：draft 2026-05-20（v2 — 加 AI skill 取代 pipeline / dashboard 重度整合）
> **範圍**：玩家走在不同 tileset 上時播放對應材質的腳步聲。Surface 標註綁在 tileset 的 asset.json，音檔走輕量 registry。**新增 tileset / 新增音檔的維運由 AI skill 處理（讀檔名 + 看 tileset description 自動歸位），不蓋類似美術素材的多階段 pipeline**。Dashboard 只做被動的可視化與手動 override。

## 動機

目前玩家走路無聲。需要依踩到的 tile 材質播對應 SFX（草地 / 石板 / 木地板 / 水泥 …），讓 iso 場景更有臨場感。

要解決的核心問題不是「播音」本身（Godot 一個 `AudioStreamPlayer` 就行），而是：

1. **誰決定一個 tileset = 哪種材質**：得有單一事實來源（SSOT），不能 tileset 跟 SFX 兩邊靠人腦同步
2. **音檔不是生成資產**：採集 / 下載來的，套 chroma_key / iso_project 那種 multi-stage pipeline 是浪費
3. **可維運性**：要看得出「哪個 tileset 沒標 surface」「哪個 surface 還沒音檔」
4. **未來會持續追加 tileset 跟音檔**：頻率不高（不像美術天天生），但累積會多。**新增動作要省人手** — 丟個音檔進 intake 資料夾、新建一個 tileset，剩下歸位 / 標 surface / 重 export 都讓 AI 一鍵搞定，不蓋 multi-stage pipeline。

## 範圍

| 項目 | 在範圍內 |
|---|---|
| 走路 / 跑步腳步聲依 tile 材質變化 | ✅ |
| Tileset asset.json 加 `surface_id` 欄位 | ✅ |
| Surface registry（已知 surface 清單 + 中文名） | ✅ |
| Footstep SFX 檔案組織 + runtime player | ✅ |
| AI skill：`footstep-sfx` 處理新增 tileset 自動標 surface + 新音檔自動歸位 | ✅ |
| Dashboard Audio 頁籤（檢視 / 預覽播放 / 手動 override） | ✅（簡化版 — AI skill 是主入口） |
| 跳躍落地 / 撞擊 / 開門等其他 SFX | ❌（之後另開 spec） |
| 環境音（風 / 蟲鳴） / 背景音樂 | ❌（另開 spec） |
| Prop 互動 SFX（推 / 拿） | ❌ |
| Dashboard 上傳 / 編輯音檔 | ❌（用檔案總管比較快） |

**只做腳步聲**。其他 SFX 之後可能沿用同一個 SurfaceRegistry / FootstepPlayer 架構，但這次不一起做。

## 架構

```
                    ┌─────────────────────────────────────────────┐
                    │ AI skill: footstep-sfx                      │
                    │  - "幫我把 audio_intake/ 的音檔歸位"           │
                    │  - "幫新 tileset 標 surface"                 │
                    │  - "lint 一下整個系統"                        │
                    │  讀檔名 + tileset description → 自動歸位 / 標籤  │
                    └─────────┬──────────────────────┬────────────┘
                              │                      │
                              ▼                      ▼
tileset asset.json  surface_id: "grass"     game/assets/audio/footsteps/<id>/*.ogg
        │                                            ▲
        │ pipeline.manifest.export_surface_map()      │  人手丟 / AI 從 intake 移
        ▼                                            │
game/assets/audio/surface_map.json                   │
   (tileset_name → surface_id)                       │
        │                                            │
        ▼                                            │
SurfaceRegistry autoload ───────────────────────────┐│
        │                                           ▼▼
        ▼                                  FootstepPlayer.play(surface_id)
Player movement script (步距驅動)                    │
        │                                           ▼
        └──────────────────────────────► 讀 footsteps/<surface_id>/*.ogg
                                            AudioStreamRandomizer 播
```

**關鍵設計決策**：不走 Godot TileSet 的 `custom_data_layer`，原因：

- autotile pipeline 不產生 `.tres`（TileSet 資源是人手在 Godot editor 建的），pipeline 無法自動寫 custom data
- 要 custom data 等於要求人類每建一個 tileset 都手動填一次 surface_id，重複勞動
- 改用「以 tileset 名查 surface」的外部 registry，pipeline 自動產出，零手動同步

## Surface 詞彙表（初版）

存在 `game/assets/audio/surfaces.json`：

```json
{
  "grass":    { "label_zh": "草地",   "label_en": "Grass" },
  "dirt":     { "label_zh": "泥土",   "label_en": "Dirt" },
  "stone":    { "label_zh": "石板",   "label_en": "Stone" },
  "concrete": { "label_zh": "水泥",   "label_en": "Concrete" },
  "asphalt":  { "label_zh": "柏油",   "label_en": "Asphalt" },
  "wood":     { "label_zh": "木地板", "label_en": "Wood" },
  "tatami":   { "label_zh": "榻榻米", "label_en": "Tatami" },
  "tile":     { "label_zh": "磁磚",   "label_en": "Tile" }
}
```

加 surface 時直接編這檔案。Dashboard dropdown 從這裡取選項。

## 改動清單

### 1. Spec 層：tileset `asset.json` 加 `surface_id: str | None`

預設 `null`（缺欄位視同 null，跑步沒聲音，dashboard 標紅燈）。

```json
{
  "tileset_id": "...",
  "lower": "compacted brown earth ...",
  "upper": "patchy green grass ...",
  "surface_id": "grass"
}
```

複合 tileset（dirt + grass autotile）的 `surface_id` 用 **「上層 / 主視覺」** 那層，因為玩家視覺認知是「我在草地上走」。透過 transition 那幾格踩到的聲音就用同一個，不細分 — 過渡 cell 數量少，不值得做 per-cell 查表。

### 2. Surface registry：`game/assets/audio/surfaces.json`

新檔案。手動維護的 surface 詞彙表（見上節範例）。Pipeline 不寫這檔。

### 3. Manifest export：`pipeline/manifest.py` 加 `export_surface_map()`

掃 manifest 所有 tileset entries，產出 `game/assets/audio/surface_map.json`：

```json
{
  "courtyard_grass_dirt": "grass",
  "market_tile_concrete": "concrete",
  "street_sidewalk_asphalt": "asphalt"
}
```

呼叫時機：
- `autotile.py import_to_godot` stage 完成後追加一行 `manifest.export_surface_map()`
- 也曝在 CLI：`uv run python -m pipeline.manifest export-surface-map`（手動 rebuild 用）

沒標 `surface_id` 的 tileset 不進 map（runtime 查不到 → 靜音 fallback）。

### 4. Runtime autoload：`game/src/audio/surface_registry.gd`

```gdscript
extends Node
# Autoload as SurfaceRegistry

var _tileset_to_surface: Dictionary = {}   # tileset_name -> surface_id

func _ready() -> void:
    _load()

func _load() -> void:
    var f := FileAccess.open("res://assets/audio/surface_map.json", FileAccess.READ)
    if f == null:
        push_warning("surface_map.json missing — footsteps will be silent")
        return
    var parsed: Variant = JSON.parse_string(f.get_as_text())
    if parsed is Dictionary:
        _tileset_to_surface = parsed

func surface_for_tileset(tileset_name: String) -> String:
    return _tileset_to_surface.get(tileset_name, "")
```

### 5. Runtime autoload：`game/src/audio/footstep_player.gd`

```gdscript
extends Node
# Autoload as FootstepPlayer

const STEP_DISTANCE: float = 18.0   # 一步走幾像素觸發一次

var _player: AudioStreamPlayer
var _streams_by_surface: Dictionary = {}   # surface_id -> AudioStreamRandomizer

func _ready() -> void:
    _player = AudioStreamPlayer.new()
    add_child(_player)

func play(surface_id: String) -> void:
    if surface_id == "":
        return
    var stream := _get_stream(surface_id)
    if stream == null:
        return
    _player.stream = stream
    _player.play()

func _get_stream(surface_id: String) -> AudioStreamRandomizer:
    if _streams_by_surface.has(surface_id):
        return _streams_by_surface[surface_id]
    var dir_path := "res://assets/audio/footsteps/" + surface_id + "/"
    var dir := DirAccess.open(dir_path)
    if dir == null:
        _streams_by_surface[surface_id] = null
        return null
    var randomizer := AudioStreamRandomizer.new()
    for f in dir.get_files():
        if not (f.ends_with(".ogg") or f.ends_with(".wav")):
            continue
        var s: AudioStream = load(dir_path + f)
        randomizer.add_stream(-1, s)
    _streams_by_surface[surface_id] = randomizer
    return randomizer
```

`STEP_DISTANCE` 暫定 18px（iso 視角下視覺一步約這麼長），實機調。

### 6. Player movement：步距驅動觸發

Player 的 movement script（位置由場景設計人填補；此 spec 不假設路徑）新增：

```gdscript
var _step_accum: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO

func _physics_process(delta: float) -> void:
    # ... 原有移動邏輯 ...
    var moved := global_position.distance_to(_last_pos)
    _last_pos = global_position
    if velocity.length() > 1.0:
        _step_accum += moved
        if _step_accum >= FootstepPlayer.STEP_DISTANCE:
            _step_accum = 0.0
            _trigger_footstep()

func _trigger_footstep() -> void:
    var layer := _ground_tilemap_layer_under_player()
    if layer == null:
        return
    var tileset_name := layer.tile_set.resource_path.get_file().get_basename()
    var surface_id := SurfaceRegistry.surface_for_tileset(tileset_name)
    FootstepPlayer.play(surface_id)
```

`_ground_tilemap_layer_under_player()` 的實作策略（zone 設計）：
- Zone 場景的地面 TileMapLayer 加到 group `"ground_layer"`
- Player 用 `get_tree().get_nodes_in_group("ground_layer")` 找；同位置多個 layer 取最上面那個（`z_index` 高者優先）
- 完全沒找到 → 不出聲（fallback 靜音）

### 6.5 AI skill：`footstep-sfx`（核心擴充性機制）

新增 skill：`.claude/skills/footstep-sfx/SKILL.md`。觸發詞：「幫我歸位音檔」「新 tileset 標 surface」「lint footstep」「audio_intake 處理」等。

**Skill 提供三個 sub-flow**：

#### Flow A：音檔自動歸位（intake → surface 資料夾）

使用者把音檔丟到 `game/assets/audio/_intake/` 隨便命名（e.g. `wet_grass_walking.ogg`, `stone_floor_step_03.wav`, `concrete-shoes-1.mp3`）。

Skill 動作：

1. 列出 `_intake/` 所有檔案
2. 對每個檔名跑 surface 推論：
   - 比對檔名 token vs `surfaces.json` 的 `surface_id` / `label_en` / 同義詞表（內建一個 lookup：`gravel → dirt`, `pavement → concrete`, `wooden → wood` …）
   - 命中 → 提議 surface_id
   - 不命中 → 列出 top-3 候選 + 「none / 新增 surface」選項，問使用者
3. 確認後：
   - 轉檔成 `.ogg`（如果不是 ogg，用 ffmpeg；ffmpeg 不存在就保留原格式）
   - 重命名成 `<surface_id>_NN.ogg`（NN 自動取該資料夾下一個編號，01 開始）
   - 移到 `footsteps/<surface_id>/`
4. 印 summary：哪些移了、哪些跳過、是否需要新增 surface

不打 ML / Pixellab，就是字串比對 + LLM 判讀，幾秒結束。

#### Flow B：新 tileset 自動標 surface

觸發時機：使用者剛跑完 `autotile.py` 建好新 tileset，或在 dashboard 建好新 autotile。

Skill 動作：

1. 找出所有 `surface_id` 是 null / 缺欄位的 tileset entry
2. 對每個 tileset 讀 `asset.json` 的 `upper` + `lower` description（這些是 Pixellab prompt，本身就描述材質）
3. LLM 對照 `surfaces.json` 判讀 → 提議 surface_id + 信心度（high / medium / low）
4. 列表給使用者確認：
   ```
   courtyard_grass_dirt    upper="patchy green grass..."         → grass    (high)
   market_tile_concrete    lower="grey concrete slabs..."        → concrete (high)
   street_sidewalk_asphalt lower="dark asphalt road..."          → asphalt  (high)
   ```
   high 全自動套；medium / low 逐一問
5. 套用：呼叫 dashboard remake API（或直接寫 manifest + 重 export_surface_map），等效於使用者在 dashboard 手動下拉選的結果

#### Flow C：lint 整個系統

「healthcheck」式診斷，回報：

- Tileset `surface_id` 沒填的清單
- Surface 有 tileset 用但 `footsteps/<id>/` 空的（紅燈 — runtime 會靜音）
- Surface 有 clip 但 < 2 個（黃燈 — 隨機性不足）
- `surface_map.json` 跟 `manifest.json` 不同步（應該 export 但沒）
- `_intake/` 還有沒處理的檔案
- `footsteps/` 下有不在 `surfaces.json` 的孤兒資料夾

每個項目附建議動作 + 對應 Flow（「跑 Flow B 解決」「跑 Flow A 歸位 5 個檔案」）。

**Skill 內部用的工具**：純 Bash / Read / Edit / Write — 不依賴新的 Python 套件。LLM 判讀就是 Claude 自己讀 description 後決定，呼叫 `manifest.upsert_tileset` 或直接編 asset.json。

**為什麼是 skill 不是 pipeline orchestrator**：

| 維度 | art-pipeline (orchestrator) | footstep-sfx (skill) |
|---|---|---|
| 觸發 | 每個 asset 都跑（高頻） | 偶爾追加時跑（低頻） |
| 步驟 | Multi-stage、resumable、外呼 Pixellab | 一次性、不可中斷也沒差 |
| 程式量 | 數百行 Python + manifest + jobs queue | 100 行 skill markdown + 幾個 helper |
| 失敗代價 | 高（生圖耗時 + token） | 低（重跑成本 = 0） |
| Tooling | CLI + dashboard API + worker | 跑一次完事，靠 LLM 智能 |

**擴充未來**：之後加 `interact-sfx` skill（敲門、撿東西）/ `bgm-skill` 走同樣模式：一個 SKILL.md + 一兩個 helper 函式，不再蓋 pipeline。

### 7. SFX 檔案組織

```
game/assets/audio/
├── surfaces.json                    ← 詞彙表（人手維護 / skill 可加新項）
├── surface_map.json                 ← pipeline 自動產
├── _intake/                         ← 新音檔 dump 區（footstep-sfx Flow A 入口）
│   ├── wet_grass_walking.ogg
│   └── stone_floor_3.wav
└── footsteps/
    ├── grass/
    │   ├── grass_01.ogg
    │   ├── grass_02.ogg
    │   └── grass_03.ogg
    ├── stone/
    │   └── ...
    └── wood/
        └── ...
```

命名 `<surface_id>_NN.ogg`（Flow A 自動處理）。每 surface 建議 3–5 個 variant，AudioStreamRandomizer 自動隨機。

**取得來源**（不在程式範圍，記錄供參考）：freesound.org CC0 / 自錄 / 從免費 SFX pack 抽。使用者只負責下載 → 丟 `_intake/` → 跟 AI 說「歸位一下」，剩下 skill 處理。第一批先湊 grass / stone / wood / concrete 四種驗收。

### 8. Dashboard backend：`tools/asset_dashboard/backend/server.py`

**`CreateAssetRequest` / `RemakeOverrides`** 對 tileset 加：
```python
surface_id: str | None = None
```
CLI 組裝時加 `--surface-id <value>`（autotile.py 同步加這個 arg + manifest upsert）。

**`AssetSummary.extra`** 對 tileset 加：
```python
"surface_id": entry.get("surface_id")
```

**新 endpoint**：
- `GET /api/audio/surfaces` → 回 `surfaces.json` 內容
- `GET /api/audio/footstep-clips/<surface_id>` → 回該資料夾的檔案列表
- `GET /api/audio/footstep-clip/<surface_id>/<filename>` → 串流音檔（給 frontend `<audio>` 預覽用）

### 9. Dashboard frontend：新 Audio 頁籤（精簡版）

`tools/asset_dashboard/frontend/src/components/AudioPanel.tsx`（新檔）

**重點**：dashboard 是「**檢視 + 手動 override**」介面，不是新增入口（新增交給 skill）。

列出 surfaces.json 每個 surface：
- surface_id / 中文名 / 對應的 tileset 數 / clip 數
- 點開展開 clip 列表，每個 clip 可預覽播放
- **狀態徽章**：🔴 紅燈（有 tileset 用但沒 clip）/ 🟡 黃燈（< 2 clip）/ 🟢 綠燈（≥ 2 clip）
- 反查表：每個 surface 顯示「使用此材質的 tileset」list
- **頂部按鈕**：「Run footstep-sfx lint」— 跳出複製貼到 Claude 的 prompt（如 `請執行 footstep-sfx Flow C lint`），降低使用者要記指令的負擔

`AssetDetail.tsx` 對 tileset 加 surface_id dropdown（從 surfaces.json 取選項）— 當 skill 標錯或要手動微調時用。改值 → remake `import_to_godot` stage（會重新 `export_surface_map`）。

**不做**：dashboard 內建上傳音檔 / 拖檔 intake / AI 自動標 surface 按鈕 — 這些都走 skill。Dashboard 只是被動 viewer + 緊急逃生口（手動 override）。

### 10. autoload 註冊

`game/project.godot` 的 `[autoload]` section 加：
```
SurfaceRegistry="*res://src/audio/surface_registry.gd"
FootstepPlayer="*res://src/audio/footstep_player.gd"
```

## 互動行為

| 動作 | 結果 |
|---|---|
| 新建 tileset 時填 surface_id | asset.json 寫入，import_to_godot 後 surface_map.json 自動更新 |
| Dashboard 改現有 tileset 的 surface_id | remake import_to_godot stage（秒級，不打 Pixellab） |
| Tileset 沒填 surface_id | surface_map.json 不含該 tileset，runtime 踩上去靜音 |
| 加新 surface（如 "carpet"） | 編 surfaces.json + 建 footsteps/carpet/ 資料夾丟音檔；tileset dropdown 自動出現新選項 |
| Surface 有 tileset 用但 footsteps/<id>/ 空 | runtime 靜音；dashboard Audio 頁籤紅燈 |
| Player 站著不動 | velocity 太小，不觸發；不會無限播 |
| 同位置多 TileMapLayer | 取 z_index 最高的 ground layer，避免地基層干擾 |

## 邊界情況

- **跑步 vs 走路**：用同一個 STEP_DISTANCE 不分；跑步速度大 → 步距相同但時間軸密集，自然就變「跑的腳步聲」。如果之後要差異化（跑步音量大），加 `play(surface_id, intensity)` 參數，AudioStreamPlayer 設 `volume_db`。本 spec 不做。
- **斜坡 / 樓梯**：iso 沒有 3D 樓梯，地面始終是 TileMapLayer，OK。
- **跨 tile 邊界**：步距觸發時剛好踩在邊界 → 取 `local_to_map(global_position)` 拿到的 cell；Godot 邊界判定一致，無歧義。
- **Map 切換**：FootstepPlayer 是 autoload，跨 map 持續存在；切換時 `_streams_by_surface` cache 沿用（資源 path 不變 → load 命中 cache），不需要清。
- **音檔缺失中途加入**：`_get_stream` 失敗一次後 cache `null`，之後同 surface 不重試；要 hot-reload 改成 dev-only 機制（非本 spec 範圍）。
- **`_last_pos` 初值 = 0**：第一次 `_physics_process` 會誤算成「從原點走過來」一大段距離。實作時在 `_ready()` 設 `_last_pos = global_position`。

## 不做

- 跳躍落地音 / 撞擊音 / 開門音（之後 spec）
- 環境音 / 背景音樂（另 spec）
- 依角色（NPC vs Player）區分腳步聲音量 / 音色 — 第一版只有 Player 出聲
- Dashboard 上傳 / 錄製 / 編輯音檔
- Per-cell surface override（同 tileset 內不同 tile 不同材質）
- 室內 / 室外 reverb 區分

## 測試

- Pipeline unit test：`export_surface_map()` 對含 / 不含 `surface_id` 的 entry 正確投影
- Backend：`POST /api/asset/tileset/X/remake` body `overrides.surface_id: "grass"` 後 manifest 寫入，且 surface_map.json 包含該 entry
- Backend：`GET /api/audio/footstep-clips/grass` 回的列表跟資料夾實際內容一致
- Runtime 手動：
  - 開 zonemarket 在 grass / stone / asphalt 之間走動，各有對應音
  - 站著不動 → 無聲
  - 踩到沒標 surface 的 tileset → 無聲（不是 crash）
  - 把 surfaces.json 加新 surface 但不放音檔 → dashboard 紅燈、runtime 無聲

## 工時估計

- surfaces.json + pipeline export_surface_map + autotile.py arg: 1 hr
- SurfaceRegistry / FootstepPlayer autoload + Player 步距驅動 + autoload 註冊: 1.5 hr
- 找音源 + 手動處理第一批（4 種 surface × 3 clip）: 1 hr
- **`footstep-sfx` skill（SKILL.md + Flow A/B/C 操作指引）**: 1.5 hr
- Dashboard backend (3 endpoints + AssetSummary): 1 hr
- Dashboard frontend AudioPanel + AssetDetail dropdown（精簡版）: 1 hr
- 測試 + 驗證（含跑一次 skill end-to-end）: 1 hr
- **總計 ~8 hr**

## 開發順序

1. **spec 定稿（這個檔）** ← 你正在看
2. **Runtime + pipeline 骨幹**（步驟 1–7, 10）：能在 zonemarket 走 grass 出聲就算過。第一批音檔手動歸位，不靠 skill。
3. **`footstep-sfx` skill**（步驟 6.5）：第 2 步證明 runtime 可行後再寫 skill；skill 用既有資料做迴歸測試（清空 surface_map.json → 跑 Flow B → 確認 regen 結果一致）。
4. **Dashboard 整合**（步驟 8, 9）：最後補可視化。

關鍵原則：**runtime 是地基，skill 是擴充性引擎，dashboard 是維運儀表板** — 依此順序開發確保每一階段都能獨立驗收。

## 相關
- [art-pipeline skill](../../.claude/skills/art-pipeline/SKILL.md)
- [tilemapdual-guide.md](../../tilemapdual-guide.md)
- [pipeline/manifest.py](../../../pipeline/manifest.py)
- [tools/asset_dashboard/backend/manifest_io.py](../../../tools/asset_dashboard/backend/manifest_io.py)
