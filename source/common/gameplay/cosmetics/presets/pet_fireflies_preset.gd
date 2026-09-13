extends CosmeticTrailPreset
## FIREFLY SWARM. A handful of fireflies that stream along behind the wearer
## while they move and drift out into a slow glowing cloud round them when they
## stop, each one blinking on its own rhythm.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## NOT A [CompanionPreset]. That base flies ONE body on one spring; a swarm is
## many bodies, each on its own spring with its own stiffness, and that spread
## is the effect - the stiff ones keep up, the loose ones straggle, and the
## group stretches into a stream on a run and bunches up on a stop with no
## flocking code at all.
##
## Each fly is drawn, not emitted: a firefly's blink is its identity, and a
## particle's colour ramp can only fade once over its life, never pulse.

const FLIES: int = 8
const GLOW: Color = Color(0.80, 1.0, 0.35)
const CORE: Color = Color(1.0, 1.0, 0.75)
const IDLE_AFTER_S: float = 0.6

## Per fly: {"pos", "vel", "k" stiffness, "phase", "blink"}.
var _flies: Array[Dictionary] = []
var _still_for: float = 0.0
var _layer_back: VfxDrawLayer
var _layer_front: VfxDrawLayer


func _build() -> void:
	for i: int in FLIES:
		_flies.append({
			"pos": Vector2.ZERO, "vel": Vector2.ZERO, "placed": false,
			"k": lerpf(18.0, 55.0, _hash(i, 1.0)),
			"phase": _hash(i, 2.0) * TAU,
			"blink": lerpf(1.1, 2.3, _hash(i, 3.0)),
		})
	# World-space layers: each fly holds its own world position.
	_layer_back = _add_draw_layer(_paint_back, true, -2)
	_layer_back.top_level = true
	# top_level draws ON TOP of everything at its own z, so a layer meant to be
	# under the wearer needs a z strictly below theirs (see
	# CompanionPreset.set_in_front).
	_layer_front = _add_draw_layer(_paint_front, true, 2)
	_layer_front.top_level = true


func _hash(i: int, salt: float) -> float:
	return fposmod(sin(float(i) * 127.1 + salt * 311.7) * 43758.5453, 1.0)


## Where fly [param i] wants to be, in the wearer's local space, and whether that
## spot is in front of the body.
func _home(i: int) -> Array:
	var t: float = _elapsed * lerpf(0.25, 0.5, _hash(i, 4.0)) + _hash(i, 5.0) * TAU
	if _still_for < IDLE_AFTER_S:
		# Moving: a loose knot behind the shoulder.
		var knot: Vector2 = Vector2(cos(t * 3.0), sin(t * 2.3)) * 6.0
		return [Vector2(0, -30) - _heading * 12.0 + knot, true]
	# Still: spread out round the wearer on their own slow orbits.
	var r: float = lerpf(14.0, 28.0, _hash(i, 6.0))
	var y: float = lerpf(-10.0, -46.0, _hash(i, 7.0)) + sin(t * 1.7) * 3.0
	return [Vector2(cos(t) * r, y + sin(t) * r * 0.3), sin(t) > 0.0]


func _tick(delta: float) -> void:
	super(delta)
	_still_for = 0.0 if is_moving() else _still_for + delta
	var s: Vector2 = global_scale
	for i: int in FLIES:
		var fly: Dictionary = _flies[i]
		var home: Array = _home(i)
		var target: Vector2 = global_position + (home[0] as Vector2) * s
		if not fly["placed"]:
			fly["pos"] = target
			fly["placed"] = true
		var k: float = fly["k"]
		var accel: Vector2 = (target - fly["pos"]) * k - (fly["vel"] as Vector2) * (sqrt(k) * 1.2)
		fly["vel"] += accel * delta
		fly["pos"] += (fly["vel"] as Vector2) * delta
		fly["front"] = home[1]


func _paint_back(layer: VfxDrawLayer) -> void:
	_paint_flies(layer, false)


func _paint_front(layer: VfxDrawLayer) -> void:
	_paint_flies(layer, true)


func _paint_flies(layer: VfxDrawLayer, front: bool) -> void:
	var s: float = global_scale.x
	for fly: Dictionary in _flies:
		if bool(fly.get("front", true)) != front:
			continue
		# A firefly blink: mostly dim, a quick swell to bright, then back.
		var cycle: float = fposmod(_elapsed / float(fly["blink"]) + float(fly["phase"]) / TAU, 1.0)
		var on: float = pow(maxf(0.0, sin(cycle * PI)), 6.0)
		var at: Vector2 = fly["pos"]
		layer.draw_circle(at, 5.0 * s, Color(GLOW, 0.14 * on))
		layer.draw_circle(at, 2.5 * s, Color(GLOW, 0.35 * on))
		layer.draw_circle(at, 1.0 * s, Color(CORE, 0.4 + 0.6 * on))
