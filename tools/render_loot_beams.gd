extends SceneTree
## Render the loot beams over real ground drops, using the real LootBeam.spawn and
## the real tier rule — so what this shows is what the client builds, not a mockup.
##
## Four pillars, left to right by DROP RATE: a common material (10%, earns
## nothing), the material chest (2%), a level-70 weapon (0.25%), a relic (0.1%).
##
## Must run WINDOWED (no --headless) — headless has no rasteriser:
##   godot --path . -s tools/render_loot_beams.gd

const OUT_DIR := "user://loot_beams"
const W := 720
const H := 260
const ZOOM := 2
const CAPTURE_S := 2.6
const FPS := 12
## One item per tier, picked so the sample covers every branch of the rule.
const SAMPLES: Array[String] = [
	"res://source/common/gameplay/items/materials/metals/godsteel_ore.tres",
	"res://source/common/gameplay/items/chests/gold_blue_grand.tres",
	"res://source/common/gameplay/items/weapons/sword/sword_godsteel.item.tres",
	"res://source/common/gameplay/items/gears/relics/relic_cinderheart.tres",
]

var _sv: SubViewport


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	_sv = SubViewport.new()
	_sv.size = Vector2i(W, H)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.transparent_bg = false
	_sv.world_2d = World2D.new()
	root.add_child(_sv)

	var stage := Node2D.new()
	_sv.add_child(stage)
	var bg := ColorRect.new()
	bg.size = Vector2(W, H)
	bg.color = Color(0.10, 0.12, 0.10)   # dark grass, so a beam has to earn its read
	bg.z_index = -20
	stage.add_child(bg)
	var cam := Camera2D.new()
	cam.position = Vector2(W, H) * 0.5
	cam.make_current()
	stage.add_child(cam)

	var ground: float = H - 56.0
	var line := ColorRect.new()
	line.size = Vector2(W - 40.0, 2.0)
	line.position = Vector2(20.0, ground)
	line.color = Color(0.18, 0.22, 0.18)
	stage.add_child(line)

	for i: int in SAMPLES.size():
		var item: Item = load(SAMPLES[i]) as Item
		if item == null:
			continue
		var cx: float = W * (float(i) + 0.5) / float(SAMPLES.size())
		# The drop itself: a Node2D standing in for GroundItem, with the item icon
		# where GroundItem's Sprite2D would be.
		var drop := Node2D.new()
		drop.position = Vector2(cx, ground)
		drop.scale = Vector2(ZOOM, ZOOM)
		stage.add_child(drop)

		var beam: LootBeam = LootBeam.spawn(drop, item)

		var icon := Sprite2D.new()
		icon.texture = item.item_icon
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.z_index = 1
		if item.item_icon != null and item.item_icon.get_width() > 48:
			icon.scale = Vector2(0.5, 0.5)   # inventory art is bigger than a drop
		drop.add_child(icon)

		var tier: int = LootBeam.tier_for(item)
		var names: Array[String] = ["no beam", "cyan", "gold", "purple"]
		var rate: float = DropRarityIndex.chance_for(int(item.get_meta("id", 0)))
		_label(stage, Vector2(cx - 78.0, 18.0), String(item.item_name))
		_label(stage, Vector2(cx - 78.0, 38.0), "drops %.2f%%  ->  %s" % [rate * 100.0, names[tier]])
		if beam == null and tier != 0:
			printerr("FAIL: tier %d but no beam built for %s" % [tier, item.item_name])

	await process_frame
	await process_frame

	var t0: int = Time.get_ticks_msec()
	var step: float = 1.0 / float(FPS)
	var taken: int = 0
	while true:
		await process_frame
		var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
		if elapsed < float(taken) * step:
			continue
		if elapsed > CAPTURE_S:
			break
		_sv.get_texture().get_image().save_png("%s/frame_%02d.png" % [OUT_DIR, taken])
		taken += 1
	print("RENDER_OK frames=%d dir=%s" % [taken, ProjectSettings.globalize_path(OUT_DIR)])
	quit()


func _label(parent: Node, at: Vector2, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_color_override(&"font_color", Color(0.82, 0.86, 0.82))
	parent.add_child(l)
