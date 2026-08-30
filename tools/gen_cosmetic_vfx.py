#!/usr/bin/env python3
"""Generate the cosmetic VFX sprite strips sold in the Horizon Collection.

Output goes to assets/sprites/vfx/cosmetics/ as 128x128 horizontal strips,
matching the convention in source/common/gameplay/combat/vfx/ (see
static_ring.tres). Run build_cosmetic_frames.py afterwards to emit the
SpriteFrames .tres + the content index.

    python tools/gen_cosmetic_vfx.py assets/sprites/vfx/cosmetics
    python tools/build_cosmetic_frames.py

A palette here is a CALLABLE, not a fixed triple -- that is what makes the
rainbow / galaxy / chromatic looks possible:

    cs(k, t) -> (core, mid, outer)

where k is a per-particle/per-segment coordinate in 0..1 and t is normalised
animation time. Constant palettes are just callables that ignore both, so the
v1 looks are preserved exactly while hue-cycling and per-particle colour
become one-liners.

Adding a line to ROSTER is a new cosmetic SKU.

ELEVEN OF THESE STRIPS ARE NO LONGER RENDERED. The six auras and five trails
listed in CosmeticPresetLibrary (source/common/gameplay/cosmetics/presets/) are
drawn at runtime as layered node trees instead -- floor shaders, particle
emitters and world-space floor marks -- because a 12-frame 128x128 sprite cannot
hold those layers or react to whether the wearer is moving. Retuning a palette
here for aura_toxic/verdant/blood/emberfrost/galaxy/gold or for
trail_toxic/blood/galaxy/gold/storm will regenerate the strip and change NOTHING
in game; the preset script for that slug is what to edit.

The strips are still generated for all of them on purpose -- the registry wants
a SpriteFrames per cosmetic, and the strip is the fallback the moment a slug is
dropped from the preset library. Everything else here (rainbow, chromatic, the
halos, flourishes and departures) is still the real, shipping art.
"""

from __future__ import annotations

import colorsys
import math
import os
import sys

import numpy as np
from PIL import Image

CELL = 128
SS = 2
S = CELL * SS
FEET_Y = 84.0
BODY_Y = 60.0


# --- Canvas ------------------------------------------------------------------

class Canvas:
    def __init__(self) -> None:
        self.rgb = np.zeros((S, S, 3), dtype=np.float32)
        self.energy = np.zeros((S, S), dtype=np.float32)
        ys, xs = np.mgrid[0:S, 0:S]
        self.xs = xs.astype(np.float32)
        self.ys = ys.astype(np.float32)

    def blob(self, cx, cy, radius, color, intensity=1.0, falloff=2.2, squash=1.0):
        if intensity <= 0.002 or radius <= 0.1:
            return
        dx = self.xs - cx * SS
        dy = (self.ys - cy * SS) * squash
        d = np.sqrt(dx * dx + dy * dy) / (radius * SS)
        m = np.clip(1.0 - d, 0.0, 1.0) ** falloff
        m *= intensity
        for c in range(3):
            self.rgb[:, :, c] += m * color[c]
        self.energy += m

    def split_blob(self, cx, cy, radius, intensity=1.0, spread=1.6, squash=1.0):
        """Prismatic aberration: white core with R/G/B fringes pulled apart.
        This is what makes 'chromatic' read as lens-split rather than rainbow."""
        self.blob(cx - spread, cy, radius, (255, 40, 60), intensity * 0.85, squash=squash)
        self.blob(cx, cy - spread * 0.5, radius, (60, 255, 90), intensity * 0.85, squash=squash)
        self.blob(cx + spread, cy, radius, (70, 90, 255), intensity * 0.85, squash=squash)
        self.blob(cx, cy, radius * 0.55, (255, 255, 255), intensity * 0.9, squash=squash)

    def to_image(self) -> Image.Image:
        a = np.clip(self.energy, 0.0, 1.0)
        safe = np.maximum(self.energy, 1e-5)[:, :, None]
        rgb = np.clip(self.rgb / safe, 0, 255)
        boost = np.clip(self.energy - 1.0, 0.0, 1.5)[:, :, None]
        rgb = np.clip(rgb + boost * 90.0, 0, 255)
        out = np.dstack([rgb, a * 255.0]).astype(np.uint8)
        return Image.fromarray(out, "RGBA").resize((CELL, CELL), Image.LANCZOS)


