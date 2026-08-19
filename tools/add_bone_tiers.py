#!/usr/bin/env python3
"""Add Big Bones / Dragon Bones drops to enemies that should carry them.

Prayer needs a bone LADDER or it trains at one flat rate to 99. Plain bones
already drop from nearly everything; this adds the two higher tiers by health
band, as a text edit on the enemy .tres files (the same way the repo does every
other bulk content pass — see add_biome_stairs.gd).

Additive and idempotent: an enemy that already carries the drop is skipped, and
nothing existing is rewritten. Re-running changes nothing.

Usage:  python3 tools/add_bone_tiers.py [--apply]
        Without --apply it only reports what it WOULD touch.
"""

from __future__ import annotations

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TYPES = os.path.join(ROOT, "source", "common", "gameplay", "characters", "npc", "types")

BIG = {
    "path": "res://source/common/gameplay/items/materials/big_bones.tres",
    "ext_id": "loot_big_bones",
    "sub_id": "Drop_big_bones",
    "min": 1, "max": 1, "chance": "0.35",
}
DRAGON = {
    "path": "res://source/common/gameplay/items/materials/dragon_bones.tres",
    "ext_id": "loot_dragon_bones",
    "sub_id": "Drop_dragon_bones",
    "min": 1, "max": 2, "chance": "1.0",
}

# Health bands. Big Bones on anything meaningfully tougher than a starter mob;
# Dragon Bones only on the genuine bosses, guaranteed so a boss kill is always
# worth the walk to the altar.
BIG_MIN, BIG_MAX = 900.0, 11999.0
DRAGON_MIN = 12000.0


def _health(text: str) -> float | None:
    m = re.search(r"^max_health = ([0-9.]+)", text, re.M)
    return float(m.group(1)) if m else None


def _loot_script_id(text: str) -> str | None:
    """The ext_resource id this file uses for loot_drop.gd — it differs per file."""
    m = re.search(r'\[ext_resource type="Script"[^\]]*loot_drop\.gd" id="([^"]+)"\]', text)
    return m.group(1) if m else None


def _add(text: str, spec: dict) -> str | None:
    """Returns the edited text, or None when nothing needed doing."""
    if spec["path"] in text:
        return None
    loot_id = _loot_script_id(text)
    if loot_id is None:
        return None
    m = re.search(r"^loot = Array\[ExtResource\(\"[^\"]+\"\)\]\(\[(.*)\]\)$", text, re.M)
    if m is None:
        return None

    # ext_resource block: append after the last existing ext_resource line.
    ext_line = '[ext_resource type="Resource" path="%s" id="%s"]' % (
        spec["path"], spec["ext_id"]
    )
    last_ext = None
    for hit in re.finditer(r"^\[ext_resource .*\]$", text, re.M):
        last_ext = hit
    text = text[:last_ext.end()] + "\n" + ext_line + text[last_ext.end():]

    sub_block = (
        '\n[sub_resource type="Resource" id="%s"]\n'
        'script = ExtResource("%s")\n'
        'item = ExtResource("%s")\n'
        'min_amount = %d\n'
        'max_amount = %d\n'
        'chance = %s\n'
    ) % (spec["sub_id"], loot_id, spec["ext_id"], spec["min"], spec["max"], spec["chance"])
    res_at = text.index("\n[resource]")
    text = text[:res_at] + "\n" + sub_block + text[res_at:]

    m = re.search(r"^loot = Array\[ExtResource\(\"[^\"]+\"\)\]\(\[(.*)\]\)$", text, re.M)
    entries = m.group(1)
    joined = entries + ', SubResource("%s")' % spec["sub_id"] if entries.strip() \
        else 'SubResource("%s")' % spec["sub_id"]
    return text[:m.start(1)] + joined + text[m.end(1):]


def main() -> None:
    apply = "--apply" in sys.argv
    touched = 0
    for base, _dirs, files in os.walk(TYPES):
        for name in sorted(files):
            if not name.endswith(".tres"):
                continue
            path = os.path.join(base, name)
            text = io.open(path, encoding="utf-8").read()
            hp = _health(text)
            if hp is None:
                continue
            spec = None
            if BIG_MIN <= hp <= BIG_MAX:
                spec = BIG
            elif hp >= DRAGON_MIN:
                spec = DRAGON
            if spec is None:
                continue
            edited = _add(text, spec)
            if edited is None:
                continue
            touched += 1
            print("%-52s hp=%-8.0f +%s" % (name, hp, spec["sub_id"]))
            if apply:
                io.open(path, "w", encoding="utf-8", newline="").write(edited)
    print("%s %d enemy types" % ("updated" if apply else "would update", touched))


if __name__ == "__main__":
    main()
