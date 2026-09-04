extends Node
## Live round trip for the green-log TITLE GRANT.
##
##   godot --headless --path . --mode=client res://tools/check_collection_log_title.tscn
##
## Runs as a SCENE because [CollectionLogTitleService] reaches
## [CollectionLogManager], an autoload identifier that does not resolve under a
## `-s` run. The first version of this check lived in the `-s` verifier, where
## sync() threw on the very first call and every assertion after it was skipped
## in silence — the suite reported PASS while testing nothing, and only the check
## COUNT gave it away. That is the reason this file exists separately.
##
## What it proves: a filled log grants its title into titles_unlocked (which is
## what the profile's Titles tab reads), the grant is idempotent, it auto-wears
## only on a bare character, and it never overwrites a title the player chose.

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var logs: Array[BossCollectionLog] = CollectionLogManager.all_logs()
	if logs.is_empty():
		_fail("no collection logs loaded")
		return _report()
	var subject: BossCollectionLog = logs[0]
	var title: String = subject.green_log_title_text

	# 1. Nothing green -> nothing granted.
	var bare: PlayerResource = PlayerResource.new()
	_expect(CollectionLogTitleService.sync(bare).size() == 0,
		"a character with no completed log was granted a title")

	# 2. Fill the log for real, then sweep.
	for slug: StringName in subject.log_items:
		CollectionLogManager.add_item_to_log(bare, subject.boss_id, slug)
	_expect(CollectionLogManager.has_green_log(bare, subject.boss_id),
		"the log did not go green after every item was credited")

	var granted: PackedStringArray = CollectionLogTitleService.sync(bare)
	_expect(granted.size() == 1 and granted[0] == title,
		"sync granted %s, expected exactly ['%s']" % [str(granted), title])
	_expect(bare.titles_unlocked.has(title),
		"the title never reached titles_unlocked, so the profile Titles tab "
		+ "would not show it")
	_expect(bare.display_title == title,
		"a bare character did not auto-wear the new title")

	# 3. Idempotent — a second sweep grants nothing, and does not duplicate.
	_expect(CollectionLogTitleService.sync(bare).size() == 0,
		"sync re-granted a title the character already holds")
	var seen: int = 0
	for t: String in bare.titles_unlocked:
		if t == title:
			seen += 1
	_expect(seen == 1, "the title appears %d times in titles_unlocked" % seen)

	# 4. A title the player CHOSE must survive the grant.
	var chosen: PlayerResource = PlayerResource.new()
	chosen.display_title = "Something They Picked"
	for slug: StringName in subject.log_items:
		CollectionLogManager.add_item_to_log(chosen, subject.boss_id, slug)
	CollectionLogTitleService.sync(chosen)
	_expect(chosen.display_title == "Something They Picked",
		"the grant overwrote a title the player had deliberately chosen")
	_expect(chosen.titles_unlocked.has(title),
		"the title was not unlocked when another one was already worn")

	# 5. Every shipped title is distinct — two bosses awarding the same string
	#    would make the second grant a silent no-op.
	var names: Dictionary = {}
	for boss_log: BossCollectionLog in logs:
		_checks += 1
		if names.has(boss_log.green_log_title_text):
			_fail("'%s' is awarded by both %s and %s"
				% [boss_log.green_log_title_text,
				names[boss_log.green_log_title_text], boss_log.boss_name])
		names[boss_log.green_log_title_text] = boss_log.boss_name

	_report()


func _expect(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fail(msg)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("CHECK_PASS  (%d assertions)" % _checks)
	else:
		for line: String in _failures:
			printerr("  FAIL: %s" % line)
		print("CHECK_FAIL  (%d failures / %d assertions)" % [_failures.size(), _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)
