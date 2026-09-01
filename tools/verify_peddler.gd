extends Node
## Headless gate for the Traveling Peddler. Prints VERIFY_PASS only if every
## check below holds. Run:
##   godot --headless --path . --mode=client res://tools/verify_peddler.tscn
##
## Runs as a SCENE, not a `-s` tool: `-s` starts a bare SceneTree with no
## autoloads, and npc.gd
## references ClientState — under `-s` it fails to COMPILE, so the Peddler's
## NPCResource comes back unusable and this file reports failures that are purely
## an artefact of the harness.
##
## Covers what fails SILENTLY here: a stock .tres whose id does not match an
## indexed item (the shop would charge and hand over nothing), a tier pool that
## rolled empty, a daily roll that is not actually stable, an allowance that does
## not reset on the date change, and the schedule arithmetic — none of which can
## be eyeballed on a running server without waiting four hours.

const HANDLERS: Array[String] = [
	"res://source/server/world/components/data_request_handlers/peddler.stock.gd",
	"res://source/server/world/components/data_request_handlers/peddler.buy.gd",
	"res://source/server/world/components/data_request_handlers/peddler.use.gd",
	"res://source/server/world/components/data_request_handlers/peddler.vault.gd",
	"res://source/server/world/components/data_request_handlers/deposit_box.open.gd",
]
## Goods that are SOLD but deliberately inert, and why. Asserted as a set so a
## good silently losing its action shows up as a failure here rather than as a
## player buying something that does nothing.
const INERT: Dictionary = {
	"peddler_vault_key": "spent at the Vault Chest, not used from the bag",
	"noter_permit": "needs an item-noting system that does not exist",
}
const PEDDLER_NPC: String = "res://source/common/gameplay/characters/npc/npcs/traveling_peddler.tres"
## The Peddler must not wear another NPC's exact art. It was built by recolouring
## the Swamp Hermit (tools/build_peddler_sprites.py), so pointing back at the
## source sheets is the specific regression to catch.
const PEDDLER_SKIN: String = "res://source/common/gameplay/characters/sprite_frames/traveling_peddler.tres"
const HERMIT_SKIN: String = "res://source/common/gameplay/characters/sprite_frames/swamp_hermit.tres"
## The catalog the brief specifies: slug -> [tier, price].
const EXPECTED: Dictionary = {
	"peddler_vault_key": ["S", 500000],
	"chronos_clock": ["S", 250000],
	"noter_permit": ["S", 150000],
	"hunter_charm": ["S", 350000],
	"anvil_stabilizer": ["A", 75000],
	"portable_deposit_box": ["A", 100000],
	"mystery_seed": ["A", 50000],
	"botanist_skilling_crate": ["A", 60000],
	"biome_recall_scroll": ["B", 25000],
	"prismatic_dye": ["B", 20000],
	"wandering_tonic": ["B", 8000],
	"hearth_stew": ["B", 10000],
	# Brokered PvM chests — items the game already has, that the Peddler stocks.
	"gold_steel_grand": ["S", 450000],
	"gold_pink_large": ["S", 400000],
	"gold_steel_large": ["S", 300000],
	"gold_red_large": ["A", 150000],
	"wood_gold_large": ["A", 120000],
	"wood_gold_medium": ["A", 75000],
}
## Days sampled when checking that the roll is stable and that it moves.
const SAMPLE_DAYS: int = 400

var _failures: PackedStringArray = []


func _ready() -> void:
	await _run()


func _run() -> void:
	_check_handlers()
	_check_catalog()
	_check_items()
	_check_roll()
	_check_schedule()
	_check_ledger()
	_check_anvil()
	_check_charm()
	_check_actions()
	_check_suppressible_buffs()
	_check_dye()
	_check_npc()
	_check_web_export()
	_check_discord()
	_check_sites()
	_check_vault_payout()
	await _check_placement()
	print("")
	if _failures.is_empty():
		print("VERIFY_PASS (%d goods)" % PeddlerCatalog.all().size())
	else:
		print("VERIFY_FAIL")
		for f: String in _failures:
			print("  - %s" % f)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _ok(label: String, detail: String = "") -> void:
	print("  ok  %s%s" % [label, "" if detail.is_empty() else "  (%s)" % detail])


# --- checks ------------------------------------------------------------------

func _check_handlers() -> void:
	print("handlers")
	for path: String in HANDLERS:
		if not ResourceLoader.exists(path):
			_fail("missing handler %s" % path)
			continue
		var script: GDScript = load(path) as GDScript
		var handler: DataRequestHandler = null
		if script != null:
			handler = script.new() as DataRequestHandler
		if handler == null:
			# A handler that fails to compile is answered as "unknown_request",
			# which reads in-game as the cart simply not responding.
			_fail("%s is not a loadable DataRequestHandler" % path.get_file())
		else:
			_ok(path.get_file())


func _check_catalog() -> void:
	print("catalog")
	PeddlerCatalog.reload()
	var seen: Dictionary = {}
	for row: PeddlerItemData in PeddlerCatalog.all():
		seen[row.id] = true
		if not EXPECTED.has(row.id):
			_fail("catalog has unexpected good '%s'" % row.id)
			continue
		var want: Array = EXPECTED[row.id]
		if row.tier != want[0]:
			_fail("'%s' is tier %s, expected %s" % [row.id, row.tier, want[0]])
		if row.price_gold != int(want[1]):
			_fail("'%s' costs %d, expected %d" % [row.id, row.price_gold, int(want[1])])
	for slug: String in EXPECTED:
		if not seen.has(slug):
			_fail("catalog is missing '%s'" % slug)
	for tier: String in PeddlerItemData.TIERS:
		var pool: Array = PeddlerCatalog.tier_pool(tier)
		if pool.is_empty():
			# An empty pool makes the daily roll return fewer than three goods,
			# and the window would just quietly show two.
			_fail("tier %s pool is empty" % tier)
		else:
			_ok("tier %s pool" % tier, "%d goods" % pool.size())


