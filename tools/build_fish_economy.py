#!/usr/bin/env python3
"""Move fish out of the ornate chests and onto the live world's kill loot.

TWO PASSES, one design change.

PASS 1 — ornate chests stop paying fish.
Every tier-3 chest (`combat/chests/gold_*.tres`, the ones RewardService hands
out for a boss kill) loses every raw-fish and cooked-fish entry on its table,
and gains 5-15 `vial_of_water` in their place. Three of the twelve actually
carried fish (`gold_blue_large`, `gold_pink_large`, `gold_red_large`: anglerfish
and turtle, 9-12 each at the default weight 1.0); the vial goes on all twelve so
the tier reads the same whichever colour drops.

Note the chest `loot` array is a WEIGHTED DRAW WITHOUT REPLACEMENT — see
ChestResource.roll_and_grant. `chance` there is the relative weight of being one
of the `rolls_min..rolls_max` entries picked, NOT an independent probability. So
the vial goes in at weight 1.0, matching the ore/log bulk band the fish sat in,
and leaves the table's total weight roughly where it was. Vials are Mira's
alchemy input, so a chest full of them is a herblore feed, not a heal.

Tier 1/2 wood chests are deliberately untouched: they pay RAW fish, which is
cookable, and they are the low-level chest a starter actually opens.

PASS 2 — cooked fish becomes a per-ZONE kill drop.
Each named zone's InstanceResource gets its fish on `zone_kill_loot`, the
per-instance table RewardService._append_zone_kill_loot rolls for EVERY hostile
killed in that instance:

    Goblin Woodlands   cooked_lionfish      heal 28
    Fungus Cave        cooked_turtle        heal 40
    Bandit Hideout     cooked_parrot_fish   heal 45
    DimWood            cooked_anglerfish    heal 55
    The Sewers         cooked_anglerfish    heal 55, at 2-4 instead of 1-2
    Desert             cooked_halibut       heal 65
    Fire Forge         cooked_stingray      heal 75

That mapping is already the heal ladder in `items/consumables/food/`, so the
zone order and the food order agree without retuning a single item.

WHY zone_kill_loot AND NOT A PER-ENEMY TABLE. Enemy types are shared across
zones — `trpg_armored_orc` spawns in Fire Forge AND Woodland East,
`trpg_greatsword_skeleton` in Fire Forge, the Ossuary and the Sunken Tombs,
`trpg_slime` in the Sewers and Woodland East. Hanging a fish on the TYPE would
carry Fire Forge's stingray into the starter woodland, which is the exact thing
CONTENT_AUTHORING.md warns about. Hanging it on the INSTANCE means the same orc
pays stingray in the Forge and lionfish in the Woodlands, and any NPC placed in
the zone later inherits the drop for free.

It is not a lesser roll for being zone-wide: `_append_zone_kill_loot` uses the
same `randf() > drop.chance` test as `_roll_loot` and appends into the same
`loot_gained` array, so the fish lands as ground loot with the same beam, the
same 60s reservation and the same reward card as anything on the mob's own
table. Every kill rolls it; most kills miss.

RATE. 0.10 per kill, 1-2 fish (Sewers 2-4). Deliberately small: this is a
top-up between pulls, not a reason to farm. At 0.10 it also stays clear of
LootBeam.RATE_VALUABLE (0.05), so fish raise no beam — food should not flash
like a prize.

Sub-areas ride with their parent zone (the Gutterworks / Ossuary / Drowned
Cistern are the Sewers; the Sunken Tombs / Sunspire Terraces are the Desert;
the Bellows Gallery / Cinder Deeps are the Fire Forge). Instances the request
did not name — Mining Cave, The Hollow, Pirate's Cove, and every dungeon —
are left alone.

`woodland_east.tres` points at the orphaned `woodland_east.tscn`; the live east
wing is inside `woodland_tiles.tscn`, which is what `woodland.tres` loads. Both
are written anyway so the pair stays consistent if that scene is ever revived.

Text edit, not ResourceSaver: a headless `-s`/script save silently strips `uid=`
from the file and every ext_resource in it.

Idempotent: a fish already gone stays gone, a vial/zone entry already present is
skipped. Re-running changes nothing.

Usage:  python tools/build_fish_economy.py [--apply]
        Without --apply it only reports what it WOULD touch.

No index regeneration is needed. drop_rarity_index only scans enemy .tres loot
(not chest tables and not zone_kill_loot), and at 0.10 / weight 1.0 neither the
fish nor the vial would earn a beam tier anyway.
"""

