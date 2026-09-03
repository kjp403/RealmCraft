class_name ConsumableItem
extends Item


## Flat health restored on use. 0 = this consumable doesn't heal.
## Prototype-simple effect; can later move to a data-driven GameplayEffect list.
@export var heal_amount: int
## Flat mana restored on use. 0 = none.
@export var mana_amount: int
## Optional timed buff (via BuffService): the stat to raise (&"mana_regen",
## &"move_speed", ...). Empty = no buff.
@export var buff_stat: StringName = &""
@export var buff_amount: float = 0.0
@export var buff_duration_s: float = 0.0
## True when this vial holds the ONE combat-draught slot — the same slot a
## weapon coating takes. Ember, the poisons and the salve coat your weapon; the
## Defense Tonic buffs the drinker instead. Both are "the draught you went in
## with", so both ask [method draught_slot_busy] before they pour and neither
## stacks on the other. Ordinary tonics leave this false and stack freely.
@export var exclusive_buff: bool = false
## Weapon coating (via CoatingService): while it lasts, every hit the drinker
## LANDS does something extra. &"" = this consumable is not a coating. Kept
## separate from buff_* because "your hits poison" is not a stat.
## One of CoatingService.KIND_POISON / KIND_BURN / KIND_HEAL.
@export var coating_kind: StringName = &""
## Damage per second for poison/ember; health per landed hit for salve.
@export var coating_potency: float = 0.0
## How long the damage-over-time burns on each victim you hit. Unused by HEAL,
## which pays out per hit instead of over time.
@export var coating_hit_duration_s: float = 0.0
## How long the coating stays on YOUR weapon.
@export var coating_duration_s: float = 0.0
## Prayer points restored on use (via PrayerService). 0 = not a prayer potion.
@export var prayer_amount: int = 0
## Drink cooldown in ms, SHARED across every item with the same cooldown_category.
## 0 = no cooldown (potions and food can be used as fast as you tap them).
## Persists across re-equip (banked on Character.ability_cooldowns) when > 0.
@export var shared_cooldown_ms: int = 0
## Items sharing this category share ONE drink cooldown. Give a type its own category
## (e.g. &"mana_potion") to make it cool down independently of other potions.
@export var cooldown_category: StringName = &"potion"
## Server roots the drinker in place for this long on use, so you can't run
## and chug at the same time (a sip animation slots in here later). 0 = no
## freeze.
@export var use_freeze_ms: int = 900
## initial charges per single copy if 1 can use the potion one time, if 2 can use the potion 2 times for example.
@export var default_charges: int = 1


func _init() -> void:
	# Cooked food and potions are player-tradeable. Same pattern as
	# MaterialItem: Item.can_trade defaults false, so anything that omits the
	# field in its .tres (every current food/potion) would otherwise be stuck
	# untradeable. Quest draughts are QuestItem and stay locked.
	can_trade = true


func inventory_tab() -> InventoryTab:
	return InventoryTab.CONSUMABLE


func group_key() -> StringName:
	return &"consumables"


## Client-side: after a successful item.consume, stamp the shared category cooldown
## onto the local player so hotbar overlays (and held Drink) match the server gate.
static func stamp_client_cooldown(consumable: ConsumableItem) -> void:
	if consumable == null or not GameMode.is_client():
		return
	if ClientState.local_player == null:
		return
	var key: String = "consumable:" + str(consumable.cooldown_category)
	ClientState.local_player.ability_cooldowns[key] = Time.get_ticks_msec() / 1000.0


## Is [param player] already running a combat draught — a weapon coating OR an
## exclusive tonic? ONE at a time, by design: which draught you carried in is a
## real decision, and stacking a Defense Tonic on top of an Ember would make it
## a checklist instead.
##
## Server-side truth. On the client [member Player.player_resource] is null, so
## both services answer false and the sip goes out optimistically — the same
## thing the coating-only gate did before, with the server as the authority.
static func draught_slot_busy(player: Player) -> bool:
	# THREE services can hold the slot, not two. A coating lives on the
	# PlayerResource, an exclusive stat buff lives in BuffService, and an
	# aura-only draught (Shadowveil grants no stat and no coating) lives on
	# StatusEffectManager and is invisible to the other two.
	return (
		CoatingService.is_active(player)
		or BuffService.exclusive_active(player)
		or StatusEffectManager.exclusive_aura_active(player)
	)


