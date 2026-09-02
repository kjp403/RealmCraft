# Content Authoring Guide (Beginner)

Practical Godot-editor recipes for Arkenelle / RealmCraft (Godot 4.x).  
Paths are from the project root. Property names match the Inspector.

> **Naming note:** Friendly NPCs use `npc_name` on the resource (not `display_name`). At runtime the NPC node copies `npc_name` → Character `display_name` for the floating label.

---

## 1. NPCs

### Core files

| What | Path |
|------|------|
| NPC scene (place this in maps) | `source/common/gameplay/characters/npc/npc.tscn` |
| NPC resource script | `source/common/gameplay/characters/npc/npc_resource.gd` (`NPCResource`) |
| Friendly NPC definitions | `source/common/gameplay/characters/npc/npcs/*.tres` |
| Woodland-specific NPCs | `source/common/gameplay/characters/npc/npcs/woodland/*.tres` |
| Enemy type defs (hostile, different system) | `source/common/gameplay/characters/npc/types/**/*.tres` |
| Skins (SpriteFrames) | `source/common/gameplay/characters/sprite_frames/*.tres` |

### Example NPC resources

| File | Notes |
|------|--------|
| `source/common/gameplay/characters/npc/npcs/starter_merchant.tres` | Shop + Talk |
| `source/common/gameplay/characters/npc/npcs/mira.tres` | Shop + Quests + Talk |
| `source/common/gameplay/characters/npc/npcs/woodland/hermit.tres` | Shop + Talk |
| `source/common/gameplay/characters/npc/npcs/watch_sergeant.tres` | Quest giver style |
| `source/common/gameplay/characters/npc/npcs/forager_maela.tres` | Woodland forager |

### `NPCResource` fields that matter

Open a `.tres` like `starter_merchant.tres` in the Inspector:

| Property | Type | Purpose |
|----------|------|---------|
| `npc_name` | `String` | Name shown as dialogue title / floating label |
| `skin` | `SpriteFrames` | Appearance (drag from `sprite_frames/`) |
| `greeting` | multiline `String` | Text above the option buttons (BBCode OK) |
| `interactions` | `Array[NPCInteraction]` | What the NPC can do |

There is **no** top-level `shop` or `dialogue` field on `NPCResource`.  
Those live as entries inside `interactions`.

### Interaction types (add as array elements)

Scripts under `source/common/gameplay/characters/npc/interactions/`:

| Class | Script | Key properties |
|-------|--------|----------------|
| `ShopInteraction` | `shop_interaction.gd` | `shop` → `ShopResource` |
| `DialogueInteraction` | `dialogue_interaction.gd` | `lines` (`Array[String]`, one page each), optional `label_override` |
| `QuestInteraction` | `quest_interaction.gd` | `quests` → `Array[QuestResource]` |
| `SlayerInteraction` | `slayer_interaction.gd` | `master` → `SlayerMasterResource` (from `source/common/gameplay/slayer/masters/`) |
| Base | `npc_interaction.gd` | optional `label_override`, `icon_override` on every interaction |

Also available: `wardrobe_interaction.gd`, `name_change_interaction.gd`, `attribute_reset_interaction.gd`, `dungeon_interaction.gd`, `menu_interaction.gd`.

**Giver key / shop key:** taken from the **filename slug** of the `.tres`  
(e.g. `mira.tres` → `mira`). Prefer a real `.tres` file over an inline resource inside a scene (inline resources break quest/shop keys).

### Recipe: create a new friendly NPC

1. In FileSystem, duplicate a simple example:  
   `source/common/gameplay/characters/npc/npcs/starter_merchant.tres`  
   → e.g. `source/common/gameplay/characters/npc/npcs/my_vendor.tres`
2. Open `my_vendor.tres`. Set:
   - `npc_name` = `"My Vendor"`
   - `skin` = pick a `SpriteFrames` from `source/common/gameplay/characters/sprite_frames/`
   - `greeting` = opening line
3. Edit `interactions`:
   - Keep / add a `ShopInteraction` and assign its `shop` field
   - Optionally add a `DialogueInteraction` with `lines` filled in
4. Save. Filename becomes the stable id (`my_vendor`).

### Recipe: place an NPC on a map (hub example)

Reference scene: `source/common/gameplay/maps/maps/hub.tscn`

1. Open `hub.tscn`.
2. Find the `NPCs` node (direct child of the map root `Hub`).
3. Instance `source/common/gameplay/characters/npc/npc.tscn` as a child of `NPCs`.
4. Rename the node (e.g. `MyVendor`) — useful fallback if the resource were ever inline.
5. In the Inspector on that instance, set:
   - `npc_resource` → your `.tres` (e.g. `my_vendor.tres`)
   - `position` → place them in the world (Transform → Position)
6. Save the map.

Hub currently places NPCs like:

```
Hub
└── NPCs
    ├── RoyalGuard      (npc.tscn, npc_resource, position)
    ├── RoyalGuard2
    ├── QuestGiver
    ├── ForgeSmith
    └── TheTailor
```

Woodland places NPCs as **direct children of the map** (no `NPCs` folder required — both work as long as they are under the Map node):

```
Woodland
├── WardenBren   (npc_resource = warden_bren.tres)
└── Mira         (npc_resource = mira.tres)
```

Map: `source/common/gameplay/maps/maps/woodland/woodland.tscn`

---

## 2. Maps

### Where map scenes live

Root folder: `source/common/gameplay/maps/maps/`

| Map scene | Role |
|-----------|------|
| `hub.tscn` | Live social hub / “Castle Garden” (**this is what `overworld.tres` loads**) |
| `overworld.tscn` | Alternate/older overworld scene (not the active hub instance) |
| `woodland/woodland.tscn` | Goblin Woodland biome |
| `woodland/woodland_tiles.tscn` | Woodland tile helper scene |
| `forest/forest.tscn` | Forest biome |
| `bandit_hideout/bandit_hideout.tscn` | Bandit Hideout |
| `fungus_cave/fungus_cave.tscn` | Fungus Cave |
| `fungus_cave/fungus_dungeon.tscn` | Fungus dungeon |
| `dungeon/dungeon.tscn` | Dungeon |
| `dungeon/dungeon_entrance.tscn` | Dungeon entrance |
| `guild_house/outside_building.tscn` | Guild house exterior prop |
| `guild_house/inside_map.tscn` | Guild house interior |
| `guild_house/jail_room.tscn` | Jail |
| `smith_house/outside_building.tscn` / `inside_map.tscn` | Smith |
| `trade_house/outside_building.tscn` / `inside_map.tscn` | Trade house |
| `spar_house/*` | Spar / arena maps |
| `guild_outpost_base/*` | Guild outpost |
| `castle/outside_building.tscn` | Castle exterior |
| `misc_buildings/*` | Misc houses / mining vendor |
| `template/map_template.tscn` | Blank map starter (`source/common/gameplay/maps/template/`) |

#### Generated biome maps — do not hand-edit

Desert, Fire Forge and Sewers, plus their six sub-levels, are **written by
scripts**. Editing the `.tscn` by hand will be lost the next time the generator
runs. Change the generator instead.

| Map | Generator |
|-----|-----------|
| `desert/desert.tscn`, `fire_forge/fire_forge.tscn`, `sewers/sewers.tscn` | `tools/build_stub_biomes.gd` |
| `desert/sunspire_terraces.tscn`, `desert/sunken_tombs.tscn` | `tools/build_biome_levels.gd` |
| `sewers/gutterworks.tscn`, `sewers/drowned_cistern.tscn` | `tools/build_biome_levels.gd` |
| `fire_forge/bellows_gallery.tscn`, `fire_forge/cinder_deeps.tscn` | `tools/build_biome_levels.gd` |

