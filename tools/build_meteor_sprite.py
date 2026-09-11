#!/usr/bin/env python3
"""Draw the Starfall Meteor world prop and its two idle frames.

WHY THIS IS NOT THE ICON GENERATOR
----------------------------------
World props are a different art problem from the 64px item icons: they are
small pixel art (the ore veins are 30x45 to 36x47), drawn with hard pixel edges
and a soft outer glow, and they sit in a lit scene rather than on a slot plate.
Running the smooth, rim-lit icon renderer at that size produces something that
reads as a sticker pasted into the world -- which is why the vein shipped on a
borrowed `vein_celestial.png` rather than a mismatched bespoke sprite.

So this draws at 1:1 with NEAREST scaling and no antialiasing on the rock
itself, matching the pack. Only the glow is blurred, because the pack's veins
glow that way too.

WHAT MAKES IT READ AS A FALLEN STAR RATHER THAN A ROCK
------------------------------------------------------
Three things, in order of how much they carry:
  * the SILHOUETTE is asymmetric and scorched -- a lopsided lump with a flatter
    impact face, not the tidy upright lozenge every ore vein uses;
  * GLOWING FISSURES run through it, brightest at the core, so the light is
    coming from inside the rock rather than off its surface;
  * GEMS sit in those fissures in the four skilling colours, which is the only
    prop in the game showing all four, and tells a player what it pays without
    a tooltip.

Idle frames pulse the fissures and glow, not the rock, so the animation reads
as something still cooling.

Usage:  python tools/build_meteor_sprite.py
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites", "environment", "props")

W, H = 38, 46
SS = 6                       # draw big, snap down with NEAREST for hard pixels

# Matched to the pack's own veins, which are CHUNKY and high contrast: a solid
# body, a bright rim, and a few big readable blobs. The first pass was a dark
# lump with spidery cracks and it read as mush beside celestial and astralite.
INK = (18, 15, 28, 255)          # outline, near-black
ROCK_DARK = (46, 41, 66, 255)    # shadow side
ROCK_MID = (78, 72, 106, 255)    # body
ROCK_LIT = (118, 112, 152, 255)  # lit face, upper-left
ROCK_RIM = (176, 180, 214, 255)  # hard rim along the lit edge
CRATER = (38, 33, 54, 255)

FISSURE_MID = (120, 198, 255, 255)
FISSURE_CORE = (238, 250, 255, 255)
GLOW = (120, 190, 255)

# the four skilling gems, so the prop says what it pays without a tooltip
GEMS = [(88, 126, 250, 255), (66, 210, 112, 255),
        (234, 72, 88, 255), (222, 238, 255, 255)]

# Built as OVERLAPPING LUMPS, like every vein in the pack. A single smooth
# polygon read as an egg, and with the fissures branching symmetrically off a
# central stem the gems landed as two eyes and a nose — it looked like a skull.
# Lumps give the irregular, stacked outline the pack actually uses, and nothing
# below is left/right symmetric.
BODY_LUMPS = [                                  # (cx, cy, rx, ry)
    (19, 31, 15.0, 11.5),                       # broad base, spread on impact
    (13, 19, 10.5, 9.5),                        # upper-left mass
    (26, 20, 7.5, 7.0),                         # smaller shoulder, right
    (21, 39, 9.0, 5.5),                         # skirt where it struck
]
LIT_LUMPS = [(13, 17, 8.0, 6.5), (24, 17, 5.0, 4.2)]
SHADOW_LUMPS = [(22, 38, 10.0, 5.0), (29, 28, 5.5, 6.0)]
CRATERS = [(8, 28, 2.4), (27, 33, 2.0), (17, 12, 1.7)]
# One long fissure running corner to corner, one short spur. Diagonal on
# purpose: a vertical stem down the middle is what built the face.
FISSURES = [
    [(9, 12), (16, 22), (22, 28), (26, 38)],
    [(16, 22), (8, 26)],
]
GEM_AT = [(16, 22, 0), (26, 38, 1), (8, 26, 2), (22, 28, 3)]


def _odd(v: float) -> int:
    k = max(3, int(round(v)))
    return k if k % 2 else k + 1


def _poly(d, pts, fill, scale=SS):
    d.polygon([(x * scale, y * scale) for x, y in pts], fill=fill)


def _line(d, pts, fill, width, scale=SS):
    d.line([(x * scale, y * scale) for x, y in pts], fill=fill,
           width=int(width * scale), joint="curve")


def frame(pulse: float) -> Image.Image:
    """[param pulse] 0..1 — how hot the fissures burn this frame. Only the light
    animates; a cooling rock should not wobble."""
    big = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)

    # The body is the UNION of its lumps, so the outline follows the whole
    # stack rather than any one of them. Drawn into a mask first, dilated for
    # the ink rim, then filled — a per-lump stroke would leave seams where the
    # lumps overlap.
    mask = Image.new("L", (W * SS, H * SS), 0)
    md = ImageDraw.Draw(mask)
    for cx, cy, rx, ry in BODY_LUMPS:
        md.ellipse([(cx - rx) * SS, (cy - ry) * SS,
                    (cx + rx) * SS, (cy + ry) * SS], fill=255)
    rim = mask.filter(ImageFilter.MaxFilter(_odd(2.0 * SS)))
    big.paste(INK, (0, 0), rim)
    big.paste(ROCK_MID, (0, 0), mask)

    for lumps, colour in ((SHADOW_LUMPS, ROCK_DARK), (LIT_LUMPS, ROCK_LIT)):
        sub = Image.new("L", (W * SS, H * SS), 0)
        sd = ImageDraw.Draw(sub)
        for cx, cy, rx, ry in lumps:
            sd.ellipse([(cx - rx) * SS, (cy - ry) * SS,
                        (cx + rx) * SS, (cy + ry) * SS], fill=255)
        big.paste(colour, (0, 0), Image.composite(
            sub, Image.new("L", sub.size, 0), mask))

    for cx, cy, r in CRATERS:
        d.ellipse([(cx - r) * SS, (cy - r * 0.74) * SS,
                   (cx + r) * SS, (cy + r * 0.74) * SS], fill=CRATER)

    for pts in FISSURES:
        _line(d, pts, FISSURE_MID, 1.6)
        _line(d, pts, FISSURE_CORE, 0.7)

    for gx, gy, gi in GEM_AT:
        r = 2.3
        d.ellipse([(gx - r) * SS, (gy - r) * SS, (gx + r) * SS, (gy + r) * SS],
                  fill=INK)
        r = 1.9
        d.ellipse([(gx - r) * SS, (gy - r) * SS, (gx + r) * SS, (gy + r) * SS],
                  fill=GEMS[gi])
        d.ellipse([(gx - r * 0.5) * SS, (gy - r * 0.62) * SS,
                   (gx + r * 0.22) * SS, (gy - r * 0.02) * SS],
                  fill=(255, 255, 255, 225))

    # hard rim along the lit lumps' upper-left arcs
    for cx, cy, rx, ry in LIT_LUMPS:
        d.arc([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS],
              start=175, end=335, fill=ROCK_RIM, width=int(0.8 * SS))

    rock = big.resize((W, H), Image.NEAREST)

    lit = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lit)
    for pts in FISSURES:
        _line(ld, pts, (*GLOW, 255), 2.4)
    for gx, gy, gi in GEM_AT:
        r = 2.6
        ld.ellipse([(gx - r) * SS, (gy - r) * SS, (gx + r) * SS, (gy + r) * SS],
                   fill=(*GLOW, 255))
    halo = lit.resize((W, H), Image.BILINEAR).filter(
        ImageFilter.GaussianBlur(2.4))
    halo.putalpha(halo.getchannel("A").point(
        lambda v: int(v * (0.40 + 0.36 * pulse))))

    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(halo)
    out.alpha_composite(rock)
    return out


def main() -> int:
    for name, pulse in (("vein_starfall_meteor.png", 0.35),
                        ("vein_starfall_meteor_f1.png", 0.75),
                        ("vein_starfall_meteor_f2.png", 1.0)):
        frame(pulse).save(os.path.join(OUT, name), optimize=True)
        print("wrote", name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
