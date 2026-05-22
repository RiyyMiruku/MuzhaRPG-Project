"""批次把缺少的物件加入各 zone 的 YSortRoot。

用法：uv run python scripts/populate_zones.py
"""
from __future__ import annotations
import sys, io, re, random
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
random.seed(42)

REPO = Path(__file__).resolve().parent.parent

ZONES: dict[str, dict] = {
    "zone_market": {
        "file": "game/src/maps/zones/zone_market.tscn",
        "add_1983": [
            ("1983_meat_hook", "meat_hook_rack", (-200, -100, -80, -40)),
            ("1983_fish_stall", "fish_stall_icebox", (-300, -200, -60, -20)),
            ("1983_tofu_stall", "tofu_stall_bucket", (-150, -50, -50, 0)),
            ("1983_scale", "market_scale_hanging", (-120, -80, -30, 10)),
            ("1983_motorcycle", "motorcycle_parked", (200, 300, 40, 80)),
            ("1983_pole", "power_pole_wooden", (-350, -300, -20, 20)),
            ("1983_pole2", "power_pole_wooden", (280, 330, -60, -20)),
            ("1983_banner", "banner_cloth_sale", (-80, 0, -140, -100)),
            ("1983_trash", "trash_bin_green", (-250, -200, 20, 60)),
            ("1983_faucet", "water_faucet_wall", (-160, -120, -20, 20)),
            ("1983_boxes", "cardboard_boxes_stack", (-280, -240, 40, 80)),
            ("1983_bicycle", "bicycle_parked", (150, 200, 60, 100)),
            ("1983_newspaper", "newspaper_stand", (-330, -280, -40, 0)),
            ("1983_phone", "phone_booth_green", (250, 300, -40, 0)),
            ("1983_wonton", "wonton_soup_pot", (-100, -50, -60, -20)),
            ("1983_tea_egg", "tea_egg_pot", (-60, -20, -40, 0)),
            ("1983_sugarcane", "sugarcane_juice_press", (100, 150, 60, 100)),
            ("1983_mailbox", "mailbox_green", (-380, -340, 0, 40)),
            ("1983_cat", "stray_cat_sleeping", (-200, -150, 40, 80)),
            ("1983_dog", "stray_dog_sitting", (50, 100, 80, 120)),
            ("1983_neon", "neon_sign_shop", (100, 160, -160, -120)),
            ("1983_hydrant", "fire_hydrant_red", (-300, -260, 40, 60)),
            ("1983_birdcage", "birdcage_bamboo", (-40, 0, -80, -40)),
            ("1983_steamer", "bamboo_steamer", (-80, -40, -40, 0)),
        ],
        "add_modern": [
            ("mod_shutter", "shutter_closed_rusty", (-200, -100, -100, -60)),
            ("mod_shutter2", "shutter_closed_rusty", (100, 200, -80, -40)),
            ("mod_faded_sign", "sign_faded_old", (-150, -80, -120, -80)),
            ("mod_torn_boxes", "cardboard_boxes_torn", (-250, -200, 20, 60)),
            ("mod_rusted_bike", "bicycle_rusted", (160, 220, 40, 80)),
            ("mod_notice", "notice_board_urban", (-320, -280, -20, 20)),
            ("mod_scooter", "scooter_modern", (200, 260, 60, 100)),
            ("mod_vending", "vending_machine", (-280, -240, -40, 0)),
            ("mod_cctv", "cctv_camera_pole", (260, 300, -80, -40)),
        ],
    },
    "zone_pharmacy": {
        "file": "game/src/maps/zones/zone_pharmacy.tscn",
        "add_1983": [
            ("1983_herb_jar", "herb_jar_ceramic", (-40, -20, -60, -40)),
            ("1983_herb_jar2", "herb_jar_ceramic", (-20, 0, -60, -40)),
            ("1983_herb_jar3", "herb_jar_ceramic", (0, 20, -60, -40)),
            ("1983_herb_scale", "herb_scale_brass", (20, 40, -20, 0)),
            ("1983_prescription", "prescription_paper_stack", (-10, 10, -10, 10)),
            ("1983_mortar", "mortar_pestle_stone", (30, 50, -20, 0)),
            ("1983_drying_tray", "herb_drying_tray", (-60, -40, 20, 40)),
            ("1983_altar", "altar_table_wood", (50, 70, -40, -20)),
            ("1983_tea_set", "tea_set_ceramic", (-20, 0, 0, 20)),
            ("1983_radio", "radio_old_brown", (-50, -30, -30, -10)),
            ("1983_clock", "wall_clock_round", (0, 20, -80, -60)),
            ("1983_deity", "deity_statue_small", (55, 65, -35, -25)),
            ("1983_lucky_cat", "lucky_cat_ceramic", (-5, 5, 5, 15)),
            ("1983_slippers", "slippers_pair", (0, 20, 60, 80)),
            ("1983_fan", "fan_standing", (-60, -40, 0, 20)),
            ("1983_tv", "old_tv_box", (40, 60, 20, 40)),
            ("1983_thermos", "thermos_flask", (10, 30, 0, 10)),
            ("1983_ashtray", "cigarette_ashtray", (-5, 5, -5, 5)),
            ("1983_key_ring", "key_ring_wall", (60, 70, -60, -50)),
            ("1983_umbrella", "umbrella_stand", (-10, 10, 50, 70)),
        ],
        "add_modern": [
            ("mod_cobweb", "cobweb_corner", (-70, -50, -70, -50)),
            ("mod_cobweb2", "cobweb_corner", (50, 70, -70, -50)),
            ("mod_dusty_cloth", "dusty_cloth_cover", (-30, -10, -20, 0)),
            ("mod_dusty_cloth2", "dusty_cloth_cover", (10, 30, 20, 40)),
            ("mod_broken_jar", "herb_jar_broken", (-40, -20, 10, 30)),
            ("mod_broken_jar2", "herb_jar_broken", (20, 40, 0, 20)),
            ("mod_bulb", "light_bulb_hanging", (0, 10, -40, -30)),
            ("mod_footprint", "footprint_dust", (30, 50, -10, 10)),
        ],
    },
    "zone_pharmacy_backyard": {
        "file": "game/src/maps/zones/zone_pharmacy_backyard.tscn",
        "add_1983": [
            ("1983_well", "well_stone_old", (60, 80, -20, 0)),
            ("1983_clothesline", "clothesline_bamboo", (-80, -40, -40, -20)),
            ("1983_plant", "potted_plant_clay", (-30, -10, 10, 30)),
            ("1983_plant2", "potted_plant_clay", (20, 40, -10, 10)),
            ("1983_plant3", "potted_plant_clay", (-10, 10, -30, -10)),
            ("1983_broom", "broom_dustpan", (40, 60, 20, 40)),
            ("1983_door", "door_wooden_locked", (80, 100, -10, 10)),
            ("1983_desk", "desk_wooden_old", (100, 120, -20, 0)),
            ("1983_bed", "bed_single_old", (110, 130, 10, 30)),
            ("1983_clipping", "newspaper_clipping_wall", (90, 100, -30, -20)),
            ("1983_clipping2", "newspaper_clipping_wall", (95, 105, -25, -15)),
            ("1983_bench", "stone_bench_garden", (-50, -30, 0, 20)),
            ("1983_herb_garden", "herb_garden_patch", (-20, 20, 20, 40)),
            ("1983_washing", "washing_board_wood", (-60, -40, 20, 40)),
        ],
        "add_modern": [],
    },
    "zone_apartment_muzha": {
        "file": "game/src/maps/zones/zone_apartment_muzha.tscn",
        "add_1983": [],
        "add_modern": [
            ("mod_apartment", "old_apartment_muzha", (0, 20, -80, -60)),
            ("mod_suitcase", "suitcase_travel", (-30, -10, 10, 30)),
            ("mod_laptop", "laptop_modern", (0, 20, -10, 10)),
            ("mod_coffee", "coffee_mug", (15, 25, -5, 5)),
            ("mod_box", "moving_box_taped", (-50, -30, 20, 40)),
            ("mod_box2", "moving_box_taped", (-40, -20, 30, 50)),
            ("mod_table", "folding_table", (-10, 10, 0, 20)),
            ("mod_letter", "letter_envelope", (5, 15, -5, 5)),
            ("mod_backpack", "backpack_travel", (20, 40, 20, 40)),
            ("mod_sticky", "sticky_notes_wall", (-20, 0, -40, -20)),
            ("mod_mattress", "mattress_floor", (30, 50, 10, 30)),
            ("mod_water", "water_bottle_plastic", (25, 35, 25, 35)),
            ("mod_photo", "photo_frame_family", (-5, 5, -15, -5)),
        ],
    },
    "zone_law_office": {
        "file": "game/src/maps/zones/zone_law_office.tscn",
        "add_1983": [],
        "add_modern": [
            ("mod_bookshelf", "bookshelf_law", (-60, -40, -50, -30)),
            ("mod_bookshelf2", "bookshelf_law", (40, 60, -50, -30)),
            ("mod_cabinet", "filing_cabinet_metal", (-50, -30, -20, 0)),
            ("mod_lamp", "desk_lamp_brass", (-5, 5, -10, 0)),
            ("mod_clock", "wall_clock_round", (0, 10, -60, -50)),
            ("mod_plant", "potted_plant_office", (30, 50, -10, 10)),
            ("mod_cert", "certificate_frame", (-40, -20, -60, -50)),
            ("mod_cert2", "certificate_frame", (20, 40, -60, -50)),
            ("mod_typewriter", "typewriter_old", (10, 30, -10, 0)),
            ("mod_phone", "rotary_phone", (-15, -5, 0, 10)),
            ("mod_stamp", "rubber_stamp_set", (-5, 5, 5, 15)),
            ("mod_tray", "filing_tray_stack", (5, 15, -5, 5)),
        ],
    },
}