The three tilesets come from `tools/build_biome_tilesets.gd`, which is
reproducible — running it with no source change rewrites the `.tres` files
byte-for-byte. **A tile only blocks the player if that atlas cell carries a
collision polygon there**; props stamped onto the Props layer are decorative
unless their tile is marked. This is the trap to remember when picking new
tiles: several banks that look like floor (the OutdoorHouseSet paving, for
instance) are marked solid because they came from a platformer wall set.

The second trap is the mirror of the first: **a tile that looks like floor but is
mostly bare canvas**. The Epic RPG World packs draw their edge, rim and corner
pieces to be composited *over* a ground tile, so an outer corner can be only a
third opaque and a long edge about half. Painted onto the Ground layer it
replaces the floor cell outright and the bare part becomes a hole through to
`map_background_color` — grey notches around a raised slab, a hairline down a
shoreline. Only the fully opaque interior tiles belong on Ground; caps, edges,
corners, bank lips and drain covers go on a layer above it with the floor left
intact underneath. `tools/audit_tile_opacity.gd` composites the real per-pixel
alpha of all four layers and fails on any cell the stack does not cover.

The stair portals joining each surface map to its two sub-levels are appended by
`tools/add_biome_stairs.gd`. It inserts nodes as text and never touches a
`tile_map_data` line, so the surface maps' art is untouched; re-running it is a
no-op once the stairs exist.

Gates to run after any change here:

```bash
godot --headless --path . -s tools/build_biome_levels.gd && godot --headless --path . -s tools/audit_biome_collision.gd && godot --headless --path . -s tools/audit_tile_opacity.gd && godot --headless --path . -s tools/verify_biome_levels.gd && godot --headless --path . -s tools/verify_stub_biomes.gd
```

Overview renders for eyeballing layout:

```bash
godot --path . -s tools/render_biome_level_previews.gd -- --outdir=<dir>
```

### Instance resources (what portals point at)

`source/common/gameplay/maps/instance/instance_collection/`

| Resource | Points at |
|----------|-----------|
| `overworld.tres` | `hub.tscn` (startup map, zone title “Castle Garden”) |
| `biomes/woodland.tres` | woodland map |
| `biomes/forest.tres` | forest |
| `biomes/fungus_cave.tres` | fungus cave |
| `biomes/bandit_hideout.tres` | bandit hideout |
| `biomes/sunspire_terraces.tres` / `sunken_tombs.tres` | Desert upper / lower levels |
| `biomes/gutterworks.tres` / `drowned_cistern.tres` | Sewers upper / lower levels |
| `biomes/bellows_gallery.tres` / `cinder_deeps.tres` | Fire Forge upper / lower levels |
| `building/guild_house.tres` | guild house inside |
| `building/smith_house.tres` | smith inside |
| `building/trade_house.tres` | trade house inside |
| `building/spar_house.tres` | spar house |
| `building/guild_outpost.tres` | outpost |
| `dungeons/dungeon.tres` / `dungeon_entrance.tres` | dungeon maps |
| `jail.tres` | jail room |

Important `InstanceResource` fields (`instance_resource.gd`):

| Property | Purpose |
|----------|---------|
| `instance_name` | Internal name |
| `map_path` | Path/uid of the `.tscn` to load |
| `load_at_startup` | Preload on world boot |
| `zone_title` | Player-facing name |
| `level_min` / `level_max` | Soft level band (portals show “Lv N+”) |
| `required_wardstone` | Hard entry gate (empty = open) |
| `show_discovery` | Zone banner on enter |

### Portals / Warpers

| Scene | Path | Use |
|-------|------|-----|
| Plain door / spawn warper | `source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn` | Instant warp (`warp_delay_s = 0`) |
| Animated portal | `.../warper/portal/portal.tscn` | Colored swirl + label + dwell |

Scripts:

- `warper.gd` — class `Warper`
- `portal.gd` — class `Portal` (extends `Warper`)

#### Exported properties to set

On every warper/portal:

| Property | Purpose |
|----------|---------|
| `position` | Where the trigger sits in the map |
| `target_instance` | Destination `InstanceResource` (drag a `.tres` from `instance_collection/`) |
| `warper_id` | This map’s id for this warper (used for spawn lookup) |
| `target_id` | Warper id to spawn at **on the destination map** |
| `warp_delay_s` | Dwell before warp (portals default ~0.45; doors leave at 0) |

Portal-only extras:

| Property | Purpose |
|----------|---------|
| `destination_label` | Text under the swirl (e.g. `"Goblin Woodland"`) |
| `portal_color` | Swirl recolor |

Level text like `(Lv 5+)` is appended automatically from `target_instance.level_min` when set.

#### Hub Warpers structure

In `hub.tscn`:

```
Hub
└── Warpers
    ├── Spawn              (warper.tscn — default spawn, warper_id = 0)
    ├── GuildHouse         (warper.tscn → guild_house.tres)
    ├── DarkForestPortal   (portal.tscn)
    ├── BanditHideoutPortal
    ├── WoodlandPortal
    ├── CavePortal
    └── …other portals
```

Example from hub — Woodland portal:

- `destination_label` = `"Goblin Woodland"`
- `target_instance` = `biomes/woodland.tres`
- `warper_id` = `23`
- `target_id` = `23`
- `position` = place in world

### Spawn points

Spawns **are warpers**. `Map.get_spawn_position(warper_id)` looks up `map.warpers[warper_id].global_position`.

Convention:

1. Place a `warper.tscn` named `Spawn` under `Warpers` (or anywhere under the Map).
2. Leave `warper_id = 0` for the default spawn.
3. Login / recall / default entry uses index `0`.
4. When warping, the **source** warper’s `target_id` must match a `warper_id` on the **destination** map.

Hub example: `Warpers/Spawn` at some `position`, `warper_id` default 0.  
Woodland example: node `SpawnPoint` (instance of `warper.tscn`).

### TileMap editing (hub)

In `hub.tscn`:

```
Hub
└── Tiles                    (Node2D folder)
    ├── Ground               (TileMapLayer)
    ├── UpperGround          (TileMapLayer)
    ├── Walls                (TileMapLayer)
    ├── Props                (TileMapLayer)
    └── Props2               (TileMapLayer)
```

Practical tips:

1. Select a layer under `Tiles` (e.g. `Ground`).
2. Paint with the TileMap editor using that layer’s `tile_set` (hub uses `source/common/gameplay/maps/tilesets/castle.tres`).
3. Keep collision / walls on `Walls`; decorative bits on `Props*`.
4. Camera clamps are map exports on the root Map node:  
   `camera_limit_left`, `camera_limit_top`, `camera_limit_right`, `camera_limit_bottom`.

Blank starter: `source/common/gameplay/maps/template/map_template.tscn`  
(`Ground` / `Wall` / `Props` / `Roof` TileMapLayers + a Warper).

### Recipe: add a portal on hub → woodland

1. Open `hub.tscn`.
2. Under `Warpers`, instance `portal.tscn`.
3. Set:
   - `position`
   - `destination_label` = `"Goblin Woodland"`
   - `target_instance` = `source/common/gameplay/maps/instance/instance_collection/biomes/woodland.tres`
   - `warper_id` = unique int on hub
   - `target_id` = matching `warper_id` of the return/spawn warper in woodland
   - `portal_color` = any Color