## Every stock id must resolve to an indexed PeddlerGoodItem, and every good with
## an action must be marked usable. A mismatch here is the failure mode that
## charges a player and hands them nothing.
func _check_items() -> void:
	print("items")
	for row: PeddlerItemData in PeddlerCatalog.all():
		var item_id: int = ContentRegistryHub.id_from_slug(&"items", StringName(row.id))
		if item_id <= 0:
			_fail("'%s' has no indexed item — run tools/update_items_index.gd" % row.id)
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item == null:
			_fail("'%s' item id %d does not load" % [row.id, item_id])
			continue
		if row.brokered:
			# A brokered row must NOT be judged by the exclusive-good rules: the
			# item is authored elsewhere, keeps its own class and its own use
			# pipeline, and stays as tradeable as it already was.
			_check_brokered(row, item)
			continue
		var good: PeddlerGoodItem = item as PeddlerGoodItem
		if good == null:
			_fail("'%s' resolves to a %s, not a PeddlerGoodItem" % [
				row.id, item.get_class()
			])
			continue
		if good.can_trade:
			# A Peddler-EXCLUSIVE good that could be handed to another character
			# would make the one-per-account-per-day cap a cap on alts rather
			# than on players. (A brokered chest already trades freely and is
			# already dropped by bosses, so the cap only bounds purchases.)
			_fail("'%s' is tradeable — the daily cap would not hold" % row.id)
		var has_action: bool = row.action_script != null
		if has_action != good.usable:
			_fail("'%s': action_script=%s but item.usable=%s" % [
				row.id, has_action, good.usable
			])
		if has_action:
			var action: PeddlerAction = row.action_script.new() as PeddlerAction
			if action == null:
				_fail("'%s' action_script is not a PeddlerAction" % row.id)
	_ok("stock ids resolve", "%d goods" % PeddlerCatalog.all().size())

	# The fallback icon must exist for every tier — a null here is an empty slot
	# in the cart, which is exactly what it was written to prevent.
	for tier: String in PeddlerItemData.TIERS:
		var texture: Texture2D = PeddlerItemData.fallback_icon(tier)
		if texture == null or texture.get_size() != Vector2(
			PeddlerItemData.FALLBACK_SIZE, PeddlerItemData.FALLBACK_SIZE
		):
			_fail("tier %s fallback icon is missing or wrong size" % tier)
	_ok("fallback icons")


## A brokered row sells an item the game already has. What can go wrong is the
## MAPPING: several chest slugs do not read like their display name (Ornate Gold
## Chest is gold_pink_large), so a typo sells the wrong chest at the right price
## and nothing anywhere would notice.
func _check_brokered(row: PeddlerItemData, item: Item) -> void:
	if row.action_script != null:
		_fail("brokered '%s' has an action_script — it keeps its own use path" % row.id)
	if String(item.item_name) != row.item_name:
		_fail("brokered '%s' is sold as \"%s\" but the item is \"%s\"" % [
			row.id, row.item_name, String(item.item_name)
		])
	var chest: LootChestItem = item as LootChestItem
	if chest == null:
		# Not a hard failure — the Peddler may broker something that is not a
		# chest later — but every current one is, so say so.
		_ok("brokered", "%s (%s)" % [row.item_name, item.get_class()])
		return
	if chest.resolve_table() == null:
		# A chest whose table does not resolve opens into nothing, and the buyer
		# has paid up to 450,000 gold for it.
		_fail("brokered '%s' has no loot table (chest_slug '%s')" % [
			row.id, chest.chest_slug
		])
		return
	_ok("brokered chest", "%s -> %s" % [row.item_name, chest.chest_slug])


## The roll must be a pure function of the date: same date, same three; and over
## a year it must actually move through each pool rather than sticking.
func _check_roll() -> void:
	print("daily roll")
	var today: String = PeddlerSchedule.utc_date()
	var first: Array = PeddlerStock.for_date(today)
	if first.size() != PeddlerItemData.TIERS.size():
		_fail("today's roll returned %d goods, expected %d" % [
			first.size(), PeddlerItemData.TIERS.size()
		])
		return
	for i: int in first.size():
		if (first[i] as PeddlerItemData).tier != PeddlerItemData.TIERS[i]:
			_fail("roll slot %d is tier %s, expected %s" % [
				i, (first[i] as PeddlerItemData).tier, PeddlerItemData.TIERS[i]
			])
	# Stability: re-rolling the same date must give the identical three.
	for _repeat: int in 5:
		var again: Array = PeddlerStock.for_date(today)
		for i: int in first.size():
			if again[i] != first[i]:
				_fail("roll for %s is not stable" % today)
				return
	_ok("stable for %s" % today, ", ".join(_names(first)))

	# Coverage: walk a year of dates and confirm every good is reachable, and
	# that consecutive days are not locked together.
	var hits: Dictionary = {}
	var same_as_yesterday: int = 0
	var previous: Array = []
	var day_s: int = PeddlerSchedule.now_s()
	for _d: int in SAMPLE_DAYS:
		var date: String = PeddlerSchedule.utc_date(day_s)
		var roll: Array = PeddlerStock.for_date(date)
		for row: PeddlerItemData in roll:
			hits[row.id] = int(hits.get(row.id, 0)) + 1
		if not previous.is_empty() and previous == roll:
			same_as_yesterday += 1
		previous = roll
		day_s += PeddlerSchedule.DAY_S
	for slug: String in EXPECTED:
		if not hits.has(slug):
			_fail("'%s' never rolls in %d days" % [slug, SAMPLE_DAYS])
	if same_as_yesterday > SAMPLE_DAYS / 10:
		_fail("roll repeats the previous day %d times in %d — pools are correlated" % [
			same_as_yesterday, SAMPLE_DAYS
		])
	_ok("coverage over %d days" % SAMPLE_DAYS, "%d goods reachable" % hits.size())


