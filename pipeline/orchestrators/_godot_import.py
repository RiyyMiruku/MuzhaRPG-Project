"""Helpers for copying art-pipeline output into the Godot project tree.

Used by the `import_to_godot` stage of every orchestrator. Single source of
truth for the path layout under `game/assets/textures/` and `game/src/maps/`.
"""
from __future__ import annotations

import hashlib
import shutil
from pathlib import Path
from PIL import Image
import iso_base

UID_ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"

COLLISION_PRESETS: dict[str, tuple[float, float] | str | None] = {
    "none": None,
    "bottom_16x8": (16.0, 8.0),
    "bottom_16x16": (16.0, 16.0),
    "full": "full",
}


def project_root() -> Path:
    # _godot_import.py → orchestrators/ → pipeline/ → <repo root>
    return Path(__file__).resolve().parents[2]


def godot_uid(seed: str) -> str:
    h = hashlib.sha1(seed.encode()).digest()
    n = int.from_bytes(h[:8], "big")
    return "uid://c" + "".join(UID_ALPHABET[(n >> (i * 5)) % 36] for i in range(13))


def _parse_collision(spec: str) -> tuple[float, float] | str | None:
    if spec in COLLISION_PRESETS:
        return COLLISION_PRESETS[spec]
    if "x" in spec.lower():
        try:
            w, h = spec.lower().split("x")
            return (float(w), float(h))
        except ValueError:
            pass
    raise ValueError(f"unknown collision spec: {spec!r}")


def _collision_rect(png_w: int, png_h: int, spec: str) -> tuple[tuple[float, float], tuple[float, float]] | None:
    parsed = _parse_collision(spec)
    if parsed is None:
        return None
    if parsed == "full":
        return ((float(png_w), float(png_h)), (0.0, -png_h / 2.0))
    w, h = parsed
    return ((w, h), (0.0, -h / 2.0))


def import_prop(
    src_png: Path, name: str, collision: str, has_collision: bool,
    *, root: Path | None = None, flip_h: bool = False,
) -> tuple[Path, Path]:
    """Copy prop PNG into Godot tree and generate a .tscn from PropTemplate.

    Returns (game_png_path, game_tscn_path), both absolute.
    """
    root = root or project_root()
    png_dest = root / "game" / "assets" / "textures" / "props" / f"{name}.png"
    tscn_dest = root / "game" / "src" / "maps" / "props" / f"{name}.tscn"
    png_dest.parent.mkdir(parents=True, exist_ok=True)
    tscn_dest.parent.mkdir(parents=True, exist_ok=True)

    shutil.copyfile(src_png, png_dest)
    _write_prop_tscn(
        tscn_dest, png_dest, name, collision, has_collision,
        flip_h=flip_h, root=root,
    )
    return png_dest, tscn_dest


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


def import_tileset(src_png: Path, name: str, *, root: Path | None = None) -> Path:
    root = root or project_root()
    dest = root / "game" / "assets" / "textures" / "tilesets" / f"{name}.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src_png, dest)
    return dest


def import_character_spritesheet(
    src_png: Path, src_atlas_json: Path, name: str,
    *, root: Path | None = None,
) -> tuple[Path, Path]:
    root = root or project_root()
    png_dest = root / "game" / "assets" / "textures" / "characters" / f"{name}.png"
    json_dest = root / "game" / "assets" / "textures" / "characters" / f"{name}.json"
    png_dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src_png, png_dest)
    shutil.copyfile(src_atlas_json, json_dest)
    return png_dest, json_dest
