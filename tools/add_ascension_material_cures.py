#!/usr/bin/env python3
"""Create Ascension hide/fiber materials so workbench Materials tab can cure/weave them.

Leather: hide_* → *_leather (archery tiers)
Cloth:   fiber_* → *_cloth (archery + magic tiers)

Run, then:
  godot --headless --path . -s tools/update_items_index.gd
  godot --headless --path . -s tools/wire_ascension_gear.gd
"""

from __future__ import annotations

import hashlib
import shutil
import uuid
from pathlib import Path

from PIL import Image, ImageEnhance

ROOT = Path("/workspace")
ICON_DIR = ROOT / "assets/sprites/items/icons"
MAT_LEATHER = ROOT / "source/common/gameplay/items/materials/leather"
MAT_CLOTH = ROOT / "source/common/gameplay/items/materials/cloth"
UID_MATERIAL = "uid://nsr1timk430j"

ARCHERY = {
    40: "Wraithsilk",
    50: "Nightglass",
    60: "Tempest",
    70: "Skyrender",
    80: "Eclipse",
    90: "Starfall",
}
MAGIC = {
    40: "Runewoven",
    50: "Astral",
    60: "Voidsilk",
    70: "Aetherborn",
    80: "Empyrean",
    90: "Primordial",
}


def new_uid() -> str:
    return "uid://" + uuid.uuid4().hex[:13]


def import_stub(rel: str, uid: str) -> str:
    h = hashlib.md5(rel.encode()).hexdigest()
    stem = Path(rel).name
    return f"""[remap]

importer="texture"
type="CompressedTexture2D"
uid="{uid}"
path="res://.godot/imported/{stem}-{h}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="res://{rel}"
dest_files=["res://.godot/imported/{stem}-{h}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def write_png(im: Image.Image, dest: Path) -> tuple[str, str]:
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest)
    uid = new_uid()
    rel = str(dest.relative_to(ROOT)).replace("\\", "/")
    (dest.with_suffix(dest.suffix + ".import")).write_text(import_stub(rel, uid))
    return f"res://{rel}", uid


def recolor(im: Image.Image, hue_shift: float, sat: float = 1.15, bright: float = 1.05) -> Image.Image:
    rgba = im.convert("RGBA")
    r, g, b, a = rgba.split()
    buckets = [
        (r, g, b),
        (g, b, r),
        (b, r, g),
        (r, b, g),
        (g, r, b),
        (b, g, r),
    ]
    idx = int(hue_shift) % len(buckets)
    nr, ng, nb = buckets[idx]
    out = Image.merge("RGBA", (nr, ng, nb, a))
    rgb = out.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(sat)
    rgb = ImageEnhance.Brightness(rgb).enhance(bright)
    out2 = rgb.convert("RGBA")
    out2.putalpha(a)
    return out2


def material_tres(
    path: Path,
    *,
    item_name: str,
    slug: str,
    icon_res: str,
    icon_uid: str,
    description: str,
    vendor: int,
) -> None:
    body = f'''[gd_resource type="Resource" script_class="MaterialItem" format=3]

[ext_resource type="Texture2D" uid="{icon_uid}" path="{icon_res}" id="1_icon"]
[ext_resource type="Script" uid="{UID_MATERIAL}" path="res://source/common/gameplay/items/material_item.gd" id="2_script"]

[resource]
script = ExtResource("2_script")
item_name = &"{item_name}"
item_icon = ExtResource("1_icon")
description = "{description}"
holdable = false
can_trade = true
vendor_value = {vendor}
stack_limit = 50
tags = PackedStringArray("ascension", "material")
metadata/_custom_type_script = "{UID_MATERIAL}"
metadata/slug = &"{slug}"
'''
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)


def tint_from(src_name: str, dest_name: str, hue: int, sat: float = 1.25, bright: float = 1.05) -> tuple[str, str]:
    src = ICON_DIR / src_name
    if not src.exists():
        src = ICON_DIR / "mat_hide_forest.png"
    im = Image.open(src).convert("RGBA")
    im = recolor(im, hue, sat=sat, bright=bright)
    return write_png(im, ICON_DIR / dest_name)


def main() -> None:
    created = 0
    for i, (tier, name) in enumerate(ARCHERY.items()):
        slug = name.lower()
        hide_path = MAT_LEATHER / f"hide_{slug}.tres"
        if not hide_path.exists():
            icon_res, icon_uid = tint_from("mat_hide_bandit.png", f"mat_hide_{slug}.png", i + 1, sat=1.35, bright=0.95)
            material_tres(
                hide_path,
                item_name=f"{name} Hide",
                slug=f"hide_{slug}",
                icon_res=icon_res,
                icon_uid=icon_uid,
                description=f"Raw {name.lower()} hide. Cures into {name} Leather at a workbench.",
                vendor=4 + i * 3,
            )
            created += 1
            print("hide", slug)

        fiber_path = MAT_CLOTH / f"fiber_{slug}.tres"
        if not fiber_path.exists():
            icon_res, icon_uid = tint_from("mat_cloth_forest.png", f"mat_fiber_{slug}.png", i + 2, sat=1.2, bright=0.9)
            material_tres(
                fiber_path,
                item_name=f"{name} Fiber",
                slug=f"fiber_{slug}",
                icon_res=icon_res,
                icon_uid=icon_uid,
                description=f"Tough {name.lower()} fiber. Weaves into {name} Cloth at a workbench.",
                vendor=4 + i * 3,
            )
            created += 1
            print("fiber archery", slug)

    for i, (tier, name) in enumerate(MAGIC.items()):
        slug = name.lower()
        fiber_path = MAT_CLOTH / f"fiber_{slug}.tres"
        if not fiber_path.exists():
            icon_res, icon_uid = tint_from("mat_cloth_sewer.png", f"mat_fiber_{slug}.png", i + 3, sat=1.3, bright=1.0)
            material_tres(
                fiber_path,
                item_name=f"{name} Fiber",
                slug=f"fiber_{slug}",
                icon_res=icon_res,
                icon_uid=icon_uid,
                description=f"Arcane {name.lower()} fiber. Weaves into {name} Cloth at a workbench.",
                vendor=5 + i * 3,
            )
            created += 1
            print("fiber magic", slug)

    print(f"created {created} material resources")


if __name__ == "__main__":
    main()
