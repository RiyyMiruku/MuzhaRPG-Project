# ISO 底座演算法整合進 Prop Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「從 PNG 自動算 iso YSort 偏移 + 菱形碰撞」的演算法收斂成單一 pipeline 模組,讓新生成 prop 在匯入時自動套用,並修復既有 prop 的編輯器/runtime Sprite 峰置不一致。

**Architecture:** 新增 `pipeline/iso_base.py`(`analyze()` + CLI)當 SSOT;`iso_prop_patch.py` 從 `tools/` 搬進 `pipeline/` 並補上 Sprite offset 重烘;`_godot_import.py` 匯入時呼叫 `analyze()` 寫 `iso_sort_offset`、烘 `-h/2+iso_sort_offset` 的 Sprite offset、發 `ConvexPolygonShape2D` 菱形碰撞;最後重跑 patch 修復既有 201 prop。

**Tech Stack:** Python 3.12、numpy、Pillow、pytest;Godot 4.6 `.tscn` 文字格式。

設計來源:`docs/superpowers/specs/2026-05-29-iso-base-pipeline-integration-design.md`

---

## File Structure

- `pipeline/iso_base.py`(新)— `analyze(img_path) -> dict|None` 核心演算法 + 分析報告 CLI。唯一 SSOT。
- `pipeline/iso_prop_patch.py`(從 `tools/` 搬入)— 批次 patch 既有 `.tscn` 的 CLI;`from iso_base import analyze`;新增 Sprite offset 重烘。
- `pipeline/orchestrators/_godot_import.py`(改)— `_write_prop_tscn` 呼叫 `analyze()`,寫 iso_sort_offset / 烘 sprite offset / 發菱形碰撞 / 全透明 fallback 回矩形。
- `tools/iso_base_analyze.py`、`tools/iso_prop_patch.py`(刪)。
- `tests/test_iso_base.py`(新)、`tests/test_iso_prop_patch.py`(新)、`tests/test_godot_import.py`(改)。
- `game/src/maps/props/*.tscn`(Task 5 重跑修復)。

---

## Task 1: `pipeline/iso_base.py` — analyze + CLI

**Files:**
- Create: `pipeline/iso_base.py`
- Test: `tests/test_iso_base.py`

- [ ] **Step 1: 寫 failing test**

Create `tests/test_iso_base.py`:

```python
from pathlib import Path

import numpy as np
from PIL import Image

import iso_base


def _make_diamond_png(path: Path, w: int = 32, h: int = 32) -> None:
    """畫一個底座菱形:赤道在 y=h//2,半寬 h//4,線性收到上下頂點。"""
    arr = np.zeros((h, w, 4), dtype=np.uint8)
    cx, eq, max_hw = w // 2, h // 2, h // 4
    for y in range(h):
        hw = max_hw - abs(y - eq)
        if hw < 0:
            continue
        arr[y, cx - hw : cx + hw + 1, :] = (255, 0, 0, 255)
    Image.fromarray(arr, "RGBA").save(path)


def test_analyze_diamond(tmp_path):
    png = tmp_path / "diamond.png"
    _make_diamond_png(png, 32, 32)

    r = iso_base.analyze(png)
    assert r is not None
    assert r["tex_size"] == (32, 32)
    # 赤道在 image y=16 → iso_sort_offset = (32-1) - 16 = 15
    assert r["iso_sort_offset"] == 15.0
    # node-relative 四點:front, right, back, left
    assert r["collision_points"] == [(0.0, 8.0), (8.0, 0.0), (0.0, -8.0), (-8.0, 0.0)]


def test_analyze_transparent_returns_none(tmp_path):
    png = tmp_path / "blank.png"
    Image.new("RGBA", (16, 16), (0, 0, 0, 0)).save(png)
    assert iso_base.analyze(png) is None
```

- [ ] **Step 2: 跑測試確認 fail**

Run: `uv run pytest tests/test_iso_base.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'iso_base'`

- [ ] **Step 3: 寫 `pipeline/iso_base.py`**

