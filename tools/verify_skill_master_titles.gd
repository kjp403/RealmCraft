extends SceneTree
## Verify the level-99 Skill Master title system end to end.
##   godot --headless --path . -s tools/verify_skill_master_titles.gd
##
## Most of what is checked here fails SILENTLY in the game. A title keyed to a
## slug that does not exist simply never fires; a title that leaks into the
## premium set is deleted from every player who earned it on their next zone
## change; an emitter over budget costs frame time only in a crowd. None of those
## raise an error, and none show up in a single-player smoke test, which is what
## makes them worth a tool.

## Total checks this tool is expected to run. A GDScript runtime error does not
## stop the script, it abandons the CURRENT FUNCTION and carries on — so a
## section that dies half way through simply prints fewer lines and the tool
## still reports green. That happened for real here (JobRegistry is not reliably
## loadable in a -s run, see _check_table), and a verifier that passes because it
## silently skipped its most important assertion is worse than no verifier.
## Counting is the guard.
const EXPECTED_CHECKS: int = 33

var _fail: int = 0
var _ran: int = 0


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), label)
	_ran += 1
	if not ok:
		_fail += 1


func _initialize() -> void:
	_check_table()
	_check_catalog()
	_check_particles()
	_check_grants()
	if _ran != EXPECTED_CHECKS:
		print("  FAIL  ran %d checks, expected %d — a section aborted early"
			% [_ran, EXPECTED_CHECKS])
		_fail += 1
	print("SKILL_MASTER_TITLES %s failures=%d checks=%d"
		% ["FAIL" if _fail > 0 else "PASS", _fail, _ran])
	quit(1 if _fail > 0 else 0)


## Job slugs taken from the jobs directory rather than from [JobRegistry].
##
## Two reasons, and the second is the important one. JobRegistry builds its table
## from `static var` preloads, and in a -s run those intermittently fail
## ("Could not preload resource file .../harvesting.tres") which leaves the whole
## class uncompiled — the autoloaded DailyQuestManager trips over the same thing
## on startup. Depending on it here made this tool abandon its slug check without
## saying so.
##
## But the directory is also the BETTER source of truth: it is where JobRegistry
## itself gets its list, so reading it catches a job whose .tres was added and
## never given a title, which a JobRegistry cross-check could not.
func _job_slugs() -> PackedStringArray:
	var out: PackedStringArray = []
	for f: String in ResourceLoader.list_directory("res://source/common/gameplay/jobs/"):
		if f.ends_with(".tres"):
			out.append(f.get_basename())
	out.sort()
	return out


func _check_table() -> void:
	print("-- table --")
	_check(SkillMasterTitles.BY_JOB.size() == 11, "11 mastery titles (got %d)"
		% SkillMasterTitles.BY_JOB.size())
	_check(
		SkillMasterTitles.UNLOCK_LEVEL == SkillXp.LEVEL_CAP,
		"unlock level tracks the XP cap (%d)" % SkillMasterTitles.UNLOCK_LEVEL
	)

	# THE SLUG TRAP. Crafting is "outfitting" and Farming is "harvesting"; a table
	# written against display names looks completely correct and never fires,
	# because PlayerResource.skills is keyed by slug and the lookup finds nothing.
	var slugs: PackedStringArray = _job_slugs()
	_check(slugs.size() == 11, "found 11 job definitions on disk (got %d)" % slugs.size())
	var unknown: PackedStringArray = []
	for job: StringName in SkillMasterTitles.BY_JOB:
		if not slugs.has(String(job)):
			unknown.append(String(job))
	_check(unknown.is_empty(), "every title slug is a real job %s" % str(unknown))

	# ...and the other direction: a skill with no title is a hole in the set.
	var uncovered: PackedStringArray = []
	for slug: String in slugs:
		if not SkillMasterTitles.BY_JOB.has(StringName(slug)):
			uncovered.append(slug)
	_check(uncovered.is_empty(), "every job has a title %s" % str(uncovered))

	_check(
		SkillMasterTitles.ORDER.size() == SkillMasterTitles.BY_JOB.size(),
		"display order covers every title"
	)

	# fx indexes both the shader branch and the emitter set, so a duplicate or a
	# gap silently gives two titles the same look.
	var seen: Dictionary = {}
	for job: StringName in SkillMasterTitles.BY_JOB:
		seen[int((SkillMasterTitles.BY_JOB[job] as Dictionary).get("fx", -1))] = true
	var contiguous: bool = true
	for i: int in 11:
		if not seen.has(i):
			contiguous = false
	_check(contiguous and seen.size() == 11, "fx indexes are 0-10, unique")

	# Round-trip every name so a typo in one direction cannot go unnoticed.
	var broken: PackedStringArray = []
	for job: StringName in SkillMasterTitles.BY_JOB:
		var title: String = SkillMasterTitles.title_for(job)
		if title.is_empty() or SkillMasterTitles.job_for_title(title) != job:
			broken.append(String(job))
	_check(broken.is_empty(), "title <-> job round-trips %s" % str(broken))
	_check(
		SkillMasterTitles.job_for_title("master miner") == &"mining",
		"title lookup is case-insensitive"
	)
	_check(SkillMasterTitles.job_for_title("Gilded") == &"", "premium titles are not mastery")


