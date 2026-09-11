#!/usr/bin/env python3
"""Author the Crafting gem line's items and wire up where they come from.

WHAT THIS MAKES
---------------
  * 4 uncut gems + 4 cut gems (sapphire, emerald, ruby, diamond)
  * 1 Rough Geode -- a rare mining find that opens into a handful of gems
  * the ore-vein gem tables, written onto every mining node resource
  * uncut gems added to the daily skilling chest's Crafting pool
  * uncut gems added to the world chest tables that already carry ores
  * the four uncut -> cut recipes at the Workbench (Crafting XP)

THE VEIN TABLE IS CUMULATIVE, NOT FLAT (Kyle, 2026-09-08)
---------------------------------------------------------
A vein does not map to one gem. It unlocks its OWN gem and can still roll
everything below it, so the higher the vein the wider the spread and the only
place diamond appears at all:

    copper / tin              sapphire
    iron / coal               sapphire, emerald
    silver / gold             sapphire, emerald, ruby
    mithril and above         sapphire, emerald, ruby, diamond

That shape means a low-level miner has a working gem income from day one, and
a high-level one is not farming a single gem but a table where the top tier is
the rare pull. Weights below put each vein's own gem at the thin end.

WHY A GEODE
-----------
The drip is invisible: one gem every ~25 swings does not register as an event.
A geode is the same supply arriving as a MOMENT -- and because it stacks and
trades, a miner can bank a pile and sell it, which is what makes gems a market
good rather than something you burn on the spot.

Usage:  python tools/build_gem_crafting_content.py [--check]

After running, register the new items:
    godot --headless --path . -s tools/update_items_index.gd
"""

from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEM_DIR = os.path.join(ROOT, "source", "common", "gameplay", "items",
                       "materials", "gems")
NODE_DIR = os.path.join(ROOT, "source", "common", "gameplay", "maps",
                        "components", "mineable_nodes")
CHEST_DIR = os.path.join(ROOT, "source", "common", "gameplay", "combat",
                         "chests")
REWARDER = os.path.join(ROOT, "source", "common", "gameplay", "jobs",
                        "skilling_chest_rewarder.gd")

ICON = "res://assets/sprites/items/icons"
MATERIAL_SCRIPT = "res://source/common/gameplay/items/material_item.gd"
LOOT_SCRIPT = "res://source/common/gameplay/combat/loot_drop.gd"

# (slug, display, description, vendor_value, icon)
GEMS = [
    ("uncut_sapphire", "Uncut Sapphire",
     "A rough blue stone chipped out of a vein. Cut it at a workbench.",
     18, "gem_uncut_sapphire.png"),
    ("uncut_emerald", "Uncut Emerald",
     "A rough green stone chipped out of a vein. Cut it at a workbench.",
     34, "gem_uncut_emerald.png"),
    ("uncut_ruby", "Uncut Ruby",
     "A rough red stone chipped out of a vein. Cut it at a workbench.",
     62, "gem_uncut_ruby.png"),
    ("uncut_diamond", "Uncut Diamond",
     "A rough colourless stone chipped out of a vein. Cut it at a workbench.",
     110, "gem_uncut_diamond.png"),
    ("sapphire", "Sapphire",
     "A cut sapphire, ready to be set into silver or gold jewellery.",
     40, "gem_cut_sapphire.png"),
    ("emerald", "Emerald",
     "A cut emerald, ready to be set into silver or gold jewellery.",
     75, "gem_cut_emerald.png"),
    ("ruby", "Ruby",
     "A cut ruby, ready to be set into silver or gold jewellery.",
     135, "gem_cut_ruby.png"),
    ("diamond", "Diamond",
     "A cut diamond, ready to be set into silver or gold jewellery.",
     240, "gem_cut_diamond.png"),
    ("rough_geode", "Rough Geode",
     "A hollow stone with something rattling inside. Crack it at a workbench.",
     90, "gem_rough_geode.png"),
]

# vein slug -> [(uncut gem slug, relative weight)], plus how often ANY gem
# replaces the ore. The chance ramps with tier; the table does the rest.
SAPPHIRE, EMERALD, RUBY, DIAMOND = (
    "uncut_sapphire", "uncut_emerald", "uncut_ruby", "uncut_diamond")
T1 = [(SAPPHIRE, 1.0)]
T2 = [(SAPPHIRE, 0.78), (EMERALD, 0.22)]
T3 = [(SAPPHIRE, 0.55), (EMERALD, 0.30), (RUBY, 0.15)]
T4 = [(SAPPHIRE, 0.40), (EMERALD, 0.30), (RUBY, 0.20), (DIAMOND, 0.10)]

