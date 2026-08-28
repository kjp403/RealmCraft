#!/usr/bin/env python
"""Assemble ossuran_arena.tscn from the tile data printed by build_ossuran_arena.

    godot --path . --mode=client res://tools/build_ossuran_arena.tscn > tiles.txt
    python tools/build_ossuran_scene.py tiles.txt

Written as TEXT, never through PackedScene.pack(): packing a live scene rewrites
nodes and silently drops any property that happens to equal its default (the
note build_boss_arena.gd carries, learned the hard way on the woodland map).

GEOMETRY. One map, two sealed rooms, 16px tiles:

    ARENA    tiles  0..47 x  0..33   ->  px    0..768  x   0..544
             interior (inside the 2-tile wall)  px 32..736 x 32..512
    CHAMBER  tiles 64..97 x  4..29   ->  px 1024..1568 x  64..480
             interior                          px 1056..1520 x 96..432

Every placement below is checked against those interiors and against each other,
by `_assert_layout` at the bottom -- the pads, pillars, braziers and spawns must
sit inside the walls and must not overlap, or the fight has bodies standing
inside each other on the first frame.

DEPTH is explicit on every layer, because y-sorting a floor decal makes it
flicker in front of and behind anyone who crosses its pivot line:

    -10  Ground        (the forge floor)
     -9  Ice           (phase-3 overlay, no collision, no navigation)
     -8  FrostOverlay  (the shader wash)
     -2  charge pads   (floor decals, set by ChargePad._ready)
      0  characters    (y-sorted against each other)
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "source/common/gameplay/maps/maps/ossuran/ossuran_arena.tscn"

# --- Layout ------------------------------------------------------------------
ARENA_INTERIOR = (32, 32, 736, 512)      # x0, y0, x1, y1 in px
CHAMBER_INTERIOR = (1056, 96, 1520, 432)

BOSS_SPAWN = (384, 180)
ARENA_RETURN = (384, 430)
ENTRANCE = (384, 486)
EMBER_PAD = (144, 272)
STORM_PAD = (624, 272)
PAD_RADIUS = 48

PILLARS = [(240, 130), (528, 130), (384, 450)]
BRAZIERS = [(110, 110), (658, 110), (110, 434), (658, 434)]

# Light the summoning chamber. Purely decorative — the phase-3 warmth mechanic
# lives in the arena, not here — but an unlit 34x26 box reads as an unfinished
# room, and the gauntlet is a third of the encounter.
CHAMBER_TORCHES = [(1080, 180), (1496, 180), (1080, 360), (1496, 360)]

CHAMBER_SPAWN = (1296, 400)
WAVE_ORIGIN = (1296, 272)
WAVE_SPAWNS = [
    (1120, 140), (1296, 128), (1472, 140),
    (1100, 300), (1492, 300), (1296, 200),
]

# The frost wash covers the arena interior only.
FROST_RECT = (
    ARENA_INTERIOR[0],
    ARENA_INTERIOR[1],
    ARENA_INTERIOR[2] - ARENA_INTERIOR[0],
    ARENA_INTERIOR[3] - ARENA_INTERIOR[1],
)


def _assert_layout() -> list[str]:
    """Fail loudly here rather than discovering it as a visual bug in game."""
    problems: list[str] = []

    def inside(name: str, p: tuple[int, int], box: tuple[int, int, int, int], pad: int = 0) -> None:
        x0, y0, x1, y1 = box
        if not (x0 + pad <= p[0] <= x1 - pad and y0 + pad <= p[1] <= y1 - pad):
            problems.append(f"{name} {p} is outside the room interior {box} (pad {pad})")

    inside("BossSpawn", BOSS_SPAWN, ARENA_INTERIOR, 40)
    inside("ArenaReturn", ARENA_RETURN, ARENA_INTERIOR, 24)
    inside("Entrance", ENTRANCE, ARENA_INTERIOR, 16)
    inside("EmberPad", EMBER_PAD, ARENA_INTERIOR, PAD_RADIUS)
    inside("StormPad", STORM_PAD, ARENA_INTERIOR, PAD_RADIUS)
    for i, p in enumerate(PILLARS):
        inside(f"Pillar{i + 1}", p, ARENA_INTERIOR, 28)
    for i, p in enumerate(BRAZIERS):
        inside(f"Brazier{i + 1}", p, ARENA_INTERIOR, 20)
    inside("ChamberSpawn", CHAMBER_SPAWN, CHAMBER_INTERIOR, 24)
    for i, p in enumerate(WAVE_SPAWNS):
        inside(f"WaveSpawn{i + 1}", p, CHAMBER_INTERIOR, 24)
    for i, p in enumerate(CHAMBER_TORCHES):
        inside(f"ChamberTorch{i + 1}", p, CHAMBER_INTERIOR, 20)

    # A torch standing on a wave spawn means a mob materialising inside the fire.
    for i, t in enumerate(CHAMBER_TORCHES):
        for j, w in enumerate(WAVE_SPAWNS + [CHAMBER_SPAWN]):
            dx, dy = t[0] - w[0], t[1] - w[1]
            if (dx * dx + dy * dy) ** 0.5 < 40:
                problems.append(f"ChamberTorch{i + 1} {t} is on top of chamber spawn point {j + 1} {w}")

    # Nothing may be placed on top of anything else. The pads are the big ones;
    # a pillar or brazier inside a pad would be permanently standing in the ward.
    solids: list[tuple[str, tuple[int, int], int]] = [
        ("EmberPad", EMBER_PAD, PAD_RADIUS),
        ("StormPad", STORM_PAD, PAD_RADIUS),
        ("BossSpawn", BOSS_SPAWN, 34),
    ]
    solids += [(f"Pillar{i + 1}", p, 26) for i, p in enumerate(PILLARS)]
    solids += [(f"Brazier{i + 1}", p, 18) for i, p in enumerate(BRAZIERS)]
    for i in range(len(solids)):
        for j in range(i + 1, len(solids)):
            (na, pa, ra), (nb, pb, rb) = solids[i], solids[j]
            dx, dy = pa[0] - pb[0], pa[1] - pb[1]
            if (dx * dx + dy * dy) ** 0.5 < ra + rb:
                problems.append(f"{na} {pa} overlaps {nb} {pb}")
    return problems


def _read_layers(path: pathlib.Path) -> dict[str, str]:
    layers: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"LAYER (\w+) = (.+)$", line.strip())
        if m:
            layers[m.group(1)] = m.group(2).strip()
    return layers


def _markers(name: str, points: list[tuple[int, int]], parent: str) -> str:
    out = []
    for i, (x, y) in enumerate(points):
        out.append(f'[node name="{name}{i + 1}" type="Marker2D" parent="{parent}"]')
        out.append(f"position = Vector2({x}, {y})")
        out.append("")
    return "\n".join(out)


def _pad(node: str, pos: tuple[int, int], variant: int, pad_id: int, mat: str) -> str:
    x, y = pos
    r = PAD_RADIUS
    return f'''[node name="{node}" type="Area2D" parent="Encounter"]
position = Vector2({x}, {y})
script = ExtResource("6_pad")
variant = {variant}
pad_id = {pad_id}

[node name="CollisionShape2D" type="CollisionShape2D" parent="Encounter/{node}"]
shape = SubResource("PadShape")

[node name="Fill" type="ColorRect" parent="Encounter/{node}"]
material = SubResource("{mat}")
offset_left = -{r}.0
offset_top = -{r}.0
offset_right = {r}.0
offset_bottom = {r}.0
mouse_filter = 2
color = Color(1, 1, 1, 1)

[node name="ChargeBar" type="ProgressBar" parent="Encounter/{node}"]
offset_left = -40.0
offset_top = -{r + 22}.0
offset_right = 40.0
offset_bottom = -{r + 12}.0
mouse_filter = 2
max_value = 100.0
value = 0.0
show_percentage = false
'''


def build(layers: dict[str, str]) -> str:
    fx, fy, fw, fh = FROST_RECT
    return f'''[gd_scene format=3]

[ext_resource type="Script" path="res://source/common/gameplay/maps/map.gd" id="1_map"]
[ext_resource type="TileSet" path="res://source/common/gameplay/maps/tilesets/fire_forge_tileset.tres" id="2_tiles"]
[ext_resource type="TileSet" path="res://source/common/gameplay/maps/tilesets/ossuran_ice_tileset.tres" id="3_ice"]
[ext_resource type="Script" path="res://source/common/network/sync/replicated_props.gd" id="4_props"]
[ext_resource type="Script" path="res://source/common/gameplay/ossuran/ossuran_arena.gd" id="5_arena"]
[ext_resource type="Script" path="res://source/common/gameplay/ossuran/charge_pad.gd" id="6_pad"]
[ext_resource type="Script" path="res://source/common/gameplay/ossuran/minion_wave_manager.gd" id="7_waves"]
[ext_resource type="Shader" path="res://source/common/gameplay/ossuran/shaders/ember_pad.gdshader" id="8_ember"]
[ext_resource type="Shader" path="res://source/common/gameplay/ossuran/shaders/storm_pad.gdshader" id="9_storm"]
[ext_resource type="Shader" path="res://source/common/gameplay/ossuran/shaders/forge_to_ice.gdshader" id="10_freeze"]
[ext_resource type="PackedScene" path="res://source/common/gameplay/lighting/campfire.tscn" id="11_camp"]
[ext_resource type="PackedScene" path="res://source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn" id="12_warper"]
[ext_resource type="PackedScene" path="res://source/common/gameplay/maps/components/interaction_areas/warper/portal/portal.tscn" id="13_portal"]
[ext_resource type="Resource" path="res://source/common/gameplay/maps/instance/instance_collection/biomes/fire_forge.tres" id="14_forge"]

[sub_resource type="CircleShape2D" id="PadShape"]
radius = {PAD_RADIUS}.0

[sub_resource type="ShaderMaterial" id="EmberMat"]
shader = ExtResource("8_ember")
shader_parameter/charge = 0.0
shader_parameter/active = 0.0
shader_parameter/pad_pixels = {PAD_RADIUS * 2}.0

[sub_resource type="ShaderMaterial" id="StormMat"]
shader = ExtResource("9_storm")
shader_parameter/charge = 0.0
shader_parameter/active = 0.0
shader_parameter/pad_pixels = {PAD_RADIUS * 2}.0

[sub_resource type="ShaderMaterial" id="FreezeMat"]
shader = ExtResource("10_freeze")
shader_parameter/freeze = 0.0
shader_parameter/world_pixels = {fw}.0

[node name="OssuranArena" type="Node2D" node_paths=PackedStringArray("replicated_props_container")]
y_sort_enabled = true
script = ExtResource("1_map")
replicated_props_container = NodePath("ReplicatedPropsContainer")
map_background_color = Color(0.04, 0.03, 0.05, 1)

[node name="Tiles" type="Node2D" parent="."]
y_sort_enabled = true

[node name="Ground" type="TileMapLayer" parent="Tiles"]
z_index = -10
tile_map_data = PackedByteArray("{layers["Ground"]}")
tile_set = ExtResource("2_tiles")

[node name="Walls" type="TileMapLayer" parent="Tiles"]
y_sort_enabled = true
tile_map_data = PackedByteArray("{layers["Walls"]}")
tile_set = ExtResource("2_tiles")

[node name="Ice" type="TileMapLayer" parent="Tiles"]
z_index = -9
visible = false
modulate = Color(1, 1, 1, 0)
tile_map_data = PackedByteArray("{layers["Ice"]}")
tile_set = ExtResource("3_ice")

[node name="FrostOverlay" type="ColorRect" parent="."]
z_index = -8
visible = false
material = SubResource("FreezeMat")
offset_left = {fx}.0
offset_top = {fy}.0
offset_right = {fx + fw}.0
offset_bottom = {fy + fh}.0
mouse_filter = 2
color = Color(1, 1, 1, 1)

[node name="ReplicatedPropsContainer" type="Node2D" parent="." node_paths=PackedStringArray("id_to_node", "node_to_id")]
script = ExtResource("4_props")
id_to_node = {{}}
node_to_id = {{}}

[node name="Entrance" parent="." instance=ExtResource("12_warper")]
position = Vector2({ENTRANCE[0]}, {ENTRANCE[1]})
warper_id = 58

[node name="ExitPortal" parent="." instance=ExtResource("13_portal")]
position = Vector2({ENTRANCE[0] - 56}, {ENTRANCE[1]})
portal_color = Color(0.74, 0.25, 0, 1)
destination_label = "Fire Forge"
target_instance = ExtResource("14_forge")
warper_id = 158
target_id = 57

[node name="Encounter" type="Node2D" parent="."]
y_sort_enabled = true
script = ExtResource("5_arena")

[node name="BossSpawn" type="Marker2D" parent="Encounter"]
position = Vector2({BOSS_SPAWN[0]}, {BOSS_SPAWN[1]})

[node name="ArenaReturn" type="Marker2D" parent="Encounter"]
position = Vector2({ARENA_RETURN[0]}, {ARENA_RETURN[1]})

[node name="ChamberSpawn" type="Marker2D" parent="Encounter"]
position = Vector2({CHAMBER_SPAWN[0]}, {CHAMBER_SPAWN[1]})

{_pad("EmberPad", EMBER_PAD, 0, 1, "EmberMat")}
{_pad("StormPad", STORM_PAD, 1, 2, "StormMat")}
[node name="PillarMarkers" type="Node2D" parent="Encounter"]

{_markers("Pillar", PILLARS, "Encounter/PillarMarkers")}[node name="FireSources" type="Node2D" parent="Encounter"]

{_braziers()}[node name="WaveManager" type="Node2D" parent="Encounter"]
position = Vector2({WAVE_ORIGIN[0]}, {WAVE_ORIGIN[1]})
script = ExtResource("7_waves")

[node name="Spawns" type="Node2D" parent="Encounter/WaveManager"]

{_wave_markers()}[node name="ChamberProps" type="Node2D" parent="."]
y_sort_enabled = true

{_chamber_torches()}'''


def _braziers() -> str:
    out = []
    for i, (x, y) in enumerate(BRAZIERS):
        out.append(f'[node name="Brazier{i + 1}" parent="Encounter/FireSources" instance=ExtResource("11_camp")]')
        out.append(f"position = Vector2({x}, {y})")
        out.append("")
    return "\n".join(out)


def _chamber_torches() -> str:
    out = []
    for i, (x, y) in enumerate(CHAMBER_TORCHES):
        out.append(f'[node name="ChamberTorch{i + 1}" parent="ChamberProps" instance=ExtResource("11_camp")]')
        out.append(f"position = Vector2({x}, {y})")
        out.append("")
    return "\n".join(out)


def _wave_markers() -> str:
    # Positions are relative to WaveManager, which sits at WAVE_ORIGIN.
    rel = [(x - WAVE_ORIGIN[0], y - WAVE_ORIGIN[1]) for x, y in WAVE_SPAWNS]
    return _markers("WaveSpawn", rel, "Encounter/WaveManager/Spawns")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: build_ossuran_scene.py <tiles.txt>", file=sys.stderr)
        return 1
    problems = _assert_layout()
    if problems:
        for p in problems:
            print(f"LAYOUT: {p}", file=sys.stderr)
        return 1
    layers = _read_layers(pathlib.Path(sys.argv[1]))
    for needed in ("Ground", "Walls", "Ice"):
        if needed not in layers:
            print(f"missing LAYER {needed} in the tile dump", file=sys.stderr)
            return 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build(layers), encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")
    print("layout: all placements inside their room, no overlaps")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
