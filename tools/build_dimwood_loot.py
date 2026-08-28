#!/usr/bin/env python3
"""Author the DimWood Forest drop tables, with Orc Leader as the Fairy source.

Every hostile in forest.tscn (= the DimWood instance, `biomes/forest.tres`,
levels 20-25) shipped with a table that was bones and nothing else — the
beastkin literally dropped 2-5 gold. This gives each of them a real table.

MATERIAL BAND. DimWood is gated behind the sewers wardstone, so it is
post-sewers content, and the crafting ladder in `crafting/resources/workbench.tres`
puts that at level 15:

    forest hide/cloth   crafting 1    Woodland starter mobs
    cave                crafting 5    fungus / mining cave
    bandit              crafting 10   bandit hideout
    sewer               crafting 15   sewers trash
    enchanted, phantom  crafting 15   <- DimWood belongs here
    sirenic             crafting 30   Cistern Sovereign (combat 200) — too high

So the zone pays `enchanted_ore/gem/cloth` (the cloth gear line) and
`phantom_ore/gem/cloth` (the leather line), NOT forest hide/cloth, which is the
crafting-1 material Woodland wolves drop. Those six had exactly one source in
the whole game — `fungus/fungal_heart.tres` — so this also un-bottlenecks them.
Sirenic is deliberately left alone: Orc Leader is combat 70, the Cistern
Sovereign is 200.

Fungal Heart is the shape being matched throughout, including for the boss: it
pays its zone materials in stacks, the crafting-15 sets at 0.24-0.3, and all
five Spore weapon styles at 12% each.

FAIRY WEAPONS. All five styles — sword, hammer, bow, wand, tome — roll
independently at 8% on **orc_leader and nowhere else in the zone**. That is the
Spore precedent (0.12/style) discounted for Orc Leader's 480s respawn against
Fungal Heart's 90s, on a weapon two mastery tiers higher (20 vs 5). Their only
other source stays the hard-dungeon reward chest, which is daily-charge gated
and draws each style at ~0.7% per chest.

Two shared types are deliberately left on the low band: `orc_whelp` (combat 27)
and `bandit_cutpurse` (24) also spawn in Woodland East, and `bandit_sorcerer`
also spawns in the Bandit Hideout, so nothing here carries DimWood loot into a
lower zone (CONTENT_AUTHORING.md: don't hang zone rares on a reused type).

Text edit, not ResourceSaver: a headless `-s`/script save silently strips `uid=`
from the file and every ext_resource in it.

Additive and idempotent: a drop whose item is already on the table is skipped,
the beastkin's placeholder gold entry is rewritten in place, and the boss's two
crafting-1 forest entries are retired. Re-running changes nothing.

Usage:  python3 tools/build_dimwood_loot.py [--apply]
        Without --apply it only reports what it WOULD touch.

After applying, rebuild the loot-beam rarity lookup:
    godot --headless --path . -s tools/build_drop_rarity_index.gd
"""

from __future__ import annotations

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TYPES = os.path.join(ROOT, "source", "common", "gameplay", "characters", "npc", "types")

GP = "res://source/common/gameplay"