## The window must open on the UTC hour and last exactly ACTIVE_S, from any
## starting second — this is the promise that survives a server restart.
func _check_schedule() -> void:
	print("schedule")
	if PeddlerSchedule.CYCLE_S % 3600 != 0 or PeddlerSchedule.DAY_S % PeddlerSchedule.CYCLE_S != 0:
		# A cycle that does not divide the day would drift the spawn hour across
		# dates, so "the four-o'clock peddler" would stop being true.
		_fail("cycle of %ds does not tile a UTC day on the hour" % PeddlerSchedule.CYCLE_S)
	var start: int = PeddlerSchedule.cycle_start_s(PeddlerSchedule.cycle_index())
	for offset: int in [0, 1, PeddlerSchedule.ACTIVE_S - 1]:
		if not PeddlerSchedule.is_active(start + offset):
			_fail("window should be open at start+%ds" % offset)
	for offset: int in [PeddlerSchedule.ACTIVE_S, PeddlerSchedule.CYCLE_S - 1]:
		if PeddlerSchedule.is_active(start + offset):
			_fail("window should be closed at start+%ds" % offset)
	if PeddlerSchedule.seconds_remaining(start) != PeddlerSchedule.ACTIVE_S:
		_fail("a freshly opened window does not report its full length")
	if PeddlerSchedule.seconds_until_next(start + PeddlerSchedule.ACTIVE_S) \
			!= PeddlerSchedule.CYCLE_S - PeddlerSchedule.ACTIVE_S:
		_fail("closed window does not report the right wait for the next one")
	# The spawn hours must land on the clock, not on an arbitrary offset.
	var hour: Dictionary = Time.get_datetime_dict_from_unix_time(start)
	if int(hour.get("minute", -1)) != 0 or int(hour.get("second", -1)) != 0:
		_fail("cycle does not start on the hour (%02d:%02d)" % [
			int(hour.get("minute", -1)), int(hour.get("second", -1))
		])
	_ok("cycle", "%dh window, %dm active" % [
		PeddlerSchedule.CYCLE_S / 3600, PeddlerSchedule.ACTIVE_S / 60
	])


## One purchase per good per UTC day, and a date change clears the slate.
func _check_ledger() -> void:
	print("daily limit")
	var pr: PlayerResource = PlayerResource.new()
	pr.player_id = 1
	var today: String = "2026-08-30"
	var tomorrow: String = "2026-08-31"
	if PeddlerLedger.has_bought(pr, "hunter_charm", today):
		_fail("a fresh character starts with a spent allowance")
	PeddlerLedger.record(pr, "hunter_charm", today)
	if not PeddlerLedger.has_bought(pr, "hunter_charm", today):
		_fail("a recorded purchase is not remembered")
	if PeddlerLedger.has_bought(pr, "mystery_seed", today):
		_fail("buying one good spent the allowance on another")
	if PeddlerLedger.has_bought(pr, "hunter_charm", tomorrow):
		_fail("the allowance did not reset on the UTC date change")
	if not PeddlerLedger.bought_today(pr, tomorrow).is_empty():
		_fail("the ledger was not cleared by the rollover")
	# A save/load round trip across midnight must also come back clear.
	PeddlerLedger.record(pr, "hearth_stew", today)
	var saved: Dictionary = PeddlerLedger.save_state(pr)
	var loaded: PlayerResource = PlayerResource.new()
	PeddlerLedger.load_state(loaded, saved, today)
	if not PeddlerLedger.has_bought(loaded, "hearth_stew", today):
		_fail("the ledger did not survive a save/load on the same day")
	PeddlerLedger.load_state(loaded, saved, tomorrow)
	if not PeddlerLedger.bought_today(loaded, tomorrow).is_empty():
		_fail("a stale ledger was loaded onto a new day")
	_ok("one per good per UTC day")


## The smelting run cap, and that a stabilizer charge is what lifts it.
func _check_anvil() -> void:
	print("anvil stabilizer")
	var pr: PlayerResource = PlayerResource.new()
	pr.player_id = 4242
	AnvilBoost.forget(pr.player_id)
	if AnvilBoost.max_bars(pr) != AnvilBoost.BASE_MAX_BARS:
		_fail("an unboosted smith is not capped at %d bars" % AnvilBoost.BASE_MAX_BARS)
	var smelted: int = 0
	while AnvilBoost.consume_bar(pr).get("ok", false):
		smelted += 1
		if smelted > AnvilBoost.BOOSTED_MAX_BARS * 2:
			break
	if smelted != AnvilBoost.BASE_MAX_BARS:
		_fail("unboosted run smelted %d bars, expected %d" % [smelted, AnvilBoost.BASE_MAX_BARS])

	AnvilBoost.forget(pr.player_id)
	pr.anvil_boost_charges = 50
	if AnvilBoost.max_bars(pr) != AnvilBoost.BOOSTED_MAX_BARS:
		_fail("charges did not lift the cap to %d" % AnvilBoost.BOOSTED_MAX_BARS)
	smelted = 0
	while AnvilBoost.consume_bar(pr).get("ok", false):
		smelted += 1
		if smelted > AnvilBoost.BOOSTED_MAX_BARS * 2:
			break
	if smelted != AnvilBoost.BOOSTED_MAX_BARS:
		_fail("boosted run smelted %d bars, expected %d" % [smelted, AnvilBoost.BOOSTED_MAX_BARS])
	if pr.anvil_boost_charges != 0:
		# One stabilizer is meant to be exactly one full run.
		_fail("a %d-bar boosted run left %d charges, expected 0" % [
			AnvilBoost.BOOSTED_MAX_BARS, pr.anvil_boost_charges
		])

	# A booked bar the craft then rolled back must give the charge and the slot
	# back, or a full bag quietly steals 1/50th of a 75,000-gold good.
	AnvilBoost.forget(pr.player_id)
	pr.anvil_boost_charges = 3
	var booked: Dictionary = AnvilBoost.consume_bar(pr)
	AnvilBoost.refund_bar(pr, booked)
	if pr.anvil_boost_charges != 3 or AnvilBoost.bars_this_run(pr.player_id) != 0:
		_fail("refund_bar did not undo a booked bar")
	AnvilBoost.forget(pr.player_id)
	_ok("run cap", "%d bars, %d boosted" % [AnvilBoost.BASE_MAX_BARS, AnvilBoost.BOOSTED_MAX_BARS])


