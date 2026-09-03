#!/usr/bin/env python3
"""Plant the six high-tier Farming patches into their biome maps.

    Fire Forge            Rust-Spore Cap (70), Magma Root (78)
    The Sewers            Nightshade Bramble (74), Gloom-Spore Cap (85)
    Desert                Sun-Lit Lotus (82)
    Starfall Mining Cave  Iron-Spike Thorn (92)

Positions come from tools/high_tier_herb_spots.json, which is produced by
tools/pick_high_tier_herb_spots.tscn — that tool loads each map in Godot and
flood-fills the walkable set from the Entrance warper, so every spot here is on
ground a player can actually stand on. Do not hand-edit the JSON; re-run the
picker.

    godot --headless --path . --mode=client res://tools/pick_high_tier_herb_spots.tscn
    python tools/plant_high_tier_herbs.py
    godot --headless --path . --mode=client res://tools/verify_high_tier_patches.tscn

WHY THIS EDITS THE SCENES AS TEXT

All four maps are generator-authored — build_stub_biomes.gd writes Desert, Fire
Forge and Sewers; build_starfall_mining_cave.gd writes the cave — but every one
of them has been hand-edited since it was generated (boss pads, zone music,
region wildlife, sewer landmarks, the sludge collision fix). Adding the patches
by teaching the generators and re-running them would throw all of that away.
So this inserts node blocks into the scene text, the same discipline
tools/plant_farming_herbs.py already uses on the woodland maps.

Re-running is safe: every node and ext_resource this tool owns is removed by
name first, so a second run replaces rather than duplicates.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPOTS = ROOT / "tools" / "high_tier_herb_spots.json"
MAPS_DIR = ROOT / "source/common/gameplay/maps/maps"

MAPS = {
    "fire_forge": MAPS_DIR / "fire_forge/fire_forge.tscn",
    "sewers": MAPS_DIR / "sewers/sewers.tscn",
    "desert": MAPS_DIR / "desert/desert.tscn",
    "starfall_mining_cave": MAPS_DIR / "starfall_mining_cave/starfall_mining_cave.tscn",
}

NODE_SCENE = "res://source/common/gameplay/maps/components/mineable_node.tscn"
NODE_RES_DIR = "res://source/common/gameplay/maps/components/mineable_nodes"
CONTAINER = "MineableNodes"

# ext_resource ids this tool owns. Prefixed so removal can never take out an id
# the map's own generator wrote.
SCENE_RID = "hth_node_scn"


def herb_rid(slug: str) -> str:
    return f"hth_{slug}"


def strip_owned_nodes(text: str, prefixes: list[str]) -> str:
    """Drop every node block this tool previously wrote.

    A node block runs from its `[node ...]` header to the next `[` at column 0,
    which is how the .tscn property list is delimited.

    [prefixes] must name only nodes this tool owns. The container is passed in
    by the caller and ONLY when this tool created it — the Starfall cave's
    MineableNodes container was written by its own generator and holds every ore
    vein in the map, and removing that header would orphan all of them onto a
    parent path that no longer exists.
    """
    for prefix in prefixes:
        pattern = re.compile(
            rf'\[node name="{re.escape(prefix)}\d*"[^\]]*\]\n(?:(?!\[)[^\n]*\n)*',
            re.MULTILINE,
        )
        text, n = pattern.subn("", text)
        if n:
            print(f"    removed {n} x {prefix}")
    return text


def strip_owned_ext_resources(text: str, rids: list[str]) -> str:
    for rid in rids:
        pattern = re.compile(rf'^\[ext_resource[^\]]*id="{re.escape(rid)}"\]\n', re.M)
        text, n = pattern.subn("", text)
        if n:
            print(f"    removed ext_resource {rid}")
    return text


def add_ext_resources(text: str, slugs: list[str]) -> str:
    """Append our ext_resource lines after the last one already in the header."""
    lines = [
        f'[ext_resource type="PackedScene" path="{NODE_SCENE}" id="{SCENE_RID}"]\n'
    ]
    for slug in slugs:
        lines.append(
            f'[ext_resource type="Resource" path="{NODE_RES_DIR}/{slug}.tres" '
            f'id="{herb_rid(slug)}"]\n'
        )
    matches = list(re.finditer(r"^\[ext_resource[^\]]*\]\n", text, re.M))
    if not matches:
        raise RuntimeError("no ext_resource block to append to")
    at = matches[-1].end()
    return text[:at] + "".join(lines) + text[at:]


def node_blocks(spots: dict) -> str:
    """The container plus one node per patch.

    Appended at the END of the scene: a .tscn creates nodes in file order and a
    `parent=` only has to name a node already created, so the container declared
    immediately above its children is always valid — and appending keeps the
    diff to one contiguous hunk instead of threading through the map's own
    hand-edited sections.

    y_sort_enabled matches how every shipped gathering node is authored, so a
    patch draws behind a player standing below it rather than on top of them.
    """
    out = [f'[node name="{CONTAINER}" type="Node2D" parent="."]\ny_sort_enabled = true\n\n']
    for slug in sorted(spots):
        prefix = spots[slug]["prefix"]
        for i, (x, y) in enumerate(spots[slug]["positions"], start=1):
            out.append(
                f'[node name="{prefix}{i}" parent="{CONTAINER}" '
                f'instance=ExtResource("{SCENE_RID}")]\n'
                f"y_sort_enabled = true\n"
                f"position = Vector2({x:g}, {y:g})\n"
                f'data = ExtResource("{herb_rid(slug)}")\n\n'
            )
    return "".join(out)


def plant(key: str, path: Path, spots: dict) -> None:
    print(f"== {path.name} ==")
    text = path.read_text(encoding="utf-8")
    slugs = sorted(spots)
    prefixes = [spots[s]["prefix"] for s in slugs]

    # The Starfall cave already owns a MineableNodes container, full of the ore
    # veins its generator placed. There the patches join the container that is
    # already there; everywhere else this tool creates and owns one.
    reuse_container = f'[node name="{CONTAINER}" type="Node2D"' in text

    text = strip_owned_nodes(text, prefixes if reuse_container else prefixes + [CONTAINER])
    text = strip_owned_ext_resources(text, [SCENE_RID] + [herb_rid(s) for s in slugs])
    text = add_ext_resources(text, slugs)

    blocks = node_blocks(spots)
    if reuse_container:
        # Drop the container header we would otherwise add a second time.
        blocks = blocks.split("\n\n", 1)[1]
    if not text.endswith("\n"):
        text += "\n"
    if not text.endswith("\n\n"):
        text += "\n"
    text += blocks.rstrip("\n") + "\n"

    path.write_text(text, encoding="utf-8", newline="\n")
    total = sum(len(spots[s]["positions"]) for s in slugs)
    print(f"    planted {total} patches ({', '.join(slugs)})")


def main() -> None:
    data = json.loads(SPOTS.read_text(encoding="utf-8"))
    for key, path in MAPS.items():
        if key not in data:
            raise RuntimeError(f"{SPOTS.name} has no spots for {key}")
        plant(key, path, data[key])


if __name__ == "__main__":
    main()
