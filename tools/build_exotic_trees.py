"""Generate the four high-tier woodcutting trees (Wispwood, Nebula Palm,
Glimmer-birch, Supernova Rosewood) as 64x96 pixel-art sprites, their stumps,
their idle-animation frames, and their 64x64 log icons.

The trees are drawn, not cut from a pack: nothing in the licensed art we own has
translucent floating canopies or pulsing neon cracks. The recipe below IS the
design decision -- the trunk curve, cluster sites and pulse ramps are why this
script is committed rather than run once and thrown away.

Frame 0 of each tree is the plain `tree_<slug>.png` (what the .tres `texture`
points at); extra frames land as `tree_<slug>_1.png` ... and are listed on the
resource's `idle_frames`, which MineableNode cycles client-side.

  python tools/build_exotic_trees.py
  godot --headless --path . --import
"""
import math
import os
import random

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TREE_DIR = os.path.join(REPO, "assets", "sprites", "environment", "trees")
ICON_DIR = os.path.join(REPO, "assets", "sprites", "items", "icons")

W, H = 64, 96
GROUND = 95


# --- tiny raster helpers ----------------------------------------------------

def blend(dst, src):
    sa = src[3] / 255.0
    if sa >= 1.0:
        return src
    da = dst[3] / 255.0
    out_a = sa + da * (1 - sa)
    if out_a <= 0:
        return (0, 0, 0, 0)
    return tuple(
        [int(round((src[i] * sa + dst[i] * da * (1 - sa)) / out_a)) for i in range(3)]
        + [int(round(out_a * 255))]
    )


def px(img, x, y, c):
    x, y = int(x), int(y)
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), blend(img.getpixel((x, y)), c))


def blob(img, cx, cy, rx, ry, c, rng, ragged=0.35, fill=1.0):
    """Noisy filled ellipse -- the canopy unit for every tree here."""
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            d = ((x - cx) / max(0.5, rx)) ** 2 + ((y - cy) / max(0.5, ry)) ** 2
            if d > 1.0 + ragged * rng.random() - ragged * 0.5:
                continue
            if fill < 1.0 and rng.random() > fill:
                continue
            px(img, x, y, c)


