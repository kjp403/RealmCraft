"""Recolour Mana Seed outfit sheets into one distinct look per armour tier.

The packs ship a handful of colour variants per outfit; the gear ladder in
source/common/gameplay/items/gears/ has ~60 named sets. Without this, everything
past the 5th tier in a family wears the same colour and progression is invisible.

Method: read the source sheet's palette, sort it by luminance, and remap it onto a
per-tier ramp. Sorting by luminance is what preserves the original shading - a
naive hue rotate flattens the highlights and the cloth stops reading as folds.

Outputs, per tier:
    assets/sprites/characters/gear_tiers/<tier>_<slot>.png   worn sheet (512x512)
    assets/sprites/characters/gear_icons/<tier>_<slot>.png   inventory icon (32x32)

The icon is cropped from the SAME sheet the character wears, so the inventory
picture and the worn armour can never disagree.

Usage:
    python tools/paperdoll/recolor_gear.py
"""

from __future__ import annotations

import colorsys
import glob
import os
from typing import Dict, List, Sequence, Tuple

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(REPO, "assets", "sprites", "characters", "manaseed")
OUT_SHEETS = os.path.join(REPO, "assets", "sprites", "characters", "gear_tiers")
OUT_ICONS = os.path.join(REPO, "assets", "sprites", "characters", "gear_icons")

FRAME = 64
ICON = 32

RGB = Tuple[int, int, int]

# Which pack outfit each family recolours from, and which slot layer it feeds.
# Each family walks through THREE silhouettes as it climbs, so late-game gear is a
# different shape and not merely a different colour. Bands are (fraction, outfit):
# the first third of a ladder uses the first entry, and so on.
FAMILY_BANDS: Dict[str, Tuple[str, str, str]] = {
    "metal": ("pfpn", "bksm", "bksm"),
    "leather": ("pfpn", "fstr", "fstr"),
    "cloth": ("pfdr", "alch", "alch"),
}

# A gear set is a STACK, not one garment. This is what makes armour read as armour
# rather than a recoloured dress: the mantle gives a heavy set its pauldrons, and
# the hood + cloak give ranger and mage sets their silhouette.
#   part name -> (pack layer, item code)
FAMILY_PARTS: Dict[str, Dict[str, Tuple[str, str]]] = {
    # Heavy: shoulder mantle over the body. Reads as pauldrons.
    "metal": {"cloak": ("2clo", "mnpl")},
    # Archery: hood up plus a long cloak. Reads as a ranger.
    "leather": {"cloak": ("2clo", "lnpl"), "hood": ("5hat", "hdpl")},
    # Mage: hood up plus a long cloak over the robe.
    "cloth": {"cloak": ("2clo", "lnpl"), "hood": ("5hat", "hdpl")},
}
FAMILY_SOURCE: Dict[str, Tuple[str, str]] = {
    "metal": ("1out", "bksm"),
    "leather": ("1out", "fstr"),
    "cloth": ("1out", "alch"),
}
FAMILY_HAT_SOURCE: Dict[str, Tuple[str, str]] = {
    "metal": ("5hat", "band"),
    "leather": ("5hat", "hdpl"),
    "cloth": ("5hat", "pnty"),
}
SOURCE_VARIANT = "01"