from __future__ import annotations

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHESTS = os.path.join(ROOT, "source", "common", "gameplay", "combat", "chests")
INSTANCES = os.path.join(
    ROOT, "source", "common", "gameplay", "maps", "instance", "instance_collection"
)

GP = "res://source/common/gameplay"

# Any table entry whose item path matches one of these is fish and comes off the
# ornate chests. Covers both the raw material and the cooked consumable.
FISH_PATH_MARKERS = ("/items/materials/fish/", "/items/consumables/food/cooked_")

# item key -> (res path, uid or ""). A .tres with no uid= in its header is
# referenced by path only, the way the ring entries already are.
ITEMS: dict[str, tuple[str, str]] = {
    "vial_of_water": (GP + "/items/materials/herbs/vial_of_water.tres", ""),
    "cooked_lionfish": (GP + "/items/consumables/food/cooked_lionfish.tres", "uid://c67566de76e887"),
    "cooked_turtle": (GP + "/items/consumables/food/cooked_turtle.tres", "uid://c4ab069be0cdf7"),
    "cooked_parrot_fish": (GP + "/items/consumables/food/cooked_parrot_fish.tres", "uid://c15b2d57c00622"),
    "cooked_anglerfish": (GP + "/items/consumables/food/cooked_anglerfish.tres", "uid://c7704cedbdbb03"),
    "cooked_halibut": (GP + "/items/consumables/food/cooked_halibut.tres", ""),
    "cooked_stingray": (GP + "/items/consumables/food/cooked_stingray.tres", ""),
}

LOOT_DROP_SCRIPT = GP + "/combat/loot_drop.gd"
LOOT_DROP_UID = "uid://dyw7fn4hr7rbh"

# The vial replacing the fish on every tier-3 chest: (min, max, weight).
VIAL = (5, 15, "1.0")

# instance .tres (relative to INSTANCES) -> (item key, min, max, chance).
ZONES: dict[str, tuple[str, int, int, str]] = {
    # Goblin Woodlands. woodland.tres loads woodland_tiles.tscn (the live map,
    # east wing included); woodland_east.tres is the orphaned scene's instance.
    "biomes/woodland.tres": ("cooked_lionfish", 1, 2, "0.1"),
    "biomes/woodland_east.tres": ("cooked_lionfish", 1, 2, "0.1"),
    "biomes/fungus_cave.tres": ("cooked_turtle", 1, 2, "0.1"),
    "biomes/bandit_hideout.tres": ("cooked_parrot_fish", 1, 2, "0.1"),
    "biomes/forest.tres": ("cooked_anglerfish", 1, 2, "0.1"),
    # The Sewers: same fish as DimWood, at the higher quantity that was asked
    # for. The three sub-areas are the same zone and pay the same.
    "biomes/sewers.tres": ("cooked_anglerfish", 2, 4, "0.1"),
    "biomes/gutterworks.tres": ("cooked_anglerfish", 2, 4, "0.1"),
    "biomes/ossuary.tres": ("cooked_anglerfish", 2, 4, "0.1"),
    "biomes/drowned_cistern.tres": ("cooked_anglerfish", 2, 4, "0.1"),
    "biomes/desert.tres": ("cooked_halibut", 1, 2, "0.1"),
    "biomes/sunken_tombs.tres": ("cooked_halibut", 1, 2, "0.1"),
    "biomes/sunspire_terraces.tres": ("cooked_halibut", 1, 2, "0.1"),
    "biomes/fire_forge.tres": ("cooked_stingray", 1, 2, "0.1"),
    "biomes/bellows_gallery.tres": ("cooked_stingray", 1, 2, "0.1"),
    "biomes/cinder_deeps.tres": ("cooked_stingray", 1, 2, "0.1"),
}

