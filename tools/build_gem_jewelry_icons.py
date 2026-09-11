#!/usr/bin/env python3
"""Draw every piece of gem-set jewellery: the 16 Slayer rings, and the 24
gem/metal/piece combinations the Crafting gem line produces.

WHY THIS EXISTS
---------------
Two problems, one renderer.

1. The 16 Slayer rings shared FOUR images between them -- `ring_vital.png` was
   the icon for copper, iron, silver AND gold. That is the same duplicate-art
   problem tools/build_gem_icons.py just fixed on the gems, and leaving it made
   the fix look broken: the gem in your bag showed its metal tier clearly, then
   the ring you forged from it did not.

2. The Crafting gem line (mine uncut -> cut for XP -> set into a Smithing-made
   band for more XP) needs art for 4 gems x 2 metals x 3 pieces.

Both are "a stone held by a metal piece", so both come from one place. The
stone is rendered by build_gem_icons.render() -- the SAME call that draws the
loose gem -- then composited into a band, a chain or a pendant. That is the
point: a Ruby Gold Ring must carry the exact stone a player learned as a Ruby.

READING THE SET
---------------
  * METAL says the tier / value: copper, iron, silver, gold, same ramp as the
    Slayer gem settings, so a Pristine gem and the Gold ring it forges match.
  * STONE says which gem: cut and hue straight off the gem's own icon.
  * PIECE says the form, by silhouette, which is what survives a 32px HUD slot:
    ring is a closed band, necklace is a wide shallow chain with the stone set
    in it, amulet is a narrow chain with a large stone hanging BELOW it.

Usage:  python tools/build_gem_jewelry_icons.py [--check] [--sheet PNG]
"""

from __future__ import annotations

import argparse
import hashlib
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_gem_icons as gem
import gem_shading as gs

ROOT = gem.ROOT
ICON_DIR = gem.ICON_DIR
RING_DIR = os.path.join(
    ROOT, "source", "common", "gameplay", "items", "gears", "rings"
)

SIZE = gem.SIZE          # 64
SS = gem.SS              # 8
C = gem.C                # 512


def px(v: float) -> float:
    """Final-64 coordinate -> supersampled canvas coordinate."""
    return v * SS


def metal_pair(name: str):
    dark, light = gem.METALS[name]
    return gem.hsv(*dark), gem.hsv(*light), gem.hsv(dark[0], dark[1], dark[2] * 0.42)


def bezier(p0, p1, p2, steps: int = 48):
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1.0 - t
        out.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                    u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return out


def stroke(d: ImageDraw.ImageDraw, pts, colour, width: float, closed=False):
    seq = list(pts) + ([pts[0]] if closed else [])
    d.line(seq, fill=colour, width=int(width), joint="curve")


# --------------------------------------------------------------------------
# the three pieces
# --------------------------------------------------------------------------
# EVERY piece is built in one interleaved pass -- metal behind, stone, metal in
# front -- into a single shading buffer. The first version drew a finished band
# and pasted a finished stone on it, and the eye read two stickers because
# nothing ever crossed in front of the stone and nothing cast onto anything.
#
# The three rules that make a stone look SET, in order of how much they matter:
#   1. metal crossing the stone's edge (claws, a bezel lip)
#   2. a contact shadow where the stone meets that metal
#   3. one shared light, which comes free from gem_shading.LIGHT

PIECES = {
    "ring":     dict(at=(32.0, 22.5), size=28.5),
    "necklace": dict(at=(32.0, 39.5), size=25.0),
    "amulet":   dict(at=(32.0, 43.0), size=29.0),
}


def mcol(metal: str):
    dark, light = gem.METALS[metal]
    return (np.asarray(gem.hsv(*dark)[:3], np.float32) / 255.0,
            np.asarray(gem.hsv(*light)[:3], np.float32) / 255.0,
            np.asarray(gem.hsv(dark[0], dark[1], dark[2] * 0.34)[:3],
                       np.float32) / 255.0)


