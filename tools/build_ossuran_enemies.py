#!/usr/bin/env python
"""Author the Ossuran support roster: four wave minions, three pillars.

The BOSS is not here -- see the note on ENEMIES below. Ossuran already ships as
`npc/types/bosses/cleetus.tres`.

Generated rather than hand-written because the seven resources are the same
130-field EnemyTypeResource with a handful of numbers moved, and the fight's
whole difficulty curve is those numbers. Keeping them in ONE table means the
encounter can be retuned by reading a single screen instead of diffing eight
near-identical .tres files -- and it makes it impossible for a field to drift
between two minions that were supposed to match.

    python tools/build_ossuran_enemies.py
    godot --headless --path . -s tools/update_enemy_types_index.gd

The second step is not optional: enemy types are spawned BY SLUG through
ContentRegistryHub, which resolves against enemy_types_index.tres. A .tres that
exists on disk but is not in the index does not exist as far as
`spawn_dynamic({"enemy_type_slug": ...})` is concerned, and the wave silently
spawns nothing.

Written as text, with `path=` references and no uid=, deliberately: the index
tool re-saves each resource through ResourceSaver to stamp metadata, and a
headless save strips uid= from a .tres and every ext_resource in it. Authoring
without uids in the first place makes that pass a no-op instead of a silent
rewrite.
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "source/common/gameplay/characters/npc/types/ossuran"
FRAMES = "res://source/common/gameplay/characters/sprite_frames"

# Every EnemyTypeResource field, at its default. Overrides are merged over this,
# so a generated resource always writes the COMPLETE field set -- a .tres that
# omits fields inherits whatever the script's defaults happen to be that week,
# which is how two mobs authored a month apart end up quietly different.
BASE: dict[str, object] = {
    "visual_scale": 1.0,
    "is_boss": False,
    "combat_level": 1,
    "max_health": 50.0,
    "attack_damage": 8.0,
    "attack_cooldown": 1.5,
    "armor": 0.0,
    "mr": 0.0,
    "move_speed": 20,
    "distance_to_attack": 20,
    "max_distance_from_spawn": 300,
    "leashes": True,
    "detection_radius": 150,
    "chase_on_area": False,
    "is_lone": False,
    "wander_radius": 0.0,
    "wander_pause_min_s": 1.5,
    "wander_pause_max_s": 4.0,
    "xp_reward": 25,
    "respawn_delay": 5.0,
    "respawns": True,
    "combat_skill_xp_override": 0,
    "enrage_health_fraction": 0.5,
    "hp_thresholds": [],
    "slam_radius": 110.0,
    "slam_windup_s": 1.1,
    "slam_damage": 45.0,
    "slam_on_target": True,
    "slam_interval_s": 6.0,
    "enraged_slam_interval_s": 3.5,
    "add_enemy_slug": "rat_base",
    "add_count": 0,
    "add_spread_px": 48.0,
    "enrage_speed_mult": 1.3,
    "laser_range": 0.0,
    "laser_width": 28.0,
    "laser_windup_s": 1.15,
    "laser_damage": 55.0,
    "laser_interval_s": 8.0,
    "enraged_laser_interval_s": 5.0,
    "arm_shot_interval_s": 0.0,
    "arm_shot_damage": 40.0,
    "arm_shot_speed": 220.0,
    "arm_shot_lifetime_s": 1.4,
    "enraged_arm_shot_interval_s": 0.0,
    "ornate_chest_top_min": 0,
    "ornate_chest_top_max": 0,
    "ornate_chest_second_min": 0,
    "ornate_chest_second_max": 0,
    "ornate_chest_consolation_chance": 0.0,
    "phase2_skin": "",
    "cast_anim": "special",
    "telegraph_element": 0,
    "enraged_telegraph_element": -1,
    "meteor_count": 0,
    "meteor_radius": 56.0,
    "meteor_damage": 60.0,
    "meteor_windup_s": 1.5,
    "meteor_stagger_s": 0.45,
    "meteor_spread_px": 190.0,
    "meteor_interval_s": 11.0,
    "enraged_meteor_interval_s": 0.0,
    "meteor_phase": 0,
    "sweep_arc_deg": 0.0,
    "sweep_range": 300.0,
    "sweep_width": 34.0,
    "sweep_windup_s": 1.2,
    "sweep_duration_s": 1.1,
    "sweep_damage": 70.0,
    "sweep_interval_s": 12.0,
    "enraged_sweep_interval_s": 0.0,
    "sweep_phase": 0,
    "frost_safe_radius": 0.0,
    "frost_windup_s": 2.6,
    "frost_damage": 110.0,
    "frost_offset_px": 150.0,
    "frost_interval_s": 16.0,
    "enraged_frost_interval_s": 0.0,
    "frost_phase": 0,
    "chain_targets": 0,
    "chain_range": 170.0,
    "chain_damage": 45.0,
    "chain_windup_s": 0.9,
    "chain_interval_s": 9.0,
    "enraged_chain_interval_s": 0.0,
    "chain_phase": 0,
    "slam_followup_lunge": False,
    "sear_wound_duration_s": 0.0,
    "sear_wound_damage": 80.0,
    "sear_wound_radius": 72.0,
    "sear_wound_interval_s": 14.0,
    "enraged_sear_wound_interval_s": 0.0,
    "sear_wound_windup_s": 0.9,
    "style_ward_interval_s": 0.0,
    "style_ward_wrong_mult": 0.25,
    "soft_enrage_s": 0.0,
    "soft_enrage_ramp": 0.25,
}

# A stationary construct. Pillars must never chase, never wander and never leash
# home -- their brain (OssuranPillar) does all the acting, and a pillar that
# walks is a bug the player reads as the fight breaking.
PILLAR_COMMON: dict[str, object] = {
    "combat_level": 420,
    "max_health": 5200.0,
    # The body's own auto-attack is off: every pillar's damage comes from its
    # brain, so the two can never double-dip on the same target.
    "attack_damage": 0.0,
    "attack_cooldown": 99.0,
    "armor": 60.0,
    "mr": 60.0,
    "move_speed": 0,
    "distance_to_attack": 8,
    "detection_radius": 40,
    "wander_radius": 0.0,
    "leashes": False,
    "respawns": False,
    "respawn_delay": 0.5,
    "xp_reward": 1200,
    # Smaller than Ossuran (1.4 on a 64px frame). At 1.6 the pillars rendered
    # BIGGER than the boss standing between them, which reads as three bosses and
    # one add. A phase-2 objective has to be substantial and clearly subordinate.
    "visual_scale": 1.15,
}

# Wave trash. Short respawn_delay is load-bearing: for a single-life mob that
# value is how long the CORPSE lingers before despawn_dynamic frees it, and the
# wave manager advances on tree_exited -- so a long delay reads in game as a
# pause between waves for no visible reason.
MINION_COMMON: dict[str, object] = {
    "respawns": False,
    "respawn_delay": 0.6,
    "leashes": False,
    "chase_on_area": True,
    "detection_radius": 420,
}

ENEMIES: dict[str, dict[str, object]] = {
    # NOTE: the BOSS is deliberately absent from this table. Ossuran already
    # exists as `npc/types/bosses/cleetus.tres` ("Ossuran, Kindled and Cold",
    # enemy_type &"ossuran", 60k HP, with its own cleetus -> cleetus_frost
    # kindled/cold phase swap). Generating a second one here would have shadowed
    # the real boss with a weaker duplicate under a colliding slug. The encounter
    # spawns the existing body by slug; only its hp_thresholds were added, in
    # place, on that resource.
    # --- WAVE MINIONS --------------------------------------------------------
    "ossuran_bonepicker": MINION_COMMON | {
        "display_name": "Bonepicker",
        "skin": f"{FRAMES}/trpg_skeleton.tres",
        "combat_level": 240,
        "max_health": 900.0,
        "attack_damage": 62.0,
        "attack_cooldown": 1.3,
        "armor": 20.0,
        "mr": 10.0,
        "move_speed": 118,
        "distance_to_attack": 20,
        "xp_reward": 420,
    },
    "ossuran_emberling": MINION_COMMON | {
        "display_name": "Emberling",
        "skin": f"{FRAMES}/hell_imp.tres",
        "combat_level": 300,
        "max_health": 1400.0,
        "attack_damage": 84.0,
        "attack_cooldown": 1.5,
        "armor": 26.0,
        "mr": 40.0,
        "move_speed": 104,
        "distance_to_attack": 22,
        "xp_reward": 620,
        "telegraph_element": 0,
    },
    "ossuran_cinder_archer": MINION_COMMON | {
        "display_name": "Cinder Archer",
        "skin": f"{FRAMES}/trpg_skeleton_archer.tres",
        "combat_level": 320,
        "max_health": 1100.0,
        "attack_damage": 96.0,
        "attack_cooldown": 2.0,
        "armor": 16.0,
        "mr": 18.0,
        "move_speed": 88,
        # The reason this wave changes the room: it attacks from across it, so
        # standing still in one corner stops being viable.
        "distance_to_attack": 190,
        "xp_reward": 700,
    },
    "ossuran_marrow_knight": MINION_COMMON | {
        "display_name": "Marrow Knight",
        "skin": f"{FRAMES}/trpg_armored_skeleton.tres",
        "combat_level": 380,
        "max_health": 3200.0,
        "attack_damage": 140.0,
        "attack_cooldown": 1.8,
        "armor": 70.0,
        "mr": 35.0,
        "move_speed": 78,
        "distance_to_attack": 26,
        "xp_reward": 1400,
        "visual_scale": 1.25,
    },
    # --- PILLARS -------------------------------------------------------------
    "ossuran_pillar_ember": PILLAR_COMMON | {
        "display_name": "Ember Pillar",
        "skin": f"{FRAMES}/ossuran_pillar_ember.tres",
        "telegraph_element": 0,
    },
    "ossuran_pillar_thorn": PILLAR_COMMON | {
        "display_name": "Thorn Pillar",
        "skin": f"{FRAMES}/ossuran_pillar_thorn.tres",
        "telegraph_element": 3,
    },
    "ossuran_pillar_hex": PILLAR_COMMON | {
        "display_name": "Hex Pillar",
        "skin": f"{FRAMES}/ossuran_pillar_hex.tres",
        "telegraph_element": 2,
    },
}

SCRIPT_REFS = """[ext_resource type="Script" path="res://source/common/gameplay/characters/npc/behaviors/mob_attack.gd" id="1_attack"]
[ext_resource type="Script" path="res://source/common/gameplay/characters/npc/behaviors/mob_behavior.gd" id="2_behavior"]
[ext_resource type="Script" path="res://source/common/gameplay/combat/loot_drop.gd" id="3_drop"]
[ext_resource type="Script" path="res://source/common/gameplay/characters/npc/enemy_type_resource.gd" id="4_type"]
"""


def fmt(value: object) -> str:
    """Render a Python value as GDScript resource-file syntax."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return f"{value}"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        inner = ", ".join(fmt(v) for v in value)
        return f"Array[float]([{inner}])"
    return str(value)


