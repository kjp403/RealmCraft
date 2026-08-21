#!/usr/bin/env python3
"""Add-only outer rim walls on woodland_tiles.tscn.

Does not erase walls, ground, decor, or nodes. Skips interior holes and the
three south beach openings. Idempotent.
"""
from __future__ import annotations

import hashlib
import os
import re
import struct
import sys
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_PATH = os.path.join(
    ROOT, "source", "common", "gameplay", "maps", "maps", "woodland", "woodland_tiles.tscn"
)

SRC_WALL = 1
SRC_WATER = 8
WALL_TILES = [(2, 6), (3, 6), (2, 7), (3, 7), (5, 2)]
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))

# South beach instance bands (tile x), leave these openings unwalled.
BEACH_X = [
    (56, 108),   # WoodlandBeach
    (108, 152),  # WoodlandDeepCove
    # WoodlandEastShore is no longer its own doorway from the grass — it's
    # reached by walking the beach through Cove and the East Link, same as
    # those two. A second grass-side opening straight into it was an
    # inconsistent leftover and read as a bare, unwalled edge.
]


def decode(b64: str):
    raw = base64_decode(b64)
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
    return base64_encode(out)


def base64_decode(s: str) -> bytes:
    import base64
    return base64.b64decode(s)


def base64_encode(b: bytes) -> str:
    import base64
    return base64.b64encode(bytes(b)).decode("ascii")


def layer_re(name: str) -> str:
    return (
        r'(\[node name="%s" type="TileMapLayer"[^\]]*\]\n(?:(?!\[node)[\s\S])*?'
        r'tile_map_data = PackedByteArray\(")([^"]*)("\))'
    ) % re.escape(name)


def pick_wall(x: int, y: int):
    h = hashlib.md5(("%d:%d:rimwall" % (x, y)).encode()).digest()
    ax, ay = WALL_TILES[h[0] % len(WALL_TILES)]
    return (SRC_WALL, ax, ay, 0)


def in_beach_opening(x: int, y: int, max_ground_y: int) -> bool:
    if y < max_ground_y - 2:
        return False
    for a, b in BEACH_X:
        if a <= x <= b:
            return True
    return False


