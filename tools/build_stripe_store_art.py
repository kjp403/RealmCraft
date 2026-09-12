#!/usr/bin/env python3
"""Draw the four Ark Coin package tiles used as Payment Link images in Stripe.

WHY THIS EXISTS
---------------
A Stripe Payment Link has one image slot per product. Left empty, the four
packages are four identical grey placeholders distinguished only by their title
text, on a checkout page that otherwise carries none of the game's identity.

Generated rather than drawn, and generated FROM tools/build_ark_coin_icon.py
rather than from a copy of it, so the coin on the checkout page is provably the
same mark as the coin in the Vault header. A hand-made storefront image is the
kind of asset that silently stops matching the game the first time the icon is
retouched.

THE DESIGN
----------
Count is carried by the NUMBER OF COINS, not only by the numeral: one coin for
250, rising to a pile for 2500. That is the one part of the tile that still says
"this is the bigger pack" at thumbnail size, where the numeral has collapsed into
a smear - and Stripe renders this image small in the order summary as well as
large at the top of the page.

Palette is the site's: --bg-2 #10161e behind, --accent-2 #e8c56a for the numeral
(the same gold every price on the site already uses), --muted #b8c3d2 for the
label. Fonts are the site's display and UI faces, so the tile and the storefront
page read as one thing.

Square, because Stripe crops to a square thumbnail and anything else loses its
edges.

Usage:  python tools/build_stripe_store_art.py
"""

from __future__ import annotations

import importlib.util
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required:  python -m pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "previews")

# The site tokens, from website/src/styles.css. Move these when those move.
BG = (0x10, 0x16, 0x1E)
BG_EDGE = (0x09, 0x0C, 0x11)
GOLD = (0xE8, 0xC5, 0x6A)
MUTED = (0xB8, 0xC3, 0xD2)

FONT_DISPLAY = os.path.join(ROOT, "previews", "youtube", "fonts", "Jersey10-Regular.ttf")
FONT_UI = os.path.join(ROOT, "previews", "youtube", "fonts", "Silkscreen-Bold.ttf")

SIZE = 640

# Coin layout per package: (x, y, scale) in fractions of the tile, drawn in
# order so later entries sit in front. Kept as data because the only thing that
# separates these four images is how much money is on the table.
LAYOUTS: dict[int, list[tuple[float, float, float]]] = {
    250: [(0.500, 0.355, 0.440)],
    500: [(0.400, 0.330, 0.400), (0.605, 0.400, 0.400)],
    1000: [(0.355, 0.315, 0.365), (0.560, 0.290, 0.340), (0.500, 0.430, 0.400)],
    2500: [
        (0.300, 0.300, 0.330), (0.520, 0.255, 0.300), (0.700, 0.315, 0.330),
        (0.395, 0.425, 0.360), (0.615, 0.440, 0.375),
    ],
}


def _coin(px: int) -> Image.Image:
    """The real Ark Coin, re-rendered at tile resolution.

    The generator's geometry is all expressed against its own canvas, so raising
    SIZE/SS gives a faithful scale-up. OUTLINE_W is the one module-level value
    computed at import, so it has to be re-derived against the new canvas or the
    rim keeps its 64px thickness and disappears. Upscaling the finished 64px PNG
    was tried and is worse: the source is anti-aliased, so a NEAREST blow-up
    gives muddy fringes rather than crisp pixels."""
    spec = importlib.util.spec_from_file_location(
        "ark_coin_icon", os.path.join(ROOT, "tools", "build_ark_coin_icon.py")
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.SIZE, mod.SS = px, 2
    mod.C = px * 2
    mod.OUTLINE_W = mod.C / 32.0
    return mod.render()


def _fit(path: str, target_h: int) -> ImageFont.FreeTypeFont:
    """Load a font whose CAP HEIGHT is about target_h.

    Jersey 10 carries a great deal of empty space above its caps, so sizing by
    the nominal point size puts the numeral wherever the face feels like. Measure
    a digit and scale to it instead."""
    probe = ImageFont.truetype(path, 100)
    box = probe.getbbox("250")
    measured = box[3] - box[1]
    return ImageFont.truetype(path, max(8, int(100 * target_h / max(1, measured))))


def _centre(draw: ImageDraw.ImageDraw, text: str, font, cy: int, fill) -> None:
    box = draw.textbbox((0, 0), text, font=font)
    draw.text(
        (SIZE / 2 - (box[0] + box[2]) / 2, cy - (box[1] + box[3]) / 2),
        text, font=font, fill=fill,
    )


def _spaced(draw: ImageDraw.ImageDraw, text: str, font, cy: int, gap: int, fill) -> None:
    """Letter-spaced small caps, the site's .alpha treatment."""
    widths = [draw.textlength(ch, font=font) for ch in text]
    total = sum(widths) + gap * (len(text) - 1)
    x = SIZE / 2 - total / 2
    box = draw.textbbox((0, 0), text, font=font)
    for ch, w in zip(text, widths):
        draw.text((x, cy - (box[1] + box[3]) / 2), ch, font=font, fill=fill)
        x += w + gap


def tile(coins: int, coin: Image.Image) -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), BG + (255,))
    d = ImageDraw.Draw(img)

    # Vignette: a darker frame so the tile keeps an edge against Stripe's white
    # page without needing a hard border.
    for i in range(SIZE // 2):
        t = (i / (SIZE / 2)) ** 3
        d.rectangle(
            [i, i, SIZE - 1 - i, SIZE - 1 - i],
            outline=tuple(int(BG[c] + (BG_EDGE[c] - BG[c]) * (1 - t)) for c in range(3)),
        )

    # Warm glow under the coins, so gold on near-black does not look pasted on.
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gr = SIZE * 0.30
    gd.ellipse([SIZE / 2 - gr, SIZE * 0.36 - gr, SIZE / 2 + gr, SIZE * 0.36 + gr],
               fill=GOLD + (46,))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(SIZE * 0.09)))

    for fx, fy, fs in LAYOUTS[coins]:
        c = coin.resize((int(SIZE * fs), int(SIZE * fs)), Image.LANCZOS)
        img.alpha_composite(c, (int(SIZE * fx - c.width / 2), int(SIZE * fy - c.height / 2)))

    d = ImageDraw.Draw(img)
    _centre(d, str(coins), _fit(FONT_DISPLAY, int(SIZE * 0.20)), int(SIZE * 0.715), GOLD)
    _spaced(d, "ARK COINS", ImageFont.truetype(FONT_UI, int(SIZE * 0.050)),
            int(SIZE * 0.872), int(SIZE * 0.012), MUTED)
    return img


def main() -> int:
    coin = _coin(320)
    os.makedirs(OUT_DIR, exist_ok=True)
    for coins in sorted(LAYOUTS):
        path = os.path.join(OUT_DIR, "store-ark-coins-%d.png" % coins)
        tile(coins, coin).convert("RGB").save(path, quality=95)
        print("wrote", os.path.relpath(path, ROOT).replace("\\", "/"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
