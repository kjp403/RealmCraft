extends Node
## Screenshot the REAL Character → Jobs tab at the shipping 960x540 client size,
## with the new Daily Tracker panel on the left and the existing skills grid on
## the right, so the two can be checked against each other for visual drift.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_daily_tracker_previews.tscn
##
## `-s` starts a bare SceneTree with no autoloads, and both panels reference
## ClientState / Client — under `-s` they fail to COMPILE, so there is nothing to
## screenshot. Both panels normally pull from the server; there is no server
## here, so the fixtures are pushed straight into them instead.

const MENU_SCENE: String = "res://source/client/ui/menus/character/character_menu.tscn"
const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540

var _sv: SubViewport
var _menu: Control
var _tracker: Node
var _out_abs: String


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_out_abs = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out_abs)

	_sv = SubViewport.new()
	_sv.size = Vector2i(W, H)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.transparent_bg = false
	_sv.disable_3d = true
	get_tree().root.add_child(_sv)

	var ground := ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.24, 0.30, 0.22)
	_sv.add_child(ground)

	var scene: PackedScene = load(MENU_SCENE) as PackedScene
	if scene == null:
		push_error("Could not load %s" % MENU_SCENE)
		get_tree().quit(1)
		return
	_menu = scene.instantiate() as Control
	_sv.add_child(_menu)

	await get_tree().process_frame
	await get_tree().process_frame

	_menu.call("_select", &"jobs")
	_tracker = _menu.get_node_or_null(
		"Margin/Card/Pad/Root/Content/JobsContent/JobsRow/DailyTracker"
	)
	if _tracker == null:
		push_error("DailyTracker missing from the Jobs row")
		get_tree().quit(1)
		return

	_feed_skills()

	# SHOT 1 — the ordinary mid-day state: one task running, one finished and
	# waiting to be claimed, one still un-accepted (so it is absent here, which is
	# the behaviour worth seeing), charges partly spent, most of the day left.
	_feed_board(
		4 * 3600 + 12 * 60,
		{"free_left": 2, "free_max": 3, "bonus": 0, "total": 2},
		[
			_task(0, "woodcutting", "Woodcutting", 1, 45, 100, false, false),
			_task(1, "mining", "Mining", 2, 300, 300, true, false),
			_offered(2, "fishing", "Fishing"),
		]
	)
	await _settle()
	_save(_sv.get_texture().get_image(), "daily-tracker-jobs-tab.png")

	# SHOT 2 — the states the first shot cannot show at once: a claimed task
	# greyed out, banked Dungeon Keys pushing the count past the daily 3, and the
	# countdown inside its last hour (amber, seconds ticking).
	_feed_board(
		14 * 60 + 59,
		{"free_left": 0, "free_max": 3, "bonus": 4, "total": 4},
		[
			_task(0, "woodcutting", "Woodcutting", 1, 100, 100, true, true),
			_task(1, "mining", "Mining", 2, 188, 300, false, false),
			_task(2, "harvesting", "Farming", 0, 7, 40, false, false),
		]
	)
	await _settle()
	_save(_sv.get_texture().get_image(), "daily-tracker-urgent.png")

	# SHOT 3 — nothing accepted yet: the empty hint has to carry the panel and
	# point at the board, or a new player just sees a blank box.
	_feed_board(
		21 * 3600 + 6 * 60,
		{"free_left": 3, "free_max": 3, "bonus": 0, "total": 3},
		[_offered(0, "fishing", "Fishing"), _offered(1, "cooking", "Cooking")]
	)
	await _settle()
	_save(_sv.get_texture().get_image(), "daily-tracker-empty.png")

	get_tree().quit(0)


## An ACCEPTED slot, in the exact shape DailyQuestManager.build_board_payload emits.
func _task(
	slot: int, skill: String, display: String, difficulty: int,
	progress: int, required: int, complete: bool, claimed: bool
) -> Dictionary:
	return {
		"slot": slot,
		"skill": skill,
		"skill_name": display,
		"skill_level": 40 + slot,
		"accepted": true,
		"claimed": claimed,
		"complete": complete,
		"difficulty": difficulty,
		"difficulty_name": DailyTaskResource.difficulty_name(difficulty),
		"progress": progress,
		"required": required,
		"progress_noun": DailyTaskResource.ACTION_NOUNS.get(StringName(skill), "actions"),
	}


## An un-accepted slot. The tracker must SKIP these — the choice belongs on the
## Daily Skilling Board, where the payouts are spelled out.
func _offered(slot: int, skill: String, display: String) -> Dictionary:
	return {
		"slot": slot,
		"skill": skill,
		"skill_name": display,
		"accepted": false,
		"claimed": false,
		"complete": false,
		"progress": 0,
		"required": 0,
		"progress_noun": DailyTaskResource.ACTION_NOUNS.get(StringName(skill), "actions"),
	}


func _feed_board(seconds_left: int, charges: Dictionary, entries: Array) -> void:
	_tracker.call("_apply", {
		"ok": true,
		"refresh_at_ms": int(Time.get_unix_time_from_system() * 1000.0) + seconds_left * 1000,
		"dungeon_charges": charges,
		"entries": entries,
	})


## A mid-game spread for the skills grid on the right, so the tracker is judged
## against a populated neighbour rather than a column of level 1s.
func _feed_skills() -> void:
	var levels: Dictionary = {
		"mining": 51, "smithing": 33, "fishing": 44, "cooking": 38,
		"outfitting": 22, "woodcutting": 42, "harvesting": 17,
		"fletching": 12, "herblore": 8, "slayer": 29,
	}
	var skills: Dictionary = {}
	for slug: String in levels:
		skills[slug] = {
			"display_name": JobRegistry.display_name(StringName(slug)),
			"level": int(levels[slug]),
			"xp": 1200,
			"xp_to_next": 4400,
		}
	var jobs: Node = _menu.get_node_or_null("Margin/Card/Pad/Root/Content/JobsContent")
	if jobs != null:
		jobs.call("_on_skills_received", {"skills": skills})


func _settle() -> void:
	for _i: int in 8:
		await get_tree().process_frame


func _save(image: Image, file_name: String, scale: int = 2) -> void:
	if scale > 1:
		image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var dest: String = _out_abs.path_join(file_name)
	image.save_png(dest)
	print("SAVED ", dest, " size=", image.get_size())