def main() -> int:
    apply = "--apply" in sys.argv
    text = open(MAP_PATH, encoding="utf-8").read()
    gm = re.search(layer_re("Ground"), text)
    wm = re.search(layer_re("Walls"), text)
    if not gm or not wm:
        print("missing Ground/Walls layer")
        return 1
    gfmt, ground = decode(gm.group(2))
    wfmt, walls = decode(wm.group(2))

    floor = {c for c, v in ground.items() if v[0] != SRC_WATER}
    water = {c for c, v in ground.items() if v[0] == SRC_WATER}
    occupied = set(floor) | set(water) | set(walls)

    xs = [c[0] for c in floor]
    ys = [c[1] for c in floor]
    minx, maxx = min(xs) - 4, max(xs) + 4
    miny, maxy = min(ys) - 4, max(ys) + 4
    max_gy = max(ys)

    west_w = sum(1 for x, y in walls if x < 177)
    east_w = sum(1 for x, y in walls if x >= 177)
    on_floor = sum(1 for c in walls if c in floor)
    print("ground", len(ground), "walls", len(walls), "west_walls", west_w, "east_walls", east_w, "walls_on_floor", on_floor)
    print("ground_rect", min(xs), min(ys), max(xs), max(ys))
    west_edge = 0
    west_edge_walled = 0
    for x, y in floor:
        if x >= 177:
            continue
        if any((x + dx, y + dy) not in floor for dx, dy in N4):
            west_edge += 1
            if (x, y) in walls:
                west_edge_walled += 1
    east_edge = 0
    east_edge_walled = 0
    for x, y in floor:
        if x < 177:
            continue
        if any((x + dx, y + dy) not in floor for dx, dy in N4):
            east_edge += 1
            if (x, y) in walls:
                east_edge_walled += 1
    print("west_edge", west_edge, "walled", west_edge_walled)
    print("east_edge", east_edge, "walled", east_edge_walled)
    for y in range(0, 3):
        row = [(x, y) for x in range(0, 177) if (x, y) in floor]
        print("west y", y, "floor", len(row), "walled", sum(1 for c in row if c in walls))
    for y in range(0, 3):
        row = [(x, y) for x in range(177, 332) if (x, y) in floor]
        print("east y", y, "floor", len(row), "walled", sum(1 for c in row if c in walls))

    # Outside flood: empty cells reachable from the bounding-box frame.
    outside = set()
    q = deque()
    for x in range(minx, maxx + 1):
        for y in (miny, maxy):
            c = (x, y)
            if c not in occupied:
                outside.add(c)
                q.append(c)
    for y in range(miny, maxy + 1):
        for x in (minx, maxx):
            c = (x, y)
            if c not in occupied:
                outside.add(c)
                q.append(c)
    while q:
        x, y = q.popleft()
        for dx, dy in N4:
            n = (x + dx, y + dy)
            if n[0] < minx or n[0] > maxx or n[1] < miny or n[1] > maxy:
                continue
            if n in occupied or n in outside:
                continue
            outside.add(n)
            q.append(n)

    # Walls live ON the outer grass cells (west style). Only the east wing is
    # missing that frame — do not touch west cells or interior walls.
    edge = []
    for c in floor:
        x, y = c
        if x < 177:
            continue
        if c in walls:
            continue
        if not any((x + dx, y + dy) in outside for dx, dy in N4):
            continue
        if in_beach_opening(x, y, max_gy):
            continue
        edge.append(c)

    west_double = sum(1 for x in range(0, 177) if (x, 1) in floor and (x, 1) in walls)
    rings = [edge]
    if west_double > 40:
        for _depth in range(2):  # west north frame is 3 tiles thick
            nxt = []
            prev = set(rings[-1])
            seen = set()
            for r in rings:
                seen.update(r)
            for x, y in prev:
                for dx, dy in N4:
                    n = (x + dx, y + dy)
                    if n not in floor or n in walls or n in seen or n[0] < 177:
                        continue
                    if in_beach_opening(n[0], n[1], max_gy):
                        continue
                    nxt.append(n)
            rings.append(sorted(set(nxt)))
    second = rings[1] if len(rings) > 1 else []
    third = rings[2] if len(rings) > 2 else []

    edge = sorted(set(edge))
    print("east_rim_add", len(edge), "second_ring", len(second), "third_ring", len(third))
    south99 = [c for c in edge if c[1] == 99]
    print("south_y99", len(south99), "xmin", south99[0][0] if south99 else None, "xmax", south99[-1][0] if south99 else None)
    if edge:
        print("sample", edge[:6], "...", edge[-4:])

    if not apply:
        print("dry-run (pass --apply to write)")
        if "--preview" in sys.argv:
            _write_preview(floor, water, walls)
        return 0

    before = len(walls)
    for c in edge + second + third:
        if c not in walls:
            walls[c] = pick_wall(c[0], c[1])

    text = text[: wm.start(2)] + encode(wfmt, walls) + text[wm.end(2) :]
    open(MAP_PATH, "w", encoding="utf-8", newline="\n").write(text)
    print("wrote walls", before, "->", len(walls), "added", len(walls) - before)
    _write_preview(floor, water, walls)
    return 0


def _write_preview(floor, water, walls) -> None:
    import zlib
    scale = 4
    W, H = 332 * scale, 100 * scale
    rgb = bytearray(W * H * 3)
    for i in range(0, len(rgb), 3):
        rgb[i:i + 3] = b"\x10\x10\x10"

    def plot(x, y, color):
        if not (0 <= x < 332 and 0 <= y < 100):
            return
        for dy in range(scale):
            for dx in range(scale):
                o = ((y * scale + dy) * W + (x * scale + dx)) * 3
                rgb[o:o + 3] = color

    for x, y in floor:
        plot(x, y, bytes((46, 120, 46)))
    for x, y in water:
        plot(x, y, bytes((40, 90, 180)))
    for x, y in walls:
        plot(x, y, bytes((140, 90, 55)))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes(rgb[y * W * 3:(y + 1) * W * 3]) for y in range(H))
    ihdr = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    out = os.path.join(ROOT, "previews", "woodland-rim-proof.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "wb").write(png)
    print("preview", out)


if __name__ == "__main__":
    sys.exit(main())
