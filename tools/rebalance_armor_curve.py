#!/usr/bin/env python3
"""Raise armor piece stats so a full set actually changes fights.

Mitigation is 100/(100+armor) with a 15-armor naked baseline. Old bronze
(9 set armor) moved DR from 13% to 19%. This curve makes bronze a real kit
and keeps 40–90 plate above dragon so the ladder still climbs.
"""

from __future__ import annotations

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
}

PIECE = {
    "helmet": (0.32, 0.30),
    "chest": (0.45, 0.45),
    "boots": (0.23, 0.25),
}

# Folder identity: metal tanks physical, leather is speed/AD, cloth tanks magic.
FAMILY = {
    "metal": {"armor": 1.00, "hp": 1.00, "mr": 0.15, "ad": 1.00, "ap": 0.00, "speed": 1.00},
    "leather": {"armor": 0.55, "hp": 0.70, "mr": 0.35, "ad": 1.35, "ap": 0.00, "speed": 2.20},
    "cloth": {"armor": 0.32, "hp": 0.55, "mr": 0.95, "ad": 0.00, "ap": 1.00, "speed": 1.40},
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


def offensive(mastery: int, piece: str, family: str) -> dict[str, float]:
    """AD / AP / speed that should be visible, not flavor text."""
    m = max(1, mastery)
    if family == "metal":
        ad = 2 + m * 0.42
        if piece == "helmet":
            return {"ad": ad * 0.85}
        if piece == "chest":
            return {"ad": ad}
        return {"move_speed": 2 + m * 0.06}
    if family == "leather":
        ad = 3 + m * 0.55
        spd = 4 + m * 0.12
        if piece == "helmet":
            return {"ad": ad * 0.8, "move_speed": spd * 0.7}
        if piece == "chest":
            return {"ad": ad, "move_speed": spd * 0.85}
        return {"ad": ad * 0.7, "move_speed": spd}
    ap = 2 + m * 0.48
    mana = 12 + m * 1.6
    if piece == "helmet":
        return {"ap": ap * 0.8, "mana_max": mana * 0.7}
    if piece == "chest":
        return {"ap": ap, "mana_max": mana}
    return {"ap": ap * 0.55, "mana_max": mana * 0.6, "move_speed": 3 + m * 0.08, "ability_haste": 3 + m * 0.05}


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
    return mods


def parse_mastery(text: str) -> int:
    m = re.search(r"required_mastery_level = (\d+)", text)
    if m:
        return int(m.group(1))
    return 1


def parse_name(text: str) -> str:
    m = re.search(r'item_name = &"([^"]+)"', text)
    return m.group(1) if m else ""


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


def main() -> None:
    report: list[str] = []
    for family in ("metal", "leather", "cloth"):
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
            if mastery > 40:
                continue
            if mastery <= 0:
                mastery = 8 if "silver" in name.lower() else 1
            piece = piece_key(text, name)
            mods = target_mods(family, mastery, piece, name)
            report.append(f"m{mastery:>2} {rewrite(path, mods)}")

    print("\n".join(report))
    print("Bronze set ~22 armor / 40 HP (27% DR). Basilisk ~140 armor (61% DR).")


if __name__ == "__main__":
    main()
