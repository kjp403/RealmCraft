"""Check every gathering node and wildlife spawn in a map is actually playable.

Fails loudly on the things that made Goblin Woodland feel broken: nodes in the
void or inside walls, nodes cut off from the entrance, sprites drawn on top of
each other, and nodes buried under scenery.

    py tools/verify_woodland_nodes.py
"""
import math
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from tilegeom import Terrain, TS

MAP = 'source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn'
SEEDS = [(61, 82), (163, 34)]

# Half-width of each sprite in px, and how deep its base sits.
# mineable_node.gd anchors any texture taller than 48px at its foot, so the node
# position IS the trunk base. Canopies crossing above each other is just correct
# y-sorted forest; what looks broken is two trunks standing in the same spot.
HALF_W = {'normal_tree': 32, 'oak_tree': 45, 'willow_tree': 32,
          'maple_tree': 32, 'yew_tree': 32}
HERB_HALF_W = 16
BASE_DEPTH = 28   # trunk footprint height
MIN_GAP = {True: 64, False: 40}   # keyed by is_tree


def nodes_of(text, ext):
    out = []
    for b in re.split(r'\n(?=\[node )', text):
        if not b.startswith('[node '):
            continue
        head = b.split('\n', 1)[0]
        nm = re.search(r'name="([^"]+)"', head)
        pm = re.search(r'position = Vector2\(([-\d.]+), ([-\d.]+)\)', b)
        if not pm:
            continue
        dm = re.search(r'^data = ExtResource\("([^"]+)"\)', b, re.M)
        em = re.search(r'^enemy_data = ExtResource\("([^"]+)"\)', b, re.M)
        kind = ''
        if dm:
            kind = os.path.basename(ext.get(dm.group(1), '')).replace('.tres', '')
        out.append(dict(
            name=nm.group(1), x=float(pm.group(1)), y=float(pm.group(2)),
            kind=kind, mineable=bool(dm), mob=bool(em)))
    return out


def main():
    terrain = Terrain(MAP, SEEDS)
    text = terrain.text
    ext = {m.group(2): m.group(1) for m in
           re.finditer(r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"\]', text)}
    all_nodes = nodes_of(text, ext)
    mine = [n for n in all_nodes if n['mineable']]
    mobs = [n for n in all_nodes if n['mob']]
    blocked = terrain.subscene_rects()

    fails = []

    def cell(n):
        return (int(n['x'] // TS), int(n['y'] // TS))

    for n in mine + mobs:
        c = cell(n)
        what = 'node' if n['mineable'] else 'mob'
        if c not in terrain.ground:
            fails.append('%s %s at (%.0f,%.0f) is in the VOID' % (what, n['name'], n['x'], n['y']))
        elif c in terrain.solid:
            fails.append('%s %s at (%.0f,%.0f) is INSIDE A WALL' % (what, n['name'], n['x'], n['y']))
        elif c not in terrain.reach:
            fails.append('%s %s at (%.0f,%.0f) is UNREACHABLE' % (what, n['name'], n['x'], n['y']))

    # sprite bases standing on top of each other
    for i, a in enumerate(mine):
        aw = HALF_W.get(a['kind'], HERB_HALF_W)
        a_tree = a['kind'] in HALF_W
        for b in mine[i + 1:]:
            bw = HALF_W.get(b['kind'], HERB_HALF_W)
            dx, dy = abs(a['x'] - b['x']), abs(a['y'] - b['y'])
            d = math.hypot(dx, dy)
            stacked = dx < aw + bw and dy < BASE_DEPTH
            if stacked or d < MIN_GAP[a_tree and b['kind'] in HALF_W]:
                fails.append('%s and %s stack (%.0fpx apart, dx=%.0f dy=%.0f)' % (
                    a['name'], b['name'], d, dx, dy))

    # buried under map scenery or a building
    for n in mine:
        if not terrain.decor_clear(n['x'], n['y'], 0):
            fails.append('%s at (%.0f,%.0f) is under a scenery sprite' % (
                n['name'], n['x'], n['y']))
        for x0, y0, x1, y1 in blocked:
            if x0 <= n['x'] <= x1 and y0 <= n['y'] <= y1:
                fails.append('%s at (%.0f,%.0f) is inside a building' % (
                    n['name'], n['x'], n['y']))

    # replicated-prop id maps must match the surviving mob list exactly
    order = [re.search(r'name="([^"]+)"', b.split('\n', 1)[0]).group(1)
             for b in re.split(r'\n(?=\[node )', text)
             if b.startswith('[node ')
             and 'parent="ReplicatedPropsContainer"' in b.split('\n', 1)[0]]
    for key, pat in (('id_to_node', r'(\d+): NodePath\("([^"]+)"\)'),
                     ('node_to_id', r'NodePath\("([^"]+)"\): (\d+)')):
        body = re.search(key + r' = \{(.*?)\n\}', text, re.S)
        pairs = re.findall(pat, body.group(1)) if body else []
        got = [p[1] if key == 'id_to_node' else p[0] for p in pairs]
        if got != order:
            fails.append('%s is out of sync: %d entries vs %d mobs' % (key, len(got), len(order)))

    counts = {}
    for n in mine:
        counts[n['kind']] = counts.get(n['kind'], 0) + 1
    print('gathering nodes: %d across %d types' % (len(mine), len(counts)))
    for k in sorted(counts, key=lambda k: -counts[k]):
        print('   %-14s %d' % (k, counts[k]))
    print('wildlife + npc spawns: %d' % len(mobs))

    if fails:
        print('\nFAIL (%d):' % len(fails))
        for f in fails[:40]:
            print('  -', f)
        sys.exit(1)
    print('\nOK - every node is on reachable ground, clear of walls, '
          'scenery, buildings and each other.')


if __name__ == '__main__':
    main()
