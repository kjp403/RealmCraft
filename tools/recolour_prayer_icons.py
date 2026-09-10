"""Generate the Super Prayer Potion and Prayer Renewal icons.

THE TWO PNGs ARE GENERATED. Never hand-edit
assets/sprites/items/icons/potion_super_prayer.png or
potion_prayer_renewal.png -- change this script and re-run it, the same
rule tools/build_ability_icons.py and the gem icon tool follow:

    python tools/recolour_prayer_icons.py     # from the project root
    godot --headless --path . --import        # regenerate the .import

They are potion_purple_bottle and potion_purple_flask from the generic
potion pack, recoloured into the Prayer Potion's palette so the three
prayer draughts read as one family, separated by vessel silhouette --
round for the Potion, square bottle for the Super, conical flask for the
Renewal. The purple originals are left untouched and unused.

The generic potion pack draws every colour family off ONE shading ramp — the
saturation/value pairs in potion_purple_bottle are the same pairs as in
potion_prayer, only the hue differs (and potion_prayer's "cork" is that ramp in
teal, which is why its cap reads as part of the vial rather than as cork). So
the recolour is an exact palette substitution keyed on (S, V) rather than a hue
rotation: every source colour is replaced by the potion_prayer colour with the
nearest (S, V), and greys, black and white are left byte-identical.

Value is weighted double when matching, because V carries the shading. Getting
S slightly wrong shifts a tint; getting V wrong flattens the sprite.
"""
import colorsys
import os

from PIL import Image

ICONS = "assets/sprites/items/icons"
SOURCE_OF_TRUTH = "potion_prayer.png"
# Anything at or above this saturation is vial-colour (liquid or cork) and gets
# remapped. Below it is the glass neck, the outline and the highlights, which
# potion_prayer shares byte-for-byte and which must not move.
SATURATION_FLOOR = 0.30
JOBS = {
    "potion_purple_bottle.png": "potion_super_prayer.png",
    "potion_purple_flask.png": "potion_prayer_renewal.png",
}


def palette(path):
    img = Image.open(path).convert("RGBA")
    counts = {}
    for px in img.get_flattened_data():
        if px[3] == 0:
            continue
        counts[px] = counts.get(px, 0) + 1
    return img, counts


def hsv(rgba):
    r, g, b, _ = rgba
    return colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)


_, prayer_counts = palette(os.path.join(ICONS, SOURCE_OF_TRUTH))
targets = []
for colour in prayer_counts:
    h, s, v = hsv(colour)
    if s >= SATURATION_FLOOR:
        targets.append((s, v, colour))
if not targets:
    raise SystemExit("no saturated colours found in " + SOURCE_OF_TRUTH)


def nearest(s, v):
    best, best_d = None, None
    for ts, tv, colour in targets:
        d = (ts - s) ** 2 + (2.0 * (tv - v)) ** 2
        if best_d is None or d < best_d:
            best, best_d = colour, d
    return best


for src_name, dst_name in JOBS.items():
    img, counts = palette(os.path.join(ICONS, src_name))
    mapping = {}
    for colour in counts:
        _, s, v = hsv(colour)
        mapping[colour] = nearest(s, v) if s >= SATURATION_FLOOR else colour

    out = Image.new("RGBA", img.size)
    out.putdata([
        (0, 0, 0, 0) if px[3] == 0 else mapping.get(px, px)
        for px in img.get_flattened_data()
    ])
    dst = os.path.join(ICONS, dst_name)
    out.save(dst)

    moved = sum(1 for a, b in mapping.items() if a != b)
    print("%s -> %s  (%d of %d colours remapped)" % (
        src_name, dst_name, moved, len(mapping)))
    for a in sorted(mapping, key=lambda c: -counts[c]):
        b = mapping[a]
        if a == b:
            continue
        print("     #%02x%02x%02x -> #%02x%02x%02x   %4dpx" % (
            a[0], a[1], a[2], b[0], b[1], b[2], counts[a]))