## The charm must touch only high-tier BOSS rolls, and only ever upward.
func _check_charm() -> void:
	print("hunter's charm")
	var pr: PlayerResource = PlayerResource.new()
	var rare: float = LootRarity.ULTRA_MAX * 0.5
	var common: float = 0.5

	if HunterCharm.is_active(pr):
		_fail("an unblessed character reads as blessed")
	if HunterCharm.adjusted_chance(pr, true, rare) != rare:
		_fail("an unblessed roll was modified")

	pr.hunter_charm_until_ms = int(Time.get_unix_time_from_system() * 1000.0) + 60000
	if not HunterCharm.is_active(pr):
		_fail("a stamped charm does not read as active")
	if not is_equal_approx(
		HunterCharm.adjusted_chance(pr, true, rare), rare * HunterCharm.DROP_MULTIPLIER
	):
		_fail("a rare boss roll is not multiplied by %.2f" % HunterCharm.DROP_MULTIPLIER)
	if HunterCharm.adjusted_chance(pr, true, common) != common:
		_fail("a COMMON boss roll was boosted — the charm is a flat loot multiplier")
	if HunterCharm.adjusted_chance(pr, false, rare) != rare:
		_fail("a non-boss roll was boosted")
	if HunterCharm.adjusted_chance(pr, true, 0.95) > 1.0:
		_fail("a boosted chance exceeded certainty")

	# The toast must fire only when the charm is what landed the drop.
	if HunterCharm.was_decisive(pr, true, rare, rare * 0.5):
		_fail("the blessing took credit for a drop the base chance already earned")
	if not HunterCharm.was_decisive(pr, true, rare, rare * 1.1):
		_fail("the blessing did not claim a drop only it could have landed")
	pr.hunter_charm_until_ms = 1 # long expired
	if HunterCharm.is_active(pr):
		_fail("an expired charm still reads as active")
	_ok("scoped to rare boss drops", "x%.2f" % HunterCharm.DROP_MULTIPLIER)


## The NPC resource must load, carry a PeddlerInteraction, and route to the
## window the client actually has.
func _check_npc() -> void:
	print("npc")
	if not ResourceLoader.exists(PEDDLER_NPC):
		_fail("missing %s" % PEDDLER_NPC)
		return
	var resource: NPCResource = load(PEDDLER_NPC) as NPCResource
	if resource == null:
		_fail("%s did not load as an NPCResource" % PEDDLER_NPC.get_file())
		return
	if resource.giver_key() != PeddlerNames.NPC_SLUG:
		_fail("npc slug is '%s', the manager spawns '%s'" % [
			resource.giver_key(), PeddlerNames.NPC_SLUG
		])
	_check_skin(resource)
	var desk: PeddlerInteraction = null
	for interaction: NPCInteraction in resource.interactions:
		if interaction is PeddlerInteraction:
			desk = interaction as PeddlerInteraction
	if desk == null:
		_fail("the Peddler has no PeddlerInteraction — the cart would not open")
		return
	var entry: Dictionary = desk.menu_entry(Node.new())
	var menu: String = "res://source/client/ui/menus/%s/%s_menu.tscn" % [
		entry.get("menu", ""), entry.get("menu", "")
	]
	if not ResourceLoader.exists(menu):
		# HUD.display_menu resolves a menu by NAME; a mismatch here is a click
		# that silently does nothing.
		_fail("interaction routes to '%s', which has no scene" % entry.get("menu", ""))
	if not ResourceLoader.exists(ReplicatedPropsContainer.DYNAMIC_SCENE_PATHS.get(
		ReplicatedPropsContainer.SCENE_NPC, ""
	)):
		_fail("SCENE_NPC is not a spawnable dynamic scene — the cart cannot appear")
	_ok("traveling_peddler.tres", "routes to %s" % entry.get("menu", ""))


## Every good either has a working action or is on the INERT list with a reason.
## The list is what stops "this one is not wired yet" from quietly becoming "this
## one stopped working".
func _check_actions() -> void:
	print("actions")
	var wired: int = 0
	for row: PeddlerItemData in PeddlerCatalog.all():
		if row.brokered:
			continue # keeps its own class's use pipeline; no peddler action
		var has_action: bool = row.action_script != null
		if has_action and INERT.has(row.id):
			_fail("'%s' is on the INERT list but has an action_script" % row.id)
		elif not has_action and not INERT.has(row.id):
			_fail("'%s' has no action_script and is not listed as inert" % row.id)
		elif has_action:
			wired += 1
	for slug: String in INERT:
		if PeddlerCatalog.find(slug) == null:
			_fail("INERT names '%s', which is not in the catalog" % slug)
	var brokered: int = 0
	for row: PeddlerItemData in PeddlerCatalog.all():
		if row.brokered:
			brokered += 1
	_ok("wired", "%d act, %d brokered, %d inert, of %d rows" % [
		wired, brokered, INERT.size(), PeddlerCatalog.all().size()
	])

	# The consume gate: peddler.use must not spend an item whose action refused.
	# Read off the handler source rather than mocked, because the ordering IS the
	# guarantee and a refactor that moved the remove above the check would pass
	# every behavioural test written against a succeeding action.
	var source: String = FileAccess.get_file_as_string(
		"res://source/server/world/components/data_request_handlers/peddler.use.gd"
	)
	var gate: int = source.find("if not result.get(\"ok\", false):")
	var consume: int = source.find("remove_amount_by_id")
	if gate < 0 or consume < 0 or gate > consume:
		_fail("peddler.use consumes the item before checking the action result")
	else:
		_ok("consume gate", "refusal returns before the item is removed")


