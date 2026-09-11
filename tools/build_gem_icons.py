#!/usr/bin/env python3
"""Draw a unique icon for every gem in the game.

WHY THIS EXISTS
---------------
All 43 gem items shared 15 images between them, and those 15 were really two
silhouettes -- an octagonal barrel and a raw cluster -- recoloured. Eight of the
27 named gems were byte-identical triplets. In the bag you could not tell a
Dragon Gem from a Voidsilk Gem without hovering, which blocks any crafting
content that asks a player to hold several gems at once.

THE SYSTEM (this is the point -- 43 arbitrary pictures would be no better)
-------------------------------------------------------------------------
Shape carries identity, colour carries family. Both survive the worst case,
which is a 64x64 icon NEAREST-downscaled to a 32x32 HUD slot (PixelIcon._fit) --
that throws away every other pixel, so nothing thinner than ~3px here is real.

  * The three combat ladders each run six tiers (vendor_value 12->32 is an exact
    tier proxy). CUT ENCODES TIER and HUE ENCODES ROLE, so the ladders rhyme:
    a star cut is always tier 6, amber is always a fitting. Learn six shapes and
    three colours instead of eighteen pictures.
  * The nine bespoke armour/jewellery gems get a cut and a hue of their own,
    picked to match the words already in their description.
  * The sixteen Slayer gems are a 4x4 grid, so they get the treatment a grid
    wants: CUT+HUE ENCODE THE STAT, and the METAL SETTING ENCODES THE QUALITY --
    copper, iron, silver, gold, which is literally the metal each one's
    description tells you to forge it into. The icon teaches the recipe.

Uncut gems (the reason this was asked for) are already possible from here: every
gem's hue lives in GEMS, and CUTS has a "raw" entry, so an uncut set is a loop
over GEMS with cut="raw". Deliberately NOT emitted -- the uncut items need drop
tables and recipes, which is a content decision, not an art one.

Style is matched to the existing pack, not to pixel art: chunky near-black
outline, flat facet planes, one pair of diagonal streak highlights. Drawn at 8x
and Lanczos'd down, same as the pack's own anti-aliased edges.

Usage:  python tools/build_gem_icons.py [--check]
        --check renders and reports the closest pair without writing anything.
"""

from __future__ import annotations

import argparse
import colorsys
import hashlib
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import gem_shading as gs

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "assets", "sprites", "items", "icons")
GEM_DIR = os.path.join(
    ROOT, "source", "common", "gameplay", "items", "materials", "gems"
)
INDEX = os.path.join(
    ROOT, "source", "common", "registry", "indexes", "items_index.tres"
)

SIZE = 64
SS = 8            # supersample factor; 512x512 working canvas
C = SIZE * SS
# The pack's gems sit in a ~45x48 box inside 64x64. Matching that keeps a gem
# the same optical weight as the sword next to it in the bag.
HALF_W = 23.0 * SS
HALF_H = 25.0 * SS
CENTRE = (C / 2.0, C / 2.0 + 0.5 * SS)

OUTLINE_W = 1.8 * SS      # ~2px of rim at 64, so ~1px survives a 32px slot
FACET_W = 0.75 * SS
LIGHT = (-0.60, -0.80)    # upper-left, matches every other icon in the pack


# --------------------------------------------------------------------------
# palette
# --------------------------------------------------------------------------
# (hue turns, saturation, value) of the gem's MID tone. Facets step off this.
PALETTE = {
    # three combat ladders -- one hue family each, brightening up the ladder
    "amber_1": (0.065, 0.95, 0.76), "amber_2": (0.078, 0.96, 0.83),
    "amber_3": (0.092, 0.97, 0.89), "amber_4": (0.108, 0.96, 0.94),
    "amber_5": (0.124, 0.92, 0.98), "amber_6": (0.142, 0.84, 1.00),

    "arcane_1": (0.720, 0.78, 0.74), "arcane_2": (0.745, 0.80, 0.80),
    "arcane_3": (0.772, 0.82, 0.86), "arcane_4": (0.800, 0.82, 0.91),
    "arcane_5": (0.828, 0.78, 0.96), "arcane_6": (0.862, 0.70, 1.00),

    "hunter_1": (0.408, 0.85, 0.70), "hunter_2": (0.392, 0.90, 0.78),
    "hunter_3": (0.374, 0.94, 0.85), "hunter_4": (0.356, 0.95, 0.91),
    "hunter_5": (0.338, 0.94, 0.96), "hunter_6": (0.320, 0.88, 1.00),

    # bespoke -- hue taken from each gem's own description text
    "blood":     (0.985, 0.93, 0.88),
    "coal":      (0.045, 0.95, 0.92),
    "violet":    (0.788, 0.62, 0.78),
    "silver":    (0.605, 0.22, 0.86),
    "ivory":     (0.108, 0.30, 0.88),
    "sapphire":  (0.618, 0.96, 0.78),
    "tide":      (0.505, 0.95, 0.94),
    "turquoise": (0.455, 0.80, 0.82),
    "moss":      (0.278, 0.82, 0.72),

    # Skilling gems (Crafting: mine uncut -> cut -> set into jewellery). A
    # SEPARATE economy from the 27 armour-fitting gems, so they take a cut no
    # fitting uses and hues chosen to sit clear of the three ladders.
    "sapphire_gem": (0.662, 0.92, 0.92),
    "emerald_gem":  (0.352, 0.96, 0.88),
    "ruby_gem":     (0.955, 0.96, 0.80),
    "diamond_gem":  (0.545, 0.13, 1.00),
    # The geode is ROCK, not gem: low saturation, low value, so the
    # crystals in its cavity read as the only bright thing in the icon.
    "geode_rock":   (0.075, 0.22, 0.62),

    # slayer stats -- the four maximally separated hues
    "vital":  (0.985, 0.88, 0.88),
    "agile":  (0.270, 0.90, 0.80),
    "focus":  (0.558, 0.94, 0.92),
    "guard":  (0.838, 0.80, 0.94),
}

# metal of the Slayer setting == the metal the description says to forge it into
METALS = {
    "copper":  ((0.055, 0.62, 0.66), (0.050, 0.55, 0.90)),
    "iron":    ((0.600, 0.09, 0.40), (0.600, 0.07, 0.68)),
    "silver":  ((0.585, 0.10, 0.78), (0.575, 0.05, 1.00)),
    "gold":    ((0.125, 0.72, 0.76), (0.135, 0.60, 1.00)),
}


