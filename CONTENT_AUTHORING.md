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

The stair portals joining each surface map to its two sub-levels are appended by
`tools/add_biome_stairs.gd`. It inserts nodes as text and never touches a
`tile_map_data` line, so the surface maps' art is untouched; re-running it is a
no-op once the stairs exist.

Gates to run after any change here:

```bash
godot --headless --path . -s tools/build_biome_levels.gd && godot --headless --path . -s tools/audit_biome_collision.gd && godot --headless --path . -s tools/verify_biome_levels.gd && godot --headless --path . -s tools/verify_stub_biomes.gd
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

### Ascension gear (mastery 40–90)

Post-Dragon combat ladder. Soft archetypes match the existing metal / leather / cloth split:

| Mastery | Melee (metal) | Archery (leather) | Magic (cloth) |
|--------:|---------------|-------------------|---------------|
| 40 | Basilisk | Wraithsilk | Runewoven |
| 50 | Wyrmguard | Nightglass | Astral |
| 60 | Colossus | Tempest | Voidsilk |
| 70 | Godsteel | Skyrender | Aetherborn |
| 80 | Behemoth | Eclipse | Empyrean |
| 90 | Worldbreaker | Starfall | Primordial |

- Armor + matching weapons live under `gears/{metal,leather,cloth}/` and `weapons/{sword,hammer,bow,wand,book}/`.
- Craft mats: `{set}_ore` / `{set}_gem` / `{set}_cloth` / `{set}_leather` under `materials/`.
- Anvil crafts metal armor + all five weapon types; workbench crafts leather + cloth sets.
- Hub NPC **Ascension Broker Vael** sells mats / jewelry (`shops/resources/ascension_shop.tres`).
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

## 5. Deploy reminder (important)

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
