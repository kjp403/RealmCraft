extends CosmeticPreset
## PAPARAZZI. Camera flashes go off around the wearer in bursts, as if a crowd of
## photographers just out of frame cannot get enough of them, and each flash
## lights the wearer up for an instant.
##
## PROTOTYPE - unregistered. Aura slot.
##
## BURSTS, NOT A STEADY TWINKLE. A photographer pack fires several shots close
## together, then pauses, then starts again; flashes on an even beat read as a
## sparkle aura and the joke is gone. So a burst clock picks a burst, and inside
## it a handful of flashes land at uneven offsets.
##
## All deterministic from the preset's own clock (no RNG), so a render tool
## captures exactly what plays, and two wearers are out of phase because each
## preset starts its own clock when it mounts.
##
##   FLASHES  additive star + disc at a spot round the wearer, ~0.1 s each.
##   LIT      the wearer's own current frame, redrawn additive over the body on
##            each flash, so exactly their pixels light up. (A disc of light was
##            tried first and read as a bubble round them.)

const BURST_PERIOD_S: float = 2.4
## Flash start times inside a burst, in seconds from the burst start.
const SHOTS: Array[float] = [0.0, 0.13, 0.22, 0.41, 0.52, 0.78]
const FLASH_S: float = 0.1
const WHITE: Color = Color(1.0, 1.0, 0.96)
const WARM: Color = Color(0.85, 0.92, 1.0)

var _lit_copy: Sprite2D

## Render-tool seam, as on [TrailChronoEchoPreset].
var sprite_source: AnimatedSprite2D


func _build() -> void:
	_add_draw_layer(_paint_back, true, 0)
	_add_draw_layer(_paint_front, true, 2)
	_lit_copy = Sprite2D.new()
	_lit_copy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_lit_copy.material = _additive()
	_lit_copy.z_index = 2
	_lit_copy.visible = false
	add_child(_lit_copy)


func _tick(_delta: float) -> void:
	var lit: float = 0.0
	for f: Array in _live_flashes():
		lit = maxf(lit, f[1])
	var source: AnimatedSprite2D = _source()
	if lit <= 0.0 or source == null or source.sprite_frames == null:
		_lit_copy.visible = false
		return
	_lit_copy.visible = true
	_lit_copy.texture = source.sprite_frames.get_frame_texture(source.animation, source.frame)
	_lit_copy.offset = source.offset
	_lit_copy.flip_h = source.flip_h
	_lit_copy.modulate = Color(1.0, 1.0, 1.0, 0.55 * lit)


func _source() -> AnimatedSprite2D:
	if is_instance_valid(sprite_source):
		return sprite_source
	if wearer == null or not is_instance_valid(wearer):
		return null
	return wearer.animated_sprite


## Every flash currently up, as [position, strength 0..1].
func _live_flashes() -> Array:
	var out: Array = []
	var burst: float = floor(_elapsed / BURST_PERIOD_S)
	var t: float = _elapsed - burst * BURST_PERIOD_S
	# Not every burst fires every shot - vary the pack size burst to burst.
	var shots: int = 3 + int(fposmod(sin(burst * 17.3) * 997.0, 1.0) * 3.99)
	for s: int in mini(shots, SHOTS.size()):
		var since: float = t - SHOTS[s]
		if since < 0.0 or since > FLASH_S:
			continue
		var salt: float = burst * 13.7 + float(s) * 5.3
		# Round the wearer on a wide ellipse, at camera heights (knee to above head).
		var angle: float = fposmod(sin(salt) * 437.0, TAU)
		var reach: float = 30.0 + fposmod(sin(salt * 1.9) * 91.0, 1.0) * 14.0
		var height: float = -8.0 - fposmod(sin(salt * 2.3) * 53.0, 1.0) * 40.0
		var at: Vector2 = Vector2(cos(angle) * reach, height + sin(angle) * reach * 0.35)
		out.append([at, 1.0 - since / FLASH_S])
	return out


func _paint_back(layer: VfxDrawLayer) -> void:
	for f: Array in _live_flashes():
		var at: Vector2 = f[0]
		if at.y + 20.0 > 0.0 and absf(at.x) < 12.0:
			continue   # a flash right in front of the body is drawn by the front pass
		_flash(layer, at, f[1])


func _paint_front(layer: VfxDrawLayer) -> void:
	for f: Array in _live_flashes():
		var at: Vector2 = f[0]
		if at.y + 20.0 > 0.0 and absf(at.x) < 12.0:
			_flash(layer, at, f[1])


func _flash(layer: VfxDrawLayer, at: Vector2, strength: float) -> void:
	var k: float = strength * strength
	layer.draw_circle(at, 7.0, Color(WARM, 0.18 * k))
	layer.draw_circle(at, 3.0, Color(WHITE, 0.8 * k))
	var arm: float = 5.0 + 5.0 * strength
	layer.draw_line(at - Vector2(arm, 0.0), at + Vector2(arm, 0.0), Color(WHITE, 0.9 * k), 1.0)
	layer.draw_line(at - Vector2(0.0, arm), at + Vector2(0.0, arm), Color(WHITE, 0.9 * k), 1.0)