def hsv(h: float, s: float, v: float, a: int = 255) -> tuple[int, int, int, int]:
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, min(s, 1.0), min(v, 1.0))
    return (int(r * 255 + 0.5), int(g * 255 + 0.5), int(b * 255 + 0.5), a)


def shade(base: tuple[float, float, float], mul: float,
          sat_mul: float = 1.0) -> tuple[int, int, int, int]:
    """A facet plane off the gem's mid tone.

    Darkening also SATURATES and highlighting also DESATURATES, which is what
    stops a flat multiply from reading as grey mud on the shadow side.
    """
    h, s, v = base
    if mul < 1.0:
        s = s + (1.0 - mul) * 0.30
    else:
        s = s - (mul - 1.0) * 0.55
    return hsv(h, max(0.0, min(1.0, s * sat_mul)), max(0.0, min(1.0, v * mul)))


def outline_colour(base: tuple[float, float, float]) -> tuple[int, int, int, int]:
    # Near-black, but carrying the gem's hue -- a pure black outline reads as a
    # sticker cut out and pasted on top of the pack's warmer linework.
    h, s, _ = base
    return hsv(h, min(0.85, s + 0.1), 0.085)


# --------------------------------------------------------------------------
# geometry -- everything is authored in normalised [-1, 1], y down
# --------------------------------------------------------------------------
def to_px(pts, sx: float = 1.0, sy: float = 1.0, dx: float = 0.0, dy: float = 0.0):
    return [
        (CENTRE[0] + (x * sx + dx) * HALF_W, CENTRE[1] + (y * sy + dy) * HALF_H)
        for x, y in pts
    ]


def superellipse(n: float, w: float, h: float, steps: int = 48):
    pts = []
    for i in range(steps):
        t = 2.0 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        pts.append((
            w * math.copysign(abs(ct) ** (2.0 / n), ct),
            h * math.copysign(abs(st) ** (2.0 / n), st),
        ))
    return pts


def ngon(sides: int, w: float, h: float, rot: float = 0.0):
    return [
        (w * math.cos(2.0 * math.pi * i / sides + rot),
         h * math.sin(2.0 * math.pi * i / sides + rot))
        for i in range(sides)
    ]


def star_poly(points: int, w: float, h: float, inner: float, rot: float = 0.0):
    pts = []
    for i in range(points * 2):
        r = 1.0 if i % 2 == 0 else inner
        a = math.pi * i / points + rot
        pts.append((w * r * math.cos(a), h * r * math.sin(a)))
    return pts


def scale_poly(pts, k: float, dy: float = 0.0):
    return [(x * k, y * k + dy) for x, y in pts]


def resample(pts, n: int):
    """Even-arc-length resample, so a table ring lines up with its outline ring
    even when the outline is a mix of long straights and tight corners."""
    closed = pts + [pts[0]]
    seg = [math.dist(closed[i], closed[i + 1]) for i in range(len(pts))]
    total = sum(seg)
    out, target, acc, i = [], 0.0, 0.0, 0
    step = total / n
    for _ in range(n):
        while acc + seg[i] < target - 1e-9:
            acc += seg[i]
            i += 1
        t = (target - acc) / seg[i] if seg[i] else 0.0
        a, b = closed[i], closed[i + 1]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        target += step
    return out


def heart_poly(steps: int = 56):
    pts = []
    for i in range(steps):
        t = 2.0 * math.pi * i / steps
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t)
              - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((x / 17.0, y / 17.0))
    return pts


def pear_poly(steps: int = 56):
    """Teardrop: a real point at the top over a round belly. The first pass
    tapered too gently and read as an egg, which is not a silhouette."""
    pts = []
    for i in range(steps):
        t = 2.0 * math.pi * i / steps - math.pi / 2.0
        k = (math.sin(t) + 1.0) / 2.0          # 0 at the point, 1 at the belly
        w = (k ** 0.48) * 0.94
        pts.append((math.cos(t) * w, -1.0 + k * 1.86))
    return pts


CUTS: dict[str, dict] = {
    # mode "radial": table + one ring of girdle facets
    # mode "radial2": table + two rings -- reads as a more ornate stone
    # mode "steps": concentric flats, the emerald/step-cut look
    "cushion":   dict(mode="radial",  poly=superellipse(3.4, 0.90, 0.86),
                      table=0.52, n=8),
    "emerald":   dict(mode="steps",   poly=ngon(8, 0.76, 0.94, math.pi / 8),
                      rings=(0.80, 0.58, 0.34)),
    "trillion":  dict(mode="radial",  poly=superellipse(6.0, 0.98, 0.92, 48),
                      table=0.46, n=9),
    "marquise":  dict(mode="radial",  poly=None, table=0.44, n=10,
                      marquise=True),
    "brilliant": dict(mode="radial2", poly=ngon(16, 0.94, 0.92, math.pi / 16),
                      table=0.40, mid=0.70, n=12),
    "star":      dict(mode="radial",  poly=star_poly(6, 1.00, 0.98, 0.52,
                                                     -math.pi / 2),
                      table=0.42, n=12),
    "kite":      dict(mode="radial",  poly=[(0.0, -1.0), (0.72, -0.12),
                                            (0.0, 1.0), (-0.72, -0.12)],
                      table=0.46, n=8),
    "pear":      dict(mode="radial",  poly=pear_poly(), table=0.48, n=9),
    "heart":     dict(mode="radial",  poly=heart_poly(), table=0.46, n=9),
    "hexagon":   dict(mode="steps",   poly=ngon(6, 1.00, 0.80, 0.0),
                      rings=(0.78, 0.52)),
    "barrel":    dict(mode="barrel",  poly=None),
    "orb":       dict(mode="orb",     poly=None),
    "obelisk":   dict(mode="obelisk", poly=None),
    "cluster":   dict(mode="cluster", poly=None),
    "shard":     dict(mode="shard",   poly=None),
    # Square-cornered, facets radiating from the corners. Reserved for the
    # skilling gems: it is the only hard-cornered stone in the set, so an
    # unfamiliar square silhouette reads as "not an armour fitting".
    "princess":  dict(mode="radial",  poly=ngon(4, 0.88, 0.94, math.pi / 4),
                      table=0.44, n=8),
    "raw":       dict(mode="raw",     poly=None),
}


