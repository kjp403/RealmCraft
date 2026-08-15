extends SceneTree
## Headless gate for the Mana Seed paper-doll.
##
##     godot --headless --path . -s tools/verify_paperdoll.gd
##
## Prints VERIFY_PASS / VERIFY_FAIL. Guards the ways this silently breaks:
## a roster claiming art that is not on disk, a sheet that is not the expected
## 512x512 page, gear that resolves to no layer, and appearance packing that lets
## an out-of-range index persist.
##
## Expect "Identifier not found: Client / ClientState" noise - the client autoloads
## do not exist in a -s run. That is pre-existing.

const ROOT: String = "res://assets/sprites/characters/manaseed/"
const GEARS_DIR: String = "res://source/common/gameplay/items/gears/"

var failures: Array[String] = []
var sheets_checked: int = 0
var gear_checked: int = 0
var assertions: int = 0


func _init() -> void:
	_check_rosters()
	_check_sheets()
	_check_layout()
	_check_gear()
	_check_appearance()

	print("checked: %d sheets, %d gear pieces, %d assertions"
		% [sheets_checked, gear_checked, assertions])
	if sheets_checked == 0 or gear_checked == 0:
		_fail("verification inspected nothing - asset or gear dir missing")

	if failures.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL (%d)" % failures.size())
		for f: String in failures:
			print("  - ", f)
	quit(0 if failures.is_empty() else 1)


func _fail(message: String) -> void:
	failures.append(message)


func _sheet(layer: StringName, item: StringName, variant: StringName) -> Texture2D:
	sheets_checked += 1
	var path: String = PaperDoll.sheet_path(layer, item, variant)
	if not ResourceLoader.exists(path):
		_fail("missing sheet %s" % path)
		return null
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		_fail("unloadable sheet %s" % path)
		return null
	# Every page is one 512x512 grid; a differently-sized sheet would silently
	# sample the wrong cells rather than error.
	if texture.get_width() != PaperDollData.SHEET_SIZE \
			or texture.get_height() != PaperDollData.SHEET_SIZE:
		_fail("%s is %dx%d, expected %d square"
			% [path, texture.get_width(), texture.get_height(), PaperDollData.SHEET_SIZE])
	return texture


func _check_rosters() -> void:
	assertions += 1
	if PaperDollData.BODY_VARIANTS.is_empty():
		_fail("BODY_VARIANTS empty - did the Mana Seed importer run?")
	if PaperDollData.HAIR_STYLES.is_empty():
		_fail("HAIR_STYLES empty")
	if PaperDollData.OUTFITS.is_empty():
		_fail("OUTFITS empty")
	# Each roster is indexed by one byte of the packed appearance.
	for roster: Array in [
		PaperDollData.BODY_VARIANTS, PaperDollData.HAIR_STYLES,
		PaperDollData.HAIR_COLORS, PaperDollData.OUTFITS,
	]:
		if roster.size() > 256:
			_fail("a roster has %d entries; the appearance byte caps at 256" % roster.size())


## Every roster entry the creator can offer must have a sheet behind it.
func _check_sheets() -> void:
	for body: StringName in PaperDollData.BODY_VARIANTS:
		_sheet(PaperDoll.BODY_LAYER, &"humn", body)
	for style: StringName in PaperDollData.HAIR_STYLES:
		for i: int in PaperDollData.HAIR_COLORS.size():
			_sheet(&"4har", style, PaperDoll.variant_for(&"4har", style, i))
	for outfit: StringName in PaperDollData.OUTFITS:
		_sheet(&"1out", outfit, PaperDoll.variant_for(&"1out", outfit, 0))


## The grid constants must actually describe the sheets.
func _check_layout() -> void:
	assertions += 3
	if PaperDollData.GRID_COLS * PaperDollData.FRAME_SIZE != PaperDollData.SHEET_SIZE:
		_fail("GRID_COLS x FRAME_SIZE does not equal SHEET_SIZE")
	if PaperDollData.WALK_ROW_BASE + 3 >= PaperDollData.GRID_ROWS:
		_fail("walk rows run past the bottom of the sheet")
	for col: int in PaperDollData.RUN_COLS:
		if col >= PaperDollData.GRID_COLS:
			_fail("run column %d is past the right edge of the sheet" % col)
	if PaperDollData.RUN_FRAME_TIMES.size() != PaperDollData.RUN_COLS.size():
		_fail("RUN_FRAME_TIMES and RUN_COLS disagree on frame count")


## Every wearable piece must resolve to a real sheet, or it renders as underwear.
func _check_gear() -> void:
	_scan(GEARS_DIR)


func _scan(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan(full)
		elif entry.ends_with(".tres"):
			var gear: GearItem = load(full) as GearItem
			if gear != null and gear.slot != null \
					and PaperDoll.GEAR_LAYERS.has(gear.slot.key):
				gear_checked += 1
				var look: Array = gear.appearance_item()
				if look[0] == &"":
					_fail("%s resolves to no layer art" % entry)
					entry = dir.get_next()
					continue
				# Worn sheet must exist, or the piece renders as underwear.
				var worn: String = PaperDoll.gear_sheet_path(look[0], gear.slot.key)
				if not ResourceLoader.exists(worn):
					_fail("%s -> no worn sheet at %s" % [entry, worn])
				# And the inventory icon must come from that same sheet, or the bag
				# shows one thing and the body another - the whole point of this.
				if gear.display_icon() == gear.item_icon:
					_fail("%s falls back to its authored icon - worn and icon disagree"
						% entry)
		entry = dir.get_next()
	dir.list_dir_end()


func _check_appearance() -> void:
	assertions += 3
	var parts: Array[int] = Player.unpack_appearance(Player.pack_appearance(3, 2, 4, 5))
	if parts != [3, 2, 4, 5]:
		_fail("appearance pack/unpack round-trip broken: got %s" % [parts])
	var clean: Array[int] = Player.unpack_appearance(
		Player.sanitize_appearance(Player.pack_appearance(200, 200, 200, 200))
	)
	if clean[0] >= PaperDollData.BODY_VARIANTS.size():
		_fail("sanitize let an out-of-range body index through: %s" % [clean])
	if clean[3] >= PaperDollData.OUTFITS.size():
		_fail("sanitize let an out-of-range outfit index through: %s" % [clean])
