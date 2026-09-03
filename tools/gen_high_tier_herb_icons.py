#!/usr/bin/env python3
"""Draw the six high-tier Herblore farming herbs and their six combination
draughts, plus the Empty Vial the mixer hands back.

Same approach as tools/gen_poison_icons.py, and for the same reason: everything
is derived from art already in the project, so the new items sit in the pack's
own light-to-dark ramp instead of reading as bolted-on. Only SATURATED pixels
are hue-rotated, which leaves the blue-grey glass, the cork and the black/white
outline exactly where the pack put them.

Herb cells are picked for SILHOUETTE first, so the six read apart at bag-icon
size: an upright mushroom, a flower spike, a gnarled root, a bulb, a broad cap,
a spiked succulent. Potion bottles reuse the pack's OWN size ladder rather than
scaling one bottle, which would blur the smooth shading.

This script also writes tools/high_tier_herb_sprites.json — the 16x16
Aseprite specification for each herb, so a later bespoke art pass has the
palette and the intent written down rather than inferred from a recolour.

Usage:  python tools/gen_high_tier_herb_icons.py
"""

from __future__ import annotations

import colorsys
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "assets", "sprites", "items", "icons")
NODE_DIR = os.path.join(
    ROOT, "assets", "sprites", "environment", "props", "herbs"
)
# tools/, NOT assets/_import/ — that whole tree is gitignored, so a spec
# written there is a spec that never reaches anyone else.
SPEC_DIR = os.path.join(ROOT, "tools")
VEGETATION = os.path.join(
    ROOT, "assets", "sprites", "environment", "props", "vegetation.png"
)

# Neutral pixels (glass, outline, pack shading) keep their colour. Anything at
# or above this saturation is "the liquid / the plant" and gets recoloured.
SATURATION_FLOOR = 0.35

# Hue bands, in turns. Warm source hues land at the low end of the band and cool
# ones at the high end, so the pack's own ramp survives the rotation instead of
# flattening into one colour.
RUST = (0.03, 0.09)      # oxidised copper into hazard orange
NIGHTSHADE = (0.74, 0.86)  # deep violet
MAGMA = (0.02, 0.10)     # dark ember into yellow-orange
GOLD = (0.11, 0.16)      # golden yellow
GLOOM = (0.55, 0.68)     # midnight blue into cyan
SLATE = (0.55, 0.60)     # desaturated toward grey, see the sat scale
CRIMSON = (0.96, 1.02)

# name -> (cell in vegetation.png, hue band, saturation scale)
HERBS = {
    "herb_rust_spore_cap.png": ((32, 336), RUST, 1.35),
    "herb_nightshade_bramble.png": ((224, 176), NIGHTSHADE, 1.15),
    "herb_magma_root.png": ((96, 272), MAGMA, 1.5),
    "herb_sun_lit_lotus.png": ((16, 352), GOLD, 1.25),
    "herb_gloom_spore_cap.png": ((112, 336), GLOOM, 1.2),
    "herb_iron_spike_thorn.png": ((80, 144), SLATE, 0.22),
}

# Herbs that get a second accent pass over their BRIGHTEST pixels, so the
# description's second colour actually appears rather than being implied:
# hazard-orange cracks, toxic-green berries, magma veins, a white-hot core,
# cyan spores, crimson barbs.
# name -> (hue band, saturation scale, brightness floor 0-1, saturation floor)
ACCENTS = {
    "herb_rust_spore_cap.png": ((0.06, 0.09), 1.6, 0.72, SATURATION_FLOOR),
    "herb_nightshade_bramble.png": ((0.25, 0.33), 1.5, 0.66, SATURATION_FLOOR),
    "herb_magma_root.png": ((0.10, 0.14), 1.8, 0.62, SATURATION_FLOOR),
    "herb_gloom_spore_cap.png": ((0.47, 0.52), 1.5, 0.74, SATURATION_FLOOR),
    # Barbs only, on a body that has already been desaturated to slate — so the
    # saturation floor drops to 0 and the BRIGHTNESS floor does all the picking.
    "herb_iron_spike_thorn.png": (CRIMSON, 2.2, 0.68, 0.0),
}

# Potion bottles. The source icon is chosen for its SIZE: Icon301 is the thin
# vial, 302 the conical flask, 303 the round flask, 305 the wide bottle. A
# combination draught takes a BIGGER vessel than its own inputs, so the bag
# reads the upgrade before the tooltip does.
POTIONS = {
    "potion_corrosive_ember.png": ("Icon305.png", RUST, 1.3),
    "potion_venom_draught.png": ("Icon304.png", (0.24, 0.33), 1.2),
    "potion_cinder_guard.png": ("Icon303.png", MAGMA, 1.35),
    "potion_aegis_elixir.png": ("Icon302.png", GOLD, 1.1),
    "potion_shadowveil.png": ("Icon301.png", GLOOM, 1.0),
    "potion_provocation.png": ("Icon307.png", CRIMSON, 1.2),
}

