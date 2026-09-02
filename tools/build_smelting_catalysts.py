"""Draw the five smelting catalyst / additive icons.

These are the inputs that replace coal in the post-Runite furnace recipes
(see `SmeltingRecipe`): one additive per metal, plus the shared crucible.

They are DRAWN, not recolored from an existing icon, because each one has to
read as a different KIND of thing at 64px in a bag grid — a scale, a pile of
shards, a pinch of dust, a floating mote, a pot. A palette swap of one blob
would make four items that a player has to read the tooltip to tell apart,
which is the same mistake the tier tool art made.

    python tools/build_smelting_catalysts.py
"""
import math
import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "items", "icons")
SIZE = 64


def _blend(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


class Canvas:
    """A tiny 64x64 RGBA pixel buffer with the few primitives these icons need."""

    def __init__(self, size=SIZE):
        self.size = size
        self.im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        self.px = self.im.load()

    def put(self, x, y, rgb, a=255):
        x, y = int(x), int(y)
        if 0 <= x < self.size and 0 <= y < self.size:
            self.px[x, y] = (rgb[0], rgb[1], rgb[2], a)

    def get(self, x, y):
        if 0 <= x < self.size and 0 <= y < self.size:
            return self.px[x, y]
        return (0, 0, 0, 0)

    def disc(self, cx, cy, r, rgb, a=255):
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    self.put(x, y, rgb, a)

    def line(self, x0, y0, x1, y1, rgb, a=255):
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(steps + 1):
            t = i / steps
            self.put(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), rgb, a)

    def poly(self, pts, rgb, a=255):
        """Scanline fill of a convex-ish polygon."""
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            for i in range(len(pts)):
                (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % len(pts)]
                if (y0 <= y < y1) or (y1 <= y < y0):
                    xs.append(x0 + (x1 - x0) * (y - y0) / (y1 - y0))
            if len(xs) >= 2:
                xs.sort()
                for x in range(int(round(xs[0])), int(round(xs[-1])) + 1):
                    self.put(x, y, rgb, a)

    def outline(self, rgb, a=255):
        """1px dark keyline around every opaque pixel — the pack's house style."""
        solid = [[self.get(x, y)[3] > 40 for y in range(self.size)] for x in range(self.size)]
        for y in range(self.size):
            for x in range(self.size):
                if solid[x][y]:
                    continue
                touching = False
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.size and 0 <= ny < self.size and solid[nx][ny]:
                        touching = True
                        break
                if touching:
                    self.put(x, y, rgb, a)

    def save(self, name):
        path = os.path.join(OUT_DIR, name + ".png")
        self.im.save(path)
        print("wrote", os.path.relpath(path, ROOT))


# --- the five icons ---------------------------------------------------------

def dragon_scale():
    """One shed scale: broad shouldered at the top, drawn to a point at the
    bottom, with a raised central keel and heat still trapped along the keel."""
    c = Canvas()
    dark, mid, hot, rim = (72, 10, 9), (170, 36, 26), (236, 100, 46), (255, 206, 152)
    cx = 32
    top, bot = 8, 58

    def half_at(y):
        t = (y - top) / float(bot - top)
        # quick flare to full width near the shoulder, then a long taper to a tip
        return max(0.0, 23.0 * math.sin(min(1.0, t * 1.28) * math.pi * 0.5) * (1.0 - t) ** 0.55)

    for y in range(top, bot):
        half = half_at(y)
        if half < 0.8:
            continue
        t = (y - top) / float(bot - top)
        for x in range(int(cx - half), int(cx + half) + 1):
            u = (x - cx) / max(1.0, half)  # -1 left .. +1 right
            # cross-section: keel high in the middle, falling away to both edges
            keel = 1.0 - min(1.0, abs(u) * 1.25)
            shade = _blend(dark, mid, 0.35 + 0.65 * keel)
            if u < 0.0:
                shade = _blend(shade, rim, 0.30 * keel * (1.0 - t * 0.4))  # lit from the left
            if abs(u) > 0.80:
                shade = _blend(shade, dark, 0.6)
            c.put(x, y, shade)

    # heat glowing out of the keel groove, strongest at the shoulder
    for y in range(top + 3, bot - 4):
        t = (y - top) / float(bot - top)
        w = max(1, int(half_at(y) * 0.16))
        for x in range(cx - w, cx + w + 1):
            if c.get(x, y)[3] > 0:
                c.put(x, y, _blend(hot, rim, max(0.0, 0.55 - t)))

    # growth ridges arcing across the scale
    for ry in range(top + 9, bot - 6, 7):
        half = half_at(ry)
        for x in range(int(cx - half), int(cx + half) + 1):
            u = (x - cx) / max(1.0, half)
            y = ry + int(4.0 * (1.0 - abs(u)))  # arc sagging toward the tip
            if c.get(x, y)[3] > 0 and abs(u) > 0.18:
                c.put(x, y, _blend(c.get(x, y)[:3], dark, 0.5))
    c.outline((24, 5, 5))
    c.save("catalyst_dragon_scale")