def build(slug: str, spec: dict[str, object]) -> str:
    fields = BASE | spec
    skin_path = str(fields.pop("skin"))
    display = str(fields.pop("display_name"))

    lines = ['[gd_resource type="Resource" script_class="EnemyTypeResource" format=3]', ""]
    lines.append(SCRIPT_REFS.rstrip())
    lines.append(f'[ext_resource type="SpriteFrames" path="{skin_path}" id="5_skin"]')
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("4_type")')
    lines.append(f"enemy_type = &\"{slug}\"")
    lines.append(f'display_name = "{display}"')
    lines.append('skin = ExtResource("5_skin")')

    for key, value in fields.items():
        if key in ("add_enemy_slug", "cast_anim"):
            lines.append(f'{key} = &"{value}"')
        elif key == "phase2_skin":
            lines.append(f'{key} = "{value}"')
        else:
            lines.append(f"{key} = {fmt(value)}")

    # Empty typed arrays, matching how the hand-authored resources write them.
    lines.append('behaviors = Array[ExtResource("2_behavior")]([])')
    lines.append('attacks = Array[ExtResource("1_attack")]([])')
    lines.append('loot = Array[ExtResource("3_drop")]([])')
    return "\n".join(lines) + "\n"


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for slug, spec in ENEMIES.items():
        path = OUT_DIR / f"{slug}.tres"
        path.write_text(build(slug, spec), encoding="utf-8")
        print(f"  wrote {path.relative_to(ROOT)}")
    print(f"{len(ENEMIES)} enemy types written")
    print("NEXT: godot --headless --path . -s tools/update_enemy_types_index.gd")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