LOOT_RE = re.compile(r"^loot = Array\[ExtResource\(\"[^\"]+\"\)\]\(\[(.*)\]\)$", re.M)
ZONE_RE = re.compile(r"^zone_kill_loot = Array\[ExtResource\(\"[^\"]+\"\)\]\(\[(.*)\]\)$", re.M)


# --- a .tres as a list of blocks ---------------------------------------------
# A .tres is a `[header]` line followed by its body, repeated. Editing that
# structure directly — rather than splicing with regexes that have to guess how
# many blank lines separate two blocks — is what keeps removing an entry from
# gluing the next header onto the previous line. Re-emission normalises the
# separators, so a touched file always comes back in Godot's own layout.

class Tres:
    """The blocks of one .tres in file order. Each is (header, body) with the
    blank lines between them stripped; `header` is the whole `[...]` line."""

    def __init__(self, text: str) -> None:
        self.blocks: list[list[str]] = []
        for chunk in re.split(r"(?m)^(?=\[)", text):
            if not chunk.strip():
                continue
            head, _, body = chunk.partition("\n")
            self.blocks.append([head.rstrip("\n"), body.strip("\n")])

    def __str__(self) -> str:
        out: list[str] = []
        for i, (head, body) in enumerate(self.blocks):
            out.append(head + ("\n" + body if body else ""))
            nxt: str = self.blocks[i + 1][0] if i + 1 < len(self.blocks) else ""
            # ext_resource lines sit contiguously; every other pair of blocks is
            # separated by one blank line, and the file ends with a newline.
            if nxt and not (head.startswith("[ext_resource") and nxt.startswith("[ext_resource")):
                out.append("\n")
            out.append("\n")
        return "".join(out)

    def index_of(self, prefix: str, last: bool = False) -> int:
        """Index of the first (or last) block whose header starts with prefix, or -1."""
        hits: list[int] = [i for i, b in enumerate(self.blocks) if b[0].startswith(prefix)]
        if not hits:
            return -1
        return hits[-1] if last else hits[0]

    def add_ext(self, line: str) -> None:
        """Append an ext_resource after the last one (or after the header on a
        file that somehow has none)."""
        at = self.index_of("[ext_resource", last=True)
        self.blocks.insert(at + 1 if at >= 0 else 1, [line, ""])

    def add_sub(self, header: str, body: str) -> None:
        """Insert a sub_resource just above the [resource] block."""
        self.blocks.insert(self.index_of("[resource]"), [header, body])

    def sub_body(self, sub_id: str) -> str:
        i = self.index_of('[sub_resource type="Resource" id="%s"]' % sub_id)
        return self.blocks[i][1] if i >= 0 else ""

    def drop(self, header: str) -> bool:
        i = self.index_of(header)
        if i < 0:
            return False
        del self.blocks[i]
        return True

    def resource_body(self) -> str:
        i = self.index_of("[resource]")
        return self.blocks[i][1] if i >= 0 else ""

    def set_resource_body(self, body: str) -> None:
        self.blocks[self.index_of("[resource]")][1] = body

    def uses_ext(self, ext_id: str) -> bool:
        return any('ExtResource("%s")' % ext_id in b[1] for b in self.blocks)

    def ext_id_for_path(self, path: str) -> str | None:
        for head, _ in self.blocks:
            m = re.match(r'\[ext_resource [^\]]*path="%s" id="([^"]+)"\]' % re.escape(path), head)
            if m:
                return m.group(1)
        return None

    def drop_orphan_exts(self, ext_ids: set[str]) -> None:
        """Remove ext_resource declarations in [param ext_ids] that nothing
        references any more."""
        self.blocks = [
            b for b in self.blocks
            if not (
                (m := re.match(r'\[ext_resource [^\]]*id="([^"]+)"\]', b[0])) is not None
                and m.group(1) in ext_ids
                and not self.uses_ext(m.group(1))
            )
        ]


