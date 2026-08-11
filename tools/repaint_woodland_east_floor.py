#!/usr/bin/env python3
"""Repaint the Goblin Woodland east wing floor in woodland_tiles.tscn.

The east wing (tiles x >= 177) was stamped by picking a *random* tile out of
each terrain's blob set for every cell, so paths, dirt, ponds and stone paving
read as speckled noise with transparent gaps punched through them, and the
grass under them is missing. This rewrites those four terrains the way the
original west half is painted: an opaque fill in the interior, the matching
directional edge piece on the rim, and solid grass underneath everything.

Terrain layout in the shared TileSet (floor_tiles.png / water_tiles.png). Each
blob set is a 5x5 slab with a diamond hole cut out of the middle; the eight
registered ring tiles are therefore usable as ordinary convex edges:

      (cx, cy-2)  terrain above  -> south edge
      (cx, cy+2)  terrain below  -> north edge
      (cx-2, cy)  terrain left   -> east edge
      (cx+2, cy)  terrain right  -> west edge
      (cx+1, cy+1) terrain SE    -> north-west corner   (and so on)

Run: python tools/repaint_woodland_east_floor.py
Idempotent - running it twice produces the same scene.
"""

from __future__ import annotations

import base64
import hashlib
import os
import re
import struct
import sys
from collections import deque

MAP_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "source", "common", "gameplay", "maps", "maps", "woodland", "woodland_tiles.tscn",
)

EAST_X0 = 177          # first column of the east wing
LAYERS = ["Ground", "Features", "Decor", "Walls", "WallDecor"]

SRC_FLOOR = 0
SRC_VEG = 2
SRC_WATER = 8
TREE_SOURCES = (3, 4, 5, 6)

GRASS = [(SRC_FLOOR, 1, 10), (SRC_FLOOR, 2, 10), (SRC_FLOOR, 3, 10)]

# Blob sets: centre column in the atlas + the opaque fill tile.
PATH_CX, PATH_FILL = 7, (SRC_FLOOR, 6, 10)
DIRT_CX, DIRT_FILL = 12, (SRC_FLOOR, 11, 10)
WATER_CX, WATER_FILL = 2, (SRC_WATER, 2, 7)   # 2:7 registered by this script
BRICK_X0, BRICK_Y0 = 16, 1                    # 3x3 seamless paving pattern

# Sparse ground cover, same palette and density as the west half.
VEG_SPRIGS = [(0, 9), (1, 9), (2, 9), (3, 9), (0, 10), (2, 10), (3, 10), (3, 11), (4, 11)]
VEG_FLOWERS = [(3, 23), (3, 25), (5, 26), (6, 26), (7, 24), (14, 11)]
VEG_ONE_IN = 64        # ~1.5% of open grass, matching the west half


# --------------------------------------------------------------------------- io

