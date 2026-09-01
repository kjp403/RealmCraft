extends Node
## Render the Dragon / Obsidian / Celestial / Astralite art for review without
## launching a client. Produces TWO sheets:
##
##   previews/high-ore-tiers-art.png   every asset in the tier, side by side
##   previews/tool-legibility.png      the tool silhouette revision, before vs
##                                     after, plus a silhouette-only test
##
## The second sheet exists because the first attempt at the tool art gave each
## tier its own head geometry and lost the TOOL TYPE in the process. Colour
## hides that failure — a red blob and a gold blob look like different, valid
## items. So the bottom band throws the colour away and renders the revised
## heads as flat silhouettes against the shipped Bronze tool: if a pickaxe does
## not read as a pickaxe there, it does not read as one in a bag either.
##
##   godot --path . --mode=client res://tools/render_high_ore_tiers.tscn

const OUT: String = "previews/high-ore-tiers-art.png"
const OUT_LEGIBILITY: String = "previews/tool-legibility.png"
const TIERS: Array[String] = ["dragon", "obsidian", "celestial", "astralite"]
const COLUMNS: Array[String] = ["Vein", "Ore", "Bar", "Pickaxe", "Axe", "Sickle", "Rod"]
const GUTTER: int = 120
const CELL: int = 116
const HEADER: int = 30
const ROW: int = 132

## Tool type -> its canonical cell on a 192x112 weapon sheet. Identical for the
## rejected art and the revision, so both sides of the comparison are read with
## the same rect and any difference is genuinely the drawing.
const TOOL_SLOTS: Dictionary = {
	"Pickaxe": Rect2(0, 48, 16, 32),
	"Sickle": Rect2(32, 48, 16, 32),
	"Axe": Rect2(112, 48, 16, 32),
}
const OLD_SHEET: String = "res://assets/sprites/items/weapons/%s/%s.png"
const NEW_SHEET: String = "res://assets/sprites/items/weapons/tools/high_tier/tools_%s.png"
## The shipped silhouette the revision has to match.
const REFERENCE_SHEET: String = "res://assets/sprites/items/weapons/bronze/bronze.png"

const BG: Color = Color(0.11, 0.10, 0.13)
const PANEL: Color = Color(0.93, 0.93, 0.95)
const DIM: Color = Color(0.55, 0.55, 0.62)
const BRIGHT: Color = Color(0.88, 0.88, 0.94)


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	await _render_contact_sheet()
	await _render_legibility_sheet()
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# Sheet 1 — every asset in the tier
# ---------------------------------------------------------------------------

func _render_contact_sheet() -> void:
	var sv: SubViewport = _viewport(
		Vector2i(GUTTER + CELL * COLUMNS.size(), HEADER + ROW * TIERS.size()), BG
	)

	for col: int in COLUMNS.size():
		_label(sv, COLUMNS[col], Vector2(GUTTER + CELL * col, 6), CELL, DIM)

	for row: int in TIERS.size():
		var tier: String = TIERS[row]
		var top: int = HEADER + ROW * row
		_label(sv, tier.capitalize(), Vector2(4, top + 52), GUTTER - 8, BRIGHT)
		for col: int in COLUMNS.size():
			var entry: Array = _texture_for(tier, COLUMNS[col])
			if entry.is_empty():
				continue
			_cell(sv, entry[0], entry[1], GUTTER + CELL * col, top)

	await _flush(sv, OUT)


## `[texture, caption]` for one grid cell, or empty when the tier has no such
## asset (only Dragon smiths a fishing rod).
func _texture_for(tier: String, column: String) -> Array:
	match column:
		"Vein":
			var vein: Resource = load(
				"res://source/common/gameplay/maps/components/mineable_nodes/%s_vein.tres" % tier
			)
			return [vein.texture, "lv %d" % vein.required_level]
		"Ore", "Bar":
			var mat: Resource = load(
				"res://source/common/gameplay/items/materials/metals/%s_%s.tres" % [
					tier, column.to_lower()
				]
			)
			return [mat.item_icon, "%dg" % mat.vendor_value]
		"Rod":
			if tier != "dragon":
				return []
			var rod: Resource = load(
				"res://source/common/gameplay/items/weapons/tools/fishing_rod_dragon.tres"
			)
			return [rod.item_icon, "%dg" % rod.vendor_value]
		_:
			var tool_item: Resource = load(
				"res://source/common/gameplay/items/weapons/tools/%s_%s.tres" % [
					column.to_lower(), tier
				]
			)
			return [tool_item.item_icon, "%dg" % tool_item.vendor_value]


# ---------------------------------------------------------------------------
# Sheet 2 — the legibility revision
# ---------------------------------------------------------------------------

const L_LEFT: int = 96
const L_CELL: int = 88
const L_ROW: int = 112
const L_GAP: int = 44


