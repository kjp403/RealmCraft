#!/usr/bin/env python3
"""DEPRECATED skeleton helper — use tools/build_hollow_tiles.gd instead.

Godot set_cell + footprint occupancy is required so multi-tile rocks
(2x2 / 2x3) are placed at their atlas ORIGIN only. Placing fragment
cells (e.g. 4:1, 5:1, 2:3) shows as half-rocks in-game.

  godot --headless --path . -s tools/build_hollow_tiles.gd
"""
from __future__ import annotations

import base64
import struct
from pathlib import Path

OUT = Path("/workspace/source/common/gameplay/maps/maps/the_hollow/the_hollow.tscn")

# Godot 4.x TileMapLayer tile_map_data:
#   u16 format_version (=0)
#   then per cell (12 bytes): i16 x, i16 y, u16 source_id, u16 atlas_x, u16 atlas_y, u16 alternative
def cell(x: int, y: int, source: int, ax: int, ay: int) -> bytes:
    return struct.pack("<hhHHHH", x, y, source, ax, ay, 0)


def pack(cells: list[bytes]) -> str:
    raw = struct.pack("<H", 0) + b"".join(cells)
    return base64.b64encode(raw).decode("ascii")


# Arena in tile coords (16px tiles). Camera ~ -32..960 x -32..720 → tiles -2..60, -2..45
X0, Y0 = 0, 0
X1, Y1 = 59, 44  # inclusive outer wall
FLOOR_INSET = 2  # walkable floor starts inside walls

# Source 0 CaveTiles — walkable floors + solid wall tops
FLOOR = [
    (8, 15),
    (7, 15),
    (9, 15),
    (8, 14),
    (10, 15),
    (6, 15),
]
FLOOR_DARK = [(13, 15), (14, 15), (12, 15), (11, 15)]
# Solid collision wall tiles
WALL_FILL = (2, 0)
WALL_TOP = (2, 0)
WALL_SIDE = (0, 2)
WALL_CORNER = (1, 0)

# Source 1 CaveProps accents
PROP_CAVE = [(16, 0), (18, 0), (20, 0), (12, 0), (0, 6), (5, 6)]
# Source 4 rocks.png
ROCKS = [(0, 1), (2, 1), (4, 1), (5, 1), (8, 1), (10, 1), (2, 3), (3, 3)]


def hash_xy(x: int, y: int) -> int:
    return (x * 73856093) ^ (y * 19349663)


ground: list[bytes] = []
walls: list[bytes] = []
props: list[bytes] = []

cx = (X0 + X1) // 2
cy = (Y0 + Y1) // 2

for y in range(Y0, Y1 + 1):
    for x in range(X0, X1 + 1):
        edge = (
            x < X0 + FLOOR_INSET
            or x > X1 - FLOOR_INSET
            or y < Y0 + FLOOR_INSET
            or y > Y1 - FLOOR_INSET
        )
        # Leave a south portal gap in the wall (entrance corridor)
        portal_gap = y > Y1 - FLOOR_INSET and (cx - 3) <= x <= (cx + 3)
        if edge and not portal_gap:
            # One cell per coord — duplicates corrupt TileMapLayer data.
            inner_rim = (
                x == X0 + FLOOR_INSET - 1
                or x == X1 - FLOOR_INSET + 1
                or y == Y0 + FLOOR_INSET - 1
                or y == Y1 - FLOOR_INSET + 1
            )
            ax, ay = WALL_CORNER if inner_rim else WALL_FILL
            walls.append(cell(x, y, 0, ax, ay))
        else:
            # Arena floor — darker ring around boss pad
            dx, dy = x - cx, y - (cy - 4)
            dist2 = dx * dx + dy * dy
            if dist2 <= 25:
                ax, ay = FLOOR_DARK[hash_xy(x, y) % len(FLOOR_DARK)]
            else:
                ax, ay = FLOOR[hash_xy(x, y) % len(FLOOR)]
            ground.append(cell(x, y, 0, ax, ay))