# Per-tier ramps: (light, mid, dark, accent). Ordered up each family's ladder so a
# later tier reads as an upgrade at a glance, the way bronze->dragon does in OSRS.
RAMPS: Dict[str, Tuple[RGB, RGB, RGB, RGB]] = {
    # --- metal ---
    "copper":       ((222, 148, 100), (170, 100, 62),  (104, 58, 36),   (92, 74, 58)),
    "bronze":       ((212, 164, 96),  (158, 114, 62),  (100, 70, 38),   (86, 70, 50)),
    "iron":         ((162, 164, 172), (112, 114, 124), (68, 70, 80),    (80, 64, 50)),
    "steel":        ((198, 204, 214), (140, 148, 162), (88, 94, 108),   (84, 68, 52)),
    "silver":       ((234, 238, 246), (180, 186, 200), (120, 126, 142), (96, 100, 116)),
    "gold":         ((250, 216, 120), (206, 164, 70),  (140, 106, 38),  (120, 92, 44)),
    "mithril":      ((128, 154, 226), (84, 106, 178),  (48, 64, 122),   (196, 202, 220)),
    "adamant":      ((110, 182, 134), (66, 130, 92),   (34, 84, 56),    (198, 210, 200)),
    "runite":       ((110, 200, 206), (62, 148, 158),  (30, 96, 106),   (206, 226, 228)),
    "dragon":       ((222, 100, 88),  (166, 58, 52),   (106, 28, 28),   (232, 198, 122)),
    "basilisk":     ((184, 204, 112), (132, 152, 68),  (82, 98, 36),    (222, 208, 150)),
    "behemoth":     ((184, 138, 100), (132, 94, 64),   (82, 54, 34),    (226, 176, 108)),
    "colossus":     ((202, 192, 174), (146, 136, 120), (92, 84, 72),    (232, 214, 156)),
    "godsteel":     ((246, 244, 230), (198, 194, 176), (136, 132, 116), (248, 226, 150)),
    "worldbreaker": ((228, 136, 82),  (172, 88, 48),   (108, 46, 24),   (250, 208, 128)),
    "wyrmguard":    ((172, 128, 220), (120, 82, 168),  (72, 44, 112),   (238, 214, 250)),
    "ironbane":     ((156, 164, 178), (106, 114, 130), (62, 68, 82),    (196, 120, 72)),
    "ruinplate":    ((156, 136, 124), (108, 92, 82),   (64, 53, 46),    (188, 90, 70)),
    "adamantine":   ((126, 196, 152), (80, 142, 106),  (42, 92, 66),    (232, 240, 220)),
    "doomforge":    ((204, 110, 76),  (150, 68, 42),   (92, 34, 20),    (60, 56, 64)),
    # --- leather ---
    "leather":      ((162, 122, 84),  (116, 84, 55),   (70, 48, 30),    (94, 78, 54)),
    "studded":      ((140, 106, 78),  (98, 72, 50),    (58, 40, 26),    (168, 170, 178)),
    "shadow":       ((98, 94, 110),   (64, 61, 76),    (36, 34, 46),    (128, 122, 148)),
    "eclipse":      ((84, 80, 102),   (54, 50, 70),    (28, 26, 40),    (208, 176, 96)),
    "nightglass":   ((78, 90, 114),   (48, 58, 78),    (24, 30, 46),    (140, 190, 220)),
    "phantom":      ((116, 128, 144), (78, 88, 102),   (44, 52, 64),    (176, 208, 216)),
    "sirenic":      ((94, 144, 146),  (60, 100, 104),  (32, 62, 66),    (176, 222, 214)),
    "skyrender":    ((116, 156, 202), (76, 110, 152),  (42, 68, 102),   (214, 232, 246)),
    "starfall":     ((130, 124, 182), (88, 82, 134),   (50, 46, 86),    (244, 232, 168)),
    "tempest":      ((98, 134, 174),  (62, 92, 126),   (32, 54, 80),    (232, 240, 250)),
    "wraithsilk":   ((138, 132, 154), (94, 89, 110),   (54, 50, 66),    (206, 230, 226)),
    "soulbrand":    ((166, 122, 154), (116, 80, 108),  (68, 44, 64),    (240, 196, 140)),
    "ghostweave":   ((162, 174, 182), (114, 124, 134), (66, 74, 82),    (214, 232, 236)),
    "duskfeather":  ((110, 102, 130), (72, 66, 90),    (40, 36, 54),    (198, 172, 214)),
    "silentwing":   ((102, 110, 126), (66, 73, 86),    (36, 41, 51),    (188, 204, 218)),
    "canopy":       ((130, 158, 106), (88, 112, 70),   (50, 68, 40),    (176, 148, 104)),
    "emberpath":    ((202, 130, 90),  (150, 90, 58),   (94, 52, 30),    (232, 186, 122)),
    "miststride":   ((166, 180, 188), (118, 130, 138), (70, 79, 86),    (216, 230, 236)),
    "nightcourier": ((94, 98, 116),   (60, 64, 79),    (32, 35, 46),    (180, 186, 208)),
    "tidepath":     ((106, 152, 166), (68, 107, 120),  (38, 65, 75),    (200, 228, 232)),
    "trailwalker":  ((156, 128, 98),  (110, 89, 66),   (66, 51, 36),    (190, 168, 130)),
    # --- cloth ---
    "cloth":        ((182, 168, 144), (134, 122, 102), (84, 75, 60),    (120, 104, 82)),
    "apprentice":   ((128, 138, 174), (88, 96, 128),   (50, 56, 82),    (196, 186, 146)),
    "scholars":     ((138, 118, 162), (96, 80, 116),   (56, 44, 72),    (214, 198, 152)),
    "enchanted":    ((110, 154, 178), (72, 108, 130),  (40, 66, 84),    (222, 214, 160)),
    "runewoven":    ((116, 134, 196), (76, 92, 146),   (42, 52, 94),    (232, 216, 148)),
    "astral":       ((142, 128, 206), (98, 86, 154),   (56, 48, 100),   (238, 230, 176)),
    "voidsilk":     ((84, 78, 106),   (54, 49, 72),    (28, 24, 42),    (170, 148, 220)),
    "aetherborn":   ((128, 182, 202), (86, 132, 152),  (48, 84, 100),   (236, 244, 248)),
    "empyrean":     ((240, 214, 152), (192, 162, 100), (130, 104, 54),  (250, 244, 214)),
    "primordial":   ((156, 178, 134), (110, 130, 92),  (66, 82, 52),    (232, 226, 178)),
    "ancient":      ((204, 182, 220), (152, 130, 172), (96, 78, 114),   (246, 232, 178)),
    "celestine":    ((192, 212, 238), (140, 162, 194), (86, 104, 134),  (246, 240, 206)),
    "eldritch":     ((100, 122, 98),  (64, 82, 63),    (34, 47, 34),    (176, 214, 120)),
    "firstlight":   ((248, 238, 204), (204, 190, 150), (142, 128, 94),  (250, 216, 140)),
    "sigilbound":   ((138, 128, 178), (94, 86, 130),   (54, 48, 82),    (232, 208, 146)),
    "amber":        ((222, 174, 94),  (170, 126, 56),  (110, 78, 30),   (120, 96, 64)),
    "azure":        ((110, 148, 196), (72, 104, 146),  (40, 62, 94),    (206, 220, 236)),
    "teal":         ((98, 158, 154),  (62, 112, 110),  (32, 70, 70),    (206, 232, 226)),
    "crimson":      ((184, 94, 90),   (134, 60, 58),   (82, 32, 32),    (222, 194, 158)),
    "roseweave":    ((204, 148, 162), (152, 102, 116), (96, 60, 72),    (238, 218, 200)),
    "sanctum":      ((212, 204, 184), (158, 150, 132), (100, 94, 80),   (218, 186, 116)),
    "service":      ((152, 146, 132), (106, 101, 90),  (62, 59, 52),    (176, 158, 120)),
}


