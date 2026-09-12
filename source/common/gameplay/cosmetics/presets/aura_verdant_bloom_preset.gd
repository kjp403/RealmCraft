extends ThemeAuraPreset
## VERDANT BLOOM. The matching aura for the Verdant Warden title: a quiet green
## ring with grass at its edge and leaves lifting off it.
##
## THE QUIETEST OF THE EIGHT, on purpose and priced accordingly. It is the one a
## player wears for a whole session rather than for a screenshot, so the ring is
## drawn at reduced weight and nothing here flashes, pulses hard or moves fast.
## The existing Verdant aura next door is the loud floral version; this is the
## same colour with the volume down, which is what makes them worth owning both.
##
##   RING    the shared theme circle at half weight.
##   BLADES  grass standing around the rim, swaying as one field.
##   LEAVES  tumbling up and away.
##   POLLEN  fine motes between them.

const BLADE_COUNT: int = 14
## Radians of sway. Small: grass that waves reads as wind, grass that thrashes
## reads as a storm effect and this aura is not one.
const SWAY: float = 0.22


func theme() -> StringName:
	return CosmeticThemes.VERDANT


func _build() -> void:
	_build_leaves()
	_build_pollen()


## Leaves shed from the rim. Tumbling is what makes a leaf a leaf rather than a
## green pip, so the angular range is wide and symmetric.
func _build_leaves() -> void:
	var p: CPUParticles2D = _add_emitter(8, 2.6, VfxTextures.leaf(9))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(8, BASE_RADIUS * 0.95)
	p.direction = Vector2(-1, -0.6)
	p.spread = 50.0
	p.gravity = Vector2(-5.0, -8.0)
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 16.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.angular_velocity_min = -120.0
	p.angular_velocity_max = 120.0
	p.color_ramp = _swell_ramp(core(), Color(core(), 0.9), 0.2)
	# Matte. Additive would make a leaf glow, which is the one thing a leaf must
	# never do.


## Pollen: many, tiny, dim, slow. The layer nobody notices, and the one that makes
## the space between the blades feel occupied.
func _build_pollen() -> void:
	var p: CPUParticles2D = _add_emitter(14, 3.0, VfxTextures.dot(5))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(12, BASE_RADIUS * 0.8)
	p.direction = Vector2(0, -1)
	p.spread = 45.0
	p.gravity = Vector2(0, -5.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 8.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	p.color_ramp = _swell_ramp(accent(), Color(accent(), 0.5), 0.32)
	p.material = _additive() # motes of light, not specks of paint


func _draw() -> void:
	_use_ground_plane()
	draw_theme_ring(0.5)
	_draw_blades()


## Grass around the rim. All blades share ONE sway term with a per-blade phase
## offset, so the field moves together like grass in wind instead of each blade
## having its own weather.
func _draw_blades() -> void:
	_use_upright_plane()
	var wind: float = sin(_elapsed * 0.9)
	for i: int in BLADE_COUNT:
		var offset: float = float(i) / float(BLADE_COUNT)
		var angle: float = offset * TAU
		var foot: Vector2 = _ground_point(angle, BASE_RADIUS * (0.88 + 0.14 * sin(offset * 17.0)))
		# Height varies per blade from its own index, so the rim is a ragged edge
		# rather than a haircut.
		var height: float = 5.0 + 4.0 * fposmod(offset * 7.0, 1.0)
		var bend: float = (wind + sin(offset * 11.0)) * SWAY * height * 0.5
		var tip: Vector2 = foot + Vector2(bend, -height)
		# Far-side blades are dimmer: the same near-side term the sigils use.
		var near: float = 0.45 + 0.55 * (0.5 + 0.5 * sin(angle))
		draw_line(foot, tip, Color(core(), 0.55 * near), 1.0)
		draw_line(foot.lerp(tip, 0.55), tip, Color(accent(), 0.45 * near), 1.0)
