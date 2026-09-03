"""Generate the 9-slice pixel-art UI frames used by the Daily Skilling Board and
the chest reward window.

    python tools/build_ui_frames.py

Writes into assets/sprites/ui/frames/. GENERATED — never hand-edit the PNGs;
edit this and re-run, the same way ability icons are built (see
tools/build_ability_icons.py).

Why generated rather than authored: these are structural frames, not
illustration. Every one is the same construction — a 1px black keyline, a 2px
body, a lit top-left bevel, a shadowed bottom-right bevel, corner rivets — and
the only thing that varies is a four-colour ramp. Authoring nine of those by
hand guarantees they drift out of alignment with each other; generating them
guarantees they don't, and a new frame is four colours.

Every frame is 24x24 with an 8px 9-slice margin, so the 8x8 centre tiles and the
corners never stretch. All art is on a strict 1px grid at 1x — these must be
drawn with NEAREST filtering and never scaled by a non-integer factor.

Also builds the three radial pieces of the HUD XP tracker (xp_casing,
xp_arc_fill, xp_spark). Those are not 9-slice — they are a fixed-diameter gauge
— but they belong here for the same reason as the frames: the casing's notches
and the fill band have to sit on exactly the same ring, and two files drawn by
hand at different times will not. Change XP_DIAMETER or the radii and all three
re-cut together. The GDScript reads the same numbers back out of
XpTrackerHud.CASING_* — keep the two in step.
"""

import math
import os

from PIL import Image, ImageDraw

OUT = "assets/sprites/ui/frames"
SIZE = 24          # texture is SIZE x SIZE
MARGIN = 8         # 9-slice margin; centre is SIZE - 2*MARGIN
RIVET = True

# name -> (keyline, dark body, mid body, lit bevel, interior fill)
# Kept as an explicit ramp per frame so a designer can retint one frame without
# touching the construction below.
RAMPS = {
    # Carved stone — the main window/card frame. Cool grey-brown, matte.
    "frame_stone": ((10, 11, 15), (54, 52, 60), (78, 76, 86), (116, 114, 124), (26, 28, 36)),
    # Dark iron — inner tiles and list rows. Nearly black, hard highlight.
    "frame_iron":  ((8, 9, 12),   (34, 36, 44), (52, 55, 66), (86, 92, 108), (18, 20, 26)),
    # Gold trim — completed / celebrated states.
    "frame_gold":  ((28, 18, 6),  (122, 82, 20), (176, 128, 34), (240, 204, 96), (48, 38, 20)),
    # Parchment — the difficulty badges on the board.
    "frame_parchment": ((38, 28, 18), (140, 116, 82), (176, 152, 112), (222, 206, 170), (200, 182, 144)),
    # Difficulty accents, so a badge reads at a glance before you read the word.
    "frame_easy":  ((10, 24, 12), (38, 82, 40), (60, 122, 58), (116, 190, 104), (22, 34, 24)),
    "frame_medium":((32, 24, 4),  (128, 96, 20), (176, 136, 32), (238, 196, 88), (38, 32, 18)),
    "frame_hard":  ((34, 10, 10), (124, 40, 36), (168, 62, 56), (232, 118, 108), (40, 22, 22)),
    # Rare drop outline — animated by modulating this frame's colour.
    "frame_rare":  ((14, 20, 34), (40, 74, 128), (62, 108, 176), (128, 186, 246), (20, 28, 44)),
}


def frame(ramp):
    """One 9-slice frame: keyline, body, bevels, rivets, interior."""
    key, dark, mid, lit, fill = ramp
    im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    last = SIZE - 1

    # Interior first; the border is drawn over its edges.
    d.rectangle([3, 3, last - 3, last - 3], fill=fill + (255,))

    # 1px outer keyline — what separates the panel from whatever is behind it.
    d.rectangle([0, 0, last, last], outline=key + (255,))
    # 2px body ring.
    d.rectangle([1, 1, last - 1, last - 1], outline=mid + (255,))
    d.rectangle([2, 2, last - 2, last - 2], outline=dark + (255,))

    # Carved depth: light along the top/left of the body, shadow bottom/right.
    d.line([(1, 1), (last - 1, 1)], fill=lit + (255,))
    d.line([(1, 1), (1, last - 1)], fill=lit + (255,))
    d.line([(2, last - 1), (last - 1, last - 1)], fill=key + (255,))
    d.line([(last - 1, 2), (last - 1, last - 1)], fill=key + (255,))
    # Inner lip, reversed, so the interior reads as recessed.
    d.line([(3, 3), (last - 3, 3)], fill=key + (255,))
    d.line([(3, 3), (3, last - 3)], fill=key + (255,))

    if RIVET:
        for (rx, ry) in [(3, 3), (last - 4, 3), (3, last - 4), (last - 4, last - 4)]:
            d.rectangle([rx, ry, rx + 1, ry + 1], fill=lit + (255,))
            d.point((rx, ry), fill=(255, 255, 255, 210))
    return im


