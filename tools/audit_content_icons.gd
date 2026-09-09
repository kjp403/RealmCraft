@tool
extends Node
## Audit: every icon the game can put on screen must actually resolve AND be
## mountable at a non-zero size.
##
##   godot --headless --path . tools/audit_content_icons.tscn
##
## SCENE mode, not `-s`: it touches ContentRegistryHub, JobRegistry and the
## client UI classes, none of which compile without autoloads.
##
## TWO FAILURE MODES, BOTH SILENT
##  1. CONTENT — an item/ability/cosmetic whose icon field is null, or points at a
##     file that no longer exists. Renders as an empty slot; nothing errors.
##  2. LAYOUT — a PixelIcon mounted into a Container. A Container hands its
##     children their combined MINIMUM size, and a mounted icon reports (0,0)
##     (EXPAND_IGNORE_SIZE), so the icon collapses to 0x0 and the slot renders
##     empty. See tools/verify_pixel_icon_hosts.gd for the mechanism.
##
## This audit walks ALL registered content for (1) and actually mounts a sample of
## every distinct icon for (2), so "the icons are fixed" is a measurement rather
## than a claim.

const REGISTRIES: Array[StringName] = [&"items", &"abilities", &"cosmetics", &"enemy_types", &"quests"]
## Registries whose entries are DRAWN AS AN ICON somewhere in the UI. Only these
## can have a "missing icon" bug. The rest are listed so this audit stays honest
## about what it did and did not check:
##   cosmetics   - raw SpriteFrames (animated VFX preview, no static icon)
##   enemy_types - a `skin: SpriteFrames`, rendered as a sprite, never an icon
##   quests      - QuestResource has no icon field at all
const ICON_BEARING: Array[StringName] = [&"items", &"abilities"]
## Fields an icon can live under, across the different content scripts.
const ICON_FIELDS: Array[StringName] = [&"item_icon", &"icon", &"portrait", &"sprite"]