# item key -> (res path, uid or "").  Items with no uid= in their header are
# referenced by path, the same way the existing tables reference them.
ITEMS: dict[str, tuple[str, str]] = {
    "gold": (GP + "/items/currencies/gold.tres", "uid://wj3mr4iqepu7"),
    "big_bones": (GP + "/items/materials/big_bones.tres", ""),
    "cloth_bandit": (GP + "/items/materials/cloth/cloth_bandit.tres", "uid://cif36huc5qgcj"),
    # The crafting-15 sets: enchanted feeds the cloth gear line, phantom the leather.
    "enchanted_ore": (GP + "/items/materials/metals/enchanted_ore.tres", "uid://fac00b8b51c74"),
    "enchanted_gem": (GP + "/items/materials/gems/enchanted_gem.tres", "uid://f4f2a12d85e34"),
    "enchanted_cloth": (GP + "/items/materials/cloth/enchanted_cloth.tres", "uid://f51d21a5ec844"),
    "phantom_ore": (GP + "/items/materials/metals/phantom_ore.tres", "uid://a0d9d687a07d4"),
    "phantom_gem": (GP + "/items/materials/gems/phantom_gem.tres", "uid://1353f39cac7b4"),
    "phantom_cloth": (GP + "/items/materials/cloth/phantom_cloth.tres", "uid://02631491a4034"),
    "hide_bandit": (GP + "/items/materials/leather/hide_bandit.tres", "uid://bis5a66yw1pxp"),
    "leather_bandit": (GP + "/items/materials/leather/leather_bandit.tres", "uid://dtb5bin7denb7"),
    "coal_ore": (GP + "/items/materials/metals/coal_ore.tres", "uid://crp8g14r50b4m"),
    "iron_ore": (GP + "/items/materials/metals/iron_ore.tres", "uid://ddjaybrt21lpq"),
    "mithril_ore": (GP + "/items/materials/metals/mithril_ore.tres", "uid://cmithriloremat1"),
    "silver_ore": (GP + "/items/materials/metals/silver_ore.tres", "uid://ljjy35qnjuxf"),
    "steel_bar": (GP + "/items/materials/metals/steel_bar.tres", "uid://1zetmdb1keg9l"),
    "oak_log": (GP + "/items/materials/wood/oak_log.tres", "uid://coaklogmat001"),
    "maple_log": (GP + "/items/materials/wood/maple_log.tres", "uid://clogmat000003"),
    "healing_herb": (GP + "/items/materials/herbs/healing_herb.tres", "uid://d2dopgtbgmdii"),
    "moonbloom": (GP + "/items/materials/herbs/moonbloom.tres", ""),
    "sunwort": (GP + "/items/materials/herbs/sunwort.tres", ""),
    "frostpetal": (GP + "/items/materials/herbs/frostpetal.tres", ""),
    "bloodcap": (GP + "/items/materials/herbs/bloodcap.tres", ""),
    "fairy_dust": (GP + "/items/materials/herbs/fairy_dust.tres", ""),
    "minor_health_potion": (GP + "/items/consumables/minor_health_potion.tres", "uid://6m10gk0883iw"),
    "health_potion": (GP + "/items/consumables/health_potion.tres", "uid://onx5sxsctc6a"),
    "minor_mana_potion": (GP + "/items/consumables/minor_mana_potion.tres", "uid://ac0936bb83a74"),
    "mana_potion": (GP + "/items/consumables/mana_potion.tres", "uid://ckwf1ifl3but0"),
    "chest_small": (GP + "/items/chests/wood_silver_small.tres", "uid://cd3f0178c307af"),
    "chest_medium": (GP + "/items/chests/wood_silver_medium.tres", "uid://c297e7a295caee"),
    "hammer_rustic": (GP + "/items/weapons/hammer/hammer_rustic.item.tres", "uid://bob6a10f1tu10"),
    "sword_fairy": (GP + "/items/weapons/sword/sword_fairy.item.tres", "uid://noy0eoqm3hrk"),
    "hammer_fairy": (GP + "/items/weapons/hammer/hammer_fairy.item.tres", "uid://bks25povs08h8"),
    "fairy_bow": (GP + "/items/weapons/bow/fairy_bow.item.tres", "uid://ngd2rh3ckh1o"),
    "wand_fairy": (GP + "/items/weapons/wand/wand_fairy.item.tres", "uid://dt6pjcxaosjlb"),
    "book_fairy": (GP + "/items/weapons/book/book_fairy.item.tres", "uid://bwxgmhvwau8kv"),
}

# One independent roll per style. Above the hard-dungeon chest's effective
# ~0.7%/style, and above LootBeam.RATE_PRIZE so a Fairy drop lights a cyan beam
# rather than the gold one reserved for 1-in-100 content.
# Fungal Heart pays all five Spore styles at 0.12 on a 90s respawn. Orc Leader
# respawns on 480s and the Fairy set is two mastery tiers up (20 vs 5), so 0.08
# per style — ~34% for at least one style per kill — makes him the clear source
# without matching a boss you can re-pull every minute and a half.
FAIRY_CHANCE = "0.08"
FAIRY_STYLES = ["sword_fairy", "hammer_fairy", "fairy_bow", "wand_fairy", "book_fairy"]

