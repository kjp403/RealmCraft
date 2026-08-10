# Create a New Map in Arkenelle (Beginner Guide)

**Who this is for:** anyone who can click buttons in Godot.  
**What you will make:** a new playable zone (tiles + walls + music + portals in and out).  
**Time:** first map usually takes 1–2 hours if you go slow.

Download / print this file anytime. Paths start from the project root.

---

## Big picture (read once)

You need **four** things. Miss one and the zone will not work in the live game.

| # | Thing | What it is | Example |
|---|--------|------------|---------|
| 1 | **Pictures** | PNG tiles you downloaded | `assets/sprites/.../MyCave.png` |
| 2 | **TileSet** | Godot file that turns pictures into paintable tiles | `source/common/gameplay/maps/tilesets/my_cave_tileset.tres` |
| 3 | **Map scene** | The room you paint (ground, walls, spawn, exit portal) | `source/common/gameplay/maps/maps/my_cave/my_cave.tscn` |
| 4 | **Instance resource** | The “zone card” portals point at | `source/common/gameplay/maps/instance/instance_collection/biomes/my_cave.tres` |

Then you place a **portal on an old map** that points at #4, and an **exit portal on the new map** that points back.

```
Castle Garden / Woodland  --portal-->  My Cave
My Cave                   --portal-->  Castle Garden / Woodland
```

---

## Before you start

1. Open this project in **Godot 4.7** (same version the game uses).
2. Open the Godot **FileSystem** dock (left side).
3. Pick a short name with only letters and underscores, like `my_cave` or `crystal_grove`.  
   Use that same name for the folder, scene, and instance.

---

## Step 1 — Get an asset pack

1. Download a **2D top-down** tile pack (itch.io, OpenGameArt, etc.).
2. Prefer packs that say:
   - top-down / RPG / tileset
   - **16×16** or **32×32** tiles (Arkenelle mostly uses **16×16**)
3. Unzip the pack on your computer.
4. Find the PNG sheets (often named like `Tiles.png`, `Walls.png`, `Props.png`).

**Rule:** only use art you are allowed to use (license / credit the author if required).

---

## Step 2 — Put the pictures in the project

1. In your file explorer, go to the Arkenelle project folder.
2. Create a folder for your art, for example:

```
assets/sprites/environment/my_cave/
```

3. Copy your PNG files into that folder.
4. Go back to Godot. It should import them automatically (you will see the new files in FileSystem).

If Godot does not show them: click the FileSystem root and press **Reimport**, or restart Godot.

---

## Step 3 — Make a TileSet (the paint box)

A TileSet is the box of stamps you paint with.

### Easy path (copy a working one)

1. In FileSystem, go to `source/common/gameplay/maps/tilesets/`.
2. Right-click `mining_cave_tileset.tres` → **Duplicate**.
3. Rename the copy to `my_cave_tileset.tres`.
4. Double-click `my_cave_tileset.tres` to open it.
5. In the TileSet editor, point each atlas **Texture** at your new PNGs (or keep the cave art while you learn).
6. Save (`Ctrl+S` / `Cmd+S`).

### From scratch (short version)

1. Right-click `source/common/gameplay/maps/tilesets/` → **Create New → Resource** → choose **TileSet** → save as `my_cave_tileset.tres`.
2. Open it. Add a **TileSetAtlasSource**.
3. Set **Texture** to your PNG.
4. Set **Texture Region Size** to your tile size (usually `16 x 16`).
5. Click tiles you want to use so they become paintable.
6. **Important for walls:** select wall tiles → add a **Physics** polygon (full tile square is fine for beginners).  
   Arkenelle walk-blocking uses physics **layer that walls already use** on existing tilesets — when in doubt, open `mining_cave_tileset.tres`, click a wall tile, and copy how its Physics layer is set.
7. Save.

**Floor tiles:** usually **no** collision.  
**Wall tiles:** **yes** collision (or players walk through cliffs).

---

## Step 4 — Make the map scene (paint the room)

### 4a. Create the folder + scene

1. Create folder: `source/common/gameplay/maps/maps/my_cave/`.
2. Easiest start: duplicate an existing small map.
   - Example: duplicate `source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn`
   - Move/rename copy to `source/common/gameplay/maps/maps/my_cave/my_cave.tscn`