def metal_poly(cv, pts, metal: str, *, lit: float = 1.0,
               outline: float = 0.9) -> np.ndarray:
    """A flat metal part with a gradient and a rim, not a solid fill."""
    d0, d1, deep = mcol(metal)
    m = gs.poly_mask(cv.size, pts, feather=0.8)
    if outline > 0:
        cv.over(deep, gs.stroke_mask(cv.size, pts, gem.OUTLINE_W * outline))
    gs.fill_facet(cv, pts, np.clip(d0 + (d1 - d0) * lit, 0, 1), contrast=0.46)
    gs.inner_glow(cv, m, np.clip(d1 * 1.22, 0, 1), width=cv.size * 0.011,
                  strength=0.75, direction=(-0.6, -0.78))
    return m


def claw(cv, cx: float, cy: float, angle: float, r: float, width: float,
         metal: str, *, grip: float = 0.78) -> None:
    """One tapered prong gripping the stone's edge.

    Drawn AFTER the stone, so the tip lies OVER it -- that overlap is the whole
    trick; without it a setting is just a frame behind a gem. [param grip] is
    how far in the tip reaches as a fraction of the stone radius, and it stays
    near the rim on purpose: four prongs reaching a third of the way in meet in
    the middle and hide the thing they are holding.
    """
    ca, sa = math.cos(angle), math.sin(angle)
    tx, ty = cx + ca * r * grip, cy + sa * r * grip
    bx, by = cx + ca * r * 1.15, cy + sa * r * 1.15
    nx, ny = -sa, ca
    tip = width * 0.55
    poly = [(tx + nx * tip, ty + ny * tip), (tx - nx * tip, ty - ny * tip),
            (bx - nx * width, by - ny * width), (bx + nx * width, by + ny * width)]
    m = gs.poly_mask(cv.size, poly, feather=0.9)
    gs.shadow(cv, m, offset=(width * 0.35, width * 0.45), blur=width * 0.7,
              strength=0.62)
    lit = 1.0 - 0.42 * max(0.0, ca * 0.6 + sa * 0.78)
    metal_poly(cv, poly, metal, lit=lit, outline=0.85)


def seat(cv, cx: float, cy: float, r: float, metal: str,
         cut: str | None = None) -> None:
    """The cup the stone sits in: the stone's OWN outline, scaled out.

    A circle was the obvious choice and the wrong one -- a round collar behind
    a square princess is a circle-behind-a-shape, which is exactly the "two
    circles" read this whole ring went through four rewrites to kill. Taking
    the silhouette from the cut means the metal that shows round the gem
    follows its edge, so seat and stone are one form.
    """
    if cut is not None:
        sil = gem.facets_for(cut, gem.PALETTE["ruby_gem"], False)[0][0]
        pts = gem.frame_px(gem.scale_poly(sil, 1.0), cx, cy, r, r)
    else:
        pts = [(cx + math.cos(t) * r, cy + math.sin(t) * r * 0.96)
               for t in np.linspace(0, 2 * math.pi, 40, endpoint=False)]
    d0, d1, deep = mcol(metal)
    cv.over(deep, gs.stroke_mask(cv.size, pts, gem.OUTLINE_W * 0.9))
    gs.fill_facet(cv, pts, np.clip(d0 + (d1 - d0) * 0.46, 0, 1), contrast=0.62)


