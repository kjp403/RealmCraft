extends SceneTree
## Compose beach ground images from the Sea Adventures sheets.
##
## Rather than hand-reading a blob sheet, every 32px tile is CLASSIFIED by
## sampling nine points and deciding sand vs water at each. That yields an
## 8-bit edge signature per tile (which sides/corners are sand), and the
## composer picks a tile whose signature matches the neighbourhood of the cell
## it is filling. Same idea as an autotiler, but derived from the art instead of
## a hand-authored bitmask, so a mis-read cannot put a foam edge facing inland.
##
##   godot --headless --path . -s tools/build_beach_ground.gd

const SHEET: String = "res://assets/sprites/environment/sea/tilesets/beach_foam.png"
const WATER: String = "res://assets/sprites/environment/sea/tilesets/water_anim.png"
const TILE: int = 32
## Only classify tiles from ONE block of the sheet. The sheet holds several
## coastline styles with different foam curves; mixing them gave neighbouring
## cells edges that did not meet, which read as wedges along the shore.
const BLOCK: Rect2i = Rect2i(0, 0, 6, 7)

## Sample points inside a tile: corners first (NW NE SW SE), then edge midpoints
## (N E S W), then centre. Insets avoid the foam fringe that straddles a border.
const SAMPLES: Array[Vector2i] = [
	Vector2i(5, 5), Vector2i(26, 5), Vector2i(5, 26), Vector2i(26, 26),
	Vector2i(16, 4), Vector2i(27, 16), Vector2i(16, 27), Vector2i(4, 16),
	Vector2i(16, 16),
]

var _by_signature: Dictionary = {}
var _sheet: Image
var _water: Image


## Maps to build: name -> {size in tiles, shoreline shape}. Shorelines are
## authored as a function of x so the coast reads as a designed curve rather
## than noise, and the same function feeds the collider export.
const MAPS: Array[Dictionary] = [
	{
		"name": "woodland_beach_ground",
		"cols": 26, "rows": 16,
		# 26 tiles wide, matching where the Deep Cove is instanced next to it.
		"shape": "main",
	},
	{
		"name": "woodland_east_link_ground",
		"cols": 24, "rows": 16,
		"shape": "link",
	},
	{
		"name": "deep_shoals_ground",
		"cols": 60, "rows": 34,
		"shape": "shoals",
	},
]


func _init() -> void:
	_sheet = (load(SHEET) as Texture2D).get_image()
	_water = (load(WATER) as Texture2D).get_image()
	_classify()
	for spec: Dictionary in MAPS:
		_build(spec)
	quit(0)


## Sand mask. Row 0 is the top of the map; the sea is always SOUTH, so a column
## is sand from the top down to its shore row.
func _shore_row(shape: String, col: int, cols: int, rows: int) -> float:
	var t: float = float(col) / float(maxi(1, cols - 1))
	if shape == "main":
		# A long strand that sweeps out to a headland in the east, so the map
		# ends on land instead of stopping mid-water.
		var base: float = 8.0 + 2.6 * sin(t * PI * 0.85)
		var bay: float = -1.6 * exp(-pow((t - 0.30) * 5.0, 2.0))
		var headland: float = 2.4 * exp(-pow((t - 0.86) * 4.0, 2.0))
		return clampf(base + bay + headland, 3.0, float(rows) - 4.0)
	if shape == "link":
		# Joins the Deep Cove (shore ~y332) to the East Shore (~y332) across the
		# 764px that used to be black void. Held near both neighbours' height so
		# the coast reads as one continuous strand, with a gentle bight in the
		# middle rather than a dead straight line.
		var link_rows: float = 332.0 / float(TILE)
		return clampf(link_rows + 1.4 * sin(t * PI), 3.0, float(rows) - 4.0)
	# Shoals: a sheltered crescent — deep water in the middle, arms north at
	# both ends, so every fishing hole sits in its own pocket of water.
	# Two coves and a headland across a long strand, with enough sand inland for
	# a lighthouse, a house and a market to stand clear of each other.
	var bays: float = 19.0 - 4.5 * cos(t * PI * 2.2)
	var west_cove: float = -3.0 * exp(-pow((t - 0.18) * 7.0, 2.0))
	var east_cove: float = -2.6 * exp(-pow((t - 0.62) * 8.0, 2.0))
	var point: float = 3.2 * exp(-pow((t - 0.86) * 6.0, 2.0))
	return clampf(bays + west_cove + east_cove + point, 4.0, float(rows) - 5.0)


## Per-column shore row, QUANTISED to whole tiles and limited to one tile of
## change per column. The art has edge tiles and single corner tiles; a coast
## that drops two rows at once has no tile for the join, and a diagonal run of
## bare corners reads as a comb of spikes rather than a shoreline.
var _shore_cache: Dictionary = {}


func _shore_steps(shape: String, cols: int, rows: int) -> PackedInt32Array:
	var key: String = "%s:%d:%d" % [shape, cols, rows]
	if _shore_cache.has(key):
		return _shore_cache[key]
	var steps: PackedInt32Array = PackedInt32Array()
	steps.resize(cols)
	for col: int in cols:
		steps[col] = int(round(_shore_row(shape, col, cols, rows)))
	# Two passes, forward then back, so a slope is spread evenly instead of all
	# the correction landing at one end.
	for col: int in range(1, cols):
		steps[col] = clampi(steps[col], steps[col - 1] - 1, steps[col - 1] + 1)
	for col: int in range(cols - 2, -1, -1):
		steps[col] = clampi(steps[col], steps[col + 1] - 1, steps[col + 1] + 1)
	_shore_cache[key] = steps
	return steps


