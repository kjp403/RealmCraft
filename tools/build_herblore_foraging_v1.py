#!/usr/bin/env python3
"""Generate Farming herb ladder + Herblore station content (v1).

Run: python tools/build_herblore_foraging_v1.py
Then: godot --headless --path . -s tools/update_items_index.gd
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HERBS_DIR = ROOT / "source/common/gameplay/items/materials/herbs"
NODES_DIR = ROOT / "source/common/gameplay/maps/components/mineable_nodes"
TOOLS_DIR = ROOT / "source/common/gameplay/items/weapons/tools"
JOBS_DIR = ROOT / "source/common/gameplay/jobs"
CRAFT_DIR = ROOT / "source/common/gameplay/crafting/resources"

VEG = "res://assets/sprites/environment/props/vegetation.png"
PROPS = "res://assets/sprites/environment/green_woods/props.png"
MAT_SCRIPT = "res://source/common/gameplay/items/material_item.gd"
NODE_SCRIPT = "res://source/common/gameplay/maps/components/mineable_node_resource.gd"
TOOL_SCRIPT = "res://source/common/gameplay/items/weapons/tool_item.gd"
STAT_SCRIPT = "res://source/common/gameplay/combat/attributes/stat_modifier.gd"
SLOT = "res://source/common/gameplay/items/item_slot/slots/weapon.tres"
SICKLE_SCENE = "res://source/common/gameplay/items/weapons/tools/sickle.tscn"
JP_SCRIPT = "res://source/common/gameplay/jobs/job_perks.gd"
ITEM_SCRIPT = "res://source/common/gameplay/items/item.gd"
RECIPE_SCRIPT = "res://source/common/gameplay/crafting/crafting_recipe.gd"
STATION_SCRIPT = "res://source/common/gameplay/crafting/crafting_station_resource.gd"
INGRED_SCRIPT = "res://source/common/gameplay/crafting/craft_ingredient.gd"

# Herb ladder: slug → gather level, xp, vendor, icon 16x16, node tex 32x32, desc
HERBS = [
    {
        "slug": "healing_herb",
        "name": "Healing Herb",
        "level": 1,
        "xp": 10,
        "vendor": 1,
        "icon": (64, 192, 16, 16),
        "node": None,  # keep existing green_woods atlas
        "yield": 2,
        "desc": "A common wildflower with mild healing properties. Found in clearings and along roadsides.",
        "existing": True,
    },
    {
        "slug": "frostpetal",
        "name": "Frostpetal",
        "level": 5,
        "xp": 20,
        "vendor": 2,
        "icon": (96, 400, 16, 16),
        "node": (80, 384, 32, 32),
        "yield": 2,
        "desc": "A cold blue bloom. Brews into a minor mana draught.",
    },
    {
        "slug": "sunwort",
        "name": "Sunwort",
        "level": 10,
        "xp": 35,
        "vendor": 3,
        "icon": (96, 368, 16, 16),
        "node": (64, 352, 32, 32),
        "yield": 2,
        "desc": "Warm orange florets used in standard health potions.",
    },
    {
        "slug": "moonbloom",
        "name": "Moonbloom",
        "level": 20,
        "xp": 50,
        "vendor": 4,
        "icon": (96, 384, 16, 16),
        "node": (80, 368, 32, 32),
        "yield": 2,
        "desc": "Pale night flowers. Distills cleanly into mana potions.",
    },
    {
        "slug": "bloodcap",
        "name": "Bloodcap",
        "level": 30,
        "xp": 70,
        "vendor": 6,
        "icon": (32, 336, 16, 16),
        "node": (16, 320, 32, 32),
        "yield": 1,
        "desc": "A spotted red mushroom. Potent base for greater healing brews.",
    },
    {
        "slug": "starblossom",
        "name": "Starblossom",
        "level": 40,
        "xp": 90,
        "vendor": 7,
        "icon": (96, 416, 16, 16),
        "node": (80, 400, 32, 32),
        "yield": 1,
        "desc": "Golden petals that hold a charge of arcane sap.",
    },
    {
        "slug": "grimshade",
        "name": "Grimshade",
        "level": 50,
        "xp": 110,
        "vendor": 9,
        "icon": (208, 176, 16, 16),
        "node": (208, 160, 32, 32),
        "yield": 1,
        "desc": "Purple shade-herb. Focus tonics start here.",
    },
]

# potion slug → (herb_slug, herb_amt, herblore_level, xp, potion_path)
BREWS = [
    ("minor_health_potion", "healing_herb", 2, 1, 15, "res://source/common/gameplay/items/consumables/minor_health_potion.tres"),
    ("minor_mana_potion", "frostpetal", 2, 5, 25, "res://source/common/gameplay/items/consumables/minor_mana_potion.tres"),
    ("health_potion", "sunwort", 2, 10, 40, "res://source/common/gameplay/items/consumables/health_potion.tres"),
    ("mana_potion", "moonbloom", 2, 20, 55, "res://source/common/gameplay/items/consumables/mana_potion.tres"),
    ("greater_health_potion", "bloodcap", 3, 30, 80, "res://source/common/gameplay/items/consumables/greater_health_potion.tres"),
    ("greater_mana_potion", "starblossom", 3, 40, 100, "res://source/common/gameplay/items/consumables/greater_mana_potion.tres"),
    ("focus_tonic", "grimshade", 3, 50, 120, "res://source/common/gameplay/items/consumables/focus_tonic.tres"),
]

SICKLES = [
    # slug, metal folder, level, dmg, cd, bonus, vendor, desc name
    ("sickle_iron", "iron", 10, 2, 0.40, 0.05, 28, "Iron Sickle"),
    ("sickle_steel", "steel", 20, 2, 0.38, 0.07, 55, "Steel Sickle"),
    ("sickle_mithril", "mithril", 30, 3, 0.36, 0.10, 110, "Mithril Sickle"),
]


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.replace("\n", "\r\n"), encoding="utf-8")
    print("wrote", path.relative_to(ROOT))


def herb_item_tres(h: dict) -> str:
    x, y, w, hh = h["icon"]
    return f"""[gd_resource type="Resource" script_class="MaterialItem" format=3]

