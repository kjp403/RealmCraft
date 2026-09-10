"""Draw the Fillet Knife and the Bottomless Bait Bucket inventory icons.

LEGIBILITY FIRST, MATERIAL SECOND — the same rule build_high_tier_tool_art.py
states. At 32x32 in a bag grid the only thing the art has to communicate is WHAT
THE OBJECT IS. Both of these previously shipped as borrowed sprites (a stack of
bronze arrowheads for the knife, a potion vial for the bucket) and neither read
as its item for even a moment.

So each silhouette is built from primitives and then depth-shaded, rather than
recoloured from an existing icon:

    Fillet knife   long narrow blade angled up-right to a point, a bright spine
                   and a dark bolster separating it from a wooden handle. The
                   blade is deliberately thin — a fat blade reads as a cleaver.
    Bait bucket    a wooden pail, wider at the rim than the base, banded top and
                   bottom with iron and carried by an arc handle. Two bait curls
                   poke over the rim, which is what stops it reading as a plain
                   bucket prop.

    python tools/build_angler_icons.py
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "items", "icons")

SIZE = 32

# dark -> light, sampled by how deep a pixel sits inside its shape.
STEEL = [(28, 32, 42), (72, 82, 98), (126, 138, 156), (186, 198, 214), (238, 246, 255)]
WOOD = [(38, 24, 14), (74, 48, 26), (110, 74, 40), (146, 104, 60), (178, 134, 84)]
IRON = [(26, 26, 30), (58, 58, 66), (92, 94, 104), (132, 136, 148), (176, 182, 196)]
BAIT = [(74, 16, 12), (128, 32, 20), (184, 58, 32), (222, 96, 52), (250, 152, 96)]
# Cut fish flesh: salmon pink with a pale fatty edge, deliberately NOT the red of
# a whole shrimp so a chunk never reads as a small animal.
FLESH = [(96, 38, 40), (150, 66, 62), (198, 104, 92), (232, 150, 132), (252, 206, 188)]
OUTLINE = (14, 12, 18)


def _mask(draw_fn):
    """Run draw_fn against a 1-bit canvas and return the set of filled pixels."""
    im = Image.new("1", (SIZE, SIZE), 0)
    draw_fn(ImageDraw.Draw(im))
    px = im.load()
    return {(x, y) for y in range(SIZE) for x in range(SIZE) if px[x, y]}


def shade(cells, ramp, outline=OUTLINE):
    """Depth from distance to the silhouette edge, plus a key light from the
    upper-left, then a 1px keyline. Lifted from build_high_tier_tool_art so the
    two sets of tool art sit in the same light."""
    im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    if not cells:
        return im
    px = im.load()
    for (x, y) in cells:
        d = 1
        while d < 4:
            ring = [(x + dx, y + dy)
                    for dx in range(-d, d + 1) for dy in range(-d, d + 1)
                    if max(abs(dx), abs(dy)) == d]
            if any(q not in cells for q in ring):
                break
            d += 1
        depth = min(1.0, (d - 1) / 2.0)
        lit = ((x - 1, y) not in cells) or ((x, y - 1) not in cells)
        dark = ((x + 1, y) not in cells) or ((x, y + 1) not in cells)
        idx = 1 + int(round(depth * 2))
        if lit and d == 1:
            idx = min(len(ramp) - 1, idx + 2)
        elif dark and d == 1:
            idx = max(0, idx - 1)
        px[x, y] = ramp[min(idx, len(ramp) - 1)] + (255,)

    # 1px keyline around the whole shape so it holds against any bag background.
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    op = out.load()
    for (x, y) in cells:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (x + dx, y + dy)
                if q not in cells and 0 <= q[0] < SIZE and 0 <= q[1] < SIZE:
                    op[q] = outline + (255,)
    out.alpha_composite(im)
    return out


def build_knife():
    # Blade: a long thin wedge running lower-left to upper-right, tip at (27, 4).
    blade = _mask(lambda d: d.polygon(
        [(27, 4), (24, 4), (11, 17), (11, 20), (14, 20)], fill=1))
    # Spine highlight — the top edge of the blade only, so the steel reads as
    # having a flat back and a cutting edge rather than being a symmetrical spike.
    spine = _mask(lambda d: d.line([(25, 5), (12, 18)], fill=1, width=1))
    bolster = _mask(lambda d: d.polygon([(13, 17), (10, 20), (12, 22), (15, 19)], fill=1))
    handle = _mask(lambda d: d.polygon(
        [(11, 20), (4, 26), (3, 28), (6, 29), (14, 22)], fill=1))

    blade -= bolster
    handle -= bolster

    im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    im.alpha_composite(shade(handle, WOOD))
    im.alpha_composite(shade(blade, STEEL))
    im.alpha_composite(shade(bolster, IRON))
    # Spine last and unshaded: one bright line is what sells "sharp" at this size.
    sp = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    spp = sp.load()
    for p in spine & blade:
        spp[p] = STEEL[-1] + (255,)
    im.alpha_composite(sp)
    return im


def build_bucket():
    # Pail: wider at the rim than the base so it reads as a bucket and not a box.
    body = _mask(lambda d: d.polygon(
        [(7, 12), (25, 12), (22, 28), (10, 28)], fill=1))
    rim = _mask(lambda d: d.polygon([(6, 10), (26, 10), (26, 13), (6, 13)], fill=1))
    foot = _mask(lambda d: d.polygon([(10, 26), (22, 26), (22, 28), (10, 28)], fill=1))
    handle = _mask(lambda d: d.arc([(7, 2), (25, 16)], start=180, end=360, fill=1))
    body -= rim
    body -= foot

    # Bait over the rim — the detail that names the item. Two curls, offset so
    # they do not read as a single blob at 1:1.
    bait = _mask(lambda d: (d.arc([(10, 5), (16, 11)], start=200, end=20, fill=1),
                            d.arc([(17, 6), (22, 11)], start=210, end=30, fill=1)))
    bait = {p for p in bait if p[1] <= 11}

    im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    im.alpha_composite(shade(handle, IRON))
    im.alpha_composite(shade(bait, FLESH))  # the bucket shows the bait it holds
    im.alpha_composite(shade(body, WOOD))
    im.alpha_composite(shade(rim, IRON))
    im.alpha_composite(shade(foot, IRON))

    # Stave seams: two darker verticals, so the body is planks and not a bag.
    px = im.load()
    for x in (13, 19):
        for y in range(14, 27):
            if px[x, y][3]:
                r, g, b, a = px[x, y]
                px[x, y] = (max(0, r - 34), max(0, g - 24), max(0, b - 14), a)
    return im


def build_bait():
    """Chunks of cut fish, not a whole one.

    This shipped as a copy of the Raw Shrimp icon, which put the SAME sprite on
    two different rows of the Fillet panel — the row you cut from and the row you
    get. Bait is what filleting produces, so it is drawn as offcuts: four
    irregular pieces at different sizes and angles, each with a pale edge where
    the knife went through.
    """
    pieces = [
        [(6, 17), (13, 14), (16, 19), (9, 23)],
        [(15, 12), (22, 10), (25, 15), (18, 18)],
        [(17, 19), (24, 18), (25, 24), (18, 25)],
        [(9, 24), (15, 22), (16, 27), (10, 28)],
    ]
    im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    for poly in pieces:
        cells = _mask(lambda d, q=poly: d.polygon(q, fill=1))
        im.alpha_composite(shade(cells, FLESH))
    return im


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn in (("tool_fillet_knife", build_knife),
                     ("tool_bait_bucket", build_bucket),
                     ("mat_fish_bait", build_bait)):
        path = os.path.join(OUT_DIR, name + ".png")
        fn().save(path)
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
