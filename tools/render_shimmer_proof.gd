extends Node
## Render the Celestial / Astralite shimmer at three points in its cycle so the
## in-game shine can be reviewed without launching a client.
##   godot --path . --mode=client res://tools/render_shimmer_proof.tscn

const OUT: String = "previews/shimmer-proof.png"
const SHADER: String = "res://source/common/gameplay/items/shimmer.gdshader"
const CELL: int = 96


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(CELL * 6, CELL * 4)
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(sv)

	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.10, 0.13)
	bg.size = Vector2(sv.size)
	sv.add_child(bg)

	var rows: Array = [
		["res://source/common/gameplay/maps/components/mineable_nodes/celestial_vein.tres", true],
		["res://source/common/gameplay/items/weapons/tools/pickaxe_celestial.tres", false],
		["res://source/common/gameplay/maps/components/mineable_nodes/astralite_vein.tres", true],
		["res://source/common/gameplay/items/weapons/tools/pickaxe_astralite.tres", false],
	]
	for row: int in rows.size():
		var res: Resource = load(rows[row][0])
		var is_vein: bool = rows[row][1]
		var tex: Texture2D = res.texture if is_vein else res.item_icon
		var mat: ShaderMaterial = res.shimmer_material()
		for col: int in 6:
			var sprite := Sprite2D.new()
			sprite.texture = tex
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2(2.0, 2.0)
			sprite.position = Vector2(CELL * col + CELL / 2.0, CELL * row + CELL / 2.0)
			# one material per column, offset to a fixed point in the cycle
			var phased: ShaderMaterial = mat.duplicate() as ShaderMaterial
			phased.set_shader_parameter(&"shimmer_phase", col * 4.0 / (6.0 * res.shimmer_speed))
			sprite.material = phased
			sv.add_child(sprite)

	for _f: int in 10:
		await get_tree().process_frame
	sv.get_texture().get_image().save_png(OUT)
	print("SAVED ", OUT)
	get_tree().quit(0)
