extends GroundCompanionPreset
## SNAIL. A snail that tries VERY hard to keep up. It creeps after the wearer at
## snail pace, leaving a glistening trail, and the moment it falls too far
## behind it vanishes in a puff of smoke and reappears right beside them - where
## it creeps on as if nothing happened.
##
## PROTOTYPE - not registered, no slot yet.
##
## The joke is the contrast, so the crawl is deliberately slow (a loose spring,
## no hop) and the poof is instant ([method CompanionPreset.teleport_to_target]),
## with a smoke puff left at BOTH ends so the jump reads as a magic trick.

## Past this far from its target it gives up crawling and poofs.
const POOF_PX: float = 34.0
const POOF_S: float = 0.45
const TRAIL_LIFE_S: float = 1.8

const SHELL: Color = Color(0.72, 0.46, 0.26)
const SHELL_DARK: Color = Color(0.46, 0.27, 0.14)
const SHELL_LIGHT: Color = Color(0.90, 0.68, 0.42)
const SLUG: Color = Color(0.72, 0.82, 0.64)
const SLUG_DARK: Color = Color(0.50, 0.62, 0.46)
const SLIME: Color = Color(0.80, 0.95, 1.0)
const SMOKE: Color = Color(0.86, 0.86, 0.92)

## World-space puffs: {"p", "t"}.
var _poofs: Array[Dictionary] = []
## World-space trail dots: {"p", "t"}.
var _trail: Array[Dictionary] = []
var _since_dot: float = 0.0


func _build() -> void:
	hop_peak = 0.0
	stiffness = 6.0
	damping = 5.0
	add_body_layer(_paint_snail, false, 0)
	var world: VfxDrawLayer = _add_draw_layer(_paint_world, false, -2)
	world.top_level = true
	# top_level draws ON TOP of everything at its own z, so a layer meant to be
	# under the wearer needs a z strictly below theirs (see
	# CompanionPreset.set_in_front).


func _tick(delta: float) -> void:
	super(delta)
	var s: float = global_scale.x
	var target: Vector2 = global_position + target_local(0.0) * s
	if body.global_position.distance_to(target) > POOF_PX * s:
		_poofs.append({"p": body.global_position, "t": 0.0})
		teleport_to_target()
		body.global_position = target
		_poofs.append({"p": target, "t": 0.0})
	_age(_poofs, delta, POOF_S)
	_age(_trail, delta, TRAIL_LIFE_S)
	# Slime: a dot every so often while it is crawling.
	_since_dot += delta
	if body_velocity().length() > 3.0 * s and _since_dot > 0.12:
		_since_dot = 0.0
		_trail.append({"p": body.global_position, "t": 0.0})


## Age every entry and drop the expired ones, in place. (Array.filter returns an
## untyped Array, which cannot be assigned back to an Array[Dictionary].)
func _age(list: Array[Dictionary], delta: float, life: float) -> void:
	for i: int in range(list.size() - 1, -1, -1):
		list[i]["t"] += delta
		if list[i]["t"] >= life:
			list.remove_at(i)


func _paint_world(layer: VfxDrawLayer) -> void:
	var s: float = global_scale.x
	for d: Dictionary in _trail:
		var k: float = 1.0 - float(d["t"]) / TRAIL_LIFE_S
		layer.draw_rect(Rect2((d["p"] as Vector2) - Vector2(1.5, 0.5) * s, Vector2(3.0, 1.0) * s), Color(SLIME, 0.45 * k))
	for d: Dictionary in _poofs:
		var k: float = float(d["t"]) / POOF_S
		var at: Vector2 = (d["p"] as Vector2) + Vector2(0, -4.0) * s
		for i: int in 5:
			var a: float = float(i) * TAU / 5.0 + 0.3
			var r: float = (2.0 + k * 7.0) * s
			layer.draw_circle(at + Vector2(cos(a), sin(a) * 0.7) * r, (3.0 - k * 2.0) * s, Color(SMOKE, 0.85 * (1.0 - k)))


func _paint_snail(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 6.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing, 1.0))
	# Body: a long foot with the head raised at the front, stretching as it creeps.
	var creep: float = 1.0 + 0.12 * sin(_elapsed * 5.0) * float(body_velocity().length() > 1.0)
	layer.draw_rect(Rect2(-6.0, -2.0, 12.0 * creep, 2.0), SLUG)
	layer.draw_rect(Rect2(-6.0, -1.0, 12.0 * creep, 1.0), SLUG_DARK)
	var head: Vector2 = Vector2(5.0 * creep, -3.0)
	layer.draw_circle(head, 2.2, SLUG)
	# Eye stalks with shiny eyes, bobbing a little out of step.
	for k: int in 2:
		var bob: float = sin(_elapsed * 3.0 + float(k)) * 0.5
		var tip: Vector2 = head + Vector2(-0.5 + float(k) * 2.0, -4.5 + bob)
		layer.draw_line(head + Vector2(float(k) - 0.5, -1.0), tip, SLUG_DARK, 1.0)
		var e: Vector2 = tip.round()
		layer.draw_rect(Rect2(e.x - 1.0, e.y - 1.0, 2.0, 2.0), FACE_DARK)
		layer.draw_rect(Rect2(e.x - 1.0, e.y - 1.0, 1.0, 1.0), FACE_SHINE)
	layer.draw_rect(Rect2(head.x - 0.5, head.y + 0.5, 1.0, 1.0), FACE_BLUSH)
	# Shell: a round spiral on its back.
	var c: Vector2 = Vector2(-1.0, -6.0)
	layer.draw_circle(c, 5.0, SHELL_DARK)
	layer.draw_circle(c + Vector2(-0.3, -0.3), 4.4, SHELL)
	layer.draw_arc(c, 2.8, 0.0, TAU * 0.8, 14, SHELL_DARK, 1.0)
	layer.draw_arc(c + Vector2(0.4, 0.2), 1.3, PI, PI + TAU * 0.7, 10, SHELL_DARK, 1.0)
	layer.draw_rect(Rect2(c.x - 3.0, c.y - 4.0, 2.0, 1.0), SHELL_LIGHT)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
