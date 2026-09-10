extends Node
## Load-and-shape + behaviour check for the Prayer skill: the skill registration,
## the ten prayers, the bone ladder, the altar offering table, the church, and
## the points pool / drain / exclusivity rules.
##
## Runs as a SCENE, not `-s`: prayers reach ConsumableItem and Player, both of
## which pull in client autoloads that do not exist under `-s`. See
## verify_bank.gd for the same note.
##
##   godot --headless --path . --mode=client res://tools/verify_prayer.tscn

const CHURCH_MAP: String = "res://source/common/gameplay/maps/maps/church/inside_map.tscn"
const CHURCH_INSTANCE: String = "res://source/common/gameplay/maps/instance/instance_collection/building/church.tres"

## slug -> [level, drain/min, exclusive groups]
## The three skilling prayers drain in the same band as the combat ones on
## purpose (2026-09-04): at 2-3/min a 99 pool ran for 20-33 minutes and a
## skiller never had to carry potions. Wisdom + Haste is now 14/min, i.e. a
## full pool every ~7 minutes.
const EXPECTED_PRAYERS: Dictionary = {
	"earthen_ward": [1, 1.0, ["defence"]],
	"hawk_talon": [1, 1.0, ["offence"]],
	"gatherer_haste": [10, 5.0, ["gathering_speed"]],
	"wolf_rage": [15, 1.0, ["offence"]],
	"ironheart": [25, 3.0, ["defence"]],
	"bear_might": [35, 3.0, ["offence"]],
	"prosperity": [40, 7.0, ["gathering_yield"]],
	"blood_tithe": [45, 5.0, ["lifesteal"]],
	"ward_blades": [50, 12.0, ["protection"]],
	"mind_seer": [55, 3.0, ["offence"]],
	"bulwark_mountain": [60, 6.0, ["defence"]],
	"ward_arcane": [70, 12.0, ["protection"]],
	"wisdom_light": [75, 9.0, ["gathering_xp"]],
	"oath_slayer": [85, 24.0, ["offence", "defence"]],
}

