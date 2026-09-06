class_name CollectionLogTitles
## The green-log titles, as a title-VFX source.
##
## [TitleCatalog.spec] consults this BEFORE its PREMIUM table, which is the whole
## point of the class. PREMIUM is what
## [CommandPermissions.strip_unreleased_vfx] deletes from every non-staff player
## on each instance spawn; a boss title parked there would be taken back from the
## player who ground a 1/1000 relic for it, on their next zone change, with no
## error anywhere. Resolving here keeps [method TitleCatalog.is_premium_name]
## false for all ten while still handing the render path a full profile — the
## same arrangement [SkillMasterTitles] has, and for the same reason.
##
## SCANS THE LOG RESOURCES ITSELF rather than calling CollectionLogManager.
## That manager is an autoload, so its identifier does not resolve in a `-s` tool
## or anywhere else without autoloads — and TitleCatalog is common code reached
## from both. The scan is one directory walk, cached for the process.

const LOGS_PATH: String = "res://source/common/gameplay/collection_log/logs/"

## title string -> {name, color, vip_tier, boss}. Empty until the first scan.
static var _by_title: Dictionary[String, Dictionary] = {}
static var _scanned: bool = false


## Spec for [param title], or {} when no boss awards it. Shape matches what
## [TitleCatalog.spec] returns for every other family, so nothing downstream has
## to know which family a name came from.
static func spec(title: String) -> Dictionary:
	_scan()
	var needle: String = title.strip_edges()
	if needle.is_empty():
		return {}
	if _by_title.has(needle):
		return _by_title[needle]
	# Case-insensitive fallback, matching how TitleCatalog resolves PREMIUM by
	# display name — a title typed into a command should still resolve.
	for known: String in _by_title:
		if known.to_lower() == needle.to_lower():
			return _by_title[known]
	return {}


## Every green-log title, for tooling and the log menu.
static func all_titles() -> PackedStringArray:
	_scan()
	var out: PackedStringArray = PackedStringArray()
	for title: String in _by_title:
		out.append(title)
	return out


## True when some boss awards this exact title.
static func is_green_log_title(title: String) -> bool:
	return not spec(title).is_empty()


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	for path: String in FileUtils.get_all_file_at(LOGS_PATH, "*.tres"):
		# Untyped load then an `is` check: in exports the custom-class loader may
		# not be registered when this first runs, and a typed hint would trip the
		# resource loader. Same pattern as the BossHuntCatalog scan.
		var loaded: Resource = ResourceLoader.load(path)
		if loaded == null or not (loaded is BossCollectionLog):
			continue
		var boss_log: BossCollectionLog = loaded
		var title: String = boss_log.green_log_title_text.strip_edges()
		if title.is_empty() or _by_title.has(title):
			continue
		_by_title[title] = {
			"name": title,
			"color": "#" + boss_log.green_log_title_color.to_html(false),
			# The profile key drives the whole VIP render path. Empty = the title
			# falls back to the flat `style` branch, which is a plain-looking
			# title rather than an error — the same graceful miss VipTierProfile
			# .for_tier documents.
			"vip_tier": String(boss_log.green_log_profile),
			"style": boss_log.green_log_title_style,
			# NOT vip: that flag drives donation-ladder-only chrome. These are
			# earned, and the profile is what makes them look expensive.
			"vip": false,
			"boss": boss_log.boss_name,
		}