## A combat-suppressed buff must lapse and RESUME without its timer stopping, and
## must never double-revert its bonus off the stat block.
func _check_suppressible_buffs() -> void:
	print("suppressible buffs")
	var source: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/combat/buff_service.gd"
	)
	for needle: String in ["suppress_in_combat", "\"applied\""]:
		if not source.contains(needle):
			_fail("BuffService lost its %s handling" % needle)
	# Every path that reverts a bonus has to consult "applied" — reverting one
	# that was suppressed drains the stat permanently, and it is invisible until
	# a player notices they are slow.
	for fn: String in ["clear_stat", "clear_all", "tick"]:
		var at: int = source.find("func " + fn)
		if at < 0:
			_fail("BuffService.%s is missing" % fn)
			continue
		var body: String = source.substr(at, 900)
		if body.contains("modify_stat") and not body.contains("applied"):
			_fail("BuffService.%s reverts without checking \"applied\"" % fn)
	_ok("suppression", "apply/tick/clear all honour the applied flag")

	# The stew's two halves must not stack with themselves.
	var stew: GDScript = load(
		"res://source/common/gameplay/peddler/actions/hearth_stew_action.gd"
	) as GDScript
	var tonic: GDScript = load(
		"res://source/common/gameplay/peddler/actions/wandering_tonic_action.gd"
	) as GDScript
	if stew == null or tonic == null:
		_fail("the tonic/stew actions do not load")
		return
	# Derived from BASE_STATS, so two drinks compute the identical amount and
	# BuffService's exact-match refresh finds the existing buff. A percentage of
	# the CURRENT speed would differ every time and stack instead.
	if not is_equal_approx(tonic.bonus_amount(), tonic.bonus_amount()):
		_fail("the tonic bonus is not deterministic")
	if tonic.bonus_amount() <= 0.0 or stew.speed_amount() <= 0.0:
		_fail("tonic/stew speed bonuses are non-positive")
	if stew.speed_amount() >= tonic.bonus_amount():
		# The stew is a travel perk; the tonic is the thing you buy to go fast.
		_fail("the stew's speed boost is not smaller than the tonic's")
	_ok("no-stack", "tonic +%.1f, stew +%.1f move speed" % [
		tonic.bonus_amount(), stew.speed_amount()
	])


## The dye palette, its expiry, and the render precedence against vault skins.
func _check_dye() -> void:
	print("prismatic dye")
	if PrismaticDye.all_ids().is_empty():
		_fail("the dye palette is empty — the action would refuse every use")
		return
	for id: int in PrismaticDye.all_ids():
		if not PrismaticDye.is_valid(id) or PrismaticDye.dye_name(id).is_empty():
			_fail("dye %d is malformed" % id)
	var pr: PlayerResource = PlayerResource.new()
	if PrismaticDye.visible_id(pr) != 0:
		_fail("an undyed character reads as dyed")
	var id: int = PrismaticDye.apply(pr)
	if id <= 0 or not PrismaticDye.is_active(pr) or PrismaticDye.visible_id(pr) != id:
		_fail("a fresh dye does not read back")
	# An expired stamp must render as 0 — the broadcast is expiry-checked at the
	# source so no client holds another player's timer.
	pr.prismatic_dye_until_ms = 1
	if PrismaticDye.visible_id(pr) != 0:
		_fail("a lapsed dye still paints")
	if not PrismaticDye.clear_if_expired(pr) or pr.prismatic_dye_id != 0:
		_fail("clear_if_expired did not drop the lapsed dye")
	# Vault skins win the single material slot.
	var body: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/characters/character.gd"
	)
	if not body.contains("if vault_skin_id > 0:"):
		_fail("character.gd no longer gives the vault skin precedence over the dye")
	_ok("dye", "%d colours, %dh" % [
		PrismaticDye.all_ids().size(), int(PrismaticDye.DURATION_S / 3600.0)
	])


## The Peddler wears its OWN sheets, and they are actually a different image from
## the Swamp Hermit's. Comparing resource paths alone would pass a file that was
## copied and never recoloured, so this samples the pixels too.
func _check_skin(resource: NPCResource) -> void:
	if resource.skin == null:
		_fail("the Peddler has no skin")
		return
	if resource.skin.resource_path == HERMIT_SKIN:
		_fail("the Peddler still wears the Swamp Hermit's SpriteFrames")
		return
	if resource.skin.resource_path != PEDDLER_SKIN:
		_ok("skin", resource.skin.resource_path.get_file())
		return
	var mine: Texture2D = resource.skin.get_frame_texture(&"idle", 0)
	var hermit_frames: SpriteFrames = load(HERMIT_SKIN) as SpriteFrames
	if mine == null or hermit_frames == null:
		_fail("could not sample the idle frames to compare")
		return
	var theirs: Texture2D = hermit_frames.get_frame_texture(&"idle", 0)
	if theirs == null:
		_fail("the Swamp Hermit has no idle frame to compare against")
		return
	var a: Image = mine.get_image()
	var b: Image = theirs.get_image()
	if a == null or b == null:
		_fail("could not read the idle frame images")
		return
	if a.get_size() != b.get_size():
		_ok("skin", "own sheets, different dimensions")
		return
	var differing: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				differing += 1
	if differing == 0:
		# A copied-but-unrecoloured sheet is the failure the path check misses.
		_fail("the Peddler's sheets are pixel-identical to the Swamp Hermit's")
	else:
		_ok("skin", "own sheets, %d px differ from the Hermit" % differing)


