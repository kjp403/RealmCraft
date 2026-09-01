"""Recolour the Swamp Hermit sheets into the Traveling Peddler's own sprite set.

The two NPCs must not be the same pixels. Sharing art meant a player who found
the cart in a biome and the Hermit in the swamp had no way to tell which one they
were looking at from the silhouette or the colour.

WHY A COPY, NOT A MATERIAL. The cheap route is a shader on a `skin_material` hook
on NPCResource, which is how the Wayfarer recolours a Scholar. That hook lives on
the unmerged quick-travel branch, and this feature is deliberately based on
origin/main — so depending on it would either stack the two PRs or duplicate the
hook and hand Kyle a merge conflict. Three 80x80 sheets is the cheaper price.

THE BAND IS THE DESIGN DECISION, which is why this script is committed rather
than run once and deleted. Unlike the Scholar (a 17-colour indexed palette), the
Hermit is anti-aliased -- 973 distinct opaque colours across the three sheets --
so the split has to be made on hue/saturation, not on palette entries. Bucketing
the opaque pixels shows a clean separation:

    hue 0.16-0.32, saturated  -> hood, robe, sleeves, trousers   (the garment)
    hue < 0.16,    saturated  -> staff, belt, straps, boots      (wood/leather)
    saturation < 0.18         -> beard and face
    value < 0.12              -> outline and deep shadow

Only the first band moves. The staff stays wooden, the leather stays leather, the
beard stays white and the outline is untouched, so the silhouette still reads as
the same hooded traveller -- it is the same person in different cloth, which is
what a recolour should look like.

Hue is REMAPPED THROUGH A VALUE-KEYED RAMP rather than rotated. A flat hue
rotation carries the green's own saturation curve across and the deep folds come
out muddy; keying the target colour off the pixel's value keeps the shading
readable and lets the highlights lift toward warm plum.

Writes assets/sprites/characters/traveling_peddler/traveling_peddler_{idle,run,
death}.png plus the matching SpriteFrames .tres.

  python tools/build_peddler_sprites.py
  godot --headless --path . --import
"""
import colorsys
import io
import os

from PIL import Image

SRC_DIR = os.path.join("assets", "sprites", "characters", "swamp_hermit")
OUT_DIR = os.path.join("assets", "sprites", "characters", "traveling_peddler")
SRC_SLUG = "swamp_hermit"
OUT_SLUG = "traveling_peddler"
SHEETS = ("idle", "run", "death")

FRAMES_SRC = os.path.join(
    "source", "common", "gameplay", "characters", "sprite_frames", "swamp_hermit.tres")
FRAMES_OUT = os.path.join(
    "source", "common", "gameplay", "characters", "sprite_frames", "traveling_peddler.tres")
# Hand-written uid. Godot's uid alphabet is base-34 -- it contains neither 'z'
# nor '9', and a uid using either is silently rewritten on import, which breaks
# every reference to this file.
FRAMES_UID = "uid://btravelpeddlerf1"

# The garment band, in HSV. Everything outside it is left exactly as authored.
#
# The LOW edge is the load-bearing number. The robe's lit greens sit around 0.20
# but its olive shading runs down to about 0.13, and cutting at 0.16 left those
# folds green -- a mottled purple-and-green garment rather than a recolour. The
# staff and leather sit in a tight cluster at 0.08, so 0.125 takes all the cloth
# and none of the wood.
ROBE_HUE_LO = 0.125
ROBE_HUE_HI = 0.32
MIN_SAT = 0.18
MIN_VAL = 0.12

# Value-keyed plum ramp: (value_breakpoint, target hue, target saturation).
# Walked low-to-high; a pixel takes the first stop at or above its value, and its
# own value is preserved so the original shading survives intact.
#
# Deep folds sit blue-violet and the lit edges warm toward magenta -- the way dyed
# cloth actually behaves, and the reason this is a ramp rather than one hue.
PLUM_RAMP = [
    (0.25, 0.760, 0.62),   # deepest folds  - blue-violet
    (0.45, 0.790, 0.60),   # mid shadow     - violet
    (0.70, 0.830, 0.55),   # body           - plum
    (1.01, 0.880, 0.44),   # lit edges      - warm magenta
]


def remap(rgb):
    """One pixel through the band test and the ramp. Returns the new RGB."""
    r, g, b = [v / 255.0 for v in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if v < MIN_VAL or s < MIN_SAT or not (ROBE_HUE_LO <= h <= ROBE_HUE_HI):
        return rgb
    for cutoff, hue, sat in PLUM_RAMP:
        if v <= cutoff:
            nr, ng, nb = colorsys.hsv_to_rgb(hue, sat, v)
            return (int(round(nr * 255)), int(round(ng * 255)), int(round(nb * 255)))
    return rgb


def recolour(name):
    src = Image.open(os.path.join(SRC_DIR, "%s_%s.png" % (SRC_SLUG, name))).convert("RGBA")
    w, h = src.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sp, op = src.load(), out.load()
    touched = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = sp[x, y]
            if a == 0:
                continue
            new = remap((r, g, b))
            if new != (r, g, b):
                touched += 1
            op[x, y] = new + (a,)
    dest = os.path.join(OUT_DIR, "%s_%s.png" % (OUT_SLUG, name))
    out.save(dest)
    print("wrote %s  (%d px recoloured)" % (dest, touched))
    return touched


def write_frames():
    """Clone the Hermit's SpriteFrames onto the new sheets.

    Text substitution, never ResourceSaver: a headless save strips uid= from the
    resource and every ext_resource it names. The source ext_resource uids are
    dropped rather than rewritten -- they point at the Hermit's PNGs, and Godot
    fills in the right ones for the new files on the next import pass.
    """
    body = io.open(FRAMES_SRC, encoding="utf-8").read()
    out_lines = []
    for line in body.splitlines():
        if line.startswith("[gd_resource"):
            line = '[gd_resource type="SpriteFrames" format=3 uid="%s"]' % FRAMES_UID
        elif line.startswith("[ext_resource"):
            # Drop the stale uid, repoint the path.
            head, _, rest = line.partition('uid="')
            if rest:
                line = head + rest.split('" ', 1)[1]
            line = line.replace(SRC_SLUG, OUT_SLUG)
        out_lines.append(line)
    io.open(FRAMES_OUT, "w", encoding="utf-8", newline="\n").write("\n".join(out_lines) + "\n")
    print("wrote", FRAMES_OUT)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    total = sum(recolour(name) for name in SHEETS)
    write_frames()
    print("%d sheets, %d pixels recoloured" % (len(SHEETS), total))


if __name__ == "__main__":
    main()
