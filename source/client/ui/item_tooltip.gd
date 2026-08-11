class_name ItemTooltip
## Builds an item's tooltip body: the auto-generated stat lines (from the item's real
## data via Item.stat_lines()) coloured by ROLE, above the hand-written flavor
## description. Shared by the inventory + shop detail panels so both read the same.
## The target label must be a RichTextLabel with bbcode_enabled.
##
## One colour PER STAT reads as rainbow noise, so lines are coloured by role instead:
## offense warm, defense green, resource/utility blue. Non-stat lines get their own
## cue: weapon type amber, level gate red, heal green / mana blue, charges muted.

const ROLE_COLOR: Dictionary = {
	&"offense": "e0875a",
	&"defense": "82c785",
	&"utility": "6fb0e0",
}
const STAT_ROLE: Dictionary = {
	&"ad": &"offense", &"ap": &"offense", &"ability_haste": &"offense",
	&"attack_speed": &"offense", &"attack_range": &"offense",
	&"crit_chance": &"offense", &"crit_damage": &"offense",
	&"health_max": &"defense", &"armor": &"defense", &"mr": &"defense",
	&"mana_max": &"utility", &"mana_regen": &"utility", &"move_speed": &"utility",
}
const WEAPON_COLOR: String = "e0c070"  ## amber — weapon type + power line
const LEVEL_COLOR: String = "d98080"   ## red — level gate the player does NOT meet
## Muted — a gate the player already satisfies. Still listed (it's real information),
## but red on a requirement you've met reads as "you can't use this", which is how
## every bronze tool ended up looking locked to a level-1 character.
const LEVEL_MET_COLOR: String = "9aa0aa"
const HEAL_COLOR: String = "82c785"
const MANA_COLOR: String = "6fb0e0"
const MUTED_COLOR: String = "9aa0aa"   ## charges and the like
const DEFAULT_COLOR: String = "c8c8d0" ## any stat without a role mapping
const DELTA_UP_COLOR: String = "82c785"
const DELTA_DOWN_COLOR: String = "d98080"


## Plain-text hover tooltip for bag / equipment tiles (Godot `tooltip_text`
## does not render BBCode). Includes name, auto stats, and a short flavor line.
static func hover_text(item: Item) -> String:
	if item == null:
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append(str(item.item_name))
	for entry: Dictionary in item.stat_lines():
		var text: String = str(entry.get("text", "")).strip_edges()
		if not text.is_empty():
			lines.append(text)
	var flavor: String = item.description.strip_edges()
	if not flavor.is_empty():
		# Keep hover short — first sentence / ~120 chars.
		var cut: int = flavor.find(".")
		var snippet: String = flavor.substr(0, cut + 1) if cut >= 0 and cut < 120 else flavor
		if snippet.length() > 120:
			snippet = snippet.substr(0, 117) + "…"
		lines.append(snippet)
	return "\n".join(lines)


## Builds the tooltip body. Pass [param compare_with] (the equipped
## counterpart) to append green/red per-stat deltas — stats only the equipped
## item has are listed as a red loss line. Null keeps the plain rendering, so
## shop/crafting callers are untouched.
static func body(item: Item, compare_with: Item = null) -> String:
	if item == null:
		return ""
	var sections: PackedStringArray = PackedStringArray()
	var stat_block: PackedStringArray = PackedStringArray()
	var own_stats: Dictionary = _modifier_map(item)
	var other_stats: Dictionary = _modifier_map(compare_with)
	for entry: Dictionary in item.stat_lines():
		var line: String = "[color=#%s]%s[/color]" % [_entry_color(entry, item), str(entry.get("text", ""))]
		if compare_with != null and entry.has("stat"):
			line += _delta_suffix(StringName(entry["stat"]), own_stats, other_stats)
		stat_block.append(line)
	if compare_with != null:
		for stat: StringName in other_stats:
			if not own_stats.has(stat) and not is_zero_approx(float(other_stats[stat])):
				stat_block.append("[color=#%s]%s %s (equipped)[/color]" % [
					DELTA_DOWN_COLOR, _format_signed(-float(other_stats[stat])), Stat.display_name(stat),
				])
	if not stat_block.is_empty():
		sections.append("\n".join(stat_block))
	var flavor: String = item.description.strip_edges()
	if not flavor.is_empty():
		sections.append(flavor)
	return "\n\n".join(sections)


## Public role color for a stat key — panels that render their own stat lines
## (gear totals) reuse the same palette instead of inventing one.
static func stat_color(stat: StringName) -> String:
	return ROLE_COLOR.get(STAT_ROLE.get(stat, &""), DEFAULT_COLOR)


## " (+2)" / " (−1.5)" against the equipped value; empty when equal or when
## the equipped item doesn't carry the stat (the line's own value says it all).
static func _delta_suffix(stat: StringName, own: Dictionary, other: Dictionary) -> String:
	if not other.has(stat):
		return ""
	var delta: float = float(own.get(stat, 0.0)) - float(other[stat])
	if is_zero_approx(delta):
		return ""
	var color: String = DELTA_UP_COLOR if delta > 0.0 else DELTA_DOWN_COLOR
	return " [color=#%s](%s)[/color]" % [color, _format_signed(delta)]


static func _format_signed(value: float) -> String:
	return ("%+d" % int(value)) if is_equal_approx(value, roundf(value)) else ("%+.1f" % value)


## stat_name -> summed modifier value; empty for anything that isn't gear.
static func _modifier_map(item: Item) -> Dictionary:
	var out: Dictionary
	if item is GearItem:
		for modifier: StatModifier in item.base_modifiers:
			if modifier == null:
				continue
			var key: StringName = StringName(modifier.stat_name)
			out[key] = float(out.get(key, 0.0)) + modifier.value
	return out


static func _entry_color(entry: Dictionary, item: Item = null) -> String:
	if entry.has("stat"):
		return ROLE_COLOR.get(STAT_ROLE.get(entry["stat"], &""), DEFAULT_COLOR)
	match StringName(entry.get("kind", &"")):
		&"weapon": return WEAPON_COLOR
		&"level": return LEVEL_MET_COLOR if _requirement_met(entry, item) else LEVEL_COLOR
		&"heal": return HEAL_COLOR
		&"mana": return MANA_COLOR
		&"charges": return MUTED_COLOR
	return DEFAULT_COLOR


## Does the local player satisfy the gate this entry describes? Entries without
## req_* data (or evaluated before the local player exists, e.g. a shop preview at
## load) fall back to false, keeping the old cautious red rather than promising
## access we can't verify.
static func _requirement_met(entry: Dictionary, item: Item) -> bool:
	# Profession gate (tools). ClientState mirrors skill levels for exactly this
	# kind of client-side check, and reads missing skills as level 1.
	if entry.has("req_skill"):
		return ClientState.skill_level(StringName(entry["req_skill"])) \
			>= int(entry.get("req_skill_level", 0))

	var local: LocalPlayer = ClientState.local_player
	if local == null or local.player_resource == null:
		return false
	var res: PlayerResource = local.player_resource

	# Mastery gate: the item owns the "any / one-of these categories" rule.
	if StringName(entry.get("req_kind", &"")) == &"mastery":
		return item is GearItem and (item as GearItem).meets_mastery_requirement(res)
	if entry.has("req_char_level"):
		return res.level >= int(entry["req_char_level"])
	return false