# Inner rubble ring (non-blocking visual on GroundProps via Props layer)
for angle_i in range(24):
    # place rocks around boss circle
    import math

    ang = angle_i * (math.pi * 2 / 24)
    rx = int(round(cx + math.cos(ang) * 10))
    ry = int(round((cy - 4) + math.sin(ang) * 7))
    if X0 + FLOOR_INSET + 1 <= rx <= X1 - FLOOR_INSET - 1 and Y0 + FLOOR_INSET + 1 <= ry <= Y1 - FLOOR_INSET - 1:
        ax, ay = ROCKS[angle_i % len(ROCKS)]
        props.append(cell(rx, ry, 4, ax, ay))

# Corner cave props
for x, y in [
    (X0 + 4, Y0 + 4),
    (X1 - 4, Y0 + 4),
    (X0 + 4, Y1 - 6),
    (X1 - 4, Y1 - 6),
    (X0 + 8, cy),
    (X1 - 8, cy),
    (cx - 12, Y0 + 5),
    (cx + 12, Y0 + 5),
]:
    ax, ay = PROP_CAVE[hash_xy(x, y) % len(PROP_CAVE)]
    props.append(cell(x, y, 1, ax, ay))

# Scattered floor grit (source 0 small debris-like tiles used as props in fungus)
for y in range(Y0 + 5, Y1 - 5, 3):
    for x in range(X0 + 5, X1 - 5, 4):
        if hash_xy(x, y) % 5 != 0:
            continue
        if abs(x - cx) < 4 and abs(y - (cy - 4)) < 3:
            continue
        props.append(cell(x, y, 0, 13, 10))  # small rock cluster visual

ground_b64 = pack(ground)
walls_b64 = pack(walls)
props_b64 = pack(props)

# World positions (tile * 16)
golem_pos = (cx * 16 + 8, (cy - 4) * 16 + 8)  # boss pad center
entrance_pos = (cx * 16 + 8, (Y1 - 5) * 16)
portal_pos = (cx * 16 + 8, (Y1 - 2) * 16 + 8)
campfires = [
    ((X0 + 5) * 16, (Y0 + 5) * 16),
    ((X1 - 5) * 16, (Y0 + 5) * 16),
    ((X0 + 5) * 16, (Y1 - 7) * 16),
    ((X1 - 5) * 16, (Y1 - 7) * 16),
]
fireflies = [
    (cx * 16, (cy - 10) * 16),
    ((cx - 10) * 16, cy * 16),
    ((cx + 10) * 16, cy * 16),
    (cx * 16, (cy + 6) * 16),
]

# Collision walls as StaticBody2D (hard bowl). Gap at south for portal.
wall_thickness = 24
inner_left = (X0 + FLOOR_INSET) * 16
inner_right = (X1 - FLOOR_INSET + 1) * 16
inner_top = (Y0 + FLOOR_INSET) * 16
inner_bottom = (Y1 - FLOOR_INSET + 1) * 16
arena_w = inner_right - inner_left
arena_h = inner_bottom - inner_top

