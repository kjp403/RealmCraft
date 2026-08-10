# Tiny RPG character packs (imported)

Ready-to-place skins + stub enemy types from:

- Tiny RPG Character Asset Pack 01 (22 characters)
- Blood Monsters / Demon_A pack (2 characters)

## Where things live

| What | Path |
|------|------|
| PNG strips | `assets/sprites/characters/trpg_<name>/` |
| SpriteFrames | `source/common/gameplay/characters/sprite_frames/trpg_*.tres` |
| Enemy stubs | `source/common/gameplay/characters/npc/types/trpg/trpg_*.tres` |

Slugs are prefixed `trpg_` so they do not collide with existing `orc` / `skeleton` / `wizard` skins.

## Animations on each skin

`idle`, `walk`, `run` (cloned from walk), `death`, `attack`, `special` when the pack had Attack02/Summon/Heal, plus `hurt` / `block` / `attack_3` when present.

## Using later

1. Place a `hostile_npc.tscn` on a map.
2. Set `enemy_data` to e.g. `types/trpg/trpg_slime.tres`.
3. Tune HP/damage/loot on that `.tres` (stubs ship with light placeholder stats).

## Re-import

```bash
python3 tools/copy_trpg_character_sheets.py   # needs packs extracted under /tmp/asset_packs
godot --headless --path . --import
godot --headless --path . -s tools/build_trpg_sprite_frames.gd
```