var _fails: PackedStringArray = PackedStringArray()
var _host: Control


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_host = Control.new()
	_host.size = Vector2(400, 400)
	add_child(_host)
	await get_tree().process_frame

	await _audit_registries()
	await _audit_job_icons()
	await _audit_chest_icons()
	_report_ring_rename()

	print("")
	if _fails.is_empty():
		print("VERIFY_PASS audit_content_icons")
	else:
		print("VERIFY_FAIL audit_content_icons (%d)" % _fails.size())
		for f: String in _fails:
			print("  - %s" % f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _fail(msg: String) -> void:
	_fails.append(msg)


## Every entry in every content index: does it load, does it have an icon, does
## that icon have a real texture, and does it survive being mounted?
func _audit_registries() -> void:
	for reg_name: StringName in REGISTRIES:
		var registry: ContentRegistry = ContentRegistryHub.registry_of(reg_name)
		if registry == null:
			print("[%s] no registry" % reg_name)
			continue
		var ids: Array[int] = registry.all_ids()
		var no_icon: PackedStringArray = PackedStringArray()
		var bad_icon: PackedStringArray = PackedStringArray()
		var unloadable: PackedStringArray = PackedStringArray()
		var collapsed: PackedStringArray = PackedStringArray()
		var checked: int = 0
		for id: int in ids:
			var res: Resource = ContentRegistryHub.load_by_id(reg_name, id)
			var slug: String = str(registry.slug_from_id(id))
			if res == null:
				unloadable.append("%s(#%d)" % [slug, id])
				continue
			var tex: Texture2D = _icon_of(res)
			if tex == null:
				no_icon.append(slug)
				continue
			if tex.get_width() <= 0 or tex.get_height() <= 0:
				bad_icon.append(slug)
				continue
			checked += 1
			# Mount it the way the UI does and confirm it lands at a real size.
			var size: Vector2 = await _mount_size(tex)
			if size.x <= 0.0 or size.y <= 0.0:
				collapsed.append(slug)
		if not ICON_BEARING.has(reg_name):
			print("[%s] %d entries - not icon-bearing content, nothing to check" % [
				reg_name, ids.size()])
			_bucket(reg_name, "fail to load", unloadable, true)
			continue
		print("[%s] %d entries, %d with a mountable icon" % [reg_name, ids.size(), checked])
		_bucket(reg_name, "fail to load", unloadable, true)
		_bucket(reg_name, "have a broken/zero-size texture", bad_icon, true)
		_bucket(reg_name, "collapse to 0x0 when mounted", collapsed, true)
		# Every icon-bearing entry must HAVE one: it will be drawn in a slot.
		_bucket(reg_name, "have no icon", no_icon, true)


func _bucket(reg: StringName, what: String, list: PackedStringArray, is_fail: bool) -> void:
	if list.is_empty():
		print("  ok   none %s" % what)
		return
	var shown: PackedStringArray = list.slice(0, 12)
	var tail: String = "" if list.size() <= 12 else " (+%d more)" % (list.size() - 12)
	var line: String = "%s: %d %s -> %s%s" % [reg, list.size(), what, ", ".join(shown), tail]
	if is_fail:
		print("  FAIL %s" % line)
		_fail(line)
	else:
		print("  ..   %s" % line)


## The skill icons on the daily board / tracker come from JobPerks, not an index.
func _audit_job_icons() -> void:
	print("[job perks]")
	var missing: PackedStringArray = PackedStringArray()
	var collapsed: PackedStringArray = PackedStringArray()
	var slugs: Array = JobRegistry.JOBS.keys()
	for slug: Variant in slugs:
		var perks: JobPerks = JobRegistry.perks_for(StringName(str(slug)))
		if perks == null or perks.icon == null:
			missing.append(str(slug))
			continue
		var size: Vector2 = await _mount_size(perks.icon)
		if size.x <= 0.0:
			collapsed.append(str(slug))
	if slugs.is_empty():
		print("  ..   JobRegistry exposes no slug list - skipped")
		return
	print("  ..   %d jobs" % slugs.size())
	_bucket(&"job perks", "have no icon", missing, true)
	_bucket(&"job perks", "collapse to 0x0 when mounted", collapsed, true)


## Chest art is loaded by STRING PATH, so a rename is not a compile error.
func _audit_chest_icons() -> void:
	print("[chest art]")
	var missing: PackedStringArray = PackedStringArray()
	for i: int in PixelUI.CHEST_ICON.size():
		var tex: Texture2D = PixelUI.chest_texture(i)
		if tex == null:
			missing.append(PixelUI.CHEST_ICON[i])
			continue
		var size: Vector2 = await _mount_size(tex)
		if size.x <= 0.0:
			missing.append(PixelUI.CHEST_ICON[i] + " (collapsed)")
	print("  ..   %d chest tiers" % PixelUI.CHEST_ICON.size())
	_bucket(&"chest art", "fail to resolve", missing, true)


func _report_ring_rename() -> void:
	print("[bronze ring rename]")
	for family: String in ["guard", "agile", "focus", "vital"]:
		var slug := StringName("ring_%s_bronze" % family)
		var by_slug: Item = ContentRegistryHub.load_by_slug(&"items", slug) as Item
		if by_slug == null:
			print("  FAIL %s does not resolve by slug" % slug)
			_fail("%s does not resolve by slug" % slug)
			continue
		var id: int = ContentRegistryHub.id_from_slug(&"items", slug)
		var by_id: Item = ContentRegistryHub.load_by_id(&"items", id) as Item
		var ok: bool = by_id != null and by_id.item_name == by_slug.item_name
		print("  %s %-20s id %-4d %s" % ["ok  " if ok else "FAIL", slug, id, by_slug.item_name])
		if not ok:
			_fail("%s does not round-trip by id" % slug)
		var old := StringName("ring_%s_copper" % family)
		if ContentRegistryHub.load_by_slug(&"items", old) != null:
			print("  FAIL old slug %s still resolves" % old)
			_fail("old slug %s still resolves" % old)


## Mount a texture the way the UI does and return the size it actually lands at.
func _mount_size(tex: Texture2D) -> Vector2:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(32, 32)
	_host.add_child(slot)
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(host)
	var icon: TextureRect = PixelIcon.mount(host, tex)
	await get_tree().process_frame
	await get_tree().process_frame
	var size: Vector2 = icon.size
	slot.queue_free()
	return size


func _icon_of(res: Resource) -> Texture2D:
	for field: StringName in ICON_FIELDS:
		var value: Variant = res.get(field)
		if value is Texture2D:
			return value as Texture2D
	return null
