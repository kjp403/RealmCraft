#!/usr/bin/env python3
"""Stamp Hollow Seep climaxes with unique (non-smithable) style weapons.

Smithable bronze–runite stays on the anvil. The campaign hands the drop ladder:
bone → spore → rustic → poison → fairy → sunsteel → fire → basilisk/runewoven.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QDIR = ROOT / "source/common/gameplay/quests/resources"
WEAP = "res://source/common/gameplay/items/weapons"
POTION = "res://source/common/gameplay/items/consumables/health_potion.tres"
GREATER = "res://source/common/gameplay/items/consumables/greater_health_potion.tres"
REWARD_SCRIPT = "res://source/common/gameplay/quests/quest_reward.gd"
ITEM_SCRIPT = "res://source/common/gameplay/items/item.gd"

STYLES = {
    "bone": [
        f"{WEAP}/sword/sword_bone.item.tres",
        f"{WEAP}/hammer/hammer_bone.item.tres",
        f"{WEAP}/bow/bone_bow.item.tres",
        f"{WEAP}/wand/wand_bone.item.tres",
        f"{WEAP}/book/book_bone.item.tres",
    ],
    "spore": [
        f"{WEAP}/sword/sword_spore.item.tres",
        f"{WEAP}/hammer/hammer_spore.item.tres",
        f"{WEAP}/bow/spore_bow.item.tres",
        f"{WEAP}/wand/wand_spore.item.tres",
        f"{WEAP}/book/book_spore.item.tres",
    ],
    "rustic": [
        f"{WEAP}/sword/sword_rustic.item.tres",
        f"{WEAP}/hammer/hammer_rustic.item.tres",
        f"{WEAP}/bow/rustic_bow.item.tres",
        f"{WEAP}/wand/wand_bandit.item.tres",
        f"{WEAP}/book/book_rustic.item.tres",
    ],
    "poison": [
        f"{WEAP}/sword/sword_poison.item.tres",
        f"{WEAP}/hammer/hammer_poison.item.tres",
        f"{WEAP}/bow/poison_bow.item.tres",
        f"{WEAP}/wand/wand_poison.item.tres",
        f"{WEAP}/book/book_poison.item.tres",
    ],
    "fairy": [
        f"{WEAP}/sword/sword_fairy.item.tres",
        f"{WEAP}/hammer/hammer_fairy.item.tres",
        f"{WEAP}/bow/fairy_bow.item.tres",
        f"{WEAP}/wand/wand_fairy.item.tres",
        f"{WEAP}/book/book_fairy.item.tres",
    ],
    "sunsteel": [
        f"{WEAP}/sword/sword_sunsteel.item.tres",
        f"{WEAP}/hammer/hammer_sunsteel.item.tres",
        f"{WEAP}/bow/sunsteel_bow.item.tres",
        f"{WEAP}/wand/wand_sunsteel.item.tres",
        f"{WEAP}/book/book_sunsteel.item.tres",
    ],
    "fire": [
        f"{WEAP}/sword/sword_fire.item.tres",
        f"{WEAP}/hammer/hammer_fire.item.tres",
        f"{WEAP}/bow/fire_bow.item.tres",
        f"{WEAP}/wand/fire_wand.item.tres",
        f"{WEAP}/book/book_fire.item.tres",
    ],
    "end": [
        f"{WEAP}/sword/sword_basilisk.item.tres",
        f"{WEAP}/hammer/hammer_basilisk.item.tres",
        f"{WEAP}/bow/wraithsilk_bow.item.tres",
        f"{WEAP}/wand/wand_runewoven.item.tres",
        f"{WEAP}/book/book_runewoven.item.tres",
    ],
}

QUESTS = [
    ("goblin_woodland/the_goblin_chief.tres", "bone", POTION, 8),
    ("hollow_seep/cut_the_heart.tres", "spore", POTION, 10),
    ("hollow_seep/break_the_cage.tres", "rustic", POTION, 10),
    ("hollow_seep/the_sovereign_below.tres", "poison", GREATER, 8),
    ("hollow_seep/bone_and_shard.tres", "fairy", GREATER, 8),
    ("hollow_seep/leave_the_crown.tres", "sunsteel", GREATER, 10),
    ("hollow_seep/the_fuel_lock.tres", "fire", GREATER, 10),
    ("hollow_seep/the_thing_it_was_built_to_run.tres", "end", GREATER, 12),
]


def patch(path: Path, style_key: str, potion: str, potion_n: int) -> None:
    text = path.read_text(encoding="utf-8")
    if "reward_style_weapons" in text:
        print(f"skip {path.name} (already stamped)")
        return

    extras: list[str] = [
        f'[ext_resource type="Script" path="{ITEM_SCRIPT}" id="kit_item"]',
    ]
    already_has_items = "\nreward_items =" in text.split("[resource]")[-1]
    if not already_has_items:
        extras = [
            f'[ext_resource type="Script" path="{REWARD_SCRIPT}" id="kit_reward"]',
            *extras,
            f'[ext_resource type="Resource" path="{potion}" id="kit_pot"]',
        ]
    style_ids: list[str] = []
    for i, wp in enumerate(STYLES[style_key]):
        sid = f"kit_w{i}"
        extras.append(f'[ext_resource type="Resource" path="{wp}" id="{sid}"]')
        style_ids.append(sid)

    insert_at = text.find("\n[sub_resource")
    if insert_at < 0:
        insert_at = text.find("\n[resource]")
    text = text[:insert_at] + "\n" + "\n".join(extras) + "\n" + text[insert_at:]

    refs = ", ".join(f'ExtResource("{sid}")' for sid in style_ids)
    style_line = f'reward_style_weapons = Array[ExtResource("kit_item")]([{refs}])'
    if already_has_items:
        for anchor in ("\nreward_gold =", "\ngrant_title =", "\nmetadata/slug"):
            if anchor in text:
                text = text.replace(anchor, f"\n{style_line}{anchor}", 1)
                break
    else:
        subs = "\n".join([
            '[sub_resource type="Resource" id="Reward_kit_potion"]',
            'script = ExtResource("kit_reward")',
            'item = ExtResource("kit_pot")',
            f"amount = {potion_n}",
            "",
        ])
        resource_at = text.find("\n[resource]")
        text = text[:resource_at] + "\n" + subs + text[resource_at:]
        reward_block = (
            'reward_items = Array[ExtResource("kit_reward")]([SubResource("Reward_kit_potion")])\n'
            + style_line
        )
        text = text.replace("\nreward_gold =", f"\n{reward_block}\nreward_gold =", 1)

    path.write_text(text, encoding="utf-8")
    print(f"stamped {path.name}")


def main() -> None:
    for rel, style, potion, n in QUESTS:
        patch(QDIR / rel, style, potion, n)


if __name__ == "__main__":
    main()
