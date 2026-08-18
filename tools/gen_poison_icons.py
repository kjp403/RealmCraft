#!/usr/bin/env python3
"""Draw the Herblore weapon-coating icons (materials + potions).

Everything here is derived from art already in the project so the new items sit
in the same pack style as their neighbours rather than reading as bolted-on.

Potions reuse the pack's OWN size ladder instead of scaling one bottle, which
would blur the smooth shading: thin vial -> conical flask -> round flask -> wide
bottle. Only saturated pixels are hue-rotated, so the blue-grey glass, the cork
and the black/white outline stay exactly where the pack put them.

Materials are 16x16 cells out of the vegetation atlas, doubled to 32 and tinted.

Usage:  python3 tools/gen_poison_icons.py
"""

from __future__ import annotations

import colorsys
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "assets", "sprites", "items", "icons")
VEGETATION = os.path.join(
    ROOT, "assets", "sprites", "environment", "props", "vegetation.png"
)

# Neutral pixels (glass, outline, pack shading) keep their colour. Anything at
# or above this saturation is "the liquid / the plant" and gets recoloured.
SATURATION_FLOOR = 0.35

# Hue bands, in turns. Warm source hues land at the low end of the band and cool
# ones at the high end, so the pack's own light-to-dark ramp survives the
# rotation instead of flattening into one colour.
GREEN = (0.22, 0.34)
ORANGE = (0.04, 0.11)
PINK = (0.86, 0.96)
SICKLY = (0.20, 0.32)
VIOLET = (0.72, 0.85)

# name -> (source icon, hue band, saturation scale)
# The source icon is chosen for its SIZE: Icon301 is the thin vial, 302 the
# conical flask, 303 the round flask, 305 the wide bottle.
POTIONS = {
    "potion_weapon_poison.png": ("Icon301.png", GREEN, 1.0),
    "potion_weapon_poison_plus.png": ("Icon305.png", GREEN, 1.0),
    "potion_weapon_ember.png": ("Icon302.png", ORANGE, 1.0),
    "potion_weapon_salve.png": ("Icon303.png", PINK, 0.85),
}

# name -> (cell in vegetation.png, hue band, saturation scale)
# Cells picked for SILHOUETTE first, so the four read apart at bag-icon size:
# a broad cap, a bulb, a fern, a flower spike.
MATERIALS = {
    "blightspore.png": ((48, 336), SICKLY, 0.75),
    "venom_sac.png": ((0, 352), VIOLET, 1.0),
    "ember_ash.png": ((128, 272), ORANGE, 1.9),
    "fairy_dust.png": ((192, 160), PINK, 0.9),
}


def _recolour(
    image: Image.Image,
    hue_band: tuple[float, float],
    saturation_scale: float = 1.0,
) -> Image.Image:
    """Rotate every saturated pixel into [hue_band].

    Value is untouched — the source art's light-to-dark ramp IS the shading, so
    preserving it is what keeps the result looking hand-drawn rather than
    filtered.
    """
    hue_low, hue_high = hue_band
    out = Image.new("RGBA", image.size, (0, 0, 0, 0))
    src = image.load()
    dst = out.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = src[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if s < SATURATION_FLOOR:
                dst[x, y] = (r, g, b, a)
                continue
            # Source hue as a position on the warm->cool circle, measured from
            # red so a potion's orange highlights stay the LIGHT end.
            position = (h + 0.5) % 1.0
            new_h = (hue_low + (hue_high - hue_low) * position) % 1.0
            new_s = min(1.0, s * saturation_scale)
            nr, ng, nb = colorsys.hsv_to_rgb(new_h, new_s, v)
            dst[x, y] = (round(nr * 255), round(ng * 255), round(nb * 255), a)
    return out


def _write(image: Image.Image, name: str) -> None:
    image.save(os.path.join(ICON_DIR, name))
    print("wrote %s (%dx%d)" % (name, image.width, image.height))


def main() -> None:
    atlas = Image.open(VEGETATION).convert("RGBA")
    for name, (cell, band, sat) in MATERIALS.items():
        x, y = cell
        crop = atlas.crop((x, y, x + 16, y + 16)).resize((32, 32), Image.NEAREST)
        _write(_recolour(crop, band, sat), name)

    for name, (source, band, sat) in POTIONS.items():
        bottle = Image.open(os.path.join(ICON_DIR, source)).convert("RGBA")
        _write(_recolour(bottle, band, sat), name)


if __name__ == "__main__":
    main()
