extends SceneTree
## Build the pond tiles from the PURCHASED pack instead of compositing my own.
##
## "platform - grass(transparency) - coast" is a full grass/water autotile set,
## so it already contains the pieces a pond needs: water with a grass bank on
## each side, and the inner corners where grass juts in. Tiles are identified by
## sampling nine points and voting grass vs water — the same classifier used for
## the beaches — then downscaled from the pack's 32px grid to the woodland's 16.
##   godot --headless --path . -s tools/build_pond_tiles_from_pack.gd

const SHEET: String = "res://assets/sprites/environment/sea/tilesets/grass_coast.png"
const WATER: String = "res://assets/sprites/environment/sea/tilesets/water_anim.png"
const OUT: String = "res://assets/sprites/environment/overworld/pond_tiles.png"
const SRC_TILE: int = 32
const DST_TILE: int = 16
const SAMPLES: Array[Vector2i] = [
	Vector2i(5, 5), Vector2i(26, 5), Vector2i(5, 26), Vector2i(26, 26),
	Vector2i(16, 4), Vector2i(27, 16), Vector2i(16, 27), Vector2i(4, 16),
	Vector2i(16, 16),
]

var _by_sig: Dictionary = {}
var _sheet: Image


func _init() -> void:
	var tex: Texture2D = load(SHEET)
	if tex == null:
		push_error("missing %s" % SHEET)
		quit(1)
		return
	_sheet = tex.get_image()
	_classify()

	# Bits: NW NE SW SE N E S W C. For a POND cell the centre is WATER, so the
	# wanted tiles are the ones whose centre samples as water and whose land
	# sits on the side facing the bank.
	var want: Dictionary = {
		"FILL": 0,
		"N": 1 | 2 | 16, "S": 4 | 8 | 64, "W": 1 | 4 | 128, "E": 2 | 8 | 32,
		"NW": 1 | 2 | 4 | 16 | 128, "NE": 1 | 2 | 8 | 16 | 32,
		"SW": 1 | 4 | 8 | 64 | 128, "SE": 2 | 4 | 8 | 32 | 64,
		"INW": 1, "INE": 2, "ISW": 4,
	}
	var layout: Dictionary = {
		"NW": Vector2i(0, 0), "N": Vector2i(1, 0), "NE": Vector2i(2, 0),
		"W": Vector2i(0, 1), "FILL": Vector2i(1, 1), "E": Vector2i(2, 1),
		"SW": Vector2i(0, 2), "S": Vector2i(1, 2), "SE": Vector2i(2, 2),
		"INW": Vector2i(3, 0), "INE": Vector2i(3, 1), "ISW": Vector2i(3, 2),
	}

	var out := Image.create_empty(DST_TILE * 4, DST_TILE * 3, false, Image.FORMAT_RGBA8)
	var water_fill: Image = (load(WATER) as Texture2D).get_image().get_region(
		Rect2i(0, 0, SRC_TILE, SRC_TILE))
	var missing: PackedStringArray = []
	for key: String in want:
		var cell: Vector2i = _closest(int(want[key]))
		var piece: Image
		if key == "FILL" or cell.x < 0:
			piece = water_fill.duplicate()
			if cell.x < 0:
				missing.append(key)
		else:
			piece = water_fill.duplicate()
			if piece.get_format() != Image.FORMAT_RGBA8:
				piece.convert(Image.FORMAT_RGBA8)
			var overlay: Image = _sheet.get_region(
				Rect2i(cell * SRC_TILE, Vector2i(SRC_TILE, SRC_TILE)))
			if overlay.get_format() != Image.FORMAT_RGBA8:
				overlay.convert(Image.FORMAT_RGBA8)
			piece.blend_rect(overlay, Rect2i(Vector2i.ZERO, Vector2i(SRC_TILE, SRC_TILE)),
				Vector2i.ZERO)
		piece.resize(DST_TILE, DST_TILE, Image.INTERPOLATE_LANCZOS)
		if piece.get_format() != Image.FORMAT_RGBA8:
			piece.convert(Image.FORMAT_RGBA8)
		out.blit_rect(piece, Rect2i(Vector2i.ZERO, Vector2i(DST_TILE, DST_TILE)),
			layout[key] * DST_TILE)
	out.save_png(ProjectSettings.globalize_path(OUT))
	print("SAVED %s from pack art; fell back to plain water for: %s"
		% [OUT, "none" if missing.is_empty() else ", ".join(missing)])
	quit(0)


static func _is_land(c: Color) -> bool:
	# This sheet is a grass PLATFORM drawn over transparency: the transparent
	# pixels are where the water shows through. So land = opaque and green.
	return c.a > 0.5 and c.g >= c.b


func _classify() -> void:
	var cols: int = _sheet.get_width() / SRC_TILE
	var rows: int = _sheet.get_height() / SRC_TILE
	for ty: int in rows:
		for tx: int in cols:
			var sig: int = 0
			var ok: bool = true
			for i: int in SAMPLES.size():
				var land: int = 0
				var total: int = 0
				for dy: int in range(-2, 3):
					for dx: int in range(-2, 3):
						var p: Vector2i = SAMPLES[i] + Vector2i(tx * SRC_TILE + dx, ty * SRC_TILE + dy)
						if p.x < 0 or p.y < 0 or p.x >= _sheet.get_width() or p.y >= _sheet.get_height():
							continue
						var c: Color = _sheet.get_pixelv(p)
						total += 1
						if _is_land(c):
							land += 1
					if not ok:
						break
				if not ok:
					break
				if total > 0 and land * 2 > total:
					sig |= 1 << i
			if ok and not _by_sig.has(sig):
				_by_sig[sig] = Vector2i(tx, ty)
	print("distinct signatures in the pack sheet: ", _by_sig.size())


## Exact signature if present, else the nearest by Hamming distance.
func _closest(sig: int) -> Vector2i:
	if _by_sig.has(sig):
		return _by_sig[sig]
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 99
	for key: int in _by_sig:
		var d: int = 0
		var v: int = key ^ sig
		while v != 0:
			d += v & 1
			v >>= 1
		if d < best_d:
			best_d = d
			best = _by_sig[key]
	return best if best_d <= 3 else Vector2i(-1, -1)