func _render_legibility_sheet() -> void:
	var tools: Array = TOOL_SLOTS.keys()
	var block: int = L_CELL * TIERS.size()
	var width: int = L_LEFT + block + L_GAP + block + 16
	var band: int = 34 + L_ROW * tools.size()
	var sil_top: int = 40 + band + 30
	var height: int = sil_top + 44 + L_ROW * tools.size() + 36

	var sv: SubViewport = _viewport(Vector2i(width, height), BG)

	_label(sv, "REJECTED — per-tier head geometry", Vector2(L_LEFT, 10), block, Color(0.92, 0.55, 0.45))
	_label(sv, "REVISED — shared tool silhouette", Vector2(L_LEFT + block + L_GAP, 10), block, Color(0.55, 0.85, 0.62))
	for t: int in TIERS.size():
		var name: String = TIERS[t].capitalize()
		_label(sv, name, Vector2(L_LEFT + L_CELL * t, 34), L_CELL, DIM, 12)
		_label(sv, name, Vector2(L_LEFT + block + L_GAP + L_CELL * t, 34), L_CELL, DIM, 12)

	for r: int in tools.size():
		var tool: String = tools[r]
		var rect: Rect2 = TOOL_SLOTS[tool]
		var top: int = 54 + L_ROW * r
		_label(sv, tool, Vector2(4, top + 40), L_LEFT - 10, BRIGHT)
		for t: int in TIERS.size():
			var tier: String = TIERS[t]
			_icon(sv, _atlas(OLD_SHEET % [tier, tier], rect),
				L_LEFT + L_CELL * t + L_CELL / 2, top + 46, 2.6)
			_icon(sv, _atlas(NEW_SHEET % tier, rect),
				L_LEFT + block + L_GAP + L_CELL * t + L_CELL / 2, top + 46, 2.6)

	# --- silhouette band: colour removed, shape only ---
	var panel := ColorRect.new()
	panel.color = PANEL
	panel.position = Vector2(0, sil_top)
	panel.size = Vector2(width, 44 + L_ROW * tools.size() + 28)
	sv.add_child(panel)
	_label(sv, "SILHOUETTE TEST — colour removed; Bronze reference at left",
		Vector2(8, sil_top + 6), width - 16, Color(0.24, 0.24, 0.30), 13)

	_label(sv, "Bronze", Vector2(2, sil_top + 26), L_LEFT - 4, Color(0.36, 0.36, 0.44), 12)
	for t: int in TIERS.size():
		_label(sv, TIERS[t].capitalize(), Vector2(L_LEFT + L_CELL * t, sil_top + 26),
			L_CELL, Color(0.36, 0.36, 0.44), 12)
	for r: int in tools.size():
		var tool: String = tools[r]
		var rect: Rect2 = TOOL_SLOTS[tool]
		var top: int = sil_top + 44 + L_ROW * r
		# Reference and revision both flattened to pure black: modulate
		# multiplies, so any non-black tint leaves the source colour showing and
		# the "colour removed" claim would be a lie.
		_icon(sv, _atlas(REFERENCE_SHEET, rect), L_LEFT / 2, top + 40, 2.6, Color.BLACK)
		for t: int in TIERS.size():
			_icon(sv, _atlas(NEW_SHEET % TIERS[t], rect),
				L_LEFT + L_CELL * t + L_CELL / 2, top + 40, 2.6, Color.BLACK)
		if tool == "Axe":
			# Honest caption: the shipped Bronze "axe" cell is a hoe, so the
			# revision is SUPPOSED to diverge from the reference on this row.
			_label(sv, "base axe art is a hoe — revision diverges deliberately",
				Vector2(L_LEFT, top + 88), block, Color(0.45, 0.30, 0.24), 11)

	await _flush(sv, OUT_LEGIBILITY)


func _atlas(sheet_path: String, region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(sheet_path)
	atlas.region = region
	return atlas


# ---------------------------------------------------------------------------
# Shared drawing helpers
# ---------------------------------------------------------------------------

func _viewport(size: Vector2i, bg_color: Color) -> SubViewport:
	var sv := SubViewport.new()
	sv.size = size
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(sv)
	var bg := ColorRect.new()
	bg.color = bg_color
	bg.size = Vector2(size)
	sv.add_child(bg)
	return sv


func _flush(sv: SubViewport, path: String) -> void:
	for _f: int in 10:
		await get_tree().process_frame
	sv.get_texture().get_image().save_png(path)
	print("SAVED ", path)
	sv.queue_free()


## One sprite centred on (cx, cy). `tint` of BLACK collapses it to a pure
## silhouette — modulate multiplies, so alpha survives and every colour goes.
func _icon(
	sv: SubViewport, tex: Texture2D, cx: int, cy: int, scale: float,
	tint: Color = Color.WHITE
) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(scale, scale)
	sprite.position = Vector2(cx, cy)
	sprite.modulate = tint
	sv.add_child(sprite)


func _cell(sv: SubViewport, tex: Texture2D, caption: String, x: int, y: int) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Fit the tallest side to 72px so a 16x32 tool icon and a 48px vein read at
	# a comparable size instead of the vein swamping the row.
	var size: Vector2 = tex.get_size()
	var fit: float = 72.0 / maxf(size.x, size.y)
	sprite.scale = Vector2(fit, fit)
	sprite.position = Vector2(x + CELL / 2.0, y + 50.0)
	sv.add_child(sprite)
	_label(sv, caption, Vector2(x, y + 96), CELL, DIM)


func _label(
	sv: SubViewport, text: String, pos: Vector2, width: int, color: Color, size: int = 15
) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = Vector2(width, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	sv.add_child(label)