func _is_sand_cell(shape: String, col: int, row: int, cols: int, rows: int) -> bool:
	if col < 0 or col >= cols:
		# Off-map columns continue the edge column, so the coast does not fray
		# into water at the seams.
		col = clampi(col, 0, cols - 1)
	if row < 0:
		return true
	if row >= rows:
		return false
	return row < _shore_steps(shape, cols, rows)[col]


## Pick the tile whose art matches this neighbourhood. Exact match first; the
## nearest signature by Hamming distance otherwise, so an unusual corner still
## gets sensible art instead of a hole.
func _tile_for(sig: int, salt: int) -> Vector2i:
	var options: Array = _by_signature.get(sig, [])
	if options.is_empty():
		var best: int = -1
		var best_d: int = 99
		for key: int in _by_signature:
			var d: int = _bit_count(key ^ sig)
			if d < best_d:
				best_d = d
				best = key
		options = _by_signature[best]
	return options[salt % options.size()]


static func _bit_count(v: int) -> int:
	var n: int = 0
	while v != 0:
		n += v & 1
		v >>= 1
	return n


func _build(spec: Dictionary) -> void:
	var cols: int = int(spec["cols"])
	var rows: int = int(spec["rows"])
	var shape: String = str(spec["shape"])
	var out := Image.create_empty(cols * TILE, rows * TILE, false, Image.FORMAT_RGBA8)

	# The art puts the shore INSIDE a single straddle tile — sand along its top,
	# water below — rather than splitting sand and water into separate cells. So
	# each column is: full sand above its shore row, the straddle tile ON it,
	# open water below. Steps between columns then read as a natural stepped
	# coast instead of a comb of corner nubs.
	var shore_steps: PackedInt32Array = _shore_steps(shape, cols, rows)
	var edge: Vector2i = _by_signature[19][0]
	for col: int in cols:
		var shore: int = shore_steps[col]
		for row: int in rows:
			var cell: Vector2i
			var src: Image = _sheet
			if row < shore:
				cell = _by_signature[511][(col * 7 + row * 13) % _by_signature[511].size()]
			elif row == shore:
				cell = edge
			else:
				src = _water
				cell = Vector2i(0, 0)
			var at := Rect2i(cell.x * TILE, cell.y * TILE, TILE, TILE)
			out.blit_rect(src.get_region(at), Rect2i(Vector2i.ZERO, Vector2i(TILE, TILE)),
				Vector2i(col * TILE, row * TILE))

	var dest_dir: String = ProjectSettings.globalize_path(
		"res://assets/sprites/environment/fishing/beach"
	)
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var dest: String = dest_dir.path_join(str(spec["name"]) + ".png")
	out.save_png(dest)

	# Collider data: the sand/water boundary in PIXELS, every 16px, in the
	# format beach_area_colliders.gd expects.
	var steps: PackedInt32Array = _shore_steps(shape, cols, rows)
	var pts: PackedStringArray = []
	var x: int = 0
	while x <= cols * TILE - 1:
		var c0: int = clampi(int(floor(float(x) / float(TILE))), 0, cols - 1)
		# Walkable sand ends a few pixels into the foam tile, so players stand at
		# the water's edge rather than floating on it.
		pts.append("%d, %d" % [x, steps[c0] * TILE + 10])
		x += 16
	print("SAVED %s  %dx%d px" % [dest, out.get_width(), out.get_height()])
	print("SHORELINE %s = PackedVector2Array(%s)" % [spec["name"], ", ".join(pts)])


## Sand is warm (red > blue); water is cold. Transparent samples disqualify the
## tile — the sheet has empty padding cells between blocks.
static func _is_sand(c: Color) -> bool:
	return c.r > c.b


func _classify() -> void:
	var counts: Dictionary = {}
	for ty: int in range(BLOCK.position.y, BLOCK.end.y):
		for tx: int in range(BLOCK.position.x, BLOCK.end.x):
			var sig: int = 0
			var opaque: bool = true
			for i: int in SAMPLES.size():
				# Vote over a patch: a single pixel lands in foam often enough to
				# mis-read an island corner as an edge, which left the tile set
				# without convex corners and put nubs along every diagonal.
				var sand_votes: int = 0
				var total: int = 0
				for dy: int in range(-2, 3):
					for dx: int in range(-2, 3):
						var p: Vector2i = SAMPLES[i] + Vector2i(tx * TILE + dx, ty * TILE + dy)
						if p.x < 0 or p.y < 0 or p.x >= _sheet.get_width() or p.y >= _sheet.get_height():
							continue
						var c: Color = _sheet.get_pixelv(p)
						if c.a < 0.9:
							opaque = false
							break
						total += 1
						if _is_sand(c):
							sand_votes += 1
					if not opaque:
						break
				if not opaque:
					break
				if total > 0 and sand_votes * 2 > total:
					sig |= 1 << i
			if not opaque:
				continue
			if not _by_signature.has(sig):
				_by_signature[sig] = []
			_by_signature[sig].append(Vector2i(tx, ty))
			counts[sig] = int(counts.get(sig, 0)) + 1
	var keys: Array = counts.keys()
	keys.sort()
	print("distinct signatures: ", keys.size())
	for sig: int in keys:
		print("  sig %3d (%s) x%d  e.g. %s" % [
			sig, _sig_text(sig), counts[sig], _by_signature[sig][0]
		])


static func _sig_text(sig: int) -> String:
	var names: PackedStringArray = ["NW", "NE", "SW", "SE", "N", "E", "S", "W", "C"]
	var on: PackedStringArray = []
	for i: int in names.size():
		if sig & (1 << i):
			on.append(names[i])
	return "-" if on.is_empty() else " ".join(on)