4. On woodland, ensure a warper/portal exists with that `warper_id` (arrival point) and a return portal with `target_instance` = `overworld.tres`.

---

## 3. Items

### Where items live

`source/common/gameplay/items/`

| Folder / file | Kind |
|---------------|------|
| `consumables/*.tres` | Potions (`ConsumableItem`) |
| `materials/*.tres` | Crafting / drop mats (`MaterialItem`) |
| `currencies/gold.tres` | Currency |
| `gears/**/*.tres` | Armor / rings (`GearItem`) |
| `weapons/**/*.item.tres` | Weapons (`WeaponItem`) |
| `item.gd` | Base class `Item` |
| `consumable_item.gd` / `material_item.gd` / `gear_item.gd` / `weapon_item.gd` | Subclasses |

### Base `Item` fields (Inspector)

| Property | Purpose |
|----------|---------|
| `item_name` | Display name (`StringName`) |
| `item_icon` | Icon texture |
| `description` | Tooltip blurb |
| `holdable` | Can go in the hand |
| `is_currency` | Wallet currency |
| `can_trade` | Player trade |
| `market_minimum_price` | Consignment floor (not shop price) |
| `stack_limit` | `0` = unlimited stack, `1` = non-stackable |
| `tags` | Free-form tags |

Consumable extras (`ConsumableItem`): `heal_amount`, `mana_amount`, buff fields, cooldowns.  
Example: `source/common/gameplay/items/consumables/health_potion.tres`.

Material example: `source/common/gameplay/items/materials/bone.tres`.

### How items get registered

Index file:

`source/common/registry/indexes/items_index.tres`

- `content_name` = `items`
- `scan_path` = `res://source/common/gameplay/items`
- `filters` = `*.tres`, `*.tscn`
- Each entry stores `id`, `slug`, `path`, `hash`
- Saved onto the item as metadata: `metadata/id`, `metadata/slug`

**You do not hand-edit the index.** Use the TinyMMO editor tool:

1. In Godot, open the **TinyMMO** main screen panel (`addons/tinymmo/`).
2. Generate / Update the **items** content index (scans `source/common/gameplay/items`).
3. That rewrites `items_index.tres` and stamps `metadata/id` + `metadata/slug` on each item.

Other indexes in the same folder (same workflow):  
`abilities_index.tres`, `enemy_types_index.tres`, `quests_index.tres`, `sprites_index.tres`.

### Boss-drop relics — do not hand-edit

The ten relics under `source/common/gameplay/items/gears/relics/` and their drop
entries on ten boss `.tres` files are written by `tools/build_boss_relics.gd`.
Edit the `RELICS` table in that script and re-run it; re-running is byte-stable
and never duplicates a drop.

Five colour families, each a **lesser charm** from an early boss and a **greater
sigil** from a late one:

| Family | Lesser | Greater |
|--------|--------|---------|
| Moss | Mossgrown Charm — Goblin Chief | Rotmire Sigil — The Bloated Sovereign |
| Verdant | Sporebloom Charm — The Fungal Heart | Coreblossom Sigil — Mecha-stone Golem |
| Crimson | Bloodbrand Charm — Bandit Captain | Scarabheart Sigil — Ankhemet, the Sand King |
| Indigo | Duskglass Charm — Skeleton Mage | Netherglass Sigil — Necromancer |
| Ember | Emberbrand Charm — Orc Leader | Cinderheart Sigil — Vurthek, the Cinderborn |

Two traps that script exists to avoid, and that any tool touching a `.tres`
shares:

- **Never `ResourceSaver.save()` an existing `.tres` from a headless `-s` run.**
  The uid cache is not loaded, so the text saver finds no id for any path and
  silently drops `uid=` from the file *and from every `ext_resource` in it*.
  Edit as text instead. This is also why `update_items_index.gd` must find these
  relics already stamped — anything it has to stamp, it re-saves.
- **`get_slice('id="', …)` also matches `uid="`.** Search for `' id="'` with the
  leading space, or a drop ends up with `script = ExtResource("uid://…")`.

Gate:

```bash
godot --headless --path . -s tools/verify_boss_relics.gd
```

### Recipe: add a simple new item (material)

1. Duplicate `source/common/gameplay/items/materials/bone.tres`  
   → `source/common/gameplay/items/materials/shiny_pebble.tres`
2. Open it; set `item_name`, `item_icon`, `description`.
3. Run TinyMMO **Generate/Update** for items so `items_index.tres` picks it up and assigns `metadata/id` / `metadata/slug`.
4. (Optional) Add it to a shop’s `entries` (see below).
5. Commit both the `.tres` and the updated `items_index.tres`.

For a potion, duplicate something under `consumables/` instead and set `heal_amount` / etc.

### Breaking items down (salvage)

One table drives the bag's **Break Down** button:
`source/common/gameplay/crafting/resources/salvage_table.tres` (`SalvageTable`).
There is no station and no per-item code — an item is salvageable purely because
it has a row here.

Current spec (29 rows: five weapons per family, but there is no rustic *wand* in
the art pack):

| Weapon family | Breaks into | Herblore to do it | Feeds |
|---|---|---|---|
| Spore | 1 Blightspore | 1 | Weapon Poison |
| Poison | 1 Venom Sac | 20 | Weapon Poison ++ |
| Fairy | 1 Fairy Dust | 25 | Weapon Salve |
| Fire | 1 Ember Ash | 30 | Weapon Ember |
| Bone | **2-4** Bone | 1 | (existing bone economy) |
| Rustic | **1-3** Iron Bar | 1 | (existing smithing) |

Each row is a `SalvageRecipe`:

| Field | Meaning |
|-------|---------|
| `source_item` | the item consumed (one unit per Break Down) |
| `outputs` | `Array[SalvageOutput]` — what one unit yields |
| `required_level` | level in the table's `profession` needed to do it |
| `xp_reward` | profession xp per unit, before perks |

A `SalvageOutput` is `{item, min_amount, max_amount}`. **A fixed yield is just
`min == max`**, so "1 Blightspore" and "1-3 Iron Bars" are one shape and the UI
has one thing to render. Rolls happen **per unit, server-side** in
`item.salvage.gd` — breaking 5 rustic swords is five independent rolls, and the
client only learns the result from the response.

The table's `profession` (currently `&"herblore"`) gates and is paid by every
row, and its Green Thumb xp perk applies exactly as it does to brewing.

To make another weapon family salvageable, add a `SalvageOutput` + a
`SalvageRecipe` sub-resource and append it to `recipes` — nothing else. The bag
button appears for it automatically, on both the client (which reads this table
only to decide whether to offer the button) and the server handler.

Two guards worth knowing: **favorited stacks refuse to break down** (the pin is
treated as "don't touch this", because unlike Drop this is not recoverable), and
the whole yield has to fit in the bag or nothing happens.

### Weapon coatings

A `ConsumableItem` with `coating_kind` set is a weapon coating rather than a
drink:

| Field | Meaning |
|-------|---------|
| `coating_kind` | `&"poison"` / `&"burn"` / `&"heal"` (see `CoatingService`) |
| `coating_potency` | damage per second for poison/burn; **health per landed hit** for heal |
| `coating_hit_duration_s` | how long the DoT burns on each victim. Unused by `heal` |
| `coating_duration_s` | how long the coating stays on YOUR weapon |

Authored set — all four last **5 minutes**:

| Potion | Kind | Effect per hit | Herblore |
|---|---|---|---|
| Weapon Poison | poison | 24 damage over 6s | 70 |
| Weapon Salve | heal | heals you 3 | 76 |
| Weapon Ember | burn | 30 damage over 5s | 82 |
| Weapon Poison ++ | poison | 72 damage over 8s | 88 |

These are **end-game** brews on purpose. Level 65 arrives fast, so when the
whole potion list sat at or below it Herblore had nothing left above halfway;
70/76/82/88 also leaves 89-99 clear for whatever gets brewed next.

Leave a kind empty and the item is not treated as a coating at all (a
half-filled set is an authoring slip, not a weak coating). While a coating
lasts, every hit the drinker lands fires it — hooked **once** in
`CombatHit.try_damage`, so it already works for every weapon type, melee and
projectile alike, with no per-weapon code.

**One at a time.** Drinking any coating while another is running is *refused*,
not merged and not refreshed — including re-drinking the same one. The player
gets "You already have an active potion." from both the bag and the hotbar. A
refused drink does **not** consume the vial. Coatings share the
`&"weapon_coating"` cooldown category, deliberately separate from `&"potion"`,
so coating a weapon can never block an emergency health potion.

That one slot is the **combat draught** slot, and a coating is not the only
thing that can hold it. A `ConsumableItem` with `exclusive_buff = true` — today
just the **Defense Tonic** (`+25 armor for 5m`, Herblore 58) — takes the same
slot through `BuffService`, so a tonic and a coating refuse each other in both
directions. `ConsumableItem.draught_slot_busy()` is the single arbiter; the bag
button, the held sip and `item.consume` all ask it, and each side bails before
the vial is spent. Ordinary buff potions leave `exclusive_buff` false and stack
as they always did.

The coating is runtime-only state on `PlayerResource.weapon_coating` (like
`active_buffs`): it survives an instance change within a session and is gone on
logout. It is **not** persisted, so no save data changes shape.

Brew levels are the one dial to retune if this ladder feels long — they are set
in `alchemy_station.tres` and mirrored in `jobs/herblore.tres` (`recipe_levels`
is positional and must stay parallel to `recipe_items`).

Gates:

```bash
godot --headless --path . --mode=client res://tools/verify_weapon_coatings.tscn
godot --headless --path . --mode=client res://tools/verify_coating_behaviour.tscn
```

### Crafting XP is priced per unit of material

Smithing set the rule and Outfitting now follows it: **a recipe's `xp_reward` is
the tier's per-unit rate times the number of ingredient units it consumes.** The
anvil's rate per bar is the tier's own smelt/arrowhead value (bronze 39, iron 58,
steel 78, mithril 104, adamant 136, runite 195), so a 5-bar chest pays five
times what a 1-bar batch of arrowheads does.

The workbench rates, applied across every cloth and hide armour recipe:

| Tier | Recipe level | XP per unit |
|---|---:|---:|
| Forest cloth / leather | 1 | 36 |
| Cave cloth / leather (incl. Studded) | 5 | 54 |
| Bandit cloth / leather | 10 | 72 |
| Enchanted / Phantom | 15 | 180 |
| Ancient / Sirenic | 30 | 200 |
| Wraithsilk / Runewoven | 45 | 240 |
| Nightglass / Astral | 50 | 290 |