3. Or use the blank starter: `source/common/gameplay/maps/template/map_template.tscn` (duplicate it into your folder).

### 4b. Required node layout

Open `my_cave.tscn`. Your tree should look like this:

```
my_cave                          ← Node2D + map.gd script
├── Tiles                        ← Node2D (turn ON Y Sort)
│   ├── Ground                   ← TileMapLayer (floors)
│   ├── Walls                    ← TileMapLayer (block walking)
│   └── Props                    ← TileMapLayer (optional decorations)
├── ReplicatedPropsContainer     ← Node2D + replicated_props.gd
├── Entrance                     ← warper.tscn  (players land here)
└── ExitPortal                   ← portal.tscn  (leave the zone)
```

Checklist on the root `my_cave` node (Inspector):

| Property | What to set |
|----------|-------------|
| Script | `source/common/gameplay/maps/map.gd` |
| `replicated_props_container` | drag `ReplicatedPropsContainer` node |
| `music` | optional `.ogg` from `assets/audio/music/` |
| `map_background_color` | dark color for caves / sky color for outdoor |
| `camera_limit_left / top / right / bottom` | box around your painted area (in pixels) |

**Camera limits matter.** Click-to-move uses them as the walkable bounds.  
If left is `400` and your west wall is at `x=100`, players cannot path there.  
Set limits just outside your painted tiles (example: left `-16`, top `-16`, right `1280`, bottom `768`).

### 4c. Assign your TileSet and paint

1. Select `Ground` → Inspector → `tile_set` → your `my_cave_tileset.tres`.
2. Do the same for `Walls` and `Props`.
3. Select `Ground` → paint floors with the TileMap brush.
4. Select `Walls` → paint walls around the floors.
5. Leave open doorways where portals will sit.
6. Turn **Y Sort** on for `Tiles`, `Ground`, `Walls`, `Props` if characters should walk “in front of / behind” art.

### 4d. Entrance warper (where players appear)

1. Instance `source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn`.
2. Name it `Entrance`.
3. Put it on open floor (not inside a wall).
4. Set **`warper_id = 30`** (pick any unused number; remember it).

This id is the landing pad. Other maps’ portals will say `target_id = 30` to drop players here.

### 4e. Exit portal (go back)

1. Instance `source/common/gameplay/maps/components/interaction_areas/warper/portal/portal.tscn`.
2. Name it `ExitPortal`.
3. Place on open floor near the entrance.
4. Set:

| Property | Example |
|----------|---------|
| `destination_label` | `Goblin Woodland` |
| `target_instance` | `biomes/woodland.tres` (or hub `overworld.tres`) |
| `warper_id` | `31` (unique on **this** map) |
| `target_id` | warper id on the **destination** map (Woodland mining return uses `130`) |
| `portal_color` | any color you like |

Save the map.

---

## Step 5 — Make the Instance resource (the zone card)

Portals do **not** point at `.tscn` files directly. They point at an `InstanceResource`.

1. Go to `source/common/gameplay/maps/instance/instance_collection/biomes/`.
2. Duplicate `mining_cave.tres` → rename to `my_cave.tres`.
3. Open `my_cave.tres` and set:

| Property | Example |
|----------|---------|
| `instance_name` | `my_cave` (must be unique) |
| `map_path` | `res://source/common/gameplay/maps/maps/my_cave/my_cave.tscn` |
| `zone_title` | `My Cave` (pretty name players see) |
| `level_min` / `level_max` | `1` / `10` (shown on portals as Lv) |
| `show_discovery` | on (zone banner when entering) |
| `death_return_instance` | where players go if they die here (e.g. woodland) |
| `death_return_warper_id` | landing warper id on that return map |

Save.

The game auto-loads every `.tres` under `instance_collection/`. You do **not** register it in a list.

---

## Step 6 — Door from an existing map into your zone

Example: add a portal in Goblin Woodland.

1. Open `source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn` (or hub / another map).
2. Instance `portal.tscn` as a child of the map root.
3. Place it on **open grass/floor**, not under a tree trunk and not inside wall collision.
4. Set:

| Property | Example |
|----------|---------|
| `destination_label` | `My Cave` |
| `target_instance` | your `my_cave.tres` |
| `warper_id` | pick unused id on **this** map (e.g. `140`) |
| `target_id` | your cave Entrance id (`30` from Step 4d) |
| `portal_color` | color that fits the zone |