## bone slug -> prayer xp
##
## The jump from Big Bones to Dragon Bones is enormous (326 -> 9,000) and it is
## DELIBERATE, not a typo — confirmed 2026-09-10. Dragon Bones are the endgame
## Prayer training item and the reason a dragon bone is worth more burnt than
## brewed; every recipe that consumes one is priced against that 9,000.
## This table held 550 / 1,650 / 4,400 long after the altar stopped paying them,
## and nobody saw it because the script could not be loaded (see the header).
const EXPECTED_OFFERINGS: Dictionary = {
	"bone": 109,
	"big_bones": 326,
	"dragon_bones": 9000,
}

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_check_skill()
	_check_prayers()
	_check_offerings()
	_check_prayer_draughts()
	_check_church()
	_check_pool()
	_check_toggling()
	_check_drain()

	print("")
	print("PASS %d  FAIL %d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _check_skill() -> void:
	var perks: JobPerks = JobRegistry.perks_for(&"prayer")
	_check(perks != null, "JobRegistry knows prayer")
	if perks != null:
		_check(perks.category == &"combat", "prayer is a combat skill")
		_check(perks.icon != null, "prayer has a menu icon")
		# The Conservation perk has to actually reduce drain, capped.
		var full: Dictionary = {&"conservation": 99}
		var cut: float = perks.prayer_drain_reduction(full)
		_check(cut > 0.0 and cut <= perks.abs_max_prayer_drain_reduction,
			"Conservation reduces drain and stays capped (%.2f)" % cut)
	_check(LeaderboardService.TOTAL_LEVEL_SKILLS.has(&"prayer"),
		"prayer counts toward Total Level")


func _check_prayers() -> void:
	_check(PrayerBook.PRAYERS.size() == EXPECTED_PRAYERS.size(),
		"prayer book holds %d prayers" % EXPECTED_PRAYERS.size())
	for slug: String in EXPECTED_PRAYERS:
		var spec: Array = EXPECTED_PRAYERS[slug]
		var prayer: PrayerResource = PrayerBook.by_slug(StringName(slug))
		if prayer == null:
			_check(false, "%s exists" % slug)
			continue
		_check(prayer.required_level == int(spec[0]),
			"%s unlocks at %d" % [slug, int(spec[0])])
		_check(is_equal_approx(prayer.drain_per_minute, float(spec[1])),
			"%s drains %s/min" % [slug, spec[1]])
		_check(not prayer.modifiers.is_empty(), "%s grants something" % slug)
		var groups: Array = []
		for g: StringName in prayer.exclusive_groups:
			groups.append(String(g))
		_check(groups == spec[2], "%s competes in %s" % [slug, spec[2]])
	_check(PrayerBook.by_slug(&"not_a_prayer") == null, "an unknown slug resolves to null")
	_check(PrayerBook.unlocked_at(1).size() == 2, "two prayers are open at level 1")
	_check(PrayerBook.unlocked_at(99).size() == EXPECTED_PRAYERS.size(),
		"every prayer is open at 99")

	# Oath of the Slayer must cancel BOTH ladders — the reason groups are a list.
	var oath: PrayerResource = PrayerBook.by_slug(&"oath_slayer")
	var bulwark: PrayerResource = PrayerBook.by_slug(&"bulwark_mountain")
	var hawk: PrayerResource = PrayerBook.by_slug(&"hawk_talon")
	var ward: PrayerResource = PrayerBook.by_slug(&"ward_blades")
	if oath != null and bulwark != null and hawk != null and ward != null:
		_check(oath.conflicts_with(bulwark), "Oath of the Slayer cancels the defence ladder")
		_check(oath.conflicts_with(hawk), "Oath of the Slayer cancels the offence ladder")
		_check(not oath.conflicts_with(ward), "Oath of the Slayer stacks with a protect prayer")
		_check(not oath.conflicts_with(oath), "a prayer does not conflict with itself")


func _check_offerings() -> void:
	var table: AltarOfferingTable = AltarOfferingTable.shared()
	if table == null:
		_check(false, "altar offering table loads")
		return
	_check(table.profession == &"prayer", "offerings pay into prayer")
	_check(table.offerings.size() == EXPECTED_OFFERINGS.size(),
		"altar takes %d kinds of bone" % EXPECTED_OFFERINGS.size())
	for slug: String in EXPECTED_OFFERINGS:
		var item: Item = ContentRegistryHub.load_by_slug(&"items", StringName(slug))
		if item == null:
			_check(false, "%s is in the item registry" % slug)
			continue
		var offering: AltarOffering = table.offering_for(int(item.get_meta(&"id", 0)))
		if offering == null:
			_check(false, "the altar takes %s" % slug)
			continue
		_check(offering.xp == int(EXPECTED_OFFERINGS[slug]),
			"%s pays %d xp" % [slug, int(EXPECTED_OFFERINGS[slug])])
	# Something that is NOT a bone must be refused.
	var sword: Item = ContentRegistryHub.load_by_slug(&"items", &"sword_bronze.item")
	if sword != null:
		_check(table.offering_for(int(sword.get_meta(&"id", 0))) == null,
			"the altar refuses a sword")

	var potion: ConsumableItem = ContentRegistryHub.load_by_slug(
		&"items", &"prayer_potion"
	) as ConsumableItem
	_check(potion != null and potion.prayer_amount > 0, "the prayer potion restores points")
	if potion != null:
		_check(potion.cooldown_category != &"potion",
			"the prayer potion has its own cooldown")


## The three brewed prayer draughts. They are one ladder — Potion, Super Potion,
## Renewal — so the checks here are mostly about them staying ORDERED and staying
## different from one another: a Super that restores no more than the Potion, or
## a Renewal that pays its whole pool at once, is the same item twice.
func _check_prayer_draughts() -> void:
	var potion: ConsumableItem = ContentRegistryHub.load_by_slug(
		&"items", &"prayer_potion"
	) as ConsumableItem
	var super_potion: ConsumableItem = ContentRegistryHub.load_by_slug(
		&"items", &"super_prayer_potion"
	) as ConsumableItem
	var renewal: PotionItem = ContentRegistryHub.load_by_slug(
		&"items", &"prayer_renewal"
	) as PotionItem
	_check(super_potion != null, "the super prayer potion is in the item registry")
	_check(renewal != null, "the prayer renewal is in the item registry")
	if potion == null or super_potion == null or renewal == null:
		return

	_check(
		super_potion.prayer_amount > potion.prayer_amount,
		"the super potion restores more than the potion (%d > %d)" % [
			super_potion.prayer_amount, potion.prayer_amount
		]
	)
	# Shared category, so a player cannot chain-chug one then the other. The
	# whole reason prayer has its own category is that it must not gate a heal.
	_check(
		super_potion.cooldown_category == potion.cooldown_category,
		"the super potion shares the prayer cooldown"
	)

	# The Renewal is an AURA, not a restore. A prayer_amount on it would make it
	# a bigger potion, which is the thing it exists not to be.
	_check(renewal.prayer_amount == 0, "the renewal restores nothing on the sip")
	_check(renewal.is_aura(), "the renewal arms an aura")
	_check(
		renewal.aura_effect == StatusEffectManager.EFFECT_PRAYER_RENEWAL,
		"the renewal arms the prayer-renewal family"
	)
	_check(renewal.aura_pulse_s > 0.0, "the renewal pulses")
	# The renewal is sized against the PRAYER BOOK, from BOTH ends. Too slow and
	# it is a drip-fed Prayer Potion that does not justify two Dragon Bones
	# (18,000 Prayer xp burnt at the altar); at or over the heaviest setup it
	# stops extending prayer and starts deleting it. See
	# StatusEffectManager.EFFECT_PRAYER_RENEWAL for both numbers.
	var heaviest: float = _heaviest_prayer_drain()
	var per_minute: float = renewal.aura_potency * (60.0 / renewal.aura_pulse_s)
	_check(
		per_minute >= heaviest / 3.0,
		"the renewal (%.0f/min) meaningfully offsets the heaviest setup (%.0f/min)" % [
			per_minute, heaviest
		]
	)
	_check(
		per_minute < heaviest,
		"the renewal (%.0f/min) does NOT fully cover the heaviest setup (%.0f/min)" % [
			per_minute, heaviest
		]
	)
	# One vial should still be worth more than a full altar recharge, or there is
	# no reason to brew it over walking back to the church.
	var pulses: int = int(renewal.aura_duration_s / renewal.aura_pulse_s) + 1
	var total: float = renewal.aura_potency * pulses
	_check(
		total > PrayerService.max_points_for_level(99),
		"one renewal (%d points) beats a full 99 pool" % int(total)
	)
	_check(
		not renewal.exclusive_buff,
		"the renewal holds no combat-draught slot"
	)

	# Behaviour: an aura-only draught with no slot claim must be DRINKABLE. The
	# base class refuses anything with no heal / mana / prayer / buff / coating,
	# so this is the check that catches it silently becoming un-pourable.
	var player: Player = _make_player(99)
	_check(renewal.can_use(player), "the renewal is drinkable")
	_check(
		not ConsumableItem.draught_slot_busy(player),
		"a fresh player holds no draught slot"
	)
	Inventory.add_item(player.player_resource.inventory, int(renewal.get_meta(&"id", 0)), 1)
	renewal.on_use(player)
	_check(
		Inventory.count(player.player_resource.inventory, int(renewal.get_meta(&"id", 0))) == 0,
		"the renewal vial is consumed"
	)
	var manager: StatusEffectManager = StatusEffectManager.find(player)
	_check(manager != null, "the renewal builds a status manager")
	if manager == null:
		return
	_check(
		manager.has_aura(StatusEffectManager.EFFECT_PRAYER_RENEWAL),
		"the renewal aura is running"
	)
	_check(
		not ConsumableItem.draught_slot_busy(player),
		"the running renewal still holds no combat-draught slot"
	)

	# A pulse pays points back, and cannot overfill the pool.
	PrayerService.restore(player, -PrayerService.points(player))
	player.player_resource.prayer_points = 10.0
	var before: float = PrayerService.points(player)
	manager._pulse(
		StatusEffectManager.EFFECT_PRAYER_RENEWAL,
		{"potency": renewal.aura_potency}
	)
	_check(
		is_equal_approx(PrayerService.points(player), before + renewal.aura_potency),
		"a renewal pulse pays %d points back" % int(renewal.aura_potency)
	)
	player.player_resource.prayer_points = PrayerService.max_points(player)
	manager._pulse(
		StatusEffectManager.EFFECT_PRAYER_RENEWAL,
		{"potency": renewal.aura_potency}
	)
	_check(
		PrayerService.points(player) <= PrayerService.max_points(player),
		"a renewal pulse cannot overfill the pool"
	)

	# The tooltip has to name both the rate and the total, or the draught reads
	# as far weaker than it is.
	var said_rate: bool = false
	var said_total: bool = false
	for line: Dictionary in renewal.stat_lines():
		var text: String = str(line.get("text", ""))
		if text.contains("Restores") and text.contains("prayer every"):
			said_rate = true
		if text.contains("prayer in total"):
			said_total = true
	_check(said_rate, "the renewal tooltip names its rate")
	_check(said_total, "the renewal tooltip names its total")

	# Distinct art. A draught that wears another draught's icon is a draught the
	# player grabs by mistake mid-fight, and the generic potion pack makes that
	# easy to do by accident — the Super Prayer Potion first shipped in the same
	# green bottle as Weapon Poison ++.
	var icons: Dictionary = {}
	for vial: Item in [potion, super_potion, renewal]:
		var art: String = "" if vial.item_icon == null else vial.item_icon.resource_path
		_check(not art.is_empty(), "%s has an icon" % vial.item_name)
		var clash: String = String(icons.get(art, ""))
		_check(clash.is_empty(), "%s has art of its own%s" % [
			vial.item_name,
			"" if clash.is_empty() else " (wears %s's)" % clash,
		])
		icons[art] = String(vial.item_name)
	_check(
		_icon_users(super_potion) == 1 and _icon_users(renewal) == 1,
		"the two new draughts' icons are used by nothing else"
	)


func _check_church() -> void:
	var scene: PackedScene = load(CHURCH_MAP) as PackedScene
	_check(scene != null, "the church map loads")
	if scene != null:
		var church: Node = scene.instantiate()
		var altar: Node = church.get_node_or_null(^"Altar")
		_check(altar is Altar, "the church has an altar")
		_check(church.get_node_or_null(^"Entrance") != null, "the church has a way out")
		church.free()
	_check(load(CHURCH_INSTANCE) != null, "the church instance resource loads")


func _check_pool() -> void:
	_check(is_equal_approx(PrayerService.max_points_for_level(1), 1.0),
		"a level 1 pool holds 1 point")
	_check(is_equal_approx(PrayerService.max_points_for_level(70), 70.0),
		"the pool is one point per level")

	var player: Player = _make_player(20)
	_check(is_equal_approx(PrayerService.max_points(player), 20.0),
		"reapply seats the pool from the Prayer level")
	_check(is_equal_approx(PrayerService.points(player), 20.0),
		"a fresh session starts full")

	# Spending then re-seating must NOT refill — that is the instance-hop exploit.
	player.player_resource.prayer_points = 6.0
	PrayerService.reapply(player)
	_check(is_equal_approx(PrayerService.points(player), 6.0),
		"an instance change does NOT refill the pool")

	_check(PrayerService.restore(player, 5.0) > 0.0, "a potion restores points")
	_check(is_equal_approx(PrayerService.points(player), 11.0), "restore adds the right amount")
	PrayerService.restore_full(player)
	_check(is_equal_approx(PrayerService.points(player), 20.0), "the altar fills the pool")
	_check(is_equal_approx(PrayerService.restore(player, 5.0), 0.0),
		"restoring at full does nothing")


func _check_toggling() -> void:
	var player: Player = _make_player(85)

	_check(not bool(PrayerService.activate(player, &"nope").get("ok", false)),
		"an unknown prayer is refused")
	var low: Player = _make_player(1)
	_check(not bool(PrayerService.activate(low, &"oath_slayer").get("ok", false)),
		"a prayer above your level is refused")

	var armor_before: float = player.stats_component.get_stat(Stat.ARMOR)
	_check(bool(PrayerService.activate(player, &"ironheart").get("ok", false)),
		"Ironheart switches on")
	_check(player.stats_component.get_stat(Stat.ARMOR) > armor_before,
		"Ironheart actually raises armour")
	_check(PrayerService.is_active(player, &"ironheart"), "it reads as active")

	# Same ladder: switching Bulwark of the Mountain on must switch Ironheart off.
	PrayerService.activate(player, &"bulwark_mountain")
	_check(not PrayerService.is_active(player, &"ironheart"),
		"a same-group prayer switches the other off")
	_check(PrayerService.is_active(player, &"bulwark_mountain"), "and the new one is on")

	# Different ladder: stacks.
	PrayerService.activate(player, &"hawk_talon")
	_check(PrayerService.is_active(player, &"bulwark_mountain")
		and PrayerService.is_active(player, &"hawk_talon"),
		"different groups stack")

	# Switching everything off must return stats exactly to baseline.
	PrayerService.deactivate_all(player)
	_check(PrayerService.active_slugs(player).is_empty(), "deactivate_all clears them")
	_check(is_equal_approx(player.stats_component.get_stat(Stat.ARMOR), armor_before),
		"armour returns exactly to baseline (no orphaned bonus)")
	_check(player.player_resource.applied_prayer_modifiers.is_empty(),
		"the modifier ledger is empty")

	# Oath of the Slayer cancels both ladders at once.
	PrayerService.activate(player, &"bulwark_mountain")
	PrayerService.activate(player, &"hawk_talon")
	PrayerService.activate(player, &"oath_slayer")
	_check(PrayerService.active_slugs(player).size() == 1,
		"Oath of the Slayer leaves only itself on")
	PrayerService.deactivate_all(player)
	_check(is_equal_approx(player.stats_component.get_stat(Stat.ARMOR), armor_before),
		"armour is still exactly baseline after Oath of the Slayer")


func _check_drain() -> void:
	# Level 99: Oath of the Slayer needs 85, and a player who cannot switch it on makes every
	# assertion below vacuously pass.
	var player: Player = _make_player(99)
	_check(bool(PrayerService.activate(player, &"oath_slayer").get("ok", false)),
		"Oath of the Slayer switches on at 99")
	var before: float = PrayerService.points(player)
	PrayerService.tick(player)
	var after: float = PrayerService.points(player)
	_check(after < before, "praying burns points (%.2f -> %.2f)" % [before, after])
	# 24/min over a 1s tick is 0.4 points.
	_check(is_equal_approx(before - after, 24.0 / 60.0), "the burn matches the authored rate")

	# Running dry switches everything off.
	player.player_resource.prayer_points = 0.05
	PrayerService.tick(player)
	_check(is_equal_approx(PrayerService.points(player), 0.0), "the pool bottoms out at 0")
	_check(PrayerService.active_slugs(player).is_empty(),
		"running dry switches every prayer off")
	_check(not bool(PrayerService.activate(player, &"oath_slayer").get("ok", false)),
		"you cannot pray with an empty pool")

	# Death switches prayers off too.
	var dying: Player = _make_player(99)
	PrayerService.activate(dying, &"earthen_ward")
	dying.die(null)
	_check(PrayerService.active_slugs(dying).is_empty(), "death switches prayers off")


## A live Player with a real StatsComponent (it is an @onready child node, so a
## bare Player.new() has none) and a Prayer level already banked.
## Points per minute burnt by the most expensive LEGAL set of prayers — the
## dearest prayer in each conflict group, plus every ungrouped one. Computed
## from the book rather than hard-coded, so a new prayer or a re-tuned drain
## moves the bar the Renewal has to clear instead of quietly leaving it behind.
func _heaviest_prayer_drain() -> float:
	var per_group: Dictionary = {}
	var ungrouped: float = 0.0
	for slug: String in EXPECTED_PRAYERS:
		var prayer: PrayerResource = PrayerBook.by_slug(StringName(slug))
		if prayer == null:
			continue
		var groups: Array = EXPECTED_PRAYERS[slug][2]
		if groups.is_empty():
			ungrouped += prayer.drain_per_minute
			continue
		# A prayer claiming two groups (Oath of the Slayer) locks both, so it is
		# charged once and blocks everything else in either.
		for group: String in groups:
			per_group[group] = maxf(
				float(per_group.get(group, 0.0)), prayer.drain_per_minute
			)
	# Combat only. A gathering prayer is never up in the fight this is sized for,
	# and folding one in would inflate the bar with drain no boss ever sees.
	var total: float = ungrouped
	for group: String in ["offence", "defence", "protection", "lifesteal"]:
		total += float(per_group.get(group, 0.0))
	# Oath of the Slayer is counted once for offence and once for defence by the
	# loop above; give one of them back.
	var oath: PrayerResource = PrayerBook.by_slug(&"oath_slayer")
	if oath != null and float(per_group.get("offence", 0.0)) == oath.drain_per_minute:
		total -= oath.drain_per_minute
	return total


## How many item resources reference [param item]'s icon. 1 = it owns its art.
## Grep-shaped on purpose: the icon path is a plain string in every .tres, and
## walking the whole registry to load every Item would cost far more than
## reading the files.
func _icon_users(item: Item) -> int:
	if item == null or item.item_icon == null:
		return 0
	var needle: String = item.item_icon.resource_path
	var count: int = 0
	for path: String in _all_item_resources("res://source/common/gameplay/items"):
		var body: String = FileAccess.get_file_as_string(path)
		if body.contains(needle):
			count += 1
	return count


func _all_item_resources(root: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	for sub: String in dir.get_directories():
		out.append_array(_all_item_resources(root.path_join(sub)))
	for file_name: String in dir.get_files():
		if file_name.ends_with(".tres"):
			out.append(root.path_join(file_name))
	return out


func _make_player(prayer_level: int) -> Player:
	var player: Player = Player.new()
	var resource: PlayerResource = PlayerResource.new()
	resource.level = 99
	resource.skills[&"prayer"] = {"level": prayer_level, "xp": 0, "perks": {}}
	player.player_resource = resource
	var stats: StatsComponent = StatsComponent.new()
	stats.name = "StatsComponent"
	player.add_child(stats)
	add_child(player)
	player.stats_component.set_stat(Stat.ARMOR, 15.0)
	player.stats_component.set_stat(Stat.HEALTH_MAX, 100.0)
	player.stats_component.set_stat(Stat.HEALTH, 100.0)
	PrayerService.reapply(player)
	return player


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  ok    ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)