func _check_catalog() -> void:
	print("-- catalog --")
	var missing: PackedStringArray = []
	var premium_leak: PackedStringArray = []
	for job: StringName in SkillMasterTitles.BY_JOB:
		var title: String = SkillMasterTitles.title_for(job)
		if not TitleCatalog.has_vfx(title):
			missing.append(title)
		# THE STRIP TRAP. CommandPermissions.strip_unreleased_vfx deletes any
		# title matching is_premium_name from a non-staff player on EVERY instance
		# spawn. A mastery title that ends up in TitleCatalog.PREMIUM would be
		# taken back off everyone who earned it, on their next zone change, with
		# no error anywhere.
		if TitleCatalog.is_premium_name(title):
			premium_leak.append(title)
	_check(missing.is_empty(), "every mastery title resolves VFX %s" % str(missing))
	_check(premium_leak.is_empty(), "no mastery title is premium (would be stripped) %s"
		% str(premium_leak))

	var spec: Dictionary = TitleCatalog.spec("Forge Master")
	_check(int(spec.get("fx", -1)) == 1, "catalog spec carries the fx index")
	_check(not str(spec.get("color", "")).is_empty(), "catalog spec carries a colour")

	var roster: Array = TitleCatalog.vault_roster()
	var in_roster: int = 0
	for row: Variant in roster:
		if SkillMasterTitles.is_mastery_title(str((row as Dictionary).get("name", ""))):
			in_roster += 1
	_check(in_roster == 11, "all 11 appear in the vault roster (got %d)" % in_roster)


func _check_particles() -> void:
	print("-- particles --")
	var over_budget: PackedStringArray = []
	var wrong_depth: PackedStringArray = []
	var gpu: PackedStringArray = []
	var emitters: int = 0
	for fx: int in 11:
		var layer: TitleParticles = TitleParticles.new()
		layer.fx = fx
		# build() explicitly rather than parenting and waiting for _ready: a node
		# added during _initialize() does not get _ready until the tree ticks, and
		# this tool quits before that — so the emitters would all read as absent.
		layer.build()
		if layer.z_index != TitleParticles.NAMEPLATE_Z or layer.z_as_relative:
			wrong_depth.append("fx%d" % fx)
		for child: Node in layer.get_children():
			if child is GPUParticles2D:
				gpu.append("fx%d" % fx)
				continue
			var p: CPUParticles2D = child as CPUParticles2D
			if p == null:
				continue
			emitters += 1
			if p.amount < TitleParticles.MIN_AMOUNT or p.amount > TitleParticles.MAX_AMOUNT:
				over_budget.append("fx%d amount=%d" % [fx, p.amount])
			if p.lifetime < TitleParticles.MIN_LIFETIME or p.lifetime > TitleParticles.MAX_LIFETIME:
				over_budget.append("fx%d life=%.2f" % [fx, p.lifetime])
		layer.free()
	_check(emitters > 0, "every fx builds emitters (got %d)" % emitters)
	_check(gpu.is_empty(), "CPUParticles2D only, web-safe %s" % str(gpu))
	_check(over_budget.is_empty(), "amount 10-25 and life 0.5-1.2s %s" % str(over_budget))
	_check(wrong_depth.is_empty(), "particle layers sit at absolute z 5 %s" % str(wrong_depth))