def process_zone(zone_name: str, config: dict) -> int:
    filepath = REPO / config["file"]
    content = filepath.read_text(encoding="utf-8")

    all_adds: list[tuple] = []
    for item in config.get("add_1983", []):
        all_adds.append((*item, "era_1983", True))
    for item in config.get("add_modern", []):
        all_adds.append((*item, "era_modern", False))

    if not all_adds:
        return 0

    # Collect unique tscn files needed
    needed_tscns: set[str] = set()
    for _node_name, tscn_name, _pos, _era, _hid in all_adds:
        needed_tscns.add(tscn_name)

    # Check existing ext_resources
    existing_exts: dict[str, str] = {}
    for m in re.finditer(
        r'\[ext_resource[^\]]*path="res://src/maps/props/([^"]+)\.tscn"[^\]]*id="([^"]+)"\]',
        content,
    ):
        existing_exts[m.group(1)] = m.group(2)

    # Add missing ext_resources
    new_ext_lines: list[str] = []
    ext_counter = 100
    for tscn_name in sorted(needed_tscns):
        if tscn_name not in existing_exts:
            ext_id = f"{ext_counter}_{tscn_name[:10]}"
            new_ext_lines.append(
                f'[ext_resource type="PackedScene" path="res://src/maps/props/{tscn_name}.tscn" id="{ext_id}"]'
            )
            existing_exts[tscn_name] = ext_id
            ext_counter += 1

    if new_ext_lines:
        last_ext_pos = content.rfind("[ext_resource")
        last_ext_end = content.index("]", last_ext_pos) + 1
        insert_pos = content.index("\n", last_ext_end)
        content = (
            content[:insert_pos] + "\n" + "\n".join(new_ext_lines) + content[insert_pos:]
        )

    # Build node entries
    node_lines: list[str] = []
    uid_base = random.randint(100000000, 999999999)
    for i, (node_name, tscn_name, pos_range, era, hidden) in enumerate(all_adds):
        x = random.randint(pos_range[0], pos_range[1])
        y = random.randint(pos_range[2], pos_range[3])
        ext_id = existing_exts[tscn_name]
        uid = uid_base + i

        vis = "\nvisible = false" if hidden else ""
        node_lines.append(
            f'[node name="{node_name}" parent="YSortRoot" unique_id={uid} '
            f'groups=["{era}"] instance=ExtResource("{ext_id}")]'
            f"{vis}"
            f"\nposition = Vector2({x}, {y})\n"
        )

    # Insert before [node name="Camera2D"
    camera_match = re.search(r'\[node name="Camera2D"', content)
    if camera_match:
        insert_pos = camera_match.start()
        content = content[:insert_pos] + "\n".join(node_lines) + "\n" + content[insert_pos:]

    filepath.write_text(content, encoding="utf-8")
    return len(all_adds)


total = 0
for zn, cfg in ZONES.items():
    n = process_zone(zn, cfg)
    if n:
        print(f"  {zn}: +{n} objects")
        total += n

print(f"\nDone! Added {total} objects across all zones.")