def obsidian_flux():
    """A pile of crushed volcanic glass — sharp shards, no round edges."""
    c = Canvas()
    rng = random.Random(7)
    dark, mid, lit, edge = (30, 6, 46), (96, 22, 122), (166, 62, 208), (232, 190, 255)
    shards = [
        [(10, 54), (20, 30), (30, 54)],
        [(24, 55), (34, 18), (45, 55)],
        [(40, 54), (52, 33), (57, 54)],
        [(16, 55), (27, 41), (38, 55)],
        [(35, 55), (46, 42), (54, 55)],
    ]
    for i, tri in enumerate(shards):
        base = _blend(mid, lit, (i % 3) / 2.0 * 0.55)
        c.poly(tri, base)
        # facet: darken the right half of each shard so it reads faceted
        apex = tri[1]
        c.poly([apex, tri[2], ((apex[0] + tri[2][0]) / 2, tri[2][1])], _blend(base, dark, 0.5))
        # bright chip along the left edge
        c.line(apex[0], apex[1], tri[0][0], tri[0][1], _blend(base, edge, 0.6))
    # glassy speck highlights
    for _ in range(14):
        x, y = rng.randint(12, 52), rng.randint(24, 52)
        if c.get(x, y)[3] > 0:
            c.put(x, y, edge)
    c.outline((18, 3, 28))
    c.save("catalyst_obsidian_flux")


def celestial_dust():
    """A pinch of luminous powder: a soft mound plus loose airborne grains."""
    c = Canvas()
    rng = random.Random(11)
    dark, mid, lit, glow = (74, 62, 34), (188, 168, 96), (238, 220, 132), (255, 250, 214)
    # mound
    for y in range(34, 56):
        t = (y - 34) / 21.0
        half = 5 + 21 * math.sqrt(max(0.0, t))
        for x in range(int(32 - half), int(32 + half) + 1):
            u = abs(x - 32) / max(1.0, half)
            shade = _blend(lit, mid, u * 0.8 + t * 0.3)
            if u > 0.72:
                shade = _blend(shade, dark, 0.5)
            c.put(x, y, shade)
    # granular texture on the mound
    for _ in range(150):
        x, y = rng.randint(8, 56), rng.randint(34, 55)
        if c.get(x, y)[3] > 0:
            c.put(x, y, _blend(c.get(x, y)[:3], glow if rng.random() < 0.45 else dark, 0.4))
    # airborne motes drifting up, fading as they rise
    for _ in range(34):
        y = rng.randint(6, 36)
        x = rng.randint(12, 52)
        a = int(255 * (y - 4) / 34.0)
        c.put(x, y, glow, max(70, min(255, a)))
    # four-point sparkles
    for sx, sy, r in ((20, 16, 3), (44, 12, 4), (34, 26, 2)):
        for d in range(-r, r + 1):
            c.put(sx + d, sy, glow)
            c.put(sx, sy + d, glow)
    c.outline((44, 36, 20))
    c.save("catalyst_celestial_dust")


