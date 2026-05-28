# ISO 底座演算法整合進 Prop Pipeline — 設計

> 把「從 PNG 自動算 iso YSort 偏移 + 菱形碰撞」的演算法烘進美術 pipeline 的 prop 匯入步驟,讓新生成的 prop 在 `import_to_godot` 時自動套用,不必事後手動跑批次 patch。

## 背景

commit `9048ee5` 新增了兩支一次性工具:

- `tools/iso_base_analyze.py` — 掃 PNG 底部向上找最寬 row(底座菱形赤道),推出 `iso_sort_offset` + 四個碰撞菱形頂點(node-relative),只印報告。
- `tools/iso_prop_patch.py` — 用同一套 `analyze()` 批次改寫既有 `.tscn`:把 StaticBody 的 `CollisionShape2D` 換成 `ConvexPolygonShape2D`、設 root 的 `iso_sort_offset`、移除手動 position。

當時以一次性方式套到全部 201 個 prop `.tscn`。但 pipeline 的 prop 匯入(`pipeline/orchestrators/_godot_import.py::_write_prop_tscn`)**沒有**這段邏輯:它仍烘 `sprite offset = -h/2`(等同 `iso_sort_offset = 0`),且用固定矩形 preset(`bottom_16x16` 等)生成 `RectangleShape2D` 碰撞。因此每次生成新 prop 都得手動補跑 `iso_prop_patch.py`。

`analyze()` 目前在兩支 tool 腳本各複製一份;若 pipeline 也接,會變第三份。

## 目標

1. 新 prop 經 pipeline 匯入時,`.tscn` 自動帶正確的 `iso_sort_offset` 與菱形碰撞。
2. `analyze()` 收斂成單一 SSOT,消除複製。
3. iso 相關工具跟其他 pipeline 模組一樣模組化、可 CLI 直接調用。
4. 修復既有 201 個 prop 的「編輯器預覽 vs runtime」Sprite 峰置不一致(見下「已知 bug」)。

## 已知 bug:編輯器/runtime Sprite 峰置不一致

commit `9048ee5` 的 `iso_prop_patch.py` 把 `iso_sort_offset` 寫上 root node,卻沒同步更新 `.tscn` 烘進的 `Sprite2D.offset`(仍是 `-h/2`)。`Prop.gd` 不是 `@tool`,`_ready()` 在編輯器不跑,於是:

- **編輯器預覽**:`Sprite2D.offset.y = -h/2`(`.tscn` 烘進的舊值)
- **Runtime**:`Prop.gd._ready()` 算 `-h/2 + iso_sort_offset`

兩者差 `iso_sort_offset` px(例:`altar_table_wood` 差 11px),runtime 時圖往下掉。

**根因**:`.tscn` 烘進的 Sprite offset 必須等於 `_ready()` 算出來的值。SSOT 是 `_ready()` 的 `-h/2 + iso_sort_offset`;`.tscn` 的 bake 只是給編輯器顯示用的鏡像,patch 當時漏了同步。本 spec 的 pipeline 端(§4)與 patch 端(§2)都改成烘 `-h/2 + iso_sort_offset`,並重跑修復既有 prop(§6)。

## 決策(已與使用者確認)

- **套用範圍**:所有三種 prop kind(`building` / `iso_building` / `iso_prop`)都套,不 gate kind。
- **碰撞**:有碰撞時,自動菱形 `ConvexPolygonShape2D` **完全取代**矩形 preset。
- **程式組織**:抽出共用模組;且 iso 工具全部收進 `pipeline/`,模組化 + CLI 可直接跑;`tools/` 的兩支刪除。

## 架構

### 1. `pipeline/iso_base.py`(新,核心共用模組)

唯一版本的演算法 + CLI,放 `pipeline/` 而非 `tools/`,讓 dev 工具依賴 pipeline runtime,不要反向(避免層級倒置)。

- `analyze(img_path: Path) -> dict | None`
  - 輸入一張 PNG,回傳:
    - `iso_sort_offset: float` — `(h - 1) - widest_y`
    - `collision_points: list[tuple[float, float]]` — `[front, right, back, left]`,node-relative
    - debug 欄位:`tex_size`、`widest_y_img`、`bottom_y_img`、`back_y_img`
  - 全透明圖回 `None`。
  - 演算法與既有 `tools/iso_base_analyze.py::analyze` 完全相同(掃描、`_SHRINK_CONFIRM = 2`、赤道判定、四點推算)。
- `main()` / `parse_args()` / `if __name__ == "__main__"`
  - `uv run python pipeline/iso_base.py <png> [<png> ...]` 印分析報告(沿用既有 `iso_base_analyze.py` 的輸出格式:檔名、赤道、各點、`PackedVector2Array(...)`、`iso_sort_offset`)。
- 匯入機制:`_godot_import.py` 在 `pipeline/orchestrators/`,runtime 時 `pipeline/` 已在 `sys.path`(orchestrator 進入點 insert,pytest 也以 `pipeline/` 為 import 根),故 `import iso_base` 可解析。

### 2. `pipeline/iso_prop_patch.py`(從 `tools/` 搬入)

批次 patch 既有 `.tscn` 的 CLI(手動 re-patch 用途保留)。