# enemy .tres (relative to TYPES) -> drops to add, as (item key, min, max, chance).
# Ordering is table order; gold first, junk last, matching the other zones.
TABLES: dict[str, list[tuple[str, int, int, str]]] = {
    # --- Bandit camp, combat 34-40. Their own bandit cloth/hide (crafting 10)
    # is already on them and stays; the crafting-15 set rides along thinly.
    "bandit.tres": [
        ("gold", 45, 110, "1.0"),
        ("hide_bandit", 1, 2, "0.45"),
        ("leather_bandit", 1, 1, "0.18"),
        ("enchanted_ore", 1, 2, "0.12"),
        ("healing_herb", 1, 1, "0.12"),
        ("minor_health_potion", 1, 1, "0.12"),
        ("chest_small", 1, 1, "0.015"),
    ],
    # Also spawns in bandit_hideout.tscn, so this stays deliberately thin.
    "bandit_sorcerer.tres": [
        ("gold", 55, 130, "1.0"),
        ("hide_bandit", 1, 2, "0.35"),
        ("silver_ore", 1, 3, "0.4"),
        ("enchanted_gem", 1, 1, "0.12"),
        ("enchanted_cloth", 1, 1, "0.1"),
        ("moonbloom", 1, 1, "0.15"),
        ("minor_mana_potion", 1, 1, "0.18"),
        ("mana_potion", 1, 1, "0.06"),
        ("chest_small", 1, 1, "0.015"),
    ],
    # --- Orc warband, combat 38-40 -----------------------------------------
    "orc.tres": [
        ("gold", 50, 120, "1.0"),
        ("enchanted_ore", 1, 2, "0.16"),
        ("enchanted_cloth", 1, 1, "0.12"),
        ("phantom_ore", 1, 2, "0.14"),
        ("coal_ore", 1, 3, "0.4"),
        ("iron_ore", 1, 2, "0.3"),
        ("oak_log", 1, 3, "0.3"),
        ("minor_health_potion", 1, 1, "0.14"),
        ("chest_small", 1, 1, "0.015"),
    ],
    "orc_rogue.tres": [
        ("gold", 60, 135, "1.0"),
        ("enchanted_ore", 1, 2, "0.16"),
        ("phantom_ore", 1, 2, "0.16"),
        ("phantom_gem", 1, 1, "0.1"),
        ("iron_ore", 1, 3, "0.38"),
        ("mithril_ore", 1, 2, "0.14"),
        ("maple_log", 1, 3, "0.28"),
        ("hammer_rustic", 1, 1, "0.03"),
        ("minor_health_potion", 1, 1, "0.14"),
        ("chest_small", 1, 1, "0.018"),
    ],
    # --- Shared with Woodland East. Combat 24 and 27, and they are the two
    # mobs a Slayer-20 character meets first, so they stay on the low band.
    "orcs/orc_whelp.tres": [
        ("oak_log", 1, 2, "0.2"),
        ("big_bones", 1, 1, "0.15"),
    ],
    "bandits/bandit_cutpurse.tres": [
        ("leather_bandit", 1, 1, "0.1"),
        ("silver_ore", 1, 2, "0.22"),
        ("minor_health_potion", 1, 1, "0.08"),
    ],
    # --- Beastkin, combat 42-58: the ones that dropped 2-5 gold. They are the
    # zone's leather-line farm, so phantom leads and enchanted rides along.
    "trpg/trpg_werewolf.tres": [
        ("phantom_ore", 1, 2, "0.18"),
        ("phantom_cloth", 1, 1, "0.14"),
        ("bloodcap", 1, 1, "0.18"),
        ("minor_health_potion", 1, 1, "0.12"),
        ("chest_small", 1, 1, "0.015"),
    ],
    "trpg/trpg_werebear.tres": [
        ("phantom_ore", 1, 3, "0.2"),
        ("phantom_cloth", 1, 2, "0.16"),
        ("phantom_gem", 1, 1, "0.1"),
        ("sunwort", 1, 1, "0.18"),
        ("minor_health_potion", 1, 1, "0.14"),
        ("chest_small", 1, 1, "0.02"),
    ],
    "trpg/trpg_werewolf_stalker.tres": [
        ("phantom_ore", 1, 3, "0.2"),
        ("phantom_gem", 1, 1, "0.14"),
        ("enchanted_cloth", 1, 1, "0.12"),
        ("moonbloom", 1, 1, "0.2"),
        ("minor_health_potion", 1, 1, "0.14"),
        ("chest_small", 1, 1, "0.02"),
    ],
    "trpg/trpg_crag_yeti.tres": [
        ("phantom_ore", 1, 3, "0.22"),
        ("phantom_cloth", 1, 2, "0.18"),
        ("enchanted_ore", 1, 2, "0.16"),
        ("coal_ore", 1, 3, "0.35"),
        ("frostpetal", 1, 1, "0.2"),
        ("health_potion", 1, 1, "0.1"),
        ("chest_medium", 1, 1, "0.015"),
    ],
    "trpg/trpg_snow_yeti.tres": [
        ("phantom_ore", 1, 3, "0.24"),
        ("phantom_gem", 1, 2, "0.16"),
        ("enchanted_gem", 1, 1, "0.14"),
        ("iron_ore", 1, 3, "0.32"),
        ("frostpetal", 1, 2, "0.24"),
        ("health_potion", 1, 1, "0.1"),
        ("chest_medium", 1, 1, "0.018"),
    ],
    "trpg/trpg_fog_giant.tres": [
        ("phantom_ore", 1, 4, "0.26"),
        ("phantom_cloth", 1, 2, "0.2"),
        ("phantom_gem", 1, 2, "0.18"),
        ("enchanted_cloth", 1, 2, "0.16"),
        ("mithril_ore", 1, 2, "0.16"),
        ("steel_bar", 1, 2, "0.12"),
        ("moonbloom", 1, 2, "0.22"),
        ("health_potion", 1, 1, "0.12"),
        ("chest_medium", 1, 1, "0.025"),
    ],
    # --- The boss. Fairy weapons live here and nowhere else in DimWood, and
    # both crafting-15 sets pay at Fungal Heart's boss rates.
    "orc_leader.tres": [
        ("enchanted_ore", 2, 5, "0.35"),
        ("enchanted_gem", 1, 3, "0.28"),
        ("enchanted_cloth", 1, 3, "0.28"),
        ("phantom_ore", 2, 5, "0.35"),
        ("phantom_gem", 1, 3, "0.28"),
        ("phantom_cloth", 1, 3, "0.28"),
    ]
    + [(k, 1, 1, FAIRY_CHANCE) for k in FAIRY_STYLES]
    + [("fairy_dust", 1, 3, "0.35")],
}

