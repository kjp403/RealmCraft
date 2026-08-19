#!/usr/bin/env python3
"""Draw the art the Prayer skill needs.

Three jobs:

* The skill's menu icon. The realmcraft_menu_icons pack has no prayer symbol,
  so this draws one in the pack's idiom: a bold 32x32 silhouette, flat two-tone
  fill, hard black outline, and the soft down-right drop shadow the "_shadow"
  folder is named for. An ankh rather than praying hands — hands turn to mush
  at 32px, while the ankh keeps a readable silhouette and still says
  "religion" instantly.

* The two higher bone tiers, derived from mat_bone.png so the ladder reads as
  one family: Big Bones is the same bone scaled up, Dragon Bones is scaled up
  and shifted to a cold blue.

* The prayer potion. Deliberately built off Icon304 (the bulbous round bottle)
  rather than either mana potion's silhouette (307 thin vial, 308 conical
  flask), and pushed to a true CYAN rather than mana's blue, so the two are
  never confused in a hurry.

Usage:  python3 tools/gen_prayer_assets.py
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter

import colorsys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(
    ROOT, "assets", "sprites", "ui", "menu_icons_shadow", "32px",
    "realmcraft_menu_icons", "Prayer.png",
)
ICON_DIR = os.path.join(ROOT, "assets", "sprites", "items", "icons")

# Only saturated pixels move, so glass, cork and outlines stay put. Same rule
# gen_poison_icons.py uses — keep the two in step if you touch one.
SATURATION_FLOOR = 0.35
CYAN = (0.47, 0.54)
BONE_BLUE = (0.53, 0.62)

SIZE = 32
# Supersample so the ellipse reads as a clean ring, then box-filter down. The
# pack's art is smooth-shaded rather than hard-pixel, so this matches it.
SS = 8

GOLD = (242, 193, 78, 255)
GOLD_SHADE = (198, 148, 46, 255)
OUTLINE = (26, 20, 16, 255)
SHADOW = (0, 0, 0, 110)

# Geometry in 32px space.
LOOP_CX, LOOP_CY = 16.0, 9.5
LOOP_OUTER, LOOP_INNER = 6.2, 2.9
BAR_X0, BAR_X1 = 13.4, 18.6
BAR_Y0, BAR_Y1 = 9.0, 28.0
ARM_X0, ARM_X1 = 6.6, 25.4
ARM_Y0, ARM_Y1 = 14.6, 19.4


def _draw_ankh(draw: ImageDraw.ImageDraw, fill: tuple, grow: float = 0.0,
               dx: float = 0.0, dy: float = 0.0) -> None:
    """Stamp the ankh at supersampled scale, dilated by `grow`, offset by dx/dy."""
    s = SS

    def box(x0, y0, x1, y1):
        draw.rectangle(
            [(x0 - grow + dx) * s, (y0 - grow + dy) * s,
             (x1 + grow + dx) * s, (y1 + grow + dy) * s],
            fill=fill,
        )

    # Vertical bar and cross arms.
    box(BAR_X0, BAR_Y0, BAR_X1, BAR_Y1)
    box(ARM_X0, ARM_Y0, ARM_X1, ARM_Y1)
    # Loop: an outer disc with the middle punched back out afterwards.
    r = LOOP_OUTER + grow
    cx, cy = LOOP_CX + dx, LOOP_CY + dy
    draw.ellipse([(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s], fill=fill)


def _punch_loop(draw: ImageDraw.ImageDraw, shrink: float = 0.0,
                dx: float = 0.0, dy: float = 0.0) -> None:
    s = SS
    r = LOOP_INNER - shrink
    if r <= 0:
        return
    cx, cy = LOOP_CX + dx, LOOP_CY + dy
    draw.ellipse([(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s],
                 fill=(0, 0, 0, 0))


def _layer() -> Image.Image:
    return Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))


def _recolour(image, hue_band, saturation_scale=1.0):
    """Rotate every saturated pixel into [hue_band], preserving the value ramp."""
    hue_low, hue_high = hue_band
    out = Image.new("RGBA", image.size, (0, 0, 0, 0))
    src, dst = image.load(), out.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = src[x, y]
            if a == 0:
                continue
            h, sat, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if sat < SATURATION_FLOOR:
                dst[x, y] = (r, g, b, a)
                continue
            new_h = (hue_low + (hue_high - hue_low) * ((h + 0.5) % 1.0)) % 1.0
            nr, ng, nb = colorsys.hsv_to_rgb(new_h, min(1.0, sat * saturation_scale), v)
            dst[x, y] = (round(nr * 255), round(ng * 255), round(nb * 255), a)
    return out


def _scaled(image, factor):
    """Scale about the centre, keeping the canvas size (a bigger bone in the
    same 64px cell is what makes the tier read at a glance in the bag)."""
    w, h = image.size
    big = image.resize((round(w * factor), round(h * factor)), Image.NEAREST)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(big, ((w - big.width) // 2, (h - big.height) // 2))
    return out


def _write_item(image, name):
    image.save(os.path.join(ICON_DIR, name))
    print("wrote %s (%dx%d)" % (name, image.width, image.height))


def _bones() -> None:
    bone = Image.open(os.path.join(ICON_DIR, "mat_bone.png")).convert("RGBA")
    _write_item(_scaled(bone, 1.42), "mat_big_bones.png")
    # Saturation pushed hard: the source bone is nearly grey, so a plain hue
    # rotation would leave dragon bones looking like ordinary ones.
    _write_item(_recolour(_scaled(bone, 1.42), BONE_BLUE, saturation_scale=2.6),
                "mat_dragon_bones.png")


def _altar() -> None:
    """Cut the clean stone slab out of the catacombs sheet as its own sprite.

    Region picked by scanning the sheet's left column for blobs: the band at
    y 101..128 is the only slab WITHOUT bones strewn over it, which is the one
    that reads as an altar rather than a disturbed grave.
    """
    sheet = Image.open(os.path.join(
        ROOT, "assets", "sprites", "environment", "rf_catacombs", "decorative.png"
    )).convert("RGBA")
    slab = sheet.crop((0, 101, 50, 128))
    slab = slab.crop(slab.getbbox())
    out_dir = os.path.join(
        ROOT, "assets", "sprites", "environment", "structures", "stations", "altar"
    )
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "altar.png")
    slab.save(path)
    print("wrote altar.png (%dx%d)" % (slab.width, slab.height))


def _potion() -> None:
    src = Image.open(os.path.join(ICON_DIR, "Icon304.png")).convert("RGBA")
    _write_item(_recolour(src, CYAN), "potion_prayer.png")


def main() -> None:
    _bones()
    _altar()
    _potion()

    # Outline pass: the shape dilated, filled with the outline colour. The pack
    # carries a heavy black keyline, so this is a full ~2px at final size.
    big = _layer()
    d = ImageDraw.Draw(big)
    _draw_ankh(d, OUTLINE, grow=2.0)
    _punch_loop(d, shrink=2.0)

    # Body: the shade tone at full size, then the light tone nudged up-left, so
    # what shows through along the bottom-right edge IS the shade. Classic
    # two-tone bevel — cheaper and cleaner than masking a gradient.
    body = _layer()
    db = ImageDraw.Draw(body)
    _draw_ankh(db, GOLD_SHADE)
    _punch_loop(db)
    _draw_ankh(db, GOLD, dx=-0.85, dy=-0.85)
    _punch_loop(db, shrink=-0.85, dx=-0.85, dy=-0.85)
    big.alpha_composite(body)

    icon = big.resize((SIZE, SIZE), Image.LANCZOS)

    # Drop shadow, down-right, matching the pack's "_shadow" variants.
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow.paste(SHADOW, (0, 0), icon.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(0.8))
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.alpha_composite(shadow, (2, 2))
    out.alpha_composite(icon)

    out.save(OUT)
    print("wrote %s (%dx%d)" % (os.path.basename(OUT), out.width, out.height))


if __name__ == "__main__":
    main()