```python
#!/usr/bin/env python3
"""iso_base.py — 從 ISO prop PNG 計算 YSort 偏移與碰撞菱形四點(pipeline SSOT)。

演算法:
  從圖片底部逐 row 向上掃描非透明像素寬度。寬度持續增加 → 仍在底座菱形下半;
  寬度停止增加 → 找到最寬列 = 菱形赤道 = YSort 基準點。已知前端底部 + 左右側,
  以赤道對稱推算後端第四點。

CLI:
  uv run python pipeline/iso_base.py game/assets/textures/props/foo.png [...]
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

# 連續縮減幾個 row 才確認已過赤道(容忍偶發鋸齒)
_SHRINK_CONFIRM = 2


def analyze(img_path: Path) -> dict | None:
    img = Image.open(img_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]
    alpha = arr[:, :, 3]

    # 1. 找最底部非透明 row
    bottom_y = None
    for y in range(h - 1, -1, -1):
        if np.any(alpha[y] > 0):
            bottom_y = y
            break
    if bottom_y is None:
        return None  # 全透明圖

    # 2. 從底部向上收集每 row 的 [left_x, right_x]
    rows: dict[int, tuple[int, int]] = {}
    for y in range(bottom_y, -1, -1):
        nz = np.where(alpha[y] > 0)[0]
        if len(nz) == 0:
            break  # 透明縫隙,停止
        rows[y] = (int(nz[0]), int(nz[-1]))

    # 3. 找赤道(最寬 row)
    widest_y = bottom_y
    widest_left, widest_right = rows[bottom_y]
    max_width = widest_right - widest_left
    shrink_count = 0
    for y in range(bottom_y - 1, min(rows.keys()) - 1, -1):
        if y not in rows:
            break
        left, right = rows[y]
        width = right - left
        if width > max_width:
            max_width = width
            widest_y = y
            widest_left, widest_right = left, right
            shrink_count = 0
        else:
            shrink_count += 1
            if shrink_count >= _SHRINK_CONFIRM:
                break

    # 4. 各點(image pixel 座標)
    center_x = (widest_left + widest_right) / 2.0
    back_y = 2 * widest_y - bottom_y
    iso_sort_offset = (h - 1) - widest_y

    # 5. 轉 node-relative:widest row 對齊 y=0,x 以圖中心為 0
    def to_node(px: float, py: float) -> tuple[float, float]:
        return (px - w / 2, py - widest_y)

    return {
        "iso_sort_offset": float(iso_sort_offset),
        "tex_size": (w, h),
        "widest_y_img": widest_y,
        "bottom_y_img": bottom_y,
        "back_y_img": back_y,
        "collision_points": [
            to_node(center_x, bottom_y),     # front
            to_node(widest_right, widest_y), # right
            to_node(center_x, back_y),       # back
            to_node(widest_left, widest_y),  # left
        ],
    }


def _fmt_pts(pts: list[tuple[float, float]]) -> str:
    return ", ".join(f"{x:.1f}, {y:.1f}" for x, y in pts)


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)
    for arg in sys.argv[1:]:
        path = Path(arg)
        if not path.exists():
            print(f"[SKIP] 找不到檔案: {path}")
            continue
        r = analyze(path)
        if r is None:
            print(f"[SKIP] 全透明圖: {path.name}")
            continue
        w, h = r["tex_size"]
        print(f"\n{'-' * 60}")
        print(f"  檔案  : {path.name}  ({w}x{h})")
        print(f"  赤道  : image y={r['widest_y_img']}  ->  iso_sort_offset = {r['iso_sort_offset']:.1f}")
        print(f"  底部  : image y={r['bottom_y_img']}")
        print(f"  後端  : image y={r['back_y_img']}  (推算)")
        labels = ["front", "right", "back ", "left "]
        for label, (x, y) in zip(labels, r["collision_points"]):
            print(f"  {label}: ({x:+6.1f}, {y:+6.1f})")
        print("  -- Godot ConvexPolygonShape2D --")
        print(f"  points = PackedVector2Array({_fmt_pts(r['collision_points'])})")
        print(f"  iso_sort_offset = {r['iso_sort_offset']:.1f}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: 跑測試確認 pass**

Run: `uv run pytest tests/test_iso_base.py -v`
Expected: PASS（2 passed）

- [ ] **Step 5: 跑 CLI 抽查一個真實 prop**

Run: `uv run python pipeline/iso_base.py game/assets/textures/props/altar_table_wood.png`
Expected: 印出 `iso_sort_offset = 11.0`、四點與 `PackedVector2Array(...)`

- [ ] **Step 6: Commit**

```bash
git add pipeline/iso_base.py tests/test_iso_base.py
git commit -m "feat(pipeline): add iso_base module (analyze + CLI) as SSOT"
```

---

## Task 2: `pipeline/iso_prop_patch.py` — 搬入 + Sprite offset 重烘

**Files:**
- Create: `pipeline/iso_prop_patch.py`
- Test: `tests/test_iso_prop_patch.py`

- [ ] **Step 1: 寫 failing test**

Create `tests/test_iso_prop_patch.py`:

```python
import iso_prop_patch

