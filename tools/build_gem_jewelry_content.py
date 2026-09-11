#!/usr/bin/env python3
"""Author the SETTING half of the Crafting gem line.

build_gem_crafting_content.py shipped the first half: mine an uncut gem, cut it
at the Workbench. This is the second: set the cut stone into a piece of
Smithing-made jewellery, so the two skills chain rather than compete.

WHAT THIS MAKES
---------------
  * 1 Gold Amulet base -- Smithing, anvil, 3 gold bars, level 15. Silver had an
    amulet and gold did not, which left four of the 24 pieces with nothing to
    be set into.
  * 24 gem jewellery pieces: {sapphire, emerald, ruby, diamond}
    x {silver, gold} x {ring, necklace, amulet}. Art already exists
    (tools/build_gem_jewelry_icons.py), keyed by the slug each item takes here.
  * 24 setting recipes at the Workbench: base piece + cut gem -> gem piece.
  * base jewellery vendor values halved (see VENDOR below).
  * skill guide entries: the Gold Amulet in smithing.tres, and the 4 cuts plus
    24 settings in outfitting.tres (the cuts shipped without guide entries).

XP (Kyle, 2026-09-10)
---------------------
Setting pays 60 / 105 / 165 / 270 into silver and 90 / 158 / 248 / 405 into
gold -- gold pays 1.5x, the ratio Smithing already uses for its gold pieces --
and unlocks five levels after the cut; cutting pays 27 / 45 / 69 / 105. Cut +
set is two actions per gem at the 2s craft interval, so 99 setting into gold
is ~29.2h and ~26,300 gems. Ring, necklace and amulet pay the same; the metal
is what changes the XP.

The Gold Amulet's 184 xp is the anvil's own silver amulet:necklace ratio
(117:91) applied to the gold necklace's 143. There is no generator behind the
anvil jewellery numbers to follow, so the ratio in the data is the rule.

Usage:  python tools/build_gem_jewelry_content.py [--check]

After running:
    godot --headless --path . -s tools/update_items_index.gd
    godot --headless --path . -s tools/verify_gem_jewelry.gd
"""

from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from build_gem_crafting_content import uid_for  # noqa: E402

RES = "res://source/common/gameplay"
JEWELRY_DIR = os.path.join(ROOT, "source", "common", "gameplay", "items",
                           "gears", "jewelry")
JEWELRY_RES = f"{RES}/items/gears/jewelry"
GEM_RES = f"{RES}/items/materials/gems"
WORKBENCH = os.path.join(ROOT, "source", "common", "gameplay", "crafting",
                         "resources", "workbench.tres")
ANVIL = os.path.join(ROOT, "source", "common", "gameplay", "crafting",
                     "resources", "anvil.tres")
JOB_DIR = os.path.join(ROOT, "source", "common", "gameplay", "jobs")

ICON = "res://assets/sprites/items/icons"
MOD_SCRIPT = f"{RES}/combat/attributes/stat_modifier.gd"
GEAR_SCRIPT = f"{RES}/items/gear_item.gd"
# Necklaces and amulets share the amulet slot -- gold_necklace.tres already
# equips there -- so a player wears one or the other, never both.
SLOT = {
    "ring": f"{RES}/items/item_slot/slots/ring.tres",
    "necklace": f"{RES}/items/item_slot/slots/amulet.tres",
    "amulet": f"{RES}/items/item_slot/slots/amulet.tres",
}

# (cut gem slug, cut level -- shipped in #439, set level, silver set xp,
#  gold set xp -- gold pays 1.5x silver, the ratio Smithing already uses)
GEMS = [
    ("sapphire", 1, 5, 60, 90),
    ("emerald", 27, 32, 105, 158),
    ("ruby", 43, 48, 165, 248),
    ("diamond", 60, 65, 270, 405),
]
METALS = ("silver", "gold")
PIECES = ("ring", "necklace", "amulet")

GOLD_AMULET_LEVEL = 15
GOLD_AMULET_XP = 184
GOLD_AMULET_BARS = 3

# ---------------------------------------------------------------------------
# STATS (Kyle, 2026-09-10)
# ---------------------------------------------------------------------------
# Base piece stats as ResourceLoader reads them -- never parse these from the
# .tres text: StatModifier defaults to health_max, so Godot elides that line
# on re-save and a text parse reads every HP modifier as absent.
BASE_STATS = {
    "silver_ring": [("health_max", 10)],
    "silver_necklace": [("armor", 4), ("health_max", 8)],
    "silver_amulet": [("mr", 5), ("mana_max", 10)],
    "gold_ring": [("health_max", 16)],
    "gold_necklace": [("armor", 6), ("health_max", 14), ("mana_max", 10)],
    # New. 1.6x the silver amulet: silver -> gold ring (10 -> 16) is the one
    # single-stat metal pair in the data.
    "gold_amulet": [("mr", 8), ("mana_max", 16)],
}

