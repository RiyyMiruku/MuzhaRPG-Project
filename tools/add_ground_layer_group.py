"""One-shot: add `ground_layer` Godot group to the parent TileMapLayer
of every zone scene under game/src/maps/zones/.

Pattern targeted (Godot 4 .tscn):
    [node name="TileMapLayer" type="TileMapLayer" parent="." unique_id=...]
->  [node name="TileMapLayer" type="TileMapLayer" parent="." groups=["ground_layer"] unique_id=...]

Skips files where the parent layer is already in the group, or no parent
TileMapLayer line exists.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

_NODE_RE = re.compile(
    r'(\[node name="TileMapLayer" type="TileMapLayer" parent="\.")'
    r'([^\]]*?)'
    r'(\])'
)


def main() -> int:
    zones_dir = Path("game/src/maps/zones")
    scenes = sorted(zones_dir.glob("*.tscn"))
    if not scenes:
        print(f"no .tscn under {zones_dir}", file=sys.stderr)
        return 1

    for scene in scenes:
        text = scene.read_text(encoding="utf-8")
        m = _NODE_RE.search(text)
        if m is None:
            print(f"SKIP (no parent TileMapLayer): {scene.name}")
            continue
        if "ground_layer" in m.group(0):
            print(f"SKIP (already grouped):       {scene.name}")
            continue
        new_text = _NODE_RE.sub(
            r'\1 groups=["ground_layer"]\2\3',
            text,
            count=1,
        )
        scene.write_text(new_text, encoding="utf-8")
        print(f"OK:                             {scene.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
