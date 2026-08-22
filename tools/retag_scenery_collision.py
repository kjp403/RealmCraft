#!/usr/bin/env python3
"""Split decorative tile collision off PhysicsLayers.WORLD onto a new SCENERY
layer, so ranged projectiles (arrow.gd's Projectile base — bow AND wand/book
bolts) stop dying on trees/props they merely graze, while player/NPC movement,
spawn placement, and blink still collide with that scenery exactly as before
(those consumers were widened to WORLD | SCENERY in physics_layers.gd,
character.tscn, boss_controller.gd, hostile_npc.gd, blink_ability.gd).

A TileSet's physics layer bitmask (collision_layer/collision_mask) is declared
ONCE per TileSet resource; individual tiles just say which polygon exists on
which physics_layer_N. Every tileset here draws walls and decoration from
DIFFERENT source textures (Props.png, Tree.png, vegetation.png, trees/*.png vs
Wall_Variations.png, wall_tiles.png, floor_tiles.png) — so classifying by the
originating texture PATH, one [sub_resource type="TileSetAtlasSource"] block at
a time, is a clean, low-risk signal: move a whole atlas source's physics_layer_0
polygons to a new physics_layer_1 (SCENERY-only) when its texture path matches
a known decoration folder/filename, and leave anything unmatched untouched
(conservative default — worst case a decoration tile keeps blocking arrows like
today; never a new movement pass-through, since physics_layer_0 stays WORLD
everywhere it isn't explicitly moved).

Pure TEXT edit — never load these through ResourceSaver/a `-s` tool run, which
silently strips uid= from the resource and every ext_resource (see
docs/uid_notes or ask Kyle: headless ResourceSaver stripping uids is a known
trap in this repo). This script only rewrites `physics_layer_0/polygon` ->
`physics_layer_1/polygon` on matched lines and appends two `physics_layer_1/...`
lines to the TileSet's own property block; nothing else in the file is touched.

Usage:  python3 tools/retag_scenery_collision.py <file> [<file> ...] [--apply]
        Without --apply it only PRINTS the classification (per atlas source:
        texture path, PASS/leave, and how many polygon lines would move).
        Handles both a standalone TileSet .tres (physics props in a trailing
        [resource] block) and an embedded TileSet SubResource inside a map
        .tscn (physics props inline after the `[sub_resource type="TileSet"]`
        header) — whichever the file contains.
"""

from __future__ import annotations

import re
import sys

# Path FOLDER segments that mark a source texture as decoration outright
# (case-insensitive) regardless of filename — e.g. .../props/rocks.png.
PASS_FOLDER_SEGMENTS = {"props", "trees", "decor", "decoration", "vegetation"}

# Filename substrings that mark decoration (case-insensitive, checked against
# the basename only so a folder like ".../Properties/tiles.png" can't match).
# Broad enough to catch "Interior_Props_01.png" / "forge_props_16.png" style
# names, narrow enough to require a real "prop"/"tree"/etc token.
PASS_BASENAME_SUBSTRINGS = [
    "props",
    "prop_",
    "vegetation",
    "decorative",
    "decoration",
]


def _basename_is_decor(basename_low: str) -> bool:
    if any(sub in basename_low for sub in PASS_BASENAME_SUBSTRINGS):
        return True
    # "tree"/"trees" as a filename TOKEN, not a substring — avoids false
    # positives like "street.png" (contains "tree" but isn't one).
    stem = re.sub(r"\.[a-z0-9]+$", "", basename_low)
    tokens = re.split(r"[^a-z0-9]+", stem)
    return "tree" in tokens or "trees" in tokens

ATLAS_SOURCE_RE = re.compile(r'^\[sub_resource type="TileSetAtlasSource" id="([^"]+)"\]')
TEXTURE_LINE_RE = re.compile(r'^texture = ExtResource\("([^"]+)"\)')
EXT_TEXTURE_RE = re.compile(
    r'^\[ext_resource type="Texture2D"(?:[^\]]*\bpath="([^"]+)")(?:[^\]]*\bid="([^"]+)")'
    r'|^\[ext_resource type="Texture2D"(?:[^\]]*\bid="([^"]+)")(?:[^\]]*\bpath="([^"]+)")'
)
SECTION_START_RE = re.compile(r"^\[(sub_resource|resource|node|gd_resource|gd_scene)\b")
PHYSICS0_MASK_RE = re.compile(r"^physics_layer_0/collision_mask\s*=")
POLY0_RE = re.compile(r"/physics_layer_0/polygon")