Every ingredient counts as a unit — ore and gem alongside the cloth, the same way
the anvil's Dragon-and-up armour prices its ore + gem + cloth. Each rate is the
material-weighted average of what that band already paid, so a tier's total XP
throughput is unchanged and only the *distribution* inside it moved: a vest that
eats five cloth is now worth more than a hood that eats three, which was not
true before (a Studded Cap used to pay 180 XP per leather against an Apprentice
Robe's 43, for gear of the same mastery tier).

**Tanning and weaving are not rebased.** `hide -> leather` and `fibre -> cloth`
are the "smelting" step: one output, one flat per-craft rate, already
proportionate among themselves. They stay the efficient way to train, exactly as
smelting does for Smithing.

When you add an armour recipe, read the rate off this table and multiply. Do not
eyeball an `xp_reward`. The gate re-derives every row from the same table:

```bash
godot --headless --path . --mode=client res://tools/verify_outfitting_xp.tscn
```

### Ascension gear (mastery 40–90)

Post-Dragon combat ladder. Soft archetypes match the existing metal / leather / cloth split:

| Mastery | Melee (metal) | Archery (leather) | Magic (cloth) |
|--------:|---------------|-------------------|---------------|
| 40 | Basilisk | Wraithsilk | Runewoven |
| 50 | Wyrmguard | Nightglass | Astral |
| 60 | Godsteel | Tempest | Voidsilk |
| 70 | Colossus | Skyrender | Aetherborn |
| 80 | Behemoth | Eclipse | Empyrean |
| 90 | Worldbreaker | Starfall | Primordial |

- Armor + matching weapons live under `gears/{metal,leather,cloth}/` and `weapons/{sword,hammer,bow,wand,book}/`.
- Craft mats: `{set}_ore` / `{set}_gem` / `{set}_cloth` / `{set}_leather` under `materials/`.
- Anvil crafts metal armor + all five weapon types; workbench crafts leather + cloth sets.
- Ascension materials shop (`shops/resources/ascension_shop.tres`) sells **materials only** — finished Ascension gear is never gold-buyable.
- Slayer Shop (`shops/resources/slayer_shop.tres`, NPC `ascension_broker_vael.tres` → Slayer Quartermaster Vael) sells entry-ring gems for **Slayer Points only** (not gold): Low/Med/High/Pristine = **5 / 10 / 20 / 40** pts. Also stocks Wood Gold Small (15 pts) and Wood Gold Medium (30 pts). Crafted Slayer rings are mid-game deterministic gear — keep them **strictly below** Ornate jewelry (level-50 exclusive pool).
- Drop material band (pre-Ascension): a zone drops the craft set matching **its crafting level**, not the set whose name matches its flavour. `Forest` hide/cloth is crafting **1** — Woodland wolf loot — so a post-sewers zone dropping it is a bug, not theming. The ladder in `crafting/resources/workbench.tres`:

  | Crafting | Leather line | Cloth line | Dropped by |
  |---------:|--------------|------------|------------|
  | 1 | `hide_forest` → `leather_forest` | `cloth_forest` | Woodland: wolves, badgers, rats, goblins |
  | 5 | `hide_cave` → `leather_cave` | `cloth_cave` | Fungus + mining caves |
  | 10 | `hide_bandit` → `leather_bandit` | `cloth_bandit` | Bandit Hideout |
  | 15 | `hide_sewer` → `leather_sewer` | `cloth_sewer` | Sewers trash |
  | 15 | `phantom_ore` / `_gem` / `_cloth` | `enchanted_ore` / `_gem` / `_cloth` | Fungal Heart, **DimWood** |
  | 30 | `sirenic_leather` / `_gem` / `_cloth` | — | Cistern Sovereign (combat 200), Ornate Gold chests |

  The `{set}_ore/_gem/_cloth` rows are zone-neutral by name, which is what makes them safe to hang on a second zone. Check `metadata/id` against `registry/indexes/items_index.tres` if a name is ambiguous, and keep crafting-30 sets on genuine late bosses — Orc Leader is combat 70, the Cistern Sovereign is 200.

- Zone-wide kill loot: set `zone_kill_loot` on the biome `InstanceResource` (`biomes/woodland.tres`, `biomes/woodland_east.tres`). Every hostile kill in that instance rolls those drops — new NPCs inherit them automatically. Wood Silver Small ≈1.5% in Goblin Woodland; Wood Silver Medium ≈2% in Woodlands East. Do **not** put shared enemy-type loot for zone rares (types are reused across maps).
- Zone difficulty: set `enemy_health_mult` on the biome `InstanceResource` to scale the max HP of every non-boss hostile in that instance (Bandit Hideout = `0.5`). Use this instead of editing an `EnemyTypeResource` whenever the archetype is shared with another map — the bandit sorcerer/captain also live in the Forest and keep full HP there. `is_boss` mobs ignore it, and mob XP follows the scaled HP, so a softened zone can't become an XP-per-kill outlier.
- Dungeon clear rewards: set `ornate_chest_count` on `DungeonReward` for guaranteed T3 Ornate Gold Chests (item 249). Normal = 1, Hard = 2. Still gated by the 3 daily charges.
- Chest loot tables (`combat/chests/*.tres`): an open grants `rolls_min`..`rolls_max` **distinct** entries drawn from `loot`, so `LootDrop.chance` there is a relative weight, not an independent roll — raising one entry's chance makes it more likely to be the one you get, it does not add a stack on top. `exclusive_loot` (rare jewelry) still rolls independently and is capped by `exclusive_max`.
- Chest opens (`ChestResource.roll_and_grant`): gold goes to the pouch; items stage in `PlayerResource.pending_chest_loot` and open the **Chest Loot** claim UI (`menus/chest_loot/`). Players Take (bag, 28-slot capped) or Bank stacks; logout auto-banks leftovers. Do not grant chest items with uncapped `Inventory.add_item` into the bag.
- Dungeon difficulty (per `DungeonResource`): `normal_health_mult` / `normal_damage_mult` always apply in-run; `boss_health_mult` / `boss_damage_mult` stack on bosses only; Hard uses absolute `hard_*` mults. Dark Cave / Fungus Domain are tuned for Runite+Fire — overworld copies of those mobs are unchanged.
- Optional dungeon table: `dungeon/ascension_reward.tres` (attach as `hard_reward` on a `DungeonResource`).
- Regenerator / wire / verify: `tools/generate_ascension_gear.py`, `tools/wire_ascension_gear.gd`, `tools/verify_ascension_gear.gd`.

---

## 4. Dialogue & shops

### Dialogue

There are **no separate dialogue `.tres` files**.  
Dialogue is a `DialogueInteraction` sub-resource on the NPC’s `interactions` array.

| Script | `source/common/gameplay/characters/npc/interactions/dialogue_interaction.gd` |
|--------|-----------------------------------------------------------------------------|
| Properties | `lines: Array[String]` (one string = one page), `label_override` (button text; empty → `"Talk"`) |

Example pattern (from `starter_merchant.tres` / `hermit.tres`):

1. Open the NPC `.tres`.
2. Add element to `interactions` → New `DialogueInteraction`.
3. Fill `lines` with pages.
4. Set `label_override` if you want e.g. `"Talk about yourself"`.

Greeting text is **not** dialogue pages — it is `NPCResource.greeting`.

### Shops

| What | Path |
|------|------|
| Shop script | `source/common/gameplay/shops/shop_resource.gd` |
| Entry script | `source/common/gameplay/shops/shop_entry.gd` |
| Trade/buyback script | `source/common/gameplay/shops/shop_trade.gd` |
| Shop catalogs | `source/common/gameplay/shops/resources/*.tres` |

Existing shops include:  
`start_shop.tres`, `miras_apothecary.tres`, `hermit_exchange.tres`, `bone_shop.tres`, `spore_shop.tres`, `sunsteel_shop.tres`, `fairy_shop.tres`, `fire_shop.tres`, `poison_shop.tres`, `rustic_shop.tres`, `lost_soul_shop.tres`, `quarry_counter.tres`, …

#### `ShopResource` fields

| Property | Purpose |
|----------|---------|
| `shop_name` | UI title |
| `currency_item` | Default currency (empty = gold) |
| `entries` | `Array[ShopEntry]` — what the vendor **sells** |
| `accepted_trades` | `Array[ShopTrade]` — what the vendor **buys** / barters |

#### `ShopEntry` fields

| Property | Purpose |
|----------|---------|
| `item` | Item resource to sell |
| `price` | Cost |
| `currency_item` | Optional per-entry currency override |

#### `ShopTrade` fields (sell-to-vendor / barter)

| Property | Purpose |
|----------|---------|
| `item` | What the player gives |
| `amount` | Bundle size (default 1) |
| `payout` | Currency paid to the player |
| `currency_item` | Optional; empty = gold |

### Recipe: new shop + attach to NPC

1. Duplicate `source/common/gameplay/shops/resources/start_shop.tres`  
   → `source/common/gameplay/shops/resources/my_shop.tres`
2. Set `shop_name`.
3. Clear/rebuild `entries`: each entry needs `item` + `price`.
4. Optionally set `accepted_trades` for buybacks.
5. On your NPC `.tres`, ensure a `ShopInteraction` has `shop` = `my_shop.tres`.
6. Place the NPC on a map (server registers the shop from that map at boot).

Shops are **not** registered through `items_index` / a shop index.  
The server finds them via the NPC on the current map (`giver_key` from the NPC `.tres` filename).

### Recipe: quest talker (quick)

1. Put quest defs in `source/common/gameplay/quests/resources/*.tres`.
2. On the NPC, add `QuestInteraction` with `quests` listing those resources.
3. Regenerate `quests_index.tres` via TinyMMO if the quest is new.
4. Keep the NPC as a **file** `.tres` (needed for giver slug).

---

## 5. High-tier gathering nodes & custom smelting

Everything below is authored **in the Inspector on a `.tres`** — there is no new
scene work. The node scene, the shader and the particle emitter are all built at
runtime from these fields, so a new tier is a resource, not a prefab.

### 5.1 Node hierarchy — what you do and do NOT build

`MineableNode` (`source/common/gameplay/maps/components/mineable_node.tscn`) is
placed in the map and pointed at a `MineableNodeResource` via its `data` export.
That is the whole setup. Its children are:

| Child | Who owns it | Notes |
|-------|-------------|-------|
| `Sprite2D` | script | texture, scale, shimmer material, idle frames, flash + recoil all applied from `data` |
| `CollisionShape2D` | script | resized from the texture by `_layout_from_texture()` |
| `NameLabel`, `VisualState` | script | repositioned from the texture height |
| *(particles)* | script | `CPUParticles2D` is **created per swing and freed**; do not add one in the editor |

> **Do not** add an `AnimatedSprite2D`, a `ShaderMaterial` on the sprite, or a
> `GPUParticles2D` by hand. The script drives `Sprite2D.texture` directly for the
> depleted swap, and an `AnimationPlayer` or editor-set material fights it — the
> node ends up frozen on one frame or stuck grey after it refills.

### 5.2 Idle frames (sprite animation)

`texture` is frame 0; `idle_frames` are frames 1..n, cycled at
`idle_frame_seconds`. A depleted node freezes on its stump art.

* Frames **must be the same size as `texture`** or the node jumps every cycle.
* Generate them with `python tools/build_ore_vein_idle_frames.py`, which derives
  each frame from the shipped vein sprite so registration is exact. Hand-drawn
  frames are fine, but check the silhouette pixel-for-pixel.
* 2 frames + `0.5s` reads as a slow breath; 3 frames + `0.25s` reads as energy.

### 5.3 Shimmer shader

Set `shimmer_strength > 0` and the script builds the `ShaderMaterial` itself from
`shimmer.gdshader` — leave the sprite's material **empty** in the editor.

| Field | Guidance |
|-------|----------|
| `shimmer_strength` | `0.3`–`0.6`. Past `~0.8` pale art blows out to white |
| `shimmer_tint` | the metal's highlight, not its body colour |
| `shimmer_speed` | `0.7` slow gleam → `1.3` restless |
| `shimmer_iridescent` | hue-cycles as well; Astralite only, it is loud |

`Item.shimmer_*` mirrors these for the icon / in-hand sprite, so a shimmering
vein and its bar are set up the same way.

### 5.4 Strike feedback (flash, recoil, particles)

Fired from `ClientState` only when a swing actually connects, so a cooldown or
wrong-tool reply never plays.

| Field | Guidance |
|-------|----------|
| `hit_flash_strength` | how much **brighter**, as a fraction: `0.5` peaks at 1.5x. `0.35` on pale art (Celestial), `0.55` on near-black (Obsidian) |
| `hit_flash_color` | the flash's hue; white for a plain impact, tinted toward the metal to feel "woken up". Alpha ignored |
| `hit_flash_seconds` | keep `≤ 0.2` — longer reads as a glow, and swings land every ~0.3s |
| `hit_recoil_pixels` | `2`–`4`. Past ~6 the rock wobbles instead of being struck |
| `chop_fx_style` | `drift_up`, `sparkle`, `spark_side`, `starburst` |
| `chop_fx_amount` | keep low; this fires on **every** hit |

Flash and particles are independent — either can be used alone.

> The flash is an **overbright**: the sprite is driven toward
> `hit_flash_color * (1 + hit_flash_strength)`. `modulate` multiplies, so a
> flash authored at or below white can only darken — and a white flash on an
> unmodulated (white) sprite is a silent no-op. That is not a knob you can turn
> off by choosing a dim colour; set `hit_flash_strength` to `0` instead.

### 5.5 Custom smelting (`SmeltingRecipe`)

Post-Runite metals do not use `N x Coal + 1 x Ore`. Author them in
`furnace.tres` as `SmeltingRecipe` (not `CraftingRecipe`); the station holds a
mixed list and the server branches on the type.

| Field | Meaning |
|-------|---------|
| `ingredients` | consumed every craft — ore, additive, and the **previous tier's bar** |
| `catalysts` | must be **held**, consumed only on a roll |
| `catalyst_consume_chance` | per-unit erosion. `0.04` ships; `0.0` = a permanent tool |
| `flavor` | one line shown above the material list |

**Rules that bite:**

* Availability checks and the crafting UI read `required_inputs()`, never
  `ingredients`. A new kind of input must be added there or it will be invisible
  in the UI and ungated on the client.
* Do **not** list the same item as both an ingredient and a catalyst — each is
  counted independently, so the craft can pass the check and then overdraw.
* Every additive needs a source. The four shipped ones are a `secondary_ore`
  catch on their own vein at `secondary_chance = 0.34`, which matches the 2 ore :
  1 additive the recipes ask for. Change one and change the other.
* The **Everburning Crucible** is an anvil recipe at Smithing 66 costing
  **10x Runite Bar** — deliberately a mid-tier sink, so Runite mining stays
  worth doing after a player is smelting Astralite. At `catalyst_consume_chance
  = 0.04` a crucible survives ~25 smelts, which amortises to **0.4 Runite Bar
  per high-tier bar**; because each tier alloys in the bar below it, an
  Astralite Bar transitively costs ~2.6 Runite Bars. Retuning either the recipe
  or the erosion rate moves that number — `verify_high_ore_tiers.gd` prints it
  on every run so a change is visible rather than silent.
* Crafting the Crucible must stay a net LOSS against vendoring its inputs
  (1000g of bars in, 400g out). The gate fails if that ever inverts, because a
  craftable item worth more than its parts is a gold printer.
* Perk / outfit refunds deliberately do not apply to catalysts.

### 5.6 Regenerating the art

| Script | Produces |
|--------|----------|
| `tools/build_ore_vein_idle_frames.py` | `vein_<tier>_f1/f2.png` idle frames |
| `tools/build_high_tier_tool_art.py` | `high_tier/tools_<tier>.png` + the Dragon rod |
| `tools/build_smelting_catalysts.py` | the five catalyst / additive icons |

**Tool silhouettes are fixed per tool TYPE, not per tier.** The pickaxe, sickle
and axe shapes in `build_high_tier_tool_art.py` are ASCII pixel grids shared by
all four tiers and matched to the Bronze–Runite shapes players already read. A
tier is identified by its ramp, a 2–3 pixel ornament inset inside the head, and
two accent bands on the haft — never by changing the head's outline.

> An earlier pass gave every tier its own head geometry. It was rejected: the
> tiers were distinguishable and the TOOL TYPE was not, which is the only thing
> the silhouette has to carry. If you add a tier, add a ramp and a motif — do
> **not** add a shape. Prove it with the silhouette band of
> `render_high_ore_tiers.tscn`, which strips the colour out.

Sheets are laid out on the same `192x112` grid as the base weapon sheets, so
tool items keep the canonical regions — `Rect2(0, 48, 16, 32)` pickaxe,
`Rect2(32, 48, 16, 32)` sickle, `Rect2(112, 48, 16, 32)` axe. `weapon.gd` drives
the in-hand sprite from `item_icon`, so repointing the AtlasTexture updates the
player model and the UI together.

Two traps when repointing a tool's texture:

* Drop the `uid=` from the `ext_resource` line. It resolves ahead of `path`, so
  leaving it silently keeps loading the old sheet.
* The shipped Bronze–Runite `axe_*` items point at a cell that is drawn as a
  **hoe**, not an axe. The high tiers deliberately diverge from that reference
  and draw a real weighted bit; the silhouette sheet labels the row so the
  mismatch does not read as a regression.

`build_higher_ore_tiers.py` still owns tier ARMOUR by recolouring the Runite
set — that is correct there, where the silhouette is shared anyway. Do not route
a tool through it.

### 5.7 Gates

```
godot --headless --path . -s tools/verify_high_ore_tiers.gd      # bad=0
godot --path . --mode=client res://tools/check_ore_alcove.tscn   # ore alcove OK
godot --path . --mode=client res://tools/verify_vein_fx.tscn     # VEIN_FX bad=0
godot --path . --mode=client res://tools/render_shimmer_proof.tscn
godot --path . --mode=client res://tools/render_high_ore_tiers.tscn
```

`verify_vein_fx.tscn` is a RUNTIME gate: it instances a real `MineableNode`,
swings at it, and asserts the flash actually changes the sprite, the recoil
settles back to rest, and the one-shot emitters free themselves. It stretches
`hit_flash_seconds` on a copy of the resource first, because at the shipped
0.12s a slow frame can step over the whole strike and observe nothing.

> It earned its keep immediately: Celestial was authored with a white flash on a
> white base, and `modulate` multiplies, so `WHITE.lerp(WHITE, t)` did nothing.
> The flash is now an **overbright** — `hit_flash_color * (1 + strength)` — so a
> white flash brightens instead of being a no-op. A flash authored at or below
> white can only ever darken a sprite.

`render_high_ore_tiers.tscn` writes two sheets: the tier contact sheet, and
`previews/tool-legibility.png` — rejected vs revised tool art plus a
colour-stripped silhouette band against the Bronze reference.

#### Blocking rule: merge order

`verify_high_ore_tiers.gd` reports an `XP_ORDER` section.

| Counter | Must be | Meaning |
|---------|---------|---------|
| `new_tier_inversions` | `0` always | a higher new tier pays less than a lower one — an authoring bug |
| `cross_ladder_inversions` | `1` for now | the new tiers are costed on the rescaled curve; the old ladder is not |

**As of 2026-09-01 `rework/skill-xp-rates` is still NOT merged into `main`** —
`main` pays a Runite Bar 254 XP against this branch's Dragon Bar at 35. Merging
this branch first makes the new tier a 7x XP *downgrade*. Git will not catch it:
the branches touch different lines and merge cleanly in either order.

**Do not merge this branch while that check fails.** `--is-ancestor` exits `0`
when the rework has landed and `1` when it has not, so it drops straight into
CI as a hard gate:

```bash
git fetch origin
if git merge-base --is-ancestor origin/rework/skill-xp-rates origin/main; then
  echo "rework landed - safe to merge content/high-ore-tiers"
else
  echo "BLOCKED: merge rework/skill-xp-rates first" >&2
  exit 1
fi
```

Once it passes, rebase and re-run the gate: `cross_ladder_inversions` must drop
to `0`. If it does not, the rescale and these recipes have diverged and the
factor needs recomputing — do not merge on the assumption that it will settle.

> The `steel_bar` (lv15, was 78 XP) vs `silver_bar` (lv10, 98 XP) inversion that
> this gate also surfaced was pre-existing on `main` and is patched here: steel
> now pays 105, between silver and gold. **That patch touches a line
> `rework/skill-xp-rates` also rewrites** (to 10, as part of its full rescale),
> so expect a conflict on `furnace.tres` when the two meet — take the rework's
> value, which fixes the inversion its own way.

---

## 6. Cave maps: layers, collision and the Starfall Mining Cave

`starfall_mining_cave.tscn` is **generated**. Hand edits are lost the next time
`tools/build_starfall_mining_cave.gd` runs — change the generator, then re-run
and re-verify. Same rule as the biome maps in §2.

```
godot --headless --path . -s tools/build_starfall_mining_cave.gd
godot --path . --mode=client res://tools/verify_starfall_cave.tscn   # bad=0
godot --headless --path . -s tools/verify_warp_links.gd              # VERIFY_PASS
```

### 6.1 Layer order — what each one is for

Everything hangs off a `Tiles` Node2D with `y_sort_enabled`. Order and
`z_index` are the whole "no overlap, no bleeding" story:

| Node | z_index | y_sort | Carries collision | Purpose |
|------|---------|--------|-------------------|---------|
| `Tiles/Ground` | `-3` | no | no | floor, **and a dark fill under every void cell** |
| `Tiles/GroundDetail` | `-2` | no | no | per-alcove floor material, autotiled |
| `Tiles/Walls` | default | **yes** | **yes** | rim + cliff face; the only solid layer |
| `Tiles/Props` | default | **yes** | some | boulders and formations |
| `Tiles/Ceiling` | `200` | no | **never** | overhang drawn ABOVE the player |
| `MineableNodes` | — | **yes** | per-node | ore veins |
| `ReplicatedPropsContainer` | — | **yes** | per-node | NPCs |

Rules that produce the clean result:

* **Y-sort on the map root, `Tiles`, `Walls`, `Props`, `MineableNodes` and
  `ReplicatedPropsContainer`.** A player must sort against a wall and a vein by
  their feet. `Ground`/`GroundDetail`/`Ceiling` are flat and use `z_index`
  instead — y-sorting a full-map floor layer is wasted sorting.
* **Ground is painted under the VOID as well as the floor.** The rim corner art
  is only ~70% opaque; without a dark fill behind it the corners punch through
  to the background and read as flat grey squares. This is the single most
  common cause of "tile bleeding" in this pack.
* **The Ceiling layer must never carry collision.** It draws at `z_index 200`,
  above the player, so a solid tile there is an invisible wall. The audit fails
  the build if any tile on it has a collision polygon.

### 6.2 Collision is a property of the TILESET, not the layer

In `rpgw_caves_tileset.tres` exactly one block of atlas cells — `(0,0)` to
`(9,8)`, the rim bank — carries collision polygons. 82 tiles. Everything else in
the 2448-tile sheet is decorative and walkable.

That has two consequences worth internalising:

* A wall drawn from anywhere else in the sheet **looks like rock and walks like
  floor.** `MapKit.paint_rim` only ever paints from the rim bank, which is why
  the generator's walkability model and the physics engine agree.
* Collision sits at the **visual base** of the wall, not its top edge. The south
  cliff face is three tiles tall in the art, so `paint_rim` blocks the void cell
  plus the **two rows beneath it** (`face_rows = 2`). Skip that and players walk
  into the painted rock face.

`verify_starfall_cave.gd` re-derives solidity from
`TileData.get_collision_polygons_count(0)` on the built scene rather than
trusting any of the above, then floods from the entrance. It refuses a vein
inside rock, an unreachable pocket, a floating wall cell with no wall neighbour,
a walkable cell with no ground under it, and a vein whose only approach is a
1-tile pinch.

### 6.3 Zonal layout

Six rooms, joined by ~5-tile corridors so two players pass without shoving each
other into the rock:

| Room | Tier | Floor material | Light |
|------|------|----------------|-------|
| Lantern Landing | — | earth | warm, campfire + grove portal |
| The Crossing | — | grey stone | neutral; every alcove hangs off it |
| Emberthroat | Dragon, Mining 65 | earth | hot orange |
| Geode Hollow | Obsidian, Mining 70 | grey stone | violet |
| The Skylight | Celestial, Mining 80 | mossy | pale gold, brightest room |
| Astral Vault | Astralite, Mining 90 | grey stone | cold violet, behind a throat |

> **What actually separates zones is the FLOOR and the LIGHT, not the rock.**
> Corridors wide enough for multiplayer inevitably read as openings at map
> scale, so thinning the rock between rooms does not buy distinctness. Each
> alcove gets its own autotiled ground material via `MapKit.paint_corner_patch`.
> An early pass painted those patches with the *same* tiles as the base ground —
> the layer filled with 800+ cells and nothing changed on screen.

### 6.4 Vein placement rules

Veins are placed by the generator, never by hand. `ZONES` in the generator is
the authoring surface: centre, radius, count, colour, floor material.

* A vein goes on a floor cell that **touches rock** (`MapKit.edge_cells`) — that
  is where an embedded seam belongs.
* `ore_r` must be **>= the chamber radius**, because that touching-rock ring
  lives at the chamber wall. Set it lower and the search only sees the open
  middle of the room and silently places nothing.
* Minimum spacing is `MapKit.scatter(..., spacing: 2)`. `spacing` is a Chebyshev
  +/-N box, so 2 already guarantees 3 tiles / 96px — comfortably past the 72px
  (1.5x `HarvestController.GATHER_RANGE`) a click needs to resolve to one vein.
  3 reserves a 7x7 and starves the smaller chambers.
* Every vein needs **>= 3 open sides**, or two players block each other on it.

### 6.5 Zone transition

Bidirectional, and both halves are generated:

| Side | Node | warper_id | target_id |
|------|------|-----------|-----------|
| Starfall Grove | `CaveMouth` (arrival) | 35 | — |
| Starfall Grove | `MiningCavePortal` | 134 | 34 |
| Mining Cave | `Entrance` (arrival) | 34 | — |
| Mining Cave | `GrovePortal` | 135 | 35 |

The grove half lives in `tools/build_starfall_grove.gd` and sits on the
**Unquarried Shelf**, the paved, lit, road-connected clearing that map has
always reserved for the high ore tiers. `verify_warp_links.gd` proves both
`(target_instance, target_id)` pairs resolve to a real warper in the
destination map — a link pointing at a missing id used to drop players into the
top-left border wall.

Portals fade the screen and reposition through the shared
`warper/portal.tscn`; there is no per-map transition code to write.

---

## 7. Ammunition procs (high-tier arrows)

Four arrow tiers carry an on-hit effect. The chain is
**1 bar -> 10 arrowheads** (Smithing, anvil) then
**10 shafts + 10 arrowheads -> 10 arrows** (Fletching, bench).

```
godot --path . --mode=client res://tools/verify_high_tier_arrows.tscn  # bad=0
godot --path . --mode=client res://tools/verify_ammo_equip.tscn
```

### 7.1 Authoring a proc

Four fields on the `AmmoItem` .tres. Leave `proc_chance` at 0 and the arrow is
an ordinary one, which is every tier up to Runite.

| Field | Meaning |
|-------|---------|
| `proc_chance` | 0-1, rolled per landed **ranged** hit |
| `effect_type` | must be one of the `AmmoProcService.EFFECT_*` constants |
| `proc_magnitude` | per-effect: DPS, a 0-1 fraction, or flat splash damage |
| `proc_duration_s` | duration effects only; ignored by instant ones |

| Tier | Chance | Effect | Magnitude | Splat |
|------|--------|--------|-----------|-------|
| Dragon | 15% | `thermal_burn` | 8 dps / 4s, +50% of that as armour shred | fiery orange |
| Obsidian | 12% | `life_siphon` | 0.35 of the hit, healed to the shooter | crimson |
| Celestial | 20% | `holy_splash` | 14 damage in 72px, victim excluded | radiant gold |
| Astralite | 10% | `gravity_slow` | 0.35 move, half that attack speed, 3s | electric cyan |

> **A half-authored proc is an authoring slip, not a weak arrow.** A chance with
> no effect, or an effect with no chance, ships as a plain arrow and nothing
> complains. Worse, an `effect_type` TYPO is dispatched to `_: pass` — the arrow
> looks like it has a proc, rolls it, and does nothing. Both fail the gate.

### 7.2 Where the proc runs

`AmmoProcService.on_hit` is called from `CombatHit.try_damage`, beside
`CoatingService.on_hit` — the one place every melee arc and projectile resolves
a hit. That means no per-weapon or per-ability code, and a proc can never be
reached by a path that skipped the target rules.

* **`randf()` runs on the server**, against a chance read from the item on disk.
  The client does not roll, cannot report a proc and cannot re-roll a miss; it
  learns a proc happened only from the damage payload that comes back.
* **Only bow shots proc.** The gate is `damage_type == DAMAGE_RANGED` — melee
  sends physical, wands send magic. Without it a quiver would proc off swords.
* **The splash re-enters `try_damage`** so each splash target gets the full zone
  and allegiance rules (a burst next to a guildmate must not hit them). That
  makes the service re-entrant, so a static `_resolving` flag stops a splash
  procing a splash: at 20% in a packed camp that is an exponential chain, and it
  would surface as a server hang rather than as anything a player could report.

### 7.3 Slows and shreds do NOT go through BuffService

`BuffService` stores its entries on `PlayerResource`, so it can only touch a
Player. Arrows are mostly shot at NPCs, and a slow that silently does nothing to
a mob is a bug that looks like balance.

`TimedDebuff` attaches to any `Character` as a child node, the same shape as
`DamageOverTime`. Two of the three things it weakens are not stats at all on an
NPC — `HostileNpc.move_speed` and `attack_cooldown` are plain fields, so they
are scaled and restored directly; ARMOR is a real stat and goes through
`modify_stat`. It records **what it actually applied** and gives back exactly
that: reverting a change that was never applied silently drains the victim's
stat block. Re-applying refreshes the clock and keeps the original magnitudes,
so arrow spam cannot stack a mob to zero armour.

### 7.4 Hit splat colours

Server and client are joined by a **string**, not a symbol:
`AmmoProcService.SPLAT_*` must appear verbatim in
`FloatingDamageNumber._color()`. Rename one side and it compiles fine while the
splat silently falls back to default orange — the gate checks for exactly this.

Effect identity is matched **before** the heal colour, so an Obsidian siphon
pays out in crimson instead of reading as a generic green heal.

### 7.5 XP scale and the positional mirrors

Arrowhead and arrow XP are on the **post-#388 scale**, like everything else on
this branch: Smithing 28/31/36/42 at levels 68/72/80/88, Fletching
270/320/380/450 at 80/84/88/92. Ranged Attack stays on the established +1 per
tier ladder (17/18/19/20) — the power jump is the PROC, not an inflated stat,
which is what keeps these from disrupting the existing arrow ladder.

`jobs/smithing.tres` and `jobs/fletching.tres` mirror these recipes, and
`recipe_items` / `recipe_levels` are read **positionally**. A length drift does
not error — it silently mislabels every recipe after the insertion point. The
gate checks both lists are parallel. Arrowheads are `MaterialItem`s so they are
safe in `recipe_items`; only weapon/tool items must use
`recipe_deferred_paths` (see the cycle warning in §5).

---

## 8. Deploy reminder (important)

World/server content is **authoritative**. Editing maps, NPCs, shops, items, or portals in git does nothing live until the VPS pulls and restarts.

After you push content changes:

```bash
# On the VPS (see deploy/README.md)
cd /opt/arkenelle && git pull
sudo -u arkenelle godot --headless --path /opt/arkenelle --import
sudo systemctl restart arkenelle-master arkenelle-gateway arkenelle-world
```

| Change type | Needs VPS pull + restart | Needs client rebuild/redistribute |
|-------------|--------------------------|-----------------------------------|
| Map layout, warpers, spawn, NPC placement | Yes | Only if new client-visible assets (sprites, new scenes clients must load) |
| NPC `.tres` text / shop prices / interactions | Yes | Usually no (shared `source/common` — still ship client if you distribute packed builds) |
| New item icons / sprite frames / portal art | Yes | **Yes** — rebuild/export the client |
| Pure server logic under `source/server/` | Yes | No |

Client export note: `deploy/README.md` — export the Windows client from Godot after client-visible asset changes; servers already run headless from source on the VPS.

---

## Quick checklist cheat sheet

**New talk/shop NPC on hub**

1. Create `npcs/my_npc.tres` (`npc_name`, `skin`, `greeting`, `interactions`)
2. Optional: create `shops/resources/my_shop.tres` and link via `ShopInteraction.shop`
3. Open `maps/maps/hub.tscn` → `NPCs` → instance `npc.tscn` → set `npc_resource` + `position`
4. Commit, push, VPS `git pull` + restart world

**New portal**

1. Instance `portal.tscn` under the map’s `Warpers`
2. Set `target_instance`, `destination_label`, `position`, `warper_id`, `target_id`
3. Mirror arrival warper id on the destination map
4. Deploy server

**New item**

1. Add `.tres` under `items/...`
2. TinyMMO Generate → updates `registry/indexes/items_index.tres`
3. Optionally add to a shop `entries`
4. Deploy server; rebuild client if new icons/assets