def ease_out(t: float) -> float:
    return 1.0 - (1.0 - t) ** 2.4


# --- Colour sources ----------------------------------------------------------

STATIC = {
    "ember":   ((255, 244, 214), (255, 148, 42),  (198, 42, 12)),
    "frost":   ((232, 250, 255), (118, 200, 255), (38, 92, 200)),
    "void":    ((242, 222, 255), (170, 92, 255),  (68, 20, 140)),
    "verdant": ((236, 255, 220), (138, 230, 108), (28, 120, 48)),
    "gold":    ((255, 250, 222), (255, 204, 88),  (188, 118, 18)),
    "blood":   ((255, 226, 226), (232, 54, 62),   (120, 8, 20)),
    "toxic":   ((238, 255, 210), (176, 255, 60),  (78, 140, 10)),
}


def _hsv(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, s, v)
    return (r * 255, g * 255, b * 255)


def const(name):
    trip = STATIC[name]
    return lambda k, t: trip


def rainbow(spread=1.0, speed=1.0):
    """Hue varies across particles (k) and drifts over time (t)."""
    def cs(k, t):
        h = (k * spread + t * speed) % 1.0
        return (_hsv(h, 0.28, 1.0), _hsv(h, 0.85, 1.0), _hsv(h, 1.0, 0.62))
    return cs


def galaxy(speed=0.35):
    """Deep-space nebula. The hue band is deliberately NARROW (indigo -> violet ->
    magenta, never reaching green) -- a wide band just reads as a second rainbow.
    Low-value outer keeps it dark and dusty rather than neon."""
    def cs(k, t):
        h = 0.74 + 0.12 * math.sin((k * 2.1 + t * speed) * math.tau)
        return (_hsv(h - 0.06, 0.12, 1.0), _hsv(h, 0.72, 0.92), _hsv(h + 0.04, 0.95, 0.34))
    return cs


def duotone(a, b, speed=1.0):
    """Two static palettes cross-faded over time -- cheap way to double the roster."""
    pa, pb = STATIC[a], STATIC[b]
    def cs(k, t):
        m = 0.5 + 0.5 * math.sin((t * speed + k * 0.5) * math.tau)
        return tuple(
            tuple(pa[i][c] * (1 - m) + pb[i][c] * m for c in range(3)) for i in range(3)
        )
    return cs


# --- Shared primitives -------------------------------------------------------

def arc_ring(c, cx, cy, r, cs, t, intensity=1.0, squash=2.3, segs=200, size=3.0):
    """Ellipse drawn as coloured segments so a colour source can vary around it.

    Segment count must be high enough that adjacent blobs overlap well past their
    falloff shoulder, otherwise the ring reads as a dotted bead chain. Per-segment
    intensity is normalised against a 72-segment reference so raising `segs` for
    smoothness does not also brighten the ring."""
    norm = 72.0 / segs
    for i in range(segs):
        k = i / segs
        ang = k * math.tau
        px = cx + math.cos(ang) * r
        py = cy + math.sin(ang) * r / squash
        core, mid, outer = cs(k, t)
        c.blob(px, py, size * 1.35, mid, 0.52 * intensity * norm)
        c.blob(px, py, size * 0.6, core, 0.50 * intensity * norm)
        c.blob(px, py, size * 3.0, outer, 0.13 * intensity * norm)


# --- Effects -----------------------------------------------------------------

