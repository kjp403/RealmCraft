extends RefCounted
## Shared map-building toolkit.
##
## The point of this file is that biome builders never hand-stamp atlas
## rectangles. They describe *shapes* (masks) and *materials* (terrain ids /
## rim specs), and the helpers below resolve each cell to the correct tile from
## its neighbours — real autotiling, the same way a level artist paints with a
## terrain brush.
##
## Two painting systems live here:
##   1. Godot terrain autotiling (`TileMapLayer.set_cells_terrain_connect`) for
##      ground blends. Peering bits are derived from the artwork itself in
##      `derive_corner_terrain`, so a set never has to be transcribed by hand.
##   2. `paint_rim` for cliff/pit borders, which terrain mode cannot express
##      because the south face of a cliff is several tiles tall.

class_name MapKit


# --- Deterministic noise ----------------------------------------------------

static func hash2(x: int, y: int, seed_value: int = 0) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (seed_value * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


static func rand01(x: int, y: int, seed_value: int = 0) -> float:
	return float(hash2(x, y, seed_value) % 100000) / 100000.0


## Smooth value noise in roughly [0,1]. `scale` is the cell size of the lattice.
static func value_noise(x: float, y: float, scale: float, seed_value: int) -> float:
	var fx: float = x / scale
	var fy: float = y / scale
	var x0: int = int(floor(fx))
	var y0: int = int(floor(fy))
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var v00: float = rand01(x0, y0, seed_value)
	var v10: float = rand01(x0 + 1, y0, seed_value)
	var v01: float = rand01(x0, y0 + 1, seed_value)
	var v11: float = rand01(x0 + 1, y0 + 1, seed_value)
	return lerp(lerp(v00, v10, tx), lerp(v01, v11, tx), ty)


static func fbm(x: float, y: float, scale: float, octaves: int, seed_value: int) -> float:
	var total: float = 0.0
	var amp: float = 1.0
	var norm: float = 0.0
	var s: float = scale
	for i in octaves:
		total += value_noise(x, y, s, seed_value + i * 17) * amp
		norm += amp
		amp *= 0.5
		s *= 0.5
	return total / norm


# --- Mask shaping -----------------------------------------------------------

## Organic disk: a circle whose radius is modulated by noise so the outline is
## never a clean arc. This is what keeps caverns from reading as stamped rects.
static func blob(
	mask: Dictionary,
	center: Vector2i,
	radius: float,
	wobble: float,
	seed_value: int,
	bounds: Rect2i
) -> void:
	var reach: int = int(radius + radius * wobble) + 2
	for y in range(center.y - reach, center.y + reach + 1):
		for x in range(center.x - reach, center.x + reach + 1):
			var cell := Vector2i(x, y)
			if not bounds.has_point(cell):
				continue
			var dx: float = float(x - center.x)
			var dy: float = float(y - center.y)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 0.001:
				mask[cell] = true
				continue
			var ang: float = atan2(dy, dx)
			# Sample noise on the unit circle so the wobble wraps seamlessly.
			var n: float = fbm(cos(ang) * 6.0 + 32.0, sin(ang) * 6.0 + 32.0, 3.0, 3, seed_value)
			var r: float = radius * (1.0 + (n - 0.5) * 2.0 * wobble)
			if dist <= r:
				mask[cell] = true


## Winding corridor between two points; the path drifts with noise instead of
## running as an L-shaped pipe.
static func tunnel(
	mask: Dictionary,
	from_cell: Vector2i,
	to_cell: Vector2i,
	width: float,
	wander: float,
	seed_value: int,
	bounds: Rect2i
) -> void:
	var steps: int = int(max(absi(to_cell.x - from_cell.x), absi(to_cell.y - from_cell.y))) * 2 + 4
	var perp := Vector2(float(to_cell.y - from_cell.y), float(from_cell.x - to_cell.x)).normalized()
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var base := Vector2(from_cell).lerp(Vector2(to_cell), t)
		var drift: float = (fbm(t * 40.0, float(seed_value), 9.0, 2, seed_value) - 0.5) * 2.0 * wander
		# Taper the drift at both ends so the tunnel still meets its endpoints.
		drift *= sin(t * PI)
		var p := base + perp * drift
		var w: float = width * (0.85 + 0.35 * fbm(t * 30.0, 7.0, 6.0, 2, seed_value + 5))
		var reach: int = int(w) + 1
		for oy in range(-reach, reach + 1):
			for ox in range(-reach, reach + 1):
				if float(ox * ox + oy * oy) > w * w:
					continue
				var cell := Vector2i(int(round(p.x)) + ox, int(round(p.y)) + oy)
				if bounds.has_point(cell):
					mask[cell] = true


## Cellular-automata smoothing: removes 1-cell spikes and pinholes so rims read
## as continuous rock instead of confetti.
static func smooth(mask: Dictionary, bounds: Rect2i, iterations: int, birth: int, death: int) -> Dictionary:
	var current: Dictionary = mask.duplicate()
	for _i in iterations:
		var next: Dictionary = {}
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				var cell := Vector2i(x, y)
				var n: int = 0
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						if ox == 0 and oy == 0:
							continue
						if current.has(cell + Vector2i(ox, oy)):
							n += 1
				if current.has(cell):
					if n >= death:
						next[cell] = true
				elif n >= birth:
					next[cell] = true
		current = next
	return current


## Drop every region except the one containing `keep`, so a map can never ship
## with an unreachable pocket.
static func largest_region(mask: Dictionary, keep: Vector2i) -> Dictionary:
	if not mask.has(keep):
		return mask
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = [keep]
	seen[keep] = true
	var qi: int = 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cur + d
			if mask.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


# --- Terrain bit derivation (real autotiling) -------------------------------

## Build an explicit corner-mask → atlas-coords table by reading the artwork.
##
## Averaging a whole quadrant misreads feathered blend tiles, so each corner is
## sampled from a small box pinned into that corner of the tile, which is what
## actually has to line up with the neighbouring tile.
##
## Mask bits: 1 = top-left, 2 = top-right, 4 = bottom-left, 8 = bottom-right.
## A set bit means "overlay terrain occupies this corner".
static func corner_lookup(
	texture: Texture2D,
	tile_size: int,
	region: Rect2i,
	overlay_color: Color,
	alpha_threshold: float = 0.95
) -> Dictionary:
	var image: Image = texture.get_image()
	var table: Dictionary = {}
	# Sample close to the true corner: these blend tiles feather across most of
	# their area, so anything wider reads as "covered" on every corner.
	var box: int = maxi(3, tile_size / 5)
	var inset: int = maxi(1, tile_size / 16)
	for ty in range(region.position.y, region.end.y):
		for tx in range(region.position.x, region.end.x):
			var mask: int = 0
			var valid: bool = true
			for ci in 4:
				var cx: int = ci % 2
				var cy: int = ci / 2
				var ox: int = tx * tile_size + (inset if cx == 0 else tile_size - inset - box)
				var oy: int = ty * tile_size + (inset if cy == 0 else tile_size - inset - box)
				var avg := _region_average(image, Vector2i(ox, oy), Vector2i(box, box))
				if avg.a < alpha_threshold:
					continue  # see-through corner => base terrain, bit stays clear
				if _color_distance(avg, overlay_color) > 0.09:
					# Opaque but not the overlay colour: not part of this set.
					valid = false
					break
				mask |= 1 << ci
			if not valid:
				continue
			if not table.has(mask):
				table[mask] = [] as Array[Vector2i]
			(table[mask] as Array).append(Vector2i(tx, ty))
	return table


## Paint a patch using a corner lookup. Cells whose four corners are all base
## are left untouched, so the layer never drops a stray fill tile on open floor.
static func paint_corner_patch(
	layer: TileMapLayer,
	source_id: int,
	lookup: Dictionary,
	patch: Dictionary,
	bounds: Rect2i,
	seed_value: int,
	allowed: Dictionary = {}
) -> int:
	# The dual grid pushes tiles one cell right/down of the mask, so without a
	# bound the blend spills past the floor and paints over the void.
	var candidates: Dictionary = {}
	for cell: Vector2i in patch.keys():
		for off in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var c: Vector2i = cell + off
			if not bounds.has_point(c):
				continue
			if not allowed.is_empty() and not allowed.has(c):
				continue
			candidates[c] = true
	var painted: int = 0
	for cell: Vector2i in candidates.keys():
		# Dual grid: this tile's corners are the four mask cells around it.
		var mask: int = 0
		if patch.has(cell + Vector2i(-1, -1)):
			mask |= 1
		if patch.has(cell + Vector2i(0, -1)):
			mask |= 2
		if patch.has(cell + Vector2i(-1, 0)):
			mask |= 4
		if patch.has(cell):
			mask |= 8
		if mask == 0:
			continue
		var resolved: int = resolve_mask(lookup, mask)
		if resolved < 0:
			continue
		var options: Array = lookup[resolved]
		layer.set_cell(cell, source_id, _pick(options, cell, seed_value))
		painted += 1
	return painted


## Blob sets ship the common 13 corner combinations, not all 16 — single-corner
## nubs and pure diagonals are usually absent. Substitute the closest tile that
## still covers every requested corner, so a patch grows by a corner rather than
## punching a hole in itself.
static func resolve_mask(lookup: Dictionary, mask: int) -> int:
	if lookup.has(mask):
		return mask
	var best: int = -1
	var best_extra: int = 99
	for candidate: int in lookup.keys():
		if candidate & mask != mask:
			continue  # must cover every corner the shape asked for
		var extra: int = _popcount(candidate) - _popcount(mask)
		if extra < best_extra:
			best_extra = extra
			best = candidate
	return best


static func _popcount(v: int) -> int:
	var n: int = 0
	var x: int = v
	while x > 0:
		n += x & 1
		x >>= 1
	return n


static func _region_average(image: Image, origin: Vector2i, size: Vector2i) -> Color:
	var r: float = 0.0
	var g: float = 0.0
	var b: float = 0.0
	var a: float = 0.0
	var n: int = 0
	# Inset the sample box: tile borders carry anti-aliased pixels from the
	# neighbouring terrain and would bias the classification.
	var inset: int = maxi(1, size.x / 5)
	for y in range(origin.y + inset, origin.y + size.y - inset):
		for x in range(origin.x + inset, origin.x + size.x - inset):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var c := image.get_pixel(x, y)
			r += c.r
			g += c.g
			b += c.b
			a += c.a
			n += 1
	if n == 0:
		return Color(0, 0, 0, 0)
	return Color(r / n, g / n, b / n, a / n)


static func _color_distance(a: Color, b: Color) -> float:
	var dr: float = a.r - b.r
	var dg: float = a.g - b.g
	var db: float = a.b - b.b
	return dr * dr + dg * dg + db * db


# --- Cliff / pit rims -------------------------------------------------------

## A rim spec describes the border drawn around a void (chasm, pit, cave dark).
## Cliff art of this style extends *below* the south edge, so the south border
## needs `s_face` and `s_base` rows painted onto the two cells underneath.
class RimSpec:
	extends RefCounted
	var source: int = 0
	var fill: Array[Vector2i] = []
	var n: Array[Vector2i] = []
	var s: Array[Vector2i] = []
	var w: Array[Vector2i] = []
	var e: Array[Vector2i] = []
	var nw: Vector2i
	var ne: Vector2i
	var sw: Vector2i
	var se: Vector2i
	var s_face: Array[Vector2i] = []
	var s_base: Array[Vector2i] = []
	var sw_face: Vector2i
	var sw_base: Vector2i
	var se_face: Vector2i
	var se_base: Vector2i
	## How many rows the south cliff face occupies below the void.
	var face_rows: int = 2


static func _pick(list: Array, cell: Vector2i, seed_value: int = 0) -> Vector2i:
	return list[hash2(cell.x, cell.y, seed_value) % list.size()]


## Paint a void mask with correct rim tiles. `blocked` receives every cell the
## player must not enter (void plus the south cliff face rows).
static func paint_rim(
	layer: TileMapLayer,
	void_mask: Dictionary,
	spec: RimSpec,
	bounds: Rect2i,
	blocked: Dictionary
) -> void:
	for cell: Vector2i in void_mask.keys():
		blocked[cell] = true
	# South face occupies the two rows under the bottom edge of the void.
	for cell: Vector2i in void_mask.keys():
		if void_mask.has(cell + Vector2i.DOWN):
			continue
		for i in range(1, spec.face_rows + 1):
			var below: Vector2i = cell + Vector2i(0, i)
			if bounds.has_point(below):
				blocked[below] = true

	for cell: Vector2i in void_mask.keys():
		var up: bool = not void_mask.has(cell + Vector2i.UP)
		var down: bool = not void_mask.has(cell + Vector2i.DOWN)
		var left: bool = not void_mask.has(cell + Vector2i.LEFT)
		var right: bool = not void_mask.has(cell + Vector2i.RIGHT)
		var atlas: Vector2i
		if up and left:
			atlas = spec.nw
		elif up and right:
			atlas = spec.ne
		elif down and left:
			atlas = spec.sw
		elif down and right:
			atlas = spec.se
		elif up:
			atlas = _pick(spec.n, cell, 11)
		elif down:
			atlas = _pick(spec.s, cell, 12)
		elif left:
			atlas = _pick(spec.w, cell, 13)
		elif right:
			atlas = _pick(spec.e, cell, 14)
		else:
			# Interior. Diagonal-only contact still needs a rim or the void
			# would butt against open ground with a hard seam.
			var diag := _diagonal_rim(void_mask, cell, spec)
			atlas = diag if diag != Vector2i(-1, -1) else _pick(spec.fill, cell, 15)
		layer.set_cell(cell, spec.source, atlas)

		if down:
			var face_atlas: Vector2i = _pick(spec.s_face, cell, 16)
			var base_atlas: Vector2i = _pick(spec.s_base, cell, 17)
			if left:
				face_atlas = spec.sw_face
				base_atlas = spec.sw_base
			elif right:
				face_atlas = spec.se_face
				base_atlas = spec.se_base
			var f1: Vector2i = cell + Vector2i(0, 1)
			var f2: Vector2i = cell + Vector2i(0, 2)
			if bounds.has_point(f1):
				layer.set_cell(f1, spec.source, face_atlas)
			if spec.face_rows >= 2 and bounds.has_point(f2):
				layer.set_cell(f2, spec.source, base_atlas)


static func _diagonal_rim(void_mask: Dictionary, cell: Vector2i, spec: RimSpec) -> Vector2i:
	if not void_mask.has(cell + Vector2i(-1, -1)):
		return spec.nw
	if not void_mask.has(cell + Vector2i(1, -1)):
		return spec.ne
	if not void_mask.has(cell + Vector2i(-1, 1)):
		return spec.sw
	if not void_mask.has(cell + Vector2i(1, 1)):
		return spec.se
	return Vector2i(-1, -1)


# --- Prop discovery ---------------------------------------------------------

## Describe a prop by its atlas rectangle. Decorative sheets pack props edge to
## edge, so connected-component grouping merges a whole bank into one blob;
## verified rectangles are the reliable way to keep a formation intact.
static func rect_cluster(x: int, y: int, w: int, h: int) -> Dictionary:
	var cells: Array[Vector2i] = []
	for oy in h:
		for ox in w:
			cells.append(Vector2i(x + ox, y + oy))
	return {"origin": Vector2i(x, y), "size": Vector2i(w, h), "cells": cells}


## Stamp a cluster with its top-left at `origin`, returning the cells it covers,
## or an empty array when it will not fit.
static func stamp_cluster(
	layer: TileMapLayer,
	source_id: int,
	cluster: Dictionary,
	origin: Vector2i,
	allowed: Dictionary,
	bounds: Rect2i
) -> Array[Vector2i]:
	var cluster_origin: Vector2i = cluster["origin"]
	var cells: Array = cluster["cells"]
	var placed: Array[Vector2i] = []
	for atlas: Vector2i in cells:
		var target: Vector2i = origin + (atlas - cluster_origin)
		if not bounds.has_point(target) or not allowed.has(target):
			return [] as Array[Vector2i]
		placed.append(target)
	for atlas: Vector2i in cells:
		var target: Vector2i = origin + (atlas - cluster_origin)
		layer.set_cell(target, source_id, atlas)
	return placed


# --- Scattering -------------------------------------------------------------

## Blue-noise-ish scatter: keeps a minimum spacing so props never clump into the
## grid patterns that make a map look machine-made.
static func scatter(
	candidates: Array,
	density: float,
	spacing: int,
	seed_value: int,
	filter: Callable = Callable()
) -> Array[Vector2i]:
	var sorted_cells: Array = candidates.duplicate()
	sorted_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return hash2(a.x, a.y, seed_value) < hash2(b.x, b.y, seed_value)
	)
	var taken: Dictionary = {}
	var out: Array[Vector2i] = []
	for cell: Vector2i in sorted_cells:
		if rand01(cell.x, cell.y, seed_value + 3) > density:
			continue
		if filter.is_valid() and not filter.call(cell):
			continue
		var ok: bool = true
		for oy in range(-spacing, spacing + 1):
			for ox in range(-spacing, spacing + 1):
				if taken.has(cell + Vector2i(ox, oy)):
					ok = false
					break
			if not ok:
				break
		if ok:
			taken[cell] = true
			out.append(cell)
	return out


## Cells of `mask` that touch a non-mask cell — where wall-hugging detail goes.
static func edge_cells(mask: Dictionary, blocked: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in mask.keys():
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if blocked.has(cell + d) or not mask.has(cell + d):
				out.append(cell)
				break
	return out


static func interior_cells(mask: Dictionary, blocked: Dictionary, margin: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in mask.keys():
		var ok: bool = true
		for oy in range(-margin, margin + 1):
			for ox in range(-margin, margin + 1):
				var n: Vector2i = cell + Vector2i(ox, oy)
				if blocked.has(n) or not mask.has(n):
					ok = false
					break
			if not ok:
				break
		if ok:
			out.append(cell)
	return out


static func to_base64(layer: TileMapLayer) -> String:
	return Marshalls.raw_to_base64(layer.tile_map_data)
