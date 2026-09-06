#!/usr/bin/env python3
"""Draw the Collection Log's own item icons.

    python tools/gen_collection_log_icons.py

Five icons that were placeholders borrowed from the art pack and read wrong in
the bag:

  * Ankhemet Signet was Icon321 — a plain silver disc. It read as a coin, not a
    ring, which is the one thing a ring icon has to do.
  * Everburning Coal was Icon325 — a glowing gold disc. Also a coin.
  * Slagborn and Siltbound borrowed pack gear whose palettes sit right next to
    bronze and adamant. Hue alone was not the problem: both borrowed icons carry
    the pack's EVEN mid-value shading, and at 16x16 an even mid-value mass reads
    as "some metal armour" no matter what colour it is. So these two are rebuilt
    around CONTRAST, not hue — Slagborn is near-black basalt with molten veins,
    Siltbound is drowned navy with a pale dried-silt crust. Both now separate
    from bronze/adamant at a glance and, just as importantly, from each other.

METHOD: luminance-ramp remap of the source art, not hand-placed pixels. Every
source is an existing 8-colour pack icon; this keeps its silhouette and its
light-to-dark STRUCTURE and substitutes a new ramp, so the results still sit in
the pack's own rendering conventions instead of reading as bolted on. Same
reasoning as tools/gen_high_tier_herb_icons.py.

Sources are read, never written. Each icon is written to its own file rather
than over the pack art it derives from, so the pack stays intact and any of this
is one `git checkout` from being undone.
"""

from __future__ import annotations

import colorsys
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "assets", "sprites", "items", "icons")


def luma(c) -> float:
    return (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) / 255.0


def hexc(s: str):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def ramp_at(ramp, t: float):
    """Sample a list of (stop, '#rrggbb') at t, interpolating between stops."""
    stops = [(s, hexc(c)) for s, c in ramp]
    if t <= stops[0][0]:
        return stops[0][1]
    if t >= stops[-1][0]:
        return stops[-1][1]
    for i in range(len(stops) - 1):
        a, b = stops[i], stops[i + 1]
        if a[0] <= t <= b[0]:
            f = (t - a[0]) / (b[0] - a[0]) if b[0] > a[0] else 0.0
            return tuple(round(a[1][j] + (b[1][j] - a[1][j]) * f) for j in range(3))
    return stops[-1][1]


def remap(src_name: str, out_name: str, ramp) -> None:
    """Re-ink one icon: every opaque colour keeps its luminance ORDER but takes
    its new colour from `ramp`. Alpha is untouched, so the silhouette is exactly
    the pack's."""
    im = Image.open(os.path.join(ICONS, src_name + ".png")).convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            px[x, y] = ramp_at(ramp, luma((r, g, b))) + (a,)
    im.save(os.path.join(ICONS, out_name + ".png"))
    print("  %-28s <- %s" % (out_name + ".png", src_name))


# Stops are keyed to the SOURCE palettes' actual luminances, printed by the
# --palette flag below. Evenly spaced stops do not work here: both pack icons
# carry most of their pixels in the upper half of the range, so a ramp spread
# evenly across 0..1 hands the majority of the art to its brightest stops and
# the result comes out pale — which is exactly how the first pass of these two
# failed. Placing a stop ON each source value is what puts a chosen proportion
# of the icon in shadow.

# --- Slagborn: cooled slag with the heat still in it -------------------------
# Five basalt stops then three molten ones, so roughly three quarters of the
# icon is near-black and the heat reads as veins in it. That dark-plus-hot split
# is the separation from bronze: bronze is an EVEN mid-brown mass, and no amount
# of hue change would have fixed a value structure that matches it.
SLAG = [
    (0.04, "#08080e"), (0.11, "#141319"), (0.16, "#1d1b21"),
    (0.25, "#292429"), (0.33, "#3b3134"),
    (0.47, "#8f3d12"), (0.59, "#d4621a"), (0.77, "#ffc255"),
]

# --- Siltbound: dredged up, the silt set into it as a second metal ------------
# Drowned navy body with one dull dried-silt highlight. The highlight is
# deliberately desaturated ochre-green: adamant's greens are saturated and
# evenly lit, so muted-and-dark is what tells them apart at 16x16.
SILT = [
    (0.16, "#060c14"), (0.23, "#0d1720"), (0.29, "#142029"),
    (0.37, "#1d2d33"), (0.50, "#2d4140"), (0.61, "#4b5b4c"),
    (0.82, "#9aa07e"),
]


