extends Node
## Runtime gate for the high-tier vein feedback: idle frames, hit-flash, strike
## recoil and the chop particle burst.
##
##   godot --path . --mode=client res://tools/verify_vein_fx.tscn
##
## Scene mode, not `-s`: MineableNode is an Area2D whose _ready() touches
## `$VisualState` and the physics layers, so it has to be instanced in a real
## tree. A `-s` SceneTree run has no autoloads and the script will not compile.
##
## This asserts BEHAVIOUR, not authoring. `verify_high_ore_tiers.gd` already
## checks the .tres fields are set; what it cannot see is whether the flash
## actually moves a pixel, whether the recoil settles back to rest, or whether
## the burst frees itself. A leak there costs a node per swing, forever.

const TIERS: Array[String] = ["dragon", "obsidian", "celestial", "astralite"]
const NODE_SCENE: String = "res://source/common/gameplay/maps/components/mineable_node.tscn"
const VEIN: String = "res://source/common/gameplay/maps/components/mineable_nodes/%s_vein.tres"

var _bad: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	# play_chop_effect() bails when it thinks it is the server, and a headless
	# tool run can carry an OfflineMultiplayerPeer that reports is_server()
	# true. Drop it so the client path is the one under test.
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null

	for tier: String in TIERS:
		await _check(tier)

	print("VEIN_FX bad=", _bad)
	if _bad > 0:
		push_error("vein FX check FAILED")
	get_tree().quit(0)


func _check(tier: String) -> void:
	var data: MineableNodeResource = load(VEIN % tier) as MineableNodeResource
	var node: Node = (load(NODE_SCENE) as PackedScene).instantiate()
	node.data = data
	add_child(node)
	await get_tree().process_frame

	var sprite: Sprite2D = node.get_node("Sprite2D") as Sprite2D
	var rest_modulate: Color = sprite.modulate
	var rest_offset: Vector2 = sprite.offset
	var problems: PackedStringArray = []

	# Snapshot everything the recoil must NOT disturb. The recoil drives the
	# sprite's `offset` precisely so these stay put — `_layout_from_texture`,
	# the click area and the chop-burst origin all read `_sprite.position`, so a
	# recoil applied there would drag the gather hitbox around under the cursor
	# on every swing. Snapshot rather than trust the comment.
	var hitbox: CollisionShape2D = node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var rest_sprite_pos: Vector2 = sprite.position
	var rest_hitbox_pos: Vector2 = hitbox.position if hitbox != null else Vector2.ZERO
	var rest_hitbox_size: Vector2 = Vector2.ZERO
	if hitbox != null and hitbox.shape is RectangleShape2D:
		rest_hitbox_size = (hitbox.shape as RectangleShape2D).size
	var click_areas: Array[Node] = []
	for child: Node in node.get_children():
		if child is Area2D:
			click_areas.append(child)
	var rest_click_pos: Array[Vector2] = []
	for area: Node in click_areas:
		rest_click_pos.append((area as Node2D).global_position)

	# --- authoring the runtime depends on ---
	if data.idle_frames.size() < 1:
		problems.append("no idle_frames")
	for frame: Texture2D in data.idle_frames:
		if frame == null or frame.get_size() != data.texture.get_size():
			problems.append("idle frame size != texture size (node will jitter)")
			break
	if data.hit_flash_strength <= 0.0:
		problems.append("hit_flash_strength is 0")
	if data.hit_recoil_pixels <= 0.0:
		problems.append("hit_recoil_pixels is 0")
	if data.chop_fx_style == &"":
		problems.append("no chop_fx_style")

	# The shipped flash is 0.12s, which a slow tool frame can step straight over
	# — the whole strike would begin and end inside one _tick_strike and nothing
	# would ever be observable. Stretch the window on a COPY so the same code
	# path is exercised with room to sample it, and design-check the real value
	# separately below.
	if data.hit_flash_seconds > 0.2:
		problems.append("hit_flash_seconds %.2f reads as a glow, not an impact"
			% data.hit_flash_seconds)
	var slow: MineableNodeResource = data.duplicate() as MineableNodeResource
	slow.hit_flash_seconds = 0.8
	node.data = slow

	# --- the strike itself ---
	node.play_chop_effect()
	var bursts: int = 0
	for child: Node in node.get_children():
		if child is CPUParticles2D:
			bursts += 1
	if bursts == 0:
		problems.append("no particle burst spawned")

	# Sample across the whole window rather than one frame: the recoil is a
	# damped bounce, so its offset legitimately passes back through zero
	# mid-flight and a single "is it moved yet" probe is a coin toss.
	var saw_flash: bool = false
	var saw_recoil: bool = false
	var hitbox_moved: bool = false
	var click_moved: bool = false
	var waited: float = 0.0
	while waited < 0.7:
		if not sprite.modulate.is_equal_approx(rest_modulate):
			saw_flash = true
		if not sprite.offset.is_equal_approx(rest_offset):
			saw_recoil = true
		# Sampled DURING the bounce, not just after it: a hitbox that drifts and
		# returns is still a hitbox that moved under the player mid-swing.
		if not sprite.position.is_equal_approx(rest_sprite_pos):
			hitbox_moved = true
		if hitbox != null:
			if not hitbox.position.is_equal_approx(rest_hitbox_pos):
				hitbox_moved = true
			if hitbox.shape is RectangleShape2D 					and not (hitbox.shape as RectangleShape2D).size.is_equal_approx(rest_hitbox_size):
				hitbox_moved = true
		for i: int in click_areas.size():
			if not (click_areas[i] as Node2D).global_position.is_equal_approx(rest_click_pos[i]):
				click_moved = true
		waited += await _tick()
	if hitbox_moved:
		problems.append("recoil displaced the gather hitbox / sprite position")
	if click_moved:
		problems.append("recoil displaced the click area")
	if not saw_flash:
		problems.append("flash never changed modulate")
	if not saw_recoil:
		problems.append("recoil never moved the sprite")

	# --- and it must settle back ---
	while waited < 2.0:
		waited += await _tick()
	if not sprite.offset.is_equal_approx(Vector2.ZERO):
		problems.append("recoil never settled (offset %s after %.1fs)" % [sprite.offset, waited])
	if not sprite.modulate.is_equal_approx(rest_modulate):
		problems.append("flash never cleared (modulate %s)" % sprite.modulate)

	# The one-shot emitters free themselves on a SceneTreeTimer; give them time
	# and then confirm nothing is left parented to the node.
	var slept: float = 0.0
	while slept < 1.5:
		slept += await _tick()
	var leaked: int = 0
	for child: Node in node.get_children():
		if child is CPUParticles2D:
			leaked += 1
	if leaked > 0:
		problems.append("%d particle emitter(s) leaked after the burst" % leaked)

	if problems.is_empty():
		print("ok %-10s flash %.2f, recoil %.1fpx, %s x%d, %d idle frame(s), %d burst(s), hitbox fixed" % [
			tier, data.hit_flash_strength, data.hit_recoil_pixels,
			data.chop_fx_style, data.chop_fx_amount, data.idle_frames.size(), bursts,
		])
	else:
		for problem: String in problems:
			push_error("%s: %s" % [tier, problem])
			print("  FAIL %s: %s" % [tier, problem])
		_bad += problems.size()

	node.queue_free()
	await get_tree().process_frame


func _tick() -> float:
	await get_tree().process_frame
	return get_process_delta_time()