VEINS = {
    "copper_vein": (T1, 0.030), "tin_vein": (T1, 0.030),
    "iron_vein": (T2, 0.035), "coal_vein": (T2, 0.035),
    "silver_vein": (T3, 0.042), "gold_vein": (T3, 0.042),
    "mithril_vein": (T4, 0.050), "adamant_vein": (T4, 0.050),
    "runite_vein": (T4, 0.055), "dragon_vein": (T4, 0.055),
    "obsidian_vein": (T4, 0.060), "celestial_vein": (T4, 0.060),
    "astralite_vein": (T4, 0.065),
}

# The geode rides the same roll as the gems, as a thin slice of the top two
# vein tiers only -- it is the "moment", so it must stay rare enough to be one.
GEODE_VEINS = {"runite_vein", "dragon_vein", "obsidian_vein",
               "celestial_vein", "astralite_vein"}
GEODE_WEIGHT = 0.04


def uid_for(slug: str) -> str:
    """Deterministic, valid base-34 uid (0-8, a-y). Godot may still remint it on
    import; nothing references these by uid, the .tres point at icons by path."""
    import hashlib
    n = int(hashlib.sha256(slug.encode()).hexdigest(), 16)
    alpha = "012345678abcdefghijklmnopqrstuvwxy"
    out = ""
    for _ in range(13):
        n, r = divmod(n, len(alpha))
        out += alpha[r]
    return "uid://" + out


def gem_tres(slug: str, name: str, desc: str, value: int, icon: str) -> str:
    return f'''[gd_resource type="Resource" script_class="MaterialItem" format=3 uid="{uid_for(slug)}"]

[ext_resource type="Texture2D" path="{ICON}/{icon}" id="1_icon"]
[ext_resource type="Script" path="{MATERIAL_SCRIPT}" id="2_script"]

[resource]
script = ExtResource("2_script")
item_name = &"{name}"
item_icon = ExtResource("1_icon")
description = "{desc}"
holdable = false
can_trade = true
vendor_value = {value}
tags = PackedStringArray("gem")
stack_limit = 10
metadata/slug = &"{slug}"
'''


def write_items(dry: bool) -> int:
    made = 0
    for slug, name, desc, value, icon in GEMS:
        path = os.path.join(GEM_DIR, f"{slug}.tres")
        if os.path.exists(path):
            continue
        made += 1
        if not dry:
            open(path, "w", encoding="utf-8",
                 newline="\n").write(gem_tres(slug, name, desc, value, icon))
    return made


def _splice(body: str, ext_lines: list[str], sub_blocks: list[str],
            props: str) -> str:
    """Insert into a .tres at the three places Godot actually requires.

    Order is load-bearing here, and getting it wrong parses as garbage rather
    than erroring loudly: every `[ext_resource]` must precede the first
    `[sub_resource]`, and inside `[resource]` the `script =` line must come
    FIRST -- a property written above it is applied to a resource that has no
    script yet, and is silently dropped.
    """
    first_sub = body.find("[sub_resource")
    res_at = body.index("[resource]")
    ext_at = first_sub if 0 <= first_sub < res_at else res_at
    body = body[:ext_at] + "\n".join(ext_lines) + "\n\n" + body[ext_at:]

    res_at = body.index("[resource]")
    body = body[:res_at] + "\n".join(sub_blocks) + "\n" + body[res_at:]

    # properties go at the END of the resource block, after `script =`
    return body.rstrip("\n") + "\n" + props + "\n"


