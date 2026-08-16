"""Offline tilemap geometry for RealmCraft .tscn maps.

Decodes TileMapLayer blobs and the TileSet atlas definitions straight out of the
scene text so placement tools can ask real questions about the map — is this
cell walkable, is it reachable from the entrance, is a big tree sprite already
drawn over it — without booting the engine.
"""
import base64
import os
import re
import struct
from collections import deque

TS = 16  # tile size in px
GRASS = {(1, 10), (2, 10), (3, 10)}
SRC_FLOOR, SRC_WATER = 0, 8


def _res(root, p):
    return os.path.join(root, p.replace('res://', '').replace('/', os.sep))


def _parse_ext(src):
    return {m.group(2): m.group(1) for m in
            re.finditer(r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"\]', src)}


def _parse_atlases(src, blocks):
    """{source_id: {(ax, ay): {size, origin, collide}}} for one TileSet body."""
    idmap = {m.group(2): int(m.group(1))
             for m in re.finditer(r'^sources/(\d+) = SubResource\("([^"]+)"\)', src, re.M)}
    out = {}
    for b in blocks:
        hm = re.match(r'\[sub_resource type="TileSetAtlasSource" id="([^"]+)"\]', b)
        if not hm or hm.group(1) not in idmap:
            continue
        tiles = {}
        for m in re.finditer(r'^(\d+):(\d+)/size_in_atlas = Vector2i\((\d+), (\d+)\)', b, re.M):
            tiles.setdefault((int(m.group(1)), int(m.group(2))), {})['size'] = (
                int(m.group(3)), int(m.group(4)))
        for m in re.finditer(
                r'^(\d+):(\d+)/0/texture_origin = Vector2i\((-?\d+), (-?\d+)\)', b, re.M):
            tiles.setdefault((int(m.group(1)), int(m.group(2))), {})['origin'] = (
                int(m.group(3)), int(m.group(4)))
        for m in re.finditer(r'^(\d+):(\d+)/0/physics_layer_0/polygon_0/points', b, re.M):
            tiles.setdefault((int(m.group(1)), int(m.group(2))), {})['collide'] = True
        out[idmap[hm.group(1)]] = tiles
    return out


def _decode(blob):
    raw = base64.b64decode(blob)
    return [struct.unpack_from('<hhhhhh', raw, 2 + i * 12) for i in range((len(raw) - 2) // 12)]


class Terrain:
    """Walkability, reachability and sprite-footprint queries for one map."""

    def __init__(self, scene_path, seeds, root='.'):
        src = open(scene_path, encoding='utf-8').read()
        self.text = src
        ext = _parse_ext(src)
        blocks = re.split(r'\n(?=\[)', src)

        tsm = re.search(r'^tile_set = SubResource\("([^"]+)"\)', src, re.M)
        if tsm:
            body = next(b for b in blocks
                        if b.startswith('[sub_resource type="TileSet" id="%s"]' % tsm.group(1)))
            self.atlases = _parse_atlases(body, blocks)
        else:
            tem = re.search(r'^tile_set = ExtResource\("([^"]+)"\)', src, re.M)
            tsrc = open(_res(root, ext[tem.group(1)]), encoding='utf-8').read()
            self.atlases = _parse_atlases(tsrc, re.split(r'\n(?=\[)', tsrc))

        self.ground, self.solid, self.floor_atlas = set(), set(), {}
        self.decor_rects = []
        for b in blocks:
            hm = re.match(r'\[node name="([^"]+)" type="TileMapLayer"', b)
            if not hm:
                continue
            dm = re.search(r'tile_map_data = PackedByteArray\("([^"]*)"\)', b)
            if not dm or not dm.group(1):
                continue
            for x, y, s, ax, ay, _alt in _decode(dm.group(1)):
                t = self.atlases.get(s, {}).get((ax, ay), {})
                w, h = t.get('size', (1, 1))
                if s == SRC_FLOOR:
                    self.ground.add((x, y))
                    self.floor_atlas[(x, y)] = (ax, ay)
                if s == SRC_WATER or t.get('collide'):
                    for dx in range(w):
                        for dy in range(h):
                            self.solid.add((x + dx, y + dy))
                if (w > 1 or h > 1) and s >= 2:
                    # Engine geometry, verified against tools/probe_decor_rects.gd:
                    #   rect.position = cell_centre - size/2 + texture_origin
                    cx, cy = x * TS + TS / 2, y * TS + TS / 2
                    pw, ph = w * TS, h * TS
                    ox, oy = t.get('origin', (0, 0))
                    x0, y0 = cx - pw / 2 + ox, cy - ph / 2 + oy
                    self.decor_rects.append((x0, y0, x0 + pw, y0 + ph))

        self.walk = self.ground - self.solid
        self.reach = self._flood(seeds)

    def _flood(self, seeds):
        seen, q = set(), deque()
        for s in seeds:
            if s in self.walk:
                seen.add(s)
                q.append(s)
        while q:
            x, y = q.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                c = (x + dx, y + dy)
                if c in self.walk and c not in seen:
                    seen.add(c)
                    q.append(c)
        return seen

    def subscene_rects(self, root='.'):
        """Pixel rects of every instanced sub-scene's own tilemaps.

        Buildings and shoreline pieces are separate .tscn instances, so their
        art is invisible to this map's layers. Without this, a patch radius can
        happily drop a tree on top of the slayer house roof.
        """
        ext = _parse_ext(self.text)
        rects = []
        for b in re.split(r'\n(?=\[node )', self.text):
            if not b.startswith('[node '):
                continue
            head = b.split('\n', 1)[0]
            im = re.search(r'instance=ExtResource\("([^"]+)"\)', head)
            if not im:
                continue
            path = ext.get(im.group(1), '')
            if not path.endswith('.tscn'):
                continue
            base = os.path.basename(path)
            if base in ('mineable_node.tscn', 'hostile_npc.tscn', 'npc.tscn',
                        'warper.tscn', 'portal.tscn', 'teleporter.tscn'):
                continue
            # `position` may sit on the header line itself in hand-edited scenes
            pm = re.search(r'position = Vector2\(([-\d.]+), ([-\d.]+)\)', b)
            ox, oy = (float(pm.group(1)), float(pm.group(2))) if pm else (0.0, 0.0)
            sub = _res(root, path)
            if not os.path.exists(sub):
                continue
            stext = open(sub, encoding='utf-8').read()
            xs0 = ys0 = xs1 = ys1 = None
            for sb in re.split(r'\n(?=\[node )', stext):
                if not re.match(r'\[node name="[^"]+" type="TileMapLayer"', sb):
                    continue
                dm = re.search(r'tile_map_data = PackedByteArray\("([^"]*)"\)', sb)
                if not dm or not dm.group(1):
                    continue
                lm = re.search(r'^position = Vector2\(([-\d.]+), ([-\d.]+)\)', sb, re.M)
                lx, ly = (float(lm.group(1)), float(lm.group(2))) if lm else (0.0, 0.0)
                for x, y, _s, _ax, _ay, _alt in _decode(dm.group(1)):
                    px0, py0 = x * TS + lx, y * TS + ly
                    xs0 = px0 if xs0 is None else min(xs0, px0)
                    ys0 = py0 if ys0 is None else min(ys0, py0)
                    xs1 = px0 + TS if xs1 is None else max(xs1, px0 + TS)
                    ys1 = py0 + TS if ys1 is None else max(ys1, py0 + TS)
            if xs0 is not None:
                rects.append((ox + xs0, oy + ys0, ox + xs1, oy + ys1))
        return rects

    def open_cell(self, c, elbow=1):
        """Reachable, with clear ground all round — no nodes jammed into nooks."""
        if c not in self.reach:
            return False
        return all((c[0] + dx, c[1] + dy) in self.walk
                   for dx in range(-elbow, elbow + 1)
                   for dy in range(-elbow, elbow + 1))

    def decor_clear(self, px, py, pad):
        return not any(x0 - pad <= px <= x1 + pad and y0 - pad <= py <= y1 + pad
                       for x0, y0, x1, y1 in self.decor_rects)