def marquise_poly(steps: int = 48):
    """Two circular arcs meeting in points at top and bottom."""
    pts = []
    for i in range(steps):
        t = 2.0 * math.pi * i / steps - math.pi / 2.0
        s = math.sin(t)
        pts.append((math.cos(t) * (1.0 - abs(s) ** 1.7) * 1.02, s))
    return pts


CUTS["marquise"]["poly"] = marquise_poly()


def rounded_tri(steps: int = 60, round_k: float = 0.30):
    """Equilateral-ish triangle, point up, with softened corners."""
    verts = [(0.0, -1.0), (0.98, 0.72), (-0.98, 0.72)]
    pts = []
    for i in range(3):
        a, b, c = verts[i], verts[(i + 1) % 3], verts[(i - 1) % 3]
        p0 = (a[0] + (c[0] - a[0]) * round_k, a[1] + (c[1] - a[1]) * round_k)
        p1 = (a[0] + (b[0] - a[0]) * round_k, a[1] + (b[1] - a[1]) * round_k)
        for j in range(steps // 3 + 1):      # quadratic bezier round the corner
            t = j / (steps // 3)
            u = 1.0 - t
            pts.append((u * u * p0[0] + 2 * u * t * a[0] + t * t * p1[0],
                        u * u * p0[1] + 2 * u * t * a[1] + t * t * p1[1]))
    return pts


CUTS["trillion"]["poly"] = rounded_tri()
CUTS["trillion"].pop("tri", None)


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------
def facet_shade(mid, centre_xy, ring: float, alt: int = 0) -> float:
    """Brightness of a facet plane, from where it sits on the stone.

    A gem's crown facets tilt outward, so a facet's 2D direction from the centre
    doubles as its normal. `ring` pulls outer facets darker, which is what gives
    the stone a domed crown instead of a flat sticker.
    """
    x, y = centre_xy
    n = math.hypot(x, y) or 1.0
    d = (x / n) * LIGHT[0] + (y / n) * LIGHT[1]
    d += 0.16 if alt else -0.16
    return (0.92 + 0.42 * d) * (1.0 - 0.10 * ring)


def draw_poly(d: ImageDraw.ImageDraw, pts, fill, edge=None, width: float = 0.0):
    d.polygon(pts, fill=fill)
    if edge is not None and width > 0:
        d.line(list(pts) + [pts[0]], fill=edge, width=int(width), joint="curve")


def build_facets(spec: dict, base):
    """(silhouette, [(polygon, colour)]) in normalised space for a faceted cut."""
    mode = spec["mode"]
    poly = spec["poly"]
    facets = []

    if mode in ("radial", "radial2"):
        n = spec["n"]
        outer = resample(poly, n)
        table_k = spec["table"]
        if mode == "radial2":
            mid_k = spec["mid"]
            middle = resample(scale_poly(poly, mid_k, -0.02), n)
            rings = [(outer, middle, 1.0), (middle,
                     resample(scale_poly(poly, table_k, -0.03), n), 0.45)]
            table = resample(scale_poly(poly, table_k, -0.03), n)
        else:
            table = resample(scale_poly(poly, table_k, -0.03), n)
            rings = [(outer, table, 1.0)]
        for a_ring, b_ring, depth in rings:
            for i in range(n):
                j = (i + 1) % n
                quad = [a_ring[i], a_ring[j], b_ring[j], b_ring[i]]
                cx = sum(p[0] for p in quad) / 4.0
                cy = sum(p[1] for p in quad) / 4.0
                facets.append((quad, shade(base, facet_shade(
                    base, (cx, cy), depth, i % 2))))
        facets.append((table, shade(base, 1.30)))
        return poly, facets

    if mode == "steps":
        prev = poly
        facets.append((prev, shade(base, 0.82)))
        for k, ring_k in enumerate(spec["rings"]):
            cur = scale_poly(poly, ring_k, -0.015 * (k + 1))
            # risers first, so the flat that follows sits on top of them
            for i in range(len(poly)):
                j = (i + 1) % len(poly)
                quad = [prev[i], prev[j], cur[j], cur[i]]
                cx = sum(q[0] for q in quad) / 4.0
                cy = sum(q[1] for q in quad) / 4.0
                facets.append((quad, shade(base, facet_shade(
                    base, (cx, cy), 1.0 - 0.3 * k))))
            facets.append((cur, shade(base, 0.96 + 0.15 * (k + 1))))
            prev = cur
        return poly, facets

    return poly, facets


def barrel_facets(base):
    """The pack's original octagonal barrel, kept so one gem still reads as the
    silhouette players already know."""
    top = [(-0.52, -0.98), (0.52, -0.98), (0.92, -0.62), (0.92, 0.66),
           (0.52, 0.98), (-0.52, 0.98), (-0.92, 0.66), (-0.92, -0.62)]
    lid = [(-0.52, -0.98), (0.52, -0.98), (0.92, -0.62), (0.60, -0.30),
           (-0.46, -0.30), (-0.92, -0.62)]
    left = [(-0.92, -0.62), (-0.46, -0.30), (-0.46, 0.86), (-0.92, 0.66)]
    right = [(0.60, -0.30), (0.92, -0.62), (0.92, 0.66), (0.52, 0.98),
             (0.46, 0.90)]
    front = [(-0.46, -0.30), (0.60, -0.30), (0.46, 0.90), (0.52, 0.98),
             (-0.52, 0.98), (-0.46, 0.86)]
    return top, [(front, shade(base, 1.00)), (left, shade(base, 0.66)),
                 (right, shade(base, 0.78)), (lid, shade(base, 1.24))]


def obelisk_facets(base):
    """Upright four-sided pillar under a pyramid cap -- reads as architecture,
    not jewellery, which is the point for a sworn/covenant stone."""
    sil = [(0.0, -1.00), (0.56, -0.42), (0.56, 0.86), (0.20, 1.00),
           (-0.36, 1.00), (-0.56, 0.82), (-0.56, -0.42)]
    cap_l = [(0.0, -1.00), (-0.06, -0.30), (-0.56, -0.42)]
    cap_r = [(0.0, -1.00), (0.56, -0.42), (-0.06, -0.30)]
    face_l = [(-0.56, -0.42), (-0.06, -0.30), (-0.10, 0.96), (-0.36, 1.00),
              (-0.56, 0.82)]
    face_r = [(-0.06, -0.30), (0.56, -0.42), (0.56, 0.86), (0.20, 1.00),
              (-0.10, 0.96)]
    return sil, [(face_r, shade(base, 0.70)), (face_l, shade(base, 1.02)),
                 (cap_r, shade(base, 0.86)), (cap_l, shade(base, 1.30))]


def _spire(cx: float, cy: float, w: float, h: float, lean: float):
    """One hexagonal crystal: body plus a two-plane point."""
    tipx = cx + lean * w
    sil = [(tipx, cy - h), (cx + w, cy - h * 0.58), (cx + w, cy + h * 0.34),
           (cx, cy + h * 0.52), (cx - w, cy + h * 0.34),
           (cx - w, cy - h * 0.58)]
    left = [(cx - w, cy - h * 0.58), (cx, cy - h * 0.50), (cx, cy + h * 0.52),
            (cx - w, cy + h * 0.34)]
    right = [(cx, cy - h * 0.50), (cx + w, cy - h * 0.58),
             (cx + w, cy + h * 0.34), (cx, cy + h * 0.52)]
    tip_l = [(tipx, cy - h), (cx, cy - h * 0.50), (cx - w, cy - h * 0.58)]
    tip_r = [(tipx, cy - h), (cx + w, cy - h * 0.58), (cx, cy - h * 0.50)]
    return sil, left, right, tip_l, tip_r


def cluster_facets(base):
    """Three spires of different heights. Kept for the two gems the pack already
    drew this way, so the change does not erase their identity."""
    spires = [(-0.52, 0.42, 0.32, 0.72, -0.14),
              (0.46, 0.50, 0.28, 0.60, 0.16),
              (0.00, 0.06, 0.40, 1.02, 0.02)]
    sils, facets = [], []
    for i, (cx, cy, w, h, lean) in enumerate(spires):
        sil, l, r, tl, tr = _spire(cx, cy, w, h, lean)
        sils.append(sil)
        lift = 1.0 if i == 2 else 0.86      # back spires sit in shadow
        facets += [(l, shade(base, 1.02 * lift)), (r, shade(base, 0.66 * lift)),
                   (tl, shade(base, 1.30 * lift)), (tr, shade(base, 0.86 * lift))]
    return sils, facets


def shard_facets(base):
    """A single leaning splinter with a chip beside it -- the most irregular
    silhouette in the set, so it never reads as any cut stone."""
    big = [(0.10, -1.00), (0.52, -0.30), (0.42, 0.62), (0.06, 1.00),
           (-0.26, 0.54), (-0.34, -0.34)]
    spine = [(0.10, -1.00), (0.10, 0.86), (0.06, 1.00), (-0.26, 0.54),
             (-0.34, -0.34)]
    chip = [(-0.62, 0.06), (-0.34, 0.28), (-0.40, 0.96), (-0.78, 0.72)]
    chip_l = [(-0.62, 0.06), (-0.52, 0.20), (-0.58, 0.86), (-0.78, 0.72)]
    return [big, chip], [
        (big, shade(base, 0.70)), (spine, shade(base, 1.16)),
        (chip, shade(base, 0.80)), (chip_l, shade(base, 1.06)),
    ]


def raw_facets(base):
    """Uncut nugget: a lumpy silhouette with one exposed cleavage plane. Not
    wired to any item yet -- this is the shape an uncut set would use."""
    sil = [(-0.30, -0.92), (0.34, -0.80), (0.78, -0.30), (0.86, 0.36),
           (0.44, 0.90), (-0.30, 0.96), (-0.82, 0.52), (-0.88, -0.22)]
    face = [(-0.30, -0.92), (0.34, -0.80), (0.18, -0.10), (-0.46, -0.24)]
    lower = [(-0.46, -0.24), (0.18, -0.10), (0.44, 0.90), (-0.30, 0.96)]
    return sil, [(sil, shade(base, 0.66, 0.80)), (lower, shade(base, 0.88, 0.85)),
                 (face, shade(base, 1.18, 0.90))]


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------
# Everything below composites into one float buffer (tools/gem_shading.py) so
# a stone and the metal holding it share a light and can be INTERLEAVED --
# cup behind, stone, claws in front. Drawing each part to its own finished
# image and pasting them is what made the first pass read as two stickers.


def frame_px(pts, cx: float, cy: float, hw: float, hh: float):
    return [(cx + x * hw, cy + y * hh) for x, y in pts]


def facets_for(cut: str, base, matte: bool):
    """(silhouettes, facets) in normalised space for any cut."""
    spec = CUTS[cut]
    mode = spec["mode"]
    if mode == "barrel":
        sil, facets = barrel_facets(base)
        return [sil], facets
    if mode == "obelisk":
        sil, facets = obelisk_facets(base)
        return [sil], facets
    if mode == "cluster":
        return cluster_facets(base)
    if mode == "shard":
        return shard_facets(base)
    if mode == "raw":
        sil, facets = raw_facets(base)
        return [sil], facets
    if mode == "orb":
        return [superellipse(2.0, 0.94, 0.92)], []
    sil, facets = build_facets(spec, base)
    return [sil], facets


def draw_stone(cv, cut: str, palette: str, cx: float, cy: float,
               hw: float, hh: float, *, matte: bool = False,
               sparkle: bool = False) -> "np.ndarray":
    """Paint one stone into [param cv] at an arbitrary place and scale.

    Returns its silhouette mask, which callers use for contact shadows and for
    deciding where a claw must cross in front of it.

    The value range here is deliberately wide -- deep pavilion shadow through a
    near-white specular. Flat mid-tone facets were the whole reason the first
    pass looked cheap.
    """
    base = PALETTE[palette]
    if matte:
        h, s_, v_ = base
        base = (h, s_ * 0.72, v_ * 0.78)

    sils, facets = facets_for(cut, base, matte)
    sil_px = [frame_px(s, cx, cy, hw, hh) for s in sils]
    mask = np.zeros((cv.size, cv.size), dtype=np.float32)
    for s in sil_px:
        mask = np.maximum(mask, gs.poly_mask(cv.size, s, feather=0.7))

    ink = np.asarray(outline_colour(base)[:3], dtype=np.float32) / 255.0

    # Body first: a dark base under everything, so any seam between facets
    # falls to shadow rather than to the page.
    cv.over(ink * 1.35, mask)

    if CUTS[cut]["mode"] == "orb":
        # Cabochon: a smooth dome, so it gets a radial falloff rather than
        # facets, plus one tight specular.
        # Dome: normal from the radial offset, lit like a sphere.
        nx = (cv.X - cx) / max(hw, 1.0)
        ny = (cv.Y - cy) / max(hh, 1.0)
        r2 = np.clip(nx * nx + ny * ny, 0.0, 1.0)
        nz = np.sqrt(1.0 - r2)
        diff = np.clip(nx * gs.LIGHT[0] + ny * gs.LIGHT[1] + nz * gs.LIGHT[2],
                       0.0, 1.0)
        lo = np.asarray(shade(base, 0.48)[:3], np.float32) / 255.0
        hi = np.asarray(shade(base, 1.34)[:3], np.float32) / 255.0
        col = lo[None, None, :] + (hi - lo)[None, None, :] * (diff ** 0.9)[..., None]
        cv.over(np.clip(col, 0.0, 1.0), mask)
    else:
        for poly, colour in facets:
            pts = frame_px(poly, cx, cy, hw, hh)
            col = np.asarray(colour[:3], dtype=np.float32) / 255.0
            gs.fill_facet(cv, pts, col, contrast=0.13 if matte else 0.22)
        # Facet seams: a hair of shadow between planes reads as a real edge
        # without the leaded-glass look a full stroke gives.
        seam = np.asarray(shade(base, 0.40, 1.05)[:3], dtype=np.float32) / 255.0
        for poly, _ in facets:
            pts = frame_px(poly, cx, cy, hw, hh)
            cv.over(seam, gs.stroke_mask(cv.size, pts, FACET_W * 0.85,
                                         feather=0.55) * mask * 0.80)

    scale = max(hw, hh)

    if not matte:
        # Rim light on the shadow side. This is the single strongest "solid
        # object" cue in the whole icon.
        rim = np.asarray(shade(base, 1.55, 0.55)[:3], dtype=np.float32) / 255.0
        gs.inner_glow(cv, mask, rim, width=scale * 0.055, strength=0.42,
                      direction=(0.62, 0.72))
        # Crown light along the lit edge, brighter and tighter.
        crown = np.asarray(shade(base, 1.75, 0.30)[:3], dtype=np.float32) / 255.0
        gs.inner_glow(cv, mask, crown, width=scale * 0.042, strength=0.58,
                      direction=(-0.60, -0.78))
        # One specular hotspot on the table, up-left of centre.
        hx, hy = cx - hw * 0.30, cy - hh * 0.34
        r = scale * 0.20
        dist = np.sqrt((cv.X - hx) ** 2 + (cv.Y - hy) ** 2) / max(r, 1.0)
        hot = np.clip(1.0 - dist, 0.0, 1.0) ** 2.1
        cv.over(np.array([1.0, 1.0, 1.0], dtype=np.float32),
                hot * mask * (0.26 if CUTS[cut]["mode"] == "orb" else 0.34))
    else:
        # Uncut rock: no polish, so only a weak ambient rim.
        rim = np.asarray(shade(base, 1.30, 0.70)[:3], dtype=np.float32) / 255.0
        gs.inner_glow(cv, mask, rim, width=scale * 0.075, strength=0.30,
                      direction=(-0.60, -0.78))

    # Outline last, and NOT uniform: it thins to nothing on the lit edge so the
    # stone catches light instead of sitting in a cartoon keyline.
    for s in sil_px:
        line = gs.stroke_mask(cv.size, s, OUTLINE_W * 1.05, feather=0.6)
        gy, gx = np.gradient(mask)
        n = np.sqrt(gx * gx + gy * gy) + 1e-6
        away = np.clip((gx / n) * 0.60 + (gy / n) * 0.78, 0.0, 1.0)
        cv.over(ink, line * (0.66 + 0.34 * away))

    if sparkle:
        sx, sy = cx + hw * 0.56, cy - hh * 0.62
        r = scale * 0.26
        d = np.sqrt(((cv.X - sx) / r) ** 2 + ((cv.Y - sy) / r) ** 2)
        star = np.clip(1.0 - d, 0.0, 1.0) ** 1.6
        arms = (np.exp(-((cv.X - sx) / (r * 0.13)) ** 2)
                + np.exp(-((cv.Y - sy) / (r * 0.13)) ** 2))
        cv.over(np.array([1.0, 1.0, 1.0], dtype=np.float32),
                np.clip(star * arms, 0.0, 1.0) * 0.9)

    return mask


def setting_claws(cv, mask, cx: float, cy: float, hw: float, hh: float,
                  metal: str, tier_index: int, count: int = 4) -> None:
    """Metal claws drawn IN FRONT of a stone, plus the shadow they cast on it.

    A stone is only "set" when metal crosses over its edge. Everything else --
    a cup behind it, a band under it -- still reads as two objects placed near
    each other.
    """
    dark, light = METALS[metal]
    d0 = np.asarray(hsv(*dark)[:3], dtype=np.float32) / 255.0
    d1 = np.asarray(hsv(*light)[:3], dtype=np.float32) / 255.0
    deep = np.asarray(hsv(dark[0], dark[1], dark[2] * 0.35)[:3],
                      dtype=np.float32) / 255.0
    r = max(hw, hh)
    for i in range(count):
        a = math.pi * (0.25 + 0.5 * i)
        px_, py_ = cx + math.cos(a) * hw * 0.86, cy + math.sin(a) * hh * 0.86
        w = r * (0.20 + 0.02 * tier_index)
        claw = [(px_ - w, py_ - w * 1.25), (px_ + w, py_ - w * 1.25),
                (px_ + w * 0.72, py_ + w * 1.25), (px_ - w * 0.72, py_ + w * 1.25)]
        m = gs.poly_mask(cv.size, claw, feather=1.0)
        gs.shadow(cv, m, offset=(r * 0.05, r * 0.06), blur=r * 0.09,
                  strength=0.5)
        cv.over(deep, gs.stroke_mask(cv.size, claw, OUTLINE_W * 0.9))
        lit = 1.0 - (i in (1, 2)) * 0.45
        cv.over(d0 + (d1 - d0) * lit, m)
        gs.inner_glow(cv, m, np.clip(d1 * 1.25, 0, 1), width=r * 0.07,
                      strength=0.8, direction=(-0.6, -0.78))


def draw_geode(cv, cx: float, cy: float, hw: float, hh: float) -> None:
    """A cracked stone with a crystal-lined cavity.

    Not a cut at all -- it is the raw nugget with a hole bitten out of it and
    the four skilling gems glinting inside, which is the only icon in the set
    that shows more than one stone. That is the point: a geode is a handful of
    gems you have not seen yet.
    """
    draw_stone(cv, "raw", "geode_rock", cx, cy, hw, hh, matte=True)

    # the cavity, punched into the upper-right of the rock face
    ox, oy = cx + hw * 0.16, cy - hh * 0.10
    rx, ry = hw * 0.62, hh * 0.58
    hole = [(ox + math.cos(t) * rx * (0.86 + 0.18 * math.sin(t * 3.0)),
             oy + math.sin(t) * ry * (0.88 + 0.14 * math.cos(t * 2.0)))
            for t in np.linspace(0, 2 * math.pi, 40, endpoint=False)]
    mask = gs.poly_mask(cv.size, hole, feather=1.0)
    cv.over(np.array([0.05, 0.03, 0.07], dtype=np.float32), mask)
    gs.inner_glow(cv, mask, np.array([0.16, 0.12, 0.20], dtype=np.float32),
                  width=hw * 0.10, strength=0.9, direction=(-0.6, -0.78))

    # crystals growing out of the cavity wall, one per skilling gem
    spots = [(-0.34, 0.18, 0.30, "sapphire_gem"), (0.26, -0.26, 0.26, "ruby_gem"),
             (0.30, 0.34, 0.24, "emerald_gem"), (-0.18, -0.38, 0.22, "diamond_gem")]
    for dx, dy, size, pal in spots:
        draw_stone(cv, "princess", pal, ox + rx * dx, oy + ry * dy,
                   rx * size, ry * size)


def render(cut: str, palette: str, *, metal: str | None = None,
           tier_index: int = 0, sparkle: bool = False,
           matte: bool = False, canvas=None,
           at=None) -> Image.Image:
    """One loose gem, optionally sitting in a Slayer metal setting.

    [param canvas] / [param at] let a caller (the jewellery tool) draw this
    stone into ITS buffer at its own place and scale, instead of receiving a
    finished 64px image it could only paste.
    """
    own = canvas is None
    cv = gs.Canvas(C) if own else canvas
    cx, cy, hw, hh = at if at else (CENTRE[0], CENTRE[1], HALF_W, HALF_H)

    if metal:
        inset = 0.84
        dark, light = METALS[metal]
        rx = hw * 1.02
        ry = hh * 1.00
        half = (2.1 + 0.55 * tier_index) * SS
        gs.shadow(cv, gs.poly_mask(cv.size, [
            (cx - rx, cy - ry), (cx + rx, cy - ry),
            (cx + rx, cy + ry), (cx - rx, cy + ry)], feather=rx * 0.5),
            offset=(SS * 0.6, SS * 0.9), blur=SS * 1.6, strength=0.30)
        band = gs.band_shade(cv, cx, cy, rx, ry, half,
                             np.asarray(hsv(*dark)[:3], np.float32) / 255.0,
                             np.asarray(hsv(*light)[:3], np.float32) / 255.0)
        deep = np.asarray(hsv(dark[0], dark[1], dark[2] * 0.30)[:3],
                          np.float32) / 255.0
        cv.over(deep, gs.stroke_mask(cv.size, [
            (cx + math.cos(t) * (rx + half), cy + math.sin(t) * (ry + half))
            for t in np.linspace(0, 2 * math.pi, 72, endpoint=False)],
            OUTLINE_W * 0.7) * 0.85)
        studs = (0, 2, 3, 4)[tier_index]
        for i in range(studs):
            a = -math.pi / 2.0 + 2.0 * math.pi * i / max(studs, 1) + math.pi / 4.0
            sx2, sy2 = cx + math.cos(a) * rx, cy + math.sin(a) * ry
            sr = 2.4 * SS
            gs.band_shade(cv, sx2, sy2, sr, sr, sr * 0.9,
                          np.asarray(hsv(*dark)[:3], np.float32) / 255.0,
                          np.asarray(hsv(*light)[:3], np.float32) / 255.0)
        hw, hh = hw * inset, hh * inset
        # No claws here on purpose. A Slayer gem's band is a TIER FRAME, not a
        # jewellery setting -- the stone is not lying in its plane -- and claws
        # crossing it just smothered the stone that carries the identity.
        # Instead the stone is drawn large enough to break the band's inner
        # edge and casts onto it, which joins the two without hiding either.
        # Real claws live in build_gem_jewelry_icons.py, where they belong.
        probe = gs.poly_mask(cv.size, [
            (cx + math.cos(t) * hw, cy + math.sin(t) * hh)
            for t in np.linspace(0, 2 * math.pi, 40, endpoint=False)],
            feather=1.0)
        gs.shadow(cv, probe, offset=(SS * 0.7, SS * 1.0), blur=SS * 2.0,
                  strength=0.45)
        draw_stone(cv, cut, palette, cx, cy, hw, hh, matte=matte,
                   sparkle=sparkle)
    elif cut == "geode":
        draw_geode(cv, cx, cy, hw, hh)
    else:
        draw_stone(cv, cut, palette, cx, cy, hw, hh, matte=matte,
                   sparkle=sparkle)

    return cv.image(SIZE) if own else None


# --------------------------------------------------------------------------
# who gets what
# --------------------------------------------------------------------------
# Ladder position comes from vendor_value, which is an exact tier proxy for all
# three combat families (12/16/20/24/28/32, six rungs, no gaps).
LADDER_CUTS = ("cushion", "emerald", "trillion", "marquise", "brilliant", "star")

LADDERS = {
    # role -> (hue family, gems in vendor_value order)
    "amber": ("fittings", ["basilisk", "wyrmguard", "godsteel", "colossus",
                           "behemoth", "worldbreaker"]),
    "arcane": ("arcane foci", ["runewoven", "astral", "voidsilk", "aetherborn",
                               "empyrean", "primordial"]),
    "hunter": ("hunter", ["wraithsilk", "nightglass", "tempest", "skyrender",
                          "eclipse", "starfall"]),
}

# The nine one-off armour/jewellery gems. Hue is taken from the gem's own
# description, so nothing here is an invention: "blood-red", "coal-red",
# "violet", "Silver", "Pale", "sapphire-dark", "seawater", "green-blue",
# "Ancient green".
BESPOKE = {
    "dragon":    ("kite", "blood"),
    "ember":     ("shard", "coal"),
    "phantom":   ("cluster", "violet"),
    "enchanted": ("orb", "turquoise"),
    "covenant":  ("obelisk", "silver"),
    "oath":      ("hexagon", "ivory"),
    "sirenic":   ("pear", "sapphire"),
    "tideglass": ("barrel", "tide"),
    "verdance":  ("heart", "moss"),
}

# Slayer: cut+hue say WHICH STAT, the metal setting says WHICH QUALITY -- and
# the metal is the one the item's own description tells you to forge it into.
SLAYER_STATS = {
    "vital": ("heart", "vital"),
    "agile": ("marquise", "agile"),
    "focus": ("kite", "focus"),
    "guard": ("cushion", "guard"),
}
SLAYER_TIERS = ("low", "medium", "high", "pristine")
SLAYER_METALS = ("copper", "iron", "silver", "gold")

# The Crafting skilling line: mine an uncut stone, cut it (Crafting XP), set it
# into a Smithing-made band (more Crafting XP). All four share the princess cut
# so the family reads as one; uncut is the SAME hue rendered matte, so a player
# pairs the rough stone with its cut form on sight.
SKILLING_GEMS = ("sapphire", "emerald", "ruby", "diamond")


def plan() -> dict[str, dict]:
    """slug -> {file, cut, palette, ...} for all 43 gems."""
    out: dict[str, dict] = {}
    for family, (role, gems) in LADDERS.items():
        for i, gem in enumerate(gems):
            out[f"{gem}_gem"] = dict(
                png=f"gem_{gem}.png", cut=LADDER_CUTS[i],
                palette=f"{family}_{i + 1}", note=f"{role} tier {i + 1}/6",
            )
    for gem, (cut, pal) in BESPOKE.items():
        out[f"{gem}_gem"] = dict(png=f"gem_{gem}.png", cut=cut, palette=pal,
                                 note="bespoke")
    out["rough_geode"] = dict(png="gem_rough_geode.png", cut="geode",
                              palette="geode_rock", note="skilling / geode")
    for gem in SKILLING_GEMS:
        out[f"{gem}_uncut"] = dict(png=f"gem_uncut_{gem}.png", cut="raw",
                                   palette=f"{gem}_gem", matte=True,
                                   note="skilling / uncut")
        out[f"{gem}_cut"] = dict(png=f"gem_cut_{gem}.png", cut="princess",
                                 palette=f"{gem}_gem", note="skilling / cut")
    for stat, (cut, pal) in SLAYER_STATS.items():
        for i, tier in enumerate(SLAYER_TIERS):
            out[f"gem_{stat}_{tier}"] = dict(
                png=f"gem_slayer_{stat}_{tier}.png", cut=cut, palette=pal,
                metal=SLAYER_METALS[i], tier_index=i,
                sparkle=(i == len(SLAYER_TIERS) - 1),
                note=f"slayer {stat} / {SLAYER_METALS[i]}",
            )
    return out


def draw(spec: dict) -> Image.Image:
    return render(spec["cut"], spec["palette"], metal=spec.get("metal"),
                  tier_index=spec.get("tier_index", 0),
                  sparkle=spec.get("sparkle", False),
                  matte=spec.get("matte", False))


# --------------------------------------------------------------------------
# distinguishability check -- the whole point of the change, so it is measured
# --------------------------------------------------------------------------
SLOT_BG = (34, 30, 40)          # the bag's slot plate, roughly


def fingerprint(im: Image.Image):
    """What a player actually sees: the icon at its SMALLEST in-game size
    (32px HUD slot, NEAREST -- PixelIcon._fit), flattened onto the slot plate.
    Alpha is kept as its own plane so two gems that differ only in silhouette
    still score as different."""
    small = im.resize((32, 32), Image.NEAREST)
    flat = Image.new("RGB", (32, 32), SLOT_BG)
    flat.paste(small, (0, 0), small)
    rgb = flat.resize((12, 12), Image.BOX)
    alpha = small.getchannel("A").resize((12, 12), Image.BOX)
    return [v / 255.0 for v in rgb.tobytes()] + \
           [v / 255.0 * 1.6 for v in alpha.tobytes()]


def distance(a, b) -> float:
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)) / len(a))