# --- shared table surgery ----------------------------------------------------

def _loot_script_id(doc: Tres) -> str:
    """The ext_resource id this file uses for loot_drop.gd — it differs per file.
    Declares it when the file has no LootDrop yet."""
    existing = doc.ext_id_for_path(LOOT_DROP_SCRIPT)
    if existing is not None:
        return existing
    doc.add_ext('[ext_resource type="Script" uid="%s" path="%s" id="fish_loot"]'
                % (LOOT_DROP_UID, LOOT_DROP_SCRIPT))
    return "fish_loot"


def _has_drop(doc: Tres, key: str) -> bool:
    """True when this item is already an entry somewhere in the file."""
    ext_id = doc.ext_id_for_path(ITEMS[key][0])
    return ext_id is not None and doc.uses_ext(ext_id)


def _add_drop(doc: Tres, key: str, sub_id: str, lo: int, hi: int, chance: str) -> None:
    """Add the ext_resource (if new) and the LootDrop sub_resource for an item.
    The caller still has to put [param sub_id] on the array it belongs to."""
    loot_id = _loot_script_id(doc)
    path, uid = ITEMS[key]
    ext_id = doc.ext_id_for_path(path)
    if ext_id is None:
        ext_id = "fish_" + key
        doc.add_ext('[ext_resource type="Resource"%s path="%s" id="%s"]'
                    % (' uid="%s"' % uid if uid else "", path, ext_id))
    doc.add_sub(
        '[sub_resource type="Resource" id="%s"]' % sub_id,
        'script = ExtResource("%s")\nitem = ExtResource("%s")\n'
        'min_amount = %d\nmax_amount = %d\nchance = %s' % (loot_id, ext_id, lo, hi, chance),
    )


def _append_to_array(doc: Tres, array_re: re.Pattern, sub_id: str) -> bool:
    """Put SubResource(sub_id) on an existing array line in [resource]."""
    body = doc.resource_body()
    m = array_re.search(body)
    if m is None:
        return False
    entries: str = m.group(1)
    joined: str = (entries + ', SubResource("%s")' % sub_id) if entries.strip() \
        else 'SubResource("%s")' % sub_id
    doc.set_resource_body(body[:m.start(1)] + joined + body[m.end(1):])
    return True


def _retire(doc: Tres, sub_id: str, array_re: re.Pattern) -> bool:
    """Pull one entry off a table: its array ref and its sub_resource. The now
    possibly-unused ext_resource is swept afterwards by drop_orphan_exts, once
    every retirement is done. False when the entry was already gone."""
    body = doc.resource_body()
    m = array_re.search(body)
    ref: str = 'SubResource("%s")' % sub_id
    if m is None or ref not in m.group(1):
        return False
    entries: list[str] = [e for e in m.group(1).split(", ") if e != ref]
    doc.set_resource_body(body[:m.start(1)] + ", ".join(entries) + body[m.end(1):])
    return doc.drop('[sub_resource type="Resource" id="%s"]' % sub_id)


# --- pass 1: ornate chests ---------------------------------------------------

def _fish_ext_ids(doc: Tres) -> set[str]:
    """ext_resource ids in this file that point at a raw or cooked fish."""
    out: set[str] = set()
    for head, _ in doc.blocks:
        m = re.match(r'\[ext_resource [^\]]*path="([^"]+)" id="([^"]+)"\]', head)
        if m and any(marker in m.group(1) for marker in FISH_PATH_MARKERS):
            out.add(m.group(2))
    return out


