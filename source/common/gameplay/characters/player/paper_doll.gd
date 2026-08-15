class_name PaperDoll
extends Node2D
## Layered player appearance built from the Mana Seed character sheets.
##
## Every layer - body, outfit, cloak, hair, hat, weapon, offhand - is a plain
## [Sprite2D] reading a cell out of a 512x512 page. All of them share ONE frame
## index and ONE facing, so nothing can drift out of step.
##
## This node owns the player's animation outright rather than following the
## AnimationTree. That is deliberate: the tree's locomotion states only know
## idle/run/death and have no concept of facing, while these sheets are indexed by
## (facing, clip, frame). The old [AnimatedSprite2D] body is hidden for players.
##
## The old single-sprite body is hidden for players. The hand rig is NOT: it still
## draws the equipped weapon until the pack's 6tla weapon layer is wired (the pack
## indexes weapons by its own codes on the combat pages, not by gear-set name).
##
## Sheet layout (from the pack's own "using this base.txt", verified against the
## art):  rows 0-3 = standing per facing, rows 4-7 = walk/run per facing,
## row order DOWN, UP, RIGHT, LEFT.
##
## Client-only: the server holds appearance as ints and renders nothing.

const ROOT: String = "res://assets/sprites/characters/manaseed/"
## Per-tier armour, recoloured from the pack outfits by tools/paperdoll/recolor_gear.py
## so every named set (Astral Robe, Mithril Chest, ...) has its OWN look. The
## inventory icon is cropped from these same sheets, so worn and icon cannot diverge.
const GEAR_ROOT: String = "res://assets/sprites/characters/gear_tiers/"
const PAGE: String = "p1"

## Which pack layer each visible slot draws on. Order here is draw order.
const BODY_LAYER: StringName = &"0bas"

enum Clip { STAND, WALK, RUN }

var character: Character

## layer -> Sprite2D. Keys are the pack's own layer codes (1out, 4har, ...).
var _layers: Dictionary[StringName, Sprite2D] = {}
var _body: Sprite2D

var _facing: int = PaperDollData.Facing.DOWN
var _clip: Clip = Clip.STAND
var _frame: int = 0
var _frame_time: float = 0.0

## Shared across every paper-doll in the instance: a crowded hub is many players
## wearing a handful of distinct sheets, so this collapses to a few loads.
static var _texture_cache: Dictionary[String, Texture2D] = {}


func _ready() -> void:
	if character == null:
		character = get_parent() as Character
	if character == null:
		push_warning("PaperDoll has no Character parent; disabling.")
		set_process(false)
		return
	if multiplayer != null and multiplayer.is_server():
		set_process(false)
		return
	_build_layers()
	# These sheets draw the whole body, so the old single-sprite body is retired.
	character.animated_sprite.visible = false
	# The hand rig is hidden the moment a weapon resolves to a pack sheet; it stays
	# for wands/books, which the packs do not cover. _sync_hand_rig owns this.
	set_process(true)


func _build_layers() -> void:
	_body = _make_sprite(0)
	for i: int in PaperDollData.LAYER_ORDER.size():
		var layer: StringName = PaperDollData.LAYER_ORDER[i]
		_layers[layer] = _make_sprite(i + 1)


func _make_sprite(z: int) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.centered = true
	# Match the body the rest of the game positions against: character.tscn draws
	# its sprite at offset (0,-30), which puts the feet on the last row of the cell.
	sprite.offset = character.animated_sprite.offset
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.z_index = z
	sprite.visible = false
	add_child(sprite)
	return sprite


# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if character == null:
		return
	var clip: Clip = _clip_for(character.anim)
	var facing: int = _facing_from_pivot(character.pivot)
	if clip != _clip:
		_clip = clip
		_frame = 0
		_frame_time = 0.0
	_facing = facing

	if _clip == Clip.STAND:
		_frame = 0
	else:
		_advance(delta)
	_paint()


func _clip_for(anim: int) -> Clip:
	# These sheets have no death clip, so a dead player holds the standing pose;
	# the death read comes from Character's own tint/fade handling.
	match anim:
		Character.Animations.RUN:
			return Clip.WALK
		_:
			return Clip.STAND


## Advance the frame timer. Run uses the pack's uneven 80/55/125 timing - even
## spacing makes the two borrowed run frames read as a stumble.
func _advance(delta: float) -> void:
	var count: int = _cols().size()
	if count <= 0:
		return
	_frame_time += delta
	var hold: float = _hold_for(_frame)
	while _frame_time >= hold:
		_frame_time -= hold
		_frame = (_frame + 1) % count
		hold = _hold_for(_frame)