[ext_resource type="Texture2D" path="{VEG}" id="1_tex"]
[ext_resource type="Script" path="{MAT_SCRIPT}" id="2_script"]

[sub_resource type="AtlasTexture" id="Atlas_icon"]
atlas = ExtResource("1_tex")
region = Rect2({x}, {y}, {w}, {hh})

[resource]
script = ExtResource("2_script")
item_name = &"{h['name']}"
item_icon = SubResource("Atlas_icon")
description = "{h['desc']}"
vendor_value = {h['vendor']}
stack_limit = 10
metadata/slug = &"{h['slug']}"
"""


def node_tres(h: dict, herb_path: str) -> str:
    if h.get("node") is None:
        # update existing healing_herb node only via separate path
        return ""
    x, y, w, hh = h["node"]
    return f"""[gd_resource type="Resource" script_class="MineableNodeResource" format=3]

[ext_resource type="Script" path="{NODE_SCRIPT}" id="1_script"]
[ext_resource type="Resource" path="{herb_path}" id="2_ore"]
[ext_resource type="Texture2D" path="{VEG}" id="3_tex"]

[sub_resource type="AtlasTexture" id="Atlas_node"]
atlas = ExtResource("3_tex")
region = Rect2({x}, {y}, {w}, {hh})

[resource]
script = ExtResource("1_script")
display_name = "{h['name']}"
ore = ExtResource("2_ore")
yield_amount = {h['yield']}
job_xp = Dictionary[StringName, int]({{
&"harvesting": {h['xp']}
}})
required_level = {h['level']}
required_tool = &"sickle"
extraction_hp = 2
charge_regen_seconds = 10.0
depleted_recharge_seconds = 50.0
player_cooldown_seconds = 4.0
texture = SubResource("Atlas_node")
"""


def sickle_tres(s: tuple) -> str:
    slug, metal, level, dmg, cd, bonus, vendor, name = s
    return f"""[gd_resource type="Resource" script_class="ToolItem" format=3]

[ext_resource type="Texture2D" path="res://assets/sprites/items/weapons/{metal}/{metal}.png" id="1_tex"]
[ext_resource type="Script" path="{STAT_SCRIPT}" id="1_stat"]
[ext_resource type="Script" path="{TOOL_SCRIPT}" id="2_tool"]
[ext_resource type="Resource" path="{SLOT}" id="3_slot"]
[ext_resource type="PackedScene" path="{SICKLE_SCENE}" id="4_scene"]