def check(images: dict[str, Image.Image], top: int = 8) -> float:
    prints = {k: fingerprint(v) for k, v in images.items()}
    keys = sorted(prints)
    pairs = []
    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            pairs.append((distance(prints[a], prints[b]), a, b))
    pairs.sort()
    print("\nclosest pairs at 32px (higher = easier to tell apart):")
    for d, a, b in pairs[:top]:
        print(f"  {d:.4f}  {a:<22s} vs {b}")
    print(f"\n  worst pair {pairs[0][0]:.4f} | median {pairs[len(pairs)//2][0]:.4f}"
          f" | {len(pairs)} pairs")
    return pairs[0][0]


# --------------------------------------------------------------------------
# wiring
# --------------------------------------------------------------------------
# Godot's ResourceUID text form is base-34: 0-8 and a-y. A uid outside that
# alphabet is silently reminted on import. Nothing REFERENCES these uids (the
# gem .tres files point at their icon by path, with no uid= attribute), but a
# valid one keeps `--import` from rewriting the file we just wrote.
UID_ALPHABET = "012345678" + "abcdefghijklmnopqrstuvwxy"   # 0-8, a-y: 34 symbols


def stable_uid(rel_path: str) -> str:
    n = int(hashlib.sha256(rel_path.encode()).hexdigest(), 16)
    out = ""
    for _ in range(13):
        n, r = divmod(n, len(UID_ALPHABET))
        out += UID_ALPHABET[r]
    return "uid://" + out


