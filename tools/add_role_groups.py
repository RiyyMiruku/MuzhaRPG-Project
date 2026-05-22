"""Retroactively add `prop` / `npc` / `transition` Godot groups to placed nodes
in existing zone scenes.

Classification:
  - parent="YSortRoot" and instance refers to res://src/maps/props/ → "prop"
  - parent="YSortRoot" and instance refers to BaseNPC.tscn / has npc_config → "npc"
  - parent="YSortRoot" and type="Sprite2D" → "npc"  (sprite-based NPCs)
  - parent="YSortRoot" and name=="Player" → skip (singular)
  - parent="Transitions" → "transition"
  - everything else → skip

Idempotent: skips nodes that already have the target group.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

_NODE_LINE = re.compile(r'^\[node (.*)\]\s*$')
_GROUPS_ATTR = re.compile(r' groups=\[([^\]]*)\]')
_EXT_RESOURCE_LINE = re.compile(
    r'^\[ext_resource [^\]]*\bid="([^"]+)"[^\]]*\bpath="([^"]+)"'
    r'|^\[ext_resource [^\]]*\bpath="([^"]+)"[^\]]*\bid="([^"]+)"'
)


def _attr_value(attrs: str, key: str) -> str | None:
    m = re.search(rf'{re.escape(key)}="([^"]*)"', attrs)
    return m.group(1) if m else None


def _ext_id_in_instance(attrs: str) -> str | None:
    m = re.search(r'instance=ExtResource\("([^"]+)"\)', attrs)
    return m.group(1) if m else None


def _strip_groups(attrs: str) -> tuple[str, list[str]]:
    items: list[str] = []
    for m in _GROUPS_ATTR.finditer(attrs):
        for part in m.group(1).split(","):
            p = part.strip()
            if p and p not in items:
                items.append(p)
    clean = _GROUPS_ATTR.sub("", attrs).rstrip()
    return clean, items


def _classify(attrs: str, ext_paths: dict[str, str]) -> str | None:
    """Return 'prop' | 'npc' | 'transition' | None (skip)."""
    parent = _attr_value(attrs, "parent")
    name = _attr_value(attrs, "name")
    if parent == "Transitions":
        return "transition"
    if parent == "YSortRoot":
        if name == "Player":
            return None
        node_type = _attr_value(attrs, "type")
        if node_type == "Sprite2D":
            return "npc"  # sprite-based NPC
        ext_id = _ext_id_in_instance(attrs)
        if ext_id is None:
            return None
        path = ext_paths.get(ext_id, "")
        if "/src/maps/props/" in path:
            return "prop"
        # BaseNPC.tscn or any character/entity instance → npc
        if "BaseNPC" in path or "/src/entities/" in path or "/npcs/" in path:
            return "npc"
        # Unknown — leave alone to be safe
        return None
    return None


def _parse_ext_paths(text: str) -> dict[str, str]:
    """Build {id: path} from [ext_resource] lines."""
    paths: dict[str, str] = {}
    for line in text.splitlines():
        if not line.startswith("[ext_resource"):
            continue
        id_m = re.search(r'\bid="([^"]+)"', line)
        path_m = re.search(r'\bpath="([^"]+)"', line)
        if id_m and path_m:
            paths[id_m.group(1)] = path_m.group(1)
    return paths


def _process_line(line: str, ext_paths: dict[str, str]) -> str:
    m = _NODE_LINE.match(line)
    if not m:
        return line
    attrs = m.group(1)
    role = _classify(attrs, ext_paths)
    if role is None:
        return line
    clean_attrs, group_items = _strip_groups(attrs)
    if role in group_items:
        return line  # already has it
    group_items.insert(0, role)  # role first, then era_*
    groups_attr = ' groups=[' + ", ".join(f'"{g}"' if not g.startswith('"') else g for g in group_items) + ']'
    return f'[node {clean_attrs}{groups_attr}]\n'


def main() -> int:
    zones_dir = Path("game/src/maps/zones")
    scenes = sorted(zones_dir.glob("*.tscn"))
    if not scenes:
        print(f"no .tscn under {zones_dir}", file=sys.stderr)
        return 1

    for scene in scenes:
        original = scene.read_text(encoding="utf-8")
        ext_paths = _parse_ext_paths(original)
        new_lines = [_process_line(line, ext_paths) for line in original.splitlines(keepends=True)]
        new_text = "".join(new_lines)
        if new_text == original:
            print(f"SKIP (no change):  {scene.name}")
            continue
        scene.write_text(new_text, encoding="utf-8")
        print(f"OK:                {scene.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
