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

So: ONE silhouette, ONE glyph, no fine detail. A face-on disc reads as coinage at
any size, and face-on (not the three-quarter ellipse that looks better large)
keeps a clean circular edge when the pixels get thrown away.

Gold, because the site already spends gold on money — --accent-2 / --cat-donate
are both #e8c56a, which is what the Donate page and every price uses. A premium
currency in a NEW colour would be the only gold-adjacent thing on the site that
is not those, and would read as a different kind of value.

The glyph is an angular "A": two legs and a crossbar, 4px thick at 64 so it
survives the halving. Deliberately not the project icon — that is a detailed
mark that turns to mush below 32px.

Stamped, not printed: the glyph is cut INTO the coin as a darker inset with a
light top edge, so it reads as struck metal rather than a sticker. That is what
keeps it looking like currency instead of a logo in a circle.

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

# ~2px of rim at 64, so ~1px survives the drop to 32.
OUTLINE_W = 2.0 * SS


def _disc(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill) -> None:
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def _glyph_a(draw: ImageDraw.ImageDraw, cx: float, cy: float, h: float, w: float, fill) -> None:
    """An angular A: two splayed legs and a crossbar. No counter (the triangular
    hole) — at 32px it fills in anyway, and leaving it out means the shape is the
    same at every size instead of degrading into a blob."""
    half = w * 0.5
    top = cy - h * 0.5
    bottom = cy + h * 0.5
    stroke = w * 0.30

    draw.line([(cx, top), (cx - half, bottom)], fill=fill, width=int(stroke), joint="curve")
    draw.line([(cx, top), (cx + half, bottom)], fill=fill, width=int(stroke), joint="curve")
    # Crossbar low enough to leave the apex readable when the legs thicken.
    bar_y = cy + h * 0.16
    bar_half = half * 0.52
    draw.line([(cx - bar_half, bar_y), (cx + bar_half, bar_y)], fill=fill, width=int(stroke * 0.9))
    # Round the apex so the two legs read as one joined stroke at small sizes.
    _disc(draw, cx, top, stroke * 0.5, fill)


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

    # The glyph, struck in: dark body with a light top edge one step up, which is
    # what sells "pressed into metal" rather than "drawn on top of".
    gh = r_face * 1.02
    gw = r_face * 0.92
    _glyph_a(d, cx, cy + C * 0.012, gh, gw, GOLD_DEEP)
    _glyph_a(d, cx, cy - C * 0.004, gh, gw, GOLD_LIGHT)
    _glyph_a(d, cx, cy + C * 0.004, gh, gw, GOLD_MID)

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