def bar_track():
    """Progress-bar track: a recessed 8px-tall channel."""
    w, h = 24, 10
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w - 1, h - 1], fill=(12, 13, 18, 255))
    d.rectangle([0, 0, w - 1, h - 1], outline=(6, 6, 9, 255))
    d.line([(1, 1), (w - 2, 1)], fill=(26, 28, 38, 255))     # inner top shadow
    d.line([(1, 2), (w - 2, 2)], fill=(20, 22, 30, 255))
    d.line([(1, h - 2), (w - 2, h - 2)], fill=(46, 50, 64, 255))
    return im


def bar_fill():
    """Progress-bar fill: a lit top line, a mid body and a dark base, plus a
    1px inner highlight — the detail that makes a bar read as a solid object
    rather than a coloured rectangle. Tinted per difficulty at runtime via
    modulate, so this stays neutral white-ish."""
    w, h = 24, 10
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w - 1, h - 1], fill=(188, 188, 188, 255))
    d.line([(0, 0), (w - 1, 0)], fill=(104, 104, 104, 255))     # top keyline
    d.line([(0, 1), (w - 1, 1)], fill=(255, 255, 255, 255))     # inner highlight
    d.line([(0, 2), (w - 1, 2)], fill=(230, 230, 230, 255))     # highlight falloff
    d.line([(0, h - 1), (w - 1, h - 1)], fill=(78, 78, 78, 255))  # base shadow
    d.line([(0, h - 2), (w - 1, h - 2)], fill=(132, 132, 132, 255))
    return im


def slot():
    """Item slot: a dark recessed square with a lit lip, for reward rows and the
    inventory grid."""
    n = 20
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, n - 1, n - 1], fill=(22, 24, 31, 255))
    d.rectangle([0, 0, n - 1, n - 1], outline=(8, 9, 12, 255))
    d.line([(1, 1), (n - 2, 1)], fill=(14, 15, 20, 255))
    d.line([(1, 1), (1, n - 2)], fill=(14, 15, 20, 255))
    d.line([(1, n - 2), (n - 2, n - 2)], fill=(48, 52, 64, 255))
    d.line([(n - 2, 1), (n - 2, n - 2)], fill=(48, 52, 64, 255))
    return im


# --- Radial XP tracker ------------------------------------------------------
# One ring, three textures, all cut from these numbers. The gauge is drawn at 1x
# and integer-scaled by the HUD; anything else resamples the notches into mush.
XP_DIAMETER = 48    # texture is XP_DIAMETER x XP_DIAMETER
XP_R_OUT = 23.0     # outer edge of the ring band
XP_R_IN = 17.0      # inner edge of the ring band
# Fractions of a full lap that get a notch carved through the casing. Quarters:
# the whole point is to read "about two thirds to the next level" at a glance
# without counting anything, and quarters are the finest division that stays
# instantly countable.
XP_NOTCHES = (0.25, 0.50, 0.75)
XP_NOTCH_HALF_WIDTH = 0.016   # half-width of a notch, in laps (~5.8 degrees)

# Cold gunmetal, lit from the top-left like every other frame in this file.
XP_CASING_RAMP = (
    (6, 7, 10),        # keyline
    (34, 36, 44),      # shadowed body
    (58, 62, 74),      # mid body
    (92, 98, 116),     # lit body
    (140, 148, 172),   # specular
)


def _ring_geometry(x, y):
    """Pixel centre -> (radius, lap) where lap is 0..1 clockwise from the top.

    Clockwise-from-top matches TextureProgressBar's FILL_CLOCKWISE with
    radial_initial_angle 0, so a notch at lap 0.25 lands exactly where the arc
    reads 25%. Deriving both from one function is what keeps them aligned.
    """
    c = (XP_DIAMETER - 1) / 2.0
    dx = x - c
    dy = y - c
    r = math.hypot(dx, dy)
    lap = (math.atan2(dx, -dy) / (2.0 * math.pi)) % 1.0
    return r, lap


