#!/usr/bin/env python3
"""
iso_base_analyze.py — 自動從 ISO prop PNG 計算 YSort 偏移與碰撞菱形四點

演算法：
  從圖片底部逐 row 向上掃描非透明像素的寬度。
  寬度持續增加 → 仍在底座菱形下半。
  寬度停止增加（開始縮減）→ 找到最寬列 = 菱形赤道 = YSort 基準點。
  已知三點（前端底部、左側、右側）+ 菱形對稱推算第四點（後端）。

輸出：
  iso_sort_offset    — 要填進 Prop.gd 的 export 值
  collision_points   — ConvexPolygonShape2D 的四個頂點（node-relative 座標）

用法:
  uv run tools/iso_base_analyze.py game/assets/textures/props/market_shophouse_concrete.png
  uv run tools/iso_base_analyze.py game/assets/textures/props/*.png
"""

import sys
from pathlib import Path
import numpy as np
from PIL import Image


# 連續縮減幾個 row 才確認已過赤道（容忍偶發鋸齒）
_SHRINK_CONFIRM = 2


def analyze(img_path: Path) -> dict | None:
    img = Image.open(img_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]
    alpha = arr[:, :, 3]

    # ── 1. 找最底部非透明 row ──────────────────────────────────────
    bottom_y = None
    for y in range(h - 1, -1, -1):
        if np.any(alpha[y] > 0):
            bottom_y = y
            break
    if bottom_y is None:
        return None  # 全透明圖

    # ── 2. 從底部向上掃，收集每 row 的 [left_x, right_x] ──────────
    rows: dict[int, tuple[int, int]] = {}
    for y in range(bottom_y, -1, -1):
        nz = np.where(alpha[y] > 0)[0]
        if len(nz) == 0:
            break  # 遇到透明縫隙，停止
        rows[y] = (int(nz[0]), int(nz[-1]))

    # ── 3. 找赤道（最寬 row，寬度停止增加的地方）────────────────────
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
            # 嚴格大於才更新：遇到平台（width 不變）視為已到赤道，停止往上
            max_width = width
            widest_y = y
            widest_left, widest_right = left, right
            shrink_count = 0
        else:
            shrink_count += 1
            if shrink_count >= _SHRINK_CONFIRM:
                break  # 確認寬度已持續縮減或停滯，赤道在此

    # ── 4. 計算各點（image pixel 座標） ─────────────────────────────
    center_x = (widest_left + widest_right) / 2.0
    # 後端尖點：以赤道為軸，鏡射前端底部
    back_y = 2 * widest_y - bottom_y

    # ── 5. 轉換成 node-relative 座標 ────────────────────────────────
    # foot_anchor + iso_sort_offset 後：
    #   sprite.offset.y = -h/2 + iso_sort_offset
    #   pixel(px, py) → node_rel: (px - w/2,  py - h + iso_sort_offset)
    # iso_sort_offset = h - 1 - widest_y  →  widest row 對齊 y=0
    iso_sort_offset = (h - 1) - widest_y

    def to_node(px: float, py: float) -> tuple[float, float]:
        return (px - w / 2, py - widest_y)

    front  = to_node(center_x, bottom_y)   # 前端（最低點）
    right  = to_node(widest_right, widest_y)
    back   = to_node(center_x, back_y)     # 後端（推算）
    left   = to_node(widest_left, widest_y)

    return {
        "iso_sort_offset": iso_sort_offset,
        "tex_size": (w, h),
        "widest_y_img": widest_y,
        "bottom_y_img": bottom_y,
        "back_y_img": back_y,
        "collision_points": [front, right, back, left],
    }


def fmt_pts(pts: list[tuple[float, float]]) -> str:
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
        print(f"\n{'─'*60}")
        print(f"  檔案  : {path.name}  ({w}×{h})")
        print(f"  赤道  : image y={r['widest_y_img']}  →  iso_sort_offset = {r['iso_sort_offset']}")
        print(f"  底部  : image y={r['bottom_y_img']}")
        print(f"  後端  : image y={r['back_y_img']}  (推算)")
        print()
        pts = r["collision_points"]
        labels = ["front (底部前端)", "right (右側)   ", "back  (後端推算)", "left  (左側)   "]
        for label, (x, y) in zip(labels, pts):
            print(f"  {label}: ({x:+6.1f}, {y:+6.1f})")
        print()
        print(f"  ── Godot ConvexPolygonShape2D ──")
        print(f"  points = PackedVector2Array({fmt_pts(pts)})")
        print(f"  iso_sort_offset = {r['iso_sort_offset']}")


if __name__ == "__main__":
    main()
