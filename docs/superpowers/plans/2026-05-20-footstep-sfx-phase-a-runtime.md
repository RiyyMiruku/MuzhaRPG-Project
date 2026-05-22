# Footstep SFX Phase A — Runtime + Pipeline Backbone

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 玩家走路依踩到的 tileset 材質播放對應腳步聲；surface 標註綁在 tileset asset.json，pipeline 自動 export 對照表給 runtime 用。

**Architecture:** Tileset asset.json 加 `surface_id` 欄位（SSOT）→ `pipeline.manifest.export_surface_map()` 寫出 `game/assets/audio/surface_map.json`（runtime registry）→ `SurfaceRegistry` autoload 讀 map → `Player.gd` 步距驅動 → `FootstepPlayer.play(surface_id)` 從 `footsteps/<id>/*.ogg` 隨機播。

**Tech Stack:** Python 3 (pytest, pipeline manifest), GDScript (Godot 4.6 AudioStreamPlayer / AudioStreamRandomizer / autoload), JSON。

**Spec:** [docs/superpowers/specs/2026-05-20-footstep-sfx-design.md](../specs/2026-05-20-footstep-sfx-design.md)

**Phase A 範圍**：spec 步驟 1–7, 10。Phase B（footstep-sfx AI skill）+ Phase C（dashboard 整合）會另寫 plan。

**驗收條件**：開 zonemarket，操控玩家在草地 / 水泥 / 柏油三種 tileset 上走動，各有對應腳步聲；站著不動時無聲；踩到沒標 surface 的 tileset 時無聲且不 crash。

---

## File Structure

**新檔**：

- `game/assets/audio/surfaces.json` — surface 詞彙表（人手維護）
- `game/assets/audio/footsteps/<surface_id>/<id>_NN.ogg` — 第一批音檔（手動歸位）
- `game/assets/audio/surface_map.json` — pipeline 自動產，不手動編
- `game/assets/audio/_intake/.gitkeep` — Phase B 用的空 dump 區
- `game/src/audio/surface_registry.gd` — autoload，讀 surface_map.json
- `game/src/audio/footstep_player.gd` — autoload，依 surface_id 播放
- `tests/test_export_surface_map.py` — pipeline 端 unit test

**修改**：

- `pipeline/manifest.py` — 加 `export_surface_map()`
- `pipeline/orchestrators/autotile.py` — 加 `--surface-id` CLI arg，`import_to_godot` stage 後呼叫 export
- `game/project.godot` — 註冊兩個新 autoload
- `game/src/entities/player/Player.gd` — 加步距驅動 footstep trigger

**手動更新（不在程式 task 內，做 verification 前完成）**：

- 既有 6 個 tileset 的 `asset.json` 補 `surface_id` 欄位（grass / concrete / asphalt / dirt 之類）

---

## Task 1: Surface 詞彙表 + 資料夾骨架

**Files:**
- Create: `game/assets/audio/surfaces.json`
- Create: `game/assets/audio/footsteps/.gitkeep`
- Create: `game/assets/audio/_intake/.gitkeep`

- [ ] **Step 1: 建詞彙表**

Create `game/assets/audio/surfaces.json`:

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

- [ ] **Step 2: 建空資料夾佔位**

Create `game/assets/audio/footsteps/.gitkeep` (empty file)
Create `game/assets/audio/_intake/.gitkeep` (empty file)

- [ ] **Step 3: Commit**

```powershell
git add game/assets/audio/surfaces.json game/assets/audio/footsteps/.gitkeep game/assets/audio/_intake/.gitkeep
git commit -m "feat(audio): add surface vocabulary + audio folder skeleton"
```

---

## Task 2: `manifest.export_surface_map()` — TDD

**Files:**
- Create: `tests/test_export_surface_map.py`
- Modify: `pipeline/manifest.py` (加 `export_surface_map`)

- [ ] **Step 1: 寫失敗測試**

Create `tests/test_export_surface_map.py`:

```python
"""Tests for manifest.export_surface_map()."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "pipeline"))

import manifest


@pytest.fixture
def tmp_project(tmp_path, monkeypatch):
    """Point manifest at a temp project root."""
    monkeypatch.setattr(manifest, "_project_root", lambda: tmp_path)
    (tmp_path / "art_source" / "tilesets").mkdir(parents=True)
    (tmp_path / "game" / "assets" / "audio").mkdir(parents=True)
    return tmp_path


def _write_tileset(root: Path, name: str, fields: dict) -> None:
    d = root / "art_source" / "tilesets" / name
    d.mkdir(exist_ok=True)
    payload = {"status": "completed", "tileset_id": "x", **fields}
    (d / "asset.json").write_text(json.dumps(payload), encoding="utf-8")


def test_export_includes_tilesets_with_surface_id(tmp_project):
    _write_tileset(tmp_project, "courtyard_grass_dirt", {"surface_id": "grass"})
    _write_tileset(tmp_project, "market_tile_concrete", {"surface_id": "concrete"})

    out = manifest.export_surface_map()

    expected = tmp_project / "game" / "assets" / "audio" / "surface_map.json"
    assert out == expected
    data = json.loads(expected.read_text(encoding="utf-8"))
    assert data == {
        "courtyard_grass_dirt": "grass",
        "market_tile_concrete": "concrete",
    }


def test_export_skips_tilesets_without_surface_id(tmp_project):
    _write_tileset(tmp_project, "with_surface", {"surface_id": "wood"})
    _write_tileset(tmp_project, "no_surface", {})              # 缺欄位
    _write_tileset(tmp_project, "null_surface", {"surface_id": None})  # 明確 null

    manifest.export_surface_map()

    data = json.loads(
        (tmp_project / "game" / "assets" / "audio" / "surface_map.json").read_text("utf-8")
    )
    assert data == {"with_surface": "wood"}


def test_export_overwrites_existing_file(tmp_project):
    target = tmp_project / "game" / "assets" / "audio" / "surface_map.json"
    target.write_text('{"stale": "data"}', encoding="utf-8")

    _write_tileset(tmp_project, "fresh", {"surface_id": "stone"})
    manifest.export_surface_map()

    assert json.loads(target.read_text("utf-8")) == {"fresh": "stone"}
```

- [ ] **Step 2: 跑測試確認失敗**

```powershell
uv run pytest tests/test_export_surface_map.py -v
```

Expected: 全部 FAIL，原因 `AttributeError: module 'manifest' has no attribute 'export_surface_map'` 或 `_project_root`（看哪個 attr 先被找）。

- [ ] **Step 3: 確認 manifest 既有的 project-root helper**

Read [pipeline/manifest.py](../../../pipeline/manifest.py) 找出目前怎麼定位 project root（grep `project_root\|art_source` ）。

如果沒有 `_project_root()` 函式，但有別的方式（e.g. 直接拼 `Path(__file__).parents[1]`），改測試的 monkeypatch target 對齊既有寫法。如果有 `art_source_dir()` 之類的，monkeypatch 那個 + tileset 目錄結構照樣 fixture 化。**先讀 manifest.py 弄清楚再改測試**，再進下一步。

- [ ] **Step 4: 實作 `export_surface_map`**

加在 `pipeline/manifest.py` 最後（在現有 helper 之後）：

```python
def export_surface_map() -> Path:
    """Walk all tileset asset.json files; write {tileset_name: surface_id}
    to game/assets/audio/surface_map.json. Tilesets without a non-null
    surface_id are skipped. Returns the output path.
    """
    root = _project_root()
    tilesets_dir = root / "art_source" / "tilesets"
    out_dir = root / "game" / "assets" / "audio"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "surface_map.json"

    mapping: dict[str, str] = {}
    if tilesets_dir.exists():
        for asset_json in sorted(tilesets_dir.glob("*/asset.json")):
            try:
                entry = json.loads(asset_json.read_text(encoding="utf-8"))
            except Exception:
                continue
            surface = entry.get("surface_id")
            if isinstance(surface, str) and surface:
                mapping[asset_json.parent.name] = surface

    out_path.write_text(
        json.dumps(mapping, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return out_path
```

