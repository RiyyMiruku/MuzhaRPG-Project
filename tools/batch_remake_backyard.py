"""Batch remake zone_pharmacy_backyard iso_props as iso_building."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

BASE = "isometric pixel art, 30-degree top-down angled view, transparent background — "

ASSETS = [
    ("bed_single_old", 64, 64,
     BASE + "1980s taiwan single bed with folded blanket, wooden bed frame, flat mattress, slightly worn, neat but unused for years"),
    ("broom_dustpan", 48, 48,
     BASE + "bamboo broom and metal dustpan leaning against wall, traditional cleaning tools, 1980s taiwan household"),
    ("chicken_coop_small", 48, 48,
     BASE + "small wooden chicken coop with wire mesh, a few chickens inside, backyard farmyard, 1980s taiwan"),
    ("clothesline_bamboo", 64, 64,
     BASE + "bamboo pole clothesline with hanging clothes and towels, outdoor backyard laundry, 1980s taiwan"),
    ("door_wooden_locked", 64, 64,
     BASE + "old wooden door with brass padlock, weathered dark wood grain, locked mysterious door, 1980s taiwan"),
    ("herb_garden_patch", 48, 48,
     BASE + "small raised herb garden patch with planted medicinal herbs and green leaves, traditional chinese medicine backyard garden, soil visible"),
    ("newspaper_clipping_wall", 32, 32,
     BASE + "newspaper clippings pinned on wall, several yellowed paper cuttings with chinese text, 1980s taiwan"),
    ("potted_plant_clay", 48, 48,
     BASE + "clay pot with green herbs or wan-nian-qing plant, traditional taiwanese backyard, terracotta clay pot"),
    ("rain_barrel_wood", 48, 48,
     BASE + "wooden rain barrel for collecting rainwater, backyard utility, dark brown aged wood with metal bands, 1980s taiwan"),
    ("stone_bench_garden", 48, 48,
     BASE + "simple stone garden bench, grey stone rectangular slab on two short stone legs, courtyard seating, weathered"),
    ("washing_board_wood", 48, 48,
     BASE + "wooden washboard with corrugated surface leaning on basin, traditional laundry tool, 1980s taiwan household"),
    ("well_stone_old", 64, 64,
     BASE + "old stone well with wooden bucket and rope, circular stone wall, overgrown with moss, 1980s taiwan backyard"),
]

total = len(ASSETS)
for i, (name, w, h, desc) in enumerate(ASSETS, 1):
    print(f"\n[{i}/{total}] {name} ({w}x{h})", flush=True)
    cmd = [
        "uv", "run", "python", "-u",
        "pipeline/orchestrators/prop.py",
        "--name", name,
        "--kind", "iso_building",
        "--description", desc,
        "--width", str(w),
        "--height", str(h),
        "--force-restart-stage", "generate_object",
        "--force-restart-stage", "chroma_key",
        "--force-restart-stage", "import_to_godot",
        "--resume-from", "generate_object",
        "--review-mode", "none",
    ]
    result = subprocess.run(cmd, cwd=ROOT, capture_output=False)
    if result.returncode != 0:
        print(f"  [FAILED] exit {result.returncode}", flush=True)
    else:
        print(f"  [OK]", flush=True)

print("\n=== All done ===")