def import_stub(rel_path: str) -> str:
    """Matches the params Godot already wrote for every other icon in this
    folder, so the new files import identically to their neighbours."""
    digest = hashlib.md5(rel_path.encode()).hexdigest()
    ctex = f"res://.godot/imported/{os.path.basename(rel_path)}-{digest}.ctex"
    return f'''[remap]

importer="texture"
type="CompressedTexture2D"
uid="{stable_uid(rel_path)}"
path="{ctex}"
metadata={{
"vram_texture": false
}}

[deps]

source_file="res://{rel_path}"
dest_files=["{ctex}"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
'''


def icon_uid(png: str) -> str:
    """The uid Godot minted for an icon, read back out of its `.import`.

    Load-bearing: an `ext_resource` line carrying BOTH uid and path is resolved
    by UID FIRST, so rewriting only the path silently keeps the old texture.
    That is how the Slayer rings kept their shared art through a repoint that
    looked correct in the diff. Returns "" when the icon has not been imported
    yet, and the caller then drops the uid= attribute so path wins.
    """
    imp = os.path.join(ICON_DIR, png + ".import")
    if not os.path.exists(imp):
        return ""
    m = re.search(r'^uid="(uid://[^"]+)"', open(imp, encoding="utf-8").read(),
                  re.M)
    return m.group(1) if m else ""