## The website exporter: the payload shape the site reads, and the rule that an
## unconfigured world stays silent.
func _check_web_export() -> void:
	print("web export")
	# OFF unless BOTH env vars are set. This is the guard that stops every
	# developer machine POSTing to production, so it is worth asserting rather
	# than trusting: the test only holds while the vars are actually unset here.
	if OS.get_environment(PeddlerWebExport.URL_ENV).is_empty() 			or OS.get_environment(PeddlerWebExport.KEY_ENV).is_empty():
		if PeddlerWebExport.is_configured():
			_fail("the exporter reads as configured with the environment unset")
		if PeddlerWebExport.post(self, {"probe": true}):
			_fail("the exporter POSTed with no endpoint configured")
		_ok("disabled without env", "%s + %s" % [
			PeddlerWebExport.URL_ENV, PeddlerWebExport.KEY_ENV
		])

	# The payload is the site's contract. A missing key renders as an empty
	# banner or a stuck countdown, so every one is asserted by name.
	var payload: Dictionary = PeddlerWebExport.build_payload(&"desert", true)
	for key: String in [
		"is_active", "current_zone", "time_remaining_seconds",
		"next_spawn_utc_timestamp", "daily_stock",
	]:
		if not payload.has(key):
			_fail("the exported payload is missing '%s'" % key)
	if payload.get("is_active") is not bool:
		_fail("is_active is not a bool")
	var stock: Array = payload.get("daily_stock", []) as Array
	if stock.size() != PeddlerItemData.TIERS.size():
		_fail("the payload carries %d stock rows, expected %d" % [
			stock.size(), PeddlerItemData.TIERS.size()
		])
	for row: Variant in stock:
		for key: String in ["id", "name", "price", "tier", "description"]:
			if not (row as Dictionary).has(key):
				_fail("a stock row is missing '%s'" % key)
				break
	# The secret must never be able to ride the payload out.
	var flat: String = JSON.stringify(payload)
	if flat.contains(PeddlerWebExport.KEY_ENV) or flat.to_lower().contains("authorization"):
		_fail("the payload mentions the auth key — it belongs in the header only")

	# A CLOSED window must not advertise a zone, or the site would name a place
	# nobody can go.
	var closed: Dictionary = PeddlerWebExport.build_payload(&"desert", false)
	if str(closed.get("current_zone", "")) != "":
		_fail("an inactive snapshot still names a zone")
	if int(closed.get("time_remaining_seconds", -1)) != 0:
		_fail("an inactive snapshot reports time remaining")
	# next_spawn must always be in the future, in both states — it is what the
	# site counts down to and a past timestamp would render as a stuck 0.
	var now_s: int = PeddlerSchedule.now_s()
	for snapshot: Dictionary in [payload, closed]:
		if int(snapshot.get("next_spawn_utc_timestamp", 0)) <= now_s:
			_fail("next_spawn_utc_timestamp is not in the future")
	_ok("payload", "%d stock rows, next spawn in %s" % [
		stock.size(), PeddlerSchedule.clock(
			int(payload["next_spawn_utc_timestamp"]) - now_s
		)
	])