def _in_notch(lap):
    for at in XP_NOTCHES:
        d = abs(((lap - at + 0.5) % 1.0) - 0.5)
        if d <= XP_NOTCH_HALF_WIDTH:
            return True
    return False


def xp_casing():
    """Dark metallic ring the XP arc fills, notched at the quarter marks.

    Banded rather than smoothly shaded: four flat steps of the ramp, picked by
    how much each pixel faces the top-left light. A smooth gradient would dither
    against the pixel font sitting next to it.
    """
    key, dark, mid, lit, spec = XP_CASING_RAMP
    im = Image.new("RGBA", (XP_DIAMETER, XP_DIAMETER), (0, 0, 0, 0))
    px = im.load()
    inv_root2 = 1.0 / math.sqrt(2.0)
    for y in range(XP_DIAMETER):
        for x in range(XP_DIAMETER):
            r, lap = _ring_geometry(x, y)
            if r > XP_R_OUT or r < XP_R_IN - 1.0:
                continue
            # Keylines on both edges of the band, and through each notch, so the
            # gauge stays legible against a bright map as well as a dark one.
            if r > XP_R_OUT - 1.0 or r < XP_R_IN or _in_notch(lap):
                px[x, y] = key + (255,)
                continue
            c = (XP_DIAMETER - 1) / 2.0
            nx = (x - c) / max(r, 0.001)
            ny = (y - c) / max(r, 0.001)
            face = (-(nx) - (ny)) * inv_root2        # 1 facing top-left, -1 away
            if face > 0.55:
                px[x, y] = spec + (255,)
            elif face > 0.05:
                px[x, y] = lit + (255,)
            elif face > -0.5:
                px[x, y] = mid + (255,)
            else:
                px[x, y] = dark + (255,)
    return im


def xp_arc_fill():
    """The band the arc reveals as XP is earned.

    Near-white on purpose: TextureProgressBar's tint_progress MULTIPLIES this,
    and the HUD swaps that tint per skill, so any colour baked in here would
    drag every skill's arc toward it. The only shaping is a brighter inner
    lip, which reads as a lit channel once tinted.
    """
    im = Image.new("RGBA", (XP_DIAMETER, XP_DIAMETER), (0, 0, 0, 0))
    px = im.load()
    for y in range(XP_DIAMETER):
        for x in range(XP_DIAMETER):
            r, _lap = _ring_geometry(x, y)
            # Sits INSIDE the casing keylines rather than under them, so the
            # fill never bleeds over the notches it is being measured against.
            if r > XP_R_OUT - 1.0 or r < XP_R_IN:
                continue
            if r < XP_R_IN + 1.0:
                px[x, y] = (255, 255, 255, 255)
            elif r > XP_R_OUT - 2.0:
                px[x, y] = (168, 172, 184, 255)
            else:
                px[x, y] = (224, 228, 238, 255)
    return im


def xp_spark():
    """The glowing bead that rides the leading edge of the filled arc.

    White with a hard core and one falloff step — it is modulated to the skill's
    colour at runtime. Odd-sized so it has a true centre pixel to pivot on; an
    even sprite lands the highlight half a pixel off the arc.
    """
    n = 7
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    px = im.load()
    c = (n - 1) / 2.0
    for y in range(n):
        for x in range(n):
            d = math.hypot(x - c, y - c)
            if d <= 1.2:
                px[x, y] = (255, 255, 255, 255)
            elif d <= 2.2:
                px[x, y] = (255, 255, 255, 168)
            elif d <= 3.2:
                px[x, y] = (255, 255, 255, 72)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    written = []
    for name, ramp in RAMPS.items():
        p = os.path.join(OUT, name + ".png")
        frame(ramp).save(p)
        written.append(p)
    for name, fn in (
        ("bar_track", bar_track), ("bar_fill", bar_fill), ("slot", slot),
        ("xp_casing", xp_casing), ("xp_arc_fill", xp_arc_fill), ("xp_spark", xp_spark),
    ):
        p = os.path.join(OUT, name + ".png")
        fn().save(p)
        written.append(p)
    for p in written:
        print("wrote", p)
    print("%d frames -> %s (9-slice margin %d)" % (len(written), OUT, MARGIN))


if __name__ == "__main__":
    main()