# ---------------------------------------------------------------------------
# Ramps derived from the game's own item icons
# ---------------------------------------------------------------------------

GEARS_SRC = os.path.join(REPO, "source", "common", "gameplay", "items", "gears")
ICONS_SRC = os.path.join(REPO, "assets", "sprites", "items", "icons")


def _slug(name: str) -> str:
    first = name.split(" ")[0].lower()
    return "".join(c for c in first if c.isalnum())


def icon_ramps() -> Dict[str, Tuple[RGB, RGB, RGB, RGB]]:
    """tier -> (light, mid, dark, accent), sampled from that tier's OWN icon.

    The game already ships a distinct 16x16 icon per armour piece, drawn in the
    right colours. Reading the ramp out of the icon means the worn armour is
    coloured by the same art the player sees in their bag - no invented palette,
    and no way for the two to disagree about what "mithril" looks like.
    """
    import re

    out: Dict[str, Tuple[RGB, RGB, RGB, RGB]] = {}
    for path in glob.glob(os.path.join(GEARS_SRC, "**", "*.tres"), recursive=True):
        text = open(path, encoding="utf-8", errors="replace").read()
        name = re.search(r'item_name\s*=\s*&?"([^"]+)"', text)
        icon = re.search(r'path="res://assets/sprites/items/icons/([^"]+)"', text)
        if not name or not icon:
            continue
        # Torso pieces only: that is the layer we recolour.
        if not re.search(r"slots/torso\.tres", text):
            continue
        tier = _slug(name.group(1).replace("\'", "'"))
        if tier in out:
            continue
        icon_path = os.path.join(ICONS_SRC, icon.group(1))
        if not os.path.exists(icon_path):
            continue
        ramp = sample_ramp(Image.open(icon_path).convert("RGBA"))
        if ramp:
            out[tier] = ramp
    return out