tscn = f'''[gd_scene format=3]

[ext_resource type="Script" path="res://source/common/gameplay/maps/maps/the_hollow/the_hollow.gd" id="1_map"]
[ext_resource type="TileSet" uid="uid://hrdxga40fogr" path="res://source/common/gameplay/maps/tilesets/mining_cave_tileset.tres" id="2_tiles"]
[ext_resource type="AudioStream" uid="uid://bqvqgqvqmiddle" path="res://assets/audio/music/middle_boss.ogg" id="3_music"]
[ext_resource type="Script" uid="uid://wq8klpndipnu" path="res://source/common/network/sync/replicated_props.gd" id="4_rp"]
[ext_resource type="PackedScene" uid="uid://b2ckixon7ryh6" path="res://source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn" id="5_warper"]
[ext_resource type="PackedScene" uid="uid://0m5eq6iylq26" path="res://source/common/gameplay/maps/components/interaction_areas/warper/portal/portal.tscn" id="6_portal"]
[ext_resource type="Resource" uid="uid://doc0umc2oovri" path="res://source/common/gameplay/maps/instance/instance_collection/overworld.tres" id="7_hub"]
[ext_resource type="PackedScene" path="res://source/common/gameplay/lighting/campfire.tscn" id="8_camp"]
[ext_resource type="PackedScene" path="res://source/common/gameplay/lighting/firefly.tscn" id="9_fly"]
[ext_resource type="Texture2D" path="res://source/common/gameplay/lighting/light_radial.tres" id="10_glow"]
[ext_resource type="Texture2D" path="res://assets/sprites/environment/fx/fog.png" id="11_fog"]

[sub_resource type="RectangleShape2D" id="WallN"]
size = Vector2({arena_w + wall_thickness * 2}, {wall_thickness})

[sub_resource type="RectangleShape2D" id="WallS"]
size = Vector2({(arena_w - 112) / 2.0}, {wall_thickness})

[sub_resource type="RectangleShape2D" id="WallE"]
size = Vector2({wall_thickness}, {arena_h + wall_thickness * 2})

[sub_resource type="RectangleShape2D" id="WallW"]
size = Vector2({wall_thickness}, {arena_h + wall_thickness * 2})

[node name="the_hollow" type="Node2D"]
y_sort_enabled = true
script = ExtResource("1_map")
replicated_props_container = NodePath("ReplicatedPropsContainer")
map_background_color = Color(0.04, 0.045, 0.04, 1)
music = ExtResource("3_music")
camera_limit_left = -16
camera_limit_top = -16
camera_limit_right = {(X1 + 1) * 16 + 16}
camera_limit_bottom = {(Y1 + 1) * 16 + 16}

[node name="CanvasModulate" type="CanvasModulate" parent="."]
color = Color(0.62, 0.66, 0.7, 1)

[node name="Tiles" type="Node2D" parent="."]
y_sort_enabled = true

[node name="Ground" type="TileMapLayer" parent="Tiles"]
z_index = -1
y_sort_enabled = true
tile_map_data = PackedByteArray("{ground_b64}")
tile_set = ExtResource("2_tiles")

[node name="Walls" type="TileMapLayer" parent="Tiles"]
y_sort_enabled = true
tile_map_data = PackedByteArray("{walls_b64}")
tile_set = ExtResource("2_tiles")

[node name="Props" type="TileMapLayer" parent="Tiles"]
y_sort_enabled = true
tile_map_data = PackedByteArray("{props_b64}")
tile_set = ExtResource("2_tiles")

[node name="ArenaWalls" type="StaticBody2D" parent="."]
collision_layer = 2
collision_mask = 0

[node name="North" type="CollisionShape2D" parent="ArenaWalls"]
position = Vector2({(inner_left + inner_right) / 2.0}, {inner_top - wall_thickness / 2.0})
shape = SubResource("WallN")

[node name="SouthLeft" type="CollisionShape2D" parent="ArenaWalls"]
position = Vector2({inner_left + (arena_w - 112) / 4.0}, {inner_bottom + wall_thickness / 2.0})
shape = SubResource("WallS")

[node name="SouthRight" type="CollisionShape2D" parent="ArenaWalls"]
position = Vector2({inner_right - (arena_w - 112) / 4.0}, {inner_bottom + wall_thickness / 2.0})
shape = SubResource("WallS")

[node name="East" type="CollisionShape2D" parent="ArenaWalls"]
position = Vector2({inner_right + wall_thickness / 2.0}, {(inner_top + inner_bottom) / 2.0})
shape = SubResource("WallE")

[node name="West" type="CollisionShape2D" parent="ArenaWalls"]
position = Vector2({inner_left - wall_thickness / 2.0}, {(inner_top + inner_bottom) / 2.0})
shape = SubResource("WallW")

[node name="BossPad" type="Polygon2D" parent="."]
z_index = -1
color = Color(0.12, 0.1, 0.09, 0.55)
polygon = PackedVector2Array({golem_pos[0] - 72}, {golem_pos[1] - 48}, {golem_pos[0] + 72}, {golem_pos[1] - 48}, {golem_pos[0] + 72}, {golem_pos[1] + 48}, {golem_pos[0] - 72}, {golem_pos[1] + 48})

[node name="FogBack" type="Sprite2D" parent="."]
modulate = Color(0.45, 0.55, 0.5, 0.22)
position = Vector2({cx * 16}, {(cy - 8) * 16})
scale = Vector2(1.8, 1.1)
texture = ExtResource("11_fog")
z_index = -1

[node name="FogFront" type="Sprite2D" parent="."]
modulate = Color(0.4, 0.5, 0.45, 0.16)
position = Vector2({cx * 16}, {(cy + 4) * 16})
scale = Vector2(2.0, 0.9)
texture = ExtResource("11_fog")
z_index = 2

[node name="SceneProps" type="Node2D" parent="."]
y_sort_enabled = true

[node name="CampfireNW" parent="SceneProps" instance=ExtResource("8_camp")]
position = Vector2({campfires[0][0]}, {campfires[0][1]})

[node name="CampfireNE" parent="SceneProps" instance=ExtResource("8_camp")]
position = Vector2({campfires[1][0]}, {campfires[1][1]})

[node name="CampfireSW" parent="SceneProps" instance=ExtResource("8_camp")]
position = Vector2({campfires[2][0]}, {campfires[2][1]})

[node name="CampfireSE" parent="SceneProps" instance=ExtResource("8_camp")]
position = Vector2({campfires[3][0]}, {campfires[3][1]})

[node name="Firefly1" parent="SceneProps" instance=ExtResource("9_fly")]
position = Vector2({fireflies[0][0]}, {fireflies[0][1]})

[node name="Firefly2" parent="SceneProps" instance=ExtResource("9_fly")]
position = Vector2({fireflies[1][0]}, {fireflies[1][1]})

[node name="Firefly3" parent="SceneProps" instance=ExtResource("9_fly")]
position = Vector2({fireflies[2][0]}, {fireflies[2][1]})

[node name="Firefly4" parent="SceneProps" instance=ExtResource("9_fly")]
position = Vector2({fireflies[3][0]}, {fireflies[3][1]})

[node name="BossLight" type="PointLight2D" parent="SceneProps"]
position = Vector2({golem_pos[0]}, {golem_pos[1]})
color = Color(0.85, 0.55, 0.35, 1)
energy = 1.15
texture = ExtResource("10_glow")
texture_scale = 2.4

[node name="ReplicatedPropsContainer" type="Node2D" parent="."]
y_sort_enabled = true
script = ExtResource("4_rp")
id_to_node = {{}}
node_to_id = {{}}
metadata/_custom_type_script = "uid://wq8klpndipnu"

[node name="RespawnPoint" parent="." instance=ExtResource("5_warper")]
position = Vector2({entrance_pos[0]}, {entrance_pos[1]})

[node name="Entrance" parent="." instance=ExtResource("5_warper")]
position = Vector2({entrance_pos[0]}, {entrance_pos[1]})
warper_id = 27

[node name="Portal" parent="." instance=ExtResource("6_portal")]
position = Vector2({portal_pos[0]}, {portal_pos[1]})
portal_color = Color(0.18, 0.2, 0.18, 1)
destination_label = "Castle Garden"
target_instance = ExtResource("7_hub")
warper_id = 127
target_id = 27
'''

# Fix music uid — don't invent fake uid; omit uid if unknown
tscn = tscn.replace(
    '[ext_resource type="AudioStream" uid="uid://bqvqgqvqmiddle" path="res://assets/audio/music/middle_boss.ogg" id="3_music"]',
    '[ext_resource type="AudioStream" path="res://assets/audio/music/middle_boss.ogg" id="3_music"]',
)

OUT.write_text(tscn)
print(f"Wrote {OUT}")
print(f"ground cells={len(ground)} walls={len(walls)} props={len(props)}")
print(f"golem_spawn≈{golem_pos} entrance≈{entrance_pos} portal≈{portal_pos}")
print(f"GOLEM_SPAWN should be Vector2({golem_pos[0]}, {golem_pos[1]})")
