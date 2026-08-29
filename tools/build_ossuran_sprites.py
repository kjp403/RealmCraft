#!/usr/bin/env python
"""Recolour the three Ossuran phase-2 pillars from the stone golem base.

NOT the boss. Ossuran already exists as
`npc/types/bosses/cleetus.tres` ("Ossuran, Kindled and Cold") with purpose-made
cleetus / cleetus_frost art and its own kindled->cold phase-2 skin swap. This
tool only produces the three pillars the encounter adds, which have no art of
their own.

Each pillar owns a combat style and the COLOUR IS THE TELL: a player needs to
know at a glance which pillar is winding up and what it is about to hit them
with. The three hues are matched to the telegraph elements the pillars actually
fire (FIRE / EARTH / STORM), so the floor marker and the thing that drew it can
never disagree.

THE RECOLOUR IS INDEXED, NOT A TINT. Every opaque pixel's luminance is bucketed
into one of RAMP_STEPS bands and replaced with an authored colour for that band:

  * A multiply/hue tint keeps the source's own colour relationships and just
    washes them, which on grey stone gives grey stone wearing a filter.
    Remapping by luminance re-authors the palette outright.
  * Bucketing keeps HARD palette boundaries -- the stepped edges pixel art is
    made of, and the same rule the pad shaders follow. A continuous gradient
    would blur exactly those edges.

Alpha is copied through untouched, so each silhouette is bit-identical to the
source and every AtlasTexture region in the cloned .tres still lines up. Nothing
here moves a pixel, so the source's per-clip baseline survives intact.

    python tools/build_ossuran_sprites.py
"""

from __future__ import annotations

import pathlib
import re
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
FRAMES_DIR = ROOT / "source/common/gameplay/characters/sprite_frames"
SRC_DIR = ROOT / "assets/sprites/characters/stone_base"
SRC_TRES = FRAMES_DIR / "stone_base.tres"
CLIPS = ["death", "idle", "run"]

RAMP_STEPS = 6

RAMPS: dict[str, list[tuple[int, int, int]]] = {
    # Red -- melee. Matches ElementalTelegraph FIRE.
    "ossuran_pillar_ember": [
        (18, 10, 12),
        (54, 20, 18),
        (104, 32, 22),
        (168, 58, 26),
        (228, 110, 38),
        (255, 200, 128),
    ],
    # Green -- archery. Matches the EARTH element added for this fight.
    "ossuran_pillar_thorn": [
        (12, 22, 12),
        (26, 50, 22),
        (46, 92, 34),
        (78, 140, 46),
        (134, 194, 74),
        (214, 244, 150),
    ],
    # Purple -- magic. Matches ElementalTelegraph STORM.
    "ossuran_pillar_hex": [
        (16, 12, 28),
        (38, 26, 62),
        (68, 44, 110),
        (108, 70, 168),
        (162, 118, 226),
        (226, 200, 255),
    ],
}

# Pillars are lit objects, not dark bodies: a little <1 so the carved detail
# stays visible instead of sinking into the shadow stops.
GAMMA = 0.95

# Rec. 601 luma weights. Chosen over a flat mean because the source's greens
# would otherwise map far brighter than they read to the eye, flattening the
# shading into the top two bands.
LUMA = (0.299, 0.587, 0.114)


def remap(image: Image.Image, ramp: list[tuple[int, int, int]]) -> Image.Image:
    """Return a copy of image with every opaque pixel remapped through ramp."""
    src = image.convert("RGBA")
    width, height = src.size
    pixels = src.load()
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    dst = out.load()

    # Normalise against the sprite's OWN range, measured by PERCENTILE rather
    # than min/max. A single near-black outline pixel or one specular highlight
    # is enough to stretch a min/max span across the whole scale and squash every
    # real body pixel into the middle, which comes out flat.
    lums: list[float] = []
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            lums.append(r * LUMA[0] + g * LUMA[1] + b * LUMA[2])
    if not lums:
        return out
    lums.sort()
    lo = lums[int(len(lums) * 0.04)]
    hi = lums[int(len(lums) * 0.96) - 1 if len(lums) > 1 else 0]
    span = max(1.0, hi - lo)

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            lum = r * LUMA[0] + g * LUMA[1] + b * LUMA[2]
            t = max(0.0, min(1.0, (lum - lo) / span)) ** GAMMA
            index = max(0, min(RAMP_STEPS - 1, int(round(t * (RAMP_STEPS - 1)))))
            cr, cg, cb = ramp[index]
            dst[x, y] = (cr, cg, cb, a)
    return out


def build_tres(skin: str) -> str:
    """Clone stone_base's SpriteFrames, repointed at this pillar's textures.

    Cloned as TEXT rather than rebuilt through ResourceSaver: a headless save
    strips uid= from a .tres and every ext_resource in it. Copying the source's
    text keeps frame regions, ordering and clip speeds byte-identical to a
    resource that is known to work.

    STRIPPING uid= IS LOAD-BEARING, not tidiness. Godot resolves an ext_resource
    by uid FIRST and only falls back to path -- so a clone that kept the source's
    uids would silently load the ORIGINAL stone textures no matter what the paths
    say, and the recolour would never appear in game.
    """
    text = SRC_TRES.read_text(encoding="utf-8")
    text = re.sub(r'\suid="uid://[^"]*"', "", text)
    text = text.replace(
        "res://assets/sprites/characters/stone_base/stone_base_",
        f"res://assets/sprites/characters/{skin}/{skin}_",
    )
    # Drop the source's registry stamps -- these are new resources and must be
    # allocated fresh, never inherit another entry's id.
    text = re.sub(r"^metadata/slug = .*$", "", text, flags=re.MULTILINE)
    text = re.sub(r"^metadata/id = .*$", "", text, flags=re.MULTILINE)
    return text.rstrip() + "\n"


def main() -> int:
    if not SRC_DIR.is_dir():
        print(f"missing source art: {SRC_DIR}", file=sys.stderr)
        return 1

    for skin, ramp in RAMPS.items():
        skin_dir = ROOT / "assets/sprites/characters" / skin
        skin_dir.mkdir(parents=True, exist_ok=True)
        for clip in CLIPS:
            src_path = SRC_DIR / f"stone_base_{clip}.png"
            if not src_path.is_file():
                print(f"missing clip: {src_path}", file=sys.stderr)
                return 1
            remap(Image.open(src_path), ramp).save(skin_dir / f"{skin}_{clip}.png")
        (FRAMES_DIR / f"{skin}.tres").write_text(build_tres(skin), encoding="utf-8")
        print(f"  {skin}: {len(CLIPS)} clips + SpriteFrames")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
