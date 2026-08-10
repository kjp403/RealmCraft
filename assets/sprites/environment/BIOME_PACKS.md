# Biome tile packs (Desert / Fire Forge / Sewers)

Orthogonal 16×16 (and RF Catacombs 32×32 atlas) art used to fill the former stub biomes.

| Pack | In-repo path | Used for |
|------|--------------|----------|
| Existing Desert world tiles | `world_tileset/Desert/` | Desert floors / cliffs / props |
| Existing Fire Forge sheet | `fire_forge/tiles.png` | Fire Forge floors / walls / lava |
| 2D Pixel Dungeon Asset Pack | `pixel_dungeon/` | Sewers floors / walls / props |
| RF Catacombs | `rf_catacombs/` | Sewers accent atlas + torch sprites |
| Critters (wolf sheets) | `assets/sprites/characters/critters/wolf/` | Reserved for future wildlife NPCs |
| Isometric tileset (upload) | — | **Not imported** — TileMaps are orthogonal; isometric art does not match movement/camera |

Rebuild tilesets + maps:

```bash
godot --headless --path . --import
godot --headless --path . -s tools/build_biome_tilesets.gd
godot --headless --path . -s tools/build_stub_biomes.gd
```
