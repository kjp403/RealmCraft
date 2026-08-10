# Biome tile packs (Desert / Fire Forge / Sewers)

| Pack / tileset | Path | Role |
|----------------|------|------|
| Desert world tiles | `world_tileset/Desert/` | Desert floors, cliffs, temple, props |
| Fire Forge sheet | `fire_forge/tiles.png` | Fire Forge floors / walls / industrial props |
| 2D Pixel Dungeon | `pixel_dungeon/` | Sewers floors / walls / décor |
| RF Catacombs | `rf_catacombs/` | Animated torch / candle / spike strips + atlas accents |
| Critter GIFs + sheets | `characters/critters/{stag,boar,badger,wolf}/` | Ambient fauna (non-attackable) |
| Decorative GIF frames | `rf_catacombs/*_strip.png` | Looping SceneProps lights / traps |

Rebuild:

```bash
godot --headless --path . --import
godot --headless --path . -s tools/build_biome_tilesets.gd
godot --headless --path . -s tools/build_biome_props.gd
godot --headless --path . -s tools/build_stub_biomes.gd
godot --headless --path . -s tools/verify_stub_biomes.gd
godot --path . --mode=client -s tools/render_biome_previews.gd
```

Warper IDs: Desert `25/125`, Fire Forge `26/126`, Sewers `28/128` → Castle Garden.

Maps ship **without attackable NPCs**. Ambient critters + animated décor live under `SceneProps` (client-local).
