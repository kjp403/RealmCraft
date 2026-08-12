#!/usr/bin/env python3
"""Count Farming herb MineableNodes after plant_farming_herbs.py."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKS = {
    "woodland_tiles": (
        ROOT / "source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn",
        {
            "healing": r'\[node name="(?:HerbNode\d+|SecretHerbNode)"',
            "frost": r'\[node name="Frostpetal\d+"',
            "forbidden": r'\[node name="(?:Sunwort|Moonbloom|Bloodcap|Starblossom|Grimshade)',
        },
    ),
    "woodland_east": (
        ROOT / "source/common/gameplay/maps/maps/woodland/woodland_east.tscn",
        {
            "healing": r'\[node name="EastHerb\d+"',
            "frost": r'\[node name="EastFrost\d+"',
            "forbidden": r'\[node name="(?:Sunwort|Moonbloom|Bloodcap|Starblossom|Grimshade|Dim)',
        },
    ),
    "dimwood": (
        ROOT / "source/common/gameplay/maps/maps/forest/forest.tscn",
        {
            "healing": r'\[node name="(?:HealingHerb\d+|DimHeal\d+)"',
            "frost": r'\[node name="DimFrost\d+"',
            "sunwort": r'\[node name="DimSun\d+"',
            "moonbloom": r'\[node name="DimMoon\d+"',
            "bloodcap": r'\[node name="DimBlood\d+"',
        },
    ),
    "bandit": (
        ROOT / "source/common/gameplay/maps/maps/bandit_hideout/bandit_hideout.tscn",
        {
            "moonbloom": r'\[node name="BanditMoon\d+"',
            "bloodcap": r'\[node name="BanditBlood\d+"',
            "starblossom": r'\[node name="BanditStar\d+"',
            "grimshade": r'\[node name="BanditGrim\d+"',
        },
    ),
}

ok = True
for name, (path, pats) in CHECKS.items():
    text = path.read_text(encoding="utf-8")
    print(f"== {name} ==")
    for key, rx in pats.items():
        n = len(re.findall(rx, text))
        print(f"  {key}: {n}")
        if key == "forbidden" and n:
            ok = False
            print("  FAIL: high-tier herbs still on starter woodland")
        if key != "forbidden" and n == 0:
            ok = False
            print("  FAIL: expected some nodes")

oak = (ROOT / "source/common/gameplay/maps/components/mineable_nodes/oak_tree.tres").read_text(
    encoding="utf-8"
)
if "visual_scale = 1.4" not in oak:
    ok = False
    print("FAIL: oak visual_scale missing")
else:
    print("oak visual_scale = 1.4 OK")

raise SystemExit(0 if ok else 1)