## The grant paths, against a throwaway PlayerResource. No database and no
## WorldServer here, which is exactly what the service is written to tolerate —
## it saves and notifies only when those exist.
func _check_grants() -> void:
	print("-- grants --")
	var pr: PlayerResource = PlayerResource.new()
	pr.skills = {
		&"mining": {"level": 99, "xp": 0, "perks": {}},
		&"outfitting": {"level": 99, "xp": 0, "perks": {}},
		&"fishing": {"level": 98, "xp": 0, "perks": {}},
	}

	var granted: PackedStringArray = SkillMasterTitleService.sync(pr)
	_check(granted.size() == 2, "retroactive sweep grants both 99s (got %d)" % granted.size())
	_check(pr.titles_unlocked.has("Master Miner"), "Master Miner granted")
	# The slug trap again, from the other end: this is the grant that a
	# display-name-keyed table would have missed.
	_check(pr.titles_unlocked.has("Grand Artisan"), "Grand Artisan granted (outfitting)")
	_check(not pr.titles_unlocked.has("Deep Sea Legend"), "level 98 grants nothing")
	_check(not pr.display_title.is_empty(), "a bare account auto-wears its first title")

	# Idempotent: this runs on EVERY login.
	var again: PackedStringArray = SkillMasterTitleService.sync(pr)
	_check(again.is_empty(), "second sweep grants nothing (got %d)" % again.size())

	# A chosen title must never be overwritten by a later grant.
	pr.display_title = "Gilded"
	pr.skills[&"prayer"] = {"level": 99, "xp": 0, "perks": {}}
	SkillMasterTitleService.sync(pr)
	_check(pr.titles_unlocked.has("High Priest"), "later 99s still grant")
	_check(pr.display_title == "Gilded", "a worn title is never replaced")

	# Untouched skills must not be created by the sweep — get_skill() would.
	_check(not pr.skills.has(&"herblore"), "the sweep does not create skill rows")

	# LIVE PATH. attach() then emit, exactly as add_skill_xp does.
	var live: PlayerResource = PlayerResource.new()
	SkillMasterTitleService.attach(live)
	live.skills = {&"slayer": {"level": 99, "xp": 0, "perks": {}}}
	live.skill_leveled.emit(&"slayer", 99)
	_check(live.titles_unlocked.has("Slayer Master"), "live signal grants at 99")
	live.skill_leveled.emit(&"slayer", 99)
	_check(live.titles_unlocked.size() == 1, "live grant does not duplicate")
	live.skill_leveled.emit(&"cooking", 42)
	_check(live.titles_unlocked.size() == 1, "a non-99 level grants nothing")

	# attach() is called on every login and PlayerResource instances survive a
	# reconnect takeover, so a second attach must not stack a second handler.
	SkillMasterTitleService.attach(live)
	var live2: PlayerResource = PlayerResource.new()
	SkillMasterTitleService.attach(live2)
	live2.skills = {&"fletching": {"level": 99, "xp": 0, "perks": {}}}
	live2.skill_leveled.emit(&"fletching", 99)
	_check(live2.titles_unlocked.size() == 1, "re-attach does not double-grant")

	# And the real funnel: add_skill_xp must emit, or the live path is dead.
	var xp: PlayerResource = PlayerResource.new()
	SkillMasterTitleService.attach(xp)
	xp.skills = {&"woodcutting": {"level": 98, "xp": 0, "perks": {}}}
	xp.add_skill_xp(&"woodcutting", 100_000_000)
	_check(
		xp.titles_unlocked.has("Timber Lord"),
		"add_skill_xp emits skill_leveled and the title lands"
	)