[sub_resource type="AtlasTexture" id="Atlas_icon"]
atlas = ExtResource("1_tex")
region = Rect2(32, 48, 16, 32)

[resource]
script = ExtResource("2_tool")
tool_type = &"sickle"
extraction_damage = {dmg}
swing_cooldown = {cd}
required_skill = &"harvesting"
required_skill_level = {level}
bonus_yield_chance = {bonus}
right_hand_scene = ExtResource("4_scene")
slot = ExtResource("3_slot")
item_name = &"{name}"
item_icon = SubResource("Atlas_icon")
description = "A {metal} harvesting sickle. Requires Farming {level}."
can_trade = true
vendor_value = {vendor}
stack_limit = 1
tags = PackedStringArray()
metadata/slug = &"{slug}"
"""


def main() -> None:
    herb_paths: dict[str, str] = {}
    for h in HERBS:
        rel = f"res://source/common/gameplay/items/materials/herbs/{h['slug']}.tres"
        herb_paths[h["slug"]] = rel
        if h.get("existing"):
            # Refresh existing healing herb description/stack only lightly — keep uid/id.
            continue
        write(HERBS_DIR / f"{h['slug']}.tres", herb_item_tres(h))

    # Update healing_herb node with required_level
    healing_node = f"""[gd_resource type="Resource" script_class="MineableNodeResource" format=3 uid="uid://g8rxlnr0pfyk"]

[ext_resource type="Script" uid="uid://w4s2ld2v5xdq" path="{NODE_SCRIPT}" id="1_script"]
[ext_resource type="Resource" uid="uid://d2dopgtbgmdii" path="res://source/common/gameplay/items/materials/herbs/healing_herb.tres" id="2_ore"]
[ext_resource type="Texture2D" uid="uid://cg5jhosmuvhud" path="{PROPS}" id="3_twypx"]

[sub_resource type="AtlasTexture" id="AtlasTexture_nlin3"]
atlas = ExtResource("3_twypx")
region = Rect2(0, 32, 32, 32)

[resource]
script = ExtResource("1_script")
display_name = "Healing Herb"
ore = ExtResource("2_ore")
yield_amount = 2
job_xp = Dictionary[StringName, int]({{
&"harvesting": 10
}})
required_level = 1
required_tool = &"sickle"
extraction_hp = 2
charge_regen_seconds = 10.0
depleted_recharge_seconds = 50.0
player_cooldown_seconds = 4.0
texture = SubResource("AtlasTexture_nlin3")
"""
    write(NODES_DIR / "healing_herb.tres", healing_node)

    flax = f"""[gd_resource type="Resource" script_class="MineableNodeResource" format=3 uid="uid://dsvbif0isp6d5"]

[ext_resource type="Script" uid="uid://w4s2ld2v5xdq" path="{NODE_SCRIPT}" id="1_script"]
[ext_resource type="Resource" uid="uid://vhgsmnbqslo6" path="res://source/common/gameplay/items/materials/cloth/cloth_forest.tres" id="2_cloth"]
[ext_resource type="Texture2D" uid="uid://cg5jhosmuvhud" path="{PROPS}" id="3_props"]

[sub_resource type="AtlasTexture" id="AtlasTexture_flax"]
atlas = ExtResource("3_props")
region = Rect2(0, 32, 32, 32)

[resource]
script = ExtResource("1_script")
display_name = "Flax"
ore = ExtResource("2_cloth")
job_xp = Dictionary[StringName, int]({{
&"harvesting": 8
}})
required_level = 1
required_tool = &"sickle"
extraction_hp = 2
charge_regen_seconds = 10.0
player_cooldown_seconds = 4.0
texture = SubResource("AtlasTexture_flax")
"""
    write(NODES_DIR / "flax.tres", flax)

    for h in HERBS:
        if h.get("existing"):
            continue
        body = node_tres(h, herb_paths[h["slug"]])
        write(NODES_DIR / f"{h['slug']}.tres", body)

    for s in SICKLES:
        write(TOOLS_DIR / f"{s[0]}.tres", sickle_tres(s))

    # Update base sickle with skill gate
    base_sickle = f"""[gd_resource type="Resource" script_class="ToolItem" format=3 uid="uid://c4r6h4wum0u0b"]

