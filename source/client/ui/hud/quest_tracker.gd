class_name QuestTracker
extends PanelContainer
## HUD quest tracker: shows a single quest (the one pinned via the log, else the first
## active quest) with its objectives + live progress. Hidden when there's nothing to track.
## Click-through so it never blocks world interaction.

## Padding inside the card. Rides on the STYLEBOX, not a MarginContainer — same
## as a toast card, and it is what lets the panel wrap its text tightly.
const PAD_X: int = 8
const PAD_Y: int = 6

## The rail slot this panel is pinned into: Hud.RIGHT_RAIL_WIDTH (224) minus
## Hud.RIGHT_RAIL_MARGIN (8). Hud._ready() sets the anchors that make it true;
## this copy exists only so WRAP_WIDTH below can be derived rather than guessed.
const PANEL_WIDTH: float = 216.0

## How narrow / wide the player may drag the tracker. The floor is roughly the
## width at which a two-word objective still fits on one line; past the ceiling
## the panel starts eating the centre of the screen, which is the thing the right
## rail exists to prevent.
const MIN_WIDTH: float = 160.0
const MAX_WIDTH: float = 380.0

var _content: VBoxContainer
var _resizer: HudResizer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# On-theme panel: a transparent dark-neutral card (no accent bar) that reads cleanly over the
	# world under any palette — same overlay language as the chat. The palette shows through the
	# quest name instead (see _display).
	add_theme_stylebox_override(&"panel", _make_panel_style())

	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override(&"separation", 2)
	add_child(_content)

	# Width only. The tracker is a shrink-to-content PanelContainer whose HEIGHT
	# is its wrapped text, and Hud._place_right_rail re-derives that height from
	# get_combined_minimum_size() on every `resized` — a vertical handle here
	# would be a grip the player could drag that the rail would immediately
	# undo. Widening is the real control, and it grows LEFTWARD because the panel
	# is pinned to the screen edge (grow_horizontal = GROW_DIRECTION_BEGIN).
	_resizer = HudResizer.attach(
		self,
		&"quest_tracker",
		HudResizer.AXIS_X,
		HudResizer.SizeMode.MODE_MIN_SIZE,
		Vector2(MIN_WIDTH, 0.0),
		Vector2(MAX_WIDTH, 0.0)
	)
	_resizer.size_changed.connect(_on_resized_by_player)

	hide()
	ClientState.tracked_quest_changed.connect(func(_id: int): _refresh())
	ClientState.quest_progressed.connect(_on_quest_progressed)
	Client.subscribe(&"quest.update", func(_data: Dictionary): _refresh())
	# COLLECT objectives track live inventory, which never fires quest.update on its
	# own. Refresh on the two open-world item-gain pushes — loot (combat.reward) and
	# gathering (mining.gather_result) — so a "Bring N item" objective climbs live
	# instead of only updating when a menu is reopened.
	Client.subscribe(&"combat.reward", func(_data: Dictionary): _refresh())
	Client.subscribe(&"mining.gather_result", func(_data: Dictionary): _refresh())
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): _refresh())
	_refresh()


## Re-derive visibility + content from the live tracked / active quest state. Public so the HUD
## can re-validate after a menu closes — a quest may have been untracked while the tracker was
## menu-hidden, and a blind show() would otherwise resurrect it.
func refresh() -> void:
	_refresh()


## The tracked quest ticked forward: the tracker IS its progress surface
## (tracker-first — no toast for the tracked quest), so draw the eye with a
## brief brightness pulse. Content itself refreshes via the quest.update
## subscription above.
func _on_quest_progressed(quest_id: int) -> void:
	if quest_id != ClientState.tracked_quest_id or not visible:
		return
	var tween: Tween = create_tween()
	tween.tween_property(self, ^"modulate", Color(1.4, 1.32, 1.0), 0.1)
	tween.tween_property(self, ^"modulate", Color.WHITE, 0.4)


func _refresh() -> void:
	if InstanceClient.current == null:
		hide()
		return
	Client.request_data(&"quest.list", _on_received, {}, InstanceClient.current.name)


func _on_received(data: Dictionary) -> void:
	# -1 = explicitly untracked (player cleared the HUD); stay hidden.
	if ClientState.tracked_quest_id == -1:
		hide()
		return

	var tracked: Dictionary = {}
	var first_active: Dictionary = {}
	for quest: Dictionary in data.get("quests", []):
		if str(quest.get("state", "")) != "active":
			continue
		if first_active.is_empty():
			first_active = quest
		if int(quest.get("id", 0)) == ClientState.tracked_quest_id:
			tracked = quest

	if tracked.is_empty():
		if first_active.is_empty():
			hide()
			return
		# Auto-track the first active quest (set directly, no signal, to avoid a refetch loop).
		tracked = first_active
		ClientState.tracked_quest_id = int(first_active.get("id", 0))

	_display(tracked)
	show()


## The shared overlay-card look ([method PixelUI.hud_card]) — the same near-black,
## hairline accent border and radius a toast uses, so the tracker reads as part of
## the same notification system rather than as its own panel. No accent bar; the
## palette comes through the quest name instead (see _display).
##
## The old 5px drop shadow is gone deliberately: at this size it doubled the
## panel's apparent footprint and was the main reason the tracker looked like it
## was floating over the world rather than sitting in the rail.
func _make_panel_style() -> StyleBoxFlat:
	return PixelUI.hud_card(PAD_X, PAD_Y)