def fx_aura(cs, n=12):
    frames = []
    for i in range(n):
        t = i / n
        c = Canvas()
        pulse = 0.5 + 0.5 * math.sin(t * math.tau)
        r = 30.0 + pulse * 5.0
        arc_ring(c, 64, FEET_Y, r, cs, t, 0.62 + 0.24 * pulse, size=3.0 + pulse * 1.2)
        for k in range(3):
            ang = t * math.tau + k * math.tau / 3
            hx = 64 + math.cos(ang) * r
            hy = FEET_Y + math.sin(ang) * r / 2.3
            core, mid, _ = cs((k / 3 + t) % 1.0, t)
            c.blob(hx, hy, 7.0, core, 0.7)
            c.blob(hx, hy, 13.0, mid, 0.26)
        for k in range(7):
            mt = (t + k / 7.0) % 1.0
            ang = k * 2.399 + t * 1.2
            rise = ease_out(mt)
            mx = 64 + math.cos(ang) * r * (0.75 + 0.2 * mt)
            my = FEET_Y + math.sin(ang) * r / 2.3 - rise * 34.0
            fade = math.sin(mt * math.pi) ** 0.8
            core, mid, _ = cs(k / 7.0, t)
            c.blob(mx, my, 2.6, core, 0.85 * fade)
            c.blob(mx, my, 6.5, mid, 0.35 * fade)
        frames.append(c)
    return frames


def fx_trail(cs, n=10):
    """Directional -- authored running RIGHT, mirrored via flip_h in engine."""
    frames = []
    for i in range(n):
        t = i / n
        c = Canvas()
        for k in range(11):
            mt = (t + k / 11.0) % 1.0
            back = ease_out(mt)
            mx = 70 - back * 54.0
            my = FEET_Y - math.sin(mt * math.pi) * 13.0 + math.sin(k * 1.7) * 3.5
            fade = (1.0 - mt) ** 1.15
            size = 2.6 + (1.0 - mt) * 2.6
            core, mid, outer = cs(k / 11.0, t)
            c.blob(mx, my, size, core, 1.0 * fade)
            c.blob(mx, my, size * 2.8, mid, 0.45 * fade)
            c.blob(mx, my, size * 5.0, outer, 0.18 * fade)
        for k in range(14):
            st = k / 14.0
            sx = 68 - st * 50.0
            fade = (1.0 - st) ** 1.5
            _, mid, _ = cs(st, t)
            c.blob(sx, FEET_Y + 1.0, 6.0 - st * 2.5, mid, 0.20 * fade, squash=2.4)
        core, _, _ = cs(0.0, t)
        c.blob(68, FEET_Y, 9.0, core, 0.55, squash=2.2)
        frames.append(c)
    return frames


def fx_ribbon_trail(cs, n=12):
    """Continuous wavy ribbon rather than discrete motes -- the shape that shows
    a hue sweep best, so it is the natural home for rainbow."""
    frames = []
    for i in range(n):
        t = i / n
        c = Canvas()
        SEG = 46
        for k in range(SEG):
            st = k / SEG
            sx = 70 - st * 58.0
            wave = math.sin(st * 4.4 - t * math.tau) * (3.0 + st * 7.0)
            sy = FEET_Y - 6.0 + wave
            fade = (1.0 - st) ** 0.9
            core, mid, outer = cs(st, t)
            c.blob(sx, sy, 3.4 * (1.0 - st * 0.45), core, 0.85 * fade)
            c.blob(sx, sy, 8.0 * (1.0 - st * 0.4), mid, 0.40 * fade)
            c.blob(sx, sy, 15.0, outer, 0.12 * fade)
        frames.append(c)
    return frames


