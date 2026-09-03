class_name PotionItem
extends ConsumableItem
## A COMBINATION draught: a potion whose effect is more than "restore X" or
## "raise one stat".
##
## Extends [ConsumableItem] rather than replacing it, so every combination
## draught inherits — unchanged — the drink cooldown, the sip-root, the hotbar
## mount, the one-draught-at-a-time slot, the client cooldown stamp and the bag
## removal. Those are the parts that took the longest to get right; a parallel
## potion class would have had to re-earn all of them.
##
## Two shapes live here:
##
## 1. COATING draughts (Corrosive Ember, Venom) arm your WEAPON. They reuse
##    [member ConsumableItem.coating_kind] with two new kinds, so
##    [method CoatingService.on_hit] — already wired into the single choke point
##    every melee arc and projectile passes through — carries them with no new
##    hook. The extra numbers those kinds need live in the Corrosion / Venom
##    groups below.
##
## 2. AURA draughts (Cinder-Guard, Aegis, Shadowveil, Provocation) arm the
##    DRINKER. They set [member aura_effect] and are handed to
##    [StatusEffectManager], which owns every effect family [BuffService]
##    structurally cannot hold: stacks with caps, per-source cooldowns, a stealth
##    override, and a repeating pulse.
##
## A draught may be both a stat buff and an aura (Cinder-Guard is armor plus a
## retaliation aura); the base class's buff_stat plus [member extra_buffs] cover
## the stat half and the aura covers the rest.


@export_group("Extra Buffs")
## Additional timed stat grants beyond the base class's single buff_stat, each
## with its OWN duration. See [PotionBuff]. Empty for a single-stat potion.
##
## These ride [BuffService] exactly like the base buff, which means they refresh
## rather than stack and are stripped together on death. They are NOT marked
## exclusive individually — the draught's [member ConsumableItem.exclusive_buff]
## already claims the one combat-draught slot for the whole vial.
@export var extra_buffs: Array[PotionBuff] = []

@export_group("Corrosion", "corrode_")
## Armor stripped PER STACK, as a fraction of the victim's armor (0.03 = 3%).
## Percentage, not flat, so one draught stays meaningful against both a 40-armor
## goblin and a 900-armor boss without an authored table per tier.
@export_range(0.0, 0.2, 0.005) var corrode_armor_per_stack: float = 0.0
## Hard cap on simultaneous stacks on one victim. The design budget is
## [member corrode_armor_per_stack] times this — keep the product inside
## 0.10-0.15 or a coordinated group strips a boss to paper.
@export var corrode_max_stacks: int = 5
## Seconds a stack lives before it decays. REFRESH-ONLY: a fresh hit re-arms the
## clock on the existing stacks instead of extending them one by one, so a long
## fight cannot ratchet a permanent debuff onto a boss. Keep it SHORT (6-10s) —
## this window is the whole reason the effect is not stat-crushing.
@export var corrode_duration_s: float = 0.0

# The burn that rides alongside the strip is the base class's coating_potency
# over coating_hit_duration_s. One authored damage number per coating, shared by
# every kind, rather than a second field per family that could drift out of step
# with the first — and it keeps a corroding hit comparable to an Ember hit at a
# glance, which is the comparison the price of the draught has to justify.

@export_group("Venom", "venom_")
## One venom per PLAYER SOURCE on a given victim. True (the only sane setting)
## keys the effect by the applying player, so two players' venoms tick
## independently while a single player re-hitting only ever REFRESHES their own.
## That is the whole exploit guard: without the per-source key, the strongest
## venom in a group is repeatedly overwritten by the weakest.
@export var venom_per_source: bool = true
## Hard ceiling on how long ONE application may be kept alive by refreshes.
##
## The venom ticks for [member ConsumableItem.coating_hit_duration_s] and every
## landed hit tops that timer back up — which, on its own, means a player who
## keeps swinging holds the venom forever and it stops being a burst they set up
## and re-earn. This deadline is stamped when the venom FIRST lands and is never
## moved, so refreshes can fill the timer but not push past it. When it lapses
## the effect drops and the next hit starts a fresh application with a fresh
## deadline — so the uptime is high but never total, and the ceiling on what one
## application can deal is a number rather than "however long the fight runs".
##
## 0 = uncapped, which is how every DoT behaved before this existed.
@export var venom_max_lifespan_s: float = 30.0

