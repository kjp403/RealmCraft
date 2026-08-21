extends Node
## Render every Dragon / Obsidian / Celestial / Astralite art asset onto one
## contact sheet, so the vein, ore, bar and tool icons can be judged side by
## side without launching a client.
##   godot --path . --mode=client res://tools/render_high_ore_tiers.tscn

const OUT: String = "previews/high-ore-tiers-art.png"
const TIERS: Array[String] = ["dragon", "obsidian", "celestial", "astralite"]
const COLUMNS: Array[String] = ["Vein", "Ore", "Bar", "Pickaxe", "Axe", "Sickle", "Rod"]
const GUTTER: int = 120
const CELL: int = 116
const HEADER: int = 30
const ROW: int = 132


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(GUTTER + CELL * COLUMNS.size(), HEADER + ROW * TIERS.size())
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(sv)

	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.10, 0.13)
	bg.size = Vector2(sv.size)
	sv.add_child(bg)

	for col: int in COLUMNS.size():
		_label(sv, COLUMNS[col], Vector2(GUTTER + CELL * col, 6), CELL, Color(0.62, 0.62, 0.68))

	for row: int in TIERS.size():
		var tier: String = TIERS[row]
		var top: int = HEADER + ROW * row
		_label(sv, tier.capitalize(), Vector2(4, top + 52), GUTTER - 8, Color(0.86, 0.86, 0.92))
		for col: int in COLUMNS.size():
			var entry: Array = _texture_for(tier, COLUMNS[col])
			if entry.is_empty():
				continue
			_cell(sv, entry[0], entry[1], GUTTER + CELL * col, top)

	for _f: int in 10:
		await get_tree().process_frame
	sv.get_texture().get_image().save_png(OUT)
	print("SAVED ", OUT)
	get_tree().quit(0)


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
	_label(sv, caption, Vector2(x, y + 96), CELL, Color(0.55, 0.55, 0.62))


func _label(sv: SubViewport, text: String, pos: Vector2, width: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = Vector2(width, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 15)
	label.add_theme_color_override(&"font_color", color)
	sv.add_child(label)