def fx_galaxy_trail(cs, n=12):
    """Nebula puffs with twinkling stars scattered through them."""
    rng = np.random.default_rng(7)
    stars = rng.random((26, 3))
    frames = []
    for i in range(n):
        t = i / n
        c = Canvas()
        for k in range(11):
            mt = (t * 0.6 + k / 11.0) % 1.0
            sx = 70 - ease_out(mt) * 56.0
            sy = FEET_Y - 4.0 + math.sin(k * 2.2 + t * 2.0) * 7.0
            fade = (1.0 - mt) ** 1.1
            core, mid, outer = cs(k / 11.0, t)
            # Layered nebula: broad tint, denser body, hot filament.
            c.blob(sx, sy, 19.0 - mt * 5.0, outer, 0.50 * fade)
            c.blob(sx, sy, 11.0 - mt * 3.0, mid, 0.55 * fade)
            c.blob(sx, sy, 5.0 - mt * 1.5, core, 0.35 * fade)
        for j, (sx0, sy0, ph) in enumerate(stars):
            mt = (t * 0.7 + ph) % 1.0
            sx = 72 - float(sx0) * 62.0 - mt * 6.0
            sy = FEET_Y - 16.0 + float(sy0) * 26.0
            tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin((t * 2.4 + ph * 6.3) * math.tau))
            fade = (1.0 - mt) ** 1.2 * tw
            c.blob(sx, sy, 1.5, (255, 255, 255), 0.95 * fade)
            c.blob(sx, sy, 4.0, (200, 220, 255), 0.22 * fade)
        frames.append(c)
    return frames


def fx_chromatic_trail(_cs, n=12):
    """Prism-split motes: white cores with R/G/B fringes widening as they age."""
    frames = []
    for i in range(n):
        t = i / n
        c = Canvas()
        # Continuous split spine -- the aberration needs a solid edge to fringe,
        # otherwise the R/G/B offsets just read as loose coloured dots.
        for k in range(34):
            st = k / 34.0
            sx = 70 - st * 58.0
            sy = FEET_Y - 5.0 + math.sin(st * 3.6 - t * math.tau) * (2.5 + st * 5.0)
            fade = (1.0 - st) ** 0.95
            c.split_blob(sx, sy, 5.2 * (1.0 - st * 0.45), 0.62 * fade,
                         spread=1.1 + st * 5.0)
        for k in range(7):
            mt = (t + k / 7.0) % 1.0
            back = ease_out(mt)
            mx = 70 - back * 56.0
            my = FEET_Y - math.sin(mt * math.pi) * 14.0 + math.sin(k * 1.9) * 3.0
            c.split_blob(mx, my, 4.4 + (1 - mt) * 2.4, 0.85 * (1.0 - mt) ** 1.1,
                         spread=1.4 + back * 5.0)
        frames.append(c)
    return frames


def fx_storm_trail(cs, n=10):
    """Jagged arcs snapping between ground points -- reads as electricity."""
    rng = np.random.default_rng(11)
    frames = []
    for i in range(n):
        t = i / n
        c = Canvas()
        for arc in range(3):
            seed = rng.random(10)
            x0 = 68 - arc * 6.0
            # Interpolate along each jagged segment so bolts are continuous
            # strokes rather than a row of dots.
            pts = []
            for k in range(9):
                st = k / 8.0
                sx = x0 - st * (34.0 + arc * 7.0)
                jitter = (seed[k] - 0.5) * 15.0 * math.sin(t * math.tau + arc)
                pts.append((sx, FEET_Y - 4.0 + jitter * (0.35 + st), st))
            flicker = 0.5 + 0.5 * abs(math.sin(t * math.tau + arc * 1.7))
            for j in range(len(pts) - 1):
                (ax, ay, ast), (bx, by, _) = pts[j], pts[j + 1]
                for s in range(6):
                    f = s / 6.0
                    px, py = ax + (bx - ax) * f, ay + (by - ay) * f
                    fade = (1.0 - ast) ** 1.2 * flicker
                    core, mid, outer = cs(ast, t)
                    c.blob(px, py, 2.0, core, 0.85 * fade)
                    c.blob(px, py, 5.5, mid, 0.34 * fade)
                    c.blob(px, py, 13.0, outer, 0.12 * fade)
        frames.append(c)
    return frames