## The Discord announcement: the exact message body, and the mention whitelist.
func _check_discord() -> void:
	print("discord announce")
	if OS.get_environment(PeddlerDiscord.WEBHOOK_ENV).is_empty():
		if PeddlerDiscord.is_configured():
			_fail("Discord reads as configured with the environment unset")
		if PeddlerDiscord.announce(self, {"is_active": true}):
			_fail("Discord announced with no webhook configured")
		_ok("disabled without env", PeddlerDiscord.WEBHOOK_ENV)

	var payload: Dictionary = PeddlerWebExport.build_payload(&"desert", true)
	var msg: Dictionary = PeddlerDiscord.build_message(payload, "123456789")

	# The mention whitelist is the safety property: without it a stock item whose
	# name contained an @ could ping a real user or role. With it, the opt-in role
	# is the only thing this webhook can ever ping.
	var allowed: Dictionary = msg.get("allowed_mentions", {}) as Dictionary
	if allowed.is_empty():
		_fail("the message carries no allowed_mentions whitelist")
	elif not (allowed.get("parse", null) is Array) or not (allowed["parse"] as Array).is_empty():
		_fail("allowed_mentions.parse must be an EMPTY array (it disables @everyone)")
	elif (allowed.get("roles", []) as Array) != ["123456789"]:
		_fail("allowed_mentions.roles does not name only the opt-in role")
	if str(msg.get("content", "")) != "<@&123456789>":
		_fail("the role ping is missing or malformed")

	# No role configured must mean NOTHING is pinged — not a stray empty mention.
	var silent: Dictionary = PeddlerDiscord.build_message(payload, "")
	if silent.has("content"):
		_fail("an unconfigured role still produced a ping")
	if not (silent.get("allowed_mentions", {}) as Dictionary).get("roles", []).is_empty():
		_fail("an unconfigured role still whitelisted a mention")

	var embed: Dictionary = (msg.get("embeds", []) as Array)[0]
	if (embed.get("fields", []) as Array).size() != (payload["daily_stock"] as Array).size():
		_fail("the embed does not list every stocked good")
	# The live countdown is the whole reason this is one message and not two: a
	# baked "30 minutes left" string is wrong for everyone who reads it later.
	# Required only when there IS time left — with the window closed (which is
	# the usual state when this gate runs) the honest output is prose, and
	# demanding a stamp here would be demanding a countdown to the past.
	var has_time: bool = int(payload.get("time_remaining_seconds", 0)) > 0
	if has_time and not str(embed.get("description", "")).contains("<t:"):
		_fail("a live snapshot produced no Discord timestamp — the countdown would go stale")
	# Whatever zone the snapshot carries must reach the message. Compared against
	# the payload rather than a hardcoded title: with no world server running,
	# _zone_title falls back to the raw instance_name, and asserting the pretty
	# form here would only be testing the harness.
	var zone: String = str(payload.get("current_zone", ""))
	if zone.is_empty() or not str(embed.get("description", "")).contains(zone):
		_fail("the embed does not name the zone ('%s')" % zone)
	# Exercise the live branch explicitly, so the stamp is covered even when this
	# gate happens to run between windows.
	var live: Dictionary = payload.duplicate(true)
	live["generated_utc_timestamp"] = PeddlerSchedule.now_s()
	live["time_remaining_seconds"] = 1500
	var live_desc: String = str(
		((PeddlerDiscord.build_message(live, "") .get("embeds", []) as Array)[0]
		as Dictionary).get("description", "")
	)
	if not live_desc.contains("<t:"):
		_fail("a snapshot with time left produced no live timestamp")
	else:
		var lat: int = int(live_desc.substr(
			live_desc.find("<t:") + 3,
			live_desc.find(":R>") - live_desc.find("<t:") - 3
		))
		if lat <= PeddlerSchedule.now_s():
			_fail("the live timestamp is not in the future")

	# A timestamp must never point at the past: Discord renders that as "just
	# now", which reads as "do not bother going". Caught by testing against a
	# real webhook while the window happened to be closed.
	var now_s2: int = PeddlerSchedule.now_s()
	var stamp: String = str(embed.get("description", ""))
	var at: int = stamp.find("<t:")
	if at != -1:
		var ts: int = int(stamp.substr(at + 3, stamp.find(":R>", at) - at - 3))
		if ts <= now_s2:
			_fail("the embed timestamp is in the past (%d <= %d)" % [ts, now_s2])
	# The zero-remaining snapshot must fall back to prose, not a stale stamp.
	var spent: Dictionary = payload.duplicate(true)
	spent["time_remaining_seconds"] = 0
	var spent_desc: String = str(
		((PeddlerDiscord.build_message(spent, "") .get("embeds", []) as Array)[0]
		as Dictionary).get("description", "")
	)
	if spent_desc.contains("<t:"):
		_fail("a zero-remaining snapshot still emitted a live timestamp")

	# A snapshot with nothing standing must not be announced.
	if PeddlerDiscord.announce(self, PeddlerWebExport.build_payload(&"desert", false)):
		_fail("announced a spawn for an inactive snapshot")
	_ok("message", "%d fields, live timestamp, whitelisted mention" % [
		(embed.get("fields", []) as Array).size()
	])


## The biome rotation must have somewhere to go, be stable per cycle, and offer a
## FALLBACK — a rotation one entry long would strand the cart for a whole window
## the first time its biome could not host a prop.
func _check_sites() -> void:
	print("spawn sites")
	var biomes: Array[StringName] = PeddlerSites.biome_names()
	if biomes.is_empty():
		_fail("no biome instances found — the Peddler has nowhere to stand")
		return
	var cycle_now: int = PeddlerSchedule.cycle_index()
	var order: Array[StringName] = PeddlerSites.rotation_for_cycle(cycle_now)
	if order.size() != biomes.size():
		_fail("the rotation lists %d biomes but %d exist" % [order.size(), biomes.size()])
	if order.is_empty() or order[0] != PeddlerSites.biome_for_cycle(cycle_now):
		_fail("rotation_for_cycle does not start at biome_for_cycle")
	var seen: Dictionary = {}
	for name: StringName in order:
		if seen.has(name):
			_fail("the rotation repeats '%s' — a skip could loop forever" % name)
		seen[name] = true
	_ok("fallback order", "%d biomes, no repeats" % order.size())
	var cycle: int = PeddlerSchedule.cycle_index()
	var first: StringName = PeddlerSites.biome_for_cycle(cycle)
	if first == &"":
		_fail("cycle %d picked no biome" % cycle)
	if PeddlerSites.biome_for_cycle(cycle) != first:
		_fail("the biome pick for one cycle is not stable")
	var distinct: Dictionary = {}
	for i: int in 200:
		distinct[PeddlerSites.biome_for_cycle(cycle + i)] = true
	if distinct.size() < mini(4, biomes.size()):
		_fail("the rotation only reaches %d of %d biomes in 200 cycles" % [
			distinct.size(), biomes.size()
		])
	_ok("rotation", "%d biomes, %d reached in 200 cycles" % [biomes.size(), distinct.size()])


## Everything the Vault Chest promises must actually be an item it can grant.
func _check_vault_payout() -> void:
	print("vault")
	var key_id: int = ContentRegistryHub.id_from_slug(&"items", PeddlerVaultChest.KEY_SLUG)
	if key_id <= 0:
		_fail("the vault key slug '%s' is not indexed" % PeddlerVaultChest.KEY_SLUG)
	var payout: Array = PeddlerVaultChest._resolve_payout()
	if payout.size() != PeddlerVaultChest.PAYOUT.size():
		# A short payout means try_open would still take the key.
		_fail("only %d of %d payout entries resolve" % [
			payout.size(), PeddlerVaultChest.PAYOUT.size()
		])
	for entry: Dictionary in payout:
		_ok("payout", "%dx %s" % [int(entry["amount"]), str(entry["name"])])
	if not ResourceLoader.exists(ReplicatedPropsContainer.DYNAMIC_SCENE_PATHS.get(
		ReplicatedPropsContainer.SCENE_PEDDLER_VAULT, ""
	)):
		_fail("SCENE_PEDDLER_VAULT is not a spawnable dynamic scene")
	if ContentRegistryHub.id_from_slug(&"items", BossHuntService.CONTRACT_KEY_SLUG) <= 0:
		_fail("boss contract keys are not indexed — the vault would pay out nothing usable")


