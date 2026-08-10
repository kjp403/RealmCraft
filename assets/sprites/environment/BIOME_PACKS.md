# Biome tile packs (Desert / Fire Forge / Sewers / Mining Cave)

| Pack / tileset | Path | Role |
|----------------|------|------|
| Desert world tiles | `world_tileset/Desert/` | Desert floors, cliffs, temple, props |
| Top Down Lava 16×16 | `lava_forge_16/` | Fire Forge floors / walls / animated lava (cut as 16×16 — never full sheets as tiles) |
| Fire Forge (legacy sheet) | `fire_forge/tiles.png` | Kept for reference; Forge maps no longer paint this sheet |
| 2D Pixel Dungeon | `pixel_dungeon/` | Sewers floors / walls / décor |
| RF Catacombs | `rf_catacombs/` | Animated torch / candle / spike strips + atlas accents |
| RPG Worlds Caves | `rpgw_caves/` | Mining Cave 32×32 floors / walls / crystals (Szadi) |
| Starter Tiles Platformer | `starter_platformer/` | DarkCastle sewer décor + OutdoorHouse oasis stalls (SciGho) |
| DG Fire Zone Free | `dg_fire/` | Legacy accents (unused by current Forge builder) |
| DG Dungeon Free | `dg_dungeon/` | Set1 floors/pillars/urns for Sewers (SnowHex) |
| Critter GIFs + sheets | `characters/critters/{stag,boar,badger,wolf}/` | Ambient fauna (non-attackable) |
| Decorative GIF frames | `rf_catacombs/*_strip.png` + `lava_forge_16/animated/` | Looping SceneProps lights / lava / traps |

**Fire Forge rule:** PNG tile sheets are atlases. Cut/paint **individual 16×16 cells** only. Do not place an entire sheet (or a contiguous sheet block) as one tile or prop stamp.

Rebuild:

```bash
godot --headless --path . --import
godot --headless --path . -s tools/build_biome_tilesets.gd
godot --headless --path . -s tools/build_biome_props.gd
godot --headless --path . -s tools/build_stub_biomes.gd
godot --headless --path . -s tools/verify_stub_biomes.gd
godot --path . --mode=client -s tools/render_biome_previews.gd
godot --headless --path . -s tools/build_rpgw_cave_tileset.gd
godot --headless --path . -s tools/build_mining_cave.gd
godot --headless --path . -s tools/render_mining_cave_previews.gd
```

Warper IDs: Desert `25/125`, Fire Forge `26/126`, Sewers `28/128` → Castle Garden.
Mining Cave: entrance `30`, portal `131` → Woodland `130`.

Stub biomes ship **without attackable NPCs**. Ambient critters + animated décor live under `SceneProps` (client-local).
Mining Cave uses `rpgw_caves_tileset.tres` (not the Hollow-shared `mining_cave_tileset.tres`).
