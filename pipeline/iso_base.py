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
