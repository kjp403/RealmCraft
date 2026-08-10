# Biome tile packs (Desert / Fire Forge / Sewers)

Orthogonal 16×16 art used to fill the former stub biomes.

| Pack / tileset | In-repo path | Used for |
|----------------|--------------|----------|
| Desert world tiles | `world_tileset/Desert/` | Desert floors, mesa/cliff stamps, temple, props |
| Mining cave tileset | `mining_cave_tileset.tres` | Fire Forge + Sewers **structure** (authored Fungus room stamps — same craft as Mining Cave / Hollow) |
| Fire Forge sheet | `fire_forge/tiles.png` | Fire Forge **accent** layer (barrels / crates) + hot lighting |
| 2D Pixel Dungeon | `pixel_dungeon/` | Sewers **accent** layer (torches, webs, bones, doors) |
| RF Catacombs | `rf_catacombs/` | Available on sewers accent atlas; used sparingly |
| Critters (wolf) | `characters/critters/wolf/` | Reserved for future wildlife NPCs |
| Isometric upload | — | **Not imported** — TileMaps are orthogonal |

Rebuild:

```bash
godot --headless --path . --import
godot --headless --path . -s tools/build_biome_tilesets.gd
godot --headless --path . -s tools/build_stub_biomes.gd
godot --headless --path . -s tools/verify_stub_biomes.gd
godot --path . -s tools/render_biome_previews.gd
```

Warper IDs (unchanged): Desert 25/125, Fire Forge 26/126, Sewers 28/128 → Castle Garden.
