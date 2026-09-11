extends Node2D
## Client half of [ChampionStatue]: the plaque, the champions fetch and the
## click-to-profile. The statue adds this as a child from its _ready, loading it
## BY PATH and only on a client, so the world server never parses this file.
##
## WHY IT IS SPLIT. This code names ClientState, Client, InstanceClient,
## LocalPlayer, ClickableArea and GameMode. While it lived in champion_statue.gd,
## every world-server boot compiled that client class graph when it loaded the
## Guild Hall (a load_at_startup map), and Godot 4.7.1 intermittently segfaulted
## inside that load(). On 2026-09-11 that was 52 and then 58 crash-restarts on
## back-to-back deploys and the world down for half an hour. Reproduced locally:
## the world server crashed in 5 of 12 boots with the old script, 0 of 10 with
## the client code removed. tools/verify_champion_statue_split.tscn keeps
## client identifiers out of the statue script.
##
## Children are added to THIS Node2D rather than the statue, so they share the
## statue's transform exactly as before without adding to a parent mid-_ready.

## "level" maps to the Skills-panel Total Level board (not combat level).
const BOARD_BY_CATEGORY: Dictionary = {
	"pve": "pve_total",
	"pvp": "pvp_total",
	"level": "total_level",
}
const CATEGORY_LABEL: Dictionary = {"pve": "PvE", "pvp": "PvP", "level": "Level"}

var statue: ChampionStatue
## player_id of the displayed champion, for the click-to-profile (0 = none yet).
var _champion_id: int = 0
var _plaque: Label
var _hovered: bool = false
var _fetching: bool = false # dedupes the _ready + local_player_ready double-call into one request


func _ready() -> void:
	statue = get_parent() as ChampionStatue
	if statue == null:
		push_error("champion_statue_client.gd must be a child of a ChampionStatue")
		return
	statue.progress_bar.hide()
	statue.display_name_label.hide() # the plaque carries the name instead
	_build_plaque()
	_spawn_click_area()
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer) -> void: _refresh())
	# DEFERRED, not immediate. Godot readies children before parents, so when this
	# statue runs _ready the enclosing InstanceClient has NOT run its own yet and
	# InstanceClient.current is still null (InstanceManagerClient clears it during
	# the swap and only reassigns it in InstanceClient._ready). An immediate call
	# bailed on that null check — and on a map change local_player_ready never
	# fires again, because the avatar node is reused across maps and _ready runs
	# once per node. So walking into the Guild Hall left every statue on the
	# plaque's built-in empty text: no name, no score, ever. Deferring to the end
	# of the frame lets InstanceClient._ready land first. Same fix TerritoryFlag
	# uses for the same ordering (see its _request_state.call_deferred).
	_refresh.call_deferred()


## Pull the cached champions once and apply this statue's (category, rank). The _fetching guard
## collapses the deferred _ready call + the local_player_ready signal into a single request.
func _refresh() -> void:
	if InstanceClient.current == null or _fetching:
		return
	_fetching = true
	var result: Array = await Client.request_data_await(
		&"leaderboard.champions", {}, InstanceClient.current.name
	)
	# The request can take up to ~5s; if a map switch freed this statue meanwhile, the resumed
	# coroutine must not touch the node. is_instance_valid works on a freed self; is_inside_tree
	# would itself error. Guard BEFORE writing any member.
	if not is_instance_valid(self) or not is_instance_valid(statue):
		return
	_fetching = false
	if result[1] != OK:
		return
	var champions: Dictionary = (result[0] as Dictionary).get("champions", {})
	var ranked: Array = champions.get(BOARD_BY_CATEGORY.get(statue.category, "total_level"), [])
	if statue.rank < 1 or statue.rank > ranked.size():
		_champion_id = 0
		_plaque.text = "%s\n(unclaimed)" % _rank_label()
		return
	var entry: Dictionary = ranked[statue.rank - 1]
	_champion_id = int(entry.get("id", 0))
	statue.skin_id = int(entry.get("skin_id", 1)) # Character's setter swaps the sprite
	if statue.animated_sprite != null and statue.animated_sprite.sprite_frames != null \
			and statue.animated_sprite.sprite_frames.has_animation(&"idle"):
		statue.animated_sprite.play(&"idle")
	_plaque.text = "%s\n%s\n%s" % [
		_rank_label(),
		str(entry.get("name", "?")),
		_score_line(int(entry.get("score", 0))),
	]


## "#2 Level" / "#1 PvE" — the rank + category line atop the plaque.
func _rank_label() -> String:
	return "#%d %s" % [statue.rank, CATEGORY_LABEL.get(statue.category, "")]


func _score_line(score: int) -> String:
	match statue.category:
		"level":
			return "Total Level %d" % score
		_:
			return "%s kills" % _comma(score)


func _build_plaque() -> void:
	_plaque = Label.new()
	_plaque.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plaque.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plaque.z_index = 10
	# Scaled-down crisp text, mirroring DisplayNameLabel (scale 0.x + big font). Tweak the
	# position/scale here or in the scene if the plaque sits off over a given map.
	_plaque.scale = Vector2(0.25, 0.25)
	_plaque.custom_minimum_size = Vector2(480, 0)
	_plaque.position = Vector2(-60, -70)
	_plaque.add_theme_font_size_override(&"font_size", 32)
	_plaque.add_theme_constant_override(&"outline_size", 6)
	_plaque.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	_plaque.add_theme_color_override(&"font_color", Color(1.0, 0.92, 0.7))
	# Seed the rank line so a statue is never a blank pedestal: if the champions
	# fetch is slow, times out, or errors, the plaque still reads "#1 Level".
	_plaque.text = _rank_label()
	add_child(_plaque)


## Click -> open the champion's profile by player_id (works offline; reuses the click-a-player
## flow). Hover suppresses the local player's attack so a click doesn't also fire the weapon.
func _spawn_click_area() -> void:
	var area: ClickableArea = ClickableArea.new()
	var collision: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(28, 44)
	collision.shape = rect
	collision.position = statue.animated_sprite.position
	area.add_child(collision)
	add_child(area)
	area.clicked.connect(_on_clicked)
	area.mouse_entered.connect(_set_hover.bind(true))
	area.mouse_exited.connect(_set_hover.bind(false))
	area.tree_exiting.connect(_set_hover.bind(false))


func _on_clicked() -> void:
	if _champion_id > 0:
		ClientState.player_profile_requested.emit(_champion_id)


func _set_hover(on: bool) -> void:
	if not GameMode.is_client() or on == _hovered:
		return
	_hovered = on
	ClientState.world_interactables_hovered += 1 if on else -1


## 12400 -> "12,400" for the plaque score line.
func _comma(n: int) -> String:
	var s: String = str(n)
	var out: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