def build_ring(cv, metal: str, weight: float, cut: str, palette: str,
               style: str = "solitaire") -> None:
    """A band whose SHOULDERS rise into the setting, so band and head are one
    object rather than a circle with a gem balanced on it.

    ONE construction, two dress levels. Slayer and Crafting rings are separate
    item families and did need separating -- they scored 0.024 apart when both
    were plain solitaires -- but the fix is NOT a second construction. Four
    goes at a flush-set band (stacked ellipses, a square mount, a domed boss, a
    crown swell) all lost the same way: a band thick enough to hold the stone
    leaves the stone ~7px at HUD size, the metal dominates, and the four gems
    collapse into one icon. Measured at 0.028 -- worse than the duplicate art
    this whole set replaced.

    So both families use the raised head, which reads, and they differ by
    ORNAMENT instead:
      style="solitaire"  heavy shank, four prongs.  Slayer, bought with points.
      style="plain"      slim shank, two prongs.   Crafting, made by the thousand.
    """

    d0, d1, deep = mcol(metal)
    heavy = style == "solitaire"
    cx, cy = px(32), px(45.0 if heavy else 44.2)
    rx = px(17.4 if heavy else 15.6)
    ry = px(15.2 if heavy else 13.5)
    half = px((2.6 if heavy else 1.9) + weight * (0.8 if heavy else 0.52))

    gs.shadow(cv, gs.poly_mask(cv.size, [
        (cx - rx, cy - ry), (cx + rx, cy - ry),
        (cx + rx, cy + ry), (cx - rx, cy + ry)], feather=rx * 0.55),
        offset=(px(0.7), px(1.0)), blur=px(2.2), strength=0.30)

    spec = PIECES["ring"]
    sx = px(spec["at"][0])
    sy = px(spec["at"][1])
    sr = px(spec["size"]) * 0.5

    # shoulders: two tapered struts sweeping from the band's crown up into the
    # head, so the two are one casting rather than a gem balanced on a hoop
    for side in (-1.0, 1.0):
        w0, w1 = (px(9.8), px(15.0)) if heavy else (px(8.4), px(13.2))
        metal_poly(cv, [
            (cx + side * px(2.2), sy + sr * 0.10),
            (cx + side * w0, sy + sr * 0.46),
            (cx + side * w1, cy - ry * 0.34),
            (cx + side * px(6.0), cy - ry * 0.06),
        ], metal, lit=1.0 if side < 0 else 0.60, outline=0.8)

    gs.band_shade(cv, cx, cy, rx, ry, half, d0, d1)
    cv.over(deep, gs.stroke_mask(cv.size, [
        (cx + math.cos(t) * (rx + half), cy + math.sin(t) * (ry + half))
        for t in np.linspace(0, 2 * math.pi, 64, endpoint=False)],
        gem.OUTLINE_W * 0.75) * 0.8)

    seat(cv, sx, sy, sr * 1.26, metal, cut)
    gem.render(cut, palette, canvas=cv, at=(sx, sy, sr, sr))
    gs.shadow(cv, gs.poly_mask(cv.size, [
        (sx + math.cos(t) * sr, sy + math.sin(t) * sr)
        for t in np.linspace(0, 2 * math.pi, 32, endpoint=False)], feather=1.0),
        offset=(px(0.4), px(0.6)), blur=px(1.4), strength=0.40)
    # Four prongs on the premium piece, two on the plain one.
    angles = ([0.25, 0.75, 1.25, 1.75] if heavy else [1.22, 1.78])
    for a in angles:
        claw(cv, sx, sy, math.pi * a, sr, sr * (0.19 if heavy else 0.24), metal)


def build_necklace(cv, metal: str, weight: float, cut: str, palette: str) -> None:
    """A wide chain that TERMINATES INTO a bezel round the stone -- the chain
    ends inside the metal, it does not pass behind the gem."""
    d0, d1, deep = mcol(metal)
    spec = PIECES["necklace"]
    sx, sy = px(spec["at"][0]), px(spec["at"][1])
    sr = px(spec["size"]) * 0.5

    curve = bezier((px(5), px(12)), (px(32), px(51)), (px(59), px(12)))
    chain = px(2.4 + weight * 0.8)
    cv.over(deep, gs.stroke_mask(cv.size, curve, chain + gem.OUTLINE_W * 1.4,
                                 closed=False))
    gs.chain_shade(cv, curve, chain, d0, d1)
    for end in (curve[0], curve[-1]):
        r = px(2.2)
        gs.band_shade(cv, end[0], end[1], r, r, r * 0.85, d0, d1)

    bez = sr * 1.28
    seat(cv, sx, sy, bez, metal, cut)
    gs.shadow(cv, gs.poly_mask(cv.size, [
        (sx + math.cos(t) * bez, sy + math.sin(t) * bez)
        for t in np.linspace(0, 2 * math.pi, 32, endpoint=False)], feather=1.2),
        offset=(px(0.4), px(0.7)), blur=px(1.6), strength=0.34)
    gem.render(cut, palette, canvas=cv, at=(sx, sy, sr, sr))
    # a lip of metal over the stone's top edge, where the chain meets it
    for a in (math.pi * 0.86, math.pi * 0.14):
        claw(cv, sx, sy, a, sr, sr * 0.22, metal, grip=0.70)


