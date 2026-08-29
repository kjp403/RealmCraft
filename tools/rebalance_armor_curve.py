#!/usr/bin/env python3
"""Raise armor piece stats so a full set actually changes fights.

Mitigation is 100/(100+armor) with a 15-armor naked baseline. Old bronze
(9 set armor) moved DR from 13% to 19%. This curve makes bronze a real kit
and keeps 40–90 plate above dragon so the ladder still climbs.

Cloth and leather are the mage / archery kits. Their AP / AD / mana / haste /
speed must beat same-mastery metal for that style so players do not default
to plate while casting or shooting. Metal stays the tank set (this tool does
not rewrite metal unless --families includes it).
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "source/common/gameplay/items/gears"

# Full 3-piece metal set. Kept modest on purpose: unique drop weapons already
# carry the DPS, so plate should be a noticeable tank bump without making
# dungeon bosses trivial. Naked baseline is 15 armor (13% DR).
SET_ARMOR = {
    1: 22,
    5: 32,
    10: 44,
    15: 58,
    20: 74,
    25: 92,
    30: 112,
    40: 140,
    45: 152,
    50: 165,
    55: 176,
    60: 186,
    65: 194,
    70: 200,
    75: 210,
    80: 220,
    90: 235,
}
SET_HP = {
    1: 40,
    5: 55,
    10: 72,
    15: 94,
    20: 118,
    25: 145,
    30: 176,
    40: 215,
    45: 235,
    50: 255,
    55: 275,
    60: 292,
    65: 305,
    70: 315,
    75: 335,
    80: 350,
    90: 375,
}

PIECE = {
    "helmet": (0.32, 0.30),
    "chest": (0.45, 0.45),
    "boots": (0.23, 0.25),
}

# Folder identity: metal tanks physical, leather is speed/AD, cloth tanks magic
# and carries AP. Leather/cloth survivability stays below plate on purpose.
FAMILY = {
    "metal": {"armor": 1.00, "hp": 1.00, "mr": 0.15, "ad": 1.00, "ap": 0.00, "speed": 1.00},
    "leather": {"armor": 0.62, "hp": 0.78, "mr": 0.42, "ad": 2.20, "ap": 0.00, "speed": 2.40},
    "cloth": {"armor": 0.38, "hp": 0.62, "mr": 1.10, "ad": 0.00, "ap": 2.20, "speed": 1.50},
}

SET_MULT = {
    "copper": 0.72,
    "gold": 0.92,
    "silver": 0.90,
}

SKIP_NAMES = {
    "skilling_tunic_crimson",
    "skilling_tunic_sanctum",
}

# Named-set extras on top of the curve so uniques still beat the adjacent tier.
UNIQUE_EXTRAS: dict[str, dict[str, dict[str, float]]] = {
    "Tempest": {
        "helmet": {"ability_haste": 5},
        "chest": {"ability_haste": 7, "move_speed": 4},
        "boots": {"ability_haste": 5, "move_speed": 6},
    },
    "Skyrender": {
        "helmet": {"ad": 6, "ability_haste": 4},
        "chest": {"ad": 10, "ability_haste": 6},
        "boots": {"ad": 6, "move_speed": 5},
    },
    "Eclipse": {
        "helmet": {"mr": 6, "ability_haste": 5},
        "chest": {"mr": 8, "ad": 8, "ability_haste": 6},
        "boots": {"mr": 5, "move_speed": 5},
    },
    "Starfall": {
        "helmet": {"ad": 10, "ability_haste": 6},
        "chest": {"ad": 14, "ability_haste": 8},
        "boots": {"ad": 8, "move_speed": 8, "ability_haste": 5},
    },
    "Voidsilk": {
        "helmet": {"mana_regen": 2.5, "ability_haste": 4},
        "chest": {"mana_regen": 3.5, "ability_haste": 6},
        "boots": {"mana_regen": 2.0, "ability_haste": 5},
    },
    "Aetherborn": {
        "helmet": {"ap": 6, "ability_haste": 5},
        "chest": {"ap": 10, "ability_haste": 7},
        "boots": {"ap": 5, "ability_haste": 5},
    },
    "Empyrean": {
        "helmet": {"health_max": 25, "ap": 6},
        "chest": {"health_max": 40, "ap": 10, "ability_haste": 5},
        "boots": {"health_max": 20, "ability_haste": 4},
    },
    "Primordial": {
        "helmet": {"ap": 10, "mr": 6, "ability_haste": 6},
        "chest": {"ap": 16, "mr": 10, "ability_haste": 8},
        "boots": {"ap": 8, "ability_haste": 6, "mana_regen": 2.5},
    },
    "Phantom": {
        "helmet": {"move_speed": 3, "ad": 3},
        "chest": {"move_speed": 4, "ad": 4},
        "boots": {"move_speed": 5, "ad": 3},
    },
    "Duskfeather": {"chest": {"ad": 10, "move_speed": 6, "ability_haste": 4}},
    "Ghostweave": {"chest": {"ad": 8, "move_speed": 4, "ability_haste": 3}},
    "Soulbrand": {"chest": {"ad": 12, "move_speed": 6, "ability_haste": 6}},
    "Silentwing": {"boots": {"move_speed": 8, "ad": 6}},
    "Eldritch": {"chest": {"ap": 10, "mana_max": 15, "ability_haste": 4}},
    "Celestine": {"chest": {"ap": 12, "mana_max": 18, "ability_haste": 5}},
    "Firstlight": {"chest": {"ap": 16, "mana_max": 24, "ability_haste": 8}},
    "Sigilbound": {"boots": {"ability_haste": 6, "move_speed": 4, "mana_max": 12}},
}

COMPARE_CHESTS = [
    (5, "metal/iron_chest.tres", "leather/studded_jacket.tres", "cloth/apprentice_robe.tres"),
    (15, "metal/mithril_chest.tres", "leather/shadow_vest.tres", "cloth/enchanted_robe.tres"),
    (40, "metal/basilisk_chest.tres", "leather/wraithsilk_vest.tres", "cloth/runewoven_robe.tres"),
    (50, "metal/wyrmguard_chest.tres", "leather/nightglass_vest.tres", "cloth/astral_robe.tres"),
    (70, "metal/colossus_chest.tres", "leather/skyrender_vest.tres", "cloth/aetherborn_robe.tres"),
    (90, "metal/worldbreaker_chest.tres", "leather/starfall_vest.tres", "cloth/primordial_robe.tres"),
]


def lerp_table(table: dict[int, int], mastery: int) -> int:
    keys = sorted(table)
    if mastery <= keys[0]:
        return table[keys[0]]
    if mastery >= keys[-1]:
        return table[keys[-1]]
    for lo, hi in zip(keys, keys[1:]):
        if lo <= mastery <= hi:
            t = (mastery - lo) / (hi - lo)
            return int(round(table[lo] + (table[hi] - table[lo]) * t))
    return table[keys[-1]]


def piece_key(slot_path: str, item_name: str) -> str:
    low = item_name.lower()
    if "helmet" in low or "hood" in low or "cap" in low:
        return "helmet"
    if "boot" in low or "sandal" in low or "shoe" in low:
        return "boots"
    if "chest" in low or "vest" in low or "robe" in low or "jacket" in low or "cuirass" in low or "cloak" in low or "wrap" in low or "mantle" in low or "coat" in low:
        return "chest"
    if "helmet.tres" in slot_path:
        return "helmet"
    if "boot.tres" in slot_path:
        return "boots"
    return "chest"


def set_mult(item_name: str) -> float:
    first = item_name.split(" ", 1)[0].lower()
    return SET_MULT.get(first, 1.0)


def unique_key(item_name: str) -> str:
    first = item_name.replace("\\'", "'").split()[0]
    return first.replace("'s", "")


def merge_mods(base: dict[str, float], extra: dict[str, float]) -> dict[str, float]:
    out = dict(base)
    for stat, val in extra.items():
        cur = out.get(stat, 0)
        if stat == "mana_regen" or isinstance(val, float) and not float(val).is_integer() or isinstance(cur, float) and not float(cur).is_integer():
            out[stat] = round(float(cur) + float(val), 2)
        else:
            out[stat] = int(round(float(cur) + float(val)))
    return out


def offensive(mastery: int, piece: str, family: str) -> dict[str, float]:
    """AD / AP / speed that should be visible, not flavor text.

    Metal keeps a little AD so melee plate is not a pure EHP dump. Leather AD
    and cloth AP are ~2x that metal AD so archery / magic actually want their
    own sets. Spells scale with AP (often 80–200%); bows scale with AD.
    """
    m = max(1, mastery)
    if family == "metal":
        ad = 2 + m * 0.42
        if piece == "helmet":
            return {"ad": ad * 0.85}
        if piece == "chest":
            return {"ad": ad}
        return {"move_speed": 2 + m * 0.06}
    if family == "leather":
        ad = 7 + m * 1.20
        spd = 5 + m * 0.22
        haste = 2 + m * 0.08
        if piece == "helmet":
            return {"ad": ad * 0.8, "move_speed": spd * 0.7, "ability_haste": haste * 0.7}
        if piece == "chest":
            return {"ad": ad, "move_speed": spd * 0.85, "ability_haste": haste}
        return {"ad": ad * 0.7, "move_speed": spd, "ability_haste": haste * 0.8}
    ap = 7 + m * 1.20
    mana = 18 + m * 2.4
    haste = 2 + m * 0.10
    if piece == "helmet":
        return {"ap": ap * 0.8, "mana_max": mana * 0.7, "ability_haste": haste * 0.7}
    if piece == "chest":
        return {"ap": ap, "mana_max": mana, "ability_haste": haste}
    return {
        "ap": ap * 0.55,
        "mana_max": mana * 0.6,
        "move_speed": 4 + m * 0.10,
        "ability_haste": haste,
    }


def target_mods(family: str, mastery: int, piece: str, item_name: str) -> dict[str, float]:
    fam = FAMILY[family]
    mult = set_mult(item_name)
    aw, hw = PIECE[piece]
    armor = lerp_table(SET_ARMOR, mastery) * aw * fam["armor"] * mult
    hp = lerp_table(SET_HP, mastery) * hw * fam["hp"] * mult
    mr = lerp_table(SET_ARMOR, mastery) * aw * fam["mr"] * mult
    mods: dict[str, float] = {
        "armor": max(1, round(armor)),
        "health_max": max(4, round(hp)),
    }
    if mr >= 1:
        mods["mr"] = max(1, round(mr))
    for stat, val in offensive(mastery, piece, family).items():
        scaled = val * mult
        if stat in ("mana_regen",):
            mods[stat] = round(scaled, 2)
        else:
            mods[stat] = max(1, round(scaled))
    extra = UNIQUE_EXTRAS.get(unique_key(item_name), {}).get(piece, {})
    if extra:
        mods = merge_mods(mods, extra)
        for stat, val in list(mods.items()):
            if stat == "mana_regen":
                continue
            mods[stat] = max(1, round(val)) if not isinstance(val, float) or float(val).is_integer() else val
    return mods


def parse_mastery(text: str) -> int:
    m = re.search(r"required_mastery_level = (\d+)", text)
    if m:
        return int(m.group(1))
    return 1


def parse_name(text: str) -> str:
    m = re.search(r'item_name = &"([^"]+)"', text)
    return m.group(1) if m else ""


def parse_stats(text: str) -> dict[str, float]:
    return {
        name: float(val)
        for name, val in re.findall(r'stat_name = "([^"]+)"\s*\nvalue = (-?[0-9.]+)', text)
    }


def mod_ext_id(text: str) -> str:
    m = re.search(
        r'path="res://source/common/gameplay/combat/attributes/stat_modifier.gd"[^\]]*id="([^"]+)"',
        text,
    )
    return m.group(1) if m else "1_mod"


def rewrite(path: Path, mods: dict[str, float]) -> str:
    text = path.read_text(encoding="utf-8")
    name = parse_name(text)
    ext_id = mod_ext_id(text)
    old = re.findall(r'stat_name = "([^"]+)"\s*\nvalue = (-?[0-9.]+)', text)
    if not old:
        old = re.findall(r'value = (-?[0-9.]+)', text)
        old = [("?", v) for v in old[:6]]

    lines: list[str] = []
    refs: list[str] = []
    for i, (stat, val) in enumerate(mods.items()):
        mid = f"Mod_{i}"
        refs.append(f'SubResource("{mid}")')
        if isinstance(val, float) and not float(val).is_integer():
            v_str = str(val)
        else:
            v_str = f"{int(val)}.0"
        lines.append(
            f'[sub_resource type="Resource" id="{mid}"]\n'
            f'script = ExtResource("{ext_id}")\n'
            f'stat_name = "{stat}"\n'
            f"value = {v_str}\n"
            f'metadata/_custom_type_script = "uid://cvggwjkht4km4"\n'
        )
    new_mods = "\n".join(lines)
    text2 = re.sub(
        r'(?:\[sub_resource type="Resource" id="Mod_[^\"]+"\]\n(?:.*?\n)+?)+(?=\[resource\])',
        new_mods + "\n",
        text,
        count=1,
    )
    text2 = re.sub(
        rf'base_modifiers = Array\[ExtResource\("{re.escape(ext_id)}"\)\]\(\[.*?\]\)',
        f'base_modifiers = Array[ExtResource("{ext_id}")]([{", ".join(refs)}])',
        text2,
        count=1,
    )
    if text2 == text:
        raise RuntimeError(f"failed to rewrite {path}")
    path.write_text(text2, encoding="utf-8")
    old_s = ", ".join(f"{a}={b}" for a, b in old)
    new_s = ", ".join(f"{k}={v}" for k, v in mods.items())
    return f"{name}: [{old_s}] -> [{new_s}]"


def fmt_piece(rel: str) -> str:
    path = ROOT / rel
    stats = parse_stats(path.read_text(encoding="utf-8"))
    bits = []
    for key in ("armor", "health_max", "mr", "ad", "ap", "mana_max", "move_speed", "ability_haste", "mana_regen"):
        if key in stats:
            val = stats[key]
            bits.append(f"{key}={int(val) if float(val).is_integer() else val}")
    return f"{path.stem} ({', '.join(bits)})"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--families",
        default="leather,cloth",
        help="Comma-separated folders to rewrite (default: leather,cloth).",
    )
    args = parser.parse_args()
    families = [part.strip() for part in args.families.split(",") if part.strip()]

    report: list[str] = []
    for family in families:
        report.append(f"=== {family.upper()} ===")
        folder = ROOT / family
        for path in sorted(folder.glob("*.tres")):
            if path.stem in SKIP_NAMES:
                continue
            text = path.read_text(encoding="utf-8")
            name = parse_name(text)
            if not name:
                continue
            mastery = parse_mastery(text)
            if mastery <= 0:
                mastery = 8 if "silver" in name.lower() else 1
            piece = piece_key(text, name)
            mods = target_mods(family, mastery, piece, name)
            report.append(f"m{mastery:>2} {rewrite(path, mods)}")

    print("\n".join(report))
    print("\n=== STYLE CHECK (chest, live files) ===")
    for mastery, metal, leather, cloth in COMPARE_CHESTS:
        print(f"m{mastery}")
        print(f"  metal   {fmt_piece(metal)}")
        print(f"  leather {fmt_piece(leather)}")
        print(f"  cloth   {fmt_piece(cloth)}")
    print("Bronze set ~22 armor / 40 HP (27% DR). Basilisk ~140 armor (61% DR).")


if __name__ == "__main__":
    main()