func _display(quest: Dictionary) -> void:
	for child in _content.get_children():
		child.queue_free()

	var complete: bool = bool(quest.get("complete", false))
	var any_mode: bool = int(quest.get("completion", 0)) == 1

	# Name leads the panel — no "QUEST" eyebrow, the layout speaks for itself. It follows the active
	# palette accent while in progress, then flips to bright green with a ✓ prefix once ready: that
	# color shift is the player's primary "I'm done!" cue.
	var prefix: String = "✓ " if complete else ""
	var name_label: Label = PixelUI.hud_text(
		prefix + str(quest.get("name", "?")),
		PixelUI.SIZE_CAPTION,
		PixelUI.INK_GREEN if complete else _accent_color()
	)
	_fit_line(name_label)
	_content.add_child(name_label)

	var objectives: Array = quest.get("objectives", [])
	# Track whether we've already pushed at least one objective into the tracker;
	# the OR separator only goes between visible objectives, so an early continue
	# (ANY-mode complete hiding unmet paths) doesn't leave a leading "OR" line.
	var any_shown: bool = false
	for objective: Dictionary in objectives:
		var count: int = int(objective.get("count", 0))
		var required: int = int(objective.get("required", 1))
		var met: bool = count >= required
		# ANY-mode complete: only show the satisfied objective so the tracker
		# isn't cluttered with paths the player chose not to take.
		if any_mode and complete and not met:
			continue
		# In-progress ANY mode: drop an "OR" between alternatives so the
		# player reads them as a choice rather than a checklist.
		if any_mode and not complete and any_shown:
			var or_label: Label = PixelUI.hud_text("OR", PixelUI.SIZE_TINY, PixelUI.INK_DIM)
			# The one line that is NOT left-aligned: it separates two alternatives
			# rather than labelling one, so it is centred between them.
			or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_fit_line(or_label)
			_content.add_child(or_label)
		var objective_label: Label = PixelUI.hud_text("", PixelUI.SIZE_TINY, PixelUI.INK)
		# VISIT rows aren't counted — show a ✓ when done, not "(0/1)".
		if bool(objective.get("countable", true)):
			objective_label.text = "• %s (%d/%d)" % [str(objective.get("desc", "")), count, required]
		else:
			objective_label.text = "• %s%s" % [str(objective.get("desc", "")), "  ✓" if met else ""]
		if met:
			objective_label.add_theme_color_override(&"font_color", PixelUI.INK_GREEN)
		_fit_line(objective_label)
		_content.add_child(objective_label)
		any_shown = true

	# Ready-to-turn-in nudge. Same line every game uses, instantly readable.
	if complete:
		var ready_label: Label = PixelUI.hud_text(
			"↩ " + str(quest.get("return_prompt", "Return to the quest giver")),
			PixelUI.SIZE_TINY,
			PixelUI.INK_GREEN
		)
		_fit_line(ready_label)
		_content.add_child(ready_label)


## The player dragged the panel wider or narrower: re-break every line that is
## already on screen. Without this the labels keep the wrap width they were built
## with, so widening leaves a ragged column in a roomy panel and narrowing pushes
## text out under the border.
## Uses the size the signal CARRIES, never self.size.
##
## Control.size does not update at the moment a size is committed — it settles on
## the next layout pass. Reading it back here made every re-wrap one drag step
## stale: the labels ended up broken to the width the panel had before the last
## mouse move, which on a fast drag is visibly wrong text.
func _on_resized_by_player(new_size: Vector2) -> void:
	var wrap: float = _wrap_width(new_size.x)
	for child: Node in _content.get_children():
		if child is Label:
			(child as Label).custom_minimum_size.x = wrap


## Where every line breaks: the panel interior at its CURRENT width.
##
## This is set explicitly on each label rather than left to the container because
## Hud._place_right_rail sizes the tracker's rail slot from
## get_combined_minimum_size().y — a Label that has not been told its width
## reports the height it would have at its longest WORD, and the rail then
## reserves a slot of the wrong height. Falls back to the authored width before
## the first layout pass, when size.x is still zero.
##
## [param panel_width] overrides the live width for callers that already know the
## size being committed — see [method _on_resized_by_player].
func _wrap_width(panel_width: float = -1.0) -> float:
	var width: float = panel_width
	if width <= 0.0:
		width = size.x if size.x > 0.0 else PANEL_WIDTH
	return maxf(width - float(PAD_X) * 2.0, 40.0)


## HUD rail is 224px by default; without wrap, "Speak with Forgemaster Helka ·
## Fire Forge, at the entrance" clips to "Speak with Forgemaster" and the
## location is lost.
func _fit_line(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = _wrap_width()


## The active palette's accent (the same hue the gateway + menus focus-tint with), read live from
## the shared [gateway]/palette setting so the quest name matches the player's chosen theme. Mirrors
## ui.gd's palette read; falls back to the default palette.
func _accent_color() -> Color:
	var saved: Variant = ClientState.settings.get_value(&"gateway", &"palette")
	var slug: StringName = StringName(saved) if saved is String or saved is StringName else ThemePalettes.DEFAULT
	return ThemePalettes.accent(slug)
