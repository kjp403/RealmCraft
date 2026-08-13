#!/usr/bin/env python3
"""Build the VFX Vault map scene (staff-only cosmetics testing room).

    python tools/build_vfx_vault.py

The room reuses the Smith House interior's verified tile layers rather than
stamping new atlas coordinates -- the tile_map_data byte arrays are copied
VERBATIM, so the floor/walls are known-good art instead of guessed cells.
Everything else (stations, shopkeepers, quest NPCs) is dropped; the vault gets
the Curator and one exit warper.

Written as a text transform, not a Godot `-s` script, on purpose: saving a scene
headlessly strips `uid=` from the file and from every ext_resource in it, which
silently breaks the tileset/script references.
"""

from __future__ import annotations

import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "source/common/gameplay/maps/maps/smith_house/inside_map.tscn")
OUT_DIR = os.path.join(REPO, "source/common/gameplay/maps/maps/vfx_vault")
OUT = os.path.join(OUT_DIR, "vfx_vault.tscn")


def ext_line(text: str, needle: str) -> str:
    """Copy an ext_resource line verbatim so its uid= survives."""
    for line in text.splitlines():
        if line.startswith("[ext_resource") and needle in line:
            return line
    raise SystemExit(f"ext_resource not found for {needle}")


def node_block(text: str, name: str) -> str:
    """Extract one [node name="..."] block including its properties."""
    m = re.search(
        r'^\[node name="%s"[^\]]*\]\n(?:(?!\[node )[^\n]*\n)*' % re.escape(name),
        text,
        re.M,
    )
    if not m:
        raise SystemExit(f"node not found: {name}")
    return m.group(0).rstrip("\n")


def main() -> None:
    src = open(SRC, encoding="utf-8").read()
    os.makedirs(OUT_DIR, exist_ok=True)

    map_script = ext_line(src, "maps/map.gd")
    tileset = ext_line(src, "buildings_inside_tileset.tres")
    warper = ext_line(src, "warper/warper.tscn")
    overworld = ext_line(src, "instance_collection/overworld.tres")
    npc_scene = ext_line(src, "npc/npc.tscn")

    # Re-id the copied ext_resources to a clean local numbering.
    remap = {
        map_script: ("1_map", None),
        tileset: ("2_ts", None),
        warper: ("3_warp", None),
        overworld: ("4_overworld", None),
        npc_scene: ("5_npc", None),
    }
    ext_lines = []
    id_swaps = {}
    for line, (new_id, _) in remap.items():
        # Anchor on the TRAILING id="..." attribute. A bare id=" pattern also
        # matches inside uid="...", which silently destroys the uid.
        old_id = re.search(r'\sid="([^"]+)"\]', line).group(1)
        id_swaps[old_id] = new_id
        ext_lines.append(re.sub(r'(\s)id="[^"]+"\]', r'\1id="%s"]' % new_id, line))
    ext_lines.append(
        '[ext_resource type="Resource" '
        'path="res://source/common/gameplay/characters/npc/npcs/vfx_curator.tres" id="6_curator"]'
    )

    layers = []
    for layer in ("Ground", "Walls", "Props"):
        block = node_block(src, layer)
        for old, new in id_swaps.items():
            block = block.replace('ExtResource("%s")' % old, 'ExtResource("%s")' % new)
        # unique_id values are per-scene; drop them and let Godot reassign.
        block = re.sub(r"\s+unique_id=\d+", "", block)
        layers.append(block)

    # No uid= in the header: Godot mints one on first import. A hand-written uid
    # risks characters outside its base-34 alphabet and gets silently rewritten.
    parts = [
        "[gd_scene format=4]",
        "",
        "\n".join(ext_lines),
        "",
        '[node name="VfxVault" type="Node2D"]',
        "y_sort_enabled = true",
        'script = ExtResource("1_map")',
        "",
        "\n\n".join(layers),
        "",
        # Arrival marker. A Warper with NO target_instance never warps anyone (the
        # server's handler requires target_instance, and Warper.gate_level() is
        # null-safe) -- it exists purely so Map.get_spawn_position(0) resolves to a
        # known-interior tile. Without it the lookup falls through to "any warper",
        # which is the Exit door, and logs a warning on every entry.
        # World (0, 256) is tile (0, 16) at 16 px: the floor centre, verified
        # surrounded by ground for 2 tiles in every direction.
        '[node name="Arrival" parent="." instance=ExtResource("3_warp")]',
        "position = Vector2(0, 256)",
        "warper_id = 0",
        "",
        # Exit only. Nothing anywhere in the world warps INTO the vault -- entry is
        # /vault, and AdminOnlyInstanceResource refuses non-staff regardless.
        '[node name="Exit" parent="." instance=ExtResource("3_warp")]',
        "position = Vector2(8, 433)",
        "scale = Vector2(1.6, 1)",
        'target_instance = ExtResource("4_overworld")',
        "warper_id = 5",
        "target_id = 4",
        "",
        '[node name="Curator" parent="." instance=ExtResource("5_npc")]',
        "position = Vector2(0, 300)",
        'npc_resource = ExtResource("6_curator")',
        "",
    ]
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(parts))
    print(f"wrote {os.path.relpath(OUT, REPO)}")


if __name__ == "__main__":
    main()