# The Empty Vial is the Vial of Water with its liquid taken out: the same glass,
# the same outline, nothing inside. Drained rather than redrawn so the pair read
# as the same object in two states.
# The WORLD PLANT for each patch, as a true 32x32 sprite.
#
# These are NOT the bag icon scaled up, and they are NOT a raw atlas region.
# Pointing a node at a raw region did two bad things at once: the plant kept the
# pack's original green/tan colours while the bag icon was recoloured, so you
# walked up to a green bush and received a grey metal thorn; and a 32x32 region
# anchored on a 16x16 icon cell dragged in three NEIGHBOURING cells, which is why
# a patch showed two mushrooms, or a completely unrelated plant.
#
# Cells here are picked from the 32x32 grid as SELF-CONTAINED plants, then run
# through the same recolour as their icon so world and bag agree, then cleaned of
# any fragment of a neighbour that still crept in.
# name -> (cell, hue band, saturation scale, accent or None)
NODES = {
    "node_rust_spore_cap.png": ((0, 336), RUST, 1.35, ((0.06, 0.09), 1.6, 0.72, SATURATION_FLOOR)),
    "node_nightshade_bramble.png": ((192, 160), NIGHTSHADE, 1.15, ((0.25, 0.33), 1.5, 0.66, SATURATION_FLOOR)),
    "node_magma_root.png": ((144, 272), MAGMA, 1.5, ((0.10, 0.14), 1.8, 0.62, SATURATION_FLOOR)),
    "node_sun_lit_lotus.png": ((80, 240), GOLD, 1.25, None),
    "node_gloom_spore_cap.png": ((0, 352), GLOOM, 1.2, ((0.47, 0.52), 1.5, 0.74, SATURATION_FLOOR)),
    "node_iron_spike_thorn.png": ((144, 224), SLATE, 0.34, (CRIMSON, 2.4, 0.93, 0.0)),
}

EMPTY_VIAL_SOURCE = "Icon309.png"
EMPTY_VIAL_NAME = "empty_vial.png"


