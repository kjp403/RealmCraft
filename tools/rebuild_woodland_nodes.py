"""Re-author the gathering + wildlife layout of Goblin Woodland.

The old layout was procedural spray: nodes stepped across the map on a fixed
stride, which dropped herbs into walls and the void, stacked trees on top of
each other, and made the whole zone read as noise. This rebuilds it as authored
patches -- each one sited on a real terrain feature and filled by a solver that
only ever picks reachable, unobstructed, properly-spaced ground.

    py tools/rebuild_woodland_nodes.py [--dry-run]

Two regions live in woodland_tiles.tscn and are NOT walk-connected:
  * the walled meadow   (cells x 4..131)   -- the level 1-5 starter zone
  * the east wing       (cells x 160..330) -- the expansion, reached by the
    teleporter pair at (1656,128) <-> (2616,544), and carrying the authored
    region labels (Sunlit Meadow / Murkwood Ponds / Stone Shelves / East Shore)
"""
import math
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from tilegeom import Terrain, TS

MAP = 'source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn'
SEEDS = [(61, 82), (163, 34)]  # meadow spawn, east-wing teleporter landing

SCENE_ID = '7_jiw8u'  # mineable_node.tscn, already declared

# ext_resource ids already declared in the scene
DATA = {
    'healing_herb': '28_svn3l', 'flax': '27_lebv5', 'frostpetal': '29_frost',
    'normal_tree': '31_ntree', 'oak_tree': '32_otree', 'willow_tree': '33_wtree',
    'maple_tree': '34_mtree',
}
# declared by this tool on first run
NEW_DATA = {
    'yew_tree': ('37_ytree', 'uid://cyewtree001xxx',
                 'res://source/common/gameplay/maps/components/mineable_nodes/yew_tree.tres'),
    'sunwort': ('38_sunwrt', None,
                'res://source/common/gameplay/maps/components/mineable_nodes/sunwort.tres'),
    'moonbloom': ('39_moonb', None,
                  'res://source/common/gameplay/maps/components/mineable_nodes/moonbloom.tres'),
    'bloodcap': ('47_blood', None,
                 'res://source/common/gameplay/maps/components/mineable_nodes/bloodcap.tres'),
    'starblossom': ('48_star', None,
                    'res://source/common/gameplay/maps/components/mineable_nodes/starblossom.tres'),
    'grimshade': ('49_grim', None,
                  'res://source/common/gameplay/maps/components/mineable_nodes/grimshade.tres'),
}
TREES = {'normal_tree', 'oak_tree', 'willow_tree', 'maple_tree', 'yew_tree'}