def fx_halo(cs, n=12):
    frames = []
    for i in range(n):
        t = i / n
        c = Canvas()
        rx, ry, hy = 31.0, 11.0, BODY_Y - 30.0
        _, mid0, _ = cs(0.0, t)
        c.blob(64, hy, 1.0, mid0, 0.0)
        for k in range(4):
            base = t * math.tau + k * math.tau / 4
            for tail in range(7):
                ang = base - tail * 0.15
                px = 64 + math.cos(ang) * rx
                py = hy + math.sin(ang) * ry
                depth = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(ang))
                amp = (1.0 - tail / 7.0) ** 1.4 * depth
                core, mid, outer = cs((k / 4 + tail * 0.03) % 1.0, t)
                c.blob(px, py, 3.4 - tail * 0.28, core, 1.0 * amp)
                c.blob(px, py, 9.0 - tail * 0.7, mid, 0.42 * amp)
                c.blob(px, py, 16.0 - tail * 1.2, outer, 0.14 * amp)
        frames.append(c)
    return frames


def fx_flourish(cs, n=12):
    frames = []
    for i in range(n):
        t = i / n
        c = Canvas()
        grow = ease_out(t)
        r = 8 + grow * 42
        fade = (1.0 - t) ** 1.2
        arc_ring(c, 64, FEET_Y, r, cs, t, 0.9 * fade, size=2.6)
        arc_ring(c, 64, FEET_Y, r * 0.72, cs, t + 0.3, 0.5 * fade, size=1.9)
        for k in range(8):
            ang = -t * math.tau * 0.6 + k * math.tau / 8
            tx = 64 + math.cos(ang) * r
            ty = FEET_Y + math.sin(ang) * r / 2.3
            core, mid, _ = cs(k / 8.0, t)
            c.blob(tx, ty, 3.4, core, 0.8 * fade)
            c.blob(tx, ty, 8.0, mid, 0.28 * fade)
        if t < 0.6:
            ct = 1.0 - t / 0.6
            for seg in range(7):
                core, mid, _ = cs(seg / 7.0, t)
                sy = FEET_Y - seg * 9.0
                c.blob(64, sy, 9.0 - seg * 0.7, mid, 0.30 * ct)
                c.blob(64, sy, 4.0, core, 0.34 * ct)
        frames.append(c)
    return frames


def fx_departure(cs, n=14):
    frames = []
    for i in range(n):
        t = i / n
        c = Canvas()
        if t < 0.45:
            bt = t / 0.45
            arc_ring(c, 64, FEET_Y, 6 + ease_out(bt) * 26, cs, t, 0.9 * (1 - bt), size=4.0)
            core, _, _ = cs(0.0, t)
            c.blob(64, FEET_Y, 16 * (1 - bt) + 4, core, 0.7 * (1 - bt), squash=2.0)
        if t > 0.12:
            wt = (t - 0.12) / 0.88
            head = FEET_Y - ease_out(wt) * 68.0
            fade = math.sin(min(wt, 1.0) * math.pi) ** 0.35
            for seg in range(16):
                st = seg / 16.0
                sy = head + st * 34.0
                if sy > FEET_Y:
                    continue
                sway = math.sin(wt * 5.2 + st * 3.1) * (4.0 + st * 3.2)
                girth = math.sin(min(st * 1.5, 1.0) * math.pi) * 0.75 + 0.25
                amp = (1.0 - st * 0.85) * fade
                core, mid, outer = cs(st, t)
                c.blob(64 + sway, sy, 3.2 * girth + 1.4, core, 1.0 * amp)
                c.blob(64 + sway, sy, 9.0 * girth + 2.5, mid, 0.48 * amp)
                c.blob(64 + sway, sy, 18.0 * girth + 4.0, outer, 0.16 * amp)
            for k in range(4):
                kt = (wt * 1.6 + k / 4.0) % 1.0
                sy = head + 12.0 + kt * 26.0
                if sy > FEET_Y:
                    continue
                sx = 64 + math.sin(wt * 4.0 + k * 2.1) * (7.0 + kt * 9.0)
                sa = (1.0 - kt) * fade
                core, mid, _ = cs(k / 4.0, t)
                c.blob(sx, sy, 2.0, core, 0.8 * sa)
                c.blob(sx, sy, 5.5, mid, 0.28 * sa)
        frames.append(c)
    return frames


