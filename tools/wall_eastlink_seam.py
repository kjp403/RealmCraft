#!/usr/bin/env python3
"""Add-only: wall the boundary row above WoodlandEastLink (tiles x=152..199,
y=99), the same treatment restore_woodland_rim_walls.py just gave EastShore.

EastLink's ground texture lacks the grass-blend gradient Cove/EastShore have
at their top edge (confirmed by direct pixel sampling), so the seam shows a
visible color mismatch. The flood-fill in restore_woodland_rim_walls.py finds
nothing to add here because there's no contiguous grass-floor tile at this
exact boundary for it to anchor to — so this adds the row directly, using the
identical tile palette and hash-based selection for visual consistency.
"""
import base64
import hashlib
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_PATH = os.path.join(
    ROOT, "source", "common", "gameplay", "maps", "maps", "woodland", "woodland_tiles.tscn"
)

SRC_WALL = 1
WALL_TILES = [(2, 6), (3, 6), (2, 7), (3, 7), (5, 2)]
Y_ROW = 99
X_RANGE = range(152, 200)


def decode(b64):
    raw = base64.b64decode(b64)
    fmt = struct.unpack_from("<H", raw, 0)[0]
    cells = {}
    for i in range((len(raw) - 2) // 12):
        x, y, sid, ax, ay, alt = struct.unpack_from("<hhhhhh", raw, 2 + i * 12)
        cells[(x, y)] = (sid, ax, ay, alt)
    return fmt, cells


def encode(fmt, cells):
    out = bytearray(struct.pack("<H", fmt))
    for (x, y) in sorted(cells, key=lambda c: (c[1], c[0])):
        sid, ax, ay, alt = cells[(x, y)]
        out += struct.pack("<hhhhhh", x, y, sid, ax, ay, alt)
    return base64.b64encode(bytes(out)).decode("ascii")


def layer_re(name):
    return (
        r'(\[node name="%s" type="TileMapLayer"[^\]]*\]\n(?:(?!\[node)[\s\S])*?'
        r'tile_map_data = PackedByteArray\(")([^"]*)("\))'
    ) % re.escape(name)


def pick_wall(x, y):
    h = hashlib.md5(("%d:%d:rimwall" % (x, y)).encode()).digest()
    ax, ay = WALL_TILES[h[0] % len(WALL_TILES)]
    return (SRC_WALL, ax, ay, 0)


def main():
    apply_ = "--apply" in sys.argv
    text = open(MAP_PATH, encoding="utf-8").read()
    wm = re.search(layer_re("Walls"), text)
    if not wm:
        print("missing Walls layer")
        return 1
    wfmt, walls = decode(wm.group(2))

    to_add = [(x, Y_ROW) for x in X_RANGE if (x, Y_ROW) not in walls]
    print("candidates:", len(to_add), to_add[:5], "...", to_add[-3:] if to_add else [])
    if not apply_:
        print("dry-run (pass --apply to write)")
        return 0

    before = len(walls)
    for c in to_add:
        walls[c] = pick_wall(c[0], c[1])
    text = text[: wm.start(2)] + encode(wfmt, walls) + text[wm.end(2):]
    open(MAP_PATH, "w", encoding="utf-8", newline="\n").write(text)
    print("wrote walls", before, "->", len(walls), "added", len(walls) - before)
    return 0


if __name__ == "__main__":
    sys.exit(main())