def line(img, x0, y0, x1, y1, c, width=1):
    steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
    for i in range(steps + 1):
        t = i / steps
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        for ox in range(width):
            for oy in range(width):
                px(img, x + ox - width // 2, y + oy - width // 2, c)


def outline(img, c):
    """1px dark border around every opaque cluster -- keeps the bright trees legible."""
    src = img.copy()
    for y in range(img.height):
        for x in range(img.width):
            if src.getpixel((x, y))[3] > 40:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < img.width and 0 <= ny < img.height and src.getpixel((nx, ny))[3] > 120:
                    img.putpixel((x, y), c)
                    break


def trunk(img, pal, height, base_w, twist, freq=1.6, phase=0.0, taper=0.72):
    """Tapering, twisting trunk. Returns the centre-line samples so canopies and
    branches can hang off the real geometry instead of guessed coordinates."""
    spine = []
    for step in range(height):
        t = step / float(height - 1)
        y = GROUND - step
        x = 32 + twist * math.sin(t * freq * math.pi + phase)
        w = max(1.5, base_w * (1.0 - taper * t))
        spine.append((x, y, w))
        for dx in range(int(-w / 2) - 1, int(w / 2) + 2):
            if abs(dx) > w / 2:
                continue
            shade = pal["bark_light"] if dx < -w / 4 else (
                pal["bark_dark"] if dx > w / 4 - 1 else pal["bark"])
            px(img, x + dx, y, shade)
    return spine


def branch(img, spine, at, dx, dy, length, pal, width=2):
    x, y, _ = spine[min(int(at * (len(spine) - 1)), len(spine) - 1)]
    ex, ey = x + dx * length, y - dy * length
    line(img, x, y, ex, ey, pal["bark"], width)
    line(img, x + 0.5, y, ex, ey - 0.5, pal["bark_light"], 1)
    return ex, ey


# --- tree recipes -----------------------------------------------------------

WISP = dict(
    bark=(209, 213, 219, 255), bark_light=(241, 243, 246, 255),
    bark_dark=(156, 163, 175, 255), ink=(90, 84, 120, 255),
    leaf=(6, 182, 212, 190), leaf_hi=(103, 232, 249, 200), leaf_dark=(14, 116, 144, 185),
    core=(6, 182, 212, 255),
)
NEBULA = dict(
    bark=(49, 46, 129, 255), bark_light=(76, 29, 149, 255),
    bark_dark=(30, 27, 75, 255), ink=(11, 10, 31, 255),
    leaf=(112, 26, 117, 255), leaf_hi=(162, 28, 175, 255), leaf_dark=(74, 16, 82, 255),
    core=(253, 230, 138, 255),
)
BIRCH = dict(
    bark=(255, 255, 255, 255), bark_light=(255, 255, 255, 255),
    bark_dark=(229, 231, 235, 255), ink=(55, 65, 81, 255),
    leaf=(156, 163, 175, 255), leaf_hi=(209, 213, 219, 255), leaf_dark=(107, 114, 128, 255),
    core=(6, 182, 212, 255),
)
ROSE = dict(
    bark=(255, 255, 255, 255), bark_light=(255, 255, 255, 255),
    bark_dark=(244, 114, 182, 255), ink=(76, 29, 75, 255),
    leaf=(244, 63, 94, 255), leaf_hi=(236, 72, 153, 255), leaf_dark=(159, 18, 57, 255),
    core=(245, 158, 11, 255),
)


def wispwood(frame):
    """3-5 detached teal clusters; alternating clusters bob 1px per frame."""
    rng = random.Random(6001)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    spine = trunk(img, WISP, 60, 9, 5.0, freq=1.9, taper=0.74)
    tips = [branch(img, spine, a, dx, 0.9, l, WISP)
            for a, dx, l in ((0.62, -1.0, 11), (0.74, 1.0, 12), (0.86, -0.7, 9), (0.93, 0.8, 8))]
    outline(img, WISP["ink"])

    # Clusters float DETACHED -- drawn after the outline so no border ties them
    # to the branches, which is what sells "floating".
    sites = [(18, 30, 11, 8), (44, 26, 10, 7), (31, 16, 12, 8),
             (22, 44, 8, 6), (45, 42, 8, 6)]
    for i, (cx, cy, rx, ry) in enumerate(sites):
        bob = -1 if (i % 2 == 0) == (frame == 0) else 1
        blob(img, cx, cy + bob, rx, ry, WISP["leaf"], rng, 0.4)
        blob(img, cx - 1, cy + bob - 1, rx * 0.6, ry * 0.55, WISP["leaf_hi"], rng, 0.5)
        blob(img, cx + 1, cy + bob + 2, rx * 0.5, ry * 0.4, WISP["leaf_dark"], rng, 0.5)
    for tx, ty in tips:
        px(img, tx, ty, WISP["leaf_hi"])
    return img


def nebula_palm(frame):
    """Desert palm: bare violet trunk, drooping purple fronds, star-fruit that
    twinkles bright/dim on the two frames."""
    rng = random.Random(7002)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    spine = trunk(img, NEBULA, 66, 8, -6.0, freq=1.0, taper=0.55)
    # Bark rings, then the starfield speckle that gives the trunk its night sky.
    for step in range(4, 62, 5):
        x, y, w = spine[step]
        line(img, x - w / 2, y, x + w / 2, y, NEBULA["bark_dark"], 1)
    for _ in range(46):
        step = rng.randrange(2, 64)
        x, y, w = spine[step]
        px(img, x + rng.uniform(-w / 2 + 1, w / 2 - 1), y, (255, 255, 255, 210))

    crown = spine[-1]
    fronds = [(-1.0, 0.30), (-0.8, 0.70), (-0.35, 0.95), (0.35, 0.95), (0.8, 0.70), (1.0, 0.30)]
    for fx, fy in fronds:
        cx, cy = crown[0], crown[1]
        for i in range(34):
            t = i / 33.0
            # droop: rises then falls, the classic palm arc
            x = cx + fx * 26 * t
            y = cy - fy * 17 * t + 16 * t * t
            px(img, x, y, NEBULA["leaf_hi"])
            px(img, x, y + 1, NEBULA["leaf"])
            # Leaflets comb off the spine only every third sample, and shorten
            # toward the tip -- combing every sample fuses the six fronds into
            # one solid cap and the palm stops reading as a palm.
            if i % 3:
                continue
            span = 3.0 * (1.0 - t * 0.6)
            for k in range(1, int(span) + 1):
                px(img, x - fx * k * 0.5, y - k, NEBULA["leaf"])
                px(img, x - fx * k * 0.5, y + 1 + k, NEBULA["leaf_dark"])
    outline(img, NEBULA["ink"])

    bright = frame == 0
    star = (253, 230, 138, 255) if bright else (139, 118, 62, 255)
    glow = (255, 255, 255, 255) if bright else (176, 137, 68, 255)
    for sx, sy in ((26, 34), (38, 32), (32, 39), (20, 30), (44, 36)):
        px(img, sx, sy, glow)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            px(img, sx + dx, sy + dy, star)
    return img


def glimmer_birch(frame):
    """White trunk with jagged neon cracks. 4 frames ramp dim -> neon -> blinding."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    spine = trunk(img, BIRCH, 64, 10, 3.0, freq=1.2, taper=0.6)
    for a, dx, l in ((0.66, -1.0, 12), (0.78, 1.0, 13), (0.9, -0.8, 9)):
        branch(img, spine, a, dx, 0.85, l, BIRCH)

    rng2 = random.Random(4242)
    for cx, cy, rx, ry in ((19, 27, 12, 9), (44, 24, 12, 9), (32, 14, 14, 9), (32, 33, 16, 8)):
        blob(img, cx, cy, rx, ry, BIRCH["leaf_dark"], rng2, 0.5)
        # Sub-clumps break the silhouette up so the canopy reads as foliage
        # rather than one grey cloud -- the birch has no colour to do that job.
        for k in range(5):
            ox = rng2.uniform(-rx * 0.6, rx * 0.6)
            oy = rng2.uniform(-ry * 0.6, ry * 0.6)
            blob(img, cx + ox, cy + oy, rx * 0.42, ry * 0.45, BIRCH["leaf"], rng2, 0.55)
            blob(img, cx + ox - 1, cy + oy - 1.5, rx * 0.26, ry * 0.28,
                 BIRCH["leaf_hi"], rng2, 0.6)
    outline(img, BIRCH["ink"])

    # Cycle: dim blue -> neon blue -> blinding cyan -> dim blue.
    ramp = [(30, 58, 138, 255), (37, 99, 235, 255), (103, 232, 249, 255), (37, 99, 235, 255)]
    hot = [(37, 99, 235, 120), (96, 165, 250, 160), (224, 252, 255, 220), (96, 165, 250, 160)]
    crack = ramp[frame % 4]
    halo = hot[frame % 4]
    for seed in (11, 27, 53):
        r = random.Random(seed)
        step = 2
        x, y, w = spine[step]
        jx = x + r.uniform(-w / 4, w / 4)
        while step < 60:
            prev_step = step
            step += r.randrange(2, 5)
            if step >= len(spine):
                break
            nx, ny, nw = spine[step]
            jx2 = nx + r.uniform(-nw / 3, nw / 3)
            line(img, jx, GROUND - prev_step, jx2, ny, crack, 1)
            px(img, jx2 + 1, ny, halo)
            px(img, jx2 - 1, ny, halo)
            jx = jx2
    return img


def supernova_rosewood(frame):
    """White-cored trunk in a heavy magenta outline, neon-pink branch tips, and a
    1px pink aura that pulses outward across the 4 frames."""
    rng = random.Random(9004)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    spine = trunk(img, ROSE, 58, 11, -4.0, freq=1.5, taper=0.66)
    # Heavy magenta shoulder so the white core never blows out against pale ground.
    for x, y, w in spine:
        px(img, x - w / 2, y, (134, 25, 143, 255))
        px(img, x + w / 2, y, (134, 25, 143, 255))
    tips = [branch(img, spine, a, dx, 0.9, l, ROSE)
            for a, dx, l in ((0.6, -1.0, 13), (0.72, 1.0, 14), (0.84, -0.75, 10), (0.92, 0.7, 9))]
    for tx, ty in tips:
        blob(img, tx, ty, 3, 3, (244, 114, 182, 255), rng, 0.3)

    for cx, cy, rx, ry, col in (
        (19, 28, 12, 9, ROSE["leaf"]), (45, 25, 12, 9, ROSE["leaf"]),
        (32, 14, 14, 9, ROSE["leaf_hi"]), (32, 34, 16, 8, ROSE["leaf_dark"]),
    ):
        blob(img, cx, cy, rx, ry, col, rng, 0.45)
        blob(img, cx - 1, cy - 2, rx * 0.55, ry * 0.5, (245, 158, 11, 255), rng, 0.5, fill=0.5)
        blob(img, cx + 2, cy + 2, rx * 0.5, ry * 0.4, ROSE["leaf_hi"], rng, 0.5, fill=0.6)
    outline(img, ROSE["ink"])

    # Aura: a 1px low-opacity ring that widens (and fades) over the cycle.
    radius = (0, 2, 4, 6)[frame % 4]
    alpha = (0, 70, 46, 24)[frame % 4]
    if alpha:
        for x, y, w in spine[::2]:
            for side in (-1, 1):
                px(img, x + side * (w / 2 + radius), y, (244, 63, 94, alpha))
        for ang in range(0, 360, 12):
            rad = math.radians(ang)
            px(img, 32 + math.cos(rad) * (18 + radius), 28 + math.sin(rad) * (15 + radius),
               (244, 63, 94, alpha))
    return img


def stump(pal, core, ring=None):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for step in range(9):
        y = GROUND - step
        w = 13 - step * 0.25
        for dx in range(int(-w / 2), int(w / 2) + 1):
            shade = pal["bark_light"] if dx < -w / 4 else (
                pal["bark_dark"] if dx > w / 4 - 1 else pal["bark"])
            px(img, 32 + dx, y, shade)
    blob(img, 32, GROUND - 9, 6.5, 2.5, core, random.Random(1), 0.1)
    if ring:
        blob(img, 32, GROUND - 9, 4.0, 1.4, ring, random.Random(2), 0.1)
    outline(img, pal["ink"])
    return img


# --- log icons --------------------------------------------------------------

def log_icon(bark, bark_dark, bark_light, cut, ink, deco=None):
    """Diagonal log matching the shipped oak/yew/maple icons: lower-left cut face,
    barrel running up-right, `deco(img, t, u, x, y)` painting the tier's signature."""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    x0, y0, x1, y1 = 16.0, 46.0, 48.0, 18.0
    ax, ay = x1 - x0, y1 - y0
    alen = math.hypot(ax, ay)
    ux, uy = ax / alen, ay / alen
    nx, ny = -uy, ux
    rad = 11.0
    for i in range(int(alen * 3) + 1):
        t = i / (alen * 3)
        bx, by = x0 + ax * t, y0 + ay * t
        for j in range(-int(rad), int(rad) + 1):
            u = j / rad
            if abs(u) > 1.0:
                continue
            x, y = bx + nx * j, by + ny * j
            c = bark_light if u < -0.45 else (bark_dark if u > 0.45 else bark)
            px(img, x, y, c)
            if deco:
                deco(img, t, u, x, y)
    # Cut face: an ellipse squashed along the log axis.
    for j in range(-14, 15):
        for k in range(-14, 15):
            if (j / 11.0) ** 2 + (k / 5.0) ** 2 > 1.0:
                continue
            px(img, x0 + nx * j + ux * k, y0 + ny * j + uy * k, cut)
    outline(img, ink)
    return img


def build_logs():
    rng = random.Random(31337)

    # Wispwood: pale grey barrel, glowing turquoise ring around the cut core.
    img = log_icon((203, 209, 216, 255), (150, 157, 168, 255), (233, 237, 242, 255),
                   (226, 232, 240, 255), (86, 92, 110, 255))
    alen = math.hypot(32.0, -28.0)
    ux, uy = 32.0 / alen, -28.0 / alen
    nx, ny = -uy, ux
    x0, y0 = 16.0, 46.0
    for j in range(-14, 15):
        for k in range(-14, 15):
            d = (j / 7.5) ** 2 + (k / 3.4) ** 2
            if 0.55 < d <= 1.0:
                px(img, x0 + nx * j + ux * k, y0 + ny * j + uy * k, (6, 182, 212, 255))
            elif d <= 0.55:
                px(img, x0 + nx * j + ux * k, y0 + ny * j + uy * k, (165, 243, 252, 255))
    img.save(os.path.join(ICON_DIR, "wispwood_log.png"))

    # Nebula: violet bark whose grain is a starfield.
    def stars(im, t, u, x, y):
        if rng.random() < 0.035 and abs(u) < 0.9:
            px(im, x, y, (255, 255, 255, 235))
    img = log_icon((45, 42, 110, 255), (30, 27, 75, 255), (67, 60, 150, 255),
                   (112, 26, 117, 255), (10, 9, 28, 255), stars)
    img.save(os.path.join(ICON_DIR, "nebula_palm_log.png"))

    # Glimmer-birch: white bark wrapped in glowing blue cracks.
    def cracks(im, t, u, x, y):
        band = math.sin(t * 26.0 + u * 1.4)
        if band > 0.93:
            px(im, x, y, (6, 182, 212, 255))
        elif band > 0.86:
            px(im, x, y, (147, 197, 253, 190))
    img = log_icon((255, 255, 255, 255), (214, 219, 226, 255), (255, 255, 255, 255),
                   (240, 244, 248, 255), (55, 65, 81, 255), cracks)
    img.save(os.path.join(ICON_DIR, "glimmer_birch_log.png"))

    # Rosewood: hot-pink bark layer over a gold grain core.
    def pinkbark(im, t, u, x, y):
        if abs(u) > 0.62:
            px(im, x, y, (244, 63, 94, 255))
        elif abs(u) > 0.5:
            px(im, x, y, (236, 72, 153, 255))
    img = log_icon((245, 158, 11, 255), (180, 108, 8, 255), (253, 205, 116, 255),
                   (250, 204, 21, 255), (76, 29, 75, 255), pinkbark)
    img.save(os.path.join(ICON_DIR, "rosewood_log.png"))


# --- unstrung bow icons -----------------------------------------------------

def bow_icon(limb, limb_dark, limb_light, nock, ink, sheen=None):
    """An UNSTRUNG bow: a bare wooden C with the nocks cut and no string drawn.
    The gap where the string belongs is the whole read -- it is what tells a
    player at a glance that this is a fletching intermediate, not a weapon."""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    cx, cy, rad = 44.0, 32.0, 24.0
    # Limb: an arc swept from roughly 8 o'clock round to 4 o'clock, thickest at
    # the grip and tapering into both tips.
    for i in range(721):
        ang = math.radians(120.0 + i * 120.0 / 720.0)
        t = i / 720.0
        # 0 at the tips, 1 at the grip -> the limb tapers the way a bow does
        taper = math.sin(t * math.pi)
        half = 1.0 + 2.4 * taper
        for j in range(-4, 5):
            if abs(j) > half:
                continue
            x = cx + math.cos(ang) * (rad + j)
            y = cy + math.sin(ang) * (rad + j)
            c = limb_light if j < -half * 0.35 else (limb_dark if j > half * 0.35 else limb)
            px(img, x, y, c)
            if sheen:
                sheen(img, t, j / max(0.6, half), x, y)
    # Nocks: the cut notches at both tips, left bare.
    for ang in (math.radians(120.0), math.radians(240.0)):
        nx, ny = cx + math.cos(ang) * rad, cy + math.sin(ang) * rad
        for d in range(-2, 3):
            px(img, nx + d * 0.6, ny + abs(d) * 0.4, nock)
    outline(img, ink)
    return img


def build_bows():
    rng = random.Random(9182)

    def starry(im, t, u, x, y):
        if rng.random() < 0.05:
            px(im, x, y, (255, 255, 255, 230))

    def crackle(im, t, u, x, y):
        if math.sin(t * 34.0) > 0.9:
            px(im, x, y, (6, 182, 212, 255))

    def goldgrain(im, t, u, x, y):
        if abs(u) < 0.3:
            px(im, x, y, (245, 158, 11, 255))

    specs = [
        ("wispwood_bow_u", (203, 209, 216, 255), (150, 157, 168, 255), (236, 240, 245, 255),
         (6, 182, 212, 255), (86, 92, 110, 255), None),
        ("nebula_palm_bow_u", (52, 48, 122, 255), (30, 27, 75, 255), (78, 70, 160, 255),
         (253, 230, 138, 255), (10, 9, 28, 255), starry),
        ("glimmer_birch_bow_u", (255, 255, 255, 255), (214, 219, 226, 255), (255, 255, 255, 255),
         (6, 182, 212, 255), (55, 65, 81, 255), crackle),
        ("rosewood_bow_u", (244, 63, 94, 255), (159, 18, 57, 255), (250, 130, 150, 255),
         (245, 158, 11, 255), (76, 29, 75, 255), goldgrain),
    ]
    for name, limb, dark, light, nock, ink, sheen in specs:
        bow_icon(limb, dark, light, nock, ink, sheen).save(os.path.join(ICON_DIR, name + ".png"))
    print("unstrung bow icons: %d" % len(specs))


TREES = {
    "wispwood": (wispwood, 2, WISP, (165, 243, 252, 255), (6, 182, 212, 255)),
    "nebula_palm": (nebula_palm, 2, NEBULA, (112, 26, 117, 255), (253, 230, 138, 255)),
    "glimmer_birch": (glimmer_birch, 4, BIRCH, (240, 244, 248, 255), (6, 182, 212, 255)),
    "supernova_rosewood": (supernova_rosewood, 4, ROSE, (245, 158, 11, 255), (244, 63, 94, 255)),
}


def main():
    os.makedirs(TREE_DIR, exist_ok=True)
    for slug, (fn, frames, pal, cut, ring) in TREES.items():
        for f in range(frames):
            name = "tree_%s.png" % slug if f == 0 else "tree_%s_%d.png" % (slug, f)
            fn(f).save(os.path.join(TREE_DIR, name))
        stump(pal, cut, ring).save(os.path.join(TREE_DIR, "tree_%s_stump.png" % slug))
        print("tree %s: %d frames + stump" % (slug, frames))
    build_logs()
    print("log icons: 4")
    build_bows()


if __name__ == "__main__":
    main()
