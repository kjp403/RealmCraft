#!/usr/bin/env python3
"""Generate Level 40–90 Ascension gear for Arkenelle.

Creates icons, MaterialItem / GearItem / WeaponItem resources, a shop,
dungeon reward table, and a Godot helper that patches crafting stations.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import uuid
from pathlib import Path

from PIL import Image, ImageEnhance, ImageOps

ROOT = Path("/workspace")
SRC = Path("/tmp/new_gear/New Weps Armor Jewelry")
ICON_DIR = ROOT / "assets/sprites/items/icons"
WPN_ICON_DIR = ROOT / "assets/sprites/items/weapons/ascension"
GEAR_METAL = ROOT / "source/common/gameplay/items/gears/metal"
GEAR_LEATHER = ROOT / "source/common/gameplay/items/gears/leather"
GEAR_CLOTH = ROOT / "source/common/gameplay/items/gears/cloth"
GEAR_JEWELRY = ROOT / "source/common/gameplay/items/gears/jewelry"
GEAR_RINGS = ROOT / "source/common/gameplay/items/gears/rings"
GEAR_SKILLING = ROOT / "source/common/gameplay/items/gears/skilling"
MAT_METALS = ROOT / "source/common/gameplay/items/materials/metals"
MAT_GEMS = ROOT / "source/common/gameplay/items/materials/gems"
MAT_CLOTH = ROOT / "source/common/gameplay/items/materials/cloth"
MAT_LEATHER = ROOT / "source/common/gameplay/items/materials/leather"
WPN_SWORD = ROOT / "source/common/gameplay/items/weapons/sword"
WPN_HAMMER = ROOT / "source/common/gameplay/items/weapons/hammer"
WPN_BOW = ROOT / "source/common/gameplay/items/weapons/bow"
WPN_WAND = ROOT / "source/common/gameplay/items/weapons/wand"
WPN_BOOK = ROOT / "source/common/gameplay/items/weapons/book"
SHOP_DIR = ROOT / "source/common/gameplay/shops/resources"
DUNGEON_DIR = ROOT / "source/common/gameplay/dungeon"
CATALOG_OUT = ROOT / "tools/ascension_gear_catalog.json"

UID_MOD = "uid://cvggwjkht4km4"
UID_GEAR = "uid://dnmtdktay2df6"
UID_WEAPON = "uid://5hk0gl5ng64h"
UID_MATERIAL = "uid://nsr1timk430j"
SLOT = {
    "helmet": ("uid://dnbj6tmyghec4", "res://source/common/gameplay/items/item_slot/slots/helmet.tres"),
    "torso": ("uid://wi13k03tseev", "res://source/common/gameplay/items/item_slot/slots/torso.tres"),
    "boot": ("uid://dn7q51odqrqp5", "res://source/common/gameplay/items/item_slot/slots/boot.tres"),
    "weapon": ("uid://qav4p12rsbn3", "res://source/common/gameplay/items/item_slot/slots/weapon.tres"),
    "ring": ("uid://cdrd3x2ugfrev", "res://source/common/gameplay/items/item_slot/slots/ring.tres"),
    "amulet": ("uid://camuletslotx41k", "res://source/common/gameplay/items/item_slot/slots/amulet.tres"),
    "relic": ("uid://dp67jicqi8ovy", "res://source/common/gameplay/items/item_slot/slots/relic.tres"),
}
SCENE = {
    "sword": ("uid://cq4pqfg3tnqxh", "res://source/common/gameplay/items/weapons/sword/sword.tscn"),
    "hammer": ("uid://ivb4cdjfwbtx", "res://source/common/gameplay/items/weapons/hammer/hammer.tscn"),
    "bow": ("uid://e6kqwoh5tlxp", "res://source/common/gameplay/items/weapons/bow/wooden_bow.tscn"),
    "wand": None,  # resolved below
    "book": ("uid://bv06kai8ia12k", "res://source/common/gameplay/items/weapons/book/book.tscn"),
}

# Resolve wand scene uid from existing file
_wand_txt = (WPN_WAND / "fire_wand.item.tres").read_text()
for line in _wand_txt.splitlines():
    if "wand.tscn" in line and line.startswith("[ext_resource"):
        # [ext_resource type="PackedScene" uid="uid://..." path="...wand.tscn"
        parts = line.split("uid=")
        if len(parts) > 1:
            SCENE["wand"] = (parts[1].split()[0].strip('"'), "res://source/common/gameplay/items/weapons/wand/wand.tscn")
        break
if SCENE["wand"] is None:
    SCENE["wand"] = ("uid://bqwandscene001", "res://source/common/gameplay/items/weapons/wand/wand.tscn")


def new_uid() -> str:
    return "uid://" + uuid.uuid4().hex[:13]


def import_stub(rel_path: str, uid: str) -> str:
    # Godot will rewrite on import; this is enough for ResourceLoader in editor/headless after import.
    src = f"res://{rel_path}"
    digest = hashlib.md5(rel_path.encode()).hexdigest()
    ctex = f"res://.godot/imported/{Path(rel_path).name}-{digest}.ctex"
    return f"""[remap]

importer="texture"
type="CompressedTexture2D"
uid="{uid}"
path="{ctex}"
metadata={{
"vram_texture": false
}}

[deps]

