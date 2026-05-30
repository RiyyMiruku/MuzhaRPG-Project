"""Generate modern corner assets for zone_market bottom-right area."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

BASE = "isometric pixel art, 30-degree top-down angled view, full building with visible roof and two side walls, transparent background — "

ASSETS = [
    ("building_convenience_store", 128, 128,
     BASE + "modern taiwanese convenience store, 7-eleven style, bright white and green facade, large illuminated sign with logo, glass sliding door entrance, fluorescent lit interior visible, promotional posters on windows, modern clean design, urban taiwan street"),
    ("building_bubble_tea", 128, 128,
     BASE + "modern taiwanese hand-shaken drink shop, large colorful LED lightbox sign with bubble tea menu photos, bright pastel colored facade pink or mint green, glass front counter visible with cups and syrups, modern shopfront design, young urban style"),
    ("building_parking_lot", 128, 96,
     BASE + "open air urban parking lot, low concrete perimeter wall with yellow painted curb, painted white parking space lines on dark asphalt ground, entrance gate with metal bar, small booth kiosk at entrance, urban taiwan modern"),
    ("food_truck_modern", 96, 64,
     "isometric pixel art, 30-degree top-down angled view, transparent background — modern taiwanese food truck, white van with colorful painted branding on side, service window open on side with small awning, menu board mounted on vehicle, parked on street, modern urban food vendor"),
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
