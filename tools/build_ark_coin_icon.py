#!/usr/bin/env python3
"""Draw the Ark Coin — the premium currency mark, for the HUD and the website.

WHY THIS EXISTS
---------------
Ark Coins shipped as a bare integer. "Balance: 4250" in a menu header is not a
currency; players cannot recognise it in a shop row, a price tag, or a web
storefront, and there is nothing to put next to a number anywhere else.

Generated rather than drawn for the same reason every other icon pack here is
(gems, abilities, UI frames): one script means the 16px HUD version and the
256px web hero are the SAME mark rather than two drawings that drift.

THE DESIGN, AND WHY IT IS THIS
------------------------------
It has to survive three sizes that are very far apart:

  * ~16px beside a balance in the Vault header
  * 32px in a shop row (PixelIcon NEAREST-downscales 64 -> 32, which throws away
    every other pixel, so nothing thinner than ~3px at 64 is real)
  * 256px+ on the storefront

So: ONE silhouette, ONE mark, no fine detail. A face-on disc reads as coinage at
any size, and face-on (not the three-quarter ellipse that looks better large)
keeps a clean circular edge when the pixels get thrown away.

Gold, because the site already spends gold on money — --accent-2 / --cat-donate
are both #e8c56a, which is what the Donate page and every price uses. A premium
currency in a NEW colour would be the only gold-adjacent thing on the site that
is not those, and would read as a different kind of value.

A SET GEM, NOT A LETTER, and that is the whole reason this version works. A
glyph identifies by SHAPE, and shape is exactly what a NEAREST halving to 16px
destroys — every letter-mark tried here collapsed into a dark smear at the size
the coin is smallest. The gem identifies by COLOUR: teal against gold is a
two-tone contrast that survives any downscale, because it does not depend on any
particular pixel surviving.

It also earns its place in the world. Gems are already a generated icon family
here (tools/build_gem_icons.py), where cut carries tier and hue carries role, so
a gem set into gold reads as "valuable thing from this game" rather than as a
logo someone put in a circle.

Teal is #5CE8F0 — the Aether vault dye, the one palette in the game that is
unmistakably arcane rather than elemental, and far enough from every gold on the
site that the two can never blur together.

Usage:  python tools/build_ark_coin_icon.py [--check]
        --check renders and reports legibility at 16/32/64 without writing.
"""

from __future__ import annotations

import argparse
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required:  python -m pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Where the icon lands. Two copies on purpose: the game reads the first, the
# website build copies the second. One generator, so they cannot drift.
GAME_OUT = os.path.join(ROOT, "assets", "sprites", "ui", "ark_coin.png")
WEB_OUT = os.path.join(ROOT, "website", "src", "ark-coin.png")

SIZE = 64
SS = 8                      # supersample, Lanczos'd down like the gem pack
C = SIZE * SS

# Matches --accent-2 / --cat-donate in website/src/styles.css. If that token
# ever moves, move this with it.
GOLD_LIGHT = (0xF6, 0xDF, 0x9A)
GOLD = (0xE8, 0xC5, 0x6A)
GOLD_MID = (0xC9, 0xA1, 0x45)
GOLD_DEEP = (0x8E, 0x6C, 0x22)
OUTLINE = (0x2A, 0x1E, 0x08)

# The set stone. Matches VaultSkins.STYLE_AETHER (#5ce8f0); the deep tone is the
# same hue dropped in value, so the girdle reads as one stone in shadow rather
# than as two colours side by side.
GEM = (0x5C, 0xE8, 0xF0)
GEM_DEEP = (0x1E, 0x6E, 0x86)
GEM_LIGHT = (0xC4, 0xF7, 0xFB)

# ~2px of rim at 64, so ~1px survives the drop to 32.
OUTLINE_W = 2.0 * SS