def sample_ramp(icon: Image.Image) -> Tuple[RGB, RGB, RGB, RGB] | None:
    """Pull a (light, mid, dark, accent) ramp out of an item icon.

    The dominant saturated-or-grey colours become the garment ramp; the most
    distinct remaining hue becomes the accent (trim, studs, gems).
    """
    px = icon.load()
    counts: Dict[RGB, int] = {}
    for y in range(icon.height):
        for x in range(icon.width):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            counts[(r, g, b)] = counts.get((r, g, b), 0) + 1
    if len(counts) < 3:
        return None
    # Drop the outline (darkest) so it does not drag the ramp down.
    ordered = sorted(counts, key=luminance)
    darkest = luminance(ordered[0])
    body = [c for c in ordered if luminance(c) > darkest + 10.0]
    if len(body) < 3:
        body = ordered
    body.sort(key=lambda c: -counts[c])
    main = body[: max(3, min(6, len(body)))]
    main.sort(key=luminance)
    dark, mid, light = main[0], main[len(main) // 2], main[-1]
    # Accent: the colour furthest in hue from the garment's own.
    base_hue = hue_of(mid)
    accent = max(
        body,
        key=lambda c: min(abs(hue_of(c) - base_hue), 360 - abs(hue_of(c) - base_hue))
        * (1.0 if sat_of(c) > 0.15 else 0.3),
    )
    return (light, mid, dark, accent)


FAMILY_TIERS: Dict[str, List[str]] = {
    "metal": [
        "copper", "bronze", "iron", "steel", "silver", "gold", "mithril", "adamant",
        "runite", "dragon", "basilisk", "behemoth", "colossus", "godsteel",
        "worldbreaker", "wyrmguard", "ironbane", "ruinplate", "adamantine", "doomforge",
    ],
    "leather": [
        "leather", "studded", "shadow", "eclipse", "nightglass", "phantom", "sirenic",
        "skyrender", "starfall", "tempest", "wraithsilk", "soulbrand", "ghostweave",
        "duskfeather", "silentwing", "canopy", "emberpath", "miststride",
        "nightcourier", "tidepath", "trailwalker",
    ],
    "cloth": [
        "cloth", "apprentice", "scholars", "enchanted", "runewoven", "astral",
        "voidsilk", "aetherborn", "empyrean", "primordial", "ancient", "celestine",
        "eldritch", "firstlight", "sigilbound", "amber", "azure", "teal", "crimson",
        "roseweave", "sanctum", "service",
    ],
}


def luminance(c: RGB) -> float:
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def lerp(a: RGB, b: RGB, t: float) -> RGB:
    return (
        int(round(a[0] + (b[0] - a[0]) * t)),
        int(round(a[1] + (b[1] - a[1]) * t)),
        int(round(a[2] + (b[2] - a[2]) * t)),
    )


def ramp_sample(stops: Sequence[RGB], t: float) -> RGB:
    """Sample a dark->light gradient."""
    if t <= 0.0:
        return stops[0]
    if t >= 1.0:
        return stops[-1]
    span = 1.0 / (len(stops) - 1)
    i = min(int(t / span), len(stops) - 2)
    return lerp(stops[i], stops[i + 1], (t - i * span) / span)


def shade(c: RGB, f: float) -> RGB:
    return (
        max(0, min(255, int(c[0] * f))),
        max(0, min(255, int(c[1] * f))),
        max(0, min(255, int(c[2] * f))),
    )


def hue_of(c: RGB) -> float:
    return colorsys.rgb_to_hsv(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)[0] * 360.0


def sat_of(c: RGB) -> float:
    return colorsys.rgb_to_hsv(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)[1]


def group_palette(source: Image.Image) -> Tuple[List[List[RGB]], List[RGB]]:
    """Split the sheet's palette into MATERIAL groups, plus outline colours.

    These outfits are built from a few materials - leather, cloth, metal fittings -
    each with its own 3-shade ramp. Recolouring them as one ramp (what the first
    version did) collapses every material into a single hue and the garment reads
    as a flat silhouette. Grouping by hue keeps them separate so the tier colour
    lands on the garment while the fittings stay fittings.
    """
    px = source.load()
    counts: Dict[RGB, int] = {}
    for y in range(source.height):
        for x in range(source.width):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            counts[(r, g, b)] = counts.get((r, g, b), 0) + 1
    if not counts:
        return [], []

    outline: List[RGB] = []
    grey: List[RGB] = []
    hued: List[RGB] = []
    darkest = min(luminance(c) for c in counts)
    for c in counts:
        if luminance(c) <= darkest + 12.0:
            outline.append(c)
        elif sat_of(c) < 0.18:
            grey.append(c)
        else:
            hued.append(c)

    # Cluster the saturated colours by hue; 40 degrees separates leather from
    # cloth in these sheets without splitting a single material's own shading.
    clusters: List[List[RGB]] = []
    for c in sorted(hued, key=hue_of):
        if clusters and abs(hue_of(c) - hue_of(clusters[-1][-1])) <= 40.0:
            clusters[-1].append(c)
        else:
            clusters.append([c])
    # Largest material first - that is the garment the tier colour belongs on.
    clusters.sort(key=lambda g: -sum(counts[c] for c in g))
    if grey:
        clusters.append(sorted(grey, key=luminance))
    return clusters, outline


def build_map(source: Image.Image, ramp: Sequence[RGB]) -> Dict[RGB, RGB]:
    """Map each material group onto its own target ramp.

    group 0  -> the tier colour        (the garment itself)
    group 1  -> a darker companion     (secondary cloth: straps, sleeves, lining)
    greys    -> the tier accent        (buckles, studs, plate fittings)
    outline  -> untouched              (the silhouette must survive on dark ground)
    """
    light, mid, dark, accent = ramp[0], ramp[1], ramp[2], ramp[3]
    clusters, outline = group_palette(source)
    targets: List[List[RGB]] = [
        [dark, mid, light],
        # Companion: the same hue pushed darker and desaturated toward the accent,
        # so it reads as a second material rather than a clashing colour.
        [shade(dark, 0.62), shade(mid, 0.66), shade(light, 0.70)],
        [shade(accent, 0.55), shade(accent, 0.80), accent],
    ]

    out: Dict[RGB, RGB] = {c: c for c in outline}
    for i, group in enumerate(clusters):
        stops = targets[min(i, len(targets) - 1)]
        ordered = sorted(group, key=luminance)
        if len(ordered) == 1:
            out[ordered[0]] = stops[len(stops) // 2]
            continue
        lo, hi = luminance(ordered[0]), luminance(ordered[-1])
        span = max(1.0, hi - lo)
        for c in ordered:
            out[c] = ramp_sample(stops, (luminance(c) - lo) / span)
    return out


def recolor(source: Image.Image, mapping: Dict[RGB, RGB]) -> Image.Image:
    out = source.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a < 8:
                px[x, y] = (0, 0, 0, 0)
                continue
            nr, ng, nb = mapping.get((r, g, b), (r, g, b))
            px[x, y] = (nr, ng, nb, a)
    return out


def make_icon(body: Image.Image, worn: Image.Image) -> Image.Image:
    """Crop the DOWN-facing standing pose and trim to the worn piece.

    Cropped from the same sheet the character wears, so the inventory picture and
    the body can never drift apart.
    """
    cell_body = body.crop((0, 0, FRAME, FRAME))
    cell_worn = worn.crop((0, 0, FRAME, FRAME))
    stacked = Image.alpha_composite(cell_body, cell_worn)
    box = cell_worn.getbbox() or stacked.getbbox()
    if box is None:
        return stacked.resize((ICON, ICON), Image.NEAREST)
    # Pad the worn bounds a little so the icon shows the piece in context.
    x0, y0, x1, y1 = box
    pad = 3
    x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
    x1, y1 = min(FRAME, x1 + pad), min(FRAME, y1 + pad)
    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    half = side // 2 + 1
    crop = stacked.crop((cx - half, cy - half, cx + half, cy + half))
    return crop.resize((ICON, ICON), Image.NEAREST)


def main() -> int:
    os.makedirs(OUT_SHEETS, exist_ok=True)
    os.makedirs(OUT_ICONS, exist_ok=True)

    body_path = os.path.join(SRC, "0bas", "char_a_p1_0bas_humn_v00.png")
    if not os.path.exists(body_path):
        print("body sheet missing - run import_manaseed.py first")
        return 1
    body = Image.open(body_path).convert("RGBA")

    derived = icon_ramps()
    print("ramps read from the game's own icons: %d" % len(derived))

    written = 0
    missing: List[str] = []
    for family, tiers in FAMILY_TIERS.items():
        # Torso only. The packs have no helmet art (see PaperDoll.GEAR_LAYERS), so
        # generating recoloured hats would only produce wrong-looking "helmets".
        parts: Dict[str, Image.Image] = {}
        for part, (player, code) in FAMILY_PARTS.get(family, {}).items():
            pp = os.path.join(
                SRC, player, "char_a_p1_%s_%s_v%s.png" % (player, code, SOURCE_VARIANT)
            )
            if os.path.exists(pp):
                parts[part] = Image.open(pp).convert("RGBA")
            else:
                missing.append(pp)

        for slot in ("torso",):
            bands = FAMILY_BANDS[family]
            sources: Dict[str, Image.Image] = {}
            for code in bands:
                sp = os.path.join(
                    SRC, "1out", "char_a_p1_1out_%s_v%s.png" % (code, SOURCE_VARIANT)
                )
                if os.path.exists(sp):
                    sources[code] = Image.open(sp).convert("RGBA")
                else:
                    missing.append(sp)
            if not sources:
                continue
            for index, tier in enumerate(tiers):
                band = bands[min(index * len(bands) // max(1, len(tiers)), len(bands) - 1)]
                source = sources.get(band) or next(iter(sources.values()))
                ramp = derived.get(tier) or RAMPS.get(tier)
                if ramp is None:
                    missing.append("ramp for %s" % tier)
                    continue
                mapping = build_map(source, ramp)
                sheet = recolor(source, mapping)
                sheet.save(os.path.join(OUT_SHEETS, "%s_%s.png" % (tier, slot)))
                # Same ramp across the whole set so the pieces read as one outfit.
                for part, part_src in parts.items():
                    recolor(part_src, build_map(part_src, ramp)).save(
                        os.path.join(OUT_SHEETS, "%s_%s.png" % (tier, part))
                    )
                    written += 1
                full = sheet.copy()
                for part_src in parts.values():
                    full = Image.alpha_composite(
                        full, recolor(part_src, build_map(part_src, ramp))
                    )
                make_icon(body, full).save(
                    os.path.join(OUT_ICONS, "%s_%s.png" % (tier, slot))
                )
                written += 2

    print("wrote %d files" % written)
    print("  sheets -> %s" % os.path.relpath(OUT_SHEETS, REPO))
    print("  icons  -> %s" % os.path.relpath(OUT_ICONS, REPO))
    total = sum(len(t) for t in FAMILY_TIERS.values())
    print("  %d tiers x 2 slots, each with a matching icon" % total)
    if missing:
        print("\nMISSING:")
        for m in sorted(set(missing)):
            print("  -", m)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
