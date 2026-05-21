"""掃描 art_source/objects/ 中有 PNG 但缺少 .tscn 的 prop，自動產出 .tscn 到 Godot。

用法：
    uv run python scripts/sync_props.py          # 偵測 + 轉換
    uv run python scripts/sync_props.py --dry-run # 只列出缺的，不轉換
"""
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ART_SOURCE = REPO / "art_source" / "objects"
TSCN_DIR = REPO / "game" / "src" / "maps" / "props"
TEX_DIR = REPO / "game" / "assets" / "textures" / "props"
TEMPLATE = REPO / "game" / "src" / "maps" / "props" / "PropTemplate.tscn"

SKIP = {"test_iso", "test_well", "test_pharmacy_iso", "probe_iso_b"}


def find_missing() -> list[dict]:
    """找出有 PNG 但沒有 .tscn 的 prop。"""
    missing = []
    for obj_dir in sorted(ART_SOURCE.iterdir()):
        if not obj_dir.is_dir():
            continue
        name = obj_dir.name
        if name in SKIP:
            continue
        png = obj_dir / f"{name}.png"
        if not png.exists():
            continue
        tscn = TSCN_DIR / f"{name}.tscn"
        if tscn.exists():
            continue
        # Read asset.json for metadata
        asset_json = obj_dir / "asset.json"
        meta = {}
        if asset_json.exists():
            meta = json.loads(asset_json.read_text(encoding="utf-8"))
        missing.append({"name": name, "png": png, "meta": meta})
    return missing


def generate_tscn(name: str, png_src: Path, meta: dict) -> Path:
    """從 PNG 產出 .tscn，複製 PNG 到 Godot 資源目錄。"""
    from PIL import Image

    # 複製 PNG 到 game/assets/textures/props/
    tex_dst = TEX_DIR / f"{name}.png"
    shutil.copy2(png_src, tex_dst)

    # 讀取圖片尺寸
    img = Image.open(png_src)
    w, h = img.size

    # 根據尺寸計算 offset 和碰撞
    if h > 80:
        offset_y = -(h // 2)
        coll_w, coll_h = int(w * 0.6), int(h * 0.15)
        interact_w, interact_h = int(w * 0.8), int(h * 0.2)
    elif h > 40:
        offset_y = -(h // 4)
        coll_w, coll_h = int(w * 0.5), int(h * 0.25)
        interact_w, interact_h = int(w * 0.7), int(h * 0.3)
    else:
        offset_y = 0
        coll_w, coll_h = max(12, int(w * 0.5)), max(8, int(h * 0.4))
        interact_w, interact_h = max(16, int(w * 0.7)), max(12, int(h * 0.5))

    coll_pos_y = -8 if h > 40 else 0
    offset_line = f"\noffset = Vector2(0, {offset_y})" if offset_y != 0 else ""

    tscn_content = f"""[gd_scene load_steps=4 format=3]

[ext_resource type="PackedScene" uid="uid://muzha_prop_template" path="res://src/maps/props/PropTemplate.tscn" id="1_tmpl"]
[ext_resource type="Texture2D" path="res://assets/textures/props/{name}.png" id="2_tex"]

[sub_resource type="RectangleShape2D" id="1_rect"]
size = Vector2({coll_w}.0, {coll_h}.0)

[sub_resource type="RectangleShape2D" id="2_irect"]
size = Vector2({interact_w}.0, {interact_h}.0)

[node name="{name}" instance=ExtResource("1_tmpl")]
has_collision = true

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("2_tex"){offset_line}

[node name="CollisionShape2D" parent="StaticBody2D" index="0"]
position = Vector2(0.0, {coll_pos_y}.0)
shape = SubResource("1_rect")

[node name="CollisionShape2D" parent="InteractArea" index="0"]
position = Vector2(0.0, {coll_pos_y}.0)
shape = SubResource("2_irect")
"""
    tscn_path = TSCN_DIR / f"{name}.tscn"
    tscn_path.write_text(tscn_content.strip() + "\n", encoding="utf-8")
    return tscn_path


def main():
    import sys, io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

    parser = argparse.ArgumentParser(description="sync art_source -> .tscn")
    parser.add_argument("--dry-run", action="store_true", help="list only, no convert")
    args = parser.parse_args()

    missing = find_missing()

    if not missing:
        print("All props have .tscn, nothing to sync.")
        return

    print(f"找到 {len(missing)} 個缺少 .tscn 的 prop：\n")
    for item in missing:
        print(f"  {item['name']}")

    if args.dry_run:
        print("\n(dry-run 模式，未產生任何檔案)")
        return

    print()
    for item in missing:
        tscn = generate_tscn(item["name"], item["png"], item["meta"])
        print(f"  OK {item['name']} -> {tscn.relative_to(REPO)}")

    print(f"\nDone! Generated {len(missing)} .tscn files. Press Ctrl+Shift+R in Godot to rescan.")


if __name__ == "__main__":
    main()