def build_signet() -> None:
    """Ankhemet Signet, from the Bulwark band.

    Two ramps, split by SATURATION rather than by luminance: the band is the
    pack's near-neutral metal and the gem is the one saturated element, so a
    single luminance ramp would paint the stone the same gold as the shank and
    lose the seal entirely.
    """
    band = [(0.00, "#1e1206"), (0.20, "#4a2f0d"), (0.38, "#7c5615"),
            (0.52, "#ab7c22"), (0.66, "#dcac41"), (1.00, "#f7e0a2")]
    seal = [(0.30, "#5e1710"), (0.45, "#8d2a18"), (0.65, "#c05230")]

    im = Image.open(os.path.join(ICONS, "ring_ring_bulwark.png")).convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            _, _, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            t = luma((r, g, b))
            px[x, y] = ramp_at(seal if s >= 0.55 else band, t) + (a,)
    im.save(os.path.join(ICONS, "everburn_signet_tmp.png"))
    os.replace(os.path.join(ICONS, "everburn_signet_tmp.png"),
               os.path.join(ICONS, "ankhemet_signet.png"))
    print("  %-28s <- ring_ring_bulwark (band + seal)" % "ankhemet_signet.png")


def build_coal() -> None:
    """Everburning Coal, from the ore_coal render.

    The coal is left alone; the CREVICES are lit. ore_coal is a 64x64 antialiased
    render rather than a flat pack icon, so a ramp remap would flatten its
    shading — instead the darkest interior pixels become ember and everything
    else keeps its charcoal.

    "Interior" matters: the silhouette edge is also near-black, and lighting that
    would put a glowing outline around the lump and lose the coal read entirely.
    A pixel counts as interior only when all four neighbours are opaque.
    """
    im = Image.open(os.path.join(ICONS, "ore_coal.png")).convert("RGBA")
    src = im.copy()
    sp, px = src.load(), im.load()
    w, h = im.size
    ember = [(0.000, "#3d0b04"), (0.020, "#8c2306"), (0.045, "#d95a12"),
             (0.075, "#f7a52c")]
    for y in range(h):
        for x in range(w):
            r, g, b, a = sp[x, y]
            if a < 250:
                continue
            interior = all(
                0 <= x + dx < w and 0 <= y + dy < h and sp[x + dx, y + dy][3] >= 250
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))
            )
            if not interior:
                continue
            t = luma((r, g, b))
            if t < 0.085:
                # Invert within the band: the deepest crack is the hottest, which
                # is what makes it read as light coming from inside the lump.
                px[x, y] = ramp_at(ember, 0.085 - t) + (a,)
    im.save(os.path.join(ICONS, "everburning_coal.png"))
    print("  %-28s <- ore_coal (lit crevices)" % "everburning_coal.png")


def palette(name: str) -> None:
    """Print a source icon's palette by luminance — where the ramp stops go."""
    im = Image.open(os.path.join(ICONS, name + ".png")).convert("RGBA")
    seen: dict = {}
    for y in range(im.height):
        for x in range(im.width):
            p = im.load()[x, y]
            if p[3]:
                seen[p[:3]] = seen.get(p[:3], 0) + 1
    print(name)
    for c, n in sorted(seen.items(), key=lambda kv: luma(kv[0])):
        print("   l=%.2f  #%02x%02x%02x  x%d" % (luma(c), c[0], c[1], c[2], n))


def main() -> None:
    import sys
    if "--palette" in sys.argv:
        for n in sys.argv[sys.argv.index("--palette") + 1:]:
            palette(n)
        return
    print("Collection Log icons ->", ICONS)
    remap("gear_fire_helm", "slagborn_helm", SLAG)
    remap("gear_fire_boots", "slagborn_sabatons", SLAG)
    remap("gear_enchanted_helm", "siltbound_coronet", SILT)
    remap("gear_enchanted_torso_heavy", "siltbound_plate", SILT)
    build_signet()
    build_coal()
    print("done — run the editor once to import, then repoint the .tres files")


if __name__ == "__main__":
    main()
