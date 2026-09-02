"""Recolor the runite art set into the Dragon / Obsidian / Celestial / Astralite tiers."""
import colorsys
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# dark -> light ramps, sampled by source luminance
RAMPS = {
    "dragon": [(28, 6, 6), (96, 16, 12), (168, 34, 24), (226, 76, 44), (255, 186, 140)],
    "obsidian": [(26, 4, 42), (70, 12, 96), (128, 30, 152), (186, 82, 236), (238, 196, 255)],
    "celestial": [(24, 24, 42), (70, 76, 104), (186, 170, 104), (226, 208, 120), (242, 234, 196)],
    "astralite": [(26, 22, 46), (78, 60, 132), (150, 110, 210), (216, 170, 246), (250, 240, 255)],
}
IRIDESCENT = "astralite"
STARLIT = "celestial"
# pale gold the starlight aura and the sparkles are drawn in
AURA = (255, 240, 168)


def _lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _ramp(colors, lum):
    pos = lum * (len(colors) - 1)
    i = min(int(pos), len(colors) - 2)
    return _lerp(colors[i], colors[i + 1], pos - i)


def _neighbours(px, w, h, x, y):
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < w and 0 <= ny < h:
            yield px[nx, ny]
        else:
            yield (0, 0, 0, 0)


def starlight(im, pad, pad_y=None, aura=True):
    """Rim-light the silhouette, scatter sparkles, and bloom a soft aura outside it."""
    pad_y = pad if pad_y is None else pad_y
    if pad or pad_y:
        lit = Image.new("RGBA", (im.width + pad * 2, im.height + pad_y * 2), (0, 0, 0, 0))
        lit.alpha_composite(im, (pad, pad_y))
        im = lit
    w, h = im.size
    px = im.load()
    solid = [[px[x, y][3] > 128 for y in range(h)] for x in range(w)]

    # rim light: lit pixels that touch empty space or the outline pick up the aura
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0 or not solid[x][y]:
                continue
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            if lum < 0.10:
                continue
            edge = any(n[3] < 128 for n in _neighbours(px, w, h, x, y))
            if edge:
                px[x, y] = (
                    min(255, round(r * 0.68 + AURA[0] * 0.32)),
                    min(255, round(g * 0.68 + AURA[1] * 0.32)),
                    min(255, round(b * 0.68 + AURA[2] * 0.32)),
                    a,
                )

    # sparkles: 4-point stars on the brighter faces
    for y in range(h):
        for x in range(w):
            if not solid[x][y]:
                continue
            r, g, b, a = px[x, y]
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            if lum < 0.66:
                continue
            if ((x * 71 + y * 149) * 2654435761) % 31:
                continue
            px[x, y] = (255, 253, 235, 255)
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h and solid[nx][ny]:
                    pr, pg, pb, pa = px[nx, ny]
                    px[nx, ny] = (
                        min(255, round(pr * 0.55 + AURA[0] * 0.45)),
                        min(255, round(pg * 0.55 + AURA[1] * 0.45)),
                        min(255, round(pb * 0.55 + AURA[2] * 0.45)),
                        pa,
                    )

    # aura: distance-falloff bloom painted into the empty pixels around the rock.
    # World props only — a halo on an inventory icon just eats its contrast.
    for y in range(h) if aura else []:
        for x in range(w):
            if px[x, y][3] > 0:
                continue
            best = 99
            for dy in range(-3, 4):
                for dx in range(-3, 4):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and solid[nx][ny]:
                        best = min(best, abs(dx) + abs(dy))
            if best <= 3:
                px[x, y] = AURA + (round(140 * (1.0 - (best - 1) / 3.0)),)
    return im


def recolor(src, dst, tier, pad=0, pad_y=None, tile=None, aura=True):
    im = Image.open(os.path.join(ROOT, src)).convert("RGBA")
    px = im.load()
    ramp = RAMPS[tier]
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            if lum < 0.06:  # keep the outline black
                continue
            nr, ng, nb = _ramp(ramp, lum)
            if tier == IRIDESCENT and 0.15 < lum < 0.92:
                h, s, v = colorsys.rgb_to_hsv(nr / 255, ng / 255, nb / 255)
                n = ((x * 37 + y * 101) * 2654435761) % 997 / 997.0
                h = (h + (n - 0.5) * 0.30) % 1.0
                s = min(1.0, s + 0.10)
                nr, ng, nb = (round(c * 255) for c in colorsys.hsv_to_rgb(h, s, v))
            px[x, y] = (nr, ng, nb, a)
    if tier == STARLIT:
        if tile:
            # the weapon sheet is a 16x32 atlas: light each cell on its own, with no
            # aura, so a tool's glow cannot bleed into the neighbouring icon's region
            tw, th = tile
            for ty in range(0, im.height, th):
                for tx in range(0, im.width, tw):
                    box = (tx, ty, tx + tw, ty + th)
                    im.paste(starlight(im.crop(box), 0, aura=False), box)
        else:
            im = starlight(im, pad, pad_y, aura)
    out = os.path.join(ROOT, dst)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    im.save(out)
    print("wrote", dst)


ICONS = "assets/sprites/items/icons"
PROPS = "assets/sprites/environment/props"
WEAPONS = "assets/sprites/items/weapons"

for tier in RAMPS:
    recolor(f"{PROPS}/vein_runite.png", f"{PROPS}/vein_{tier}.png", tier, pad=3, pad_y=1)
    recolor(f"{ICONS}/bar_runite.png", f"{ICONS}/bar_{tier}.png", tier, aura=False)
    recolor(f"{WEAPONS}/runite/runite.png", f"{WEAPONS}/{tier}/{tier}.png", tier, tile=(16, 32))
    if tier != "dragon":  # ore_dragon.png already ships with the boss drop
        recolor(f"{ICONS}/ore_runite.png", f"{ICONS}/ore_{tier}.png", tier, aura=False)

recolor(f"{WEAPONS}/tools/fishing_rod_lv30.png", f"{WEAPONS}/tools/fishing_rod_dragon.png", "dragon")
