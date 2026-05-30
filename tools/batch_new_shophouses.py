"""Generate 6 new shophouse building variants for zone_market."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

BASE = "isometric pixel art, 30-degree top-down angled view, full building with visible roof and two side walls, transparent background — "

ASSETS = [
    ("shophouse_pharmacy_old", 128, 128,
     BASE + "1980s taiwan two-story shophouse pharmacy, green cross medical sign above door, glass window display with medicine bottles and herbal jars, white tiled lower floor facade, iron roll-up shutter half open, neon green cross sign, upper floor white plaster with laundry hanging"),
    ("shophouse_noodle_shop", 128, 128,
     BASE + "taiwanese two-story noodle restaurant shophouse, red cloth banners with chinese characters hanging at entrance, two red paper lanterns flanking door, steamy atmosphere, wooden sign with hand-painted noodle dish, open kitchen visible through doorway, warm amber lighting inside, tiled lower floor"),
    ("shophouse_hardware", 128, 128,
     BASE + "1980s taiwanese two-story hardware store shophouse, corrugated metal roof overhang, tools and pipes hanging outside on wall racks, metal shelving visible inside, cluttered merchandise, faded blue paint on facade, handwritten price signs, galvanized iron goods stacked by entrance"),
    ("shophouse_abandoned", 128, 128,
     BASE + "abandoned derelict two-story taiwanese shophouse, rusted broken metal roll-up shutter, crumbling plaster facade with exposed brick, overgrown weeds at base, boarded up upper windows, peeling paint, faded illegible signboard, dark and empty interior, urban decay"),
    ("shophouse_teahouse", 128, 128,
     BASE + "1980s taiwanese traditional teahouse two-story shophouse, bamboo roll blinds on upper floor, dark wooden facade with carved decorative panels, elegant wooden hanging sign with gold chinese characters for tea, clay teapot display in window, potted plants at entrance, warm aged wood tones"),
    ("shophouse_corner", 160, 128,
     BASE + "taiwanese three-story corner shophouse occupying street corner, wider facade with two street-facing sides visible, concrete and tile construction, different shops on ground floor each side, upper floors residential with laundry poles and potted plants on balconies, rooftop water tank and antenna"),
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
        "--zones", "zone_market",
        "--category", "building",
        "--chapter", "1",
        "--review-mode", "none",
    ]
    result = subprocess.run(cmd, cwd=ROOT, capture_output=False)
    if result.returncode != 0:
        print(f"  [FAILED] exit {result.returncode}", flush=True)
    else:
        print(f"  [OK]", flush=True)

print("\n=== All done ===")
