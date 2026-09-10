extends Node
## Screenshot the REAL Fillet panel at the shipping 960x540 client size, plus an
## icon strip for the three new items, so the shop art can be judged before it
## ships rather than after a player sees a vial labelled "bucket".
##
## Runs as a SCENE and WINDOWED — headless has no rasteriser, and `-s` has no
## autoloads, so fillet_menu.gd (Client / ClientState / Toaster) would not even
## compile there:
##   godot --path . --mode=client res://tools/render_fillet_preview.tscn

const MENU: String = "res://source/client/ui/menus/fillet/fillet_menu.tscn"
const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540

var _sv: SubViewport
var _out: String


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_out = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out)

	_sv = SubViewport.new()
	_sv.size = Vector2i(W, H)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.disable_3d = true
	get_tree().root.add_child(_sv)

	# Stand-in for the water behind the panel so the dim backdrop reads the way it
	# does over a real beach rather than over pure black.
	var ground := ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.16, 0.28, 0.34)
	_sv.add_child(ground)

	await _render_panel()
	await _render_icons()
	get_tree().quit(0)


func _render_panel() -> void:
	var menu: Control = (load(MENU) as PackedScene).instantiate()
	_sv.add_child(menu)
	await get_tree().process_frame
	# Feed the panel the exact payload shape fillet.list returns. open() is
	# skipped on purpose: it would fire a server request that cannot answer here.
	menu.set("_rows", _rows())
	menu.call("_render")
	await get_tree().process_frame
	await _capture("fillet_panel.png")
	menu.queue_free()


## A believable mid-game bag: a few species, mixed counts, ordered the way the
## panel orders them (most bait first).
func _rows() -> Array:
	var out: Array = []
	for spec: Array in [
		[&"tuna", "Raw Tuna", 24], [&"lobster", "Raw Lobster", 11],
		[&"trout", "Raw Trout", 9], [&"shrimp", "Raw Shrimp", 6],
	]:
		var id: int = ContentRegistryHub.id_from_slug(&"items", spec[0])
		out.append({
			"id": id, "name": spec[1], "held": spec[2],
			"yield_each": 2, "bait": int(spec[2]) * 2,
		})
	return out


## The three new item icons at bag scale, side by side with their names, so the
## placeholders are obvious rather than something to discover in the shop.
func _render_icons() -> void:
	var card := PanelContainer.new()
	PixelUI.panel(card, "frame_stone", 14)
	card.position = Vector2(150, 190)
	card.custom_minimum_size = Vector2(660, 0)
	_sv.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 26)
	card.add_child(row)

	for slug: StringName in [&"fillet_knife", &"bottomless_bait_bucket", &"fish_bait"]:
		var item: Item = ContentRegistryHub.load_by_slug(&"items", slug) as Item
		var col := VBoxContainer.new()
		col.add_theme_constant_override(&"separation", 6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)

		# A bare Control, never a Container: a Container collapses a mounted
		# PixelIcon to 0x0 and the slot renders empty, silently.
		var host := Control.new()
		host.custom_minimum_size = Vector2(64, 64)
		host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(host)
		if item != null:
			PixelIcon.mount(host, item.item_icon)

		var label: Label = PixelUI.text(
			String(item.item_name) if item != null else String(slug),
			PixelUI.SIZE_CAPTION, PixelUI.INK
		)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(label)

	await get_tree().process_frame
	await _capture("fillet_icons.png")
	card.queue_free()


## MUST be awaited: it waits a frame before sampling, so a bare call lets the
## caller free the very thing being photographed.
func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _sv.get_texture().get_image()
	image.resize(W * 2, H * 2, Image.INTERPOLATE_NEAREST)
	image.save_png(_out.path_join(file_name))
	print("wrote ", file_name)