def wire_veins(dry: bool) -> int:
    """Write secondary_pool + gem_chance onto each vein resource.

    Text edit rather than ResourceSaver: a headless save strips uid= off every
    ext_resource it rewrites, which would break the vein's own ore reference.

    gem_chance, NOT secondary_chance. Four of these veins already carry a
    secondary_chance of their own for dragon scale / obsidian flux / celestial
    dust / astralite mote, so writing that key again appended a DUPLICATE that
    Godot silently resolved to the later line -- nerfing those drops ~6x, and
    then the pool shadowed them out of the game completely. Gems are an extra
    roll on a vein, never a replacement for what it already drops.
    """
    touched = 0
    for vein, (table, chance) in sorted(VEINS.items()):
        path = os.path.join(NODE_DIR, f"{vein}.tres")
        if not os.path.exists(path):
            print(f"  ! missing {vein}.tres")
            continue
        body = open(path, encoding="utf-8").read()
        if "secondary_pool" in body:
            continue                      # already wired; re-running is a no-op
        entries = list(table)
        if vein in GEODE_VEINS:
            entries = entries + [("rough_geode", GEODE_WEIGHT)]

        ext = [f'[ext_resource type="Script" path="{LOOT_SCRIPT}" id="gem_loot"]']
        subs = []
        refs = []
        for i, (gem, weight) in enumerate(entries):
            ext.append(
                '[ext_resource type="Resource" '
                'path="res://source/common/gameplay/items/materials/'
                f'gems/{gem}.tres" id="gem_{i}"]')
            subs.append(
                f'[sub_resource type="Resource" id="GemDrop_{i}"]\n'
                'script = ExtResource("gem_loot")\n'
                f'item = ExtResource("gem_{i}")\n'
                'min_amount = 1\n'
                'max_amount = 1\n'
                f'chance = {weight}\n')
            refs.append(f'SubResource("GemDrop_{i}")')

        props = (
            f"gem_chance = {chance}\n"
            'secondary_pool = Array[ExtResource("gem_loot")]([\n'
            + ",\n".join("\t" + r for r in refs)
            + "\n])")
        if not dry:
            open(path, "w", encoding="utf-8", newline="\n").write(
                _splice(body, ext, subs, props))
        touched += 1
    return touched


def wire_daily_chest(dry: bool) -> bool:
    """Uncut gems into the Crafting pool of the daily skilling chest.

    The Crafting pool is cloth and leather today, which is the whole reason the
    gem line exists: Crafting had no material a player could just go and get.
    """
    body = open(REWARDER, encoding="utf-8").read()
    if "uncut_sapphire" in body:
        return False
    m = re.search(r'(\t&"outfitting": \{\n)(.*?)(\n\t\},\n)', body, re.S)
    if m is None:
        print("  ! could not find the outfitting pool")
        return False
    block = m.group(2)
    for band, gems in (("low", '&"uncut_sapphire"'),
                       ("mid", '&"uncut_emerald"'),
                       ("high", '&"uncut_ruby", &"uncut_diamond"')):
        block = re.sub(r'("' + band + r'": \[)([^\]]*)(\])',
                       lambda mm: mm.group(1) + mm.group(2).rstrip()
                       + (", " if mm.group(2).strip() else "") + gems + mm.group(3),
                       block, count=1)
    if not dry:
        open(REWARDER, "w", encoding="utf-8", newline="\n").write(
            body[:m.start(2)] + block + body[m.end(2):])
    return True


def wire_world_chests(dry: bool) -> int:
    """Uncut gems into the chest tables that already carry ores, so a gem is a
    plausible thing to find beside the metal it would be set next to.

    Chest tiers come from the filename: wood_silver is T1, wood_gold T2, the
    ornate gold_* chests T3. `loot` is a weighted SAMPLE, not independent
    rolls, so these weights compete with the ores already in the table rather
    than adding a separate chance on top.
    """
    touched = 0
    for name in sorted(os.listdir(CHEST_DIR)):
        if not name.endswith(".tres"):
            continue
        path = os.path.join(CHEST_DIR, name)
        body = open(path, encoding="utf-8").read()
        if "uncut_" in body or "_ore.tres" not in body:
            continue
        loot_id = re.search(r'path="' + re.escape(LOOT_SCRIPT)
                            + r'"[^\]]*id="([^"]+)"', body)
        if loot_id is None:
            print(f"  ! {name}: no LootDrop script ext_resource")
            continue
        loot_id = loot_id.group(1)

        tier = 1 if name.startswith("wood_silver") else (
            2 if name.startswith("wood_gold") else 3)
        gems = {1: ["uncut_sapphire"],
                2: ["uncut_sapphire", "uncut_emerald"],
                3: ["uncut_emerald", "uncut_ruby", "uncut_diamond"]}[tier]
        weight = {1: 0.10, 2: 0.09, 3: 0.07}[tier]

        ext = []
        subs = []
        refs = []
        for i, gem in enumerate(gems):
            ext.append(
                '[ext_resource type="Resource" '
                'path="res://source/common/gameplay/items/materials/'
                f'gems/{gem}.tres" id="uncut_{i}"]')
            subs.append(
                f'[sub_resource type="Resource" id="UncutDrop_{i}"]\n'
                f'script = ExtResource("{loot_id}")\n'
                f'item = ExtResource("uncut_{i}")\n'
                'min_amount = 1\n'
                f'max_amount = {2 if tier > 1 else 1}\n'
                f'chance = {weight}\n')
            refs.append(f'SubResource("UncutDrop_{i}")')

        first_sub = body.find("[sub_resource")
        res_at = body.index("[resource]")
        ext_at = first_sub if 0 <= first_sub < res_at else res_at
        body = body[:ext_at] + "\n".join(ext) + "\n\n" + body[ext_at:]
        res_at = body.index("[resource]")
        body = body[:res_at] + "\n".join(subs) + "\n" + body[res_at:]

        patched, n = re.subn(r"(\nloot = Array\[ExtResource\(\"" + loot_id
                             + r"\"\)\]\(\[)",
                             r"\1" + ", ".join(refs) + ", ", body, count=1)
        if n == 0:
            print(f"  ! {name}: no loot array to extend")
            continue
        if not dry:
            open(path, "w", encoding="utf-8", newline="\n").write(patched)
        touched += 1
    return touched


