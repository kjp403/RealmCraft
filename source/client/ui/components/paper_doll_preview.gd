class_name PaperDollPreview
extends Control
## A live, animated preview of a layered character for UI with no Character node:
## the character creator, the wardrobe, character select.
##
## Builds the same layer stack from the same sheets as [PaperDoll] (via that class's
## path helpers), so what the creator shows is what spawns in the world. The only
## difference is the driver: here a local timer loops the clip, and the facing is
## whatever the UI asks for rather than derived from an aim angle.

## Which way the preview faces. DOWN shows the face, which is what a creator wants.
@export var facing: int = PaperDollData.Facing.DOWN:
	set(value):
		facing = value
		_repaint()

## Loop the walk cycle rather than standing still.
@export var walking: bool = true:
	set(value):
		walking = value
		_frame = 0
		_repaint()

## Whole-number upscale: the art is 64x64 pixel-art, so a fractional zoom shimmers.
@export var zoom: int = 3:
	set(value):
		zoom = maxi(1, value)
		_apply_zoom()

var _root: Node2D
var _body: Sprite2D
var _layers: Dictionary[StringName, Sprite2D] = {}
var _appearance: int = 0
var _gear: Dictionary[StringName, Array] = {}
var _frame: int = 0
var _frame_time: float = 0.0


func _ready() -> void:
	clip_contents = true
	_root = Node2D.new()
	add_child(_root)
	_body = _make_sprite(0)
	for i: int in PaperDollData.LAYER_ORDER.size():
		_layers[PaperDollData.LAYER_ORDER[i]] = _make_sprite(i + 1)
	resized.connect(_apply_zoom)
	_apply_zoom()
	_refresh()
	set_process(true)


func _make_sprite(z: int) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.z_index = z
	sprite.visible = false
	_root.add_child(sprite)
	return sprite


func _apply_zoom() -> void:
	if _root == null:
		return
	_root.scale = Vector2(zoom, zoom)
	# Centre the FIGURE, not the cell. The art sits low in its 64px cell (feet near
	# the last row), so centring the cell drops the body out of the control.
	var frame: float = float(PaperDollData.FRAME_SIZE)
	_root.position = Vector2(size.x * 0.5, size.y * 0.5 + frame * 0.22 * zoom)


func _process(delta: float) -> void:
	if not walking:
		return
	_frame_time += delta
	if _frame_time < PaperDollData.WALK_FRAME_TIME:
		return
	_frame_time = 0.0
	_frame = (_frame + 1) % PaperDollData.WALK_COLS.size()
	_repaint()


func set_appearance(packed: int) -> void:
	_appearance = packed
	_refresh()


## slot -> [item_code, variant]; an empty item strips the slot.
func set_gear(slot: StringName, item: StringName, variant: StringName) -> void:
	if item == &"":
		_gear.erase(slot)
	else:
		_gear[slot] = [item, variant]
	_refresh()


func _refresh() -> void:
	if _body == null:
		return
	var look: Dictionary = PaperDoll.resolve_appearance(_appearance)
	var hair_index: int = (_appearance >> 16) & 0xFF
	var outfit_index: int = (_appearance >> 24) & 0xFF

	_body.texture = PaperDoll.load_sheet(
		PaperDoll.sheet_path(PaperDoll.BODY_LAYER, &"humn", look[&"body"])
	)
	_mount(&"4har", look[&"hair_style"],
		PaperDoll.variant_for(&"4har", look[&"hair_style"], hair_index))

	# Armour overrides the creator's clothes on the same layer.
	var torso: Array = _gear.get(&"torso", [])
	if torso.is_empty():
		_mount(&"1out", look[&"outfit"],
			PaperDoll.variant_for(&"1out", look[&"outfit"], outfit_index))
	else:
		_mount(&"1out", torso[0], torso[1])

	for slot: StringName in PaperDoll.GEAR_LAYERS:
		if slot == &"torso":
			continue
		var layer: StringName = PaperDoll.GEAR_LAYERS[slot]
		var entry: Array = _gear.get(slot, [])
		if entry.is_empty():
			_layers[layer].texture = null
		else:
			_mount(layer, entry[0], entry[1])
	_repaint()


func _mount(layer: StringName, item: StringName, variant: StringName) -> void:
	if not _layers.has(layer):
		return
	_layers[layer].texture = (
		null if item == &"" else PaperDoll.load_sheet(PaperDoll.sheet_path(layer, item, variant))
	)


func _repaint() -> void:
	if _body == null:
		return
	var size_px: int = PaperDollData.FRAME_SIZE
	var col: int = 0
	var row: int = facing + PaperDollData.STAND_ROW_BASE
	if walking:
		var cols: Array = PaperDollData.WALK_COLS
		col = int(cols[clampi(_frame, 0, cols.size() - 1)])
		row = facing + PaperDollData.WALK_ROW_BASE
	var region: Rect2 = Rect2(col * size_px, row * size_px, size_px, size_px)
	_body.region_rect = region
	_body.visible = _body.texture != null
	for layer: StringName in _layers:
		var sprite: Sprite2D = _layers[layer]
		sprite.region_rect = region
		sprite.visible = sprite.texture != null
