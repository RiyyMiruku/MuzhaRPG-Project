"""Batch remake all zone_law_office iso_prop assets as iso_building."""
import subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ASSETS = [
    # (name, width, height, description)
    ("abacus_wood", 32, 32, "isometric pixel art, 30-degree top-down angled view, wooden abacus, flat rectangular frame with horizontal rods and beads, 1980s Taiwan style, warm brown wood"),
    ("cobweb_corner", 32, 32, "isometric pixel art, 30-degree top-down angled view, dusty cobweb in corner, delicate spider web strands, translucent threads with dust"),
    ("coffee_mug", 32, 32, "isometric pixel art, 30-degree top-down angled view, white coffee mug with steam, simple office mug on desk"),
    ("filing_tray_stack", 32, 32, "isometric pixel art, 30-degree top-down angled view, stacked paper filing trays, in/out office desk organizer"),
    ("fountain_pen_old", 32, 32, "isometric pixel art, 30-degree top-down angled view, old fountain pen lying flat, long thin barrel with gold nib, dark navy blue body with gold trim"),
    ("letter_envelope", 32, 32, "isometric pixel art, 30-degree top-down angled view, formal letter envelope with law firm stamp, white envelope slightly opened"),
    ("light_bulb_hanging", 32, 32, "isometric pixel art, 30-degree top-down angled view, hanging light bulb, single incandescent bulb with thin cord, warm yellow glow, 1980s Taiwan style"),
    ("paper_weight_jade", 32, 32, "isometric pixel art, 30-degree top-down angled view, small jade paperweight, flat oval smooth stone, pale green translucent jade"),
    ("rubber_stamp_set", 32, 32, "isometric pixel art, 30-degree top-down angled view, set of rubber stamps and red ink pad, official document tools on desk"),
    ("wooden_stool_old", 32, 32, "isometric pixel art, 30-degree top-down angled view, old wooden stool, round seat with four thin legs, warm brown aged wood"),
    ("certificate_frame", 48, 48, "isometric pixel art, 30-degree top-down angled view, framed certificate on wall, thin rectangular picture frame with official document inside, dark wood frame with glass"),
    ("desk_lamp_brass", 48, 48, "isometric pixel art, 30-degree top-down angled view, brass desk lamp with green glass shade, classic lawyer office style, 1980s Taiwan"),
    ("globe_desk", 48, 48, "isometric pixel art, 30-degree top-down angled view, small desk globe on wooden stand, office or study decoration"),
    ("potted_plant_office", 48, 48, "isometric pixel art, 30-degree top-down angled view, small office plant in white ceramic pot, ficus or peace lily, indoor plant"),
    ("radio_old_brown", 48, 48, "isometric pixel art, 30-degree top-down angled view, 1980s Taiwan old brown radio receiver, rectangular with round speaker grille, tuning dial and antenna, warm brown bakelite"),
    ("rotary_phone", 48, 48, "isometric pixel art, 30-degree top-down angled view, beige rotary dial telephone, 1980s office essential, visible dial and handset"),
    ("tea_set_ceramic", 48, 48, "isometric pixel art, 30-degree top-down angled view, 1980s Taiwan ceramic tea set, small teapot with two teacups on tray, white and blue porcelain"),
    ("wall_clock_round", 48, 48, "isometric pixel art, 30-degree top-down angled view, round wall clock, circular white clock face with black hands, thin wooden circular frame, mounted on wall"),
    ("barber_chair_red", 48, 48, "isometric pixel art, 30-degree top-down angled view, red vinyl barber chair, chrome armrests and footrest, neighborhood barbershop style"),
    ("barber_pole_spiral", 48, 48, "isometric pixel art, 30-degree top-down angled view, red white blue spiral barber pole, wall mounted, classic barbershop sign"),
    ("fan_standing", 48, 48, "isometric pixel art, 30-degree top-down angled view, 1980s Taiwan standing electric fan, circular fan blade with protective wire cage, tall thin metal pole, round base"),
    ("folding_table", 48, 48, "isometric pixel art, 30-degree top-down angled view, simple folding table, lightweight metal frame, flat rectangular top"),
    ("laptop_modern", 48, 48, "isometric pixel art, 30-degree top-down angled view, modern laptop computer, screen open and glowing, slim design"),
    ("moving_box_taped", 48, 48, "isometric pixel art, 30-degree top-down angled view, sealed cardboard moving box with packing tape, brown corrugated cardboard"),
    ("suitcase_travel", 48, 48, "isometric pixel art, 30-degree top-down angled view, modern rolling suitcase, dark grey, wheels and handle visible"),
    ("typewriter_old", 48, 48, "isometric pixel art, 30-degree top-down angled view, old manual typewriter, metal body with round keys, paper roll visible, on desk"),
    ("wooden_box", 48, 48, "isometric pixel art, 30-degree top-down angled view, small wooden hanging sign, flat rectangular wooden plaque suspended by two ropes, chinese text, warm brown aged wood"),
    ("woodsign", 48, 48, "isometric pixel art, 30-degree top-down angled view, small wooden hanging sign with rope, flat rectangular plaque, chinese characters painted on front, 1980s Taiwan"),
    ("desk_wooden_old", 64, 64, "isometric pixel art, 30-degree top-down angled view, 1980s Taiwan wooden office desk, flat rectangular desktop with four legs, warm brown wood grain, papers on top"),
    ("fabric_roll_shelf", 64, 64, "isometric pixel art, 30-degree top-down angled view, shelf with rolled fabric bolts in various colors, cloth shop display shelving"),
    ("filing_cabinet_metal", 64, 64, "isometric pixel art, 30-degree top-down angled view, grey metal filing cabinet with label slots and drawer handles, office furniture"),
    ("mod_clock", 64, 64, "isometric pixel art, 30-degree top-down angled view, small standing floor clock, 1980s Taiwan style, wooden pendulum clock body, round white clock face with black hands, short decorative legs"),
    ("sewing_machine_old", 64, 64, "isometric pixel art, 30-degree top-down angled view, old black singer sewing machine on table, foot pedal, tailor shop, vintage industrial design"),
    ("bookshelf_law", 96, 96, "isometric pixel art, 30-degree top-down angled view, tall wooden bookshelf filled with law books and binders, office furniture, full shelves visible from angle"),
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
