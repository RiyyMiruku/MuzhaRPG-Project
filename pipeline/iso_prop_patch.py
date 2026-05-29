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