## Does this vial coat the drinker's weapon? The fields its kind needs have to
## be authored — a half-filled set is an authoring slip, not a weak coating, so
## it reads as "not a coating" everywhere rather than silently applying a
## zero-length one.
func is_coating() -> bool:
	if coating_kind.is_empty() or coating_potency <= 0.0 or coating_duration_s <= 0.0:
		return false
	if coating_hit_duration_s > 0.0:
		return true
	# Every kind that lands something lasting on the VICTIM needs a per-victim
	# duration; only the attacker-side kinds (heal) may omit it. Corrode and venom
	# are not DOT_KINDS — their payloads are routed separately — but they are still
	# victim-side, so a missing duration is an authoring slip for them too.
	return not (
		CoatingService.is_dot_kind(coating_kind)
		or CoatingService.EXTRA_KINDS.has(coating_kind)
	)


## Per-kind tuning handed to [method CoatingService.apply] on top of {potency,
## hit_duration_s}. Empty here — see [method PotionItem.coating_extras], which is
## the only override, for the corrosion stack budget and the venom source rule.
func coating_extras() -> Dictionary:
	return {}


## "5m" / "1m 30s" / "45s". Shared by every timed line so they read the same way.
##
## The remainder is NOT dropped. Truncating it printed a 90-second draught as
## "1m", which is a third of its duration missing from the only place the player
## can read it — and it went unnoticed while every potion happened to run on a
## whole number of minutes.
static func _format_duration(seconds: float) -> String:
	var whole: int = int(seconds)
	if whole < 60:
		return "%ds" % whole
	var minutes: int = whole / 60
	var rest: int = whole % 60
	return "%dm" % minutes if rest == 0 else "%dm %ds" % [minutes, rest]


## Whole when whole, one decimal otherwise — matches GearItem's modifier format.
static func _format_amount(value: float) -> String:
	return ("%d" % int(value)) if is_equal_approx(value, roundf(value)) else ("%.1f" % value)


## The one-line "what it does per hit" tooltip, phrased per kind. Damage kinds
## quote the TOTAL a single application deals, because that is the number that
## compares against a weapon's AD; a per-second figure reads smaller than it is.
func _coating_effect_line() -> String:
	match coating_kind:
		CoatingService.KIND_POISON:
			return "Your hits poison for %s damage over %s" % [
				_format_amount(coating_potency * coating_hit_duration_s),
				_format_duration(coating_hit_duration_s),
			]
		CoatingService.KIND_BURN:
			return "Your hits burn for %s damage over %s" % [
				_format_amount(coating_potency * coating_hit_duration_s),
				_format_duration(coating_hit_duration_s),
			]
		CoatingService.KIND_HEAL:
			return "Your hits heal you for %s" % _format_amount(coating_potency)
		CoatingService.KIND_CORRODE:
			return "Your hits sear for %s damage over %s and corrode armor" % [
				_format_amount(coating_potency * coating_hit_duration_s),
				_format_duration(coating_hit_duration_s),
			]
		CoatingService.KIND_VENOM:
			# The stacking rule and the exact number are on [PotionItem]'s own
			# lines; this one only has to say what KIND of thing lands.
			return "Your hits leave a lingering venom"
	return "Your hits carry %s" % String(coating_kind).capitalize()


func stat_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if heal_amount > 0:
		lines.append({"text": "Restores %d health" % heal_amount, "kind": &"heal"})
	if mana_amount > 0:
		lines.append({"text": "Restores %d mana" % mana_amount, "kind": &"mana"})
	if prayer_amount > 0:
		lines.append({"text": "Restores %d prayer" % prayer_amount, "kind": &"prayer"})
	if buff_stat != &"" and not is_zero_approx(buff_amount) and buff_duration_s > 0.0:
		var number: String = ("%+d" % int(buff_amount)) if is_equal_approx(buff_amount, roundf(buff_amount)) else ("%+.1f" % buff_amount)
		lines.append({
			"text": "%s %s for %s" % [number, Stat.display_name(buff_stat), _format_duration(buff_duration_s)],
			"stat": StringName(buff_stat),
		})
	if is_coating():
		lines.append({
			"text": "Coats your weapon for %s" % _format_duration(coating_duration_s),
			"kind": &"poison",
		})
		lines.append({"text": _coating_effect_line(), "kind": &"poison"})
	# One draught at a time (see draught_slot_busy). Saying so on the tooltip is
	# what keeps the refusal from landing as a surprise at the door of a boss.
	if is_coating() or exclusive_buff:
		lines.append({
			"text": "Does not stack with other combat draughts", "kind": &"charges",
		})
	if default_charges > 1:
		lines.append({"text": "%d charges" % default_charges, "kind": &"charges"})
	return lines