# --- Gathering patches ------------------------------------------------------
# n / r in px. Trees need wide spacing: 64x96 sprites, and oak draws at 1.4x.
PATCHES = [
    # ---- Meadow, levels 1-5. Starter tiers only: normal/oak wood, herb, flax.
    dict(name='WoodStand', kind='normal_tree', at=(330, 1170), r=250, n=9, spacing=92,
         note="Woodcutter's Stand -- south-west field, the first axe target"),
    dict(name='NorthWood', kind='normal_tree', at=(1790, 250), r=230, n=8, spacing=92,
         note='North tree line below the grove teleporter'),
    dict(name='EastWood', kind='normal_tree', at=(1830, 880), r=250, n=7, spacing=92,
         note='East field stand, near the slayer house'),
    dict(name='OakRise', kind='oak_tree', at=(1640, 640), r=200, n=6, spacing=115,
         note='Oaks (lv10) held by the goblin camp -- risk gates the better log'),
    dict(name='HerbMeadow', kind='healing_herb', at=(1230, 1180), r=200, n=10, spacing=64,
         note='Beginner herb field, a short walk east of the hub portal'),
    dict(name='PondHerb', kind='healing_herb', at=(335, 830), r=200, n=6, spacing=64,
         note='Herbs ringing the pond'),
    dict(name='FlaxField', kind='flax', at=(700, 1210), r=150, n=7, spacing=58,
         note='Flax rows near Warden Bren -- the Cloth for the Warden quest'),
    dict(name='FrostHollow', kind='frostpetal', at=(175, 500), r=190, n=6, spacing=64,
         note='Frostpetal (lv5) in the cold north-west, under the warren'),

    # ---- East wing, the expansion. Higher tiers tied to the authored regions.
    dict(name='WingHerb', kind='healing_herb', at=(2900, 760), r=190, n=5, spacing=64,
         note='Arrival herbs by Scout Calder -- continuity with the meadow'),
    dict(name='WingSunwort', kind='sunwort', at=(3560, 260), r=230, n=9, spacing=64,
         note='Sunwort (lv10) across the Sunlit Meadow'),
    dict(name='WingMaple', kind='maple_tree', at=(3300, 470), r=180, n=6, spacing=112,
         note='Maple Rise (lv35) on the open sunlit ground'),
    dict(name='WingMoonbloom', kind='moonbloom', at=(4780, 700), r=240, n=8, spacing=64,
         note='Moonbloom (lv20) in the shade of Murkwood Ponds'),
    dict(name='WingWillow', kind='willow_tree', at=(4480, 830), r=210, n=6, spacing=108,
         note='Willow Bend (lv20) -- willows take the pond margins'),
    dict(name='WingFrost', kind='frostpetal', at=(3760, 1090), r=230, n=7, spacing=64,
         note='Frostpetal on the cold Stone Shelves'),
    dict(name='WingYew', kind='yew_tree', at=(4740, 1350), r=195, n=5, spacing=115,
         note='Yew Hollow (lv45) at East Shore -- the deepest point of the zone'),
    dict(name='WingYewCamp', kind='yew_tree', at=(4008, 584), r=170, n=4, spacing=115,
         note='Second yew stand beside the wing banker -- East Shore stays the '
              'big hollow, this is the cut-and-bank camp on the north route'),
    dict(name='WingStarblossom', kind='starblossom', at=(4000, 240), r=160, n=8, spacing=64,
         note='Starblossom (lv40) in the east Sunlit Meadow, past the sunwort'),
    dict(name='WingBloodcap', kind='bloodcap', at=(5080, 480), r=200, n=8, spacing=64,
         note='Bloodcap (lv30) ringing the quiet north-east Murkwood pool'),
    dict(name='WingGrimshade', kind='grimshade', at=(3440, 1152), r=140, n=8, spacing=64,
         note='Grimshade (lv50) in the shaded west Stone Shelves, off the frost hollow'),
]

# --- Wildlife nests ---------------------------------------------------------
# The goblin encounters (Gate/Path/Camp/Shaman/Slinger/Chief) are hand-authored
# and left exactly as they are. Only the sprayed rats and wolves are regrouped.
NESTS = [
    dict(prefix='WoodlandRat', at=(880, 560), r=140, n=5, spacing=46),
    dict(prefix='WoodlandRat', at=(1150, 380), r=140, n=5, spacing=46),
    dict(prefix='WoodlandRat', at=(430, 980), r=150, n=5, spacing=46),
    dict(prefix='WoodlandRat', at=(1460, 1230), r=150, n=5, spacing=46),
    dict(prefix='WoodlandRat', at=(1720, 300), r=150, n=4, spacing=46),
    dict(prefix='WoodlandRat', at=(1930, 980), r=150, n=4, spacing=46),
    dict(prefix='WildWolf', at=(250, 700), r=140, n=4, spacing=52),
    dict(prefix='WildWolf', at=(1780, 800), r=150, n=4, spacing=52),
    # The four badgers stay beside the desert camel; two of them sat in walls.
    dict(prefix='CamelDesertBadger', at=(4640, 1400), r=170, n=4, spacing=52),
]