_TSCN = """[gd_scene load_steps=5 format=3 uid="uid://test"]

[ext_resource type="PackedScene" uid="uid://muzha_prop_template" path="res://src/maps/props/PropTemplate.tscn" id="4_tmpl"]
[ext_resource type="Texture2D" uid="uid://x" path="res://assets/textures/props/foo.png" id="3_tex"]

[sub_resource type="RectangleShape2D" id="1_rect"]
size = Vector2(16, 16)

[sub_resource type="RectangleShape2D" id="2_irect"]
size = Vector2(48, 16)

[node name="foo" instance=ExtResource("4_tmpl")]
iso_sort_offset = 0.0
[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_tex")
offset = Vector2(0, -24)

[node name="CollisionShape2D" parent="StaticBody2D" index="0"]
position = Vector2(0, -8)
shape = SubResource("1_rect")

[node name="CollisionShape2D" parent="InteractArea" index="0"]
position = Vector2(0, -8)
shape = SubResource("2_irect")
"""


def test_patch_rebakes_sprite_offset_and_diamond():
    out = iso_prop_patch.patch_tscn(
        _TSCN,
        iso_sort_offset=11.0,
        collision_points=[(0.0, 11.0), (23.0, 0.0), (0.0, -11.0), (-24.0, 0.0)],
        tex_h=48,
    )
    # root 寫對 iso_sort_offset
    assert "iso_sort_offset = 11.0" in out
    # Sprite offset 重烘 = -h/2 + iso = -24 + 11 = -13.0  ← 修峰置 bug 的核心
    assert "offset = Vector2(0, -13.0)" in out
    assert "offset = Vector2(0, -24)" not in out
    # body 碰撞換成菱形
    assert "ConvexPolygonShape2D" in out
    assert "points = PackedVector2Array(0.0, 11.0, 23.0, 0.0, 0.0, -11.0, -24.0, 0.0)" in out
    # StaticBody CollisionShape2D 不再有 position
    sb = out[out.index('parent="StaticBody2D"'):]
    sb = sb[: sb.index("[node", 1)]
    assert "position" not in sb
    # InteractArea 仍是矩形且保留 position
    assert 'id="2_irect"' in out