def decode(b64: str):
    raw = base64.b64decode(b64)
    fmt = struct.unpack_from("<H", raw, 0)[0]
    cells = {}
    for i in range((len(raw) - 2) // 12):
        x, y, sid, ax, ay, alt = struct.unpack_from("<hhhhhh", raw, 2 + i * 12)
        cells[(x, y)] = (sid, ax, ay, alt)
    return fmt, cells


def encode(fmt: int, cells: dict) -> str:
    out = bytearray(struct.pack("<H", fmt))
    for (x, y) in sorted(cells, key=lambda c: (c[1], c[0])):
        sid, ax, ay, alt = cells[(x, y)]
        out += struct.pack("<hhhhhh", x, y, sid, ax, ay, alt)
    return base64.b64encode(bytes(out)).decode("ascii")


def _layer_re(name: str) -> str:
    return (r'(\[node name="%s" type="TileMapLayer"[^\]]*\]\n(?:(?!\[node)[\s\S])*?'
            r'tile_map_data = PackedByteArray\(")([^"]*)("\))') % re.escape(name)


def read_layer(text: str, name: str):
    m = re.search(_layer_re(name), text)
    if not m:
        raise KeyError("layer not found: " + name)
    return decode(m.group(2))


def write_layer(text: str, name: str, fmt: int, cells: dict) -> str:
    m = re.search(_layer_re(name), text)
    return text[:m.start(2)] + encode(fmt, cells) + text[m.end(2):]


# ---------------------------------------------------------------------- helpers

def pick(x: int, y: int, salt: str, options: list):
    h = hashlib.md5(("%d:%d:%s" % (x, y, salt)).encode()).digest()
    return options[h[0] % len(options)]


def roll(x: int, y: int, salt: str, one_in: int) -> bool:
    h = hashlib.md5(("%d:%d:%s" % (x, y, salt)).encode()).digest()
    return (h[1] | (h[2] << 8)) % one_in == 0


def ring_tile(src: int, cx: int, cy: int, open_sides: frozenset):
    """Edge piece for a patch cell whose `open_sides` face non-patch cells."""
    table = {
        frozenset(): None,                                   # interior -> fill
        frozenset({"n"}): (src, cx, cy + 2),
        frozenset({"s"}): (src, cx, cy - 2),
        frozenset({"e"}): (src, cx - 2, cy),
        frozenset({"w"}): (src, cx + 2, cy),
        frozenset({"n", "w"}): (src, cx + 1, cy + 1),
        frozenset({"n", "e"}): (src, cx - 1, cy + 1),
        frozenset({"s", "w"}): (src, cx + 1, cy - 1),
        frozenset({"s", "e"}): (src, cx - 1, cy - 1),
    }
    return table.get(open_sides, None)


def neighbours4(c):
    x, y = c
    return ((x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y))


def close_mask(mask: set, bounds) -> set:
    """Fill single-cell pinholes and drop specks, so a patch is a solid blob."""
    x0, y0, x1, y1 = bounds
    out = set(mask)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            c = (x, y)
            if c in out:
                continue
            if sum(1 for n in neighbours4(c) if n in mask) >= 3:
                out.add(c)
    return {c for c in out if any(n in out for n in neighbours4(c))}


def paint_patch(target: dict, mask: set, src: int, cx: int, cy: int, fill):
    for c in sorted(mask):
        x, y = c
        opens = set()
        if (x, y - 1) not in mask:
            opens.add("n")
        if (x, y + 1) not in mask:
            opens.add("s")
        if (x - 1, y) not in mask:
            opens.add("w")
        if (x + 1, y) not in mask:
            opens.add("e")
        tile = ring_tile(src, cx, cy, frozenset(opens)) or fill
        target[c] = (tile[0], tile[1], tile[2], 0)


# ------------------------------------------------------------------------- main

def main() -> int:
    text = open(MAP_PATH, encoding="utf-8").read()
    layers = {n: read_layer(text, n) for n in LAYERS}

    # 1. Drop the ~92k placeholder cells (source_id -1). They render nothing but
    #    stretch get_used_rect() to x=1065, far past camera_limit_right.
    dropped = 0
    for n, (fmt, cells) in layers.items():
        empty = [c for c, v in cells.items() if v[0] < 0]
        dropped += len(empty)
        for c in empty:
            del cells[c]

    ground = layers["Ground"][1]
    features = layers["Features"][1]
    decor = layers["Decor"][1]
    walls = layers["Walls"][1]

    def east(cells):
        return {c: v for c, v in cells.items() if c[0] >= EAST_X0}

    # 2. Classify what the east wing currently has on Ground.
    path_mask, dirt_mask, brick_mask, water_mask, land = set(), set(), set(), set(), set()
    for c, v in east(ground).items():
        sid, ax, ay = v[0], v[1], v[2]
        land.add(c)
        if sid == SRC_WATER:
            water_mask.add(c)
        elif sid == SRC_FLOOR:
            if ax in (1, 2, 3) and ay == 10:
                pass
            elif 5 <= ax <= 9:
                path_mask.add(c)
            elif 10 <= ax <= 14:
                dirt_mask.add(c)
            elif 16 <= ax <= 18:
                brick_mask.add(c)
    for c in east(features):
        land.add(c)
    for c in east(walls):
        land.add(c)

    xs = [c[0] for c in land]
    ys = [c[1] for c in land]
    bounds = (min(xs) - 1, min(ys) - 1, max(xs) + 1, max(ys) + 1)

    # 3. The voids enclosed by the landmass are all fully ringed by cliff tiles -
    #    they are the wing's ravines and rock pits, so they stay unpainted.
    ravines = enclosed_holes(land, bounds)

    # 4. Tidy each terrain blob, then repaint it properly. Closing the blobs also
    #    seals the gaps that were punched through the road and the beach.
    path_mask = close_mask(path_mask, bounds) - ravines
    dirt_mask = close_mask(dirt_mask, bounds) - ravines
    brick_mask = close_mask(brick_mask, bounds) - ravines
    water_mask = close_mask(water_mask, bounds) - ravines
    land |= path_mask | dirt_mask | brick_mask | water_mask
    # A cell belongs to exactly one terrain; water and dirt win over the road.
    path_mask -= water_mask | dirt_mask | brick_mask
    dirt_mask -= water_mask | brick_mask
    brick_mask -= water_mask

    # Ground: solid grass over the whole land mass, nothing else.
    for c in list(ground):
        if c[0] >= EAST_X0:
            del ground[c]
    for c in sorted(land):
        g = pick(c[0], c[1], "grass", GRASS)
        ground[c] = (g[0], g[1], g[2], 0)

    # Features: terrain patches only. Keep east vegetation by moving it to Decor,
    # which is where the west half puts ground cover.
    moved_veg = 0
    for c, v in sorted(east(features).items()):
        del features[c]
        if v[0] == SRC_VEG and c not in decor:
            decor[c] = v
            moved_veg += 1

    paint_patch(features, path_mask, SRC_FLOOR, PATH_CX, 7, PATH_FILL)
    paint_patch(features, dirt_mask, SRC_FLOOR, DIRT_CX, 7, DIRT_FILL)
    paint_patch(features, water_mask, SRC_WATER, WATER_CX, 7, WATER_FILL)
    for c in sorted(brick_mask):                     # seamless 3x3 paving pattern
        features[c] = (SRC_FLOOR, BRICK_X0 + c[0] % 3, BRICK_Y0 + c[1] % 3, 0)

    # 5. Break up the flat grass with the same sparse ground cover as the west.
    patches = path_mask | dirt_mask | brick_mask | water_mask
    blocked = patches | set(decor) | set(walls)
    scattered = 0
    for c in sorted(land):
        if c in blocked or any(n in patches for n in neighbours4(c)):
            continue
        if not roll(c[0], c[1], "veg", VEG_ONE_IN):
            continue
        palette = VEG_FLOWERS if roll(c[0], c[1], "flower", 4) else VEG_SPRIGS
        ax, ay = pick(c[0], c[1], "vegtile", palette)
        decor[c] = (SRC_VEG, ax, ay, 0)
        scattered += 1

    # 6. Register the opaque pond core (2:7). The rim tiles are walkable shallows;
    #    the core keeps the collision the old random 2:2 blockers provided.
    text = register_water_core(text)

    for n, (fmt, cells) in layers.items():
        text = write_layer(text, n, fmt, cells)
    open(MAP_PATH, "w", encoding="utf-8", newline="\n").write(text)

    print("placeholder cells dropped : %d" % dropped)
    print("land cells regrassed      : %d" % len(land))
    print("ravines left unpainted    : %d" % len(ravines))
    print("path / dirt / brick / pond: %d / %d / %d / %d"
          % (len(path_mask), len(dirt_mask), len(brick_mask), len(water_mask)))
    print("veg moved to Decor        : %d" % moved_veg)
    print("ground cover scattered    : %d" % scattered)
    return 0


def enclosed_holes(land: set, bounds) -> set:
    """Cells inside the bounding box that are not land and cannot reach outside."""
    x0, y0, x1, y1 = bounds
    outside = set()
    queue = deque()
    for x in range(x0, x1 + 1):
        for c in ((x, y0), (x, y1)):
            if c not in land and c not in outside:
                outside.add(c)
                queue.append(c)
    for y in range(y0, y1 + 1):
        for c in ((x0, y), (x1, y)):
            if c not in land and c not in outside:
                outside.add(c)
                queue.append(c)
    while queue:
        cx, cy = queue.popleft()
        for n in neighbours4((cx, cy)):
            if not (x0 <= n[0] <= x1 and y0 <= n[1] <= y1):
                continue
            if n in land or n in outside:
                continue
            outside.add(n)
            queue.append(n)
    holes = set()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            c = (x, y)
            if c not in land and c not in outside:
                holes.add(c)
    return holes


def register_water_core(text: str) -> str:
    """Add 2:7 (opaque water, blocking) to atlas_water if it is not there yet."""
    if re.search(r'^2:7/0 = 0$', text, re.M):
        return text
    marker = "2:5/0 = 0\n"
    idx = text.find(marker)
    if idx < 0:
        raise RuntimeError("atlas_water layout changed; cannot register 2:7")
    insert = ('2:7/0 = 0\n'
              '2:7/0/physics_layer_0/polygon_0/points = '
              'PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)\n')
    at = idx + len(marker)
    return text[:at] + insert + text[at:]


if __name__ == "__main__":
    sys.exit(main())
