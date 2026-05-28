#!/usr/bin/env python3
"""
iso_prop_patch.py — 分析 ISO prop PNG 並自動更新對應 .tscn 的碰撞形狀與 iso_sort_offset

做的事：
  1. 從 PNG 底部向上掃描找到底座菱形赤道（最寬 row）
  2. 推算四個菱形頂點（node-relative 座標）
  3. 把 StaticBody2D 的 CollisionShape2D 換成 ConvexPolygonShape2D
  4. 設定 root node 的 iso_sort_offset

用法:
  # 預覽（不寫檔）
  uv run tools/iso_prop_patch.py --dry-run game/src/maps/props/altar_table_wood.tscn

  # 更新指定 .tscn
  uv run tools/iso_prop_patch.py game/src/maps/props/altar_table_wood.tscn

  # 批次更新所有 prop .tscn
  uv run tools/iso_prop_patch.py game/src/maps/props/*.tscn
"""

import re
import sys
from pathlib import Path
import numpy as np
from PIL import Image

_SHRINK_CONFIRM = 2
_GAME_ROOT = Path(__file__).parent.parent / "game"


# ──────────────────────────────────────────────────────────────
# 分析
# ──────────────────────────────────────────────────────────────

def analyze(img_path: Path) -> dict | None:
    img = Image.open(img_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]
    alpha = arr[:, :, 3]

    bottom_y = None
    for y in range(h - 1, -1, -1):
        if np.any(alpha[y] > 0):
            bottom_y = y
            break
    if bottom_y is None:
        return None

    rows: dict[int, tuple[int, int]] = {}
    for y in range(bottom_y, -1, -1):
        nz = np.where(alpha[y] > 0)[0]
        if len(nz) == 0:
            break
        rows[y] = (int(nz[0]), int(nz[-1]))

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

    center_x = (widest_left + widest_right) / 2.0
    back_y = 2 * widest_y - bottom_y
    iso_sort_offset = (h - 1) - widest_y

    def to_node(px: float, py: float) -> tuple[float, float]:
        return (px - w / 2, py - widest_y)

    return {
        "iso_sort_offset": float(iso_sort_offset),
        "collision_points": [
            to_node(center_x, bottom_y),   # front
            to_node(widest_right, widest_y), # right
            to_node(center_x, back_y),      # back
            to_node(widest_left, widest_y),  # left
        ],
    }


# ──────────────────────────────────────────────────────────────
# .tscn 區塊解析
# ──────────────────────────────────────────────────────────────

def parse_blocks(content: str) -> list[tuple[str, list[str]]]:
    """回傳 [(header_line, [body_lines]), ...] 的列表，保留原始換行。"""
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
                # gd_scene 第一行之前的空行
                blocks.append((line, []))
            else:
                body.append(line)

    if header is not None:
        blocks.append((header, body))
    return blocks


def blocks_to_str(blocks: list[tuple[str, list[str]]]) -> str:
    return "".join(h + "".join(b) for h, b in blocks)


# ──────────────────────────────────────────────────────────────
# .tscn 修改
# ──────────────────────────────────────────────────────────────

def patch_tscn(content: str, iso_sort_offset: float, collision_points: list) -> str:
    blocks = parse_blocks(content)

    pts_str = ", ".join(f"{x:.1f}, {y:.1f}" for x, y in collision_points)

    # Step 1: 找 StaticBody2D 下的 CollisionShape2D 用的 shape sub_resource ID
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

    # collision_shape_id 可能為 None（has_collision=false 的 prop）
    # 此時跳過碰撞形狀更新，但仍寫入 iso_sort_offset

    # Step 2: 逐 block 修改
    new_blocks: list[tuple[str, list[str]]] = []
    for header, body in blocks:

        # ── root node（PropTemplate 的 instance）──
        if re.search(r'instance=ExtResource\(', header) and 'parent' not in header:
            # 過濾掉舊的 iso_sort_offset，重寫
            new_body = [l for l in body if not re.match(r'\s*iso_sort_offset\s*=', l)]
            # 插入新值（緊接 header 之後，保留一個空行分隔）
            insert_pos = 0
            while insert_pos < len(new_body) and new_body[insert_pos].strip() == "":
                insert_pos += 1
            new_body.insert(insert_pos, f"iso_sort_offset = {iso_sort_offset:.1f}\n")
            new_blocks.append((header, new_body))
            continue

        # ── 碰撞形狀 sub_resource ──
        id_match = re.search(r'id="([^"]+)"', header)
        if id_match and id_match.group(1) == collision_shape_id:
            new_header = re.sub(
                r'type="[^"]+"',
                'type="ConvexPolygonShape2D"',
                header,
            )
            new_body = [f"points = PackedVector2Array({pts_str})\n", "\n"]
            new_blocks.append((new_header, new_body))
            continue

        # ── StaticBody2D 下的 CollisionShape2D ──
        if re.search(r'\[node name="CollisionShape2D" parent="StaticBody2D"', header):
            # 移除 position 行（點已是 node-relative，不需要額外偏移）
            new_body = [l for l in body if not re.match(r'\s*position\s*=', l)]
            new_blocks.append((header, new_body))
            continue

        new_blocks.append((header, body))

    return blocks_to_str(new_blocks)


# ──────────────────────────────────────────────────────────────
# 主流程
# ──────────────────────────────────────────────────────────────

def process_tscn(tscn_path: Path, dry_run: bool) -> bool:
    content = tscn_path.read_text(encoding="utf-8")

    # 從 ext_resource 抓 PNG 路徑
    m = re.search(r'type="Texture2D"[^\n]*path="res://([^"]+\.png)"', content)
    if not m:
        print(f"  [SKIP] 找不到 Texture2D: {tscn_path.name}")
        return False

    png_rel = m.group(1)
    png_path = _GAME_ROOT / png_rel
    if not png_path.exists():
        print(f"  [SKIP] PNG 不存在: {png_path}")
        return False

    result = analyze(png_path)
    if result is None:
        print(f"  [SKIP] PNG 全透明: {tscn_path.name}")
        return False

    new_content = patch_tscn(content, result["iso_sort_offset"], result["collision_points"])

    pts = result["collision_points"]
    pts_fmt = ", ".join(f"({x:.1f},{y:.1f})" for x, y in pts)
    print(f"  {tscn_path.name}")
    print(f"    iso_sort_offset = {result['iso_sort_offset']:.1f}")
    print(f"    collision_pts   = {pts_fmt}")

    if dry_run:
        print("    [dry-run] 不寫檔")
    elif new_content != content:
        tscn_path.write_text(new_content, encoding="utf-8")
        print("    → 已更新")
    else:
        print("    → 無變化")

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
        if not p.suffix == ".tscn":
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

    print(f"\n完成：成功 {ok}，略過/失敗 {fail}")


if __name__ == "__main__":
    main()