def classify(path: str) -> bool:
    """True = decoration (move to physics_layer_1 / SCENERY)."""
    low = path.lower()
    folders = low.split("/")[:-1]
    if any(seg in PASS_FOLDER_SEGMENTS for seg in folders):
        return True
    basename = low.rsplit("/", 1)[-1]
    return _basename_is_decor(basename)


def build_ext_texture_map(lines: list[str]) -> dict[str, str]:
    ext_map: dict[str, str] = {}
    for line in lines:
        m = EXT_TEXTURE_RE.match(line)
        if not m:
            continue
        path = m.group(1) or m.group(4)
        rid = m.group(2) or m.group(3)
        if path and rid:
            ext_map[rid] = path
    return ext_map


def process(path: str, apply: bool) -> None:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    ext_map = build_ext_texture_map(lines)

    # Find every TileSetAtlasSource block's [start, end) line range.
    starts: list[tuple[int, str]] = []
    for i, line in enumerate(lines):
        m = ATLAS_SOURCE_RE.match(line)
        if m:
            starts.append((i, m.group(1)))

    def block_end(start: int) -> int:
        for j in range(start + 1, len(lines)):
            if SECTION_START_RE.match(lines[j]):
                return j
        return len(lines)

    print(f"\n== {path} ==")
    moved_any = False
    physics_prop_line: int | None = None

    for start, source_id in starts:
        end = block_end(start)
        texture_id = None
        for k in range(start, min(start + 4, end)):
            tm = TEXTURE_LINE_RE.match(lines[k])
            if tm:
                texture_id = tm.group(1)
                break
        texture_path = ext_map.get(texture_id, "<unresolved texture ref>")
        is_decor = classify(texture_path)
        poly_lines = [k for k in range(start, end) if POLY0_RE.search(lines[k])]
        if not poly_lines:
            continue  # atlas source has no collision at all — nothing to do either way
        if is_decor:
            print(f"  PASS -> scenery : {source_id:30s} {texture_path}  ({len(poly_lines)} polygon lines)")
            moved_any = True
            if apply:
                for k in poly_lines:
                    lines[k] = lines[k].replace("/physics_layer_0/polygon", "/physics_layer_1/polygon")
        else:
            print(f"  leave (WORLD)   : {source_id:30s} {texture_path}  ({len(poly_lines)} polygon lines)")

    if not moved_any:
        print("  (nothing matched the decoration list — no changes)")
        return

    # Locate the TileSet's own property block to append physics_layer_1's
    # collision bits: either a trailing [resource] (standalone .tres) or the
    # [sub_resource type="TileSet" ...] header itself (embedded in a .tscn).
    for i, line in enumerate(lines):
        if line.startswith("[resource]") or re.match(r'^\[sub_resource type="TileSet"\b', line):
            physics_prop_line = i
            break

    if physics_prop_line is None:
        print("  WARNING: no [resource] / TileSet sub_resource header found — "
              "could not add physics_layer_1 collision bits. Nothing written.")
        return

    # Insert right after the existing physics_layer_0/collision_mask line so
    # the new layer reads next to the one it splits off; idempotent.
    already_present = any(
        line.startswith("physics_layer_1/collision_layer") for line in lines[physics_prop_line:physics_prop_line + 6]
    )
    if not already_present and apply:
        for k in range(physics_prop_line + 1, min(physics_prop_line + 6, len(lines))):
            if PHYSICS0_MASK_RE.match(lines[k]):
                lines.insert(k + 1, "physics_layer_1/collision_layer = 128\n")
                lines.insert(k + 2, "physics_layer_1/collision_mask = 0\n")
                break

    if apply:
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(lines)
        print("  WRITTEN.")
    else:
        print("  (dry run — pass --apply to write)")


def main() -> None:
    args = sys.argv[1:]
    apply = "--apply" in args
    files = [a for a in args if a != "--apply"]
    if not files:
        print(__doc__)
        sys.exit(1)
    for path in files:
        process(path, apply)


if __name__ == "__main__":
    main()