# The beastkin ship a placeholder 2-5 gold. Raise it to the zone band in place
# rather than adding a second gold entry.
GOLD_REWRITE: dict[str, tuple[int, int]] = {
    "trpg/trpg_werewolf.tres": (55, 120),
    "trpg/trpg_werebear.tres": (70, 140),
    "trpg/trpg_werewolf_stalker.tres": (75, 150),
    "trpg/trpg_crag_yeti.tres": (85, 170),
    "trpg/trpg_snow_yeti.tres": (90, 180),
    "trpg/trpg_fog_giant.tres": (110, 220),
}

# Orc Leader shipped paying Forest Cloth and Forest Hide 4-10 at 0.65-0.7 — the
# crafting-1 material a Woodland wolf drops, on a combat-70 boss behind the
# sewers wardstone. The crafting-15 sets above replace them.
RETIRE: dict[str, list[str]] = {
    "orc_leader.tres": ["Drop_cloth", "Drop_hide"],
}

LOOT_RE = re.compile(r"^loot = Array\[ExtResource\(\"[^\"]+\"\)\]\(\[(.*)\]\)$", re.M)


def _loot_script_id(text: str) -> str | None:
    """The ext_resource id this file uses for loot_drop.gd — it differs per file."""
    m = re.search(r'\[ext_resource type="Script"[^\]]*loot_drop\.gd" id="([^"]+)"\]', text)
    return m.group(1) if m else None


def _ext_id_for(text: str, key: str) -> tuple[str, str | None]:
    """Existing ext_resource id for this item, or a new id plus the line to add."""
    path, uid = ITEMS[key]
    m = re.search(r'\[ext_resource type="Resource"[^\]]*path="%s" id="([^"]+)"\]'
                  % re.escape(path), text)
    if m:
        return m.group(1), None
    ext_id = "dw_" + key
    uid_part = ' uid="%s"' % uid if uid else ""
    line = '[ext_resource type="Resource"%s path="%s" id="%s"]' % (uid_part, path, ext_id)
    return ext_id, line


def _has_drop(text: str, key: str) -> bool:
    """True when this item is already an entry on the table."""
    ext_id, line = _ext_id_for(text, key)
    if line is not None:
        return False
    return bool(re.search(r'item = ExtResource\("%s"\)' % re.escape(ext_id), text))


