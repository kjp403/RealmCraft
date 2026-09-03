"""Lay out both beaches as working fishing settlements.

Scenery and fishing holes are regenerated wholesale rather than patched, so the
composition is described in one place and the collision footprints are derived
from the same table that positions the art.

!! THIS TOOL NO LONGER REPRODUCES EITHER SHIPPED BEACH. Both scenes have been
hand-edited since it last ran, and a re-run on 2026-09-02 (with the table below
already reconciled to the current prop positions) came out WORSE than what ships:

  woodland_beach  drops Barrels entirely ("no room", blocked by PointRocks),
                  pulls BeachedBoat from (700,330) back to (572,170) — undoing
                  the spread dcfbd929 did by hand — and relocates the cooking
                  station from (615,265) to (332,90). The station probe only
                  knows about prop footprints, so it cannot see that a Banker was
                  hand-placed beside the cooker at (560,260) afterwards, and
                  happily separates them.
  deep_shoals     re-adds StallWide/StallSmall/StallAlt, three market stalls the
                  shipped map does not have, and moves its station (930,544) ->
                  (828,650).

So the scenes are the source of truth now, not this file. The footprints in both
are correct as they ship — they were rewritten from the props actually drawn —
and tools/verify_beach_walkable.tscn gates that they stay that way.

Running is therefore OPT-IN: pass --rewrite-maps. Before you do, be ready to
re-place the station/banker pairing and to diff the prop list, and re-run the
verifier afterwards.
"""
import json
import re
import subprocess
import sys
from scene_edit import split_nodes, node_name, join

if "--rewrite-maps" not in sys.argv:
    sys.exit("""
build_beach_layout: refusing to rewrite the beach scenes.
This tool no longer reproduces either shipped map (see the module docstring) --
an unguarded run drops props and moves the cooking stations away from their
bankers. Pass --rewrite-maps if you really mean it, then re-run
tools/verify_beach_walkable.tscn.""")

GODOT = r"C:/Users/kjpee/Godot/Godot_v4.7.1-stable_win64_console.exe"

out = subprocess.run([GODOT, "--headless", "--path", ".", "-s", "tools/build_beach_ground.gd"],
                     capture_output=True, text=True).stdout
shore = {}
for line in out.splitlines():
    m = re.match(r'SHORELINE (\w+) = PackedVector2Array\((.*)\)\s*$', line)
    if m:
        n = [int(v) for v in m.group(2).split(",")]
        shore[m.group(1)] = {n[i]: n[i + 1] for i in range(0, len(n), 2)}


def sy(name, x):
    d = shore[name]
    return d[min(d, key=lambda k: abs(k - x))]


SIZE = {"palm_1": (103, 168), "palm_2": (70, 127), "palm_3": (76, 142),
        "stranded_ship": (512, 288), "stranded_boat": (128, 64), "stranded_boat2": (96, 64),
        "watchtower": (160, 224), "tent": (288, 352), "rocky_skull": (128, 128),
        "fish_basket": (96, 64), "fish_barrel": (32, 64), "shells_a": (32, 32),
        "shells_b": (32, 32), "rope": (32, 32), "barricade": (64, 96),
        "lighthouse_base": (160, 128), "lighthouse_cabin": (192, 256),
        "fisherman_house": (224, 288), "stall_wide": (192, 160), "stall_small": (128, 160),
        "fish_crate": (32, 64), "crates": (32, 64), "chest": (64, 64), "bucket": (32, 32),
        "dry_fish_a": (32, 32), "dry_fish_b": (32, 32), "rock_small": (32, 32),
        "rock_small2": (32, 32), "bones": (32, 32), "fossil": (512, 192), "barrels": (32, 64),
        "stall_alt": (128, 160), "skull_arch": (576, 256), "boat_wreck2": (64, 64),
        "barrel_skeleton": (32, 64), "crate_open": (32, 64), "basket": (32, 64),
        "coconut": (32, 32)}