def point_at_icon(body: str, png: str) -> str:
    """Rewrite the first Texture2D ext_resource to point at [param png].

    A uid already on the line is SYNCED to the new icon (a stale one silently
    wins over the path — see [[godot-uid-alphabet]]); a line without one is
    left without one, because path resolution is the more robust of the two and
    several resources here deliberately rely on it. Adding uids everywhere
    would be 37 files of churn to make the fragile case more common.
    """
    m = re.search(r'\[ext_resource type="Texture2D"( uid="[^"]*")? path="[^"]+"',
                  body)
    if m is None:
        return body
    if m.group(1):
        uid = icon_uid(png)
        attr = f' uid="{uid}"' if uid else ""
    else:
        attr = ""
    return (body[:m.start()]
            + f'[ext_resource type="Texture2D"{attr} '
              f'path="res://assets/sprites/items/icons/{png}"'
            + body[m.end():])


def repoint_tres(slug: str, png: str) -> bool:
    """Point one gem resource at its own icon. Edited as TEXT on purpose --
    headless ResourceSaver strips uid= off every ext_resource it rewrites."""
    path = os.path.join(GEM_DIR, f"{slug}.tres")
    if not os.path.exists(path):
        # Art can legitimately land before the item does: the four skilling
        # gems are drawn now, and their .tres files arrive with the Crafting
        # recipe pass. Nothing to repoint yet.
        return False
    body = open(path, encoding="utf-8").read()
    new = point_at_icon(body, png)
    if new == body:
        return False
    open(path, "w", encoding="utf-8", newline="\n").write(new)
    return True


