"""Batch remake zone_market iso_props that need transparent-bg sprites as iso_building."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ASSETS = [
    # (name, width, height, description)
    ("awning_retractable", 64, 64, "isometric pixel art, 30-degree top-down angled view, retractable fabric awning over shop front, striped red white pattern, extending outward"),
    ("balcony_railing_iron", 64, 64, "isometric pixel art, 30-degree top-down angled view, iron balcony railing with laundry hanging, 1980s Taiwan apartment building"),
    ("banner_cloth_sale", 48, 48, "isometric pixel art, 30-degree top-down angled view, red cloth banner with white hand-painted chinese sale text, hanging vertically"),
    ("bicycle_parked", 64, 64, "isometric pixel art, 30-degree top-down angled view, old black bicycle with front wire basket, parked standing upright, 1980s Taiwan"),
    ("birdcage_bamboo", 48, 48, "isometric pixel art, 30-degree top-down angled view, round bamboo birdcage with small bird inside, hung from pole"),
    ("broken_window", 48, 48, "isometric pixel art, 30-degree top-down angled view, window frame with broken glass pane and cracks, abandoned building"),
    ("bus_stop_sign", 64, 64, "isometric pixel art, 30-degree top-down angled view, bus stop sign on iron pole with route number plate, taiwanese municipal style"),
    ("convenience_store_sign", 48, 48, "isometric pixel art, 30-degree top-down angled view, convenience store illuminated sign, 7-eleven style, modern plastic backlit sign board"),
    ("fire_hydrant_red", 48, 48, "isometric pixel art, 30-degree top-down angled view, red fire hydrant on street corner, taiwanese municipal, chunky metal body with caps"),
    ("ice_cream_cart", 64, 64, "isometric pixel art, 30-degree top-down angled view, taiwanese ba-bu ice cream push cart with colorful umbrella on top, two wheels, street vendor"),
    ("iron_gate_rusted", 96, 96, "isometric pixel art, 30-degree top-down angled view, old vertical roller iron security gate of a taiwanese shopfront, rusty metal slats, fully closed"),
    ("lantern_paper_red", 48, 48, "isometric pixel art, 30-degree top-down angled view, traditional taiwanese round red paper lantern with gold tassel, hanging decoration"),
    ("market_awning", 96, 96, "isometric pixel art, 30-degree top-down angled view, faded striped canvas awning canopy over market stall, metal support poles and wires"),
    ("motorcycle_parked", 64, 64, "isometric pixel art, 30-degree top-down angled view, parked old taiwanese motorcycle scooter, dark green body, 1980s style, standing upright on kickstand"),
    ("neon_sign_shop", 48, 48, "isometric pixel art, 30-degree top-down angled view, colorful neon tube shop sign, chinese characters glowing, 1980s Taiwan night market style"),
    ("oil_drum_metal", 48, 48, "isometric pixel art, 30-degree top-down angled view, large metal cooking oil drum, industrial cylindrical barrel, dented and worn"),
    ("phone_booth_green", 64, 64, "isometric pixel art, 30-degree top-down angled view, green public phone booth, 1980s Taiwan municipal style, enclosed box with telephone inside"),
    ("power_pole_wooden", 64, 64, "isometric pixel art, 30-degree top-down angled view, old wooden power pole with tangled electric wires and insulators, 1980s Taiwan street"),
    ("qr_code_sign", 32, 32, "isometric pixel art, 30-degree top-down angled view, QR code payment sign on small tabletop stand, modern cashless payment display"),
    ("road_sign_blue", 48, 48, "isometric pixel art, 30-degree top-down angled view, taiwanese blue street sign post with white chinese text, metal pole and sign board"),
    ("roof_antenna_tv", 48, 48, "isometric pixel art, 30-degree top-down angled view, old TV antenna on rooftop, metal rods pointing upward, 1980s Taiwan style"),
    ("satellite_dish", 48, 48, "isometric pixel art, 30-degree top-down angled view, small satellite TV dish mounted on pole, circular dish shape, modern technology"),
    ("scaffolding_bamboo", 64, 64, "isometric pixel art, 30-degree top-down angled view, bamboo scaffolding poles lashed together against building wall, 1980s Taiwan construction"),
    ("shop_sign_pharmacy", 48, 48, "isometric pixel art, 30-degree top-down angled view, traditional wooden shop sign board hanging from chains, gold chinese characters on dark wood"),
    ("shutter_closed_rusty", 96, 96, "isometric pixel art, 30-degree top-down angled view, rusty closed metal rolling shutter door, abandoned shop front, horizontal corrugated metal slats"),
    ("stray_cat_sleeping", 32, 32, "isometric pixel art, 30-degree top-down angled view, sleeping stray tabby cat curled up on cardboard box, market alley, fluffy fur"),
    ("stray_dog_sitting", 48, 48, "isometric pixel art, 30-degree top-down angled view, stray dog sitting on street watching passersby, friendly face, market street"),
    ("street_lamp_old", 64, 64, "isometric pixel art, 30-degree top-down angled view, old taiwanese street lamp post, iron pole with glass lantern head, 1980s style, warm light glow"),
    ("temple_lantern_stone", 48, 48, "isometric pixel art, 30-degree top-down angled view, stone carved palace lantern on pillar, temple roadside decoration, ornate carved stone"),
    ("ubike_station", 64, 64, "isometric pixel art, 30-degree top-down angled view, YouBike shared bicycle docking station, modern taipei infrastructure, row of parked bikes on rack"),
    ("vendor_cart_wood", 64, 64, "isometric pixel art, 30-degree top-down angled view, wooden two-wheel vendor push cart with fruits displayed on top, traditional market vendor"),
    ("window_shutter_wood", 48, 48, "isometric pixel art, 30-degree top-down angled view, old wooden window shutters half open, peeling green paint, 1980s Taiwan"),
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