# --- Roster ------------------------------------------------------------------
# (slug, effect fn, colour source). Adding a line here is a new shop SKU.

ROSTER = [
    # Auras
    ("aura_rainbow",        fx_aura,            rainbow(spread=1.0, speed=0.6)),
    ("aura_galaxy",         fx_aura,            galaxy()),
    ("aura_gold",           fx_aura,            const("gold")),
    ("aura_verdant",        fx_aura,            const("verdant")),
    ("aura_blood",          fx_aura,            const("blood")),
    ("aura_toxic",          fx_aura,            const("toxic")),
    ("aura_emberfrost",     fx_aura,            duotone("ember", "frost")),
    # Trails
    ("trail_rainbow",       fx_ribbon_trail,    rainbow(spread=1.1, speed=0.9)),
    ("trail_galaxy",        fx_galaxy_trail,    galaxy()),
    ("trail_chromatic",     fx_chromatic_trail, None),
    ("trail_storm",         fx_storm_trail,     const("frost")),
    ("trail_blood",         fx_trail,           const("blood")),
    ("trail_toxic",         fx_trail,           const("toxic")),
    ("trail_gold",          fx_trail,           const("gold")),
    # Halos
    ("halo_rainbow",        fx_halo,            rainbow(spread=1.0, speed=0.8)),
    ("halo_galaxy",         fx_halo,            galaxy()),
    ("halo_gold",           fx_halo,            const("gold")),
    # Flourishes / departures
    ("flourish_rainbow",    fx_flourish,        rainbow(spread=0.9, speed=0.7)),
    ("flourish_void",       fx_flourish,        const("void")),
    ("departure_galaxy",    fx_departure,       galaxy()),
    ("departure_gold",      fx_departure,       const("gold")),
]


def write_strip(frames, path):
    strip = Image.new("RGBA", (CELL * len(frames), CELL), (0, 0, 0, 0))
    for i, c in enumerate(frames):
        strip.paste(c.to_image(), (i * CELL, 0))
    strip.save(path)
    return len(frames)


def write_gif(frames, path, ground=(26, 24, 32), zoom=2):
    imgs = []
    for c in frames:
        bg = Image.new("RGBA", (CELL, CELL), ground + (255,))
        bg.alpha_composite(c.to_image())
        imgs.append(bg.convert("RGB").resize((CELL * zoom, CELL * zoom), Image.NEAREST))
    imgs[0].save(path, save_all=True, append_images=imgs[1:], duration=80, loop=0)


def main() -> None:
    outdir = sys.argv[1]
    # Preview GIFs are review aids only -- never write them next to the real
    # strips, or Godot imports them as game assets.
    previews = "--previews" in sys.argv
    os.makedirs(outdir, exist_ok=True)
    for slug, fn, cs in ROSTER:
        frames = fn(cs)
        n = write_strip(frames, os.path.join(outdir, f"{slug}.png"))
        if previews:
            write_gif(frames, os.path.join(outdir, f"{slug}.gif"))
        print(f"  {slug:<22} {n:>2} frames")
    print(f"COSMETIC_VFX_PASS variants={len(ROSTER)}")


if __name__ == "__main__":
    main()