[ext_resource type="Script" uid="uid://cvggwjkht4km4" path="{STAT_SCRIPT}" id="1_5xcnt"]
[ext_resource type="Texture2D" uid="uid://bogvbnwhxp5ej" path="res://assets/sprites/items/weapons/wood/wood.png" id="1_tex"]
[ext_resource type="Script" uid="uid://b5hsnu4140fky" path="{TOOL_SCRIPT}" id="2_toolitem"]
[ext_resource type="Resource" uid="uid://qav4p12rsbn3" path="{SLOT}" id="3_slot"]
[ext_resource type="PackedScene" uid="uid://6iow1vrv0iq7" path="{SICKLE_SCENE}" id="4_scene"]

[sub_resource type="AtlasTexture" id="AtlasTexture_sickle"]
atlas = ExtResource("1_tex")
region = Rect2(32, 48, 16, 32)

[resource]
script = ExtResource("2_toolitem")
tool_type = &"sickle"
extraction_damage = 1
swing_cooldown = 0.42
required_skill = &"harvesting"
required_skill_level = 1
bonus_yield_chance = 0.03
right_hand_scene = ExtResource("4_scene")
slot = ExtResource("3_slot")
item_name = &"Sickle"
item_icon = SubResource("AtlasTexture_sickle")
description = "A curved harvesting sickle. Equip it to cut herbs and plants from the wild."
vendor_value = 3
metadata/slug = &"sickle"
metadata/id = 66
"""
    write(TOOLS_DIR / "sickle.tres", base_sickle)

    # harvesting.tres sources
    cloth = "res://source/common/gameplay/items/materials/cloth/cloth_forest.tres"
    src_ext = [
        f'[ext_resource type="Script" path="{ITEM_SCRIPT}" id="1_item"]',
        f'[ext_resource type="Script" path="{JP_SCRIPT}" id="1_jp"]',
        '[ext_resource type="Texture2D" uid="uid://csk236a261024" path="res://assets/sprites/ui/menu_icons_shadow/32px/realmcraft_menu_icons/Farming.png" id="icon_tex"]',
    ]
    source_items = []
    source_levels = []
    for i, h in enumerate(HERBS):
        eid = f"h{i}"
        src_ext.append(f'[ext_resource type="Resource" path="{herb_paths[h["slug"]]}" id="{eid}"]')
        source_items.append(f'ExtResource("{eid}")')
        source_levels.append(str(h["level"]))
    src_ext.append(f'[ext_resource type="Resource" path="{cloth}" id="flax"]')
    source_items.append('ExtResource("flax")')
    source_levels.append("1")

    harvesting = "\n".join(src_ext) + f"""

[resource]
script = ExtResource("1_jp")
icon = ExtResource("icon_tex")
job_slug = &"harvesting"
display_name = "Farming"
category = &"gathering"
sort_order = 1
cooldown_reduction_per_level = 0.02
bonus_yield_per_level = 0.01
perks = Array[Dictionary]([{{
"effect": "cooldown",
"id": "quick_hands",
"max_rank": 3,
"name": "Quick Hands",
"per_rank": 0.05
}}, {{
"effect": "bonus_yield",
"id": "lucky_find",
"max_rank": 3,
"name": "Lucky Find",
"per_rank": 0.05
}}, {{
"effect": "xp",
"id": "patient",
"max_rank": 3,
"name": "Patient",
"per_rank": 0.1
}}])
source_items = Array[ExtResource("1_item")]([{", ".join(source_items)}])
source_levels = Array[int]([{", ".join(source_levels)}])
describe_lines = Array[String](["Gather speed +{{cooldown}}%", "Bonus herb +{{bonus_yield}}%", "Farming XP +{{xp}}%"])
"""
    write(JOBS_DIR / "harvesting.tres", "[gd_resource type=\"Resource\" script_class=\"JobPerks\" format=3 uid=\"uid://dveu5j2ifx3q8\"]\n\n" + harvesting)

    # herblore.tres
    hb_ext = [
        f'[ext_resource type="Script" path="{JP_SCRIPT}" id="1_jp"]',
        '[ext_resource type="Texture2D" uid="uid://cherbloreicon01" path="res://assets/sprites/ui/menu_icons_shadow/32px/realmcraft_menu_icons/Herblore.png" id="icon_tex"]',
        f'[ext_resource type="Script" path="{ITEM_SCRIPT}" id="1_item"]',
    ]
    recipe_items = []
    recipe_levels = []
    for i, (potion, _herb, _amt, lvl, _xp, path) in enumerate(BREWS):
        eid = f"p{i}"
        hb_ext.append(f'[ext_resource type="Resource" path="{path}" id="{eid}"]')
        recipe_items.append(f'ExtResource("{eid}")')
        recipe_levels.append(str(lvl))

    herblore = "\n".join(hb_ext) + f"""