## END-TO-END placement, on a REAL map. The probe reasons about live collision,
## so nothing above proves it can actually find a square — this loads a biome,
## lets physics settle, and checks the spot the manager would use.
##
## Also builds the Peddler the way the manager does (npc.tscn + an npc_slug spawn
## init), which is the only thing that proves the slug hop works: the init crosses
## the wire as a plain dictionary, so a typo there is an NPC with no resource,
## no click area and no cart — and no error anywhere.
func _check_placement() -> void:
	print("placement")
	var biome: StringName = PeddlerSites.biome_for_cycle(PeddlerSchedule.cycle_index())
	var res_path: String = "%s%s.tres" % [PeddlerSites.BIOMES_DIR, biome]
	# The instance FILE is named after the biome in every current case, but the
	# rotation keys on instance_name — fall back to a scan rather than failing on
	# a resource whose filename and instance_name differ.
	var instance_res: InstanceResource = _find_instance(biome, res_path)
	if instance_res == null:
		_fail("could not load the instance resource for '%s'" % biome)
		return
	var scene: PackedScene = load(instance_res.map_path) as PackedScene
	if scene == null:
		_fail("%s does not load" % instance_res.map_path)
		return
	var map: Map = scene.instantiate() as Map
	if map == null:
		_fail("%s is not a Map" % instance_res.map_path)
		return
	add_child(map)
	# Collision shapes are only queryable once a physics step has run.
	await get_tree().physics_frame
	await get_tree().physics_frame

	if map.replicated_props_container == null:
		# Not a peddler failure: the manager walks past a biome that cannot carry
		# a dynamic prop (_skip_biome). Report it, because the same missing
		# container also means no ground loot, no chests and no spawned mobs
		# there — a map bug worth someone's attention.
		print("  !!  %s has no ReplicatedPropsContainer — the rotation skips it," % biome)
		print("      and ground loot / chests / spawns are broken in that map too.")
	var spot: Dictionary = PeddlerSites.pick_spot(map, PeddlerSchedule.cycle_index())
	var peddler_at: Vector2 = spot["peddler"]
	var vault_at: Vector2 = spot["vault"]
	if peddler_at.distance_to(vault_at) > 96.0:
		# The vault has to be within the player's own click walk-up of the cart.
		_fail("the vault landed %.0fpx from the Peddler" % peddler_at.distance_to(vault_at))
	if PeddlerSites.pick_spot(map, PeddlerSchedule.cycle_index())["peddler"] != peddler_at:
		_fail("the spot probe is not deterministic for one cycle")
	_ok("spot in %s" % biome, "(%.0f, %.0f)" % [peddler_at.x, peddler_at.y])

	var npc_scene: PackedScene = load(
		ReplicatedPropsContainer.DYNAMIC_SCENE_PATHS[ReplicatedPropsContainer.SCENE_NPC]
	) as PackedScene
	var npc: Node = npc_scene.instantiate()
	# Exactly the init the manager sends, applied the way apply_spawns applies it.
	for key: Variant in {"name": PeddlerNames.NODE_NAME, "npc_slug": PeddlerNames.NPC_SLUG}:
		npc.set(StringName(key), {
			"name": PeddlerNames.NODE_NAME, "npc_slug": PeddlerNames.NPC_SLUG
		}[key])
	if npc.name != PeddlerNames.NODE_NAME:
		# The window sends this name back for the server's range check.
		_fail("spawn init did not name the NPC '%s'" % PeddlerNames.NODE_NAME)
	var resource: NPCResource = npc.get(&"npc_resource") as NPCResource
	if resource == null:
		_fail("npc_slug '%s' did not resolve an NPCResource" % PeddlerNames.NPC_SLUG)
	elif PeddlerInteraction.of(npc) == null:
		_fail("the spawned Peddler carries no PeddlerInteraction")
	else:
		_ok("spawn init", "%s -> %s" % [PeddlerNames.NPC_SLUG, resource.npc_name])
	npc.free()

	var vault_scene: PackedScene = load(
		ReplicatedPropsContainer.DYNAMIC_SCENE_PATHS[ReplicatedPropsContainer.SCENE_PEDDLER_VAULT]
	) as PackedScene
	var vault: Node = vault_scene.instantiate()
	if vault as PeddlerVaultChest == null:
		_fail("SCENE_PEDDLER_VAULT does not instantiate a PeddlerVaultChest")
	else:
		_ok("vault scene")
	vault.free()
	map.queue_free()


func _find_instance(biome: StringName, guess: String) -> InstanceResource:
	if ResourceLoader.exists(guess):
		var direct: InstanceResource = load(guess) as InstanceResource
		if direct != null and direct.instance_name == biome:
			return direct
	for file_name: String in ResourceLoader.list_directory(PeddlerSites.BIOMES_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var loaded: Resource = ResourceLoader.load(PeddlerSites.BIOMES_DIR + file_name)
		if loaded is InstanceResource and (loaded as InstanceResource).instance_name == biome:
			return loaded as InstanceResource
	return null


func _names(rows: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for row: PeddlerItemData in rows:
		out.append("%s:%s" % [row.tier, row.id])
	return out