@export_group("Aura", "aura_")
## Which [StatusEffectManager] family this draught arms on the DRINKER.
## Empty = not an aura draught. One of the EFFECT_ constants on
## [StatusEffectManager].
@export var aura_effect: StringName = &""
## Seconds the aura runs. Independent of any stat buff on the same vial: the
## Aegis Elixir's armor outlives its offense on purpose.
@export var aura_duration_s: float = 0.0
## Reach in pixels, for auras that touch other bodies (Provocation's pull).
## Ignored by auras that only touch the drinker.
@export var aura_radius: float = 0.0
## Seconds between pulses, for auras that repeat (Provocation re-locks aggro on
## a cycle rather than once). 0 = the aura does not pulse.
@export var aura_pulse_s: float = 0.0
## Cap on bodies one pulse may affect, so a pull in a packed dungeon room cannot
## park thirty mobs on one player at once. Mirrors
## [member TauntAbility.max_targets] and exists for the same reason.
@export var aura_max_targets: int = 8
## Per-BODY internal cooldown in seconds for a reactive aura (Cinder-Guard's
## retaliation). Without it, one AoE swing that clips you five times returns five
## burns, which is how a defensive draught becomes the best damage draught.
@export var aura_internal_cooldown_s: float = 0.0
## Generic magnitude for the aura family — Cinder-Guard reads it as the
## retaliation burn's damage per second. Families needing no number leave it 0.
@export var aura_potency: float = 0.0
## Seconds the aura's payload lasts on whoever it lands on (Cinder-Guard's burn
## duration on the attacker). 0 = instant / not applicable.
@export var aura_payload_duration_s: float = 0.0
## Does WORKING A GATHERING NODE end the aura? Shadowveil only.
##
## This is a field rather than a constant because the two halves of the veil's
## brief pull against each other: it exists so a gatherer can reach an endgame
## patch that is guarded, but a veil that survives the gathering swing is also a
## veil that lets a player strip a contested patch with the guards standing next
## to them. Shipped true — swinging the sickle gives you away, so the veil buys
## the WALK IN and the escape, not the harvest — and flipping it is one field,
## not a code change, once there is play data to argue with.
@export var aura_breaks_on_gather: bool = true


## True when this vial arms an aura on the drinker. Same all-or-nothing rule as
## [method ConsumableItem.is_coating]: a half-authored aura reads as no aura.
func is_aura() -> bool:
	return not aura_effect.is_empty() and aura_duration_s > 0.0


## Every buff this vial grants, base plus extras, as one list. Callers must not
## read [member extra_buffs] directly or they miss the base buff_stat that most
## potions still use on its own.
func all_buffs() -> Array[PotionBuff]:
	var out: Array[PotionBuff] = []
	if not buff_stat.is_empty() and not is_zero_approx(buff_amount) and buff_duration_s > 0.0:
		var base: PotionBuff = PotionBuff.new()
		base.stat = buff_stat
		base.amount = buff_amount
		base.duration_s = buff_duration_s
		out.append(base)
	for extra: PotionBuff in extra_buffs:
		if extra != null and extra.is_valid():
			out.append(extra)
	return out


