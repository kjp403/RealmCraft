extends RefCounted
## Scene emitter for multi-level biome maps.
##
## `mapkit.gd` decides *where* floor and wall go. This file turns the finished
## layers plus a population list into a `.tscn`. It exists because the biome
## sub-levels need three things `build_stub_biomes.gd` never had to write:
## hostile NPCs with baked replication ids, friendly NPCs, and more than one
## exit warper per map.
##
## Everything is dict-driven so a level definition reads as content, not as
## string formatting.

class_name LevelKit

const MAP_SCRIPT := "res://source/common/gameplay/maps/map.gd"
const MAP_UID := "uid://7mbux4mybta0"
const RP_SCRIPT := "res://source/common/network/sync/replicated_props.gd"
const RP_UID := "uid://wq8klpndipnu"
const WARPER := "res://source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn"
const WARPER_UID := "uid://b2ckixon7ryh6"
const PORTAL := "res://source/common/gameplay/maps/components/interaction_areas/warper/portal/portal.tscn"
const PORTAL_UID := "uid://0m5eq6iylq26"
const HOSTILE := "res://source/common/gameplay/characters/npc/hostile_npc.tscn"
const HOSTILE_UID := "uid://v32667qwpj2l"
const NPC := "res://source/common/gameplay/characters/npc/npc.tscn"
const NPC_UID := "uid://dbrernsyt26qh"
const CAMP := "res://source/common/gameplay/lighting/campfire.tscn"
const GLOW := "res://source/common/gameplay/lighting/light_radial.tres"
const CRITTER := "res://source/common/gameplay/props/ambient_critter.tscn"
const DECO := "res://source/common/gameplay/props/animated_deco.tscn"
const CRITTER_FRAMES := "res://source/common/gameplay/characters/sprite_frames/%s.tres"
const DECO_FRAMES := "res://source/common/gameplay/props/sprite_frames/%s.tres"

## Layer order in the emitted scene. `Overlay` sits above `Props` for detail that
## must draw over a prop it shares a cell with; `Walls` keeps the collision.
const LAYER_ORDER: Array[String] = ["Ground", "Walls", "Props", "Overlay"]


# --- Small geometry helpers --------------------------------------------------

static func tile_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 16 + 8, cell.y * 16 + 8)


## Nearest cell in `mask` to `wanted`. Used to snap authored landmark positions
## onto whatever the carver actually produced.
static func pick_open(mask: Dictionary, wanted: Vector2i) -> Vector2i:
	if mask.has(wanted):
		return wanted
	var best := wanted
	var best_d: int = 1 << 30
	for cell: Vector2i in mask.keys():
		var d: int = (cell - wanted).length_squared()
		if d < best_d:
			best_d = d
			best = cell
	return best


## Snap a whole list of authored spots onto open floor, refusing to reuse a cell
## so two landmarks never collapse onto each other.
static func pick_spread(mask: Dictionary, wanted: Array, min_gap: int = 3) -> Array[Vector2i]:
	var used: Dictionary = {}
	var out: Array[Vector2i] = []
	for w: Vector2i in wanted:
		var pool: Dictionary = {}
		for cell: Vector2i in mask.keys():
			if not used.has(cell):
				pool[cell] = true
		var cell := pick_open(pool, w)
		out.append(cell)
		for oy in range(-min_gap, min_gap + 1):
			for ox in range(-min_gap, min_gap + 1):
				used[cell + Vector2i(ox, oy)] = true
	return out


static func b64(layer: TileMapLayer) -> String:
	return Marshalls.raw_to_base64(layer.tile_map_data)


static func void_of(floor_mask: Dictionary, w: int, h: int) -> Dictionary:
	var out: Dictionary = {}
	for y in h:
		for x in w:
			var cell := Vector2i(x, y)
			if not floor_mask.has(cell):
				out[cell] = true
	return out