def wire_cutting_recipes(dry: bool) -> int:
    """Uncut -> cut at the Workbench, paying Crafting XP.

    Without this the gems are dead weight: every source added above would pile
    up a material with no use. The Workbench is already an `outfitting`
    station, so these need no `profession_override` -- the station's own
    profession is the one that should be paid.

    XP is priced on the method, not on the top recipe (see the Smithing
    rescale): two Crafting actions per finished piece at the 2s craft interval,
    aiming for ~125 XP/action at the top of the ladder, which puts a full 99
    beside Smithing's 59h. The CUT is the smaller half; setting the stone into
    jewellery is the other, and is a later pass.
    """
    path = os.path.join(ROOT, "source", "common", "gameplay", "crafting",
                        "resources", "workbench.tres")
    body = open(path, encoding="utf-8").read()
    if "R_cut_sapphire" in body:
        return 0

    # (uncut, cut, required Crafting level, xp)
    ladder = [
        ("uncut_sapphire", "sapphire", 1, 18),
        ("uncut_emerald", "emerald", 27, 30),
        ("uncut_ruby", "ruby", 43, 46),
        ("uncut_diamond", "diamond", 60, 70),
    ]

    ext, subs, refs = [], [], []
    for uncut, cut, level, xp in ladder:
        for slug in (uncut, cut):
            line = ('[ext_resource type="Resource" '
                    'path="res://source/common/gameplay/items/materials/'
                    f'gems/{slug}.tres" id="gem_{slug}"]')
            if line not in ext:
                ext.append(line)
        subs.append(
            f'[sub_resource type="Resource" id="I_cut_{cut}"]\n'
            'script = ExtResource("3_ingred")\n'
            f'item = ExtResource("gem_{uncut}")\n'
            'amount = 1\n')
        subs.append(
            f'[sub_resource type="Resource" id="R_cut_{cut}"]\n'
            'script = ExtResource("1_recipe")\n'
            f'output_item = ExtResource("gem_{cut}")\n'
            'output_amount = 1\n'
            'ingredients = Array[ExtResource("3_ingred")]'
            f'([SubResource("I_cut_{cut}")])\n'
            f'required_level = {level}\n'
            f'xp_reward = {xp}\n')
        refs.append(f'SubResource("R_cut_{cut}")')

    first_sub = body.find("[sub_resource")
    res_at = body.index("[resource]")
    ext_at = first_sub if 0 <= first_sub < res_at else res_at
    body = body[:ext_at] + "\n".join(ext) + "\n\n" + body[ext_at:]
    res_at = body.index("[resource]")
    body = body[:res_at] + "\n".join(subs) + "\n" + body[res_at:]

    patched, n = re.subn(
        r'(\nrecipes = Array\[ExtResource\("1_recipe"\)\]\(\[)',
        r"\1" + ", ".join(refs) + ", ", body, count=1)
    if n == 0:
        print("  ! workbench: no recipes array to extend")
        return 0
    if not dry:
        open(path, "w", encoding="utf-8", newline="\n").write(patched)
    return len(ladder)


