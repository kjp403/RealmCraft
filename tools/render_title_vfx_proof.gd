extends SceneTree
## Capture the REAL TitleVfx + VaultSkinVfx (not a CSS mock).
## Must run WINDOWED — headless has no rasteriser:
##   godot --path . -s tools/render_title_vfx_proof.gd

const OUT_DIR := "res://previews"
const W := 1100
const H := 1480


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var out_abs: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_abs)

	var sv := SubViewport.new()
	sv.size = Vector2i(W, H)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.transparent_bg = false
	sv.disable_3d = true
	root.add_child(sv)

	var bg := ColorRect.new()
	bg.size = Vector2(W, H)
	bg.color = Color(0.055, 0.06, 0.075)
	sv.add_child(bg)

	_caption(sv, Vector2(28, 18), "DONATOR TITLE VFX — TitleVfx + TitleVfxPulse (game code)", 22, Color(0.92, 0.72, 0.42))
	_caption(sv, Vector2(28, 48), "Same driver the nameplate / Vault / profile use.", 15, Color(0.55, 0.55, 0.60))
	_caption(sv, Vector2(140, 68), "DIM", 13, Color(0.62, 0.62, 0.68))
	_caption(sv, Vector2(490, 68), "PULSE", 13, Color(0.62, 0.62, 0.68))
	_caption(sv, Vector2(840, 68), "FLASH", 13, Color(0.62, 0.62, 0.68))

	var titles: PackedStringArray = PackedStringArray([
		"Sapphire Supporter",
		"Emerald Supporter",
		"Ruby Supporter",
		"Arkenelle Supporter",
		"Sapphire VIP",
		"Emerald VIP",
		"Ruby VIP",
	])
	var y: float = 88.0
	for title: String in titles:
		_caption(sv, Vector2(28, y), title, 14, Color(0.70, 0.70, 0.74))
		var phases: Array = _phases_for(title)
		for col: int in 3:
			_title_cell(sv, Vector2(28.0 + float(col) * 350.0, y + 22.0), title, float(phases[col]))
		y += 96.0

	_caption(sv, Vector2(28, y + 8.0), "WARDROBE PALETTE SWAP — outlines / faces / leather stay. Armor and cloth take the ramp.", 15, Color(0.92, 0.72, 0.42))
	y += 44.0
	var skin_slugs: PackedStringArray = PackedStringArray([
		"knight", "rogue", "wizard", "goblin", "orc", "royal_knight",
	])
	var x0: float = 36.0
	for i: int in skin_slugs.size():
		var slug: String = skin_slugs[i]
		var col: int = i % 3
		var row: int = i / 3
		var at := Vector2(x0 + float(col) * 360.0, y + float(row) * 220.0)
		_skin_pair(sv, at, slug)

	for _i: int in 24:
		await process_frame

	var image: Image = sv.get_texture().get_image()
	var dest: String = out_abs.path_join("title-vfx-proof.png")
	image.save_png(dest)
	print("SAVED ", dest, " size=", image.get_size())
	await _render_dye_sheet(out_abs)
	quit(0)


func _phases_for(title: String) -> Array:
	var vip: bool = TitleCatalog.is_vip(title)
	var speed: float = 3.4 if vip else 2.2
	var dim_t: float = (3.0 * PI) / (2.0 * speed)
	var pulse_t: float = PI / (2.0 * speed)
	return [dim_t, pulse_t, 0.0]


func _title_cell(parent: Node, at: Vector2, title: String, t: float) -> void:
	var panel := ColorRect.new()
	panel.position = at
	panel.size = Vector2(330, 64)
	panel.color = Color(0.10, 0.11, 0.14)
	parent.add_child(panel)

	var label := Label.new()
	label.text = "« %s »" % title
	label.position = at + Vector2(8, 12)
	label.size = Vector2(314, 44)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 22)
	parent.add_child(label)
	TitleVfx.apply_to_label(label, title)
	var pulse: Node = label.get_node_or_null("TitleVfxPulse")
	if pulse != null:
		pulse.set_process(false)
		if pulse.has_method(&"_apply"):
			pulse.call(&"_apply", t)