# Footprint = what your body actually collides with, measured up from the base.
# Flat dressing (shells, fish, rope, bones, buckets) stays walkable: a seashell
# you cannot step over reads as a bug, not as scenery.
SOLID = {"palm_1": (24, 16), "palm_2": (20, 14), "palm_3": (20, 14),
         "stranded_ship": (430, 80), "stranded_boat": (110, 30), "stranded_boat2": (84, 28),
         "watchtower": (110, 54), "tent": (220, 80), "rocky_skull": (110, 54),
         "fish_basket": (84, 30), "fish_barrel": (26, 26), "barricade": (56, 36),
         "lighthouse_base": (140, 60), "fisherman_house": (190, 90),
         "stall_wide": (170, 60), "stall_small": (110, 60), "fish_crate": (28, 26),
         "crates": (28, 26), "chest": (52, 26), "barrels": (28, 26), "fossil": (430, 70),
         "stall_alt": (110, 60), "skull_arch": (480, 90), "boat_wreck2": (56, 26),
         "barrel_skeleton": (28, 26), "crate_open": (28, 26), "basket": (28, 26)}


# Props that are MEANT to occupy the same ground: the lighthouse cabin stands on
# its base. Everything else must not intersect anything else.
STACKS = {("LighthouseCabin", "LighthouseBase")}

# Placement is tested against the sprites' ACTUAL opaque pixels, exported by
# tools/dump_prop_masks.gd at 4px granularity. Bounding boxes carry the big
# transparent margins these sprites have, which is exactly how a palm ended up
# drawn inside a ship's hull while a box test called them clear.
MASKS = json.load(open("previews/prop_masks.json", encoding="utf-8"))
CELL = 4