def build_amulet(cv, metal: str, weight: float, cut: str, palette: str) -> None:
    """Chain into a bail, bail into a cap, cap gripping the stone. Every link
    physically overlaps the next, so the pendant hangs from the chain instead
    of floating under it -- which is exactly what the first version did."""
    d0, d1, deep = mcol(metal)
    spec = PIECES["amulet"]
    sx, sy = px(spec["at"][0]), px(spec["at"][1])
    sr = px(spec["size"]) * 0.5

    curve = bezier((px(15), px(7)), (px(32), px(27)), (px(49), px(7)))
    chain = px(2.2 + weight * 0.7)
    cv.over(deep, gs.stroke_mask(cv.size, curve, chain + gem.OUTLINE_W * 1.4,
                                 closed=False))
    gs.chain_shade(cv, curve, chain, d0, d1)

    # bail, overlapping the chain's low point
    bx, by, br = px(32), px(26.0), px(4.0)
    gs.band_shade(cv, bx, by, br, br, px(1.5), d0, d1)
    cv.over(deep, gs.stroke_mask(cv.size, [
        (bx + math.cos(t) * (br + px(1.5)), by + math.sin(t) * (br + px(1.5)))
        for t in np.linspace(0, 2 * math.pi, 40, endpoint=False)],
        gem.OUTLINE_W * 0.7) * 0.8)

    # cap: joins the bail to the stone's crown, overlapping both
    metal_poly(cv, [(bx - px(3.0), by + px(1.0)), (bx + px(3.0), by + px(1.0)),
                    (bx + px(5.2), sy - sr * 0.62), (bx - px(5.2), sy - sr * 0.62)],
               metal, lit=0.92, outline=0.85)

    seat(cv, sx, sy, sr * 1.24, metal, cut)
    gs.shadow(cv, gs.poly_mask(cv.size, [
        (sx + math.cos(t) * sr * 1.16, sy + math.sin(t) * sr * 1.16)
        for t in np.linspace(0, 2 * math.pi, 32, endpoint=False)], feather=1.2),
        offset=(px(0.4), px(0.8)), blur=px(1.8), strength=0.38)
    gem.render(cut, palette, canvas=cv, at=(sx, sy, sr, sr))
    for i in range(4):
        claw(cv, sx, sy, math.pi * (0.25 + 0.5 * i), sr, sr * 0.18, metal)


BUILD = {"ring": build_ring, "necklace": build_necklace, "amulet": build_amulet}


def render_piece(piece: str, metal: str, cut: str, palette: str,
                 weight: float = 1.0, style: str = "solitaire") -> Image.Image:
    cv = gs.Canvas(C)
    if piece == "ring":
        build_ring(cv, metal, weight, cut, palette, style=style)
    else:
        BUILD[piece](cv, metal, weight, cut, palette)
    return cv.image(SIZE)


# --------------------------------------------------------------------------
# what gets drawn
# --------------------------------------------------------------------------
JEWEL_METALS = ("silver", "gold")
PIECE_NAMES = ("ring", "necklace", "amulet")


