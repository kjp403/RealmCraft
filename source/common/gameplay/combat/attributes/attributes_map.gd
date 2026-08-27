class_name AttributeMap
## Maps spent attribute points to combat stats, and owns the player-facing
## description of what each attribute DOES (label, colour, one-line pitch), so
## the character sheet and the server stay in sync from one place.
##
## Budget: 3 points at creation + 1 per 2 combat levels (see
## PlayerResource.attribute_points_at_level) — about 65 points at the level-126
## cap. Values are tuned so a dedicated ~60pt investment is a clear, felt
## specialization (roughly doubles the target stat) without eclipsing gear:
## every 2 levels should read as a real bump, which is the whole point of
## training multiple combat styles.
##
## All six attributes are LIVE: VITALITY (HP + out-of-combat regen), STRENGTH
## (AD), AGILITY (move speed + haste), DEFENSE (armor/MR/HP), INTELLIGENCE
## (AP + a little mana), SPIRIT (mana pool + regen).


# --- Live physical attributes -------------------------------------------------

const VITALITY: Dictionary[StringName, float] = {
	# 65 all-in ≈ +195 HP. Also the only source of faster out-of-combat healing,
	# so Vitality is the "stay on your feet, keep going" pick.
	Stat.HEALTH_MAX: 3.0,
	Stat.HEALTH_REGEN: 0.03,  # 65 pts ≈ +2 HP/s on the 0.5 base (~5x)
}

const STRENGTH: Dictionary[StringName, float] = {
	# The main driver of physical damage growth on top of your weapon.
	# 65 pts ≈ +65 AD — a maxed STR build hits far harder than an unspecced one,
	# but gear still supplies the other half of the number.
	Stat.AD: 1.0,
}

const AGILITY: Dictionary[StringName, float] = {
	# Move speed scales GENTLY on purpose — doubling it would break kiting/PvP.
	# 65 pts ≈ +39 (112 → 151, +35%).
	Stat.MOVE_SPEED: 0.6,
	# Haste shortens EVERY cooldown (attack speed for basics, CDR for specials).
	# 65 pts ≈ 26 haste ≈ 21% faster actions — diminishing, never zero.
	Stat.ABILITY_HASTE: 0.4,
}

const DEFENSE: Dictionary[StringName, float] = {
	# Armor/MR use diminishing returns (100/(100+resist)) in take_damage, so
	# stacking this is self-balancing — it never makes you immortal. HP rides
	# along so Defense reads as a bruiser pick, not pure mitigation.
	Stat.ARMOR: 1.0,
	Stat.MR: 1.0,
	Stat.HEALTH_MAX: 1.0,
}

# --- Magic attributes ----------------------------------------------------------

const INTELLIGENCE: Dictionary[StringName, float] = {
	# Mirrors STRENGTH on the magic side: scales wand bolts AND heal power
	# (heal = AP x ratio), so INT is the support stat too. Mana rides along so a
	# caster can actually afford to cast what INT is buffing.
	Stat.AP: 1.0,
	Stat.MANA_MAX: 0.5,
}

const SPIRIT: Dictionary[StringName, float] = {
	# The "use your specials more often" stat: a big pool plus the regen to
	# refill it. 65 pts ≈ +130 mana and +13/s on the 0.5 base.
	Stat.MANA_MAX: 2.0,
	Stat.MANA_REGEN: 0.2,
}


## Display order on the character sheet.
const ORDER: Array[StringName] = [
	&"vitality", &"strength", &"defense", &"intelligence", &"spirit", &"agility",
]

## Player-facing copy for each attribute. [code]blurb[/code] answers "why would I
## put a point here?" in one plain-English line — no jargon, no raw stat keys.
const INFO: Dictionary = {
	&"vitality": {
		"label": "Vitality",
		"color": Color("#3de600"),
		"blurb": "Bigger health pool and faster healing when out of combat.",
	},
	&"strength": {
		"label": "Strength",
		"color": Color("#fc7f03"),
		"blurb": "Hit harder with every melee and ranged attack.",
	},
	&"defense": {
		"label": "Defense",
		"color": Color("#d8a657"),
		"blurb": "Take less damage from both weapons and spells, plus some health.",
	},
	&"intelligence": {
		"label": "Intelligence",
		"color": Color("#a67ffb"),
		"blurb": "Stronger spells and heals, with a little extra mana.",
	},
	&"spirit": {
		"label": "Spirit",
		"color": Color("#33b5e5"),
		"blurb": "More mana and much faster mana recovery, so you cast more often.",
	},
	&"agility": {
		"label": "Agility",
		"color": Color("#dbd802"),
		"blurb": "Move quicker and shorten every attack and ability cooldown.",
	},
}


## The per-point stat table for [param attribute_name]. Empty dict = unknown name.
## Accepts the historical misspelling "strenght" so old saves keep their points.
static func stats_for(attribute_name: StringName) -> Dictionary[StringName, float]:
	var none: Dictionary[StringName, float] = {}
	match normalize(attribute_name):
		&"vitality":
			return VITALITY
		&"strength":
			return STRENGTH
		&"agility":
			return AGILITY
		&"defense":
			return DEFENSE
		&"intelligence":
			return INTELLIGENCE
		&"spirit":
			return SPIRIT
	return none


## Canonical key for an attribute name: lowercased, with the legacy "strenght"
## spelling folded into "strength". The UI has always sent "strength" while the
## table was keyed "strenght", so every Strength point silently failed to save —
## normalizing in one place is what keeps a build alive across death/relog.
static func normalize(attribute_name: StringName) -> StringName:
	var key: StringName = StringName(String(attribute_name).to_lower())
	return &"strength" if key == &"strenght" else key


## Folds a saved attributes dict onto canonical keys in place, merging any legacy
## "strenght" entry into "strength". Returns true if anything changed (worth a save).
static func normalize_dict(attributes: Dictionary) -> bool:
	var changed: bool = false
	for key: StringName in attributes.keys():
		var canon: StringName = normalize(key)
		if canon == key:
			continue
		attributes[canon] = int(attributes.get(canon, 0)) + int(attributes[key])
		attributes.erase(key)
		changed = true
	return changed


static func is_valid(attribute_name: StringName) -> bool:
	return not stats_for(attribute_name).is_empty()


static func label_for(attribute_name: StringName) -> String:
	var info: Dictionary = INFO.get(normalize(attribute_name), {})
	return str(info.get("label", String(attribute_name).capitalize()))


static func color_for(attribute_name: StringName) -> Color:
	var info: Dictionary = INFO.get(normalize(attribute_name), {})
	return info.get("color", Color(0.85, 0.85, 0.9))


static func blurb_for(attribute_name: StringName) -> String:
	var info: Dictionary = INFO.get(normalize(attribute_name), {})
	return str(info.get("blurb", ""))


static func attr_to_stats(attributes: Dictionary) -> Dictionary[StringName, float]:
	var stats: Dictionary[StringName, float]
	for attribute_name: StringName in attributes:
		var amount: int = int(attributes[attribute_name])
		add_attribute_to_stats(stats_for(attribute_name), amount, stats)
	return stats


static func add_attribute_to_stats(
	attribute: Dictionary[StringName, float],
	amount: int,
	stats: Dictionary[StringName, float]
) -> void:
	for stat_name: StringName in attribute:
		if stats.has(stat_name):
			stats[stat_name] += attribute[stat_name] * amount
		else:
			stats[stat_name] = attribute[stat_name] * amount
