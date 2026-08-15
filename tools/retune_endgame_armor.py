#!/usr/bin/env python3
"""Set mastery 45+ armour/HP/MR to sit just above Basilisk without doubling EHP.

Leaves AD/AP/haste/speed alone so unique identities survive. Run after
`git restore` of those pieces so values are not compounded.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "source/common/gameplay/items/gears"

# Full 3-piece metal set. Basilisk (m40) is 140 armour / 215 HP.
SET_ARMOR = {
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
FAMILY = {
    "metal": {"armor": 1.00, "hp": 1.00, "mr": 0.15},
    "leather": {"armor": 0.55, "hp": 0.70, "mr": 0.35},
    "cloth": {"armor": 0.32, "hp": 0.55, "mr": 0.95},
}

STAT_RE = re.compile(r'stat_name = "(armor|health_max|mr)"\nvalue = (-?[0-9.]+)')


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


def piece_key(text: str, item_name: str) -> str:
    low = item_name.lower()
    if "helmet" in low or "hood" in low or "cap" in low:
        return "helmet"
    if "boot" in low or "sandal" in low or "shoe" in low:
        return "boots"
    if "chest" in low or "vest" in low or "robe" in low or "jacket" in low or "cuirass" in low or "cloak" in low or "wrap" in low or "mantle" in low or "coat" in low:
        return "chest"
    if "helmet.tres" in text:
        return "helmet"
    if "boot.tres" in text:
        return "boots"
    return "chest"


def targets(family: str, mastery: int, piece: str) -> dict[str, int]:
    fam = FAMILY[family]
    aw, hw = PIECE[piece]
    armor = max(1, round(lerp_table(SET_ARMOR, mastery) * aw * fam["armor"]))
    hp = max(4, round(lerp_table(SET_HP, mastery) * hw * fam["hp"]))
    mr = round(lerp_table(SET_ARMOR, mastery) * aw * fam["mr"])
    out = {"armor": armor, "health_max": hp}
    if mr >= 1:
        out["mr"] = mr
    return out


def main() -> None:
    updated = 0
    for family in ("metal", "leather", "cloth"):
        for path in sorted((ROOT / family).glob("*.tres")):
            text = path.read_text(encoding="utf-8")
            m = re.search(r"required_mastery_level = (\d+)", text)
            level = int(m.group(1)) if m else 0
            if level <= 40:
                continue
            name_m = re.search(r'item_name = &"([^"]+)"', text)
            name = name_m.group(1) if name_m else path.stem
            piece = piece_key(text, name)
            want = targets(family, level, piece)

            def bump(found: re.Match) -> str:
                stat = found.group(1)
                if stat not in want:
                    return found.group(0)
                return f'stat_name = "{stat}"\nvalue = {want[stat]}.0'

            new_text, count = STAT_RE.subn(bump, text)
            if not count:
                continue
            path.write_text(new_text, encoding="utf-8")
            updated += 1
            print(f"m{level} {path.name} {want}")
    print(f"updated {updated}")


if __name__ == "__main__":
    main()
