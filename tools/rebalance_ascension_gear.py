#!/usr/bin/env python3
"""Rebalance Ascension gear for true endgame (3000+ HP bosses, mastery→99).

Rewrites base_modifiers on Ascension gear/weapons/jewelry in place.
Prints a before→after summary table.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path("/workspace/source/common/gameplay/items")

# Weapon AD/AP targets (basic swing ≈ 100% AD). Fire Sword is 35 AD at m30.
# m90 should chew current 3k bosses and leave headroom for harder content.
# Bone (boss drop) sits at 19 AD, above adamant 14 / runite 17; every drop
# past bone is shifted by the same delta so smithable metals never outclass them.
SWORD_AD = {40: 75, 50: 111, 60: 158, 70: 218, 80: 293, 90: 383}
HAMMER_AD = {40: 84, 50: 124, 60: 174, 70: 239, 80: 324, 90: 424}
BOW_AD = {40: 75, 50: 111, 60: 158, 70: 218, 80: 293, 90: 383}
WAND_AP = {40: 151, 50: 206, 60: 276, 70: 361, 80: 461, 90: 591}
BOOK_AP = {40: 74, 50: 110, 60: 157, 70: 217, 80: 292, 90: 382}

# Unique identity bonuses kick in hard at m60+
UNIQUE = {
    # melee plate piece extras applied on top of scaled baseline
    "Colossus": {"helmet": {"health_max": 40}, "chest": {"health_max": 60, "armor": 8}, "boots": {"health_max": 30}},
    "Godsteel": {"helmet": {"ability_haste": 4}, "chest": {"ability_haste": 6, "ad": 8}, "boots": {"ability_haste": 4}},
    "Behemoth": {"helmet": {"armor": 10, "health_max": 35}, "chest": {"armor": 14, "health_max": 55}, "boots": {"armor": 8}},
    "Worldbreaker": {"helmet": {"ad": 10, "ability_haste": 4}, "chest": {"ad": 14, "ability_haste": 6}, "boots": {"ad": 8, "move_speed": 4}},
    "Tempest": {"helmet": {"ability_haste": 5}, "chest": {"ability_haste": 7, "move_speed": 4}, "boots": {"ability_haste": 5, "move_speed": 6}},
    "Skyrender": {"helmet": {"ad": 6, "ability_haste": 4}, "chest": {"ad": 10, "ability_haste": 6}, "boots": {"ad": 6, "move_speed": 5}},
    "Eclipse": {"helmet": {"mr": 6, "ability_haste": 5}, "chest": {"mr": 8, "ad": 8, "ability_haste": 6}, "boots": {"mr": 5, "move_speed": 5}},
    "Starfall": {"helmet": {"ad": 10, "ability_haste": 6}, "chest": {"ad": 14, "ability_haste": 8}, "boots": {"ad": 8, "move_speed": 8, "ability_haste": 5}},
    "Voidsilk": {"helmet": {"mana_regen": 2.5, "ability_haste": 4}, "chest": {"mana_regen": 3.5, "ability_haste": 6}, "boots": {"mana_regen": 2.0, "ability_haste": 5}},
    "Aetherborn": {"helmet": {"ap": 6, "ability_haste": 5}, "chest": {"ap": 10, "ability_haste": 7}, "boots": {"ap": 5, "ability_haste": 5}},
    "Empyrean": {"helmet": {"health_max": 25, "ap": 6}, "chest": {"health_max": 40, "ap": 10, "ability_haste": 5}, "boots": {"health_max": 20, "ability_haste": 4}},
    "Primordial": {"helmet": {"ap": 10, "mr": 6, "ability_haste": 6}, "chest": {"ap": 16, "mr": 10, "ability_haste": 8}, "boots": {"ap": 8, "ability_haste": 6, "mana_regen": 2.5}},
}

SETS = {
    40: ("Basilisk", "Wraithsilk", "Runewoven"),
    50: ("Wyrmguard", "Nightglass", "Astral"),
    60: ("Colossus", "Tempest", "Voidsilk"),
    70: ("Godsteel", "Skyrender", "Aetherborn"),
    80: ("Behemoth", "Eclipse", "Empyrean"),
    90: ("Worldbreaker", "Starfall", "Primordial"),
}

# Armor scale vs old Dragon baselines — much steeper for endgame
ARMOR_SCALE = {40: 1.55, 50: 2.15, 60: 2.95, 70: 3.95, 80: 5.2, 90: 6.8}
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

SPECIALS = {
    "sword_dawnbreaker.item.tres": {"ad": 243, "ability_haste": 10},
    "hammer_riftedge.item.tres": {"ad": 264, "move_speed": -4, "ability_haste": 6},
    "sword_nightfall.item.tres": {"ad": 323, "ability_haste": 8},
    "hammer_kingsbane.item.tres": {"ad": 354, "move_speed": -6, "ability_haste": 4},
}

JEWELRY = {
    "heart_of_the_wild.tres": {"health_max": 85, "armor": 22},
    "ember_locket.tres": {"ad": 48, "health_max": 55},
    "tideglass_amulet.tres": {"ap": 55, "mana_max": 120, "mana_regen": 6.0},
    "oathstone.tres": {"armor": 35, "mr": 28, "health_max": 50},
    "reliquary_of_verdance.tres": {"health_max": 95, "mana_max": 70, "armor": 18},
    "covenant_cross.tres": {"ability_haste": 14, "mr": 20, "health_max": 40},
}
RINGS = {
    "ring_wayfarer.tres": {"move_speed": 14, "health_max": 35},
    "ring_heartfire.tres": {"health_max": 110},
    "ring_starweave.tres": {"ap": 38, "mana_max": 90},
    "ring_bulwark.tres": {"armor": 28, "mr": 22, "health_max": 40},
    "ring_sovereign.tres": {"ad": 28, "ap": 28, "ability_haste": 10},
    "ring_stormchase.tres": {"move_speed": 10, "ad": 32, "ability_haste": 8},
    "ring_oathband.tres": {"armor": 20, "health_max": 60},
}


def scale(base: dict, factor: float) -> dict:
    out = {}
    for k, v in base.items():
        if k == "mana_regen":
            out[k] = round(v * factor, 2)
        elif v < 0:
            out[k] = -round(abs(v) * min(factor, 1.35), 1)
        else:
            out[k] = int(round(v * factor))
    return out


def merge(a: dict, b: dict) -> dict:
    out = dict(a)
    for k, v in b.items():
        out[k] = round(out.get(k, 0) + v, 2) if isinstance(v, float) or isinstance(out.get(k, 0), float) else int(out.get(k, 0) + v)
    return out


def rewrite_mods(path: Path, mods: dict) -> str:
    text = path.read_text()
    name = re.search(r'item_name = &"([^"]+)"', text)
    old_blocks = re.findall(
        r'\[sub_resource type="Resource" id="Mod_\d+"\]\n(.*?)(?=\n\[sub_resource|\n\[resource\])',
        text,
        re.S,
    )
    old_summary = []
    for b in old_blocks:
        sn = re.search(r'stat_name = "([^"]+)"', b)
        val = re.search(r'value = (-?[0-9.]+)', b)
        if val:
            old_summary.append(f"{sn.group(1) if sn else 'hp'}={val.group(1)}")

    # Build new mod subresources
    lines = []
    refs = []
    for i, (stat, val) in enumerate(mods.items()):
        mid = f"Mod_{i}"
        refs.append(f'SubResource("{mid}")')
        if isinstance(val, float) and not float(val).is_integer():
            v_str = str(val)
        else:
            v_str = f"{int(val)}.0"
        lines.append(
            f'[sub_resource type="Resource" id="{mid}"]\n'
            f'script = ExtResource("1_mod")\n'
            f'stat_name = "{stat}"\n'
            f"value = {v_str}\n"
            f'metadata/_custom_type_script = "uid://cvggwjkht4km4"\n'
        )
    new_mods = "\n".join(lines)

    # Replace all Mod_* subresources before [resource]
    text2 = re.sub(
        r'(?:\[sub_resource type="Resource" id="Mod_\d+"\]\n(?:.*?\n)+?)+(?=\[resource\])',
        new_mods + "\n",
        text,
        count=1,
    )
    text2 = re.sub(
        r'base_modifiers = Array\[ExtResource\("1_mod"\)\]\(\[.*?\]\)',
        f'base_modifiers = Array[ExtResource("1_mod")]([{", ".join(refs)}])',
        text2,
        count=1,
    )
    path.write_text(text2)
    new_summary = [f"{k}={v}" for k, v in mods.items()]
    return f"{name.group(1) if name else path.name}: [{', '.join(old_summary)}] → [{', '.join(new_summary)}]"


def main() -> None:
    report: list[str] = []
    report.append("=== WEAPONS ===")
    for tier, (m, a, c) in SETS.items():
        pairs = [
            (ROOT / f"weapons/sword/sword_{m.lower()}.item.tres", {"ad": SWORD_AD[tier]}),
            (ROOT / f"weapons/hammer/hammer_{m.lower()}.item.tres", {"ad": HAMMER_AD[tier], "move_speed": -6 if tier < 60 else -5}),
            (ROOT / f"weapons/bow/{a.lower()}_bow.item.tres", {"ad": BOW_AD[tier], "move_speed": -6 if tier < 60 else -5}),
            (ROOT / f"weapons/wand/wand_{c.lower()}.item.tres", {
                "ap": WAND_AP[tier],
                "mana_max": int(90 + tier * 2.2),
                "mana_regen": round(4.0 + (tier - 40) * 0.12, 2),
            }),
            (ROOT / f"weapons/book/book_{c.lower()}.item.tres", {
                "ap": BOOK_AP[tier],
                "mana_max": int(140 + tier * 3.5),
                "mana_regen": round(7.0 + (tier - 40) * 0.18, 2),
                "health_max": int(60 + (tier - 40) * 2.5),
            }),
        ]
        # Unique weapon bonuses m60+
        if tier >= 60:
            pairs[0][1]["ability_haste"] = 4 + (tier - 60) // 10 * 2
            pairs[1][1]["ability_haste"] = 3 + (tier - 60) // 10 * 2
            pairs[2][1]["ability_haste"] = 5 + (tier - 60) // 10 * 2
            pairs[3][1]["ability_haste"] = 6 + (tier - 60) // 10 * 2
            pairs[4][1]["ability_haste"] = 6 + (tier - 60) // 10 * 2
        for path, mods in pairs:
            report.append(rewrite_mods(path, mods))

    report.append("\n=== SPECIALS ===")
    for fname, mods in SPECIALS.items():
        folder = "sword" if "sword" in fname else "hammer"
        report.append(rewrite_mods(ROOT / f"weapons/{folder}/{fname}", mods))

    report.append("\n=== ARMOR ===")
    for tier, (m, a, c) in SETS.items():
        f = ARMOR_SCALE[tier]
        for set_name, folder, bases, piece_map in [
            (m, "metal", BASE_METAL, [("helmet", "helmet"), ("chest", "chest"), ("boots", "boots")]),
            (a, "leather", BASE_LEATHER, [("helmet", "hood"), ("chest", "vest"), ("boots", "sandals")]),
            (c, "cloth", BASE_CLOTH, [("helmet", "hood"), ("chest", "robe"), ("boots", "shoes")]),
        ]:
            for base_key, file_key in piece_map:
                mods = scale(bases[base_key], f)
                if set_name in UNIQUE:
                    # map helmet/chest/boots keys for leather/cloth too
                    ukey = {"hood": "helmet", "vest": "chest", "sandals": "boots", "robe": "chest", "shoes": "boots"}.get(file_key, file_key)
                    extra = UNIQUE[set_name].get(ukey, {})
                    mods = merge(mods, extra)
                if folder == "metal":
                    path = ROOT / f"gears/metal/{set_name.lower()}_{file_key}.tres"
                elif folder == "leather":
                    leather_piece = {"helmet": "hood", "chest": "vest", "boots": "sandals"}[base_key]
                    path = ROOT / f"gears/leather/{set_name.lower()}_{leather_piece}.tres"
                else:
                    cloth_piece = {"helmet": "hood", "chest": "robe", "boots": "shoes"}[base_key]
                    path = ROOT / f"gears/cloth/{set_name.lower()}_{cloth_piece}.tres"
                report.append(rewrite_mods(path, mods))

    report.append("\n=== JEWELRY ===")
    for fname, mods in JEWELRY.items():
        report.append(rewrite_mods(ROOT / f"gears/jewelry/{fname}", mods))
    for fname, mods in RINGS.items():
        report.append(rewrite_mods(ROOT / f"gears/rings/{fname}", mods))

    # Alternates — buff mid-ladder too
    report.append("\n=== ALTERNATES ===")
    ALTS = {
        "gears/metal/ironbane_cuirass.tres": {"armor": 28, "health_max": 55, "ad": 18},
        "gears/metal/adamantine_greatcloak.tres": {"armor": 36, "health_max": 70, "ad": 24},
        "gears/metal/ruinplate_chest.tres": {"armor": 48, "health_max": 95, "ad": 32},
        "gears/metal/doomforge_wrap.tres": {"armor": 62, "health_max": 120, "ad": 42, "ability_haste": 5},
        "gears/leather/ghostweave_jacket.tres": {"armor": 14, "move_speed": 8, "ad": 20},
        "gears/leather/duskfeather_cloak.tres": {"armor": 18, "move_speed": 10, "ad": 28, "ability_haste": 4},
        "gears/leather/soulbrand_vest.tres": {"armor": 24, "move_speed": 12, "ad": 40, "ability_haste": 6},
        "gears/leather/silentwing_sandals.tres": {"armor": 12, "move_speed": 14, "ad": 16},
        "gears/cloth/eldritch_coat.tres": {"armor": 14, "mr": 20, "mana_max": 40, "ap": 14, "health_max": 25},
        "gears/cloth/celestine_robe.tres": {"armor": 18, "mr": 28, "mana_max": 55, "ap": 22, "health_max": 35, "ability_haste": 5},
        "gears/cloth/firstlight_mantle.tres": {"armor": 24, "mr": 36, "mana_max": 75, "ap": 32, "health_max": 45, "ability_haste": 8},
        "gears/cloth/sigilbound_sandals.tres": {"armor": 12, "mr": 16, "mana_max": 35, "move_speed": 8, "ability_haste": 8},
    }
    for rel, mods in ALTS.items():
        report.append(rewrite_mods(ROOT / rel, mods))

    out = Path("/opt/cursor/artifacts/ascension-rebalance-report.txt")
    out.write_text("\n".join(report))
    print(f"Wrote {out} ({len(report)} lines)")
    # Print key weapon summary
    print("\nKEY WEAPON AD/AP TARGETS:")
    for t in [40, 50, 60, 70, 80, 90]:
        print(f"  m{t}: sword {SWORD_AD[t]} AD · hammer {HAMMER_AD[t]} AD · bow {BOW_AD[t]} AD · wand {WAND_AP[t]} AP · tome {BOOK_AP[t]} AP")
    print("\nFull Worldbreaker plate (approx): helm+chest+boots AD/Armor/HP from report")
    print("Starfall bow now:", SWORD_AD[90], "AD class (370)")


if __name__ == "__main__":
    main()