def wire_geode_opener(dry: bool) -> bool:
    """Turn the Rough Geode into something you can actually crack open.

    ZERO new code: [LootChestItem] is already a generic "bag item that rolls a
    [ChestResource] table", wired end to end through the `chest.open_item`
    handler and the client's chest window. A geode is exactly that, so it
    becomes one rather than growing a bespoke "crack" mechanic. A
    [CraftingRecipe] could not have done it -- its output is a fixed item, and
    the whole point of a geode is that you do not know what is inside.

    The file stays under materials/gems/ even though it is now a chest item:
    the five vein tables already reference it by that path, nothing keys off
    the folder (LootChestItem forces its own inventory tab), and moving it
    would mean rewriting those references plus the index entry's path for no
    behavioural gain.
    """
    table_path = os.path.join(CHEST_DIR, "rough_geode.tres")
    item_path = os.path.join(GEM_DIR, "rough_geode.tres")
    if not os.path.exists(item_path):
        print("  ! rough_geode.tres missing — run write_items first")
        return False
    prior = open(item_path, encoding="utf-8").read()
    if "LootChestItem" in prior:
        return False
    # The rewrite below replaces the file wholesale, so the id the index
    # has already stamped has to be carried across by hand. A literal here
    # is what collided with main's own new items once already: ids come
    # from a shared high-water mark, so this file cannot know its number
    # ahead of time -- it can only preserve the one it was given.
    stamped = re.search(r"^metadata/id = (\d+)$", prior, re.M)
    if stamped is None:
        print("  ! rough_geode.tres has no metadata/id - run "
              "update_items_index.gd first")
        return False

    # 2-4 DISTINCT entries per open (ChestResource draws without replacement),
    # 1-2 of each, so a geode is worth roughly three to six gems.
    pool = [("uncut_sapphire", 0.40), ("uncut_emerald", 0.30),
            ("uncut_ruby", 0.20), ("uncut_diamond", 0.10)]
    ext, subs, refs = [], [], []
    for i, (gem, weight) in enumerate(pool):
        ext.append('[ext_resource type="Resource" '
                   'path="res://source/common/gameplay/items/materials/'
                   f'gems/{gem}.tres" id="gem_{i}"]')
        subs.append(f'[sub_resource type="Resource" id="Drop_{i}"]\n'
                    'script = ExtResource("1_loot")\n'
                    f'item = ExtResource("gem_{i}")\n'
                    'min_amount = 1\nmax_amount = 2\n'
                    f'chance = {weight}\n')
        refs.append(f'SubResource("Drop_{i}")')

    table = (
        '[gd_resource type="Resource" script_class="ChestResource" format=3]\n\n'
        f'[ext_resource type="Script" path="{LOOT_SCRIPT}" id="1_loot"]\n'
        '[ext_resource type="Script" path="res://source/common/gameplay/combat/'
        'chest_resource.gd" id="2_chest"]\n'
        + "\n".join(ext) + "\n\n"
        + "\n".join(subs) + "\n"
        '[resource]\n'
        'script = ExtResource("2_chest")\n'
        'display_name = "Rough Geode"\n'
        'tier = 2\n'
        'rolls_min = 2\n'
        'rolls_max = 4\n'
        'gold_min = 0\n'
        'gold_max = 0\n'
        'loot = Array[ExtResource("1_loot")]([' + ", ".join(refs) + '])\n'
    )

    item = (
        '[gd_resource type="Resource" script_class="LootChestItem" format=3]\n\n'
        f'[ext_resource type="Texture2D" path="{ICON}/gem_rough_geode.png" '
        'id="1_icon"]\n'
        '[ext_resource type="Script" path="res://source/common/gameplay/items/'
        'loot_chest_item.gd" id="2_script"]\n\n'
        '[resource]\n'
        'script = ExtResource("2_script")\n'
        'chest_slug = &"rough_geode"\n'
        'item_name = &"Rough Geode"\n'
        'item_icon = ExtResource("1_icon")\n'
        'description = "A hollow stone with something rattling inside. '
        'Open it for a handful of uncut gems."\n'
        'can_trade = true\n'
        'holdable = false\n'
        'vendor_value = 90\n'
        'metadata/slug = &"rough_geode"\n'
        f'metadata/id = {stamped.group(1)}\n'
    )
    if not dry:
        open(table_path, "w", encoding="utf-8", newline="\n").write(table)
        open(item_path, "w", encoding="utf-8", newline="\n").write(item)
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="report only")
    args = ap.parse_args()
    dry = args.check

    made = write_items(dry)
    veins = wire_veins(dry)
    daily = wire_daily_chest(dry)
    chests = wire_world_chests(dry)
    cuts = wire_cutting_recipes(dry)
    geode = wire_geode_opener(dry)

    print(f"items created        {made}")
    print(f"veins wired          {veins}")
    print(f"daily chest pool     {'updated' if daily else 'already had gems'}")
    print(f"world chests wired   {chests}")
    print(f"cutting recipes      {cuts}")
    print(f"geode opener         {'wired' if geode else 'already wired'}")
    if dry:
        print("\n--check: nothing written")
    else:
        print("\nNEXT: godot --headless --path . -s tools/update_items_index.gd")
    return 0


if __name__ == "__main__":
    sys.exit(main())