func _skin_pair(parent: Node, at: Vector2, slug: String) -> void:
	var frames: SpriteFrames = load("res://source/common/gameplay/characters/sprite_frames/%s.tres" % slug) as SpriteFrames
	if frames == null:
		_caption(parent, at, "MISSING %s" % slug, 14, Color(1, 0.3, 0.3))
		return
	var anim: StringName = &"idle"
	if not frames.has_animation(anim):
		var names: PackedStringArray = frames.get_animation_names()
		anim = StringName(names[0]) if names.size() > 0 else &""
	var tex: Texture2D = frames.get_frame_texture(anim, 0) if not anim.is_empty() else null

	var skin_id: int = 0
	var sprites_reg: ContentRegistry = ContentRegistryHub.registry_of(&"sprites")
	if sprites_reg != null:
		skin_id = ContentRegistryHub.id_from_slug(&"sprites", StringName(slug))
	print("SKIN ", slug, " id=", skin_id)
	var packed: int = VaultSkins.pack(skin_id, VaultSkins.STYLE_GOLD) if skin_id > 0 else 0
	var dye_name: String = VaultSkins.display_name(packed) if packed > 0 else slug
	_caption(parent, at, "%s  →  %s" % [slug.capitalize(), dye_name], 13, Color(0.78, 0.78, 0.82))

	_sprite_at(parent, at + Vector2(40, 110), tex, 0)
	_sprite_at(parent, at + Vector2(200, 110), tex, packed)
	_caption(parent, at + Vector2(16, 168), "stock", 12, Color(0.50, 0.50, 0.55))
	_caption(parent, at + Vector2(176, 168), "vault dye", 12, Color(0.92, 0.72, 0.42))


func _sprite_at(parent: Node, at: Vector2, tex: Texture2D, vault_skin_id: int) -> void:
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = at
	spr.scale = Vector2(3.2, 3.2)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(spr)
	if vault_skin_id > 0:
		VaultSkinVfx.apply_to_sprite(spr, vault_skin_id)


func _caption(parent: Node, at: Vector2, text: String, size_px: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", color)
	parent.add_child(l)


func _render_dye_sheet(out_abs: String) -> void:
	const DW := 980
	const DH := 980
	var sv := SubViewport.new()
	sv.size = Vector2i(DW, DH)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.transparent_bg = false
	sv.disable_3d = true
	root.add_child(sv)
	var bg := ColorRect.new()
	bg.size = Vector2(DW, DH)
	bg.color = Color(0.055, 0.06, 0.075)
	sv.add_child(bg)
	_caption(sv, Vector2(24, 16), "16 VAULT DYES — same Knight, Wear-able packed ids", 20, Color(0.92, 0.72, 0.42))
	_caption(sv, Vector2(24, 42), "Gilded  Ember  Void  Starforged  Moonlit  Aether  Toxic  Crimson", 13, Color(0.55, 0.55, 0.60))
	_caption(sv, Vector2(24, 60), "Frost  Verdant  Sapphire  Rose  Obsidian  Copper  Ghost  Amber", 13, Color(0.55, 0.55, 0.60))

	var frames: SpriteFrames = load("res://source/common/gameplay/characters/sprite_frames/knight.tres") as SpriteFrames
	var tex: Texture2D = frames.get_frame_texture(&"idle", 0) if frames != null else null
	var skin_id: int = 0
	if ContentRegistryHub.registry_of(&"sprites") != null:
		skin_id = ContentRegistryHub.id_from_slug(&"sprites", &"knight")
	var i: int = 0
	for style: int in VaultSkins.STYLE_ORDER:
		var col: int = i % 4
		var row: int = i / 4
		var at := Vector2(70.0 + float(col) * 230.0, 130.0 + float(row) * 200.0)
		var packed: int = VaultSkins.pack(skin_id, style)
		_caption(sv, at + Vector2(-40, -28), str(VaultSkins.STYLE_META[style].get("label", "")), 14, Color(0.82, 0.82, 0.86))
		_sprite_at(sv, at + Vector2(40, 70), tex, packed)
		print("DYE ", style, " packed=", packed, " valid=", VaultSkins.is_valid(packed))
		i += 1

	for _i: int in 16:
		await process_frame
	var image: Image = sv.get_texture().get_image()
	var dest: String = out_abs.path_join("skin-recolor-proof.png")
	image.save_png(dest)
	print("SAVED ", dest, " size=", image.get_size(), " dyes=", VaultSkins.STYLE_ORDER.size())