func _hold_for(index: int) -> float:
	if _clip == Clip.RUN:
		var times: Array = PaperDollData.RUN_FRAME_TIMES
		return float(times[index % times.size()])
	return PaperDollData.WALK_FRAME_TIME


func _cols() -> Array:
	match _clip:
		Clip.WALK:
			return PaperDollData.WALK_COLS
		Clip.RUN:
			return PaperDollData.RUN_COLS
		_:
			return [PaperDollData.STAND_COL]


## Four-way facing from the already-synced aim angle. Deriving it costs nothing on
## the wire and means remote players face correctly with no extra property: pivot
## is replicated for every visible character already.
static func _facing_from_pivot(pivot: float) -> int:
	var angle: float = wrapf(pivot, -PI, PI)
	if angle >= -PI * 0.25 and angle < PI * 0.25:
		return PaperDollData.Facing.RIGHT
	if angle >= PI * 0.25 and angle < PI * 0.75:
		return PaperDollData.Facing.DOWN
	if angle >= -PI * 0.75 and angle < -PI * 0.25:
		return PaperDollData.Facing.UP
	return PaperDollData.Facing.LEFT


func _paint() -> void:
	var size: int = PaperDollData.FRAME_SIZE
	var cols: Array = _cols()
	var col: int = int(cols[clampi(_frame, 0, cols.size() - 1)])
	var row: int = _facing + (
		PaperDollData.STAND_ROW_BASE if _clip == Clip.STAND
		else PaperDollData.WALK_ROW_BASE
	)
	var region: Rect2 = Rect2(col * size, row * size, size, size)

	_body.region_rect = region
	_body.visible = _body.texture != null
	for layer: StringName in _layers:
		var sprite: Sprite2D = _layers[layer]
		sprite.region_rect = region
		sprite.visible = sprite.texture != null


# ---------------------------------------------------------------------------
# Appearance
# ---------------------------------------------------------------------------

## Resolve a packed appearance into pack item codes. Shared with the creator
## preview so both agree on what a stored value means.
static func resolve_appearance(packed: int) -> Dictionary:
	return {
		&"body": _pick(PaperDollData.BODY_VARIANTS, packed & 0xFF),
		&"hair_style": _pick(PaperDollData.HAIR_STYLES, (packed >> 8) & 0xFF),
		&"hair_color": _pick(PaperDollData.HAIR_COLORS, (packed >> 16) & 0xFF),
		&"outfit": _pick(PaperDollData.OUTFITS, (packed >> 24) & 0xFF),
	}


static func _pick(roster: Array[StringName], index: int) -> StringName:
	if roster.is_empty():
		return &""
	return roster[clampi(index, 0, roster.size() - 1)]


## Path to one sheet. Every caller goes through here so the naming convention
## lives in exactly one place.
static func sheet_path(layer: StringName, item: StringName, variant: StringName) -> String:
	return "%s%s/char_a_%s_%s_%s_v%s.png" % [ROOT, layer, PAGE, layer, item, variant]


