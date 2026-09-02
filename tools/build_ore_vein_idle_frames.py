"""Generate the idle animation frames for the four high-tier ore veins.

`MineableNodeResource.texture` is frame 0 and `idle_frames` are frames 1..n, so
two generated frames give a three-phase cycle. The frames are derived from the
shipped vein sprite rather than drawn fresh, because they MUST stay in exact
register with it — `_tick_idle` swaps the texture in place, and a frame whose
silhouette differs by even a pixel makes the rock jitter.

What animates is the ore itself, not the rock: the bright flecks embedded in
each vein are found by luminance and then pulsed, so the stone stays put and
only the metal breathes. That is the read we want at a distance — a Celestial
vein twinkling across a dark cave is what pulls a player toward it.

    python tools/build_ore_vein_idle_frames.py
"""
import colorsys
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS = os.path.join(ROOT, "assets", "sprites", "environment", "props")

# tier -> (fraction of opaque pixels treated as ore, pulse amplitudes per frame,
#          hue rotation per frame in degrees, bleed of the pulse into neighbours)
TIERS = {
    # Dragon: embers in the rock. Strong swing, no hue shift — it is heat.
    "dragon": dict(ore_frac=0.22, pulse=(0.34, -0.16), hue=(0.0, 0.0), bleed=0.45),
    # Obsidian: glass catching what little light there is. Deliberately subtle;
    # obsidian that throbs looks radioactive rather than volcanic.
    "obsidian": dict(ore_frac=0.18, pulse=(0.20, -0.10), hue=(0.0, 0.0), bleed=0.30),
    # Celestial: a slow twinkle, the brightest of the four.
    "celestial": dict(ore_frac=0.26, pulse=(0.42, -0.18), hue=(0.0, 0.0), bleed=0.55),
    # Astralite: pulse AND drift through hue, so it never sits on one colour.
    "astralite": dict(ore_frac=0.26, pulse=(0.38, -0.14), hue=(14.0, -12.0), bleed=0.55),
}


def _luma(p):
    return (0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]) / 255.0


def _shift(rgb, gain, hue_deg):
    """Scale value and rotate hue, in HSV, clamped back into 8-bit."""
    r, g, b = [c / 255.0 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h = (h + hue_deg / 360.0) % 1.0
    v = max(0.0, min(1.0, v * (1.0 + gain)))
    # a brightening fleck also saturates a little, the way a hot coal does
    s = max(0.0, min(1.0, s * (1.0 - gain * 0.25)))
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return (round(r * 255), round(g * 255), round(b * 255))


def build(tier, cfg):
    src_path = os.path.join(PROPS, f"vein_{tier}.png")
    src = Image.open(src_path).convert("RGBA")
    w, h = src.size
    sp = src.load()

    # Rank opaque pixels by luminance; the brightest `ore_frac` are the metal.
    opaque = [(x, y) for y in range(h) for x in range(w) if sp[x, y][3] > 40]
    lums = sorted((_luma(sp[x, y]) for x, y in opaque), reverse=True)
    if not lums:
        raise SystemExit(f"vein_{tier}.png is empty")
    cut = lums[max(0, min(len(lums) - 1, int(len(lums) * cfg["ore_frac"])))]

    # Weight each pixel: 1.0 for ore, falling off for rock next to ore so the
    # pulse spills a little glow instead of stopping at a hard edge.
    weight = {}
    for x, y in opaque:
        weight[(x, y)] = 1.0 if _luma(sp[x, y]) >= cut else 0.0
    for x, y in opaque:
        if weight[(x, y)] >= 1.0:
            continue
        near = 0.0
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            near = max(near, weight.get((x + dx, y + dy), 0.0))
        if near > 0.0:
            weight[(x, y)] = cfg["bleed"]

    out_paths = []
    for i, (gain, hue) in enumerate(zip(cfg["pulse"], cfg["hue"]), start=1):
        frame = src.copy()
        fp = frame.load()
        for (x, y), wgt in weight.items():
            if wgt <= 0.0:
                continue
            r, g, b, a = sp[x, y]
            nr, ng, nb = _shift((r, g, b), gain * wgt, hue * wgt)
            fp[x, y] = (nr, ng, nb, a)
        path = os.path.join(PROPS, f"vein_{tier}_f{i}.png")
        frame.save(path)
        out_paths.append(path)
        print("wrote", os.path.relpath(path, ROOT))
    return out_paths


if __name__ == "__main__":
    for tier, cfg in TIERS.items():
        build(tier, cfg)