def plan() -> dict[str, dict]:
    """slug -> spec. Slayer rings are keyed by their EXISTING item slug so they
    can be repointed; gem jewellery is keyed by the slug its item will take."""
    out: dict[str, dict] = {}

    # 16 Slayer rings: the ring's metal is the tier metal of the gem it eats,
    # so a Pristine Vital Gem and the Vital Gold Ring visibly belong together.
    for stat, (cut, palette) in gem.SLAYER_STATS.items():
        for i, metal in enumerate(gem.SLAYER_METALS):
            out[f"ring_{stat}_{metal}"] = dict(
                png=f"ring_{stat}_{metal}.png", piece="ring", metal=metal,
                cut=cut, palette=palette, weight=0.6 + 0.30 * i,
                repoint=os.path.join(RING_DIR, f"ring_{stat}_{metal}.tres"),
                note=f"slayer {stat} / {metal}",
            )

    # 24 gem jewellery pieces. No items yet — the Crafting line is a later
    # content pass — so nothing is repointed; the art just waits for them.
    for g in gem.SKILLING_GEMS:
        for metal in JEWEL_METALS:
            for piece in PIECE_NAMES:
                out[f"{g}_{metal}_{piece}"] = dict(
                    png=f"jewelry_{g}_{metal}_{piece}.png", piece=piece,
                    metal=metal, cut="princess", palette=f"{g}_gem",
                    style="plain",
                    weight=1.0 if metal == "silver" else 1.35,
                    note=f"crafting {g} / {metal} {piece}",
                )
    return out


def draw(spec: dict) -> Image.Image:
    return render_piece(spec["piece"], spec["metal"], spec["cut"],
                        spec["palette"], weight=spec.get("weight", 1.0),
                        style=spec.get("style", "solitaire"))


# --------------------------------------------------------------------------
def contact_sheet(images: dict[str, Image.Image]) -> Image.Image:
    rows = [(f"SLAYER {s}", [f"ring_{s}_{m}" for m in gem.SLAYER_METALS])
            for s in gem.SLAYER_STATS]
    for g in gem.SKILLING_GEMS:
        rows.append((g.upper(), [f"{g}_{m}_{p}" for m in JEWEL_METALS
                                 for p in PIECE_NAMES]))
    cw, ch, lb = 78, 98, 130
    w = lb + max(len(r[1]) for r in rows) * cw
    sheet = Image.new("RGBA", (w, len(rows) * ch), (34, 30, 40, 255))
    d = ImageDraw.Draw(sheet)
    for ri, (label, slugs) in enumerate(rows):
        y = ri * ch
        d.text((6, y + 36), label, fill=(238, 238, 244, 255))
        for ci, slug in enumerate(slugs):
            x = lb + ci * cw
            sheet.alpha_composite(images[slug], (x + 7, y + 2))
            sheet.alpha_composite(
                images[slug].resize((32, 32), Image.NEAREST), (x + 23, y + 68))
            d.text((x + 2, y + 60), slug.replace("ring_", "")[:13],
                   fill=(184, 184, 196, 255))
    return sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)


def repoint(path: str, png: str) -> bool:
    """Point one ring resource at its own icon, uid included.

    Text edit, because headless ResourceSaver strips uid= off every
    ext_resource it rewrites. The uid is the part that matters here — see
    build_gem_icons.point_at_icon.
    """
    if not os.path.exists(path):
        return False
    body = open(path, encoding="utf-8").read()
    new = gem.point_at_icon(body, png)
    if new == body:
        return False
    open(path, "w", encoding="utf-8", newline="\n").write(new)
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="score only, write nothing")
    ap.add_argument("--sheet", metavar="PNG")
    args = ap.parse_args()

    specs = plan()
    images = {slug: draw(spec) for slug, spec in specs.items()}
    worst = gem.check(images)

    if args.sheet:
        contact_sheet(images).save(args.sheet)
        print(f"\nsheet -> {args.sheet}")
    if args.check:
        print("\n--check: nothing written")
        return 0

    written, repointed = 0, set()
    for slug, spec in sorted(specs.items()):
        target = os.path.join(ICON_DIR, spec["png"])
        fresh = not os.path.exists(target)
        images[slug].save(target, optimize=True)
        written += 1
        if fresh:
            rel = f"assets/sprites/items/icons/{spec['png']}"
            open(target + ".import", "w", encoding="utf-8",
                 newline="\n").write(gem.import_stub(rel))
        if spec.get("repoint") and repoint(spec["repoint"], spec["png"]):
            repointed.add(slug)

    stamped = gem.restamp_index(repointed) if repointed else 0
    print(f"\nicons written       {written}")
    print(f"resources repointed {len(repointed)}")
    print(f"index hashes fixed  {stamped}")
    print(f"worst pair at 32px  {worst:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