def restamp_index(slugs: set[str]) -> int:
    """Re-hash the entries whose .tres we just edited. Nothing reads `hash` at
    runtime, but leaving it stale makes the editor's index rebuild look like a
    real content change later."""
    body = open(INDEX, encoding="utf-8").read()
    hit = 0

    def fix(m: re.Match) -> str:
        nonlocal hit
        slug = m.group("slug")
        if slug not in slugs:
            return m.group(0)
        disk = os.path.join(ROOT, m.group("path")[len("res://"):])
        if not os.path.exists(disk):
            return m.group(0)
        digest = hashlib.sha256(open(disk, "rb").read()).hexdigest()
        hit += 1
        return m.group(0).replace(m.group("hash"), digest)

    body = re.sub(
        r'&"hash": "(?P<hash>[0-9a-f]{64})",\s*\n&"id": \d+,\s*\n'
        r'&"path": "(?P<path>[^"]+)",\s*\n&"slug": &"(?P<slug>[^"]+)"',
        fix, body)
    open(INDEX, "w", encoding="utf-8", newline="\n").write(body)
    return hit


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="render and score only; write nothing")
    ap.add_argument("--sheet", metavar="PNG",
                    help="also write a labelled contact sheet here")
    args = ap.parse_args()

    specs = plan()
    images = {slug: draw(spec) for slug, spec in specs.items()}
    worst = check(images)

    if args.sheet:
        contact_sheet(specs, images).save(args.sheet)
        print(f"\nsheet -> {args.sheet}")

    if args.check:
        print("\n--check: nothing written")
        return 0

    written, repointed = 0, set()
    for slug, spec in sorted(specs.items()):
        png = os.path.join(ICON_DIR, spec["png"])
        fresh = not os.path.exists(png)
        images[slug].save(png, optimize=True)
        written += 1
        if fresh:
            rel = f"assets/sprites/items/icons/{spec['png']}"
            open(png + ".import", "w", encoding="utf-8",
                 newline="\n").write(import_stub(rel))
        if repoint_tres(slug, spec["png"]):
            repointed.add(slug)

    stamped = restamp_index(repointed) if repointed else 0
    print(f"\nicons written      {written}")
    print(f"resources repointed {len(repointed)}")
    print(f"index hashes fixed  {stamped}")
    print(f"worst pair at 32px  {worst:.4f}")
    return 0


