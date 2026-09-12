extends ThemeAuraPreset
## CRIMSON EMBERS. The matching aura for the Crimson Warlord title: a lit forge
## ring with embers lifting off it and ash settling back down.
##
##   RING    the shared theme circle, at full weight - this is a loud aura.
##   COALS   eight hot spots on the ring, each breathing on its own cycle, so the
##           circle looks like banked coals rather than a drawn line.
##   EMBERS  motes rising fast and dying young, in the dye and its ember accent.
##   ASH     slow grey-red flakes falling back through them. MIX blended: ash is
##           dark, and additive dark is invisible.

const COAL_COUNT: int = 8
## Seconds for one coal to brighten and fade. Long and offset per coal so the ring
## never pulses in unison, which would read as a cooldown.
const COAL_PERIOD_S: float = 2.6


func theme() -> StringName:
	return CosmeticThemes.CRIMSON


func _build() -> void:
	_build_embers()
	_build_ash()


## Rising embers. Short lives and upward gravity: an ember that falls reads as a
## spark from a grinder, and one that lingers reads as a firefly.
func _build_embers() -> void:
	var p: CPUParticles2D = _add_emitter(14, 1.6, VfxTextures.dot(5))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(12, BASE_RADIUS * 0.9)
	p.direction = Vector2(0, -1)
	p.spread = 22.0
	p.gravity = Vector2(0, -20.0)
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 30.0
	p.damping_min = 3.0
	p.damping_max = 9.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	p.color_ramp = _swell_ramp(accent(), Color(pale(), 1.0), 0.16)
	p.material = _additive()


## Ash falling back through the embers - the layer that makes the fire look like
## it has been burning a while.
func _build_ash() -> void:
	var p: CPUParticles2D = _add_emitter(10, 2.8, VfxTextures.puff(10))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _arc_points(8, BASE_RADIUS * 1.05, 0.0, TAU)
	# Shed from chest height, not off the floor: ash that starts at the feet and
	# falls has nowhere to go and piles up in the ring.
	p.position = Vector2(0.0, CHEST_Y)
	p.direction = Vector2(0, 1)
	p.spread = 50.0
	p.gravity = Vector2(3.0, 10.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 8.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	p.color_ramp = _fade_ramp(deep(), 0.55)
	# No _additive() here, deliberately. See the class docs.


func _draw() -> void:
	_use_ground_plane()
	draw_theme_ring()
	_draw_coals()


## Hot spots banked around the ring. Drawn as three stacked discs each - a hot
## pale core inside the dye inside a dim halo - which is the cheapest thing that
## reads as glowing coal rather than as a coloured dot.
func _draw_coals() -> void:
	for i: int in COAL_COUNT:
		var offset: float = float(i) / float(COAL_COUNT)
		var phase: float = fposmod(_elapsed / COAL_PERIOD_S + offset * 0.73, 1.0)
		# Brighten quickly, cool slowly. A symmetric curve looks mechanical.
		var heat: float = smoothstep(0.0, 0.18, phase) * (1.0 - smoothstep(0.35, 1.0, phase))
		if heat <= 0.03:
			continue
		var at: Vector2 = _ground_point(ring_spin() + offset * TAU, BASE_RADIUS * 0.96)
		draw_circle(at, 4.2, Color(deep(), 0.30 * heat))
		draw_circle(at, 2.4, Color(core(), 0.75 * heat))
		draw_circle(at, 1.2, Color(pale(), 0.95 * heat))