func can_use(character: Character) -> bool:
	if character == null:
		return false
	if heal_amount > 0 and character.stats_component.get_stat(Stat.HEALTH) < character.stats_component.get_stat(Stat.HEALTH_MAX):
		return true
	if mana_amount > 0 and character.stats_component.get_stat(Stat.MANA) < character.stats_component.get_stat(Stat.MANA_MAX):
		return true
	# A prayer potion is wasted at a full pool, so refuse it there — same rule
	# health and mana potions already follow.
	if prayer_amount > 0 and character is Player:
		var player: Player = character as Player
		if PrayerService.points(player) < PrayerService.max_points(player):
			return true
	# Buff potions always drinkable — re-drinking refreshes the duration. The
	# exception is a draught-slot tonic, which refuses while any other draught
	# is running rather than quietly failing to stack.
	if buff_stat != &"" and buff_amount != 0.0 and buff_duration_s > 0.0:
		if not exclusive_buff:
			return true
		return character is Player and not draught_slot_busy(character as Player)
	# A coating is drinkable only on a CLEAN weapon and an EMPTY draught slot —
	# one at a time, by design (CoatingService.apply). Refusing here is what makes
	# the bag button, the hotbar and the held sip all agree with the server.
	if is_coating():
		return character is Player and not draught_slot_busy(character as Player)
	return false


## Applies the consumable's effect. Returns true if something actually happened
## (so the caller knows whether to spend a charge / remove it from the bag).
func on_use(character: Character) -> void:
	if heal_amount > 0:
		character.apply_heal(float(heal_amount), character, true)
	if mana_amount > 0:
		var stats_component: StatsComponent = character.stats_component
		var refilled: float = minf(
			stats_component.get_stat(Stat.MANA) + mana_amount,
			stats_component.get_stat(Stat.MANA_MAX)
		)
		stats_component.set_stat(Stat.MANA, refilled)
	if prayer_amount > 0 and character is Player:
		PrayerService.restore(character as Player, float(prayer_amount))
	if buff_stat != &"" and buff_amount != 0.0 and buff_duration_s > 0.0 and character is Player:
		# A refused tonic must NOT eat the vial, same rule the coating below
		# follows — bail before the bag removal rather than charging for nothing.
		if exclusive_buff and draught_slot_busy(character as Player):
			return
		BuffService.apply(
			character as Player, buff_stat, buff_amount, buff_duration_s, exclusive_buff
		)
	if is_coating():
		# A refused coating must NOT eat the vial — bail before the bag removal
		# below rather than charging the player for nothing. CoatingService only
		# knows about other COATINGS, so the draught slot is checked here too:
		# a Defense Tonic holds the same slot and must refuse an Ember as firmly
		# as another Ember would.
		if character is not Player or draught_slot_busy(character as Player):
			return
		var coated: bool = CoatingService.apply(
			character as Player,
			coating_kind,
			coating_potency,
			coating_hit_duration_s,
			coating_duration_s,
			coating_extras()
		)
		if not coated:
			return
	if character is Player:
		Inventory.remove_one_by_id(character.player_resource.inventory, get_meta(&"id"))


## A potion is just "an item that carries a DRINK action". The generic hand mount
## (Item.mount_in_hand) does the rig + the sprite; here we only build the drink — fresh
## per mount (so it owns its own cooldown state), tuned from this item (the shared
## cooldown + the sip-root). It rides the SPECIAL (Q) slot, not left-click, so stray
## clicks can't waste it. Any other item holds the same way: a weapon brings its own
## rig, a material brings no action at all.
func equip(character: Character) -> void:
	var node: Weapon = mount_in_hand(character)
	if node == null:
		return
	var consume: ConsumeAbility = ConsumeAbility.new()
	consume.consumable = self
	consume.name = "Drink"
	consume.icon = item_icon # the ability-bar tile shows the potion itself
	consume.cooldown = float(shared_cooldown_ms) / 1000.0
	consume.root_s = float(use_freeze_ms) / 1000.0
	# Category-shared, character-persistent cooldown — the SAME mechanism weapon abilities
	# use (Character.ability_cooldowns), keyed by cooldown_category instead of the ability
	# path. So every potion in a category shares ONE cooldown that survives unequip+re-equip
	# (no reset exploit) and blocks across types (no heal->mana chug). _stamp_cooldown banks
	# it on drink; restoring it here on mount keeps the bar's cooldown sweep correct too.
	var cd_key: String = "consumable:" + str(cooldown_category)
	consume.set_meta(&"cooldown_key", cd_key)
	if character.ability_cooldowns.has(cd_key):
		consume.last_action_time = character.ability_cooldowns[cd_key]
	node.set_special_ability(consume)


func unequip(character: Character) -> void:
	unmount_hand(character)
