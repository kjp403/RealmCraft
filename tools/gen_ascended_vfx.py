#!/usr/bin/env python3
"""VFX overlays for the existing Ascended weapons.

No new weapon art. Each of the 34 Ascended icons is already hand-drawn and
already carries a strong accent colour, so the effect is DERIVED from the art:

  * accent palette      -> sampled from the weapon's own most saturated pixels,
                           so a red sword burns red and a blue one burns blue
                           with zero per-weapon authoring
  * long axis           -> principal component of the silhouette, which finds
                           the blade direction whether the art is a diagonal
                           sword, a bow arc, or a hammer head
  * rim                 -> boundary pixels, used for the edge shimmer
  * head                -> the densest end of the axis, where flares anchor

Everything is drawn in the icon's OWN 32x32 diagonal space, padded out to 48x48.
Weapon.apply_skin rotates square icons -45 degrees and the overlay is a child of
the same node, so it inherits that rotation and stays aligned for free.

Output per weapon:  <slug>_fx.png  = 48x48 x N-frame strip (transparent).

    python tools/gen_ascended_vfx.py assets/sprites/vfx/weapon_fx
    python tools/build_weapon_fx_frames.py
"""

from __future__ import annotations

import colorsys
import glob
import math
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "assets", "sprites", "items", "weapons", "ascension")
CELL = 48            # padded canvas so light can spill past the 32px art
ART = 32
PAD = (CELL - ART) // 2
SS = 3
FRAMES = 10