source_file="{src}"
dest_files=["{ctex}"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def write_png(src: Path | Image.Image, dest: Path, uid: str | None = None) -> tuple[str, str]:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(src, Image.Image):
        src.save(dest)
    else:
        shutil.copy2(src, dest)
    uid = uid or new_uid()
    rel = str(dest.relative_to(ROOT)).replace("\\", "/")
    (dest.with_suffix(dest.suffix + ".import")).write_text(import_stub(rel, uid))
    return f"res://{rel}", uid


def recolor(im: Image.Image, hue_shift: float, sat: float = 1.15, bright: float = 1.05) -> Image.Image:
    """Approximate hue shift via RGB channel remix + enhance."""
    rgba = im.convert("RGBA")
    r, g, b, a = rgba.split()
    # rotate channels based on hue buckets
    buckets = [
        (r, g, b),
        (g, b, r),
        (b, r, g),
        (r, b, g),
        (g, r, b),
        (b, g, r),
    ]
    idx = int(hue_shift) % len(buckets)
    nr, ng, nb = buckets[idx]
    out = Image.merge("RGBA", (nr, ng, nb, a))
    rgb = out.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(sat)
    rgb = ImageEnhance.Brightness(rgb).enhance(bright)
    out2 = rgb.convert("RGBA")
    out2.putalpha(a)
    return out2


def scale_stats(base: dict[str, float], factor: float) -> dict[str, float]:
    out = {}
    for k, v in base.items():
        if k == "mana_regen":
            out[k] = round(v * factor, 2)
        elif v < 0:
            out[k] = -round(abs(v) * min(factor, 1.4), 1)
        else:
            out[k] = round(v * factor, 1) if isinstance(v, float) and not float(v).is_integer() else int(round(v * factor))
    return out


# ---------------------------------------------------------------------------
# Tier catalog (Kyle's naming ladder)
# ---------------------------------------------------------------------------

TIERS = [40, 50, 60, 70, 80, 90]
FACTOR = {40: 1.18, 50: 1.38, 60: 1.60, 70: 1.86, 80: 2.15, 90: 2.50}
CRAFT_LVL = {40: 55, 50: 62, 60: 70, 70: 78, 80: 88, 90: 96}
VENDOR = {40: 220, 50: 360, 60: 520, 70: 740, 80: 980, 90: 1400}
CAPACITY = {40: 5, 50: 5, 60: 5, 70: 6, 80: 6, 90: 7}

MELEE_SETS = {
    40: "Basilisk",
    50: "Wyrmguard",
    60: "Colossus",
    70: "Godsteel",
    80: "Behemoth",
    90: "Worldbreaker",
}
ARCHERY_SETS = {
    40: "Wraithsilk",
    50: "Nightglass",
    60: "Tempest",
    70: "Skyrender",
    80: "Eclipse",
    90: "Starfall",
}
MAGIC_SETS = {
    40: "Runewoven",
    50: "Astral",
    60: "Voidsilk",
    70: "Aetherborn",
    80: "Empyrean",
    90: "Primordial",
}

# Asset mapping — prefer hand-picked sprites; synthesize only when short
MELEE_ASSETS = {
    40: {"helm": "melee helm 1.png", "chest": "melee top 1.png", "boots": "melee boots 1.png"},
    50: {"helm": "melee helm 2.png", "chest": "melee top 2.png", "boots": "melee boots 2.png"},
    60: {"helm": "melee helm 3.png", "chest": "melee top 3.png", "boots": "melee boots 3.png"},
    70: {"helm": "melee helm 4.png", "chest": "melee top  4.png", "boots": "melee boots 5.png"},
    80: {"helm": "melee helm 2.png", "chest": "melee top  5.png", "boots": "melee boots 6.png", "helm_recolor": 1},
    90: {"helm": "melee helm 4.png", "chest": "melee top  6.png", "boots": "melee boots 8.png", "helm_recolor": 2},
}
ARCHERY_ASSETS = {
    40: {"helm": "archery helm 1.png", "chest": "archery top 1.png", "boots": "archery boots 1.png"},
    50: {"helm": "archery helm 2.png", "chest": "archery top 2.png", "boots": "archery boots 2.png"},
    60: {"helm": "archery helm 3.png", "chest": "archery top 3.png", "boots": "archery boots 3.png"},
    70: {"helm": "archery helm 4.png", "chest": "archery top 4.png", "boots": "archery boots 4.png"},
    80: {"helm": "archery helm 5.png", "chest": "archery top 5.png", "boots": "archery boots 5.png"},
    90: {"helm": "archery helm 6.png", "chest": "archery top 7.png", "boots": "archery boots 6.png"},
}
MAGIC_ASSETS = {
    40: {"helm": "magic helm 1.png", "chest": "mage top 1.png", "boots": "mage boots 1.png"},
    50: {"helm": "magic helm 2.png", "chest": "mage top 2.png", "boots": "mage boots 2.png"},
    60: {"helm": "magic helm 3.png", "chest": "mage top 3.png", "boots": "mage boots 3.png"},
    70: {"helm": "magic helm 4.png", "chest": "mage top  4.png", "boots": "mage boots 4.png"},
    80: {"helm": "magic helm 5.png", "chest": "mage top  5.png", "boots": "mage boots 5.png"},
    90: {"helm": "magic helm 7.png", "chest": "mage top  8.png", "boots": "mage boots 7.png"},
}

SWORD_ASSETS = {
    40: "swordsmanship 1.png",
    50: "swordsmanship 2.png",
    60: "swordsmanship 3.png",
    70: "swordsmanship 4.png",
    80: "swordsmanship 6.png",
    90: "swordsmanship 8.png",
}
HAMMER_ASSETS = {
    40: "heavy weapon 1.png",
    50: "heavy weapon 4.png",
    60: "heavy weapon 2.png",
    70: "heavy weapon 6.png",
    80: "heavy weapon 7.png",
    90: "heavy weapon 3.png",
}
BOW_ASSETS = {
    40: "archery 1.png",
    50: "archery 2.png",
    60: "archery 3.png",
    70: "archery 4.png",
    80: "archery 5.png",
    90: "archery 6.png",
}

# Special extras using leftover weapon sprites
SPECIAL_WEAPONS = [
    {
        "slug": "sword_nightfall.item",
        "name": "Nightfall Blade",
        "category": "sword",
        "mastery": 85,
        "asset": "swordsmanship 7.png",
        "desc": "A twin-spiral blade that drinks the light. Forged for duelists who end fights before dawn.",
        "mods": {"ad": 52},
        "capacity": 6,
    },
    {
        "slug": "hammer_kingsbane.item",
        "name": "Kingsbane",
        "category": "hammer",
        "mastery": 85,
        "asset": "heavy weapon 8.png",
        "desc": "A crystal-headed maul whispered to have toppled a throne. Crushingly absolute.",
        "mods": {"ad": 56, "move_speed": -7},
        "capacity": 6,
    },
    {
        "slug": "sword_dawnbreaker.item",
        "name": "Dawnbreaker",
        "category": "sword",
        "mastery": 75,
        "asset": "swordsmanship 5.png",
        "desc": "A molten shortblade that flares with first light. Favored by vanguard captains.",
        "mods": {"ad": 44, "ability_haste": 6},
        "capacity": 6,
    },
    {
        "slug": "hammer_riftedge.item",
        "name": "Riftedge Scythe",
        "category": "hammer",
        "mastery": 75,
        "asset": "heavy weapon 5.png",
        "desc": "Void-edged crescent that shears armor and will alike.",
        "mods": {"ad": 48, "move_speed": -5},
        "capacity": 6,
    },
]

JEWELRY = [
    {"slug": "heart_of_the_wild", "name": "Heart of the Wild", "asset": "necklace 1.png", "slot": "amulet",
     "mods": {"health_max": 28, "armor": 8}, "desc": "A living emerald on a hunter's cord. Steadies the breath in the thick of war.", "vendor": 900},
    {"slug": "ember_locket", "name": "Ember Locket", "asset": "necklace 2.png", "slot": "amulet",
     "mods": {"ad": 12, "health_max": 18}, "desc": "A coal-red gem that never cools. Warms the blood of strikers.", "vendor": 900},
    {"slug": "tideglass_amulet", "name": "Tideglass Amulet", "asset": "necklace 3.png", "slot": "amulet",
     "mods": {"ap": 14, "mana_max": 40, "mana_regen": 2.5}, "desc": "Sealed seawater that refracts spellfire. A mage's second heart.", "vendor": 950},
    {"slug": "oathstone", "name": "Oathstone", "asset": "necklace 4.png", "slot": "amulet",
     "mods": {"armor": 12, "mr": 10, "health_max": 16}, "desc": "A sworn cross of pale metal. Oaths spoken over it tend to hold.", "vendor": 1000},
    {"slug": "reliquary_of_verdance", "name": "Reliquary of Verdance", "asset": "necklace 5.png", "slot": "amulet",
     "mods": {"health_max": 32, "mana_max": 24, "armor": 6}, "desc": "An ancient green focus set in bronze. Relic of the first verdant covenants.", "vendor": 1200},
    {"slug": "covenant_cross", "name": "Covenant Cross", "asset": "necklace 6.png", "slot": "amulet",
     "mods": {"ability_haste": 8, "mr": 8, "health_max": 14}, "desc": "A silver covenant mark. Speeds the resolve between strikes and spells.", "vendor": 1100},
]

RINGS = [
    {"slug": "ring_wayfarer", "name": "Wayfarer's Band", "asset": "gold ring.png",
     "mods": {"move_speed": 8, "health_max": 12}, "desc": "A traveler's gold band. Roads feel shorter with it on.", "vendor": 700},
    {"slug": "ring_heartfire", "name": "Heartfire Ring", "asset": "ring 1.png",
     "mods": {"health_max": 36}, "desc": "Ruby-set gold that pulses with stubborn vitality.", "vendor": 750},
    {"slug": "ring_starweave", "name": "Starweave Ring", "asset": "ring 2.png",
     "mods": {"ap": 10, "mana_max": 30}, "desc": "Violet band threaded with a living green star-shard.", "vendor": 780},
    {"slug": "ring_bulwark", "name": "Bulwark Signet", "asset": "ring 3.png",
     "mods": {"armor": 10, "mr": 8, "health_max": 14}, "desc": "A thick silver signet for those who refuse to fall first.", "vendor": 800},
    {"slug": "ring_sovereign", "name": "Sovereign Circlet", "asset": "ring 4.png",
     "mods": {"ad": 8, "ap": 8, "ability_haste": 6}, "desc": "Jewel-studded circlet once worn by a forgotten court.", "vendor": 1100},
    {"slug": "ring_stormchase", "name": "Stormchase Ring", "asset": "ring 5.png",
     "mods": {"move_speed": 6, "ad": 9, "ability_haste": 4}, "desc": "Dark-blue band that crackles when you sprint to the kill.", "vendor": 850},
    {"slug": "ring_oathband", "name": "Oathband", "asset": "silver ring.png",
     "mods": {"armor": 7, "health_max": 20}, "desc": "Plain silver with weight beyond its size. A quiet promise.", "vendor": 650},
]

SKILLING = [
    # Hats
    {"slug": "skilling_hat_azure", "name": "Azure Tradesman Hat", "asset": "skilling hat  3.png", "slot": "helmet",
     "mods": {"move_speed": 4, "health_max": 10}, "desc": "A crisp azure top-hat for market days and long routes.", "vendor": 180},
    {"slug": "skilling_hat_teal", "name": "Teal Artisan Hat", "asset": "skilling hat 1.png", "slot": "helmet",
     "mods": {"move_speed": 5, "mana_max": 12}, "desc": "Favored by crafters who keep long workshop hours.", "vendor": 200},
    {"slug": "skilling_hat_amber", "name": "Amber Gatherer's Hat", "asset": "skilling hat 2.png", "slot": "helmet",
     "mods": {"move_speed": 6, "health_max": 8}, "desc": "Sun-warmed felt for dawn foragers and ore runners.", "vendor": 220},
    # Tops
    {"slug": "skilling_tunic_sanctum", "name": "Sanctum Work Tunic", "asset": "skilling top 1.png", "slot": "torso",
     "mods": {"health_max": 16, "armor": 3}, "desc": "White-and-gold workshop tunic blessed for careful hands.", "vendor": 240},
    {"slug": "skilling_tunic_service", "name": "Service Apron Coat", "asset": "skilling top 2.png", "slot": "torso",
     "mods": {"move_speed": 3, "health_max": 14}, "desc": "Practical apron coat for bustling trade floors.", "vendor": 230},
    {"slug": "skilling_tunic_rose", "name": "Roseweave Smock", "asset": "skilling top 3.png", "slot": "torso",
     "mods": {"mana_max": 18, "move_speed": 3}, "desc": "Bright smock for herbalists and dye-workers.", "vendor": 250},
    {"slug": "skilling_tunic_crimson", "name": "Crimson Craft Coat", "asset": "skilling top 4.png", "slot": "torso",
     "mods": {"health_max": 18, "armor": 4, "ad": 2}, "desc": "Sturdy red coat of the master smiths' guild.", "vendor": 280},
    # Boots
    {"slug": "skilling_boots_trail", "name": "Trailwalker Boots", "asset": "skilling boots 1.png", "slot": "boot",
     "mods": {"move_speed": 7}, "desc": "Soft leather curl-toes for endless footpaths.", "vendor": 160},
    {"slug": "skilling_boots_tide", "name": "Tidepath Boots", "asset": "skilling boots 2.png", "slot": "boot",
     "mods": {"move_speed": 7, "mana_max": 8}, "desc": "Seafoam-trimmed boots for pier and wetland routes.", "vendor": 180},
    {"slug": "skilling_boots_mist", "name": "Miststride Boots", "asset": "skilling boots 3.png", "slot": "boot",
     "mods": {"move_speed": 8, "mr": 3}, "desc": "Pale boots that quiet your steps through fog.", "vendor": 200},
    {"slug": "skilling_boots_canopy", "name": "Canopy Striders", "asset": "skilling boots 4.png", "slot": "boot",
     "mods": {"move_speed": 8, "health_max": 8}, "desc": "Forest-green curlboots for canopy trails.", "vendor": 210},
    {"slug": "skilling_boots_ember", "name": "Emberpath Boots", "asset": "skilling boots 5.png", "slot": "boot",
     "mods": {"move_speed": 7, "armor": 3}, "desc": "Heat-toughened soles for forge yards and cinder roads.", "vendor": 220},
    {"slug": "skilling_boots_night", "name": "Nightcourier Boots", "asset": "skilling boots 6.png", "slot": "boot",
     "mods": {"move_speed": 9, "ability_haste": 3}, "desc": "Courier blues for midnight deliveries that cannot wait.", "vendor": 260},
]

# Extra armor from leftover mage/archery/fb pieces as alternate mid/high fashion combat pieces
EXTRA_ARMOR = [
    {"slug": "soulbrand_vest", "name": "Soulbrand Vest", "asset": "archery top 6.png", "folder": "leather", "slot": "torso",
     "mastery": 65, "mods": {"armor": 8, "move_speed": 6, "ad": 11}, "desc": "Pale soul-stitched archery plate for mid-ascent hunters.", "vendor": 480},
    {"slug": "duskfeather_cloak", "name": "Duskfeather Cloak", "asset": "fb2089.png", "folder": "leather", "slot": "torso",
     "mastery": 55, "mods": {"armor": 7, "move_speed": 5, "ad": 9}, "desc": "Soft dusk-grey cloak favored by night stalkers.", "vendor": 400},
    {"slug": "ghostweave_jacket", "name": "Ghostweave Jacket", "asset": "archery top 5.png", "folder": "leather", "slot": "torso",
     "mastery": 45, "mods": {"armor": 6, "move_speed": 5, "ad": 8}, "desc": "Buttoned ghost-grey jacket that barely whispers when you draw.", "vendor": 320},
    {"slug": "celestine_robe", "name": "Celestine Robe", "asset": "mage top 9.png", "folder": "cloth", "slot": "torso",
     "mastery": 65, "mods": {"armor": 7, "mr": 10, "mana_max": 18, "ap": 5, "health_max": 12}, "desc": "Muted star-cloth for channelers between Ascension tiers.", "vendor": 500},
    {"slug": "eldritch_coat", "name": "Eldritch Coat", "asset": "mage top 6.png", "folder": "cloth", "slot": "torso",
     "mastery": 55, "mods": {"armor": 6, "mr": 9, "mana_max": 16, "ap": 4, "health_max": 10}, "desc": "Orange-trimmed coat that smells faintly of old rituals.", "vendor": 420},
    {"slug": "firstlight_mantle", "name": "Firstlight Mantle", "asset": "mage top 7.png", "folder": "cloth", "slot": "torso",
     "mastery": 75, "mods": {"armor": 8, "mr": 11, "mana_max": 20, "ap": 6, "health_max": 14}, "desc": "Turquoise mantle woven at the hour the void pales.", "vendor": 620},
    {"slug": "ironbane_cuirass", "asset": "melee top 3.png", "name": "Ironbane Cuirass", "folder": "metal", "slot": "torso",
     "mastery": 45, "mods": {"armor": 16, "health_max": 24, "ad": 8}, "desc": "Red-gold plate etched to bite back against lesser metals.", "vendor": 340},
    {"slug": "ruinplate_chest", "name": "Ruinplate Chestguard", "asset": "fb2099.png", "folder": "metal", "slot": "torso",
     "mastery": 65, "mods": {"armor": 18, "health_max": 28, "ad": 10}, "desc": "Scarlet open-plate from a ruined legion's last stand.", "vendor": 500},
    {"slug": "adamantine_greatcloak", "name": "Adamantine Greatcloak", "asset": "fb2018.png", "folder": "metal", "slot": "torso",
     "mastery": 55, "mods": {"armor": 17, "health_max": 26, "ad": 9}, "desc": "Blue cloak lined with adamantine thread — almost plate.", "vendor": 420},
    {"slug": "doomforge_wrap", "name": "Doomforge Wrap", "asset": "fb2023.png", "folder": "metal", "slot": "torso",
     "mastery": 75, "mods": {"armor": 20, "health_max": 30, "ad": 11}, "desc": "Forge-orange wrap hardened in the Doomforge bellows.", "vendor": 640},
    {"slug": "sigilbound_sandals", "name": "Sigilbound Sandals", "asset": "mage boots 6.png", "folder": "cloth", "slot": "boot",
     "mastery": 60, "mods": {"armor": 5, "mr": 6, "mana_max": 12, "move_speed": 4, "ability_haste": 5}, "desc": "Sigil-stitched mage boots mid-ascension.", "vendor": 360},
    {"slug": "silentwing_sandals", "name": "Silentwing Sandals", "asset": "archery boots 3.png", "folder": "leather", "slot": "boot",
     "mastery": 50, "mods": {"armor": 6, "move_speed": 7, "ad": 6}, "desc": "Lavender softsoles for approaches that must not echo.", "vendor": 300},
]

# Base stats at mastery 30 (Dragon / Sirenic / Ancient / Fire weapons)
BASE_METAL = {
    "helmet": {"armor": 13, "health_max": 20, "ad": 6},
    "chest": {"armor": 14, "health_max": 22, "ad": 7},
    "boots": {"armor": 10, "health_max": 16, "ad": 5},
}
BASE_LEATHER = {
    "helmet": {"armor": 6, "mr": 2, "move_speed": 5, "ad": 6},
    "chest": {"armor": 7, "move_speed": 5, "ad": 8},
    "boots": {"armor": 5, "health_max": 10, "move_speed": 6, "ad": 5},
}
BASE_CLOTH = {
    "helmet": {"armor": 4, "mr": 5, "mana_max": 8, "ap": 2, "health_max": 6},
    "chest": {"armor": 6, "mr": 8, "mana_max": 12, "ap": 3, "health_max": 10},
    "boots": {"armor": 3, "mr": 4, "mana_max": 8, "move_speed": 3, "ability_haste": 4},
}
BASE_SWORD = {"ad": 22}
BASE_HAMMER = {"ad": 24, "move_speed": -6}
BASE_BOW = {"ad": 22, "move_speed": -8}
BASE_WAND = {"ap": 63, "mana_max": 70, "mana_regen": 3.5}
BASE_BOOK = {"ap": 22, "mana_max": 90, "mana_regen": 5.5, "health_max": 40}

DESCRIPTIONS = {
    "Basilisk": "Scaled plate tempered in basilisk bile. Stops fangs — and worse.",
    "Wyrmguard": "Guard-forged plate etched with wyrm-ward runes.",
    "Colossus": "Massive plates that remember the weight of mountains.",
    "Godsteel": "Metal that sings when struck. Said to be quenched in divine fire.",
    "Behemoth": "Siege-born armor for those who become the wall.",
    "Worldbreaker": "End-of-age plate. The world flinches when it lands.",
    "Wraithsilk": "Silk that drinks moonlight and returns it as silence.",
    "Nightglass": "Glass-dark leather that fractures light around the wearer.",
    "Tempest": "Storm-stitched leathers that crackle on the draw.",
    "Skyrender": "Sky-split feathers woven into lethal hunting kit.",
    "Eclipse": "Armor for the hour when the sun forgets its name.",
    "Starfall": "Meteor-thread leathers still warm from the fall.",
    "Runewoven": "Cloth where every stitch is a completed rune.",
    "Astral": "Robes cut from a quieter part of the night sky.",
    "Voidsilk": "Silk pulled from the edge of nothing — and tailored carefully.",
    "Aetherborn": "Born of aether currents; restless until worn by a true mage.",
    "Empyrean": "Highest heaven's weave, heavy with quiet glory.",
    "Primordial": "First-pattern cloth. Magic remembers how to begin here.",
}

catalog: dict = {"items": [], "materials": [], "icons": []}


def gear_tres(
    path: Path,
    *,
    item_name: str,
    slug: str,
    icon_res: str,
    icon_uid: str,
    slot_key: str,
    mastery: int,
    mods: dict,
    description: str,
    vendor: int,
    mastery_cats: list[str] | None = None,
    stack_limit: int = 5,
    can_trade: bool = True,
) -> None:
    slot_uid, slot_path = SLOT[slot_key]
    cats = mastery_cats if mastery_cats is not None else (["any"] if mastery > 0 else [])
    cats_literal = ", ".join(f'&"{c}"' for c in cats)
    mod_blocks = []
    mod_refs = []
    for i, (stat, val) in enumerate(mods.items()):
        mid = f"Mod_{i}"
        mod_refs.append(f'SubResource("{mid}")')
        if stat == "health_max":
            # empty stat_name defaults to health_max in engine, but be explicit
            mod_blocks.append(
                f'[sub_resource type="Resource" id="{mid}"]\n'
                f'script = ExtResource("1_mod")\n'
                f'stat_name = "health_max"\n'
                f"value = {float(val) if isinstance(val, float) else val}.0\n"
                f'metadata/_custom_type_script = "{UID_MOD}"\n'
            )
        else:
            v = float(val) if isinstance(val, (int, float)) else val
            # keep ints looking like ints when whole
            if isinstance(val, int) or (isinstance(val, float) and float(val).is_integer()):
                v_str = f"{int(val)}.0"
            else:
                v_str = str(float(val))
            mod_blocks.append(
                f'[sub_resource type="Resource" id="{mid}"]\n'
                f'script = ExtResource("1_mod")\n'
                f'stat_name = "{stat}"\n'
                f"value = {v_str}\n"
                f'metadata/_custom_type_script = "{UID_MOD}"\n'
            )
    body = f'''[gd_resource type="Resource" script_class="GearItem" format=3 uid="{new_uid()}"]

[ext_resource type="Script" uid="{UID_MOD}" path="res://source/common/gameplay/combat/attributes/stat_modifier.gd" id="1_mod"]
[ext_resource type="Texture2D" uid="{icon_uid}" path="{icon_res}" id="2_icon"]
[ext_resource type="Script" uid="{UID_GEAR}" path="res://source/common/gameplay/items/gear_item.gd" id="3_gear"]
[ext_resource type="Resource" uid="{slot_uid}" path="{slot_path}" id="4_slot"]

{chr(10).join(mod_blocks)}
[resource]
script = ExtResource("3_gear")
required_level = 0
required_mastery_categories = Array[StringName]([{cats_literal}])
required_mastery_level = {mastery}
slot = ExtResource("4_slot")
base_modifiers = Array[ExtResource("1_mod")]([{', '.join(mod_refs)}])
item_name = &"{item_name}"
item_icon = ExtResource("2_icon")
description = "{description}"
holdable = true
is_currency = false
can_trade = {str(can_trade).lower()}
market_minimum_price = 0
vendor_value = {vendor}
stack_limit = {stack_limit}
tags = PackedStringArray("ascension")
metadata/_custom_type_script = "{UID_GEAR}"
'''
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    catalog["items"].append({"slug": slug, "path": str(path.relative_to(ROOT)), "name": item_name, "mastery": mastery})


def weapon_tres(
    path: Path,
    *,
    item_name: str,
    slug: str,
    icon_res: str,
    icon_uid: str,
    category: str,
    mastery: int,
    mods: dict,
    description: str,
    capacity: int,
    vendor: int = 0,
) -> None:
    scene_uid, scene_path = SCENE[category]
    slot_uid, slot_path = SLOT["weapon"]
    mod_blocks = []
    mod_refs = []
    for i, (stat, val) in enumerate(mods.items()):
        mid = f"Mod_{i}"
        mod_refs.append(f'SubResource("{mid}")')
        if isinstance(val, int) or (isinstance(val, float) and float(val).is_integer()):
            v_str = f"{int(val)}.0"
        else:
            v_str = str(float(val))
        mod_blocks.append(
            f'[sub_resource type="Resource" id="{mid}"]\n'
            f'script = ExtResource("1_mod")\n'
            f'stat_name = "{stat}"\n'
            f"value = {v_str}\n"
        )
    body = f'''[gd_resource type="Resource" script_class="WeaponItem" format=3 uid="{new_uid()}"]

[ext_resource type="Script" uid="{UID_MOD}" path="res://source/common/gameplay/combat/attributes/stat_modifier.gd" id="1_mod"]
[ext_resource type="Texture2D" uid="{icon_uid}" path="{icon_res}" id="2_icon"]
[ext_resource type="PackedScene" uid="{scene_uid}" path="{scene_path}" id="3_scene"]
[ext_resource type="Script" uid="{UID_WEAPON}" path="res://source/common/gameplay/items/weapon_item.gd" id="4_item"]
[ext_resource type="Resource" uid="{slot_uid}" path="{slot_path}" id="5_slot"]

{chr(10).join(mod_blocks)}
[resource]
script = ExtResource("4_item")
category = &"{category}"
capacity = {capacity}
right_hand_scene = ExtResource("3_scene")
slot = ExtResource("5_slot")
required_level = 0
required_mastery_categories = Array[StringName]([&"{category}"])
required_mastery_level = {mastery}
base_modifiers = Array[ExtResource("1_mod")]([{', '.join(mod_refs)}])
item_name = &"{item_name}"
item_icon = ExtResource("2_icon")
description = "{description}"
can_trade = true
vendor_value = {vendor}
stack_limit = 5
tags = PackedStringArray("ascension")
metadata/_custom_type_script = "{UID_WEAPON}"
'''
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    catalog["items"].append({"slug": slug, "path": str(path.relative_to(ROOT)), "name": item_name, "mastery": mastery, "category": category})


def material_tres(path: Path, *, item_name: str, slug: str, icon_res: str, icon_uid: str, description: str, vendor: int) -> None:
    body = f'''[gd_resource type="Resource" script_class="MaterialItem" format=3 uid="{new_uid()}"]

[ext_resource type="Texture2D" uid="{icon_uid}" path="{icon_res}" id="1_icon"]
[ext_resource type="Script" uid="{UID_MATERIAL}" path="res://source/common/gameplay/items/material_item.gd" id="2_script"]

[resource]
script = ExtResource("2_script")
item_name = &"{item_name}"
item_icon = ExtResource("1_icon")
description = "{description}"
holdable = false
can_trade = true
vendor_value = {vendor}
stack_limit = 50
tags = PackedStringArray("ascension", "material")
metadata/_custom_type_script = "{UID_MATERIAL}"
'''
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    catalog["materials"].append({"slug": slug, "path": str(path.relative_to(ROOT)), "name": item_name})


def resolve_asset(name: str) -> Path:
    p = SRC / name
    if not p.exists():
        # try normalize double spaces
        alt = SRC / name.replace("  ", " ")
        if alt.exists():
            return alt
        matches = list(SRC.glob(name.replace("  ", "*")))
        if matches:
            return matches[0]
        raise FileNotFoundError(name)
    return p


def copy_icon(asset_name: str, dest_name: str, recolor_idx: int | None = None) -> tuple[str, str]:
    src = resolve_asset(asset_name)
    im = Image.open(src).convert("RGBA")
    if recolor_idx is not None:
        im = recolor(im, recolor_idx)
    dest = ICON_DIR / dest_name
    return write_png(im, dest)


def make_book_icon(tier: int, dest_name: str) -> tuple[str, str]:
    fire = Image.open(ROOT / "assets/sprites/items/weapons/fire/fire.png").convert("RGBA")
    # Fire tome region used by book_fire
    book = fire.crop((96, 32, 112, 48)).resize((32, 32), Image.NEAREST)
    book = recolor(book, {40: 0, 50: 1, 60: 2, 70: 3, 80: 4, 90: 5}[tier], sat=1.25, bright=1.1)
    dest = WPN_ICON_DIR / dest_name
    return write_png(book, dest)


def make_wand_icon(tier: int, dest_name: str) -> tuple[str, str]:
    base_name = "wand 1.png" if tier <= 60 else "wand 2.png"
    im = Image.open(resolve_asset(base_name)).convert("RGBA")
    im = recolor(im, {40: 0, 50: 1, 60: 2, 70: 3, 80: 4, 90: 5}[tier])
    dest = WPN_ICON_DIR / dest_name
    return write_png(im, dest)


def tint_existing_mat(src_name: str, dest_name: str, hue: int) -> tuple[str, str]:
    src = ICON_DIR / src_name
    if not src.exists():
        # fallback solid-ish from dragon ore
        src = ICON_DIR / "ore_dragon.png"
    im = Image.open(src).convert("RGBA")
    im = recolor(im, hue, sat=1.3, bright=1.08)
    dest = ICON_DIR / dest_name
    return write_png(im, dest)


def piece_names(archetype: str, set_name: str) -> dict[str, str]:
    if archetype == "metal":
        return {
            "helmet": f"{set_name} Helmet",
            "chest": f"{set_name} Chestplate",
            "boots": f"{set_name} Boots",
            "slug_helmet": f"{set_name.lower()}_helmet",
            "slug_chest": f"{set_name.lower()}_chest",
            "slug_boots": f"{set_name.lower()}_boots",
        }
    if archetype == "leather":
        return {
            "helmet": f"{set_name} Hood",
            "chest": f"{set_name} Vest",
            "boots": f"{set_name} Sandals",
            "slug_helmet": f"{set_name.lower()}_hood",
            "slug_chest": f"{set_name.lower()}_vest",
            "slug_boots": f"{set_name.lower()}_sandals",
        }
    return {
        "helmet": f"{set_name} Hood",
        "chest": f"{set_name} Robe",
        "boots": f"{set_name} Shoes",
        "slug_helmet": f"{set_name.lower()}_hood",
        "slug_chest": f"{set_name.lower()}_robe",
        "slug_boots": f"{set_name.lower()}_shoes",
    }


def main() -> None:
    WPN_ICON_DIR.mkdir(parents=True, exist_ok=True)
    GEAR_SKILLING.mkdir(parents=True, exist_ok=True)

    # ---- Materials per tier ----
    for i, tier in enumerate(TIERS):
        mset = MELEE_SETS[tier]
        aset = ARCHERY_SETS[tier]
        cset = MAGIC_SETS[tier]
        # metal ore / gem / cloth-lining for melee craft
        ore_res, ore_uid = tint_existing_mat("ore_dragon.png", f"ore_{mset.lower()}.png", i)
        gem_res, gem_uid = tint_existing_mat("gem_dragon.png", f"gem_{mset.lower()}.png", i + 1)
        cloth_res, cloth_uid = tint_existing_mat("cloth_dragon.png", f"cloth_{mset.lower()}.png", i + 2)
        material_tres(
            MAT_METALS / f"{mset.lower()}_ore.tres",
            item_name=f"{mset} Ore",
            slug=f"{mset.lower()}_ore",
            icon_res=ore_res,
            icon_uid=ore_uid,
            description=f"Rare ore used to forge {mset} arms and plate.",
            vendor=10 + i * 4,
        )
        material_tres(
            MAT_GEMS / f"{mset.lower()}_gem.tres",
            item_name=f"{mset} Gem",
            slug=f"{mset.lower()}_gem",
            icon_res=gem_res,
            icon_uid=gem_uid,
            description=f"Faceted focus gem set into {mset} fittings.",
            vendor=12 + i * 4,
        )
        material_tres(
            MAT_CLOTH / f"{mset.lower()}_cloth.tres",
            item_name=f"{mset} Cloth",
            slug=f"{mset.lower()}_cloth",
            icon_res=cloth_res,
            icon_uid=cloth_uid,
            description=f"Hardened lining cloth for {mset} armor.",
            vendor=10 + i * 4,
        )
        # archery leather + gem + cloth
        leather_res, leather_uid = tint_existing_mat("mat_sirenic_leather.png", f"mat_{aset.lower()}_leather.png", i)
        agem_res, agem_uid = tint_existing_mat("gem_dragon.png", f"gem_{aset.lower()}.png", i + 3)
        acloth_res, acloth_uid = tint_existing_mat("cloth_sirenic.png", f"cloth_{aset.lower()}.png", i)
        material_tres(
            MAT_LEATHER / f"{aset.lower()}_leather.tres",
            item_name=f"{aset} Leather",
            slug=f"{aset.lower()}_leather",
            icon_res=leather_res,
            icon_uid=leather_uid,
            description=f"Exotic leather for {aset} archery gear.",
            vendor=12 + i * 4,
        )
        material_tres(
            MAT_GEMS / f"{aset.lower()}_gem.tres",
            item_name=f"{aset} Gem",
            slug=f"{aset.lower()}_gem",
            icon_res=agem_res,
            icon_uid=agem_uid,
            description=f"Hunter's gem for {aset} fittings.",
            vendor=12 + i * 4,
        )
        material_tres(
            MAT_CLOTH / f"{aset.lower()}_cloth.tres",
            item_name=f"{aset} Cloth",
            slug=f"{aset.lower()}_cloth",
            icon_res=acloth_res,
            icon_uid=acloth_uid,
            description=f"Silent weave used in {aset} kits.",
            vendor=10 + i * 4,
        )
        # magic cloth + gem + ore
        mcloth_res, mcloth_uid = tint_existing_mat("cloth_enchanted.png", f"cloth_{cset.lower()}.png", i + 1)
        mgem_res, mgem_uid = tint_existing_mat("gem_dragon.png", f"gem_{cset.lower()}.png", i + 4)
        more_res, more_uid = tint_existing_mat("ore_dragon.png", f"ore_{cset.lower()}.png", i + 2)
        material_tres(
            MAT_CLOTH / f"{cset.lower()}_cloth.tres",
            item_name=f"{cset} Cloth",
            slug=f"{cset.lower()}_cloth",
            icon_res=mcloth_res,
            icon_uid=mcloth_uid,
            description=f"Spellbound cloth for {cset} robes.",
            vendor=12 + i * 4,
        )
        material_tres(
            MAT_GEMS / f"{cset.lower()}_gem.tres",
            item_name=f"{cset} Gem",
            slug=f"{cset.lower()}_gem",
            icon_res=mgem_res,
            icon_uid=mgem_uid,
            description=f"Arcane gem for {cset} foci.",
            vendor=12 + i * 4,
        )
        material_tres(
            MAT_METALS / f"{cset.lower()}_ore.tres",
            item_name=f"{cset} Ore",
            slug=f"{cset.lower()}_ore",
            icon_res=more_res,
            icon_uid=more_uid,
            description=f"Mana-reactive ore used in {cset} crafting.",
            vendor=10 + i * 4,
        )

    # ---- Armor sets ----
    for tier in TIERS:
        f = FACTOR[tier]
        v = VENDOR[tier]
        # metal
        mname = MELEE_SETS[tier]
        assets = MELEE_ASSETS[tier]
        names = piece_names("metal", mname)
        for piece, slot_key, base_key, disp_key, slug_key in [
            ("helm", "helmet", "helmet", "helmet", "slug_helmet"),
            ("chest", "torso", "chest", "chest", "slug_chest"),
            ("boots", "boot", "boots", "boots", "slug_boots"),
        ]:
            icon_name = f"gear_{mname.lower()}_{piece}.png"
            res, uid = copy_icon(
                assets[piece],
                icon_name,
                assets.get("helm_recolor") if piece == "helm" else None,
            )
            gear_tres(
                GEAR_METAL / f"{names[slug_key]}.tres",
                item_name=names[disp_key],
                slug=names[slug_key],
                icon_res=res,
                icon_uid=uid,
                slot_key=slot_key,
                mastery=tier,
                mods=scale_stats(BASE_METAL[base_key], f),
                description=DESCRIPTIONS[mname],
                vendor=v if piece == "chest" else int(v * 0.7) if piece == "helm" else int(v * 0.55),
            )
        # leather
        aname = ARCHERY_SETS[tier]
        assets = ARCHERY_ASSETS[tier]
        names = piece_names("leather", aname)
        for piece, slot_key, base_key, disp_key, slug_key in [
            ("helm", "helmet", "helmet", "helmet", "slug_helmet"),
            ("chest", "torso", "chest", "chest", "slug_chest"),
            ("boots", "boot", "boots", "boots", "slug_boots"),
        ]:
            icon_name = f"gear_{aname.lower()}_{piece}.png"
            res, uid = copy_icon(assets[{"helm": "helm", "chest": "chest", "boots": "boots"}[piece]], icon_name)
            gear_tres(
                GEAR_LEATHER / f"{names[slug_key]}.tres",
                item_name=names[disp_key],
                slug=names[slug_key],
                icon_res=res,
                icon_uid=uid,
                slot_key=slot_key,
                mastery=tier,
                mods=scale_stats(BASE_LEATHER[base_key], f),
                description=DESCRIPTIONS[aname],
                vendor=v if piece == "chest" else int(v * 0.7) if piece == "helm" else int(v * 0.55),
            )
        # cloth
        cname = MAGIC_SETS[tier]
        assets = MAGIC_ASSETS[tier]
        names = piece_names("cloth", cname)
        for piece, slot_key, base_key, disp_key, slug_key in [
            ("helm", "helmet", "helmet", "helmet", "slug_helmet"),
            ("chest", "torso", "chest", "chest", "slug_chest"),
            ("boots", "boot", "boots", "boots", "slug_boots"),
        ]:
            icon_name = f"gear_{cname.lower()}_{piece}.png"
            res, uid = copy_icon(assets[{"helm": "helm", "chest": "chest", "boots": "boots"}[piece]], icon_name)
            gear_tres(
                GEAR_CLOTH / f"{names[slug_key]}.tres",
                item_name=names[disp_key],
                slug=names[slug_key],
                icon_res=res,
                icon_uid=uid,
                slot_key=slot_key,
                mastery=tier,
                mods=scale_stats(BASE_CLOTH[base_key], f),
                description=DESCRIPTIONS[cname],
                vendor=v if piece == "chest" else int(v * 0.7) if piece == "helm" else int(v * 0.55),
            )

        # weapons
        mname = MELEE_SETS[tier]
        aname = ARCHERY_SETS[tier]
        cname = MAGIC_SETS[tier]
        # sword
        res, uid = write_png(resolve_asset(SWORD_ASSETS[tier]), WPN_ICON_DIR / f"sword_{mname.lower()}.png")
        weapon_tres(
            WPN_SWORD / f"sword_{mname.lower()}.item.tres",
            item_name=f"{mname} Sword",
            slug=f"sword_{mname.lower()}.item",
            icon_res=res,
            icon_uid=uid,
            category="sword",
            mastery=tier,
            mods=scale_stats(BASE_SWORD, f),
            description=f"A {mname.lower()} blade forged for Ascension mastery {tier}.",
            capacity=CAPACITY[tier],
            vendor=v,
        )
        # hammer
        res, uid = write_png(resolve_asset(HAMMER_ASSETS[tier]), WPN_ICON_DIR / f"hammer_{mname.lower()}.png")
        weapon_tres(
            WPN_HAMMER / f"hammer_{mname.lower()}.item.tres",
            item_name=f"{mname} Hammer",
            slug=f"hammer_{mname.lower()}.item",
            icon_res=res,
            icon_uid=uid,
            category="hammer",
            mastery=tier,
            mods=scale_stats(BASE_HAMMER, f),
            description=f"A crushing {mname.lower()} warhammer. Mastery {tier}.",
            capacity=CAPACITY[tier],
            vendor=int(v * 1.05),
        )
        # bow
        res, uid = write_png(resolve_asset(BOW_ASSETS[tier]), WPN_ICON_DIR / f"bow_{aname.lower()}.png")
        weapon_tres(
            WPN_BOW / f"{aname.lower()}_bow.item.tres",
            item_name=f"{aname} Bow",
            slug=f"{aname.lower()}_bow.item",
            icon_res=res,
            icon_uid=uid,
            category="bow",
            mastery=tier,
            mods=scale_stats(BASE_BOW, f),
            description=f"A {aname.lower()} bow tuned for deadly range. Mastery {tier}.",
            capacity=CAPACITY[tier],
            vendor=v,
        )
        # wand
        res, uid = make_wand_icon(tier, f"wand_{cname.lower()}.png")
        weapon_tres(
            WPN_WAND / f"wand_{cname.lower()}.item.tres",
            item_name=f"{cname} Wand",
            slug=f"wand_{cname.lower()}.item",
            icon_res=res,
            icon_uid=uid,
            category="wand",
            mastery=tier,
            mods=scale_stats(BASE_WAND, f),
            description=f"A {cname.lower()} focus wand. Mastery {tier}.",
            capacity=CAPACITY[tier],
            vendor=v,
        )
        # book / tome
        res, uid = make_book_icon(tier, f"book_{cname.lower()}.png")
        weapon_tres(
            WPN_BOOK / f"book_{cname.lower()}.item.tres",
            item_name=f"{cname} Tome",
            slug=f"book_{cname.lower()}.item",
            icon_res=res,
            icon_uid=uid,
            category="book",
            mastery=tier,
            mods=scale_stats(BASE_BOOK, f),
            description=f"A battlemage's {cname.lower()} tome. Mastery {tier}.",
            capacity=CAPACITY[tier],
            vendor=int(v * 1.05),
        )

    # Special weapons
    for spec in SPECIAL_WEAPONS:
        res, uid = write_png(resolve_asset(spec["asset"]), WPN_ICON_DIR / f"{spec['slug'].replace('.item','')}.png")
        weapon_tres(
            {"sword": WPN_SWORD, "hammer": WPN_HAMMER}[spec["category"]] / f"{spec['slug']}.tres",
            item_name=spec["name"],
            slug=spec["slug"],
            icon_res=res,
            icon_uid=uid,
            category=spec["category"],
            mastery=spec["mastery"],
            mods=spec["mods"],
            description=spec["desc"],
            capacity=spec["capacity"],
            vendor=900 if spec["mastery"] < 80 else 1200,
        )

    # Jewelry
    for j in JEWELRY:
        res, uid = copy_icon(j["asset"], f"jewelry_{j['slug']}.png")
        gear_tres(
            GEAR_JEWELRY / f"{j['slug']}.tres",
            item_name=j["name"],
            slug=j["slug"],
            icon_res=res,
            icon_uid=uid,
            slot_key="amulet",
            mastery=0,
            mods=j["mods"],
            description=j["desc"],
            vendor=j["vendor"],
            mastery_cats=[],
        )
    for r in RINGS:
        res, uid = copy_icon(r["asset"], f"ring_{r['slug']}.png")
        gear_tres(
            GEAR_RINGS / f"{r['slug']}.tres",
            item_name=r["name"],
            slug=r["slug"],
            icon_res=res,
            icon_uid=uid,
            slot_key="ring",
            mastery=0,
            mods=r["mods"],
            description=r["desc"],
            vendor=r["vendor"],
            mastery_cats=[],
        )

    # Skilling
    for s in SKILLING:
        res, uid = copy_icon(s["asset"], f"gear_{s['slug']}.png")
        gear_tres(
            GEAR_SKILLING / f"{s['slug']}.tres",
            item_name=s["name"],
            slug=s["slug"],
            icon_res=res,
            icon_uid=uid,
            slot_key=s["slot"],
            mastery=0,
            mods=s["mods"],
            description=s["desc"],
            vendor=s["vendor"],
            mastery_cats=[],
        )

    # Extra armor (spare-bank themed)
    for e in EXTRA_ARMOR:
        asset = e.get("asset_override", e["asset"])
        # fix ghostweave double
        try:
            res, uid = copy_icon(asset, f"gear_{e['slug']}.png")
        except FileNotFoundError:
            res, uid = copy_icon(e["asset"], f"gear_{e['slug']}.png")
        folder = {"metal": GEAR_METAL, "leather": GEAR_LEATHER, "cloth": GEAR_CLOTH}[e["folder"]]
        gear_tres(
            folder / f"{e['slug']}.tres",
            item_name=e["name"],
            slug=e["slug"],
            icon_res=res,
            icon_uid=uid,
            slot_key=e["slot"],
            mastery=e["mastery"],
            mods=e["mods"],
            description=e["desc"],
            vendor=e["vendor"],
        )

    CATALOG_OUT.write_text(json.dumps(catalog, indent=2))
    print(f"Generated {len(catalog['items'])} items, {len(catalog['materials'])} materials")
    print(f"Catalog -> {CATALOG_OUT}")


if __name__ == "__main__":
    main()
