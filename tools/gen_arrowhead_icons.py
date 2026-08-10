#!/usr/bin/env python3
"""Draw the metal arrowhead item icons (64x64) used by the anvil recipes.

Each icon is a cluster of five arrowheads in the OSRS pose. The palette is
sampled straight out of the matching `bar_<metal>.png` icon so an arrowhead
stack always reads as the same metal as the bar it was smithed from.

Usage:  python3 tools/gen_arrowhead_icons.py
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw

ICON_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets",
    "sprites",
    "items",
    "icons",
)

METALS = ("bronze", "iron", "steel", "mithril", "adamant", "runite")

# Supersample factor. The source art in this pack is smooth-shaded 64px, so we
# draw big and box-filter down rather than aiming for chunky pixels.
SS = 8
SIZE = 64

OUTLINE = (26, 20, 16, 255)

# Apex position (x, y) and height of each arrowhead, mirroring the reference
# scatter: three across the top, one low on the right, one bottom-centre.
HEADS = (
    (10.0, 5.0, 26.0),
    (23.0, 11.0, 26.0),
    (37.0, 4.0, 26.0),
    (51.0, 16.0, 26.0),
    (30.0, 30.0, 27.0),
)


def _lum(rgb: tuple[int, int, int]) -> float:
    return 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]


def _shift(rgb: tuple[int, int, int], factor: float) -> tuple[int, int, int, int]:
    return tuple(min(255, max(0, round(c * factor))) for c in rgb) + (255,)


def sample_palette(metal: str) -> dict[str, tuple[int, int, int, int]]:
    """Light / mid / dark tones lifted from the metal's bar icon.

    The bar art is outlined in near-black, so ignore very dark pixels when
    picking tones or every metal would come out muddy.
    """
    image = Image.open(os.path.join(ICON_DIR, f"bar_{metal}.png")).convert("RGBA")
    colors = [px[:3] for px in image.getdata() if px[3] > 200 and _lum(px[:3]) > 24]
    colors.sort(key=_lum)
    pick = lambda q: colors[min(len(colors) - 1, int(len(colors) * q))]
    return {
        "light": _shift(pick(0.96), 1.0),
        "mid": _shift(pick(0.62), 1.0),
        "dark": _shift(pick(0.22), 0.92),
        "deep": _shift(pick(0.08), 0.45),
    }


def _outline_poly(points: list[tuple[float, float]], grow: float) -> list[tuple[float, float]]:
    """Scale a polygon about its centroid — cheap way to fake a stroke."""
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    out = []
    for x, y in points:
        dx, dy = x - cx, y - cy
        length = max(0.001, (dx * dx + dy * dy) ** 0.5)
        out.append((x + dx / length * grow, y + dy / length * grow))
    return out


def draw_head(
    draw: ImageDraw.ImageDraw,
    apex: tuple[float, float],
    height: float,
    palette: dict[str, tuple[int, int, int, int]],
) -> None:
    ax, ay = apex
    h = height
    w = h * 0.30  # half-width at the widest point

    def pt(rx: float, ry: float) -> tuple[float, float]:
        return ((ax + rx * w) * SS, (ay + ry * h) * SS)

    silhouette = [pt(0, 0), pt(1.0, 0.74), pt(0.72, 1.0), pt(-0.72, 1.0), pt(-1.0, 0.74)]

    draw.polygon(_outline_poly(silhouette, 1.5 * SS), fill=OUTLINE)
    draw.polygon(silhouette, fill=palette["mid"])

    # Left face catches the light, right face falls away.
    draw.polygon([pt(0, 0), pt(-1.0, 0.74), pt(-0.72, 1.0), pt(0, 1.0)], fill=palette["light"])
    draw.polygon([pt(0, 0), pt(0, 1.0), pt(0.72, 1.0), pt(1.0, 0.74)], fill=palette["dark"])

    # Hollow socket at the base, so the head reads as a cone rather than a wedge.
    draw.polygon(
        [pt(-0.72, 1.0), pt(0.72, 1.0), pt(0.92, 0.82), pt(0, 0.9), pt(-0.92, 0.82)],
        fill=palette["deep"],
    )

    # Specular sliver down the lit edge.
    draw.polygon([pt(0, 0.10), pt(-0.55, 0.74), pt(-0.30, 0.80), pt(0, 0.30)], fill=palette["light"])


def build(metal: str) -> Image.Image:
    palette = sample_palette(metal)
    canvas = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    flat = {key: (18, 14, 12, 255) for key in palette}
    for ax, ay, h in HEADS:
        draw_head(shadow_draw, (ax + 1.6, ay + 1.6), h, flat)
    shadow.putalpha(shadow.getchannel("A").point(lambda a: int(a * 0.45)))
    canvas.alpha_composite(shadow)

    draw = ImageDraw.Draw(canvas)
    for ax, ay, h in HEADS:
        draw_head(draw, (ax, ay), h, palette)

    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    for metal in METALS:
        out = os.path.join(ICON_DIR, f"mat_{metal}_arrowheads.png")
        build(metal).save(out)
        print("wrote", out)


if __name__ == "__main__":
    main()