def _fish_sub_ids(doc: Tres) -> list[str]:
    """LootDrop sub_resource ids on this chest whose item is a fish."""
    fish: set[str] = _fish_ext_ids(doc)
    if not fish:
        return []
    out: list[str] = []
    for head, body in doc.blocks:
        m = re.match(r'\[sub_resource type="Resource" id="([^"]+)"\]', head)
        item = re.search(r'item = ExtResource\("([^"]+)"\)', body)
        if m and item is not None and item.group(1) in fish:
            out.append(m.group(1))
    return out


def _chest_pass(apply: bool) -> int:
    touched = 0
    for name in sorted(os.listdir(CHESTS)):
        if not name.startswith("gold_") or not name.endswith(".tres"):
            continue # tier 1/2 wood chests keep their raw fish
        path = os.path.join(CHESTS, name)
        original = io.open(path, encoding="utf-8").read()
        doc = Tres(original)
        if "tier = 3" not in doc.resource_body() or LOOT_RE.search(doc.resource_body()) is None:
            print("  %-32s SKIPPED (not a tier-3 loot table)" % name)
            continue
        notes: list[str] = []
        fish_exts: set[str] = _fish_ext_ids(doc)
        for sub_id in _fish_sub_ids(doc):
            if _retire(doc, sub_id, LOOT_RE):
                notes.append("-" + sub_id)
        doc.drop_orphan_exts(fish_exts)
        if not _has_drop(doc, "vial_of_water"):
            sub_id = "Drop_fish_vial_of_water"
            _add_drop(doc, "vial_of_water", sub_id, *VIAL)
            _append_to_array(doc, LOOT_RE, sub_id)
            notes.append("+vial_of_water %d-%d" % (VIAL[0], VIAL[1]))
        text = str(doc)
        if text == original:
            print("  %-32s up to date" % name)
            continue
        touched += 1
        print("  %-32s %s" % (name, ", ".join(notes)))
        if apply:
            io.open(path, "w", encoding="utf-8", newline="").write(text)
    return touched


# --- pass 2: zone kill loot --------------------------------------------------

def _zone_pass(apply: bool) -> int:
    touched = 0
    for rel, (key, lo, hi, chance) in ZONES.items():
        path = os.path.join(INSTANCES, *rel.split("/"))
        original = io.open(path, encoding="utf-8").read()
        doc = Tres(original)
        if _has_drop(doc, key):
            print("  %-32s up to date" % rel)
            continue
        sub_id = "ZoneDrop_" + key
        _add_drop(doc, key, sub_id, lo, hi, chance)
        if not _append_to_array(doc, ZONE_RE, sub_id):
            # No zone_kill_loot yet — declare it. It goes above the metadata/
            # block so [resource] keeps the exported-then-metadata order Godot
            # writes.
            body = doc.resource_body()
            line = 'zone_kill_loot = Array[ExtResource("%s")]([SubResource("%s")])\n' % (
                _loot_script_id(doc), sub_id)
            meta = re.search(r"^metadata/", body, re.M)
            at: int = meta.start() if meta is not None else len(body)
            doc.set_resource_body(body[:at] + line + body[at:])
        text = str(doc)
        if text == original:
            print("  %-32s up to date" % rel)
            continue
        touched += 1
        print("  %-32s +%s %d-%d @ %s" % (rel, key, lo, hi, chance))
        if apply:
            io.open(path, "w", encoding="utf-8", newline="").write(text)
    return touched


def main() -> None:
    apply = "--apply" in sys.argv
    print("Ornate chests (fish out, vials in):")
    chests = _chest_pass(apply)
    print("\nZone kill loot (cooked fish in):")
    zones = _zone_pass(apply)
    print("\n%s %d chest tables and %d zone instances"
          % ("updated" if apply else "would update", chests, zones))


if __name__ == "__main__":
    main()