def _disc(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill) -> None:
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def _gem(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float) -> None:
    """A set stone: girdle, body, and one bright table facet.

    A rhombus rather than a rounded stone because four straight edges and two
    points stay recognisable when the pixel grid gets coarse - a circle inside a
    circle just reads as a blob. Narrower than it is tall so it cannot be
    mistaken for a square turned 45 degrees."""
    draw.polygon(
        [(cx, cy - r), (cx + r * 0.78, cy), (cx, cy + r), (cx - r * 0.78, cy)],
        fill=GEM_DEEP,
    )
    draw.polygon(
        [(cx, cy - r * 0.72), (cx + r * 0.56, cy), (cx, cy + r * 0.72), (cx - r * 0.56, cy)],
        fill=GEM,
    )
    # Table facet, up and left with the coin's own light. Small on purpose: at
    # 16px it merges into the body and the stone just reads a shade lighter,
    # which is the right way for it to fail.
    draw.polygon(
        [
            (cx, cy - r * 0.52),
            (cx + r * 0.26, cy - r * 0.10),
            (cx, cy + r * 0.06),
            (cx - r * 0.26, cy - r * 0.10),
        ],
        fill=GEM_LIGHT,
    )


def render() -> Image.Image:
    img = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    cx = cy = C / 2
    r_outer = C * 0.46

    # Body + outline.
    _disc(d, cx, cy, r_outer, OUTLINE)
    _disc(d, cx, cy, r_outer - OUTLINE_W, GOLD_MID)

    # Milled rim: a ring inset from the edge, the thing that most says "coin".
    r_rim = r_outer - OUTLINE_W * 2.4
    _disc(d, cx, cy, r_rim, GOLD)
    d.ellipse(
        [cx - r_rim, cy - r_rim, cx + r_rim, cy + r_rim],
        outline=GOLD_DEEP, width=int(OUTLINE_W * 0.55),
    )

    # Face, very slightly lifted toward the top-left so the coin has a light
    # direction consistent with the rest of the pack.
    r_face = r_rim - OUTLINE_W * 0.9
    _disc(d, cx, cy, r_face, GOLD)
    _disc(d, cx - r_face * 0.10, cy - r_face * 0.10, r_face * 0.86, GOLD_LIGHT)
    _disc(d, cx, cy, r_face * 0.80, GOLD)

    # A one-step shadow under the stone so it sits IN the coin rather than
    # floating on the face.
    _disc(d, cx, cy + C * 0.008, r_face * 0.76, GOLD_DEEP)
    _gem(d, cx, cy, r_face * 0.72)

    # Two diagonal streaks, same highlight language as the gem pack.
    gloss = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    gd.line(
        [(cx - r_face * 0.62, cy - r_face * 0.18), (cx - r_face * 0.16, cy - r_face * 0.70)],
        fill=(255, 255, 255, 120), width=int(OUTLINE_W * 1.15),
    )
    gd.line(
        [(cx - r_face * 0.34, cy + r_face * 0.10), (cx - r_face * 0.10, cy - r_face * 0.18)],
        fill=(255, 255, 255, 70), width=int(OUTLINE_W * 0.7),
    )
    gloss = gloss.filter(ImageFilter.GaussianBlur(SS * 0.7))
    # Clipped to the face, or the streaks hang off the rim into the alpha.
    mask = Image.new("L", (C, C), 0)
    ImageDraw.Draw(mask).ellipse(
        [cx - r_face, cy - r_face, cx + r_face, cy + r_face], fill=255
    )
    img = Image.alpha_composite(img, Image.composite(gloss, Image.new("RGBA", (C, C), (0, 0, 0, 0)), mask))

    return img.resize((SIZE, SIZE), Image.LANCZOS)


def check(icon: Image.Image) -> None:
    """Report how much of the mark survives each size it has to work at."""
    print("Ark Coin legibility")
    for size, how in ((64, Image.LANCZOS), (32, Image.NEAREST), (16, Image.NEAREST)):
        small = icon.resize((size, size), how)
        alpha = small.getchannel("A")
        covered = sum(1 for p in alpha.getdata() if p > 128)
        rgb = small.convert("RGB")
        pixels = [rgb.getpixel((x, y)) for x in range(size) for y in range(size)
                  if alpha.getpixel((x, y)) > 128]
        if not pixels:
            print(f"  {size:>3}px  EMPTY")
            continue
        spread = max(max(p) - min(p) for p in pixels)
        print(f"  {size:>3}px  {covered:>4} solid px, contrast range {spread:>3}"
              f"  {'ok' if covered > size and spread > 40 else 'WEAK'}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="render and report legibility without writing")
    args = ap.parse_args()

    icon = render()
    check(icon)
    if args.check:
        return 0

    for path in (GAME_OUT, WEB_OUT):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        icon.save(path)
        print("wrote", os.path.relpath(path, ROOT).replace("\\", "/"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