def _recolour(
    image: Image.Image,
    hue_band: tuple[float, float],
    saturation_scale: float = 1.0,
    value_floor: float = 0.0,
    min_saturation: float = SATURATION_FLOOR,
) -> Image.Image:
    """Rotate every saturated pixel into [hue_band].

    [value_floor] restricts the pass to pixels at least that bright, which is
    how the accent pass hits only the highlights (the cracks, the berries, the
    veins) and leaves the body of the plant alone.

    [min_saturation] has to be overridable because of Iron-Spike Thorn: its body
    pass DESATURATES the plant to slate, which drops every pixel below the
    default floor, so a following accent pass at the default would find nothing
    to paint and the crimson barbs would silently never appear.
    """
    out = image.copy()
    pixels = out.load()
    width, height = out.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if s < min_saturation or v < value_floor:
                continue
            lo, hi = hue_band
            # Map the source hue's position in the colour wheel onto the band so
            # the pack's own dark-to-light ordering is preserved.
            h2 = (lo + (hi - lo) * ((h * 3.0) % 1.0)) % 1.0
            s2 = min(1.0, s * saturation_scale)
            r2, g2, b2 = colorsys.hsv_to_rgb(h2, s2, v)
            pixels[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    return out


def _clean(image: Image.Image, keep_ratio: float = 0.30) -> Image.Image:
    """Drop disconnected fragments and centre what is left.

    Even a well-chosen 32x32 cell can clip a corner of the plant next door, and
    a stray two-pixel blob floating beside a herb reads as a rendering fault
    rather than as art. Anything smaller than [keep_ratio] of the largest blob
    is a fragment, not the plant.
    """
    pixels = image.load()
    width, height = image.size
    seen = [[False] * height for _ in range(width)]
    blobs: list[list[tuple[int, int]]] = []
    for x in range(width):
        for y in range(height):
            if seen[x][y] or pixels[x, y][3] <= 40:
                continue
            stack = [(x, y)]
            seen[x][y] = True
            blob = []
            while stack:
                cx, cy = stack.pop()
                blob.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if (0 <= nx < width and 0 <= ny < height
                                and not seen[nx][ny] and pixels[nx, ny][3] > 40):
                            seen[nx][ny] = True
                            stack.append((nx, ny))
            blobs.append(blob)
    if not blobs:
        return image
    largest = max(len(b) for b in blobs)
    keep = [p for b in blobs if len(b) >= largest * keep_ratio for p in b]
    kept = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    kp = kept.load()
    for x, y in keep:
        kp[x, y] = pixels[x, y]
    xs = [p[0] for p in keep]
    ys = [p[1] for p in keep]
    offset = (
        (width - (max(xs) - min(xs) + 1)) // 2 - min(xs),
        (height - (max(ys) - min(ys) + 1)) // 2 - min(ys),
    )
    centred = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    centred.paste(kept, offset, kept)
    return centred


# Sprites that need their SHADOWS lifted, not just their hue rotated.
# name -> (value scale, value offset)
#
# The Iron-Spike Thorn's WORLD PLANT only. It is the one herb desaturated to bare
# slate, and it
# grows in the Starfall Mining Cave, which is unlit — a dark grey plant on a dark
# cave floor is a patch players walk past. The offset is what does the work: a
# plain multiply leaves black pixels black, so the shadows have to be raised off
# the floor rather than scaled.
#
# Its accent floor rises to match (see ACCENTS). Brightening the body without
# also raising that floor pushes every pixel over the accent threshold and paints
# the whole plant crimson, which is a red plant, not a steel one with red barbs.
LIFT = {
    "node_iron_spike_thorn.png": (1.5, 0.25),
}


def _lift(image: Image.Image, scale: float, offset: float) -> Image.Image:
    """Raise every visible pixel's brightness, shadows included."""
    out = image.copy()
    pixels = out.load()
    width, height = out.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            r2, g2, b2 = colorsys.hsv_to_rgb(h, s, min(1.0, v * scale + offset))
            pixels[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    return out


def _cell(atlas: Image.Image, origin: tuple[int, int]) -> Image.Image:
    """A 16x16 cell doubled to the 32x32 the bag grid draws items at."""
    x, y = origin
    return atlas.crop((x, y, x + 16, y + 16)).resize((32, 32), Image.NEAREST)


def _drain(image: Image.Image) -> Image.Image:
    """Strip the liquid out of a filled vial: saturated pixels become the pale
    blue-grey of the glass they sit behind."""
    out = image.copy()
    pixels = out.load()
    width, height = out.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            _, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if s < SATURATION_FLOOR:
                continue
            # Keep the pixel's VALUE so the glass keeps its shading, and drop it
            # onto the pack's own cool neutral rather than to flat grey.
            r2, g2, b2 = colorsys.hsv_to_rgb(0.58, 0.12, min(1.0, v * 1.08))
            pixels[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    return out


# The 16x16 Aseprite brief for each herb. Written to disk beside the generated
# placeholders so a bespoke art pass has the palette and the read-at-a-glance
# intent recorded, rather than reverse-engineering it from a hue rotation.
#
# "read" is the ONE thing the sprite has to communicate at bag size; when a
# detail fights it, the detail loses.
SPRITE_SPECS = {
    "rust_spore_cap": {
        "size": "16x16",
        "read": "upright mushroom, cap wider than the stalk, cracked",
        "silhouette": "cap occupies rows 3-8 spanning 10px; stalk 3px wide, rows 9-13",
        "palette": {
            "outline": "#2a1710",
            "cap_shadow": "#6b3a1c",
            "cap_mid": "#a35a24",
            "cap_light": "#c8762f",
            "crack": "#ff8c1a",
            "crack_hot": "#ffc65c",
            "stalk": "#8a6a4e",
        },
        "detail": "3-4 hazard-orange cracks radiating from the cap crown; brightest pixel at each crack mouth, never more than 6 accent pixels total",
        "anim": "none (still node art doubles the icon)",
    },
    "nightshade_bramble": {
        "size": "16x16",
        "read": "thorny vine arcing bottom-left to top-right, berries reading first",
        "silhouette": "vine 2px wide with 4 outward barbs; 3 berries clustered upper right",
        "palette": {
            "outline": "#1b1024",
            "vine_dark": "#3d2352",
            "vine_mid": "#5c3579",
            "thorn": "#7a4a9c",
            "berry_dark": "#3f7a24",
            "berry_mid": "#63c22e",
            "berry_glow": "#a6ff5e",
        },
        "detail": "berries pulse: 2-frame idle swapping berry_mid and berry_glow, 0.5s per frame",
        "anim": "2 frames, berry pulse",
    },
    "magma_root": {
        "size": "16x16",
        "read": "gnarled forked root, dark, lit from inside",
        "silhouette": "thick vertical root rows 2-14, two side forks, never symmetric",
        "palette": {
            "outline": "#141214",
            "root_dark": "#2e2b2e",
            "root_mid": "#454045",
            "vein_dull": "#8a3d0d",
            "vein_mid": "#e0721a",
            "vein_hot": "#ffc23d",
        },
        "detail": "veins run ALONG the root's length, never across it; hottest pixels deepest in the crevices so the light reads as internal",
        "anim": "2 frames, vein glow breathing",
    },
    "sun_lit_lotus": {
        "size": "16x16",
        "read": "symmetrical 8-petal flower seen from directly above",
        "silhouette": "petals on the 8 compass points, tips at the 16px edge, core 4x4 centred",
        "palette": {
            "outline": "#6b4a06",
            "petal_shadow": "#c9960f",
            "petal_mid": "#f0c02a",
            "petal_light": "#ffe066",
            "core_glow": "#fffbe6",
            "core_pure": "#ffffff",
        },
        "detail": "the ONLY radially symmetric herb in the set — symmetry is its read, so mirror all four quadrants exactly; core is pure white with a 1px glow ring",
        "anim": "2 frames, core glow swell",
    },
    "gloom_spore_cap": {
        "size": "16x16",
        "read": "broad flat mushroom cap, dark, with spores drifting off it",
        "silhouette": "wide low cap rows 5-9 spanning 12px, short 2px stalk rows 10-13",
        "palette": {
            "outline": "#0b1024",
            "cap_dark": "#182347",
            "cap_mid": "#26386b",
            "cap_light": "#38508f",
            "spore_dim": "#3fb8c4",
            "spore_bright": "#8ff6ff",
        },
        "detail": "4-6 loose spore pixels above the cap, unattached to the silhouette; they are the read, so give them the brightest value on the sprite",
        "anim": "4 frames, spores rising and looping",
    },
    "iron_spike_thorn": {
        "size": "16x16",
        "read": "low succulent rosette of straight rigid blades",
        "silhouette": "5 blades fanning from a 3px base, each 1-2px wide, all straight (no curves — curves read as grass)",
        "palette": {
            "outline": "#16181c",
            "blade_dark": "#3a4048",
            "blade_mid": "#5b636e",
            "blade_light": "#8d97a4",
            "barb_dark": "#7a1220",
            "barb_mid": "#c31f33",
            "barb_shine": "#ff5c6e",
        },
        "detail": "one crimson barb at each blade TIP, with a single barb_shine pixel — the metal read comes from the hard light/dark step on the blades, not from a gradient",
        "anim": "none",
    },
}


def main() -> None:
    os.makedirs(ICON_DIR, exist_ok=True)
    os.makedirs(SPEC_DIR, exist_ok=True)
    atlas = Image.open(VEGETATION).convert("RGBA")

    for name, (origin, band, sat) in HERBS.items():
        icon = _recolour(_cell(atlas, origin), band, sat)
        if name in LIFT:
            icon = _lift(icon, *LIFT[name])
        if name in ACCENTS:
            a_band, a_sat, a_floor, a_min_sat = ACCENTS[name]
            icon = _recolour(icon, a_band, a_sat, a_floor, a_min_sat)
        icon.save(os.path.join(ICON_DIR, name))
        print("wrote", name)

    for name, (source, band, sat) in POTIONS.items():
        src = Image.open(os.path.join(ICON_DIR, source)).convert("RGBA")
        _recolour(src, band, sat).save(os.path.join(ICON_DIR, name))
        print("wrote", name)

    os.makedirs(NODE_DIR, exist_ok=True)
    for name, (origin, band, sat, accent) in NODES.items():
        x, y = origin
        node = _clean(atlas.crop((x, y, x + 32, y + 32)))
        node = _recolour(node, band, sat)
        if name in LIFT:
            node = _lift(node, *LIFT[name])
        if accent is not None:
            a_band, a_sat, a_floor, a_min_sat = accent
            node = _recolour(node, a_band, a_sat, a_floor, a_min_sat)
        node.save(os.path.join(NODE_DIR, name))
        print("wrote", name)

    src = Image.open(os.path.join(ICON_DIR, EMPTY_VIAL_SOURCE)).convert("RGBA")
    _drain(src).save(os.path.join(ICON_DIR, EMPTY_VIAL_NAME))
    print("wrote", EMPTY_VIAL_NAME)

    spec_path = os.path.join(SPEC_DIR, "high_tier_herb_sprites.json")
    with open(spec_path, "w", encoding="utf-8") as handle:
        json.dump(SPRITE_SPECS, handle, indent=2)
        handle.write("\n")
    print("wrote", spec_path)


if __name__ == "__main__":
    main()