如 step 3 發現 manifest 沒有獨立的 `_project_root()` 函式，加一個：

```python
def _project_root() -> Path:
    return Path(__file__).resolve().parents[1]
```

放在現有 `validate_asset_name` 之後、`_upsert_in_bucket` 之前。

- [ ] **Step 5: 跑測試確認通過**

```powershell
uv run pytest tests/test_export_surface_map.py -v
```

Expected: 3 個測試全部 PASS。

- [ ] **Step 6: Commit**

```powershell
git add tests/test_export_surface_map.py pipeline/manifest.py
git commit -m "feat(pipeline): manifest.export_surface_map() projects tileset surface_id to runtime registry"
```

---

## Task 3: autotile.py 加 `--surface-id` + 自動 export

**Files:**
- Modify: `pipeline/orchestrators/autotile.py`

- [ ] **Step 1: 加 argparse arg**

在 `pipeline/orchestrators/autotile.py` `parse_args()` 函式內，於既有 `--chapter` arg 之後加：

```python
    parser.add_argument(
        "--surface-id",
        default=None,
        help="腳步聲材質標籤 (grass/dirt/stone/concrete/asphalt/wood/tatami/tile)。"
             "詞彙表是 game/assets/audio/surfaces.json。",
    )
```

- [ ] **Step 2: 在 main 套用 + 觸發 export**

在 `main()` 函式內，於現有的 `if tags: manifest.add_tags(...)` 之後、`generate_atlas(ctx)` 之前加：

```python
    if args.surface_id is not None:
        manifest.upsert_tileset(name=ctx.name, fields={"surface_id": args.surface_id})
```

於 `import_to_godot(ctx)` 之後加：

```python
    manifest.export_surface_map()
```

- [ ] **Step 3: 驗證 dry-run（沒打 Pixellab）**

不跑完整 pipeline；改開 Python REPL 驗 API 表面 OK：

```powershell
uv run python -c "from pipeline.orchestrators import autotile; print(autotile.parse_args.__doc__ or 'ok')"
```

Expected: 不噴 `argparse` import 錯，print `ok` 或 None。

然後試組一個 `--help`：

```powershell
uv run python pipeline/orchestrators/autotile.py --help
```

Expected: help 文字包含一行 `--surface-id`。

- [ ] **Step 4: 手動回灌既有 tileset 的 surface_id**

直接編 6 個既存 tileset 的 `asset.json` 加 `surface_id`（你最熟悉它們的 prompt，比看 description 猜更準）。建議對照：

| tileset name | surface_id |
|---|---|
| courtyard_grass_dirt | grass |
| market_tile_concrete | concrete |
| street_sidewalk_asphalt | asphalt |
| (其他 tilesets 視 prompt 而定) | ... |

對每個檔加一行 `"surface_id": "<id>",` 進 JSON。

- [ ] **Step 5: 跑一次 export 寫出 surface_map.json**

```powershell
uv run python -c "import sys; sys.path.insert(0, 'pipeline'); import manifest; print(manifest.export_surface_map())"
```

Expected: print 出 `game/assets/audio/surface_map.json` 路徑；該檔案內含至少 3 個 tileset → surface_id 對應。

- [ ] **Step 6: Commit**

```powershell
git add pipeline/orchestrators/autotile.py art_source/tilesets/*/asset.json game/assets/audio/surface_map.json
git commit -m "feat(pipeline): autotile --surface-id flag + backfill existing tilesets"
```

---

## Task 4: `SurfaceRegistry` autoload

**Files:**
- Create: `game/src/audio/surface_registry.gd`
- Modify: `game/project.godot`

- [ ] **Step 1: 寫 autoload script**

Create `game/src/audio/surface_registry.gd`:

```gdscript
## SurfaceRegistry — autoload
## 讀 res://assets/audio/surface_map.json 並提供 tileset → surface_id 查詢。
extends Node

const _MAP_PATH: String = "res://assets/audio/surface_map.json"

var _tileset_to_surface: Dictionary = {}

func _ready() -> void:
	_load()

func _load() -> void:
	var f: FileAccess = FileAccess.open(_MAP_PATH, FileAccess.READ)
	if f == null:
		push_warning("[SurfaceRegistry] %s missing — footsteps will be silent" % _MAP_PATH)
		return
	var text: String = f.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_tileset_to_surface = parsed
	else:
		push_warning("[SurfaceRegistry] %s is not a JSON object" % _MAP_PATH)

func surface_for_tileset(tileset_name: String) -> String:
	return _tileset_to_surface.get(tileset_name, "")
```

- [ ] **Step 2: 註冊 autoload**

Modify `game/project.godot`：在 `[autoload]` section 末尾加：

```
SurfaceRegistry="*res://src/audio/surface_registry.gd"
```

放在現有 `PhantomCameraManager` 行之後。

- [ ] **Step 3: 開 Godot 驗證沒 parse error**

```powershell
& "C:\Program Files\Godot\Godot_v4.6-stable_win64.exe" --path game --headless --editor --quit
```

（如果 Godot 安裝路徑不同，改用實際路徑。若不確定怎麼 headless 跑，改手動：用 Godot editor 打開 `game/project.godot`，看 output 沒紅字。）

Expected: 沒有 `SurfaceRegistry` 相關的 parse / load error。

- [ ] **Step 4: Commit**

```powershell
git add game/src/audio/surface_registry.gd game/project.godot
git commit -m "feat(audio): SurfaceRegistry autoload — read surface_map.json"
```

---

## Task 5: `FootstepPlayer` autoload

**Files:**
- Create: `game/src/audio/footstep_player.gd`
- Modify: `game/project.godot`

- [ ] **Step 1: 寫 autoload script**

Create `game/src/audio/footstep_player.gd`:

```gdscript
## FootstepPlayer — autoload
## 依 surface_id 播放對應資料夾的隨機腳步聲。lazy-load + cache。
extends Node

const STEP_DISTANCE: float = 18.0

var _player: AudioStreamPlayer
## surface_id -> AudioStreamRandomizer (or null if no clips found)
var _streams_by_surface: Dictionary = {}

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)

func play(surface_id: String) -> void:
	if surface_id == "":
		return
	var stream: AudioStreamRandomizer = _get_stream(surface_id)
	if stream == null:
		return
	_player.stream = stream
	_player.play()

func _get_stream(surface_id: String) -> AudioStreamRandomizer:
	if _streams_by_surface.has(surface_id):
		return _streams_by_surface[surface_id]

	var dir_path: String = "res://assets/audio/footsteps/" + surface_id + "/"
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		_streams_by_surface[surface_id] = null
		return null

	var randomizer: AudioStreamRandomizer = AudioStreamRandomizer.new()
	var added: int = 0
	for fname in dir.get_files():
		if not (fname.ends_with(".ogg") or fname.ends_with(".wav") or fname.ends_with(".mp3")):
			continue
		var s: AudioStream = load(dir_path + fname)
		if s == null:
			continue
		randomizer.add_stream(-1, s)
		added += 1

	if added == 0:
		_streams_by_surface[surface_id] = null
		return null

	_streams_by_surface[surface_id] = randomizer
	return randomizer
```

- [ ] **Step 2: 註冊 autoload**

Modify `game/project.godot`：在 `SurfaceRegistry` 行之後加：

```
FootstepPlayer="*res://src/audio/footstep_player.gd"
```

- [ ] **Step 3: Commit**

```powershell
git add game/src/audio/footstep_player.gd game/project.godot
git commit -m "feat(audio): FootstepPlayer autoload — lazy-load surface SFX into AudioStreamRandomizer"
```

---

## Task 6: 第一批音檔（手動歸位）