static func walkable(floor_mask: Dictionary, blocked: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in floor_mask.keys():
		if not blocked.has(cell):
			out[cell] = true
	return out


## Void cells with no floor anywhere in their 8-neighbourhood — the deep mass of
## rock, safe to restyle without disturbing the border tiles `paint_rim` chose.
static func deep_void(void_mask: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in void_mask.keys():
		var interior := true
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if not void_mask.has(cell + Vector2i(ox, oy)):
					interior = false
					break
			if not interior:
				break
		if interior:
			out.append(cell)
	return out


static func keepout(spots: Array, radius: int) -> Dictionary:
	var out: Dictionary = {}
	for spot: Vector2i in spots:
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				out[spot + Vector2i(ox, oy)] = true
	return out


# --- Painting ---------------------------------------------------------------

static func rim_spec(
	source: int,
	fill: Array,
	n: Array,
	s: Array,
	w: Array,
	e: Array,
	nw: Vector2i,
	ne: Vector2i,
	sw: Vector2i,
	se: Vector2i,
	face_rows: int = 0
) -> MapKit.RimSpec:
	var spec := MapKit.RimSpec.new()
	spec.source = source
	spec.fill.assign(fill)
	spec.n.assign(n)
	spec.s.assign(s)
	spec.w.assign(w)
	spec.e.assign(e)
	spec.nw = nw
	spec.ne = ne
	spec.sw = sw
	spec.se = se
	spec.face_rows = face_rows
	return spec


## Blocking scatter: stamps multi-cell prop rects and records the cells as solid
## so the caller can subtract them from the walkable set.
static func scatter_props(
	props: TileMapLayer,
	source: int,
	cells: Array,
	rects: Array,
	density: float,
	spacing: int,
	seed_value: int,
	allowed: Dictionary,
	solid: Dictionary
) -> int:
	if rects.is_empty():
		return 0
	var placed_count: int = 0
	for cell in MapKit.scatter(cells, density, spacing, seed_value):
		if not allowed.has(cell):
			continue
		var r: Array = rects[MapKit.hash2(cell.x, cell.y, seed_value + 1) % rects.size()]
		var cluster := MapKit.rect_cluster(r[0], r[1], r[2], r[3])
		var placed := MapKit.stamp_cluster(props, source, cluster, cell, allowed, _bounds_of(props))
		for c: Vector2i in placed:
			allowed.erase(c)
			solid[c] = true
		if not placed.is_empty():
			placed_count += 1
	return placed_count


## Non-blocking ground detail. Never overwrites an existing prop cell.
static func scatter_flat(
	layer: TileMapLayer,
	source: int,
	cells: Array,
	tiles: Array,
	density: float,
	spacing: int,
	seed_value: int,
	taken: Dictionary
) -> int:
	if tiles.is_empty():
		return 0
	var n: int = 0
	for cell in MapKit.scatter(cells, density, spacing, seed_value):
		if taken.has(cell) or layer.get_cell_source_id(cell) >= 0:
			continue
		var t: Vector2i = tiles[MapKit.hash2(cell.x, cell.y, seed_value + 2) % tiles.size()]
		layer.set_cell(cell, source, t)
		n += 1
	return n


## Place one authored landmark rect with its *base* on `anchor`, so a tall prop
## (obelisk, sarcophagus) stands on the cell the author picked instead of
## hanging above it. Returns the covered cells, empty if it did not fit.
static func stamp_landmark(
	layer: TileMapLayer,
	source: int,
	rect: Array,
	anchor: Vector2i,
	allowed: Dictionary,
	solid: Dictionary
) -> Array[Vector2i]:
	var w: int = int(rect[2])
	var h: int = int(rect[3])
	var origin := anchor - Vector2i(w / 2, h - 1)
	var cluster := MapKit.rect_cluster(int(rect[0]), int(rect[1]), w, h)
	var placed := MapKit.stamp_cluster(layer, source, cluster, origin, allowed, _bounds_of(layer))
	for c: Vector2i in placed:
		allowed.erase(c)
		solid[c] = true
	return placed


static func _bounds_of(layer: TileMapLayer) -> Rect2i:
	# Generous: callers already gate on `allowed`, which is bounded by the mask.
	var _unused := layer
	return Rect2i(-4, -4, 4096, 4096)


# --- Scene emission ---------------------------------------------------------

class ExtTable:
	extends RefCounted
	var lines: Array[String] = []
	var _ids: Dictionary = {}
	var _n: int = 0

	## [param fixed_id] names the entry instead of taking the next sequential
	## slot. Only the music rotation uses it, and only so a level that gains a
	## playlist does not renumber every OTHER resource in the file — see the note
	## in write_map.
	func get_id(kind: String, path: String, uid: String = "", fixed_id: String = "") -> String:
		if _ids.has(path):
			return _ids[path]
		var id := fixed_id
		if id == "":
			id = "e%d" % _n
			_n += 1
		_ids[path] = id
		var uid_part := ("uid=\"%s\" " % uid) if uid != "" else ""
		lines.append("[ext_resource type=\"%s\" %spath=\"%s\" id=\"%s\"]" % [kind, uid_part, path, id])
		return id


static func _vec(p: Vector2) -> String:
	return "Vector2(%s, %s)" % [str(p.x), str(p.y)]


## Write a level scene. See `build_biome_levels.gd` for the config shape.
static func write_map(cfg: Dictionary) -> void:
	var ext := ExtTable.new()
	var map_id := ext.get_id("Script", MAP_SCRIPT, MAP_UID)
	var tiles_id := ext.get_id("TileSet", cfg["tileset"])
	var rp_id := ext.get_id("Script", RP_SCRIPT, RP_UID)

	var music_line := ""
	if cfg.get("music", "") != "":
		music_line = "music = ExtResource(\"%s\")\n" % ext.get_id("AudioStream", cfg["music"])
		# The rotation Map plays after the base track. Emitted here rather than
		# hand-added to the generated scene: these six levels HAD playlists that
		# were patched in post-generation, and the next `build_biome_levels` run
		# silently deleted all six. Map.music_playlist is only read when `music`
		# is set, and verify_map_music.gd asserts that pairing, so it stays
		# nested under the same condition.
		#
		# Named `mus_<track>` and left out of the eN sequence deliberately. These
		# entries are being introduced to files that already exist, and taking
		# two sequential slots here would shift every later id — renumbering ~250
		# lines in each of five levels that are otherwise unchanged, and burying
		# the one real edit. It also reproduces the hand-patched form byte for
		# byte, so adopting the generator is a no-op on disk.
		# Allocated after the body below, so the entries land at the END of the
		# ext_resource block where the hand-patched ones already sit.

	var body := ""

	# --- Tiles ---
	var layers: Dictionary = cfg["layers"]
	body += "\n[node name=\"Tiles\" type=\"Node2D\" parent=\".\"]\ny_sort_enabled = true\n"
	for layer_name: String in LAYER_ORDER:
		if not layers.has(layer_name):
			continue
		body += "\n[node name=\"%s\" type=\"TileMapLayer\" parent=\"Tiles\"]\n" % layer_name
		if layer_name == "Ground":
			body += "z_index = -1\n"
		body += "y_sort_enabled = true\n"
		body += "tile_map_data = PackedByteArray(\"%s\")\n" % layers[layer_name]
		body += "tile_set = ExtResource(\"%s\")\n" % tiles_id

	# --- SceneProps: lights, campfires, decos, critters ---
	body += "\n[node name=\"SceneProps\" type=\"Node2D\" parent=\".\"]\ny_sort_enabled = true\n"
	for light: Dictionary in cfg.get("lights", []):
		var glow_id := ext.get_id("Texture2D", GLOW)
		body += "\n[node name=\"%s\" type=\"PointLight2D\" parent=\"SceneProps\"]\n" % light["name"]
		body += "position = %s\n" % _vec(light["pos"])
		body += "color = %s\n" % light.get("color", "Color(1, 0.6, 0.3, 1)")
		body += "energy = %s\n" % str(light.get("energy", 0.7))
		body += "texture = ExtResource(\"%s\")\n" % glow_id
		body += "texture_scale = %s\n" % str(light.get("scale", 1.3))
	for camp: Dictionary in cfg.get("camps", []):
		var camp_id := ext.get_id("PackedScene", CAMP)
		body += "\n[node name=\"%s\" parent=\"SceneProps\" instance=ExtResource(\"%s\")]\n" % [camp["name"], camp_id]
		body += "position = %s\n" % _vec(camp["pos"])
	for deco: Dictionary in cfg.get("decos", []):
		var deco_id := ext.get_id("PackedScene", DECO)
		var frames_id := ext.get_id("SpriteFrames", DECO_FRAMES % deco["frames"])
		body += "\n[node name=\"%s\" parent=\"SceneProps\" instance=ExtResource(\"%s\")]\n" % [deco["name"], deco_id]
		body += "position = %s\n" % _vec(deco["pos"])
		body += "sprite_frames = ExtResource(\"%s\")\n" % frames_id
		body += "scale_factor = %s\n" % str(deco.get("scale", 1.0))
		body += "light_energy = %s\n" % str(deco.get("light", 0.0))
		body += "light_color = %s\n" % deco.get("color", "Color(1, 0.7, 0.3, 1)")
	for critter: Dictionary in cfg.get("critters", []):
		var critter_id := ext.get_id("PackedScene", CRITTER)
		var cframes_id := ext.get_id("SpriteFrames", CRITTER_FRAMES % critter["frames"])
		body += "\n[node name=\"%s\" parent=\"SceneProps\" instance=ExtResource(\"%s\")]\n" % [critter["name"], critter_id]
		body += "position = %s\n" % _vec(critter["pos"])
		body += "sprite_frames = ExtResource(\"%s\")\n" % cframes_id
		body += "scale_factor = %s\n" % str(critter.get("scale", 1.0))
		body += "wander_radius = %s\n" % str(critter.get("wander_radius", 40.0))

	# --- ReplicatedPropsContainer + hostiles ---
	# Working boss maps bake both id maps on the container. A hostile that is not
	# in these dictionaries never syncs to clients, which is the failure mode
	# AGENTS.md calls out for the Hollow golem.
	var hostiles: Array = cfg.get("hostiles", [])
	var id_to_node := ""
	var node_to_id := ""
	for i in hostiles.size():
		var nm: String = hostiles[i]["name"]
		var sep := ",\n" if i < hostiles.size() - 1 else "\n"
		id_to_node += "%d: NodePath(\"%s\")%s" % [i, nm, sep]
		node_to_id += "NodePath(\"%s\"): %d%s" % [nm, i, sep]
	body += "\n[node name=\"ReplicatedPropsContainer\" type=\"Node2D\" parent=\".\" "
	body += "node_paths=PackedStringArray(\"id_to_node\", \"node_to_id\")]\n"
	body += "y_sort_enabled = true\n"
	body += "script = ExtResource(\"%s\")\n" % rp_id
	body += ("id_to_node = {\n%s}\n" % id_to_node) if hostiles.size() > 0 else "id_to_node = {}\n"
	body += ("node_to_id = {\n%s}\n" % node_to_id) if hostiles.size() > 0 else "node_to_id = {}\n"
	for h: Dictionary in hostiles:
		var hostile_id := ext.get_id("PackedScene", HOSTILE, HOSTILE_UID)
		var type_id := ext.get_id("Resource", h["type"])
		body += "\n[node name=\"%s\" parent=\"ReplicatedPropsContainer\" instance=ExtResource(\"%s\")]\n" % [
			h["name"], hostile_id
		]
		body += "position = %s\n" % _vec(h["pos"])
		body += "debug_draw_ranges = false\n"
		body += "enemy_data = ExtResource(\"%s\")\n" % type_id
		body += "weapon = null\n"

	# --- Friendly NPCs ---
	var npcs: Array = cfg.get("npcs", [])
	if not npcs.is_empty():
		body += "\n[node name=\"NPCs\" type=\"Node2D\" parent=\".\"]\ny_sort_enabled = true\n"
		for n: Dictionary in npcs:
			var npc_id := ext.get_id("PackedScene", NPC, NPC_UID)
			var res_id := ext.get_id("Resource", n["resource"])
			body += "\n[node name=\"%s\" parent=\"NPCs\" instance=ExtResource(\"%s\")]\n" % [n["name"], npc_id]
			body += "position = %s\n" % _vec(n["pos"])
			body += "npc_resource = ExtResource(\"%s\")\n" % res_id

	# --- Warpers: default spawn, arrival ids, and exits ---
	var warper_id := ext.get_id("PackedScene", WARPER, WARPER_UID)
	body += "\n[node name=\"RespawnPoint\" parent=\".\" instance=ExtResource(\"%s\")]\n" % warper_id
	body += "position = %s\n" % _vec(cfg["spawn"])
	for w: Dictionary in cfg.get("warpers", []):
		body += "\n[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]\n" % [w["name"], warper_id]
		body += "position = %s\n" % _vec(w["pos"])
		body += "warper_id = %d\n" % int(w["id"])
	for p: Dictionary in cfg.get("portals", []):
		var portal_id := ext.get_id("PackedScene", PORTAL, PORTAL_UID)
		var inst_id := ext.get_id("Resource", p["instance"])
		body += "\n[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]\n" % [p["name"], portal_id]
		body += "position = %s\n" % _vec(p["pos"])
		body += "portal_color = %s\n" % p.get("color", "Color(0.6, 0.6, 0.6, 1)")
		body += "destination_label = \"%s\"\n" % p["label"]
		body += "target_instance = ExtResource(\"%s\")\n" % inst_id
		body += "warper_id = %d\n" % int(p["id"])
		body += "target_id = %d\n" % int(p["target_id"])

	# Last ext_resources allocated, so they append to the end of the block.
	var playlist: Array = cfg.get("playlist", []) if music_line != "" else []
	if not playlist.is_empty():
		var refs: PackedStringArray = PackedStringArray()
		for track: String in playlist:
			var track_uid: String = ResourceUID.id_to_text(ResourceLoader.get_resource_uid(track))
			var id: String = ext.get_id(
				"AudioStream", track, track_uid, "mus_" + track.get_file().get_basename()
			)
			refs.append("ExtResource(\"%s\")" % id)
		music_line += "music_playlist = Array[AudioStream]([%s])\n" % ", ".join(refs)

	var header := "[gd_scene format=3]\n\n"
	header += "\n".join(ext.lines) + "\n\n"
	header += "[node name=\"%s\" type=\"Node2D\" node_paths=PackedStringArray(\"replicated_props_container\")]\n" % cfg["root"]
	header += "y_sort_enabled = true\n"
	header += "script = ExtResource(\"%s\")\n" % map_id
	header += "replicated_props_container = NodePath(\"ReplicatedPropsContainer\")\n"
	header += "map_background_color = %s\n" % cfg["bg"]
	header += music_line
	header += "camera_limit_left = -16\ncamera_limit_top = -16\n"
	header += "camera_limit_right = %d\ncamera_limit_bottom = %d\n" % [int(cfg["cam_right"]), int(cfg["cam_bottom"])]
	header += "\n[node name=\"CanvasModulate\" type=\"CanvasModulate\" parent=\".\"]\n"
	header += "color = %s\n" % cfg["modulate"]

	var out_path: String = cfg["out"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	assert(f != null, "cannot write %s" % out_path)
	f.store_string(header + body)
	f.close()