def solve(terrain, specs, taken, decor_pad=12, elbow=1, seed=97, blocked=()):
    """Greedily fill each spec from valid cells, nearest-to-anchor first."""
    placed = list(taken)
    out = []
    for spec in specs:
        cx, cy = spec['at']
        radius, spacing = spec['r'], spec['spacing']
        cands = []
        rc = int(radius // TS) + 1
        ccx, ccy = int(cx // TS), int(cy // TS)
        for gx in range(ccx - rc, ccx + rc + 1):
            for gy in range(ccy - rc, ccy + rc + 1):
                px, py = gx * TS + TS // 2, gy * TS + TS // 2
                d = math.hypot(px - cx, py - cy)
                if d > radius or not terrain.open_cell((gx, gy), elbow):
                    continue
                if not terrain.decor_clear(px, py, decor_pad):
                    continue
                if any(x0 - decor_pad <= px <= x1 + decor_pad
                       and y0 - decor_pad <= py <= y1 + decor_pad
                       for x0, y0, x1, y1 in blocked):
                    continue
                # deterministic jitter so a patch reads organic, not as a lattice
                h = ((gx * 73856093) ^ (gy * 19349663) ^ seed) & 0xFFFF
                cands.append((d + (h / 65535.0) * 26.0, px, py))
        cands.sort()
        chosen = []
        for _, px, py in cands:
            if len(chosen) >= spec['n']:
                break
            if any(math.hypot(px - qx, py - qy) < spacing for qx, qy in placed):
                continue
            chosen.append((px, py))
            placed.append((px, py))
        out.append((spec, chosen))
    return out


def split_blocks(text):
    return re.split(r'\n(?=\[node )', text)


def main():
    dry = '--dry-run' in sys.argv
    terrain = Terrain(MAP, SEEDS)
    src = terrain.text

    # Keep-out list: never bury a portal, warper, teleporter or quest NPC.
    keep_out = []
    for b in split_blocks(src):
        if not b.startswith('[node '):
            continue
        head = b.split('\n', 1)[0]
        if 'instance=ExtResource' not in head:
            continue
        if 'parent="MineableNodes"' in head or 'parent="ReplicatedPropsContainer"' in head:
            continue
        m = re.search(r'^position = Vector2\(([-\d.]+), ([-\d.]+)\)', b, re.M)
        if m:
            keep_out.append((float(m.group(1)), float(m.group(2))))

    # Instanced sub-scenes (the slayer house) draw art this map's layers know
    # nothing about — keep every patch off them.
    blocked = terrain.subscene_rects()
    for x0, y0, x1, y1 in blocked:
        print('sub-scene keep-out: x[%.0f..%.0f] y[%.0f..%.0f]' % (x0, x1, y0, y1))

    results = solve(terrain, PATCHES, keep_out, blocked=blocked)
    taken = keep_out + [p for _, ch in results for p in ch]
    nests = solve(terrain, NESTS, taken, decor_pad=4, blocked=blocked)

    print('%-14s %-14s %4s %4s %6s  %s' % ('PATCH', 'KIND', 'WANT', 'GOT', 'SPREAD', 'NOTE'))
    short = 0
    for spec, chosen in results:
        flag = '' if len(chosen) == spec['n'] else '   <-- SHORT'
        short += spec['n'] - len(chosen)
        # widest gap inside the patch: how much it reads as one group
        spread = max((math.hypot(a[0] - b[0], a[1] - b[1])
                      for a in chosen for b in chosen), default=0)
        print('%-14s %-14s %4d %4d %6d  %s%s' % (
            spec['name'], spec['kind'], spec['n'], len(chosen), spread,
            spec['note'], flag))
    print()
    for spec, chosen in nests:
        flag = '' if len(chosen) == spec['n'] else '   <-- SHORT'
        print('%-14s %-14s %4d %4d  nest at %s%s' % (
            spec['prefix'], 'mob', spec['n'], len(chosen), spec['at'], flag))
    print('\ntotal gathering nodes: %d (was 139), shortfall %d' % (
        sum(len(c) for _, c in results), short))
    if dry:
        return

    src = write_scene(src, results, nests)
    with open(MAP, 'w', encoding='utf-8', newline='\n') as f:
        f.write(src)
    print('wrote', MAP)


def write_scene(src, results, nests):
    # ---- 1. declare the new node resources --------------------------------
    anchor = ('[ext_resource type="Resource" uid="uid://cmapltree001xx" '
              'path="res://source/common/gameplay/maps/components/mineable_nodes/'
              'maple_tree.tres" id="34_mtree"]\n')
    assert anchor in src, 'maple ext_resource anchor missing'
    add = ''
    for kind in NEW_DATA:
        rid, uid, path = NEW_DATA[kind]
        if 'id="%s"' % rid in src:
            continue
        uidpart = ' uid="%s"' % uid if uid else ''
        add += '[ext_resource type="Resource"%s path="%s" id="%s"]\n' % (uidpart, path, rid)
    src = src.replace(anchor, anchor + add, 1)

    # ---- 2. swap the whole MineableNodes subtree ---------------------------
    blocks = split_blocks(src)
    kept, cut_at = [], None
    for b in blocks:
        if b.startswith('[node ') and 'parent="MineableNodes"' in b.split('\n', 1)[0]:
            if cut_at is None:
                cut_at = len(kept)
            continue
        kept.append(b)
    assert cut_at is not None, 'no MineableNodes children found'

    uid = 1930000000
    out = []
    for spec, chosen in results:
        data_id = DATA.get(spec['kind']) or NEW_DATA[spec['kind']][0]
        ysort = '\ny_sort_enabled = true' if spec['kind'] in TREES else ''
        for i, (px, py) in enumerate(chosen, 1):
            out.append(
                '[node name="%s%d" parent="MineableNodes" unique_id=%d '
                'instance=ExtResource("%s")]%s\n'
                'position = Vector2(%d, %d)\n'
                'data = ExtResource("%s")\n\n'
                % (spec['name'], i, uid, SCENE_ID, ysort, px, py, data_id))
            uid += 1
    kept.insert(cut_at, ''.join(out).rstrip('\n') + '\n')
    src = '\n'.join(kept)

    # ---- 3. regroup the wildlife, drop the surplus -------------------------
    survivors = {}
    for spec, chosen in nests:
        survivors.setdefault(spec['prefix'], []).extend(chosen)

    blocks = split_blocks(src)
    used = dict.fromkeys(survivors, 0)
    kept, dropped = [], 0
    for b in blocks:
        head = b.split('\n', 1)[0]
        m = re.match(r'\[node name="([^"]+)" parent="ReplicatedPropsContainer"', head)
        if not m:
            kept.append(b)
            continue
        base = re.sub(r'\d+$', '', m.group(1))
        if base not in survivors:
            kept.append(b)
            continue
        if used[base] >= len(survivors[base]):
            dropped += 1
            continue  # surplus spray -- dropped
        px, py = survivors[base][used[base]]
        used[base] += 1
        b = re.sub(r'^position = Vector2\([-\d.]+, [-\d.]+\)',
                   'position = Vector2(%d, %d)' % (px, py), b, count=1, flags=re.M)
        kept.append(b)
    src = '\n'.join(kept)

    # ---- 4. rebake the replicated-prop id maps -----------------------------
    order = [re.search(r'name="([^"]+)"', b.split('\n', 1)[0]).group(1)
             for b in split_blocks(src)
             if b.startswith('[node ')
             and 'parent="ReplicatedPropsContainer"' in b.split('\n', 1)[0]]
    id_to_node = ('id_to_node = {\n'
                  + ',\n'.join('%d: NodePath("%s")' % (i, n) for i, n in enumerate(order))
                  + '\n}')
    node_to_id = ('node_to_id = {\n'
                  + ',\n'.join('NodePath("%s"): %d' % (n, i) for i, n in enumerate(order))
                  + '\n}')
    src = re.sub(r'id_to_node = \{.*?\n\}', lambda _m: id_to_node, src, count=1, flags=re.S)
    src = re.sub(r'node_to_id = \{.*?\n\}', lambda _m: node_to_id, src, count=1, flags=re.S)
    print('dropped %d surplus wildlife; rebaked %d replicated props' % (dropped, len(order)))
    return src


if __name__ == '__main__':
    main()