def analyse(img):
    """Pull accent colour, long axis, rim and head out of the artwork itself."""
    px = img.load()
    pts, cols = [], []
    for y in range(ART):
        for x in range(ART):
            r, g, b, a = px[x, y]
            if a < 40:
                continue
            pts.append((x, y))
            cols.append((r, g, b))
    if not pts:
        return None

    # Accent: average the most saturated, reasonably bright pixels.
    scored = []
    for (r, g, b) in cols:
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        scored.append((s * (0.4 + v), (r, g, b), h, s, v))
    scored.sort(key=lambda t: -t[0])
    top = scored[:max(4, len(scored) // 6)]
    hs = [t[2] for t in top]
    # Circular mean of hue so red-ish wrap-around does not average to cyan.
    ang = math.atan2(sum(math.sin(h * math.tau) for h in hs),
                     sum(math.cos(h * math.tau) for h in hs))
    hue = (ang / math.tau) % 1.0
    sat = min(1.0, sum(t[3] for t in top) / len(top) * 1.15)

    def mk(s_mul, v):
        r, g, b = colorsys.hsv_to_rgb(hue, min(1.0, sat * s_mul), v)
        return (r * 255, g * 255, b * 255)

    accent = {
        "core": mk(0.18, 1.0),   # near-white hot centre
        "mid":  mk(0.85, 1.0),
        "deep": mk(1.0, 0.62),
    }

    arr = np.array(pts, dtype=np.float32)
    centre = arr.mean(axis=0)
    cov = np.cov((arr - centre).T)
    vals, vecs = np.linalg.eigh(cov)
    axis = vecs[:, int(np.argmax(vals))]      # unit vector along the weapon
    proj = (arr - centre) @ axis

    # Head = the end of the axis with more mass near it.
    lo, hi = proj.min(), proj.max()
    mass_hi = float((proj > hi * 0.55).sum())
    mass_lo = float((proj < lo * 0.55).sum())
    head_t = hi if mass_hi >= mass_lo else lo
    head = centre + axis * head_t

    solid = set(pts)
    rim = [p for p in pts
           if any((p[0] + dx, p[1] + dy) not in solid
                  for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    return {"pts": pts, "rim": rim, "centre": centre, "axis": axis,
            "proj": proj, "lo": lo, "hi": hi, "head": head, "accent": accent}


class Glow:
    def __init__(self):
        self.rgb = np.zeros((CELL * SS, CELL * SS, 3), dtype=np.float32)
        self.energy = np.zeros((CELL * SS, CELL * SS), dtype=np.float32)
        ys, xs = np.mgrid[0:CELL * SS, 0:CELL * SS]
        self.xs = xs.astype(np.float32); self.ys = ys.astype(np.float32)

    def blob(self, cx, cy, r, color, inten, falloff=2.2):
        if inten <= 0.002 or r <= 0.05:
            return
        dx = self.xs - cx * SS; dy = self.ys - cy * SS
        d = np.sqrt(dx * dx + dy * dy) / (r * SS)
        m = np.clip(1.0 - d, 0.0, 1.0) ** falloff * inten
        for c in range(3):
            self.rgb[:, :, c] += m * color[c]
        self.energy += m

    def image(self):
        a = np.clip(self.energy, 0.0, 1.0)
        safe = np.maximum(self.energy, 1e-5)[:, :, None]
        rgb = np.clip(self.rgb / safe, 0, 255)
        boost = np.clip(self.energy - 1.0, 0.0, 1.6)[:, :, None]
        rgb = np.clip(rgb + boost * 95.0, 0, 255)
        return Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8),
                               "RGBA").resize((CELL, CELL), Image.LANCZOS)


def frame(info, f):
    g = Glow()
    ph = f / FRAMES
    A = info["accent"]
    core, mid, deep = A["core"], A["mid"], A["deep"]
    ax, ay = float(info["axis"][0]), float(info["axis"][1])
    perp = (-ay, ax)

    # 1. Soft body bloom, so the whole weapon sits in its own light.
    for i, (x, y) in enumerate(info["pts"]):
        if i % 4:
            continue
        g.blob(PAD + x + 0.5, PAD + y + 0.5, 7.0, deep, 0.075)

    # 2. Rim shimmer travelling along the axis.
    lo, hi = info["lo"], info["hi"]
    band = lo + (1.0 - ph) * (hi - lo)
    rim_set = info["rim"]
    cen = info["centre"]
    for (x, y) in rim_set:
        t = (x - cen[0]) * ax + (y - cen[1]) * ay
        d = abs(t - band)
        if d < 5.0:
            amp = (1.0 - d / 5.0) ** 1.4
            g.blob(PAD + x + 0.5, PAD + y + 0.5, 2.4, core, 0.55 * amp)
            g.blob(PAD + x + 0.5, PAD + y + 0.5, 5.5, mid, 0.22 * amp)

    # 3. Head flare, breathing.
    hx, hy = info["head"]
    breathe = 0.5 + 0.5 * math.sin(ph * math.tau)
    g.blob(PAD + hx, PAD + hy, 5.0 + breathe * 2.0, core, 0.45)
    g.blob(PAD + hx, PAD + hy, 11.0 + breathe * 3.0, mid, 0.30)
    g.blob(PAD + hx, PAD + hy, 20.0, deep, 0.14)

    # 4. Motes shed perpendicular to the blade, so they read at any aim angle.
    for k in range(7):
        kt = (ph * 1.15 + k / 7.0) % 1.0
        t = lo + (hi - lo) * ((k * 0.19) % 1.0)
        bx = cen[0] + ax * t
        by = cen[1] + ay * t
        side = -1 if k % 2 else 1
        mx = bx + perp[0] * side * (2.0 + kt * 10.0)
        my = by + perp[1] * side * (2.0 + kt * 10.0)
        fade = (1.0 - kt) ** 1.25
        g.blob(PAD + mx, PAD + my, 1.7, core, 0.9 * fade)
        g.blob(PAD + mx, PAD + my, 4.6, mid, 0.30 * fade)
    return g.image()


def main():
    out = sys.argv[1]
    only = sys.argv[2].split(",") if len(sys.argv) > 2 else None
    os.makedirs(out, exist_ok=True)
    files = sorted(glob.glob(os.path.join(SRC, "*.png")))
    made = 0
    for path in files:
        slug = os.path.basename(path)[:-4]
        if only and slug not in only:
            continue
        art = Image.open(path).convert("RGBA")
        info = analyse(art)
        if info is None:
            print(f"  SKIP {slug} (empty)")
            continue
        strip = Image.new("RGBA", (CELL * FRAMES, CELL), (0, 0, 0, 0))
        for f in range(FRAMES):
            strip.paste(frame(info, f), (f * CELL, 0))
        strip.save(os.path.join(out, f"{slug}_fx.png"))
        made += 1
    print(f"ASCENDED_VFX built={made}")


if __name__ == "__main__":
    main()