[resource]
script = ExtResource("1_jp")
icon = ExtResource("icon_tex")
job_slug = &"herblore"
display_name = "Herblore"
category = &"crafting"
sort_order = 4
perks = Array[Dictionary]([{{
"effect": "xp",
"id": "green_thumb",
"max_rank": 3,
"name": "Green Thumb",
"per_rank": 0.1
}}, {{
"effect": "refund",
"id": "careful_measure",
"max_rank": 3,
"name": "Careful Measure",
"per_rank": 0.05
}}, {{
"effect": "extra_item",
"id": "extra_dose",
"max_rank": 3,
"name": "Extra Dose",
"per_rank": 0.04
}}])
recipe_items = Array[ExtResource("1_item")]([{", ".join(recipe_items)}])
recipe_levels = Array[int]([{", ".join(recipe_levels)}])
describe_lines = Array[String](["Herblore XP +{{xp}}%", "Material refund: {{refund}}%", "Extra dose: {{extra_item}}%"])
"""
    write(JOBS_DIR / "herblore.tres", "[gd_resource type=\"Resource\" script_class=\"JobPerks\" format=3]\n\n" + herblore)

    # alchemy_station.tres
    st_parts = [
        f'[ext_resource type="Script" path="{RECIPE_SCRIPT}" id="1_recipe"]',
        f'[ext_resource type="Script" path="{STATION_SCRIPT}" id="2_station"]',
        f'[ext_resource type="Script" path="{INGRED_SCRIPT}" id="3_ingred"]',
    ]
    herb_ids = {}
    for i, h in enumerate(HERBS):
        eid = f"herb_{h['slug']}"
        herb_ids[h["slug"]] = eid
        st_parts.append(f'[ext_resource type="Resource" path="{herb_paths[h["slug"]]}" id="{eid}"]')
    pot_ids = {}
    for i, (potion, _h, _a, _l, _x, path) in enumerate(BREWS):
        eid = f"pot_{i}"
        pot_ids[potion] = eid
        st_parts.append(f'[ext_resource type="Resource" path="{path}" id="{eid}"]')

    subs = []
    recipe_refs = []
    for i, (potion, herb, amt, lvl, xp, _path) in enumerate(BREWS):
        subs.append(f"""
[sub_resource type="Resource" id="I_{i}"]
script = ExtResource("3_ingred")
item = ExtResource("{herb_ids[herb]}")
amount = {amt}

[sub_resource type="Resource" id="R_{i}"]
script = ExtResource("1_recipe")
output_item = ExtResource("{pot_ids[potion]}")
ingredients = Array[ExtResource("3_ingred")]([SubResource("I_{i}")])
required_level = {lvl}
xp_reward = {xp}
""")
        recipe_refs.append(f'SubResource("R_{i}")')

    station = "\n".join(st_parts) + "\n" + "\n".join(subs) + f"""
[resource]
script = ExtResource("2_station")
station_name = "Alchemy Table"
profession = &"herblore"
craft_fee = 0
recipes = Array[ExtResource("1_recipe")]([{", ".join(recipe_refs)}])
"""
    write(CRAFT_DIR / "alchemy_station.tres", "[gd_resource type=\"Resource\" script_class=\"CraftingStationResource\" format=3]\n\n" + station)

    print("done")


if __name__ == "__main__":
    main()