def _rewrite_gold(text: str, lo: int, hi: int) -> str:
    def repl(m: re.Match) -> str:
        body = m.group(2)
        body = re.sub(r"^min_amount = \d+$", "min_amount = %d" % lo, body, flags=re.M)
        body = re.sub(r"^max_amount = \d+$", "max_amount = %d" % hi, body, flags=re.M)
        body = re.sub(r"^chance = [0-9.]+$", "chance = 1.0", body, flags=re.M)
        return m.group(1) + body
    return re.sub(
        r'(\[sub_resource type="Resource" id="Drop_gold"\]\n)((?:[^\[]*\n)*?)(?=\n?\[)',
        repl, text, count=1,
    )


def _retire(text: str, sub_id: str) -> str | None:
    """Pull one existing entry off the table: its array ref, its sub_resource,
    and the ext_resource it was the only user of. None when already gone."""
    ref = 'SubResource("%s")' % sub_id
    m = LOOT_RE.search(text)
    if m is None or ref not in m.group(1):
        return None
    entries = [e for e in m.group(1).split(", ") if e != ref]
    text = text[:m.start(1)] + ", ".join(entries) + text[m.end(1):]

    block = re.search(
        r'\n\[sub_resource type="Resource" id="%s"\]\n((?:[^\[]*\n)*?)(?=\n?\[)'
        % re.escape(sub_id), text)
    ext_id = re.search(r'item = ExtResource\("([^"]+)"\)', block.group(1)).group(1)
    text = text[:block.start()] + text[block.end():]

    # Only drop the ext_resource if nothing else in the file still points at it.
    if not re.search(r'ExtResource\("%s"\)' % re.escape(ext_id), text):
        text = re.sub(r'^\[ext_resource [^\]]*id="%s"\]\n' % re.escape(ext_id),
                      "", text, flags=re.M)
    return text


def _add_drop(text: str, key: str, lo: int, hi: int, chance: str) -> str:
    loot_id = _loot_script_id(text)
    ext_id, ext_line = _ext_id_for(text, key)
    if ext_line is not None:
        last = None
        for hit in re.finditer(r"^\[ext_resource .*\]$", text, re.M):
            last = hit
        text = text[:last.end()] + "\n" + ext_line + text[last.end():]

    sub_id = "Drop_dw_" + key
    sub_block = (
        '\n[sub_resource type="Resource" id="%s"]\n'
        'script = ExtResource("%s")\n'
        'item = ExtResource("%s")\n'
        'min_amount = %d\n'
        'max_amount = %d\n'
        'chance = %s\n'
    ) % (sub_id, loot_id, ext_id, lo, hi, chance)
    res_at = text.index("\n[resource]")
    text = text[:res_at] + "\n" + sub_block + text[res_at:]

    m = LOOT_RE.search(text)
    entries = m.group(1)
    joined = (entries + ', SubResource("%s")' % sub_id) if entries.strip() \
        else 'SubResource("%s")' % sub_id
    return text[:m.start(1)] + joined + text[m.end(1):]


def main() -> None:
    apply = "--apply" in sys.argv
    touched = 0
    for rel, drops in TABLES.items():
        path = os.path.join(TYPES, *rel.split("/"))
        text = original = io.open(path, encoding="utf-8").read()
        if _loot_script_id(text) is None or LOOT_RE.search(text) is None:
            print("%-40s SKIPPED (no loot table)" % rel)
            continue
        added: list[str] = []
        for sub_id in RETIRE.get(rel, []):
            pulled = _retire(text, sub_id)
            if pulled is not None:
                text = pulled
                added.append("-" + sub_id)
        if rel in GOLD_REWRITE:
            lo, hi = GOLD_REWRITE[rel]
            if 'id="Drop_gold"' in text and "min_amount = %d" % lo not in text:
                text = _rewrite_gold(text, lo, hi)
                added.append("gold=%d-%d" % (lo, hi))
        for key, lo, hi, chance in drops:
            if _has_drop(text, key):
                continue
            text = _add_drop(text, key, lo, hi, chance)
            added.append(key)
        if text == original:
            print("%-40s up to date" % rel)
            continue
        touched += 1
        print("%-40s + %s" % (rel, ", ".join(added)))
        if apply:
            io.open(path, "w", encoding="utf-8", newline="").write(text)
    print("%s %d enemy types" % ("updated" if apply else "would update", touched))


if __name__ == "__main__":
    main()