# A gem keeps the base piece's stats and adds ONE of its own, matched by colour
# to the Slayer gem that already stands for that stat (hues from
# build_gem_icons.py): ruby 0.955 ~ vital 0.985, emerald 0.352 ~ agile 0.270,
# sapphire 0.662 ~ focus 0.558. Diamond is colourless and takes guard, the one
# left. Those are the Slayer rings' four stats, so each has a known ceiling.
GEM_STAT = {"ruby": "health_max", "emerald": "move_speed",
            "sapphire": "mana_max", "diamond": "armor"}
# The best piece, a gold amulet, equals the Slayer SILVER ring for its stat,
# so jewellery made by the thousand never reaches the Slayer GOLD ring
# (32 / 8 / 42 / 12) bought with points. Deliberately not scaled by gem tier.
GEM_ANCHOR = {"health_max": 22, "move_speed": 6, "mana_max": 28, "armor": 7}
METAL_SCALE = {"silver": 0.6, "gold": 1.0}
PIECE_SCALE = {"ring": 0.5, "necklace": 0.75, "amulet": 1.0}

# ---------------------------------------------------------------------------
# VENDOR (Kyle, 2026-09-10)
# ---------------------------------------------------------------------------
# Jewellery is the selling point, not the bar. Silver and gold bars sold for
# 150 / 300 -- 19x and 25x their single ore, above runite's 100 -- so they are
# repriced to 16 / 24, the 2x-ore markup iron and adamant already use. Plain
# pieces sell at half their old bar-derived price, and a gem piece at that OLD
# price plus half the cut stone, so every piece is worth well over its bars
# and setting a stone adds value on top.
OLD_BASE_VENDOR = {"silver_ring": 150, "silver_necklace": 300,
                   "silver_amulet": 450, "gold_ring": 300,
                   "gold_necklace": 600,
                   # never shipped at this price; 2x silver, like ring and necklace
                   "gold_amulet": 900}
CUT_VENDOR = {"sapphire": 40, "emerald": 75, "ruby": 135, "diamond": 240}
# bar slug -> (old vendor, new vendor). Keyed on the old value so a re-run can
# never reprice twice. This also lowers what the 12 gold chests and the
# Necromancer's bar drops are worth at a vendor -- intended.
BAR_VENDOR = {"silver_bar": (150, 16), "gold_bar": (300, 24)}
BAR_DIR = os.path.join(ROOT, "source", "common", "gameplay", "items",
                       "materials", "metals")


def slug_for(gem: str, metal: str, piece: str) -> str:
    """The slug build_gem_jewelry_icons.py already keyed its art by."""
    return f"{gem}_{metal}_{piece}"


def display_for(gem: str, metal: str, piece: str) -> str:
    return f"{gem.capitalize()} {metal.capitalize()} {piece.capitalize()}"


def gem_bonus(gem: str, metal: str, piece: str) -> int:
    # Python's round() (half-to-even) is what produced the table Kyle signed
    # off -- gold necklace move speed 4.5 -> 4 -- so do not swap it.
    return max(1, round(GEM_ANCHOR[GEM_STAT[gem]] * METAL_SCALE[metal]
                        * PIECE_SCALE[piece]))


def piece_mods(gem: str, metal: str, piece: str) -> list[tuple[str, float]]:
    """Base stats, with the gem's stat added -- merged into the base's own
    modifier when the base already carries that stat, never a second one."""
    stat, add = GEM_STAT[gem], gem_bonus(gem, metal, piece)
    mods = [[s, v] for s, v in BASE_STATS[f"{metal}_{piece}"]]
    for mod in mods:
        if mod[0] == stat:
            mod[1] += add
            break
    else:
        mods.append([stat, add])
    return [(s, v) for s, v in mods]


def piece_vendor(gem: str, metal: str, piece: str) -> int:
    return OLD_BASE_VENDOR[f"{metal}_{piece}"] + CUT_VENDOR[gem] // 2