func stat_lines() -> Array[Dictionary]:
	# The base class already writes the heal / mana / prayer / single-buff /
	# coating lines and the "does not stack" warning. Only the parts it cannot
	# know about are appended here.
	var lines: Array[Dictionary] = super()
	for extra: PotionBuff in extra_buffs:
		if extra == null or not extra.is_valid():
			continue
		var number: String = (
			("%+d" % int(extra.amount)) if is_equal_approx(extra.amount, roundf(extra.amount))
			else ("%+.1f" % extra.amount)
		)
		lines.append({
			"text": "%s %s for %s" % [
				number, Stat.display_name(extra.stat), _format_duration(extra.duration_s),
			],
			"stat": extra.stat,
		})
	if corrode_armor_per_stack > 0.0 and corrode_duration_s > 0.0:
		lines.append({
			"text": "Your hits strip %s%% armor per stack, up to %d stacks (%s%%)" % [
				_format_amount(corrode_armor_per_stack * 100.0),
				corrode_max_stacks,
				_format_amount(corrode_armor_per_stack * corrode_max_stacks * 100.0),
			],
			"kind": &"poison",
		})
		lines.append({
			"text": "Corrosion fades after %s" % _format_duration(corrode_duration_s),
			"kind": &"charges",
		})
	if coating_kind == CoatingService.KIND_VENOM and coating_hit_duration_s > 0.0:
		lines.append({
			"text": "Your hits envenom for %s damage over %s" % [
				_format_amount(coating_potency * coating_hit_duration_s),
				_format_duration(coating_hit_duration_s),
			],
			"kind": &"poison",
		})
		# Both halves of the rule, because either alone reads as a different item:
		# "refreshes" without the ceiling sounds permanent, and the ceiling without
		# the refresh sounds like it just lasts 30s whatever you do.
		if venom_max_lifespan_s > 0.0:
			lines.append({
				"text": "Hits refresh the venom, up to %s on one target (%s max)" % [
					_format_duration(venom_max_lifespan_s),
					_format_amount(coating_potency * venom_max_lifespan_s),
				],
				"kind": &"charges",
			})
	if is_aura():
		for line: String in StatusEffectManager.describe(self):
			lines.append({"text": line, "kind": &"charges"})
	return lines


## The per-kind tuning the base class hands to [method CoatingService.apply].
## Empty for a plain poison / burn / heal coating, which is every potion that
## shipped before this class existed.
func coating_extras() -> Dictionary:
	match coating_kind:
		CoatingService.KIND_CORRODE:
			return {
				"armor_per_stack": corrode_armor_per_stack,
				"max_stacks": corrode_max_stacks,
				"stack_duration_s": corrode_duration_s,
			}
		CoatingService.KIND_VENOM:
			return {
				"per_source": venom_per_source,
				"max_lifespan_s": venom_max_lifespan_s,
			}
	return {}


## Drinkable? An aura draught follows the same one-draught-at-a-time rule as a
## coating or an exclusive tonic — checked HERE as well as in [method on_use] so
## the bag button, the hotbar tile and the server refuse together instead of the
## click succeeding and the sip silently failing.
func can_use(character: Character) -> bool:
	if is_aura() and exclusive_buff:
		if character is not Player:
			return false
		return not draught_slot_busy(character as Player)
	return super(character)


func on_use(character: Character) -> void:
	# A draught with neither an aura nor extra buffs is entirely the base class's
	# business — a coating-only vial (Corrosive Ember, Venom) lands here.
	if not is_aura() and extra_buffs.is_empty():
		super(character)
		return
	if character is not Player:
		return
	var player: Player = character as Player
	# Refuse BEFORE anything is spent. The base class documents this rule for
	# coatings and tonics; an aura draught that ate the vial and then declined to
	# apply would be the same bug wearing a new name.
	if exclusive_buff and draught_slot_busy(player):
		return

	var buffs: Array[PotionBuff] = all_buffs()
	for i: int in buffs.size():
		# Only the FIRST grant claims the exclusive slot. Marking all three of the
		# Aegis Elixir's buffs exclusive would leave three separate claims on a
		# slot released by expiry, so the shortest one lapsing would look like the
		# slot freeing while two buffs were still running.
		var claims_slot: bool = exclusive_buff and i == 0
		BuffService.apply(
			player, buffs[i].stat, buffs[i].amount, buffs[i].duration_s, claims_slot
		)

	if is_aura():
		StatusEffectManager.for_character(player).arm_aura(self, player)

	Inventory.remove_one_by_id(player.player_resource.inventory, get_meta(&"id"))
