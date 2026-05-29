"""修正所有 Prop .tscn 的 Sprite2D offset，使其與 Prop.gd foot_anchor 邏輯一致。

foot_anchor 在 _ready() 設定 sprite.offset = Vector2(0, -tex_height / 2)，
但 Godot 編輯器不執行 _ready()，若 .tscn 的 offset 不正確，
編輯器看到的 sprite 位置就與執行時不同，導致碰撞箱調整困難。

執行對象：有碰撞箱（has_collision=true）或有任何 CollisionShape2D 的 prop。
Re-runnable：offset 已正確的 prop 會被略過。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("需要 Pillow：uv run pip install Pillow", file=sys.stderr)
    sys.exit(1)

REPO = Path(__file__).resolve().parent.parent
PROPS_DIR = REPO / "game" / "src" / "maps" / "props"
TEX_DIR = REPO / "game" / "assets" / "textures" / "props"

_OFFSET_LINE = re.compile(r'^(offset = Vector2\()0, ([\-\d\.]+)(\))\s*$', re.MULTILINE)
_HAS_COLLISION = re.compile(r'has_collision\s*=\s*true')
_HAS_COLLISION_SHAPE = re.compile(r'\[node[^\]]*type="CollisionShape2D"')
_SPRITE2D_BLOCK = re.compile(
    r'(\[node name="Sprite2D"[^\]]*\]\n(?:[^\[]*\n)*)',
)


def _needs_fix(content: str) -> bool:
    return bool(_HAS_COLLISION.search(content) or _HAS_COLLISION_SHAPE.search(content))


def _set_sprite_offset(content: str, offset_y: float) -> str:
    """Set or insert offset line in the Sprite2D block."""
    offset_str = f"offset = Vector2(0, {offset_y:.1f})"

    def replace_block(m: re.Match) -> str:
        block = m.group(1)
        if _OFFSET_LINE.search(block):
            # Replace while preserving the trailing newline
            block = _OFFSET_LINE.sub(offset_str + "\n", block)
        else:
            lines = block.splitlines(keepends=True)
            lines.insert(1, offset_str + "\n")
            block = "".join(lines)
        return block

    new_content = _SPRITE2D_BLOCK.sub(replace_block, content)
    return new_content


def main() -> int:
    tscn_files = sorted(PROPS_DIR.glob("*.tscn"))
    tscn_files = [f for f in tscn_files if f.name != "PropTemplate.tscn"]

    changed = skipped = no_tex = no_collision = 0

    for tscn in tscn_files:
        name = tscn.stem
        png = TEX_DIR / f"{name}.png"
        if not png.exists():
            no_tex += 1
            continue

        original = tscn.read_text(encoding="utf-8")
        if not _needs_fix(original):
            no_collision += 1
            continue

        img = Image.open(png)
        _, h = img.size
        expected_y = -(h / 2.0)

        # Check current offset
        m = _OFFSET_LINE.search(original)
        current_y = float(m.group(2)) if m else None

        if current_y is not None and abs(current_y - expected_y) < 0.01:
            skipped += 1
            continue

        new_content = _set_sprite_offset(original, expected_y)
        if new_content == original:
            skipped += 1
            continue

        tscn.write_text(new_content, encoding="utf-8")
        status = "FIXED" if current_y is not None else "ADDED "
        print(f"{status}: {name:40s} offset_y: {current_y} → {expected_y:.1f}  (h={h})")
        changed += 1

    print(f"\n完成：修正 {changed} 個，跳過 {skipped} 個（已正確），"
          f"無碰撞 {no_collision} 個，無貼圖 {no_tex} 個。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