def gear_tres(slug: str, name: str, desc: str, icon: str, slot: str,
              mods: list[tuple[str, float]], vendor: int) -> str:
    # stat_name is written explicitly, but update_items_index.gd re-saves the
    # file and Godot then drops it for health_max (the default) -- a stamped
    # piece with no stat_name line is HP, not a statless modifier.
    subs = "\n".join(
        f'[sub_resource type="Resource" id="Mod_{i}"]\n'
        'script = ExtResource("1_mod")\n'
        f'stat_name = "{stat}"\n'
        f'value = {float(value)}\n'
        for i, (stat, value) in enumerate(mods))
    refs = ", ".join(f'SubResource("Mod_{i}")' for i in range(len(mods)))
    return f'''[gd_resource type="Resource" script_class="GearItem" format=3 uid="{uid_for(slug)}"]

[ext_resource type="Script" path="{MOD_SCRIPT}" id="1_mod"]
[ext_resource type="Texture2D" path="{ICON}/{icon}" id="2_icon"]
[ext_resource type="Script" path="{GEAR_SCRIPT}" id="3_gear"]
[ext_resource type="Resource" path="{slot}" id="4_slot"]

{subs}
[resource]
script = ExtResource("3_gear")
slot = ExtResource("4_slot")
base_modifiers = Array[ExtResource("1_mod")]([{refs}])
item_name = &"{name}"
item_icon = ExtResource("2_icon")
description = "{desc}"
can_trade = true
vendor_value = {vendor}
stack_limit = 10
metadata/slug = &"{slug}"
'''


