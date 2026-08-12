#!/usr/bin/env python3
"""Plant denser Farming herb MineableNodes across Goblin Woodlands (+ east),
DimWood, and Bandit Hideout.

Goblin Woodlands / East: Healing Herb (lv1) + Frostpetal (lv5) only.
DimWood: mid ladder (Sunwort 10, Moonbloom 20) + more early herbs.
Bandit Hideout: high ladder (Bloodcap 30, Starblossom 40, Grimshade 50)
plus some Moonbloom.

Run: python tools/plant_farming_herbs.py
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def node_block(
    name: str,
    parent: str,
    scene_id: str,
    data_id: str,
    x: float,
    y: float,
    uid: int,
    y_sort: bool = False,
) -> str:
    lines = [
        f'[node name="{name}" parent="{parent}" unique_id={uid} instance=ExtResource("{scene_id}")]',
    ]
    if y_sort:
        lines.append("y_sort_enabled = true")
    lines.append(f"position = Vector2({x:g}, {y:g})")
    lines.append(f'data = ExtResource("{data_id}")')
    lines.append("")
    return "\n".join(lines)


def remove_nodes(text: str, names: list[str]) -> str:
    for name in names:
        # Match a node block: [node name="X" ...] until next [node or EOF
        pattern = re.compile(
            rf'\[node name="{re.escape(name)}"[^\]]*\]\n(?:(?!\[node ).*\n)*',
            re.MULTILINE,
        )
        text, n = pattern.subn("", text)
        if n == 0:
            print(f"  warn: missing node {name}")
        else:
            print(f"  removed {name}")
    return text


def ensure_ext_resource(text: str, path: str, rid: str) -> str:
    if f'id="{rid}"' in text and path in text:
        return text
    # Insert after last herb/mineable ext_resource if possible, else after first ext_resource block line.
    line = (
        f'[ext_resource type="Resource" path="res://source/common/gameplay/maps/'
        f'components/mineable_nodes/{path}" id="{rid}"]\n'
    )
    # Prefer inserting after healing_herb / frostpetal lines.
    for marker in ("healing_herb.tres", "frostpetal.tres", "mineable_node.tscn"):
        idx = text.find(marker)
        if idx < 0:
            continue
        end = text.find("\n", idx)
        if end < 0:
            continue
        text = text[: end + 1] + line + text[end + 1 :]
        print(f"  added ext_resource {rid} -> {path}")
        return text
    raise RuntimeError(f"could not insert ext_resource {rid}")


def remove_ext_resources(text: str, ids: list[str]) -> str:
    for rid in ids:
        pattern = re.compile(rf'\[ext_resource[^\]]*id="{re.escape(rid)}"\]\n')
        text, n = pattern.subn("", text)
        if n:
            print(f"  removed ext_resource {rid}")
    return text


def insert_before_marker(text: str, marker: str, block: str) -> str:
    idx = text.find(marker)
    if idx < 0:
        raise RuntimeError(f"marker not found: {marker}")
    return text[:idx] + block + text[idx:]


def insert_after_marker(text: str, marker: str, block: str) -> str:
    idx = text.find(marker)
    if idx < 0:
        raise RuntimeError(f"marker not found: {marker}")
    # After the full line containing marker
    end = text.find("\n", idx)
    if end < 0:
        end = len(text)
    else:
        end += 1
    return text[:end] + block + text[end:]


# ---------------------------------------------------------------------------
# Goblin Woodlands (woodland_tiles) — L1/L5 only, dense
# ---------------------------------------------------------------------------

def patch_woodland_tiles() -> None:
    path = ROOT / "source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
    text = path.read_text(encoding="utf-8")
    print(f"\n== {path.name} ==")

    # Drop mid/high herbs — those move to DimWood / Bandit.
    text = remove_nodes(
        text,
        [
            "Sunwort1",
            "Sunwort2",
            "Moonbloom1",
            "Moonbloom2",
            "Bloodcap1",
            "Bloodcap2",
            "Starblossom1",
            "Starblossom2",
            "Grimshade1",
            "Grimshade2",
        ],
    )
    text = remove_ext_resources(
        text, ["29_sun", "29_moon", "29_blood", "29_star", "29_grim"]
    )

    # Existing: HerbNode1-3, SecretHerbNode (4 healing), Frostpetal1-2.
    # Add enough for a multiplayer gather loop across the full map (~5.8k x 2k).
    healing = [
        (200, 720),
        (280, 960),
        (360, 1120),
        (480, 640),
        (520, 1280),
        (640, 800),
        (720, 1080),
        (800, 560),
        (880, 960),
        (960, 1280),
        (1040, 720),
        (1120, 1040),
        (1200, 560),
        (1360, 1200),
        (1440, 720),
        (1520, 1040),
        (1680, 640),
        (1760, 1120),
        (1880, 800),
        (2000, 1280),
        (2160, 600),
        (2320, 880),
        (2480, 1120),
        (2600, 480),
        (2880, 720),
        (3040, 960),
        (3200, 640),
        (3360, 880),
        (3600, 720),
        (3840, 1000),
        (4080, 640),
        (4320, 880),
        (4560, 560),
        (4800, 800),
        (5040, 640),
        (5280, 960),
        (5440, 720),
        (5600, 880),
    ]
    frost = [
        (300, 680),
        (440, 1000),
        (600, 600),
        (760, 1200),
        (920, 800),
        (1080, 1120),
        (1240, 680),
        (1400, 960),
        (1600, 560),
        (1800, 1000),
        (1960, 720),
        (2200, 1040),
        (2400, 640),
        (2560, 920),
        (2720, 560),
        (2960, 800),
        (3120, 1120),
        (3400, 640),
        (3680, 960),
        (4000, 720),
        (4280, 1040),
        (4600, 800),
        (4920, 560),
        (5200, 880),
        (5480, 640),
    ]

    blocks: list[str] = []
    uid = 1910000100
    for i, (x, y) in enumerate(healing, start=4):
        blocks.append(
            node_block(f"HerbNode{i}", "MineableNodes", "7_jiw8u", "28_svn3l", x, y, uid)
        )
        uid += 1
    for i, (x, y) in enumerate(frost, start=3):
        blocks.append(
            node_block(f"Frostpetal{i}", "MineableNodes", "7_jiw8u", "29_frost", x, y, uid)
        )
        uid += 1

    text = insert_before_marker(
        text,
        '[node name="Tree1" parent="MineableNodes"',
        "\n".join(blocks) + "\n",
    )
    path.write_text(text, encoding="utf-8")
    print(f"  added {len(healing)} healing + {len(frost)} frostpetal")


# ---------------------------------------------------------------------------
# Woodland East — L1/L5 only
# ---------------------------------------------------------------------------

def patch_woodland_east() -> None:
    path = ROOT / "source/common/gameplay/maps/maps/woodland/woodland_east.tscn"
    text = path.read_text(encoding="utf-8")
    print(f"\n== {path.name} ==")

    if 'id="herb_scene"' not in text:
        # Insert packed scene + herb resources near other ext_resources.
        insert = (
            '[ext_resource type="PackedScene" uid="uid://dqo57ux3v3lkq" '
            'path="res://source/common/gameplay/maps/components/mineable_node.tscn" '
            'id="herb_scene"]\n'
            '[ext_resource type="Resource" uid="uid://g8rxlnr0pfyk" '
            'path="res://source/common/gameplay/maps/components/mineable_nodes/healing_herb.tres" '
            'id="herb_heal"]\n'
            '[ext_resource type="Resource" '
            'path="res://source/common/gameplay/maps/components/mineable_nodes/frostpetal.tres" '
            'id="herb_frost"]\n'
        )
        # After last et_abat ext_resource
        marker = 'id="et_abat"]'
        idx = text.find(marker)
        if idx < 0:
            raise RuntimeError("east: et_abat not found")
        end = text.find("\n", idx) + 1
        text = text[:end] + insert + text[end:]
        print("  added herb ext_resources")

    # Remove prior MineableNodes if re-run
    text = re.sub(
        r'\[node name="MineableNodes"[^\]]*\]\n(?:(?!\[node name="(?!MineableNodes)).*\n)*',
        "",
        text,
        count=1,
    )
    # Cleaner: strip from MineableNodes to next top-level sibling that isn't a child
    if '[node name="MineableNodes"' in text:
        start = text.find('[node name="MineableNodes"')
        # Find next [node that is NOT parent="MineableNodes"
        m = re.search(r'\n\[node name="(?!.*parent="MineableNodes")', text[start + 1 :])
        if m:
            end = start + 1 + m.start() + 1
            text = text[:start] + text[end:]
            print("  cleared previous MineableNodes")
        else:
            text = text[:start]
            print("  cleared previous MineableNodes (to EOF)")

    healing = [
        (200, 400),
        (360, 560),
        (520, 720),
        (680, 400),
        (840, 880),
        (1000, 560),
        (1160, 1040),
        (1320, 400),
        (1480, 720),
        (1640, 1200),
        (1800, 560),
        (1960, 880),
        (2120, 400),
        (2280, 1040),
        (2440, 720),
        (2600, 480),
        (2760, 960),
        (2920, 640),
        (800, 1400),
        (1200, 1600),
        (1600, 1800),
        (2000, 1600),
        (2400, 1800),
        (2800, 1400),
        (400, 1800),
        (600, 2000),
        (1000, 2000),
        (1400, 2200),
        (1800, 2000),
        (2200, 2200),
    ]
    frost = [
        (280, 640),
        (480, 880),
        (720, 560),
        (960, 1200),
        (1200, 720),
        (1440, 960),
        (1680, 480),
        (1920, 1120),
        (2160, 640),
        (2400, 880),
        (2640, 560),
        (2880, 1040),
        (560, 1600),
        (960, 1800),
        (1360, 1600),
        (1760, 1840),
        (2160, 1600),
        (2560, 1840),
        (400, 1200),
        (800, 2000),
        (1600, 2080),
        (2400, 2000),
    ]

    blocks = ['[node name="MineableNodes" type="Node2D" parent="."]\n\n']
    uid = 1920000100
    for i, (x, y) in enumerate(healing, start=1):
        blocks.append(
            node_block(f"EastHerb{i}", "MineableNodes", "herb_scene", "herb_heal", x, y, uid)
        )
        uid += 1
    for i, (x, y) in enumerate(frost, start=1):
        blocks.append(
            node_block(f"EastFrost{i}", "MineableNodes", "herb_scene", "herb_frost", x, y, uid)
        )
        uid += 1

    # Place MineableNodes before ReplicatedPropsContainer (or after SceneProps)
    if '[node name="ReplicatedPropsContainer"' in text:
        text = insert_before_marker(
            text, '[node name="ReplicatedPropsContainer"', "".join(blocks) + "\n"
        )
    else:
        text += "\n" + "".join(blocks)

    path.write_text(text, encoding="utf-8")
    print(f"  planted {len(healing)} healing + {len(frost)} frostpetal")


# ---------------------------------------------------------------------------
# DimWood — mid ladder + denser early herbs
# ---------------------------------------------------------------------------

def patch_dimwood() -> None:
    path = ROOT / "source/common/gameplay/maps/maps/forest/forest.tscn"
    text = path.read_text(encoding="utf-8")
    print(f"\n== {path.name} ==")

    text = ensure_ext_resource(text, "frostpetal.tres", "33_frost")
    text = ensure_ext_resource(text, "sunwort.tres", "33_sun")
    text = ensure_ext_resource(text, "moonbloom.tres", "33_moon")
    text = ensure_ext_resource(text, "bloodcap.tres", "33_blood")

    # Remove previously planted densify nodes on re-run
    for prefix in ("DimHeal", "DimFrost", "DimSun", "DimMoon", "DimBlood"):
        text = re.sub(
            rf'\[node name="{prefix}\d+"[^\]]*\]\n(?:(?!\[node ).*\n)*',
            "",
            text,
        )

    healing = [
        (900, 1200),
        (1100, 1450),
        (1300, 1100),
        (1500, 1700),
        (1700, 1250),
        (1900, 1550),
        (2100, 1350),
        (2300, 1800),
        (1000, 2100),
        (1400, 2200),
        (1800, 2100),
        (2200, 2000),
        (800, 1600),
        (1200, 900),
        (1600, 1000),
        (2000, 900),
    ]
    frost = [
        (950, 1400),
        (1150, 1600),
        (1450, 1300),
        (1650, 1800),
        (1850, 1400),
        (2050, 1650),
        (2250, 1450),
        (1050, 1900),
        (1550, 2000),
        (1950, 1900),
        (850, 1800),
        (2400, 1700),
    ]
    sunwort = [
        (1000, 1500),
        (1280, 1700),
        (1520, 1500),
        (1760, 1750),
        (2000, 1500),
        (2240, 1750),
        (1120, 2000),
        (1680, 2100),
        (2160, 2100),
        (1400, 1200),
        (1880, 1200),
        (2360, 1500),
    ]
    moonbloom = [
        (1200, 1800),
        (1480, 1950),
        (1760, 1850),
        (2040, 2000),
        (1320, 2100),
        (1880, 2150),
        (1600, 1600),
        (2080, 1600),
        (2400, 1900),
        (1000, 1750),
    ]
    bloodcap = [
        (1500, 2100),
        (1800, 2200),
        (2100, 2150),
        (1650, 2300),
        (1950, 2300),
        (2250, 2200),
        (1400, 2300),
        (2300, 2050),
    ]

    blocks: list[str] = []
    uid = 1930000100
    scene = "29_uexkn"
    for i, (x, y) in enumerate(healing, start=1):
        blocks.append(node_block(f"DimHeal{i}", "MineableNodes", scene, "31_qncuc", x, y, uid, True))
        uid += 1
    for i, (x, y) in enumerate(frost, start=1):
        blocks.append(node_block(f"DimFrost{i}", "MineableNodes", scene, "33_frost", x, y, uid, True))
        uid += 1
    for i, (x, y) in enumerate(sunwort, start=1):
        blocks.append(node_block(f"DimSun{i}", "MineableNodes", scene, "33_sun", x, y, uid, True))
        uid += 1
    for i, (x, y) in enumerate(moonbloom, start=1):
        blocks.append(node_block(f"DimMoon{i}", "MineableNodes", scene, "33_moon", x, y, uid, True))
        uid += 1
    for i, (x, y) in enumerate(bloodcap, start=1):
        blocks.append(node_block(f"DimBlood{i}", "MineableNodes", scene, "33_blood", x, y, uid, True))
        uid += 1

    text = insert_before_marker(
        text,
        '[node name="OakTree1" parent="MineableNodes"',
        "\n".join(blocks) + "\n",
    )
    path.write_text(text, encoding="utf-8")
    print(
        f"  added heal={len(healing)} frost={len(frost)} "
        f"sun={len(sunwort)} moon={len(moonbloom)} blood={len(bloodcap)}"
    )


# ---------------------------------------------------------------------------
# Bandit Hideout — high tier denser in small camp
# ---------------------------------------------------------------------------

def patch_bandit() -> None:
    path = ROOT / "source/common/gameplay/maps/maps/bandit_hideout/bandit_hideout.tscn"
    text = path.read_text(encoding="utf-8")
    print(f"\n== {path.name} ==")

    insert = (
        '[ext_resource type="PackedScene" uid="uid://dqo57ux3v3lkq" '
        'path="res://source/common/gameplay/maps/components/mineable_node.tscn" '
        'id="herb_scene"]\n'
        '[ext_resource type="Resource" '
        'path="res://source/common/gameplay/maps/components/mineable_nodes/moonbloom.tres" '
        'id="herb_moon"]\n'
        '[ext_resource type="Resource" '
        'path="res://source/common/gameplay/maps/components/mineable_nodes/bloodcap.tres" '
        'id="herb_blood"]\n'
        '[ext_resource type="Resource" '
        'path="res://source/common/gameplay/maps/components/mineable_nodes/starblossom.tres" '
        'id="herb_star"]\n'
        '[ext_resource type="Resource" '
        'path="res://source/common/gameplay/maps/components/mineable_nodes/grimshade.tres" '
        'id="herb_grim"]\n'
    )
    if 'id="herb_scene"' not in text:
        marker = 'id="34_captain"]'
        idx = text.find(marker)
        if idx < 0:
            raise RuntimeError("bandit: captain ext not found")
        end = text.find("\n", idx) + 1
        text = text[:end] + insert + text[end:]
        print("  added herb ext_resources")

    # Clear previous MineableNodes
    if '[node name="MineableNodes"' in text:
        start = text.find('[node name="MineableNodes"')
        # Find next node whose parent is NOT MineableNodes
        rest = text[start:]
        m = re.search(r'\n\[node name="[^"]+" parent="(?!MineableNodes)', rest)
        if m:
            text = text[:start] + rest[m.start() + 1 :]
        else:
            text = text[:start]
        print("  cleared previous MineableNodes")

    # Camp is roughly x 100-760, y 120-720. Place on edges / clearings.
    moonbloom = [
        (120, 480),
        (180, 420),
        (200, 640),
        (700, 480),
        (740, 560),
        (680, 640),
        (360, 680),
        (520, 680),
    ]
    bloodcap = [
        (160, 360),
        (220, 300),
        (300, 280),
        (480, 280),
        (560, 300),
        (640, 320),
        (720, 360),
        (100, 560),
        (760, 520),
        (440, 640),
    ]
    starblossom = [
        (280, 160),
        (360, 140),
        (440, 120),
        (560, 140),
        (640, 160),
        (200, 200),
        (700, 240),
        (320, 640),
    ]
    grimshade = [
        (400, 100),
        (480, 90),
        (540, 100),
        (360, 80),
        (600, 120),
        (160, 240),
        (720, 280),
        (500, 640),
    ]

    blocks = ['[node name="MineableNodes" type="Node2D" parent="."]\n\n']
    uid = 1940000100
    for i, (x, y) in enumerate(moonbloom, start=1):
        blocks.append(node_block(f"BanditMoon{i}", "MineableNodes", "herb_scene", "herb_moon", x, y, uid))
        uid += 1
    for i, (x, y) in enumerate(bloodcap, start=1):
        blocks.append(node_block(f"BanditBlood{i}", "MineableNodes", "herb_scene", "herb_blood", x, y, uid))
        uid += 1
    for i, (x, y) in enumerate(starblossom, start=1):
        blocks.append(node_block(f"BanditStar{i}", "MineableNodes", "herb_scene", "herb_star", x, y, uid))
        uid += 1
    for i, (x, y) in enumerate(grimshade, start=1):
        blocks.append(node_block(f"BanditGrim{i}", "MineableNodes", "herb_scene", "herb_grim", x, y, uid))
        uid += 1

    text = insert_before_marker(
        text, '[node name="RespawnPoint"', "".join(blocks) + "\n"
    )
    path.write_text(text, encoding="utf-8")
    print(
        f"  planted moon={len(moonbloom)} blood={len(bloodcap)} "
        f"star={len(starblossom)} grim={len(grimshade)}"
    )


def main() -> None:
    patch_woodland_tiles()
    patch_woodland_east()
    patch_dimwood()
    patch_bandit()
    print("\nDone.")


if __name__ == "__main__":
    main()