def mask_cells(tex, x, top):
    """World-space 4px cells this sprite actually paints."""
    m = MASKS[tex]
    ox, oy = x - m["w"] // 2, top
    cells = set()
    bits = m["bits"]
    for cy in range(m["rows"]):
        row = cy * m["cols"]
        for cx in range(m["cols"]):
            if bits[row + cx]:
                cells.add(((ox + cx * CELL) // CELL, (oy + cy * CELL) // CELL))
    return cells


# The waterline is where players STAND to fish. Nothing solid may sit within
# this many pixels of it, or it blocks the very holes the beach exists for.
# Flat dressing (shells, drying fish, rope, bones) is exempt: you walk over it.
FRONTAGE = 72


def scenery(entries, shore_name):
    """Place props against each other's drawn pixels, not their boxes.

    Landmarks go down first and hold their ground; everything else shuffles
    along the strand and a little inland until it paints on empty sand.
    """
    ext, nodes, foot, ids = "", "", [], {}
    order = sorted(range(len(entries)),
                   key=lambda i: -(SIZE[entries[i][1]][0] * SIZE[entries[i][1]][1]))
    taken = {}          # cell -> node that painted it
    dropped = []
    for idx in order:
        node, tex, x, sink = entries[idx]
        w, h = SIZE[tex]
        candidates = [(0, 0)]
        for step in range(1, 7):          # +/- 48px, then a little inland
            for d in (-8, 8):
                candidates.append((d * step, 0))
        for step in range(1, 7):
            for d in (-8, 8):
                candidates.append((d * step, 12 * step))
        # Second pass is wider, and anything that uses it gets reported: a prop
        # that had to travel is a composition problem for a human to look at,
        # not something the tool should quietly paper over.
        for step in range(7, 20):
            for d in (-8, 8):
                candidates.append((d * step, 0))
                candidates.append((d * step, 10 * step))
        got = None
        blocker = None
        for dx, extra in candidates:
            cx = x + dx
            if cx - w // 2 < 4 or cx + w // 2 > max(shore[shore_name]) - 4:
                continue
            base = sy(shore_name, cx) - sink - extra
            top = base - h
            if top < 4:
                continue
            # Keep the fishing frontage clear.
            if tex in SOLID and base > sy(shore_name, cx) - FRONTAGE:
                continue
            cells = mask_cells(tex, cx, top)
            clash = False
            for c in cells:
                other = taken.get(c)
                if other is not None and (node, other) not in STACKS and (other, node) not in STACKS:
                    clash = True
                    if blocker is None:
                        blocker = other
                    break
            if not clash:
                got = (cx, base, top, cells)
                if abs(dx) > 48 or extra > 48:
                    print("  MOVED %-16s %+d,%+d (was blocked by %s)" % (node, dx, extra, blocker))
                break
        if got is None:
            dropped.append("%s (blocked by %s)" % (node, blocker))
            continue
        cx, base, top, cells = got
        for c in cells:
            taken[c] = node
        if tex not in ids:
            ids[tex] = "p_" + tex
            ext += ('[ext_resource type="Texture2D" '
                    'path="res://assets/sprites/environment/sea/props/%s.png" id="%s"]\n'
                    % (tex, ids[tex]))
        nodes += ('[node name="%s" type="Sprite2D" parent="Scenery"]\n'
                  'position = Vector2(%d, %d)\ntexture = ExtResource("%s")\n\n'
                  % (node, cx, top + h // 2, ids[tex]))
        if tex in SOLID:
            fw, fh = SOLID[tex]
            foot.append((cx - fw // 2, base - fh, fw, fh))
    if dropped:
        print("  no room for: %s" % ", ".join(dropped))
    return ext, nodes, foot


def rebuild(path, shore_name, entries, holes, hole_res, station_x, ground_size):
    s = open(path, encoding="utf-8").read()
    # Single source of truth: the collider polygon and the ground size are
    # rewritten from the SAME generator output that positions everything else.
    # They had drifted apart once — the scene still held a shoreline from an
    # earlier, shallower version of the map, which put every fishing hole ~190px
    # from where the sand actually ended.
    pts = ", ".join("%d, %d" % (x, shore[shore_name][x]) for x in sorted(shore[shore_name]))
    s = re.sub(r'^shoreline = PackedVector2Array\([^)]*\)$',
               'shoreline = PackedVector2Array(%s)' % pts, s, count=1, flags=re.M)
    s = re.sub(r'^ground_size = Vector2\([^)]*\)$',
               'ground_size = Vector2(%s)' % ground_size, s, count=1, flags=re.M)
    pre, blocks = split_nodes(s)
    blocks = [b for b in blocks
              if 'parent="Scenery"' not in b[0] and 'parent="MineableNodes"' not in b[0]]
    s = join(pre, blocks)
    for line in re.findall(r'^\[ext_resource[^\n]*/sea/props/[^\n]*\n', s, re.M):
        s = s.replace(line, "", 1)

    ext, nodes, foot = scenery(entries, shore_name)
    hole_nodes = ""
    for node, res, x, depth in holes:
        hole_nodes += ('[node name="%s" parent="MineableNodes" instance=ExtResource("%s")]\n'
                       'position = Vector2(%d, %d)\ndata = ExtResource("%s")\n\n'
                       % (node, hole_res, x, sy(shore_name, x) + depth, res))

    if '[node name="Scenery"' in s:
        s = re.sub(r'(\[node name="Scenery" type="Node2D" parent="\."\]\ny_sort_enabled = true\n)',
                   lambda m: m.group(1) + "\n" + nodes, s, count=1)
    else:
        s = s.replace('[node name="MineableNodes" type="Node2D" parent="."]',
                      '[node name="Scenery" type="Node2D" parent="."]\ny_sort_enabled = true\n\n'
                      + nodes + '[node name="MineableNodes" type="Node2D" parent="."]', 1)
    s = s.rstrip("\n") + "\n\n" + hole_nodes

    # Find open sand for the station: it needs clear space to stand in AND a
    # gap in front to walk up to. The cooker used to be dropped at a fixed x,
    # which put it inside the shipwreck's footprint on the Shoals.
    def clear(cx, cy, pad=26):
        box = (cx - 40 - pad, cy - 34 - pad, 80 + pad * 2, 68 + pad * 2)
        for fx, fy, fw, fh in foot:
            if (box[0] < fx + fw and fx < box[0] + box[2]
                    and box[1] < fy + fh and fy < box[1] + box[3]):
                return False
        return True

    # Scan the whole strand and take the clear spot nearest the intended one,
    # trying a few distances inland before giving up on a column.
    width = max(shore[shore_name])
    best_spot, best_cost = None, None
    for cx in range(60, width - 60, 8):
        for inland in (96, 124, 152, 180, 208):
            cy = sy(shore_name, cx) - inland
            if cy <= 40 or not clear(cx, cy):
                continue
            cost = abs(cx - station_x) + inland
            if best_cost is None or cost < best_cost:
                best_spot, best_cost = (cx, cy), cost
            break
    if best_spot is None:
        raise SystemExit("no clear sand for the cooking station in " + path)
    chosen = best_spot
    station_x, station_y = chosen
    s = re.sub(r'(\[node name="CookingStation".*?\n)position = Vector2\([^)]*\)',
               lambda m: m.group(1) + 'position = Vector2(%d, %d)' % (station_x, station_y),
               s, flags=re.S)
    foot.append((station_x - 32, station_y - 20, 64, 34))
    print("  station at (%d, %d)" % (station_x, station_y))
    rects = ", ".join("Rect2(%d, %d, %d, %d)" % f for f in foot)
    s = re.sub(r'^solid_footprints = Array\[Rect2\]\(\[[^\]]*\]\)$',
               'solid_footprints = Array[Rect2]([%s])' % rects, s, count=1, flags=re.M)

    last = None
    for m in re.finditer(r'^\[ext_resource[^\n]*\n', s, re.M):
        last = m
    s = s[:last.end()] + ext + s[last.end():]
    s = re.sub(r'\n{3,}', '\n\n', s)
    open(path, "w", encoding="utf-8", newline="\n").write(s)
    print("%s: %d props, %d holes, %d footprints"
          % (path.split("/")[-1], len(entries), len(holes), len(foot)))


# Deep Shoals, read west to east: the wreck that named the place, the fisherman's
# house above it, the anglers' camp and market where the cooking station is, then
# the watchtower and lighthouse out on the east point.
SHOALS = [
    # ------------------------------------------------------------------ #
    # WRECK COVE (x 60-560). Where the sea throws things up. Story, not
    # function: no stalls, no station, nothing to use. It sets the tone and
    # gives the village something to be arriving FROM.
    # ------------------------------------------------------------------ #
    ("Wreck", "stranded_ship", 250, 90),
    ("WreckBoat", "stranded_boat2", 500, 90),
    ("BarrelSkeleton", "barrel_skeleton", 300, 90),
    ("Bones1", "bones", 360, 3), ("Bones2", "bones", 405, 3),
    ("RocksW1", "rock_small", 545, 3), ("RocksW2", "rock_small2", 575, 3),
    ("ShellsW1", "shells_a", 460, 3),
    ("PalmW1", "palm_1", 120, 210), ("PalmW2", "palm_3", 235, 250),
    ("PalmW3", "palm_2", 400, 230),

    # ------------------------------------------------------------------ #
    # THE DUNES (x 600-880). Deliberately empty except one landmark: the
    # bone arch you walk under between the cove and the village. Negative
    # space is the point — it makes the village read as a destination.
    # ------------------------------------------------------------------ #
    ("SkullArch", "skull_arch", 730, 300),
    ("CoconutA", "coconut", 690, 3),
    ("PalmA1", "palm_2", 620, 150),

    # ------------------------------------------------------------------ #
    # THE VILLAGE (x 950-1500). A market row facing the water, evenly
    # spaced, with the goods stacked between the stalls and the house set
    # back behind it. This is where the cooking station belongs: you land
    # your catch, cook it at the row, sell from the stalls.
    # ------------------------------------------------------------------ #
    ("StallWide", "stall_wide", 980, 90),
    ("StallSmall", "stall_small", 1180, 90),
    ("StallAlt", "stall_alt", 1360, 90),
    ("FishBaskets", "fish_basket", 1085, 90),
    ("FishCrate1", "fish_crate", 1270, 90), ("FishCrate2", "fish_crate", 1300, 90),
    ("Basket", "basket", 1440, 90), ("CrateOpen", "crate_open", 1470, 90),
    ("DryFish1", "dry_fish_a", 1130, 3), ("DryFish2", "dry_fish_b", 1230, 3),
    ("Bucket", "bucket", 1330, 3),
    ("FishermanHouse", "fisherman_house", 1150, 300),
    ("Barrels", "barrels", 1055, 200), ("FishBarrel", "fish_barrel", 1250, 210),
    ("Chest", "chest", 1400, 205),
    ("PalmV1", "palm_3", 1010, 330), ("PalmV2", "palm_1", 1330, 280),
    ("ShellsV1", "shells_b", 1015, 3), ("ShellsV2", "shells_a", 1395, 3),

    # ------------------------------------------------------------------ #
    # THE CAMP AND THE POINT (x 1550-1900). The anglers' camp sits apart
    # from the market, and the point carries the two things you navigate
    # by: the watchtower, and the lighthouse right on the end.
    # ------------------------------------------------------------------ #
    ("AnglersTent", "tent", 1580, 250),
    ("CratesCamp", "crates", 1520, 90), ("Rope", "rope", 1555, 3),
    ("Watchtower", "watchtower", 1740, 230),
    ("Lighthouse", "lighthouse_cabin", 1850, 90),
    ("RocksE1", "rock_small2", 1660, 3), ("RocksE2", "rock_small", 1810, 3),
    ("ShellsE1", "shells_a", 1700, 3),
    ("PalmE1", "palm_2", 1560, 300), ("PalmE2", "palm_3", 1470, 320),
]

# A couple-few of each tier, spread along the coves so a player works the whole
# beach instead of standing on one hole.
SHOALS_HOLES = [
    # Grouped by where you would fish them: the shallow tiers along the
    # village frontage where the market is, the deep tiers out by the wreck
    # and off the point.
    ("HalibutHole1", "h0", 1000, 30), ("HalibutHole2", "h0", 1120, 32),
    ("HalibutHole3", "h0", 1260, 30), ("HalibutHole4", "h0", 1400, 32),
    ("StingrayHole1", "h1", 1060, 32), ("StingrayHole2", "h1", 1200, 30),
    ("StingrayHole3", "h1", 1340, 32), ("StingrayHole4", "h1", 1480, 30),
    ("WolffishHole1", "h2", 300, 32), ("WolffishHole2", "h2", 470, 30),
    ("WolffishHole3", "h2", 1620, 32),
    ("BlueLobsterHole1", "h3", 150, 30), ("BlueLobsterHole2", "h3", 1760, 32),
    ("BlueLobsterHole3", "h3", 1880, 30),
]

# Kept in step with the scene by hand (2026-09-02): these x/sink pairs are where
# dcfbd929 hand-placed the props. `sink` is pixels UP from the waterline to the
# prop's base, read back as
#   sink = shoreline_y(x) - (sprite.y + ceil(height / 2))
# It is a record of the composition, not something the packer will reproduce —
# see the module docstring. FishStall is gone on purpose (c6d310a6 took the market
# stalls off this beach) and Barricade with it (e073c719 — it hid the cooker).
BEACH = [
    ("CatchBaskets", "fish_basket", 175, 9),
    ("FishCrate", "fish_crate", 245, 84), ("Barrels", "barrels", 775, 30),
    ("DryFish", "dry_fish_a", 95, 12), ("Bucket", "bucket", 560, 48),
    ("BeachedBoat", "stranded_boat", 700, 32),
    ("PointRocks", "rocky_skull", 795, 90),
    ("PalmW1", "palm_1", 55, 90), ("PalmW2", "palm_2", 140, 90),
    ("PalmM1", "palm_3", 330, 120), ("PalmM2", "palm_1", 430, 78),
    ("PalmE1", "palm_2", 640, 90), ("PalmE2", "palm_3", 745, 90),
    ("Rocks1", "rock_small", 110, 4), ("Rocks2", "rock_small2", 640, 4),
    ("ShellsA", "shells_a", 200, 3), ("ShellsB", "shells_b", 480, 3),
    ("ShellsC", "shells_a", 720, 3),
]

BEACH_HOLES = [
    ("ShrimpHole", "h0", 110, 32), ("HerringHole", "h1", 280, 34),
    ("TroutHole", "h2", 470, 30), ("TunaHole", "h3", 690, 32),
]

rebuild("source/common/gameplay/maps/maps/woodland/deep_shoals.tscn", "deep_shoals_ground",
        SHOALS, SHOALS_HOLES, "5_node", 1150, "1920, 1088")
rebuild("source/common/gameplay/maps/maps/woodland/woodland_beach.tscn", "woodland_beach_ground",
        BEACH, BEACH_HOLES, "5_node", 330, "832, 512")