- `parse_blocks` / `blocks_to_str` / `patch_tscn` / `process_tscn` / `main` 邏輯沿用既有 `tools/iso_prop_patch.py`。
- 移除自帶的 `analyze` 副本,改 `from iso_base import analyze`(消費合併後 analyze 回傳的 `tex_size`,取 `h`)。
- **新增 Sprite offset 重烘(修 §「已知 bug」)**:`patch_tscn` 多處理 `[node name="Sprite2D"]` 區塊,把 `offset` 重寫成 `Vector2(0, -h/2 + iso_sort_offset)`。原本只改 root + 碰撞,漏了 Sprite,正是峰置 bug 來源。
- `uv run python pipeline/iso_prop_patch.py [--dry-run] <tscn> [<tscn> ...]`。
- `_GAME_ROOT` 路徑改算法:`Path(__file__).parent.parent / "game"`(`pipeline/` → repo root → `game/`)。

### 3. 刪除 `tools/iso_base_analyze.py`、`tools/iso_prop_patch.py`

連帶更新任何 docs/README 對舊路徑的引用(以 grep 確認)。

### 4. `_godot_import.py::_write_prop_tscn` 改動

匯入流程(`import_prop` → `_write_prop_tscn`)在複製 PNG 後:

- `result = iso_base.analyze(png_path)`。
- **root node**(PropTemplate instance):多寫一行 `iso_sort_offset = <值>`。
- **Sprite 烘進的 offset**:`Vector2(0, -h/2 + iso_sort_offset)`(原本 `-h/2`)。讓編輯器顯示對齊 runtime;`Prop.gd._ready()` 在 `foot_anchor` 開時會套同一值。
- **StaticBody 碰撞**(`has_collision` 為真且 `analyze` 成功):
  - sub_resource 發 `ConvexPolygonShape2D`,`points = PackedVector2Array(front, right, back, left)`。
  - `CollisionShape2D`(parent `StaticBody2D`)**不**寫 `position`(點已是 node-relative)。
  - 不再用 `--collision` 的矩形尺寸決定此形狀。
- **InteractArea**:維持原本的 `RectangleShape2D`(互動範圍,非 iso 物理,與菱形無關)。

### 5. 邊界與相容

- `analyze` 回 `None`(全透明 PNG):`iso_sort_offset = 0`,StaticBody 碰撞 fallback 回現有矩形 preset 路徑(行為不破)。
- `--no-collision`:一樣不發 StaticBody,但**仍寫** `iso_sort_offset`(Y-sort 排序仍需要)。
- `--collision` 參數:保留(向下相容),但其矩形尺寸不再影響 StaticBody;實際只剩 on/off 意義(經 `--no-collision`)。先不刪、日後再考慮 deprecate。

### 6. 重跑修復既有 201 個 prop

改好 §2 的 patch 後,以更新後的 `pipeline/iso_prop_patch.py` 重跑 `game/src/maps/props/*.tscn`,修復既有 prop 的 Sprite offset bake(現在全是 stale 的 `-h/2`)。

- 先 `--dry-run` 抽查幾個(如 `altar_table_wood`:預期 Sprite offset 從 `-24` 改成 `-13`)。
- 確認後正式重跑全部。
- 這是 §「已知 bug」對既有 prop 的根因修復;新 prop 由 §4 pipeline 端覆蓋,不會再犯。

## 資料流

```
prop orchestrator: generate_object → chroma_key → import_to_godot
                                                       │
                                       import_prop(src_png, name, collision, has_collision, flip_h)
                                                       │
                                       _write_prop_tscn:
                                         iso_base.analyze(png_dest)  ──► {iso_sort_offset, collision_points}
                                         寫 .tscn:
                                           root.iso_sort_offset
                                           Sprite.offset = -h/2 + iso_sort_offset
                                           StaticBody: ConvexPolygonShape2D(points) | (None→矩形 fallback)
                                           InteractArea: RectangleShape2D(不變)
```

## 測試

- **新 `tests/test_iso_base.py`**
  - 合成一張已知尺寸的底座菱形 PNG(用 PIL 畫),驗 `analyze` 回的 `iso_sort_offset` 與四點符合幾何預期。
  - 全透明 PNG → `None`。
- **擴 `tests/test_godot_import.py`**
  - `import_prop`(有碰撞)產出的 `.tscn` 含 `ConvexPolygonShape2D`、含 `iso_sort_offset = ` 行、Sprite offset = `-h/2 + iso_sort_offset`、StaticBody 的 `CollisionShape2D` 無 `position`。
  - `--no-collision`(`has_collision=False`):無 StaticBody 碰撞,但仍有 `iso_sort_offset` 行。
  - 全透明 PNG:fallback 回矩形 preset、`iso_sort_offset = 0.0`、Sprite offset = `-h/2`。
- **新 `tests/test_iso_prop_patch.py`**(峰置 bug 回歸測試)
  - 合成一個 root iso_sort_offset 缺失/錯誤、Sprite offset 烘 `-h/2` 的 `.tscn`,跑 `patch_tscn`,驗證輸出的 Sprite offset = `-h/2 + iso_sort_offset`(對既有 bug 的回歸防護)。

## 非目標(YAGNI)

- 不改 InteractArea 碰撞形狀。
- 不刪 `--collision` 參數(僅標記未來可 deprecate)。
- 不動 autotile / character / npc 等其他 orchestrator。
- 既有 201 prop 的 PNG 不重生;重跑雖會 re-analyze,但 analyze 為決定性、PNG 未變,菱形/iso_sort_offset 值預期不變,實質 diff 僅 Sprite offset 補烘。
