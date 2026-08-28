extends Control
## The first-30-minutes coach. Runs the short, guided lessons the Charter Intake
## NPCs hand out, and the one unprompted nudge (your first mastery point).
##
## A lesson is a list of STEPS. A step with a `panel` makes the player open that
## dock panel themselves — a banner names the button, the button pulses, and the
## explanation card only appears once the panel is actually open. That is the
## whole point: reading "the bag button opens your inventory" teaches nobody, so
## the tour refuses to advance until the thing is on screen.
##
## Added as a HUD child (like DungeonHud), so the dock buttons are siblings.
## Progress is remembered per CHARACTER in the client settings, which is why a
## second character on the same install gets the tour again.
##
## No class_name on purpose — the HUD preloads this by path.

const TutorialCard: GDScript = preload("res://source/client/ui/hud/tutorial_card.gd")

const SETTINGS_SECTION: StringName = &"onboarding"
const BANNER_TOP_MARGIN: float = 74.0

## Dock button node names (children of HUD/BottomMenuDock), keyed by the panel
## id the HUD reports when one opens.
const DOCK_BUTTONS: Dictionary = {
	&"inventory": "InventoryDockButton",
	&"equipment": "EquipmentDockButton",
	&"skills": "SkillsDockButton",
	&"mastery": "MasteryDockButton",
	&"quests": "QuestsDockButton",
}

## topic -> ordered steps. A step is:
##   panel  — dock panel the player must open before the card shows (optional)
##   prompt — banner text shown while waiting for that panel
##   title / body — the card
const LESSONS: Dictionary = {
	&"menus": [
		{
			"panel": &"inventory",
			"prompt": "Open your [b]Inventory[/b] — the bag on the bottom dock (or press I).",
			"title": "Your Inventory",
			"body": """Everything you own lives here: weapons, armour, materials, food, potions and your gold.

·  [b]Right-click[/b] a square for its actions — Use, Equip, Drop, or Bind to 1-2-3 for the quick bar.
·  [b]Double-click[/b] uses or equips it straight away. [b]Shift+click[/b] swaps a piece of armour instantly.
·  Items stack only so far, and a full bag means new drops stay on the ground. Sell or bank what you are not using.
·  Bags 1-3 are the tabs at the top. The first is yours; the others are bought later with gold.""",
		},
		{
			"panel": &"equipment",
			"prompt": "Now open your [b]Equipment[/b] — the armour button on the dock.",
			"title": "Your Equipment",
			"body": """Eight slots: head, amulet, weapon, body, ring, boots, ammo and relic.

·  Items always arrive in your inventory first. Equipping moves one into a slot.
·  Your weapon decides how you fight [i]and[/i] which Mastery tree earns experience.
·  The Combat Level under the slots is derived from your weapon masteries — it is not a quest reward.
·  None of it is permanent. Swap weapons whenever you like, outside of a fight.""",
		},
		{
			"panel": &"quests",
			"prompt": "Last one: open your [b]Quests[/b] from the dock.",
			"title": "Your Quests",
			"body": """Three tabs: Active, Completed, and the ones you have not started.

·  Pick a quest to read its objectives, its rewards, and where the work is.
·  [b]Track[/b] pins it to the edge of the screen so the next objective follows you around.
·  Objectives tick as you play — enemies killed, items brought, things crafted, people spoken to.
·  Quests are the fastest gold and experience early on. The Daily Board is extra work, not a direction.""",
		},
		{
			"title": "That is the interface",
			"body": """The bottom dock holds Inventory, Equipment, Skills, Mastery, Quests, Friends, Prayers and Settings. The same button closes what it opened, and [b]Esc[/b] closes everything.

Nothing in here is hidden from you later — if you forget a detail, open the panel and poke at it.""",
			"button": "Back to the desk",
		},
	],
	&"mastery": [
		{
			"title": "Weapon Mastery",
			"body": """Five weapons, five separate trees: [b]Sword, Hammer, Bow, Wand and Book[/b].

·  Killing something grants Mastery experience to the tree of the weapon [i]in your hand[/i] — and to nothing else.
·  Mastery levels are their own track, apart from your character level. Your character level is derived from them.
·  You are not picking a class. Train all five on the same character if you want to; the kit in your bag has one of each.""",
		},
		{
			"title": "Earning and spending points",
			"body": """·  You earn [b]1 mastery point every 3 mastery levels[/b] in a tree. The first arrives at Mastery Level 3.
·  Points belong to the tree that earned them. Sword points cannot buy Bow nodes.
·  A node costs its tier: a tier-1 node costs 1 point, a tier-3 node costs 3.
·  Tiers unlock with the tree's level — tier 1 at Lv 1, tier 2 at Lv 3, tier 3 at Lv 6, tier 4 at Lv 10, tier 5 at Lv 15.
·  Nothing is locked in forever. Horizon, in the tavern, refunds a whole tree for gold.""",
		},
		{
			"title": "Abilities and passives",
			"body": """A node is one of two things.

·  [b]Passives[/b] raise your stats the moment you learn them, and most of them keep working no matter which weapon you are holding — so points spent in any tree still build the same character.
·  [b]Abilities[/b] are the moves you fire. A higher-tier node upgrades the one below it, so buying up a chain is how an ability levels up.

An ability does nothing until it is [b]equipped[/b]: open the Mastery tree, pick your two loadout slots, and they mount on [b]Q[/b] and [b]E[/b]. Each weapon type keeps its own pair. Specials cost mana and have cooldowns — your basic attack never does.""",
		},
	],
	&"food": [
		{
			"title": "Food is the healing you can farm",
			"body": """Potions run out and no shop restocks them cheaply. Cooked food does not run out, because you make it.

·  Your kit already holds a [b]Fishing Rod[/b]. Fishing spots sit along the woodland shore.
·  Click a shrimp hole with the rod to fish it. Each catch is Fishing experience and a Raw Shrimp.
·  Raw fish does nothing. Take it to a [b]cooking fire[/b] — there is one on the beach — and cook it.
·  Cooked Shrimp heals you, stacks in your bag, and costs only your time. Better fish heal far more and unlock as your Fishing level climbs.""",
		},
	],
	&"mastery_point": [
		{
			"title": "You earned a Mastery Point",
			"body": """That tree just hit a level that hands you a point to spend.

Points buy nodes in the tree that earned them: passives that make you stronger for good, and abilities you can mount on Q and E.""",
			"button": "Show me",
		},
		{
			"panel": &"mastery",
			"prompt": "Open [b]Mastery[/b] on the dock and spend your point.",
			"title": "Spending it",
			"body": """Pick the tree matching the weapon you actually fight with, then choose a node and confirm.

Tier-1 nodes cost 1 point. If you would rather save for something deeper, that is fine — unspent points keep.

If you regret a build later, Horizon in the tavern refunds the tree for gold.""",
			"button": "Got it",
		},
	],
}