**Files:**
- Create: `game/assets/audio/footsteps/grass/grass_01.ogg` (... 3 個)
- Create: `game/assets/audio/footsteps/concrete/concrete_01.ogg` (... 3 個)
- Create: `game/assets/audio/footsteps/asphalt/asphalt_01.ogg` (... 3 個)

Phase B 之前用手動處理。Phase B 的 footstep-sfx skill 之後會自動化。

- [ ] **Step 1: 找音源**

從以下任一來源拿 grass / concrete / asphalt 各 3 個 footstep clip：
- freesound.org（CC0 / CC-BY，注意授權）
- 自錄
- 既有免費 SFX pack

長度約 0.2–0.5 秒，single step（不要多步混錄），volume 大致統一。

- [ ] **Step 2: 轉成 ogg + 歸位**

對每個檔：
- 轉成 `.ogg`（用 Audacity / ffmpeg；或保留 wav 也行，FootstepPlayer 支援）
- 重命名 `<surface_id>_NN.ogg`（01, 02, 03 ...）
- 放進 `game/assets/audio/footsteps/<surface_id>/`

最終目錄：
```
footsteps/
├── grass/grass_01.ogg, grass_02.ogg, grass_03.ogg
├── concrete/concrete_01.ogg, concrete_02.ogg, concrete_03.ogg
└── asphalt/asphalt_01.ogg, asphalt_02.ogg, asphalt_03.ogg
```

- [ ] **Step 3: Godot 一鍵 reimport（讓 .ogg 被識別）**

開 Godot editor，等待自動 import；或執行：

```powershell
& "C:\Program Files\Godot\Godot_v4.6-stable_win64.exe" --path game --headless --editor --quit
```

驗證每個 .ogg 旁邊都有對應的 `.import` 檔。

- [ ] **Step 4: Commit**

```powershell
git add game/assets/audio/footsteps/
git commit -m "feat(audio): first batch of footstep clips (grass / concrete / asphalt × 3)"
```

如果音源檔案數量大，考慮用 `git lfs track "*.ogg"` 之前先評估 repo size；若 9 個小 clip 都 < 200KB 加總 < 2MB，直接 commit 不開 LFS。

---

## Task 7: Player 步距驅動 footstep trigger

**Files:**
- Modify: `game/src/entities/player/Player.gd`

- [ ] **Step 1: 加 state 變數**

在 `Player.gd` 既有的 `# ── State ──` 區塊（`var _nearby_interactable: Node = null` 之後）加：

```gdscript
var _step_accum: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
```

- [ ] **Step 2: 初始化 `_last_pos`**

在 `_ready()` 函式最後（`GameManager.game_state_changed.connect(...)` 之後）加：

```gdscript
	_last_pos = global_position
```

避免第一次 `_physics_process` 把原點到出生點當成移動距離。

- [ ] **Step 3: 改 `_physics_process` 加 footstep trigger**

把現有的：

```gdscript
func _physics_process(_delta: float) -> void:
	var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move_with_input(input_vec)
```

改為：

```gdscript
func _physics_process(_delta: float) -> void:
	var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move_with_input(input_vec)
	_update_footsteps()

func _update_footsteps() -> void:
	var moved: float = global_position.distance_to(_last_pos)
	_last_pos = global_position
	if not is_moving or velocity.length() < 1.0:
		return
	_step_accum += moved
	if _step_accum < FootstepPlayer.STEP_DISTANCE:
		return
	_step_accum = 0.0
	var surface_id: String = _surface_under_player()
	FootstepPlayer.play(surface_id)

func _surface_under_player() -> String:
	## 找站位下方最上層的 ground TileMapLayer，回它 TileSet 對應的 surface_id。
	## Ground layer 須加進 "ground_layer" group，並在 z_index 設好疊放順序。
	var best_layer: TileMapLayer = null
	for node in get_tree().get_nodes_in_group("ground_layer"):
		if node is TileMapLayer:
			if best_layer == null or node.z_index > best_layer.z_index:
				best_layer = node
	if best_layer == null or best_layer.tile_set == null:
		return ""
	var ts_path: String = best_layer.tile_set.resource_path
	if ts_path == "":
		return ""
	var tileset_name: String = ts_path.get_file().get_basename()
	return SurfaceRegistry.surface_for_tileset(tileset_name)
```

