---
name: art-pipeline-iso-collision-patch
description: Use when the user wants to (re)apply iso anchoring + diamond collision to existing prop .tscn files in this MuzhaRPG project. Triggers on requests like "重跑 iso 碰撞", "把碰撞重新拉一下", "重烘 prop offset", "美術重生後 prop 對齊跑掉幫我修", "對所有 prop 套 iso", "為新加的 prop 套碰撞菱形". Skips for creating NEW assets (use the art-pipeline skill), debugging the algorithm itself, or pipeline runtime work on `_godot_import.py`.
---

# Iso Collision Patch — 對既有 prop .tscn 重套 iso 對齊與菱形碰撞

把 `pipeline/iso_prop_patch.py` 包成 Claude Code 可調用流程。**新生成的 prop 由 `prop.py` orchestrator 在 `import_to_godot` 自動套**(見 sibling skill [art-pipeline](../art-pipeline/SKILL.md));這個 skill 處理「既有 .tscn 要重跑」的場景。

## 什麼時候用 / 不用

| 情境 | 用這個 skill? |
|---|---|
| 美術重生了 PNG,需要把 prop 的 `iso_sort_offset` / 菱形 / Sprite offset 跟新幾何對齊 | ✅ |
| 新增了一批手工建的 prop,需要套上 iso 系統 | ✅ |
| 編輯器/runtime sprite 位移對不上(`_ready()` 算的值 ≠ 烘進 .tscn 的) | ✅ |
| 從頭生一個新 prop(走 Pixellab + import) | ❌ 用 parent `art-pipeline` skill,經 `prop.py` orchestrator |
| 改 `iso_base.py` 演算法本身 / 加 unit test | ❌ 直接編輯程式碼,本 skill 不涵蓋 |
| 修一個非 prop 的 .tscn(zone、UI、character) | ❌ 此演算法只對「PropTemplate 為 root + 一張 Sprite2D + 一個 StaticBody2D 碰撞」的結構有效 |

## 演算法做的事

對每個輸入 .tscn:

1. 讀檔頭的 `Texture2D` ext_resource path,載入 PNG。
2. `iso_base.analyze(png)` 從圖底向上掃,找最寬一列(底座菱形赤道) → 算出 `iso_sort_offset` + 四個菱形頂點(node-relative)。
3. 把 root node 的 `iso_sort_offset` 改成算出來的值。
4. 把 Sprite2D 的 `offset` 重烘成 `Vector2(0, -h/2 + iso_sort_offset)`(編輯器顯示對齊 runtime;`Prop.gd._ready()` 在 runtime 套同一值)。
5. 把 StaticBody2D 下的 collision sub_resource 換成 `ConvexPolygonShape2D`、寫入 4 點,並移除 CollisionShape2D 的 manual `position`(點已是 node-relative)。
6. InteractArea 的矩形碰撞**不動**(那是互動範圍,非物理碰撞)。

全透明 PNG / 找不到 Texture2D / .tscn 結構不符 → 印 `[SKIP]`,不寫檔。

## 怎麼跑

CLI 位置:`pipeline/iso_prop_patch.py`。Bash glob 展開路徑 → 腳本 main 對每個 .tscn 跑 `process_tscn`。

### 單一檔案 dry-run 預覽(必做的安全第一步)

```bash
uv run python pipeline/iso_prop_patch.py --dry-run game/src/maps/props/<name>.tscn
```

預期輸出包含:
```
  <name>.tscn
    iso_sort_offset = <值>
    sprite offset.y = <-h/2 + iso 的值>
    [dry-run] 不寫檔
```

確認數字合理(`-h/2 + iso_sort_offset` 形式;e.g. h=48、iso=11 → -13)。若 iso 異常大或為 0,通常代表 PNG 不是落地型 prop(牆掛、漂浮)—— 演算法假設「底部 = 菱形赤道下半」,牆掛物的演算結果無意義。

### 對特定一組 .tscn 正式跑

```bash
uv run python pipeline/iso_prop_patch.py game/src/maps/props/mod_clock.tscn game/src/maps/props/woodsign.tscn
```

### 對所有 prop 重跑

```bash
uv run python pipeline/iso_prop_patch.py game/src/maps/props/*.tscn
```

PropTemplate.tscn 無 Texture2D → 自動 `[SKIP]`,不必額外排除。已經正確套過的檔 → 印 `-> 無變化`(冪等)。結尾印 `完成:成功 N,略過/失敗 M`。

## 跑完之後

1. **檢查 git diff stat**:
   ```bash
   git diff --stat -- game/src/maps/props/ | tail -20
   ```
   每個變動的檔案應該只有 `iso_sort_offset` / Sprite `offset` / collision sub_resource 行的差異,不會有節點刪除或 ExtResource 變動。

2. **Godot headless 載入確認**(可選但建議):
   ```bash
   "/c/Download Programs/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64.exe" --headless --path game --quit 2>&1 | grep -iE "parse error|SCRIPT" | head
   ```
   無輸出 = 無 prop parse error。

3. **commit scoped**:
   ```bash
   git add game/src/maps/props/
   git commit -m "fix(props): re-run iso_prop_patch on <scope>"
   ```
   **絕對不要 `git add -A`** —— prop 重跑不該帶其他路徑進 commit(歷史上有過 dashboard 測試副作用把無關檔案掃進來的事件)。

4. **人工肉眼確認(我無法替代)**:在 Godot 編輯器開 1–2 個改過的 prop scene,確認 Sprite 位置與遊戲執行時一致。

## 邊界與已知陷阱

- **解析靠的是 .tscn 既有結構**:預期 root node 有 `instance=ExtResource(...)` 指向 PropTemplate,Sprite2D `parent="."`,StaticBody2D 下有一個 CollisionShape2D。若手工 .tscn 結構不符,可能跑出無意義結果或無變化。
- **不會自動移除舊的 Sprite2D `position` 行**:極少數舊版 prop 用 `Sprite2D.position` 而非 `offset` 做錨點。本工具會「補上 offset」但**不會刪掉 position** —— 兩者疊加會雙重位移。發現這種情況要手動清掉 position(歷史上 `notebook_leather.tscn` 就踩過這個雷)。
- **`--collision` preset 已被取代**:`prop.py` 那邊的 `--collision bottom_16x16` 之類 preset 只在 analyze 回 None(全透明 PNG)時當 fallback,有不透明像素就一律走自動菱形。
- **重跑是冪等的**:相同 PNG → 相同輸出。安全跑很多次。

## 相關檔案

- 演算法 SSOT:`pipeline/iso_base.py`(`analyze()`)
- 批次工具:`pipeline/iso_prop_patch.py`
- Pipeline 端整合(新 prop 生成時自動套):`pipeline/orchestrators/_godot_import.py::_write_prop_tscn`
- Runtime 對應:`game/src/maps/props/Prop.gd::_ready()` 把 `sprite.offset = -h/2 + iso_sort_offset`
- 設計 spec:`docs/superpowers/specs/2026-05-29-iso-base-pipeline-integration-design.md`
- 實作 plan:`docs/superpowers/plans/2026-05-29-iso-base-pipeline-integration.md`