def astralite_mote():
    """A single suspended mote: a bright diamond core inside a ringed halo."""
    c = Canvas()
    core, mid, deep, halo = (250, 240, 255), (168, 122, 226), (56, 40, 104), (214, 168, 246)
    # outer halo ring (drawn first so the core sits on top)
    for ang in range(0, 360):
        a = math.radians(ang)
        for rr in (23, 24):
            x, y = 32 + math.cos(a) * rr, 32 + math.sin(a) * rr * 0.62
            c.put(x, y, halo, 150)
    for ang in range(0, 360):
        a = math.radians(ang)
        for rr in (18, 19):
            x, y = 32 + math.cos(a) * rr * 0.55, 32 + math.sin(a) * rr
            c.put(x, y, halo, 110)
    # diamond core, shaded from the upper-left
    for y in range(12, 53):
        t = abs(y - 32) / 20.0
        half = (1 - t) * 13
        for x in range(int(32 - half), int(32 + half) + 1):
            u = (x - (32 - half)) / max(1.0, 2 * half)
            shade = _blend(core, mid, min(1.0, u * 1.15 + t * 0.35))
            if u > 0.78 or t > 0.82:
                shade = _blend(shade, deep, 0.55)
            c.put(x, y, shade)
    # vertical facet seam + a hot centre
    for y in range(13, 52):
        c.put(32, y, _blend(c.get(32, y)[:3], core, 0.5))
    c.disc(29, 26, 3.2, core)
    # star flare
    for d in range(-30, 31):
        c.put(32 + d, 32, core, max(0, 190 - abs(d) * 7))
        c.put(32, 32 + d, core, max(0, 190 - abs(d) * 7))
    c.outline((30, 20, 60))
    c.save("catalyst_astralite_mote")


def everburning_crucible():
    """The shared tool: a squat pot on feet with a flame standing in its mouth."""
    c = Canvas()
    iron_d, iron_m, iron_l = (38, 34, 40), (86, 80, 92), (140, 134, 150)
    fl_o, fl_m, fl_c = (232, 96, 26), (252, 178, 44), (255, 244, 190)
    # flame in the mouth, drawn before the rim so the rim overlaps its base
    for y in range(6, 34):
        t = (y - 6) / 28.0
        half = 2 + 11 * math.sin(t * math.pi * 0.95) ** 0.7
        for x in range(int(32 - half), int(32 + half) + 1):
            u = abs(x - 32) / max(1.0, half)
            col = _blend(fl_c, fl_m, min(1.0, u * 1.3 + (1 - t) * 0.25))
            if u > 0.62:
                col = _blend(col, fl_o, 0.85)
            c.put(x, y, col)
    # pot body: tapering bowl
    for y in range(30, 54):
        t = (y - 30) / 24.0
        half = 21 - 7 * t * t
        for x in range(int(32 - half), int(32 + half) + 1):
            u = (x - (32 - half)) / (2 * half)
            shade = _blend(iron_m, iron_d, min(1.0, u * 1.1 + t * 0.45))
            if u < 0.22:
                shade = _blend(shade, iron_l, 0.55 * (1 - u / 0.22))
            c.put(x, y, shade)
    # heat glow low on the belly
    for y in range(44, 53):
        for x in range(16, 49):
            if c.get(x, y)[3] > 0 and (x - 32) ** 2 / 240.0 + (y - 52) ** 2 / 70.0 < 1.0:
                c.put(x, y, _blend(c.get(x, y)[:3], fl_o, 0.5))
    # rim band
    for x in range(10, 55):
        for y in (29, 30, 31):
            if abs(x - 32) <= 21:
                c.put(x, y, iron_l if y == 29 else iron_m)
    # three feet
    for fx in (16, 32, 48):
        for y in range(52, 57):
            for x in range(fx - 3, fx + 4):
                c.put(x, y, iron_d if x > fx else iron_m)
    c.outline((20, 16, 22))
    c.save("catalyst_everburning_crucible")


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    dragon_scale()
    obsidian_flux()
    celestial_dust()
    astralite_mote()
    everburning_crucible()