def contact_sheet(specs: dict, images: dict) -> Image.Image:
    rows = [(f"{role.upper()} t1-t6", [f"{g}_gem" for g in gems])
            for _, (role, gems) in LADDERS.items()]
    rows.append(("BESPOKE", [f"{g}_gem" for g in BESPOKE]))
    rows.append(("SKILLING uncut", [f"{g}_uncut" for g in SKILLING_GEMS]))
    rows.append(("SKILLING cut", [f"{g}_cut" for g in SKILLING_GEMS]
                 + ["rough_geode"]))
    for stat in SLAYER_STATS:
        rows.append((f"SLAYER {stat}", [f"gem_{stat}_{t}" for t in SLAYER_TIERS]))
    cw, ch, lb = 78, 96, 150
    w = lb + max(len(r[1]) for r in rows) * cw
    sheet = Image.new("RGBA", (w, len(rows) * ch), (38, 38, 46, 255))
    d = ImageDraw.Draw(sheet)
    for ri, (label, slugs) in enumerate(rows):
        y = ri * ch
        d.text((6, y + 34), label, fill=(235, 235, 240, 255))
        for ci, slug in enumerate(slugs):
            x = lb + ci * cw
            sheet.alpha_composite(images[slug], (x + 7, y + 2))
            # the 32px HUD size next to it, so the sheet shows the real worst case
            sheet.alpha_composite(
                images[slug].resize((32, 32), Image.NEAREST), (x + 23, y + 66))
            d.text((x + 2, y + 58), slug.replace("_gem", "")[:13],
                   fill=(185, 185, 196, 255))
    return sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)


if __name__ == "__main__":
    sys.exit(main())