static func load_sheet(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_texture_cache[path] = texture
	return texture


## Best available variant for an item: the creator's colour index, clamped to the
## variants that item actually ships (hair styles differ - pon1 has 13, others 14).
static func variant_for(layer: StringName, item: StringName, index: int) -> StringName:
	var key: StringName = StringName("%s/%s" % [layer, item])
	var variants: Array = PaperDollData.VARIANTS.get(key, [])
	if variants.is_empty():
		return &"00"
	return variants[clampi(index, 0, variants.size() - 1)]


func apply_appearance(packed: int) -> void:
	if character == null or (multiplayer != null and multiplayer.is_server()):
		return
	var look: Dictionary = resolve_appearance(packed)
	var hair_index: int = (packed >> 16) & 0xFF
	var outfit_index: int = (packed >> 24) & 0xFF

	_body.texture = load_sheet(
		sheet_path(BODY_LAYER, &"humn", look[&"body"])
	)
	_set_layer(
		&"4har",
		look[&"hair_style"],
		variant_for(&"4har", look[&"hair_style"], hair_index)
	)
	# The chosen outfit is the character's "clothes" - armour overrides this layer
	# when worn (see set_gear), and returns to it when stripped.
	_default_outfit = look[&"outfit"]
	_default_outfit_variant = variant_for(&"1out", look[&"outfit"], outfit_index)
	if not _gear.has(&"torso"):
		_set_layer(&"1out", _default_outfit, _default_outfit_variant)


## The creator-chosen clothes, restored whenever body armour comes off.
var _default_outfit: StringName = &""
var _default_outfit_variant: StringName = &"01"
## slot -> true while armour is overriding that layer.
var _gear: Dictionary[StringName, bool] = {}


func _set_layer(layer: StringName, item: StringName, variant: StringName) -> void:
	if not _layers.has(layer):
		return
	if item == &"":
		_layers[layer].texture = null
		return
	var texture: Texture2D = load_sheet(sheet_path(layer, item, variant))
	if texture == null:
		push_warning("PaperDoll: missing sheet %s/%s v%s" % [layer, item, variant])
	_layers[layer].texture = texture


func _clear_layer(layer: StringName) -> void:
	if _layers.has(layer):
		_layers[layer].texture = null


# ---------------------------------------------------------------------------
# Equipment
# ---------------------------------------------------------------------------

## Slots that map onto a drawn layer, and which pack layer each uses.
## Slots that map onto a drawn layer today.
##
## Weapons map through WeaponItem.appearance_item, which keys off mastery category
## (sword/hammer/bow). Wands and books have no pack equivalent and fall back to the
## hand rig - see [method set_gear].
## `helmet` is deliberately absent. The packs ship no helmets - only a bandana,
## hood, bonnet, straw hat, wizard hat and rain hat. Recolouring a straw hat and
## calling it a Mithril Helmet is the same icon-vs-worn incoherence this system
## exists to remove, and it visually sliced the head. Better to draw nothing than
## something wrong; add the row back here the moment real helmet art lands.
const GEAR_LAYERS: Dictionary = {
	&"torso": &"1out",
	&"weapon": &"6tla",
}

## Extra pieces a torso set can bring with it, generated per tier by
## tools/paperdoll/recolor_gear.py. Absent files simply leave the layer empty, so a
## family with no mantle or hood costs nothing.
const GEAR_PARTS: Dictionary = {
	&"cloak": &"2clo",
	&"hood": &"5hat",
}


## Path to a recoloured per-tier armour sheet.
static func gear_sheet_path(tier: StringName, slot: StringName) -> String:
	return "%s%s_%s.png" % [GEAR_ROOT, tier, slot]


## Show [param slot]'s gear. For armour [param item] is the TIER slug (&"astral",
## &"mithril") and the sheet is the recoloured per-tier one; for weapons it is a
## pack code plus [param variant]. An empty item strips the slot.
func set_gear(slot: StringName, item: StringName, variant: StringName) -> void:
	if not GEAR_LAYERS.has(slot):
		return
	if multiplayer != null and multiplayer.is_server():
		return
	var layer: StringName = GEAR_LAYERS[slot]
	if item == &"":
		_gear.erase(slot)
		# Taking body armour off puts the creator's clothes back on, rather than
		# leaving the character naked.
		if slot == &"torso" and _default_outfit != &"":
			_set_layer(&"1out", _default_outfit, _default_outfit_variant)
			for part_layer: StringName in GEAR_PARTS.values():
				_clear_layer(part_layer)
		else:
			_clear_layer(layer)
		_sync_hand_rig()
		return
	_gear[slot] = true
	if slot == &"weapon":
		_set_layer(layer, item, variant)
	else:
		# A gear SET, not one garment: the torso sheet plus whatever parts that
		# family ships (mantle for heavy, hood + cloak for ranger and mage). All
		# recoloured from the same ramp, so they read as one outfit.
		_layers[layer].texture = load_sheet(gear_sheet_path(item, slot))
		for part: StringName in GEAR_PARTS:
			var part_layer: StringName = GEAR_PARTS[part]
			if _layers.has(part_layer):
				_layers[part_layer].texture = load_sheet(gear_sheet_path(item, part))
	_sync_hand_rig()


## The old hand rig only draws when the paper-doll cannot: wands and books have no
## Mana Seed equivalent, so they keep the rig rather than showing no weapon at all.
## Everything else is drawn in-hand by the sheets, per frame, per direction.
func _sync_hand_rig() -> void:
	if character == null or character.hand_offset == null:
		return
	character.hand_offset.visible = not _gear.has(&"weapon")
