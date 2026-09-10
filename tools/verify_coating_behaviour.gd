@tool
extends Node
## Behaviour probe for weapon coatings: drinks the real potions on a real
## Player + PlayerResource, then walks CoatingService's state machine, the
## one-at-a-time rule, and the on-hit handoff for all three effect kinds.
##
## Same construction trick verify_ammo_equip.gd uses — a live Player without a
## live server. Static shape lives in verify_weapon_coatings.gd; this one is
## about what a coating actually DOES.
##
## Run: godot --headless --path . --mode=client res://tools/verify_coating_behaviour.tscn

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_test_drinking()
	_test_one_at_a_time()
	_test_draught_slot()
	_test_poison_on_hit()
	_test_burn_on_hit()
	_test_heal_on_hit()
	_test_salve_stacks()
	_test_expiry()

	print("")
	print("PASS %d  FAIL %d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


## A fresh player with an empty bag and no coating.
##
## Character.stats_component is `@onready var ... = $StatsComponent`, so a bare
## Player.new() has none and anything touching health explodes. Attaching a real
## StatsComponent under that exact name BEFORE add_child is what makes the
## @onready resolve — cheaper and more honest than instantiating the whole
## player scene, which drags in the client input rig.
func _make_player(health_max: float = 100.0) -> Player:
	var player: Player = Player.new()
	var resource: PlayerResource = PlayerResource.new()
	resource.level = 99
	player.player_resource = resource
	var stats: StatsComponent = StatsComponent.new()
	stats.name = "StatsComponent"
	player.add_child(stats)
	add_child(player)
	player.stats_component.set_stat(Stat.HEALTH_MAX, health_max)
	player.stats_component.set_stat(Stat.HEALTH, health_max)
	return player


func _potion(slug: StringName) -> ConsumableItem:
	return ContentRegistryHub.load_by_slug(&"items", slug) as ConsumableItem


## Put one in the bag and drink it, the way item.consume.gd does.
func _drink(player: Player, potion: ConsumableItem) -> void:
	Inventory.add_item(player.player_resource.inventory, int(potion.get_meta(&"id", 0)), 1)
	potion.on_use(player)


func _held(player: Player, potion: ConsumableItem) -> int:
	return Inventory.count(player.player_resource.inventory, int(potion.get_meta(&"id", 0)))


func _test_drinking() -> void:
	var player: Player = _make_player()
	var potion: ConsumableItem = _potion(&"weapon_poison")
	_check(not CoatingService.is_active(player), "a fresh player has a clean weapon")
	_check(potion.can_use(player), "a clean weapon can take a coating")
	_drink(player, potion)
	_check(CoatingService.is_active(player), "drinking the vial coats the weapon")
	_check(CoatingService.active_kind(player) == CoatingService.KIND_POISON, "the coating is poison")
	var left: int = CoatingService.remaining_seconds(player)
	_check(left > 295 and left <= 300, "the coating lasts ~5 minutes (got %ds)" % left)
	_check(_held(player, potion) == 0, "the vial is consumed")
	_check(
		CoatingService.status_id(CoatingService.active_kind(player)) == "coating_poison",
		"the status strip id is prefixed"
	)


## The owner rule: ONE coating at a time, refused rather than merged — and a
## refused drink must not eat the vial.
func _test_one_at_a_time() -> void:
	var player: Player = _make_player()
	var poison: ConsumableItem = _potion(&"weapon_poison")
	var ember: ConsumableItem = _potion(&"weapon_ember")
	_drink(player, poison)

	_check(not ember.can_use(player), "a second coating is refused while one runs")
	Inventory.add_item(player.player_resource.inventory, int(ember.get_meta(&"id", 0)), 1)
	ember.on_use(player)
	_check(_held(player, ember) == 1, "a refused coating does NOT consume the vial")
	_check(
		CoatingService.active_kind(player) == CoatingService.KIND_POISON,
		"the running coating is untouched by the refusal"
	)
	_check(
		not CoatingService.apply(player, CoatingService.KIND_BURN, 99.0, 9.0, 900.0),
		"CoatingService.apply reports the refusal"
	)

	# Re-drinking the SAME coating is refused too — no top-ups (owner call).
	_check(not poison.can_use(player), "re-drinking the same coating is also refused")

	# A health potion is a different system and must stay drinkable.
	var health: ConsumableItem = _potion(&"health_potion")
	if health != null:
		player.stats_component.set_stat(Stat.HEALTH, 1.0)
		_check(health.can_use(player), "a coating does not block a health potion")


## The Defense Tonic shares the coating's one slot, so the two must refuse each
## other in BOTH directions — and neither refusal may eat a vial.
func _test_draught_slot() -> void:
	var player: Player = _make_player()
	var tonic: ConsumableItem = _potion(&"defense_tonic")
	var ember: ConsumableItem = _potion(&"weapon_ember")
	_check(tonic != null, "the Defense Tonic is registered")
	if tonic == null:
		return
	_check(tonic.exclusive_buff, "the Defense Tonic holds the draught slot")
	_check(tonic.can_use(player), "an empty draught slot takes the tonic")

	var armor_before: float = player.stats_component.get_stat(Stat.ARMOR)
	_drink(player, tonic)
	_check(
		is_equal_approx(
			player.stats_component.get_stat(Stat.ARMOR), armor_before + tonic.buff_amount
		),
		"drinking the tonic raises armor by %.0f" % tonic.buff_amount
	)
	_check(BuffService.exclusive_active(player), "the tonic holds the slot")
	var left: int = BuffService.exclusive_remaining_seconds(player)
	_check(left > 295 and left <= 300, "the tonic lasts ~5 minutes (got %ds)" % left)
	_check(_held(player, tonic) == 0, "the vial is consumed")

	# Tonic running -> a coating is refused, and keeps its vial.
	_check(not ember.can_use(player), "a coating is refused while the tonic runs")
	Inventory.add_item(player.player_resource.inventory, int(ember.get_meta(&"id", 0)), 1)
	ember.on_use(player)
	_check(_held(player, ember) == 1, "a refused coating does NOT consume the vial")
	_check(not CoatingService.is_active(player), "the refused coating never landed")

	# Coating running -> the tonic is refused, and keeps its vial.
	var coated: Player = _make_player()
	_drink(coated, _potion(&"weapon_poison"))
	_check(not tonic.can_use(coated), "the tonic is refused while a coating runs")
	Inventory.add_item(coated.player_resource.inventory, int(tonic.get_meta(&"id", 0)), 1)
	var armor_coated: float = coated.stats_component.get_stat(Stat.ARMOR)
	tonic.on_use(coated)
	_check(_held(coated, tonic) == 1, "a refused tonic does NOT consume the vial")
	_check(
		is_equal_approx(coated.stats_component.get_stat(Stat.ARMOR), armor_coated),
		"a refused tonic grants no armor"
	)

	# An ordinary (non-exclusive) buff is unaffected by the slot.
	var busy: Player = _make_player()
	_drink(busy, tonic)
	BuffService.apply(busy, Stat.MOVE_SPEED, 10.0, 30.0)
	_check(
		is_equal_approx(busy.stats_component.get_stat(Stat.MOVE_SPEED), 10.0),
		"a plain buff still stacks alongside the tonic"
	)

	# Once it expires the slot frees up again.
	for buff: Dictionary in player.player_resource.active_buffs:
		buff["expires_ms"] = Time.get_ticks_msec() - 1
	_check(not BuffService.exclusive_active(player), "an elapsed tonic releases the slot")
	_check(ember.can_use(player), "a coating is drinkable once the tonic lapses")


func _test_poison_on_hit() -> void:
	var player: Player = _make_player()
	var poison: ConsumableItem = _potion(&"weapon_poison")
	_drink(player, poison)
	var victim: Character = Character.new()
	add_child(victim)
	CoatingService.on_hit(player, victim)
	var dot: DamageOverTime = victim.get_node_or_null(^"DoT_poison") as DamageOverTime
	_check(dot != null, "a poisoned hit attaches a poison DoT")
	if dot != null:
		_check(dot.source == player, "the DoT credits the attacker")
		# Read the number off the VIAL, never a literal. This assertion was
		# hard-coded to 4.0 and went red the day the poison was retuned to 18 —
		# which said nothing about the handoff it exists to test.
		_check(
			is_equal_approx(dot.damage_per_tick, poison.coating_potency),
			"the DoT carries the authored dps (%.1f)" % poison.coating_potency
		)


func _test_burn_on_hit() -> void:
	var player: Player = _make_player()
	_drink(player, _potion(&"weapon_ember"))
	var victim: Character = Character.new()
	add_child(victim)
	CoatingService.on_hit(player, victim)
	_check(
		victim.get_node_or_null(^"DoT_burn") != null,
		"an ember hit attaches a BURN DoT, not a poison one"
	)
	_check(
		victim.get_node_or_null(^"DoT_poison") == null,
		"an ember hit does not also poison"
	)


func _test_heal_on_hit() -> void:
	var player: Player = _make_player()
	_drink(player, _potion(&"weapon_salve"))
	var victim: Character = Character.new()
	add_child(victim)
	player.stats_component.set_stat(Stat.HEALTH, 50.0)
	CoatingService.on_hit(player, victim)
	var hp: float = player.stats_component.get_stat(Stat.HEALTH)
	_check(hp > 50.0, "a salved hit heals the attacker (%.0f hp)" % hp)
	_check(
		victim.get_node_or_null(^"DoT_poison") == null
		and victim.get_node_or_null(^"DoT_burn") == null,
		"a salved hit puts no damage-over-time on the victim"
	)
	# Healing must never overflow the pool.
	player.stats_component.set_stat(Stat.HEALTH, 100.0)
	CoatingService.on_hit(player, victim)
	_check(
		player.stats_component.get_stat(Stat.HEALTH) <= 100.0,
		"heal-on-hit cannot exceed max health"
	)


## The SUSTAIN slot. The salve runs alongside a damage coating and alongside a
## draught-slot tonic; the only thing it refuses is a second salve. Both halves
## are tested, because "stacks" that quietly meant "overwrites" would look
## identical from the outside until a player noticed their ember had gone.
func _test_salve_stacks() -> void:
	var player: Player = _make_player()
	var salve: ConsumableItem = _potion(&"weapon_salve")
	var ember: ConsumableItem = _potion(&"weapon_ember")
	var tonic: ConsumableItem = _potion(&"defense_tonic")

	_drink(player, ember)
	_check(salve.can_use(player), "a salve is drinkable while an ember runs")
	_drink(player, salve)
	_check(_held(player, salve) == 0, "the salve vial is consumed")
	_check(
		CoatingService.active_kind(player) == CoatingService.KIND_BURN,
		"the ember still holds the offensive slot"
	)
	_check(
		CoatingService.sustain_kind(player) == CoatingService.KIND_HEAL,
		"the salve holds the sustain slot"
	)
	_check(
		CoatingService.remaining_seconds(player) > 0
		and CoatingService.sustain_remaining_seconds(player) > 0,
		"both slots count down at once"
	)

	# ONE hit, BOTH payloads. This is the whole point of the split.
	var victim: Character = Character.new()
	add_child(victim)
	player.stats_component.set_stat(Stat.HEALTH, 50.0)
	CoatingService.on_hit(player, victim)
	_check(
		victim.get_node_or_null(^"DoT_burn") != null,
		"a salved, embered hit still burns the victim"
	)
	_check(
		player.stats_component.get_stat(Stat.HEALTH) > 50.0,
		"the same hit still heals the attacker"
	)

	# A second salve is refused, and keeps its vial.
	_check(not salve.can_use(player), "a second salve is refused")
	Inventory.add_item(player.player_resource.inventory, int(salve.get_meta(&"id", 0)), 1)
	salve.on_use(player)
	_check(_held(player, salve) == 1, "a refused salve does NOT consume the vial")

	# The salve holds no COMBAT DRAUGHT slot, so a tonic pours over it — and a
	# salve pours over a tonic. Neither direction may refuse.
	var salved: Player = _make_player()
	_drink(salved, _potion(&"weapon_salve"))
	_check(not ConsumableItem.draught_slot_busy(salved), "a salve holds no draught slot")
	_check(tonic.can_use(salved), "a tonic is drinkable while a salve runs")
	var armor_before: float = salved.stats_component.get_stat(Stat.ARMOR)
	_drink(salved, tonic)
	_check(
		is_equal_approx(
			salved.stats_component.get_stat(Stat.ARMOR), armor_before + tonic.buff_amount
		),
		"the tonic lands on a salved player"
	)
	_check(
		CoatingService.is_sustain_active(salved),
		"the tonic did not evict the salve"
	)

	var tonicked: Player = _make_player()
	_drink(tonicked, _potion(&"defense_tonic"))
	_check(salve.can_use(tonicked), "a salve is drinkable while the tonic runs")

	# The tooltip has to say so, or the rule may as well not exist.
	var said_it: bool = false
	for line: Dictionary in salve.stat_lines():
		if str(line.get("text", "")).contains("Stacks with combat draughts"):
			said_it = true
	_check(said_it, "the salve tooltip says it stacks")
	for line: Dictionary in ember.stat_lines():
		_check(
			not str(line.get("text", "")).contains("Stacks with combat draughts"),
			"the ember tooltip still says it does NOT stack"
		)


func _test_expiry() -> void:
	var player: Player = _make_player()
	_drink(player, _potion(&"weapon_poison"))
	var victim: Character = Character.new()
	add_child(victim)

	player.player_resource.weapon_coating["expires_ms"] = Time.get_ticks_msec() - 1
	_check(not CoatingService.is_active(player), "an elapsed coating reads as inactive")
	_check(CoatingService.remaining_seconds(player) == 0, "an elapsed coating shows 0s left")
	_check(CoatingService.active_kind(player) == &"", "an elapsed coating names no kind")
	CoatingService.tick(player)
	_check(player.player_resource.weapon_coating.is_empty(), "the tick clears it")
	CoatingService.on_hit(player, victim)
	_check(
		victim.get_node_or_null(^"DoT_poison") == null,
		"an elapsed coating stops poisoning"
	)
	# And the next vial is drinkable again.
	_check(_potion(&"weapon_poison").can_use(player), "a new coating can be applied after expiry")

	# An uncoated player poisons nothing at all.
	var clean: Player = _make_player()
	CoatingService.on_hit(clean, victim)
	_check(
		victim.get_node_or_null(^"DoT_poison") == null,
		"an uncoated weapon carries nothing"
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  ok    ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)