5. If players should return to this exact portal after death / exit, set the cave’s  
   `death_return_warper_id` (and exit portal `target_id`) to this `warper_id` (`140`).

Save.

### Round-trip cheatsheet

```
Woodland portal:  target_instance = my_cave.tres , target_id = 30
Cave Entrance:    warper_id = 30
Cave ExitPortal:  target_instance = woodland.tres , target_id = 140
Woodland portal:  warper_id = 140
```

Ids must match in pairs. Wrong id = silent wrong spawn or “broken” portal.

---

## Step 7 — Test like a player

1. Run the game (editor F5, or your usual client).
2. Walk to the new portal on the old map.
3. Confirm:
   - label shows (`My Cave (Lv 1+)`)
   - you appear on the Entrance warper
   - you can walk (not stuck in walls)
   - exit portal sends you back to the right spot
4. If click-move refuses an area, check **camera limits** and **wall collision** first.

---

## Step 8 — Ship it (this project’s live pipeline)

1. Bump `config/version` in `project.godot` (clients need the new scenes).
2. Commit + merge to `main`.
3. **Deploy VPS** runs on every `main` push (server/maps).
4. **Release clients to itch** runs when `project.godot` changes.
5. Update / relaunch the client before testing live.

---

## Copy-paste checklist

- [ ] Art PNGs in `assets/sprites/...`
- [ ] TileSet saved under `source/common/gameplay/maps/tilesets/`
- [ ] Wall tiles have physics collision; floor tiles do not
- [ ] Map scene under `source/common/gameplay/maps/maps/<name>/`
- [ ] Root uses `map.gd` + `ReplicatedPropsContainer`
- [ ] `Ground` / `Walls` TileMapLayers paint the space
- [ ] Camera limits surround the painted area
- [ ] `Entrance` warper with a remembered `warper_id`
- [ ] Exit `portal.tscn` points at an existing `InstanceResource`
- [ ] New `InstanceResource` `.tres` under `instance_collection/` (usually `biomes/`)
- [ ] Entrance portal on an old map points at that `.tres` + correct `target_id`
- [ ] Ids match both ways
- [ ] Version bump before merge if clients need the new scenes

---

## Common mistakes (fix these first)

| Problem | Likely cause |
|---------|----------------|
| Portal does nothing | `target_instance` empty, or destination `.tres` has wrong `map_path` |
| You appear in the wrong place | `target_id` ≠ destination `warper_id` |
| Cannot walk west / into an area | `camera_limit_*` too tight, **or** wall tiles covering the floor |
| Walk through cliffs | Wall tiles missing physics collision |
| Portal hidden / hard to click | Placed under a tree sprite or on a wall cell |
| Works in editor, missing live | Forgot version bump / client not updated |
| Zone name wrong on banner | Empty `zone_title` on the InstanceResource |

---

## Where to look at real examples

| Example | Path |
|---------|------|
| Small cave map | `source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn` |
| Cave tileset | `source/common/gameplay/maps/tilesets/mining_cave_tileset.tres` |
| Cave zone card | `source/common/gameplay/maps/instance/instance_collection/biomes/mining_cave.tres` |
| Woodland → cave portal | `source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn` (`MiningCavePortal`) |
| Blank starter | `source/common/gameplay/maps/template/map_template.tscn` |
| More recipes (NPCs, shops, etc.) | `CONTENT_AUTHORING.md` |

---

## Optional extras (after the basics work)

- **Lights:** add `PointLight2D` or instance `source/common/gameplay/lighting/campfire.tscn`.
- **Mood:** add a `CanvasModulate` child to tint the whole map.
- **Gather nodes:** instance `mineable_node.tscn` and assign a vein/tree `.tres` from `source/common/gameplay/maps/components/mineable_nodes/`.
- **Music:** assign an `.ogg` on the map root `music` property.
- **Death return:** set `death_return_instance` + `death_return_warper_id` on the zone `.tres`.

---

## One-sentence summary

**Put art in the project → make a TileSet → paint a map scene with Entrance + Exit → make a biome `.tres` → point a portal at that `.tres` with matching warper ids → bump version and merge.**