```

- [ ] **Step 2: 跑測試確認 fail**

Run: `uv run pytest tests/test_iso_prop_patch.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'iso_prop_patch'`

- [ ] **Step 3: 寫 `pipeline/iso_prop_patch.py`**

```python
#!/usr/bin/env python3
"""iso_prop_patch.py — 分析 ISO prop PNG 並更新對應 .tscn 的碰撞形狀、
iso_sort_offset 與 Sprite offset(批次手動 re-patch 用途)。

做的事:
  1. 用 iso_base.analyze 找底座菱形赤道 + 四頂點
  2. 把 StaticBody 的 CollisionShape2D 換成 ConvexPolygonShape2D
  3. 設 root 的 iso_sort_offset
  4. 把 Sprite2D 的 offset 重烘成 -h/2 + iso_sort_offset(編輯器/runtime 對齊)

用法:
  uv run python pipeline/iso_prop_patch.py --dry-run game/src/maps/props/altar_table_wood.tscn
  uv run python pipeline/iso_prop_patch.py game/src/maps/props/*.tscn
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

from iso_base import analyze

_GAME_ROOT = Path(__file__).parent.parent / "game"


def parse_blocks(content: str) -> list[tuple[str, list[str]]]:
    """回傳 [(header_line, [body_lines]), ...],保留原始換行。"""
    blocks: list[tuple[str, list[str]]] = []
    header: str | None = None
    body: list[str] = []
    for line in content.splitlines(keepends=True):
        if line.startswith("["):
            if header is not None:
                blocks.append((header, body))
            header = line
            body = []
        else:
            if header is None:
                blocks.append((line, []))
            else:
                body.append(line)
    if header is not None:
        blocks.append((header, body))
    return blocks


def blocks_to_str(blocks: list[tuple[str, list[str]]]) -> str:
    return "".join(h + "".join(b) for h, b in blocks)


def patch_tscn(
    content: str,
    iso_sort_offset: float,
    collision_points: list,
    tex_h: int,
) -> str:
    blocks = parse_blocks(content)
    pts_str = ", ".join(f"{x:.1f}, {y:.1f}" for x, y in collision_points)
    sprite_offset_y = -tex_h / 2.0 + iso_sort_offset

    # Step 1: 找 StaticBody2D 下 CollisionShape2D 用的 shape sub_resource ID
    collision_shape_id: str | None = None
    in_static_coll = False
    for header, body in blocks:
        if re.search(r'\[node name="CollisionShape2D" parent="StaticBody2D"', header):
            in_static_coll = True
        elif header.startswith("[node") or header.startswith("[sub_resource"):
            in_static_coll = False
        if in_static_coll:
            for line in body:
                m = re.search(r'shape\s*=\s*SubResource\("([^"]+)"\)', line)
                if m:
                    collision_shape_id = m.group(1)
                    break
        if collision_shape_id:
            break

    # Step 2: 逐 block 修改
    new_blocks: list[tuple[str, list[str]]] = []
    for header, body in blocks:
        # root node(PropTemplate instance):重寫 iso_sort_offset
        if re.search(r"instance=ExtResource\(", header) and "parent" not in header:
            new_body = [l for l in body if not re.match(r"\s*iso_sort_offset\s*=", l)]
            insert_pos = 0
            while insert_pos < len(new_body) and new_body[insert_pos].strip() == "":
                insert_pos += 1
            new_body.insert(insert_pos, f"iso_sort_offset = {iso_sort_offset}\n")
            new_blocks.append((header, new_body))
            continue

        # Sprite2D 節點:重烘 offset = -h/2 + iso_sort_offset
        if re.search(r'\[node name="Sprite2D" parent="\."', header):
            new_body = []
            replaced = False
            for l in body:
                if re.match(r"\s*offset\s*=", l):
                    new_body.append(f"offset = Vector2(0, {sprite_offset_y})\n")
                    replaced = True
                else:
                    new_body.append(l)
            if not replaced:
                new_body.append(f"offset = Vector2(0, {sprite_offset_y})\n")
            new_blocks.append((header, new_body))
            continue

        # 碰撞形狀 sub_resource → ConvexPolygonShape2D
        id_match = re.search(r'id="([^"]+)"', header)
        if id_match and id_match.group(1) == collision_shape_id:
            new_header = re.sub(r'type="[^"]+"', 'type="ConvexPolygonShape2D"', header)
            new_body = [f"points = PackedVector2Array({pts_str})\n", "\n"]
            new_blocks.append((new_header, new_body))
            continue

        # StaticBody 下 CollisionShape2D:移除 position(點已 node-relative)
        if re.search(r'\[node name="CollisionShape2D" parent="StaticBody2D"', header):
            new_body = [l for l in body if not re.match(r"\s*position\s*=", l)]
            new_blocks.append((header, new_body))
            continue

        new_blocks.append((header, body))

    return blocks_to_str(new_blocks)


def process_tscn(tscn_path: Path, dry_run: bool) -> bool:
    content = tscn_path.read_text(encoding="utf-8")
    m = re.search(r'type="Texture2D"[^\n]*path="res://([^"]+\.png)"', content)
    if not m:
        print(f"  [SKIP] 找不到 Texture2D: {tscn_path.name}")
        return False
    png_path = _GAME_ROOT / m.group(1)
    if not png_path.exists():
        print(f"  [SKIP] PNG 不存在: {png_path}")
        return False
    result = analyze(png_path)
    if result is None:
        print(f"  [SKIP] PNG 全透明: {tscn_path.name}")
        return False

    tex_h = result["tex_size"][1]
    new_content = patch_tscn(
        content, result["iso_sort_offset"], result["collision_points"], tex_h
    )
    sprite_y = -tex_h / 2.0 + result["iso_sort_offset"]
    print(f"  {tscn_path.name}")
    print(f"    iso_sort_offset = {result['iso_sort_offset']:.1f}")
    print(f"    sprite offset.y = {sprite_y}")
    if dry_run:
        print("    [dry-run] 不寫檔")
    elif new_content != content:
        tscn_path.write_text(new_content, encoding="utf-8")
        print("    -> 已更新")
    else:
        print("    -> 無變化")
    return True


def main() -> None:
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    paths = [Path(a) for a in args if not a.startswith("--")]
    if not paths:
        print(__doc__)
        sys.exit(0)
    ok = fail = 0
    for p in paths:
        if p.suffix != ".tscn":
            print(f"  [SKIP] 非 .tscn: {p}")
            continue
        if not p.exists():
            print(f"  [SKIP] 檔案不存在: {p}")
            fail += 1
            continue
        print()
        if process_tscn(p, dry_run):
            ok += 1
        else:
            fail += 1
    print(f"\n完成:成功 {ok},略過/失敗 {fail}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: 跑測試確認 pass**

Run: `uv run pytest tests/test_iso_prop_patch.py -v`
Expected: PASS（1 passed）

- [ ] **Step 5: Commit**

```bash
git add pipeline/iso_prop_patch.py tests/test_iso_prop_patch.py
git commit -m "feat(pipeline): move iso_prop_patch in, rebake sprite offset (fixes editor/runtime drift)"
```

---

## Task 3: `_godot_import.py` — 匯入時套用 iso 演算法

**Files:**
- Modify: `pipeline/orchestrators/_godot_import.py`
- Test: `tests/test_godot_import.py`

- [ ] **Step 1: 改寫 `tests/test_godot_import.py` 的相關測試(failing)**

在 `tests/test_godot_import.py` 第 44 行附近,於 `from PIL import Image as _Image` 之後新增 numpy import 與 diamond helper:

```python
import numpy as np


def _make_diamond_png(path: Path, w: int = 32, h: int = 32) -> None:
    arr = np.zeros((h, w, 4), dtype=np.uint8)
    cx, eq, max_hw = w // 2, h // 2, h // 4
    for y in range(h):
        hw = max_hw - abs(y - eq)
        if hw < 0:
            continue
        arr[y, cx - hw : cx + hw + 1, :] = (255, 0, 0, 255)
    _Image.fromarray(arr, "RGBA").save(path)
```

把 `test_import_prop_with_collision` 整段替換為:

```python
def test_import_prop_with_collision(tmp_path):
    src = tmp_path / "src" / "world_tree.png"
    src.parent.mkdir()
    _make_diamond_png(src, 32, 32)

    png_dest, tscn_dest = import_prop(
        src_png=src, name="world_tree",
        collision="bottom_16x16", has_collision=True,
        root=tmp_path,
    )
    assert png_dest == tmp_path / "game/assets/textures/props/world_tree.png"
    assert tscn_dest == tmp_path / "game/src/maps/props/world_tree.tscn"
    body = tscn_dest.read_text(encoding="utf-8")
    assert "load_steps=5" in body
    assert 'instance=ExtResource("4_tmpl")' in body
    assert "has_collision = true" in body
    # 菱形取代矩形當 StaticBody 碰撞
    assert "ConvexPolygonShape2D" in body
    # 赤道 image y=16 → iso_sort_offset 15.0
    assert "iso_sort_offset = 15.0" in body
    # sprite offset 烘 = -h/2 + iso = -16 + 15 = -1.0(編輯器/runtime 對齊)
    assert "offset = Vector2(0, -1.0)" in body
    # StaticBody CollisionShape2D 無手動 position
    start = body.index('[node name="CollisionShape2D" parent="StaticBody2D"')
    end = body.index("[node", start + 1)
    assert "position" not in body[start:end]
    assert 'type="Texture2D" uid="uid://c' in body
    assert 'path="res://assets/textures/props/world_tree.png"' in body
```

把 `test_import_prop_no_collision` 整段替換為(加 iso_sort_offset 斷言):

```python
def test_import_prop_no_collision(tmp_path):
    src = tmp_path / "src" / "lantern_red.png"
    src.parent.mkdir()
    _make_diamond_png(src, 32, 32)

    png_dest, tscn_dest = import_prop(
        src_png=src, name="lantern_red",
        collision="none", has_collision=False,
        root=tmp_path,
    )
    body = tscn_dest.read_text(encoding="utf-8")
    assert "load_steps=4" in body
    assert "has_collision = false" in body
    # 無碰撞仍寫 iso_sort_offset(Y-sort 需要)
    assert "iso_sort_offset = 15.0" in body
    assert "ConvexPolygonShape2D" not in body
```

在 `test_import_prop_no_collision` 之後新增全透明 fallback 測試:

```python
def test_import_prop_transparent_fallback(tmp_path):
    src = tmp_path / "src" / "ghost.png"
    src.parent.mkdir()
    _Image.new("RGBA", (32, 32), (0, 0, 0, 0)).save(src)  # 全透明

    _, tscn_dest = import_prop(
        src_png=src, name="ghost",
        collision="bottom_16x16", has_collision=True,
        root=tmp_path,
    )
    body = tscn_dest.read_text(encoding="utf-8")
    # analyze 回 None → fallback 回矩形 preset
    assert "ConvexPolygonShape2D" not in body
    assert "RectangleShape2D" in body
    assert "iso_sort_offset = 0.0" in body
    # sprite offset = -h/2 + 0 = -16.0
    assert "offset = Vector2(0, -16.0)" in body
```

- [ ] **Step 2: 跑測試確認 fail**

Run: `uv run pytest tests/test_godot_import.py -v`
Expected: FAIL — `test_import_prop_with_collision`（找不到 `ConvexPolygonShape2D` / `iso_sort_offset`）、`test_import_prop_transparent_fallback` 等

- [ ] **Step 3: 改 `_godot_import.py`**

在檔案頂部 import 區(第 11 行 `from PIL import Image` 之後)新增:

```python
import iso_base
```

把 `_write_prop_tscn`（第 78-145 行）整個函式替換為:

```python
def _write_prop_tscn(
    tscn_path: Path, png_path: Path, name: str, collision: str, has_collision: bool,
    *, root: Path, flip_h: bool = False,
) -> None:
    with Image.open(png_path) as im:
        w, h = im.size

    analysis = iso_base.analyze(png_path)
    iso_sort_offset = analysis["iso_sort_offset"] if analysis else 0.0

    interact_size = (float(w), min(float(h), 16.0))
    interact_pos = (0.0, -interact_size[1] / 2.0)

    # Body 碰撞:analyze 成功用自動菱形;全透明則 fallback 回矩形 preset。
    use_diamond = has_collision and analysis is not None
    rect_coll = (
        _collision_rect(w, h, collision)
        if (has_collision and analysis is None)
        else None
    )
    body_has_coll = use_diamond or (rect_coll is not None)
    has_coll = "true" if body_has_coll else "false"

    # 從現有 .png.import 讀真正 UID;沒有就生 deterministic 的(Godot 之後會覆寫)
    import_file = png_path.with_suffix(png_path.suffix + ".import")
    tex_uid: str | None = None
    if import_file.exists():
        import re as _re
        m = _re.search(r'uid="(uid://[^"]+)"', import_file.read_text(encoding="utf-8"))
        if m:
            tex_uid = m.group(1)
    if tex_uid is None:
        tex_uid = godot_uid("tex:" + name)
    scene_uid = godot_uid("scene:" + name)
    template_uid = "uid://muzha_prop_template"

    rel_png = "res://" + str(png_path.relative_to(root / "game")).replace("\\", "/")
    rel_template = "res://src/maps/props/PropTemplate.tscn"

    parts: list[str] = []
    load_steps = 4 if not body_has_coll else 5
    parts.append(f'[gd_scene load_steps={load_steps} format=3 uid="{scene_uid}"]\n')
    parts.append(f'[ext_resource type="PackedScene" uid="{template_uid}" path="{rel_template}" id="4_tmpl"]')
    parts.append(f'[ext_resource type="Texture2D" uid="{tex_uid}" path="{rel_png}" id="3_tex"]\n')

    if use_diamond:
        pts = ", ".join(f"{x:.1f}, {y:.1f}" for x, y in analysis["collision_points"])
        parts.append(
            f'[sub_resource type="ConvexPolygonShape2D" id="1_shape"]\n'
            f'points = PackedVector2Array({pts})\n'
        )
    elif rect_coll is not None:
        size, _ = rect_coll
        parts.append(
            f'[sub_resource type="RectangleShape2D" id="1_shape"]\n'
            f'size = Vector2({size[0]}, {size[1]})\n'
        )
    parts.append(
        f'[sub_resource type="RectangleShape2D" id="2_irect"]\n'
        f'size = Vector2({interact_size[0]}, {interact_size[1]})\n'
    )

    parts.append(
        f'[node name="{name}" instance=ExtResource("4_tmpl")]\n'
        f'has_collision = {has_coll}\n'
        f'iso_sort_offset = {iso_sort_offset}\n'
    )
    # 烘 foot-anchor + iso 偏移進 .tscn,讓編輯器顯示對齊 runtime;
    # Prop.gd._ready() 在 foot_anchor 開時會套同一值。
    sprite_lines = [
        '[node name="Sprite2D" parent="." index="0"]',
        'texture = ExtResource("3_tex")',
        f'offset = Vector2(0, {-h / 2.0 + iso_sort_offset})',
    ]
    if flip_h:
        sprite_lines.append("flip_h = true")
    parts.append("\n".join(sprite_lines) + "\n")

    if body_has_coll:
        if use_diamond:
            parts.append(
                f'[node name="CollisionShape2D" parent="StaticBody2D" index="0"]\n'
                f'shape = SubResource("1_shape")\n'
            )
        else:
            _, pos = rect_coll
            parts.append(
                f'[node name="CollisionShape2D" parent="StaticBody2D" index="0"]\n'
                f'position = Vector2({pos[0]}, {pos[1]})\n'
                f'shape = SubResource("1_shape")\n'
            )

    parts.append(
        f'[node name="CollisionShape2D" parent="InteractArea" index="0"]\n'
        f'position = Vector2({interact_pos[0]}, {interact_pos[1]})\n'
        f'shape = SubResource("2_irect")\n'
    )
    tscn_path.write_text("\n".join(parts), encoding="utf-8")
```

- [ ] **Step 4: 跑整組 godot_import 測試確認 pass**

Run: `uv run pytest tests/test_godot_import.py -v`
Expected: PASS（全綠,含改寫的 with_collision / no_collision 與新的 transparent_fallback;既有 flip 測試不受影響）

- [ ] **Step 5: Commit**

```bash
git add pipeline/orchestrators/_godot_import.py tests/test_godot_import.py
git commit -m "feat(pipeline): apply iso analyze on prop import (offset + diamond collision)"
```

---

## Task 4: 刪除 `tools/` 舊腳本 + 更新引用

**Files:**
- Delete: `tools/iso_base_analyze.py`, `tools/iso_prop_patch.py`
- Modify: 任何引用舊路徑的 docs

- [ ] **Step 1: 找舊路徑引用**

Run: `grep -rn "iso_base_analyze\|iso_prop_patch" --include=*.md --include=*.py . | grep -v "docs/superpowers/\(specs\|plans\)/2026-05-29-iso" | grep -v "pipeline/iso_" | grep -v "tests/test_iso"`
Expected: 列出 docs / README 中對 `tools/iso_*.py` 的引用(可能為空)

- [ ] **Step 2: 把找到的引用改成新路徑**

對每個命中,把 `tools/iso_base_analyze.py` → `pipeline/iso_base.py`、`tools/iso_prop_patch.py` → `pipeline/iso_prop_patch.py`(用法字串 `uv run tools/...` → `uv run python pipeline/...`)。若 Step 1 為空則跳過。

- [ ] **Step 3: 刪除舊腳本**

```bash
git rm tools/iso_base_analyze.py tools/iso_prop_patch.py
```

- [ ] **Step 4: 確認測試與 import 仍全綠**

Run: `uv run pytest tests/test_iso_base.py tests/test_iso_prop_patch.py tests/test_godot_import.py -v`
Expected: PASS（無對已刪檔的殘留 import）

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(tools): remove iso_* scripts superseded by pipeline modules"
```

---

## Task 5: 重跑 patch 修復既有 201 個 prop

**Files:**
- Modify: `game/src/maps/props/*.tscn`（由腳本批次寫入）

- [ ] **Step 1: dry-run 抽查一個已知值**

Run: `uv run python pipeline/iso_prop_patch.py --dry-run game/src/maps/props/altar_table_wood.tscn`
Expected: 印 `iso_sort_offset = 11.0`、`sprite offset.y = -13.0`，且標示 `[dry-run] 不寫檔`

- [ ] **Step 2: 正式重跑全部 prop**

Run: `uv run python pipeline/iso_prop_patch.py game/src/maps/props/*.tscn`
Expected: 結尾印「完成:成功 N…」(N 接近 201;全透明/特殊檔可能 SKIP)

- [ ] **Step 3: 驗證峰置 bug 已修(altar)**

Run: `grep -n "offset = Vector2(0, -13" game/src/maps/props/altar_table_wood.tscn`
Expected: 命中 Sprite2D 的 `offset = Vector2(0, -13.0)`（原本 `-24`）

- [ ] **Step 4: 確認 Godot 載入無 parse error**

Run: `& "C:\Download Programs\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --headless --path game --quit`
Expected: 只印引擎 banner,無 SCRIPT/parse error

- [ ] **Step 5: 人工抽查編輯器/runtime 對齊(手動)**

在 Godot 編輯器開 1-2 個 prop scene（如 `altar_table_wood.tscn`）確認 Sprite 在編輯器的位置與遊戲執行時一致(不再差 iso_sort_offset px)。若仍有偏差 → 回 systematic-debugging。

- [ ] **Step 6: Commit**

```bash
git add game/src/maps/props/
git commit -m "fix(props): rebake sprite offset on all props to match runtime iso_sort_offset"
```

---

## Self-Review Notes

- **Spec §1 pipeline 自動套用** → Task 3 ✓
- **Spec §1 `iso_base.py` analyze+CLI / SSOT** → Task 1 ✓
- **Spec §2 `iso_prop_patch.py` 搬入 + sprite 重烘** → Task 2 ✓
- **Spec §3 刪 tools + 更新引用** → Task 4 ✓
- **Spec §4 `_write_prop_tscn`(iso_sort_offset / sprite bake / 菱形 / InteractArea 不變)** → Task 3 ✓
- **Spec §5 邊界(全透明 fallback / no-collision 仍寫 offset / --collision 不再決定 StaticBody)** → Task 3 程式 + 測試 ✓
- **Spec §6 重跑修復既有 201** → Task 5 ✓
- **Spec「已知 bug」根因(.tscn bake 須等於 _ready 的 -h/2+iso)** → Task 2 sprite 重烘 + Task 3 pipeline bake + Task 5 重跑,三處一致 ✓
- **Spec 測試清單**(test_iso_base / 擴 test_godot_import / test_iso_prop_patch 回歸) → Task 1 / 3 / 2 ✓
- **型別一致**:`analyze` 回 dict 含 `iso_sort_offset: float`、`tex_size`、`collision_points`;`patch_tscn(content, iso_sort_offset, collision_points, tex_h)`;`_write_prop_tscn` 用 `analysis["collision_points"]` / `["iso_sort_offset"]` — 跨 task 一致。
- **sub_resource id**:pipeline 端統一用 `1_shape`(取代舊 `1_rect`);patch 端沿用 .tscn 既有 id(透過 `collision_shape_id` 動態抓),兩者互不衝突。