def write_items(dry: bool) -> int:
    made = 0
    targets: list[tuple[str, str]] = [("gold_amulet", gear_tres(
        "gold_amulet", "Gold Amulet",
        "A heavy gold pendant. Set a cut gem into it at a workbench.",
        "jewelry_gold_amulet.png", SLOT["amulet"], BASE_STATS["gold_amulet"],
        OLD_BASE_VENDOR["gold_amulet"] // 2))]

    for gem, _cut_lvl, _set_lvl, _silver_xp, _gold_xp in GEMS:
        for metal in METALS:
            for piece in PIECES:
                slug = slug_for(gem, metal, piece)
                targets.append((slug, gear_tres(
                    slug, display_for(gem, metal, piece),
                    f"A {metal} {piece} set with a cut {gem}.",
                    f"jewelry_{slug}.png", SLOT[piece],
                    piece_mods(gem, metal, piece),
                    piece_vendor(gem, metal, piece))))

    for slug, text in targets:
        path = os.path.join(JEWELRY_DIR, f"{slug}.tres")
        if os.path.exists(path):
            continue                      # never clobber a stamped id
        made += 1
        if not dry:
            open(path, "w", encoding="utf-8", newline="\n").write(text)
    return made


def _reprice(path: str, slug: str, old: int, new: int, dry: bool) -> bool:
    """One-line vendor_value edit, keyed on the OLD value so a re-run can never
    apply twice: a file already at the new price is skipped, and anything else
    stops the run rather than guessing."""
    body = open(path, encoding="utf-8").read()
    if re.search(rf"^vendor_value = {new}$", body, re.M):
        return False
    body, n = re.subn(rf"^vendor_value = {old}$", f"vendor_value = {new}",
                      body, flags=re.M)
    if n != 1:
        sys.exit(f"  ! {slug}: vendor_value is neither {old} nor {new}")
    if not dry:
        open(path, "w", encoding="utf-8", newline="\n").write(body)
    return True


def halve_base_vendor(dry: bool) -> int:
    """Halve the plain jewellery bases, and reprice silver/gold bars to 2x ore."""
    touched = 0
    for slug, old in OLD_BASE_VENDOR.items():
        if slug == "gold_amulet":
            continue                      # written at half by write_items
        if _reprice(os.path.join(JEWELRY_DIR, f"{slug}.tres"), slug,
                    old, old // 2, dry):
            touched += 1
    bars = 0
    for slug, (old, new) in BAR_VENDOR.items():
        if _reprice(os.path.join(BAR_DIR, f"{slug}.tres"), slug, old, new, dry):
            bars += 1
    print(f"bars repriced        {bars}")
    return touched


def insert_blocks(body: str, ext_lines: list[str], sub_blocks: list[str]) -> str:
    """Every [ext_resource] must precede the first [sub_resource], and every
    [sub_resource] must precede [resource]; out of order parses as garbage
    rather than erroring."""
    if ext_lines:
        first_sub = body.find("[sub_resource")
        res_at = body.index("[resource]")
        ext_at = first_sub if 0 <= first_sub < res_at else res_at
        body = body[:ext_at] + "\n".join(ext_lines) + "\n\n" + body[ext_at:]
    if sub_blocks:
        res_at = body.index("[resource]")
        body = body[:res_at] + "\n".join(sub_blocks) + "\n" + body[res_at:]
    return body


def _require_free_ids(body: str, ids: list[str], where: str) -> None:
    for eid in ids:
        if f'id="{eid}"' in body:
            sys.exit(f"  ! {where}: id {eid} is already taken")


def wire_anvil(dry: bool) -> bool:
    """Gold Amulet at the anvil, placed right after the Gold Ring."""
    body = open(ANVIL, encoding="utf-8").read()
    if "R_au_amu" in body:
        return False
    _require_free_ids(body, ["45_au_amu", "I_au_amu"], "anvil")
    if 'id="14_au_bar"' not in body:
        sys.exit("  ! anvil: gold bar ext_resource 14_au_bar not found")

    ext = [f'[ext_resource type="Resource" path="{JEWELRY_RES}/gold_amulet.tres" '
           'id="45_au_amu"]']
    subs = [
        '[sub_resource type="Resource" id="I_au_amu"]\n'
        'script = ExtResource("3_ingred")\n'
        'item = ExtResource("14_au_bar")\n'
        f'amount = {GOLD_AMULET_BARS}\n',
        '[sub_resource type="Resource" id="R_au_amu"]\n'
        'script = ExtResource("1_recipe")\n'
        'output_item = ExtResource("45_au_amu")\n'
        'ingredients = Array[ExtResource("3_ingred")]([SubResource("I_au_amu")])\n'
        f'required_level = {GOLD_AMULET_LEVEL}\n'
        f'xp_reward = {GOLD_AMULET_XP}\n',
    ]
    body = insert_blocks(body, ext, subs)
    body, n = re.subn(
        r'(\nrecipes = Array\[ExtResource\("1_recipe"\)\]\(\[[^\n]*?)'
        r'SubResource\("R_au_ring"\)',
        r'\1SubResource("R_au_ring"), SubResource("R_au_amu")', body, count=1)
    if n == 0:
        sys.exit("  ! anvil: R_au_ring not found in the recipes array")
    if not dry:
        open(ANVIL, "w", encoding="utf-8", newline="\n").write(body)
    return True


def wire_setting_recipes(dry: bool) -> int:
    """Base piece + cut gem -> gem piece, at the Workbench.

    The Workbench is already an `outfitting` station, so these carry no
    profession_override: the station's own profession is the one to pay.
    Recipes sit right after the four cuts so the loop reads in order.
    """
    body = open(WORKBENCH, encoding="utf-8").read()
    if "R_set_" in body:
        return 0
    if 'SubResource("R_cut_diamond")' not in body:
        sys.exit("  ! workbench: cut recipes missing -- run "
                 "build_gem_crafting_content.py first")

    ext: list[str] = []
    subs: list[str] = []
    refs: list[str] = []
    for metal in METALS:
        for piece in PIECES:
            eid = f"base_{metal}_{piece}"
            _require_free_ids(body, [eid], "workbench")
            ext.append(f'[ext_resource type="Resource" '
                       f'path="{JEWELRY_RES}/{metal}_{piece}.tres" id="{eid}"]')
    for gem, _cut_lvl, set_lvl, silver_xp, gold_xp in GEMS:
        if f'id="gem_{gem}"' not in body:
            sys.exit(f"  ! workbench: cut gem ext_resource gem_{gem} not found")
        for metal in METALS:
            for piece in PIECES:
                slug = slug_for(gem, metal, piece)
                _require_free_ids(body, [f"set_{slug}"], "workbench")
                ext.append(f'[ext_resource type="Resource" '
                           f'path="{JEWELRY_RES}/{slug}.tres" id="set_{slug}"]')
                subs.append(
                    f'[sub_resource type="Resource" id="I_set_{slug}_base"]\n'
                    'script = ExtResource("3_ingred")\n'
                    f'item = ExtResource("base_{metal}_{piece}")\n')
                subs.append(
                    f'[sub_resource type="Resource" id="I_set_{slug}_gem"]\n'
                    'script = ExtResource("3_ingred")\n'
                    f'item = ExtResource("gem_{gem}")\n')
                subs.append(
                    f'[sub_resource type="Resource" id="R_set_{slug}"]\n'
                    'script = ExtResource("1_recipe")\n'
                    f'output_item = ExtResource("set_{slug}")\n'
                    'ingredients = Array[ExtResource("3_ingred")]('
                    f'[SubResource("I_set_{slug}_base"), '
                    f'SubResource("I_set_{slug}_gem")])\n'
                    f'required_level = {set_lvl}\n'
                    f'xp_reward = {gold_xp if metal == "gold" else silver_xp}\n')
                refs.append(f'SubResource("R_set_{slug}")')

    body = insert_blocks(body, ext, subs)
    body, n = re.subn(r'SubResource\("R_cut_diamond"\)(?=[,\]])',
                      'SubResource("R_cut_diamond"), ' + ", ".join(refs),
                      body, count=1)
    if n == 0:
        sys.exit("  ! workbench: R_cut_diamond not found in the recipes array")
    if not dry:
        open(WORKBENCH, "w", encoding="utf-8", newline="\n").write(body)
    return len(refs)


def wire_guide(job: str, entries: list[tuple[str, str, int, str | None]],
               dry: bool) -> int:
    """Add (ext id, res path, level, anchor ext id) rows to a job's skill guide.

    recipe_items and recipe_levels are POSITIONAL: a length drift does not
    error, it mislabels every recipe after the insertion point. Both lists
    are edited together here and asserted equal before writing.

    With an anchor the row goes straight after it; without one it goes after
    the last row at or below its level, which keeps a level-sorted guide
    sorted (outfitting is; smithing is not, so its row is anchored).
    """
    path = os.path.join(JOB_DIR, f"{job}.tres")
    body = open(path, encoding="utf-8").read()
    m_items = re.search(r'(recipe_items = Array\[ExtResource\("[^"]+"\)\]\(\[)'
                        r'(.*?)(\]\))', body, re.S)
    m_lvls = re.search(r'(recipe_levels = Array\[int\]\(\[)(.*?)(\]\))',
                       body, re.S)
    if m_items is None or m_lvls is None:
        sys.exit(f"  ! {job}: recipe_items / recipe_levels not found")
    items = [s.strip() for s in m_items.group(2).split(",") if s.strip()]
    levels = [int(s) for s in m_lvls.group(2).split(",") if s.strip()]
    if len(items) != len(levels):
        sys.exit(f"  ! {job}: guide already out of step "
                 f"({len(items)} items, {len(levels)} levels)")

    ext: list[str] = []
    for eid, res_path, level, anchor in entries:
        if f'path="{res_path}"' in body:
            continue                      # already listed
        _require_free_ids(body, [eid], job)
        ext.append(f'[ext_resource type="Resource" path="{res_path}" id="{eid}"]')
        if anchor is not None:
            at = items.index(f'ExtResource("{anchor}")') + 1
        else:
            at = max((i + 1 for i, lv in enumerate(levels) if lv <= level),
                     default=0)
        items.insert(at, f'ExtResource("{eid}")')
        levels.insert(at, level)
    if not ext:
        return 0
    assert len(items) == len(levels)

    body = (body[:m_items.start(2)] + ", ".join(items)
            + body[m_items.end(2):])
    m_lvls = re.search(r'(recipe_levels = Array\[int\]\(\[)(.*?)(\]\))',
                       body, re.S)
    body = (body[:m_lvls.start(2)] + ", ".join(str(lv) for lv in levels)
            + body[m_lvls.end(2):])
    body = insert_blocks(body, ext, [])
    if not dry:
        open(path, "w", encoding="utf-8", newline="\n").write(body)
    return len(ext)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="report only")
    dry = ap.parse_args().check

    made = write_items(dry)
    halved = halve_base_vendor(dry)
    anvil = wire_anvil(dry)
    sets = wire_setting_recipes(dry)

    smithing_rows = wire_guide("smithing", [
        ("r_au_amu", f"{JEWELRY_RES}/gold_amulet.tres", GOLD_AMULET_LEVEL,
         "r_16"),                         # r_16 is the Gold Ring
    ], dry)
    outfitting_entries: list[tuple[str, str, int, str | None]] = []
    for gem, cut_lvl, set_lvl, _silver_xp, _gold_xp in GEMS:
        outfitting_entries.append(
            (f"cut_{gem}", f"{GEM_RES}/{gem}.tres", cut_lvl, None))
        for metal in METALS:
            for piece in PIECES:
                slug = slug_for(gem, metal, piece)
                outfitting_entries.append(
                    (f"set_{slug}", f"{JEWELRY_RES}/{slug}.tres", set_lvl, None))
    outfitting_rows = wire_guide("outfitting", outfitting_entries, dry)

    print(f"items created        {made}")
    print(f"base vendors halved  {halved}")
    print(f"gold amulet recipe   {'wired' if anvil else 'already wired'}")
    print(f"setting recipes      {sets}")
    print(f"smithing guide rows  {smithing_rows}")
    print(f"crafting guide rows  {outfitting_rows}")
    if dry:
        print("\n--check: nothing written")
    else:
        print("\nNEXT: godot --headless --path . -s tools/update_items_index.gd")
    return 0


if __name__ == "__main__":
    sys.exit(main())
