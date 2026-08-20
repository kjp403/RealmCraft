"""Lay out both beaches as working fishing settlements.

Scenery and fishing holes are regenerated wholesale rather than patched, so the
composition is described in one place and the collision footprints are derived
from the same table that positions the art.
"""
import json
import re
import subprocess
from scene_edit import split_nodes, node_name, join

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
        for step in range(1, 50):
            for d in (-12, 12):
                candidates.append((d * step, 0))
                candidates.append((d * step, 36 * ((step % 5) + 1)))
        got = None
        for dx, extra in candidates:
            cx = x + dx
            if cx - w // 2 < 4 or cx + w // 2 > max(shore[shore_name]) - 4:
                continue
            base = sy(shore_name, cx) - sink - extra
            top = base - h
            if top < 4:
                continue
            cells = mask_cells(tex, cx, top)
            clash = False
            for c in cells:
                other = taken.get(c)
                if other is not None and (node, other) not in STACKS and (other, node) not in STACKS:
                    clash = True
                    break
            if not clash:
                got = (cx, base, top, cells)
                break
        if got is None:
            dropped.append(node)
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
        for inland in (58, 84, 112, 140):
            cy = sy(shore_name, cx) - inland
            if cy <= 48 or not clear(cx, cy):
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
    # --- West cove: the wreck that named the place, and nothing else nearby. ---
    ("Wreck", "stranded_ship", 260, 6),
    ("WreckBoat", "stranded_boat2", 520, 8),
    ("BoatWreck2", "boat_wreck2", 150, 6),
    ("BarrelSkeleton", "barrel_skeleton", 340, 6),
    ("Bones1", "bones", 200, 3), ("Bones2", "bones", 430, 3),
    ("PalmW1", "palm_1", 90, 12), ("PalmW2", "palm_3", 380, 18),
    ("PalmW3", "palm_2", 200, 250), ("PalmW4", "palm_1", 480, 300),
    ("RocksW1", "rock_small", 120, 4), ("RocksW2", "rock_small2", 300, 4),
    ("ShellsW1", "shells_a", 240, 3), ("ShellsW2", "shells_b", 470, 3),
    # --- Bone arch on the dunes between the cove and the village. ---
    ("SkullArch", "skull_arch", 700, 330),
    ("PalmA1", "palm_3", 620, 150), ("PalmA2", "palm_2", 830, 190),
    ("CoconutA", "coconut", 760, 3),
    # --- The village: market row along the water, house set back. ---
    ("StallWide", "stall_wide", 980, 14),
    ("StallSmall", "stall_small", 1160, 14),
    ("StallAlt", "stall_alt", 1330, 14),
    ("FishBaskets", "fish_basket", 1070, 6),
    ("FishCrate1", "fish_crate", 1240, 6), ("FishCrate2", "fish_crate", 1270, 6),
    ("CrateOpen", "crate_open", 1400, 6), ("Basket", "basket", 1430, 6),
    ("DryFish1", "dry_fish_a", 1120, 3), ("DryFish2", "dry_fish_b", 1300, 3),
    ("Barrels", "barrels", 1210, 6), ("FishBarrel", "fish_barrel", 1360, 6),
    ("FishermanHouse", "fisherman_house", 1120, 250),
    ("Chest", "chest", 1470, 6), ("Bucket", "bucket", 1180, 3),
    ("PalmV1", "palm_2", 900, 260), ("PalmV2", "palm_1", 1300, 300),
    ("ShellsV1", "shells_a", 1030, 3), ("ShellsV2", "shells_b", 1390, 3),
    # --- The anglers' camp, off on its own east of the village. ---
    ("AnglersTent", "tent", 1580, 150),
    ("Rope", "rope", 1540, 3), ("CratesCamp", "crates", 1620, 6),
    ("RocksC", "rock_small", 1500, 4),
    # --- The point: lighthouse and watchtower, with clear ground around them. ---
    ("Watchtower", "watchtower", 1640, 300),
    ("LighthouseBase", "lighthouse_base", 1830, 14),
    ("LighthouseCabin", "lighthouse_cabin", 1830, 120),
    ("PalmE1", "palm_3", 1750, 20), ("PalmE2", "palm_2", 1890, 200),
    ("RocksE1", "rock_small2", 1660, 4), ("RocksE2", "rock_small", 1870, 4),
    ("ShellsE1", "shells_a", 1700, 3), ("ShellsE2", "shells_b", 1860, 3),
]

# A couple-few of each tier, spread along the coves so a player works the whole
# beach instead of standing on one hole.
SHOALS_HOLES = [
    # Spread the length of the strand: the west cove, the village frontage,
    # and the deep water off the point, so tiers are worked in different places.
    ("HalibutHole1", "h0", 170, 32), ("HalibutHole2", "h0", 420, 30),
    ("HalibutHole3", "h0", 1050, 32), ("HalibutHole4", "h0", 1420, 30),
    ("StingrayHole1", "h1", 300, 30), ("StingrayHole2", "h1", 900, 32),
    ("StingrayHole3", "h1", 1250, 30), ("StingrayHole4", "h1", 1620, 32),
    ("WolffishHole1", "h2", 620, 32), ("WolffishHole2", "h2", 1140, 30),
    ("WolffishHole3", "h2", 1780, 32),
    ("BlueLobsterHole1", "h3", 760, 30), ("BlueLobsterHole2", "h3", 1520, 32),
    ("BlueLobsterHole3", "h3", 1880, 30),
]

BEACH = [
    ("FishStall", "stall_small", 230, 12),
    ("CatchBaskets", "fish_basket", 380, 6),
    ("FishCrate", "fish_crate", 420, 6), ("Barrels", "barrels", 450, 6),
    ("DryFish", "dry_fish_a", 300, 3), ("Bucket", "bucket", 400, 3),
    ("Barricade", "barricade", 590, 6),
    ("BeachedBoat", "stranded_boat", 690, 6),
    ("PointRocks", "rocky_skull", 795, 12),
    ("PalmW1", "palm_1", 55, 10), ("PalmW2", "palm_2", 140, 16),
    ("PalmM1", "palm_3", 330, 120), ("PalmM2", "palm_1", 520, 130),
    ("PalmE1", "palm_2", 640, 12), ("PalmE2", "palm_3", 745, 18),
    ("Rocks1", "rock_small", 110, 4), ("Rocks2", "rock_small2", 545, 4),
    ("ShellsA", "shells_a", 200, 3), ("ShellsB", "shells_b", 480, 3),
    ("ShellsC", "shells_a", 720, 3),
]

BEACH_HOLES = [
    ("ShrimpHole", "h0", 110, 32), ("HerringHole", "h1", 280, 34),
    ("TroutHole", "h2", 470, 30), ("TunaHole", "h3", 690, 32),
]

rebuild("source/common/gameplay/maps/maps/woodland/deep_shoals.tscn", "deep_shoals_ground",
        SHOALS, SHOALS_HOLES, "5_node", 1500, "1920, 1088")
rebuild("source/common/gameplay/maps/maps/woodland/woodland_beach.tscn", "woodland_beach_ground",
        BEACH, BEACH_HOLES, "5_node", 330, "832, 512")