var _steps: Array = []
var _step: int = 0
var _waiting_panel: StringName = &""
var _banner: PanelContainer
var _banner_label: RichTextLabel
var _pulse_button: Button
var _pulse_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ClientState.tutorial_requested.connect(_on_tutorial_requested)
	ClientState.compact_panel_opened.connect(_on_compact_panel_opened)
	ClientState.mastery_point_earned.connect(_on_mastery_point_earned)


## Runs a lesson from the top. A lesson already in progress is replaced — the
## player asked for this one.
func start_lesson(topic: StringName) -> void:
	var steps: Variant = LESSONS.get(topic, [])
	if not steps is Array or (steps as Array).is_empty():
		return
	_clear_prompt()
	_steps = steps as Array
	_step = 0
	_run_step()


func _on_tutorial_requested(topic: StringName) -> void:
	start_lesson(topic)


## The one lesson nobody asks for: the first spendable mastery point. Shown once
## per character, then never again — a repeat nudge every third level is nagging.
func _on_mastery_point_earned(_category: StringName, _level: int) -> void:
	if _seen(&"mastery_point"):
		return
	_mark_seen(&"mastery_point")
	start_lesson(&"mastery_point")


func _run_step() -> void:
	if _step >= _steps.size():
		_steps = []
		return
	var step: Dictionary = _steps[_step]
	var panel: StringName = StringName(str(step.get("panel", "")))
	if panel.is_empty():
		_show_card(step)
		return
	# Gate the card on the player actually opening the panel.
	_waiting_panel = panel
	_show_prompt(str(step.get("prompt", "")), panel)


func _on_compact_panel_opened(panel: StringName) -> void:
	if _waiting_panel.is_empty() or panel != _waiting_panel:
		return
	_waiting_panel = &""
	_clear_prompt()
	if _step < _steps.size():
		_show_card(_steps[_step])


func _show_card(step: Dictionary) -> void:
	var card: Control = TutorialCard.new()
	card.title_text = str(step.get("title", ""))
	card.body_text = str(step.get("body", ""))
	card.button_text = str(step.get("button", "Got it"))
	if _steps.size() > 1:
		card.step_text = "Step %d of %d" % [_step + 1, _steps.size()]
	card.dismissed.connect(_on_card_dismissed)
	add_child(card)


func _on_card_dismissed() -> void:
	_step += 1
	_run_step()


## Non-blocking banner naming the button to press, plus a pulse on that button.
## Non-blocking matters: the player has to be able to click the thing.
func _show_prompt(text: String, panel: StringName) -> void:
	_clear_prompt()
	_banner = PanelContainer.new()
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.offset_left = -230.0
	_banner.offset_right = 230.0
	_banner.offset_top = BANNER_TOP_MARGIN
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(pad)

	_banner_label = RichTextLabel.new()
	_banner_label.bbcode_enabled = true
	_banner_label.fit_content = true
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label.add_theme_font_size_override(&"normal_font_size", 13)
	_banner_label.add_theme_font_size_override(&"bold_font_size", 13)
	_banner_label.text = "[center]%s[/center]" % text
	pad.add_child(_banner_label)

	add_child(_banner)
	_start_pulse(panel)


func _clear_prompt() -> void:
	_stop_pulse()
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
	_banner = null
	_banner_label = null


func _start_pulse(panel: StringName) -> void:
	var button: Button = _dock_button(panel)
	if button == null:
		return
	_pulse_button = button
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(button, ^"modulate", Color(1.6, 1.45, 0.7), 0.5)
	_pulse_tween.tween_property(button, ^"modulate", Color(1, 1, 1), 0.5)


func _stop_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	if _pulse_button != null and is_instance_valid(_pulse_button):
		_pulse_button.modulate = Color(1, 1, 1)
	_pulse_button = null


func _dock_button(panel: StringName) -> Button:
	var button_name: String = str(DOCK_BUTTONS.get(panel, ""))
	if button_name.is_empty():
		return null
	var hud: Node = get_parent()
	if hud == null:
		return null
	return hud.get_node_or_null("BottomMenuDock/" + button_name) as Button


## Per-character so a fresh alt is coached again on the same install.
func _flag_key(topic: StringName) -> StringName:
	if ClientState.player_id > 0:
		return StringName("char_%d_%s" % [ClientState.player_id, topic])
	return StringName("seen_%s" % topic)


func _seen(topic: StringName) -> bool:
	return bool(ClientState.settings.get_value(SETTINGS_SECTION, _flag_key(topic)))


func _mark_seen(topic: StringName) -> void:
	ClientState.settings.set_value(SETTINGS_SECTION, _flag_key(topic), true)