- [ ] **Step 4: 加 ground_layer group 到 zonemarket**

開 Godot editor 載入 `game/src/maps/...zonemarket...tscn`（或同等 zone），把地面 TileMapLayer 節點加進 group `ground_layer`：
- inspector 右上 ⋮ → "Editable Children" 不需要，直接 select node → 場景樹底下找 "Groups" panel → 加 group `ground_layer`

存檔。

- [ ] **Step 5: Commit**

```powershell
git add game/src/entities/player/Player.gd game/src/maps/*.tscn
git commit -m "feat(player): step-distance-driven footstep trigger queries ground layer surface"
```

---

## Task 8: 手動驗收 — zonemarket 走走看

**Files:** (verification only — no code edits)

- [ ] **Step 1: 跑 Godot 進入 zonemarket**

```powershell
& "C:\Program Files\Godot\Godot_v4.6-stable_win64.exe" --path game
```

開 main scene，操控玩家進 zonemarket。

- [ ] **Step 2: 驗收清單**

逐一驗證：

- [ ] 走在草地 tileset 上 → 聽到 grass 腳步聲
- [ ] 走在水泥 tileset 上 → 聽到 concrete 腳步聲
- [ ] 走在柏油 tileset 上 → 聽到 asphalt 腳步聲
- [ ] 站著不動 → 完全無聲
- [ ] 走過沒標 surface_id 的 tileset → 無聲、不 crash、debug console 沒紅字
- [ ] 連續走動腳步聲節奏穩定（不會一下密集一下稀疏）

- [ ] **Step 3: 微調 STEP_DISTANCE（如有必要）**

如果腳步聲節奏不對：
- 太密集 → `footstep_player.gd` 的 `STEP_DISTANCE` 調大（24 / 30）
- 太稀疏 → 調小（14 / 12）

調整後重 commit：

```powershell
git add game/src/audio/footstep_player.gd
git commit -m "tune(audio): adjust STEP_DISTANCE based on playtest"
```

- [ ] **Step 4: 記錄已知問題（不修）到 Phase B/C plan 的「待辦」**

Phase A 完成。若驗收發現需 dashboard 才好調的（例如想換不同 clip）或需 skill 才好補的（例如多 surface 沒音），列進後續 plan。

---

## Self-Review

- ✅ Spec 第 1, 2, 3, 4, 5, 7, 10 步驟都有對應 task。
- ✅ Spec 第 6（FootstepPlayer）對應 Task 5。
- ✅ Spec 第 6.5 (skill) — 留 Phase B，不在本 plan。
- ✅ Spec 第 8, 9 (dashboard) — 留 Phase C，不在本 plan。
- ✅ Spec 「驗收條件」（zonemarket 三種材質 + 站著無聲 + 沒標 surface 不 crash）對應 Task 8 驗收清單。
- ✅ 邊界情況「`_last_pos` 初值 = 0」對應 Task 7 Step 2。
- ✅ 邊界情況「同位置多 TileMapLayer 取 z_index 最高」對應 Task 7 Step 3 `_surface_under_player`。
- ✅ 無 placeholder，每個 code step 都有完整代碼。
- ✅ 型別一致：`STEP_DISTANCE: float`、`surface_for_tileset(String) -> String` 在所有 task 命名一致。

---

## 後續

Phase A 完成後，依 spec 開發順序進 Phase B（footstep-sfx AI skill），最後 Phase C（dashboard）。每個 phase 寫獨立 plan：

- `docs/superpowers/plans/2026-05-20-footstep-sfx-phase-b-skill.md`（未寫）
- `docs/superpowers/plans/2026-05-20-footstep-sfx-phase-c-dashboard.md`（未寫）
