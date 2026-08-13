#!/usr/bin/env python3
"""Build SpriteFrames .tres for the Ascended weapon VFX overlays.

Run after tools/gen_ascended_vfx.py:

    python tools/gen_ascended_vfx.py assets/sprites/vfx/weapon_fx
    python tools/build_weapon_fx_frames.py

These are NOT cosmetics in the content registry. There is exactly one purchasable
cosmetic ("Ascended Radiance"); these files are a LOOKUP keyed by the weapon's
art slug, resolved at equip time from the item's icon path. That is why they live
outside the cosmetics index and are loaded by path rather than by id.

Written as text rather than via ResourceSaver: a headless `-s` run strips `uid=`
from a saved .tres and from every ext_resource in it.
"""

from __future__ import annotations

import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRIPS = os.path.join(REPO, "assets", "sprites", "vfx", "weapon_fx")
OUT = os.path.join(REPO, "source", "common", "gameplay", "cosmetics", "weapon_frames")
CELL = 48
SPEED = 12.0


def frame_count(png_path: str) -> int:
    with open(png_path, "rb") as fh:
        head = fh.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {png_path}")
    width = int.from_bytes(head[16:20], "big")
    if width % CELL:
        raise ValueError(f"{png_path}: width {width} not a multiple of {CELL}")
    return width // CELL


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    made = 0
    for fname in sorted(os.listdir(STRIPS)):
        if not fname.endswith(".png"):
            continue
        slug = fname[:-4]                      # e.g. sword_dawnbreaker_fx
        n = frame_count(os.path.join(STRIPS, fname))
        lines = [
            f'[gd_resource type="SpriteFrames" load_steps={n + 2} format=3]',
            "",
            f'[ext_resource type="Texture2D" path="res://assets/sprites/vfx/weapon_fx/{fname}" id="1_tex"]',
            "",
        ]
        for i in range(n):
            lines += [
                f'[sub_resource type="AtlasTexture" id="f{i}"]',
                'atlas = ExtResource("1_tex")',
                f"region = Rect2({i * CELL}, 0, {CELL}, {CELL})",
                "",
            ]
        frames = ", ".join(
            '{\n"duration": 1.0,\n"texture": SubResource("f%d")\n}' % i for i in range(n)
        )
        lines += [
            "[resource]",
            "animations = [{",
            f'"frames": [{frames}],',
            '"loop": true,',
            '"name": &"loop",',
            f'"speed": {SPEED}',
            "}]",
            "",
        ]
        with open(os.path.join(OUT, f"{slug}.tres"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines))
        made += 1
        print(f"  {slug:<28} {n:>2} frames")
    print(f"WEAPON_FX_FRAMES built={made}")


if __name__ == "__main__":
    main()
