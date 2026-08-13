class_name WeaponVfx
extends AnimatedSprite2D
## Client-only glow overlay for an Ascended weapon, mounted as a CHILD of the
## weapon's own Sprite2D.
##
## Being a child is the whole trick: the overlay inherits the sprite's position,
## rotation and scale, so it stays glued to the blade through the -45° square-icon
## grip rotation (Weapon._apply_square_icon_grip) AND through the hand pivot as the
## player aims. Nothing here has to know about aim at all.
##
## The effect textures are 48x48 against 32x32 art, so light spills past the blade;
## both are centred, so they line up with no offset.
const FX_ANIM: StringName = &"loop"


func _init() -> void:
	# Behind the weapon art (z_index is relative to the parent sprite by default).
	# Glow in front washes the blade out — the same mistake the aura pass made.
	z_index = -1
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func apply(frames: SpriteFrames) -> void:
	if frames == null:
		visible = false
		stop()
		return
	sprite_frames = frames
	visible = true
	if frames.has_animation(FX_ANIM):
		play(FX_ANIM)
