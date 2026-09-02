"""Recolor the Runite arrow / arrowhead icons into the four high tiers.

Recolouring is the RIGHT call here, unlike for tools. An arrowhead is the same
object in a different metal — the silhouette carries no information a player
needs, the colour carries all of it. Tool heads were the opposite case: their
shape is what tells you a pickaxe from an axe, so those are drawn per tier by
`build_high_tier_tool_art.py`.

Only the METAL is remapped. The 16x16 arrow keeps its wooden shaft and pale
fletching; the head is recoloured by luminance through the tier ramp, so the
shading the artist put on the cone survives instead of being flattened.

    python tools/build_high_tier_arrow_icons.py
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "assets", "sprites", "items", "icons")

# Same ramps as every other piece of tier art. dark -> light, sampled by the
# source pixel's luminance.
RAMPS = {
    "dragon":    [(28, 6, 6), (96, 16, 12), (168, 34, 24), (226, 76, 44), (255, 186, 140)],
    "obsidian":  [(26, 4, 42), (70, 12, 96), (128, 30, 152), (186, 82, 236), (238, 196, 255)],
    "celestial": [(24, 24, 42), (70, 76, 104), (186, 170, 104), (226, 208, 120), (242, 234, 196)],
    "astralite": [(26, 22, 46), (78, 60, 132), (150, 110, 210), (216, 170, 246), (250, 240, 255)],
}

SOURCE_HEADS = "mat_runite_arrowheads.png"
SOURCE_ARROW = "mat_runite_arrow.png"


def _lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _ramp(colors, t):
    t = max(0.0, min(1.0, t))
    pos = t * (len(colors) - 1)
    i = min(int(pos), len(colors) - 2)
    return _lerp(colors[i], colors[i + 1], pos - i)


def _is_metal(px):
    """Runite's metal is teal: blue clearly above red, and not near-black.

    The shaft is brown (red above blue) and the fletching is desaturated, so
    this separates the head from the parts that must stay wood-coloured. Doing
    it by hue rather than by an authored mask means a re-export of the source
    icon does not silently shift which pixels get recoloured.
    """
    r, g, b, a = px
    if a < 40:
        return False
    if b <= r + 12:
        return False
    return max(r, g, b) > 40


def recolor(src_name, tier, out_name, metal_only):
    src = Image.open(os.path.join(ICONS, src_name)).convert("RGBA")
    out = src.copy()
    sp, op = src.load(), out.load()
    ramp = RAMPS[tier]
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = sp[x, y]
            if a == 0:
                continue
            if metal_only and not _is_metal((r, g, b, a)):
                continue
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            op[x, y] = _ramp(ramp, lum) + (a,)
    path = os.path.join(ICONS, out_name)
    out.save(path)
    print("wrote", os.path.relpath(path, ROOT))


def main():
    for tier in RAMPS:
        # The arrowhead icon is entirely metal — remap every opaque pixel so the
        # drop shadow tracks the tier instead of staying runite-dark.
        recolor(SOURCE_HEADS, tier, "mat_%s_arrowheads.png" % tier, metal_only=False)
        # The arrow keeps its shaft and fletching.
        recolor(SOURCE_ARROW, tier, "mat_%s_arrow.png" % tier, metal_only=True)


if __name__ == "__main__":
    main()
