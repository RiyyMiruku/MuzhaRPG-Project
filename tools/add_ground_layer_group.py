"""One-shot: tag `ground_layer` Godot group on every TileMapDual node
under all zone scenes.

Why TileMapDual (child) instead of TileMapLayer (parent):
TileMapDual addon puts `tile_set` and `tile_map_data` on the CHILD node;
the parent TileMapLayer is just a container. Player.gd reads
`best_layer.tile_set.resource_path`, so the group must be on the child.

Also undoes any prior incorrect placement on parent TileMapLayer nodes.

Re-runnable: idempotent on already-grouped nodes.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

_NODE_LINE = re.compile(r'^\[node (.*)\]\s*$')
_GROUPS_ATTR = re.compile(r' groups=\[([^\]]*)\]')


def _attr_value(attrs: str, key: str) -> str | None:
    """Extract a key="value" attribute, returning the inner value or None."""
    m = re.search(rf'{re.escape(key)}="([^"]*)"', attrs)
    return m.group(1) if m else None


def _strip_groups(attrs: str) -> tuple[str, list[str]]:
    """Remove all groups=[...] occurrences from attrs; return (clean_attrs, list_of_items)."""
    items: list[str] = []
    for m in _GROUPS_ATTR.finditer(attrs):
        for part in m.group(1).split(","):
            p = part.strip()
            if p and p not in items:
                items.append(p)
    clean = _GROUPS_ATTR.sub("", attrs).rstrip()
    return clean, items


def _process_line(line: str) -> str:
    m = _NODE_LINE.match(line)
    if not m:
        return line
    attrs = m.group(1)
    node_type = _attr_value(attrs, "type")
    node_name = _attr_value(attrs, "name")
    parent = _attr_value(attrs, "parent")
    if node_type != "TileMapLayer" or node_name is None or parent is None:
        return line

    clean_attrs, group_items = _strip_groups(attrs)

    # Determine intended group state:
    # - Parent TileMapLayer (parent==".") with name=="TileMapLayer": should NOT have ground_layer
    # - Any TileMapDual* node (child of a TileMapLayer): SHOULD have ground_layer
    is_parent_layer = (parent == "." and node_name == "TileMapLayer")
    is_dual_child = node_name.startswith("TileMapDual")

    target = '"ground_layer"'
    if is_parent_layer:
        # remove ground_layer from parent (cleanup from previous version)
        group_items = [g for g in group_items if g != target]
    elif is_dual_child:
        if target not in group_items:
            group_items.append(target)
    else:
        # Some other TileMapLayer node — leave alone.
        return line

    if group_items:
        groups_attr = ' groups=[' + ", ".join(group_items) + ']'
    else:
        groups_attr = ''

    return f'[node {clean_attrs}{groups_attr}]\n'


def main() -> int:
    zones_dir = Path("game/src/maps/zones")
    scenes = sorted(zones_dir.glob("*.tscn"))
    if not scenes:
        print(f"no .tscn under {zones_dir}", file=sys.stderr)
        return 1

    for scene in scenes:
        original = scene.read_text(encoding="utf-8")
        new_lines = [_process_line(line) for line in original.splitlines(keepends=True)]
        new_text = "".join(new_lines)
        if new_text == original:
            print(f"SKIP (no change):  {scene.name}")
            continue
        scene.write_text(new_text, encoding="utf-8")
        print(f"OK:                {scene.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
