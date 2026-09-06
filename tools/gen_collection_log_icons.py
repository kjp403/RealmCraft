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


"""A SIGNET IS NOT A GEM RING.

Every other ring in the game is a band carrying a raised cabochon, and the first
pass at Ankhemet was a straight recolour of the Bulwark band — which left the
game's only two signets reading as the same object in two colours. Recolouring
one of them again would not have fixed that; they need different SHAPES.

So signets get their own silhouette: a broad flat seal face, engraved, sitting
squarely on the band. That is what a signet physically is — a thing you press
into wax — and at 32x32 a wide flat plate reads apart from a small raised stone
immediately, which no palette change can achieve.

Drawn here rather than recoloured, because there is no flat-faced ring anywhere
in the pack to derive one from.
"""

# The band, front to back. Index 0 is the outline.
GOLD = ["#141006", "#5c3d10", "#8f6318", "#c08f2a", "#e8bf5c", "#ffe9a8"]
STEEL = ["#0d1016", "#2c3542", "#4a5768", "#6f7d90", "#9aa7b8", "#d6dee8"]
# The seal face: dark stone with an engraved mark cut into it.
CARNELIAN = ["#3a0d05", "#6b1a0d", "#9c3117", "#c8572f"]
IRONSEAL = ["#0f141c", "#33425a", "#4d6180", "#6e83a4"]


def _ellipse(x, y, cx, cy, rx, ry) -> float:
    """Normalised radius: <1 inside, 1 on the edge."""
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2


def draw_signet(out_name: str, band, seal, mark: str) -> None:
    """A 32x32 signet: oval band below, flat engraved seal plate above.

    Shading runs from the upper-left, matching every other ring in the pack, so
    these still sit in the same light even though the shapes are new.
    """
    S = 32
    grid = [[None] * S for _ in range(S)]

    # --- band: an oval ring, open in the middle -----------------------------
    bcx, bcy, brx, bry = 15.5, 20.0, 8.0, 7.4
    for y in range(S):
        for x in range(S):
            outer = _ellipse(x, y, bcx, bcy, brx, bry)
            inner = _ellipse(x, y, bcx, bcy, brx - 3.6, bry - 3.4)
            if outer <= 1.0 and inner >= 1.0:
                # Light from the upper left, plus a darker underside so the band
                # reads as round rather than as a flat washer.
                t = 0.5 - (x - bcx) / (brx * 2.6) - (y - bcy) / (bry * 2.2)
                grid[y][x] = band[max(1, min(len(band) - 1,
                                             1 + int(t * (len(band) - 1))))]

    # --- seal plate: a flat octagon sitting ON the band ----------------------
    # NARROWER than the band, and overlapping it. A plate the same width as the
    # band reads as two stacked discs — a figure 8 — rather than as one object,
    # which is how the first version of these came out. The width difference is
    # what says "plate on top of ring".
    px0, px1, py0, py1 = 10, 21, 3, 15
    for y in range(py0, py1 + 1):
        for x in range(px0, px1 + 1):
            # Cut the corners: an octagon reads as a struck plate, a rectangle
            # reads as a UI element.
            cut = (min(x - px0, px1 - x) + min(y - py0, py1 - y)) < 2
            if cut:
                continue
            edge = (x in (px0, px0 + 1, px1 - 1, px1)
                    or y in (py0, py1))
            if edge:
                # The plate keeps a metal rim, so the stone looks set INTO it.
                t = 0.55 - (x - 15.5) / 30.0 - (y - 9.0) / 22.0
                grid[y][x] = band[max(1, min(len(band) - 1,
                                             1 + int(t * (len(band) - 1))))]
            else:
                t = 0.6 - (x - 15.5) / 26.0 - (y - 9.0) / 20.0
                # Index 0 is RESERVED for the engraving. Letting the plate's own
                # shadow reach it makes the cut invisible wherever the plate is
                # already dark, which is exactly how the first Bulwark plate came
                # out as a featureless black box.
                grid[y][x] = seal[max(1, min(len(seal) - 1,
                                             int(t * len(seal))))]

    # --- the engraving ------------------------------------------------------
    # Cut in the darkest seal tone, one pixel wide. This is the only part that
    # differs between the two signets beyond palette, and it is what a player
    # actually reads at a glance once they know both exist.
    for x, y in MARKS[mark]:
        if grid[y][x] is not None:
            grid[y][x] = seal[0]

    # --- outline ------------------------------------------------------------
    for y in range(S):
        for x in range(S):
            if grid[y][x] is not None:
                continue
            if any(0 <= x + dx < S and 0 <= y + dy < S
                   and grid[y + dy][x + dx] is not None
                   and (x + dx, y + dy) not in OUTLINED
                   for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))):
                OUTLINED.add((x, y))
    for x, y in OUTLINED:
        grid[y][x] = band[0]
    OUTLINED.clear()

    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = im.load()
    for y in range(S):
        for x in range(S):
            if grid[y][x] is not None:
                px[x, y] = hexc(grid[y][x]) + (255,)
    im.save(os.path.join(ICONS, out_name + ".png"))
    print("  %-28s drawn (band + flat seal, %s)" % (out_name + ".png", mark))


OUTLINED: set = set()

# Engravings, in plate coordinates. Ankhemet is the ankh the dunes were promised
# under; Bulwark is a tower mark.
MARKS = {
    "ankh": [(15, 6), (16, 6), (14, 7), (17, 7), (15, 8), (16, 8),
             (13, 9), (14, 9), (15, 9), (16, 9), (17, 9), (18, 9),
             (15, 10), (16, 10), (15, 11), (16, 11)],
    "tower": [(13, 6), (15, 6), (17, 6), (18, 6),
              (13, 7), (14, 7), (15, 7), (16, 7), (17, 7), (18, 7),
              (14, 8), (15, 8), (16, 8), (17, 8),
              (14, 9), (15, 9), (16, 9), (17, 9),
              (13, 10), (14, 10), (15, 10), (16, 10), (17, 10), (18, 10)],
}


def build_signets() -> None:
    draw_signet("ankhemet_signet", GOLD, CARNELIAN, "ankh")
    draw_signet("bulwark_signet", STEEL, IRONSEAL, "tower")


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
    build_signets()
    build_coal()
    print("done — run the editor once to import, then repoint the .tres files")


if __name__ == "__main__":
    main()
