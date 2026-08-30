@tool
extends SceneTree
## Guards the pixel-chrome standard across the client UI.
##
##   godot --headless --path . -s tools/verify_pixel_chrome.gd
##
## Plain `-s` is fine: this only reads source files, so it needs no autoloads.
##
## WHAT IT ENFORCES, AND WHY IT IS THE RADIUS AND NOT StyleBoxFlat
## "No StyleBoxFlat" would be the wrong rule. A StyleBoxFlat with a SQUARE 1px
## border rasterises identically to drawn pixel art — there is no curve to
## anti-alias — and it is the correct light-weight style for tabs, rows and
## chips, where a carved 9-slice frame every time reads as clutter. It is also
## the right tool for a progress FILL and a 1px rule, neither of which is a panel.
##
## The thing that cannot survive in a pixel-art UI is the ROUNDED CORNER: a
## non-zero radius is a vector curve, it anti-aliases against the pixel grid, and
## it is the single loudest "this is a web app" tell. So that is what is banned.
##
## ESCAPE HATCH
## A deliberate exception carries `# pixel-ui-exempt: <reason>` on the offending
## line or the line above. The reason is required — an exemption with no
## justification is just a silent regression with extra steps.

const SCAN_ROOT: String = "res://source/client"
const MARKER: String = "pixel-ui-exempt:"

## The gateway (login/character select) has its own theme and art direction and
## is not part of the in-game pixel chrome pass.
const SKIP_DIRS: Array[String] = [
	"res://source/client/gateway",
]

var _violations: PackedStringArray = PackedStringArray()
var _exempt_count: int = 0
var _files_scanned: int = 0


func _init() -> void:
	_scan_dir(SCAN_ROOT)
	print("[pixel chrome] scanned %d files, %d exempted" % [_files_scanned, _exempt_count])
	if _violations.is_empty():
		print("")
		print("VERIFY_PASS")
		quit(0)
		return
	print("")
	print("VERIFY_FAIL (%d)" % _violations.size())
	for v: String in _violations:
		print("  - %s" % v)
	print("")
	print("  A rounded corner is a vector curve and cannot be pixel-perfect.")
	print("  Set the radius to 0 (flat square tile: PixelUI.flat_tile / tab_button),")
	print("  or use a carved 9-slice (PixelUI.frame / panel) for a real panel.")
	print("  Deliberate exception? Add: # %s <reason>" % MARKER)
	quit(1)


func _scan_dir(path: String) -> void:
	for skip: String in SKIP_DIRS:
		if path.begins_with(skip):
			return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir(full)
		elif entry.ends_with(".gd"):
			_scan_file(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _scan_file(path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return
	_files_scanned += 1
	var lines: PackedStringArray = text.split("\n")
	for i: int in lines.size():
		var radius: int = _radius_on(lines[i])
		if radius <= 0:
			continue
		# Exempt if the marker is on this line or the one above it.
		var exempt: bool = lines[i].contains(MARKER) or (i > 0 and lines[i - 1].contains(MARKER))
		if exempt:
			_exempt_count += 1
			continue
		_violations.append("%s:%d  radius %d  |  %s" % [
			path.replace("res://source/client/", ""), i + 1, radius, lines[i].strip_edges()
		])


## The non-zero corner radius on this line, or 0. Covers both the
## set_corner_radius_all(N) call and the four per-corner property assignments.
func _radius_on(line: String) -> int:
	var stripped: String = line.strip_edges()
	if stripped.begins_with("#"):
		return 0
	if stripped.contains("set_corner_radius_all("):
		return _int_after(stripped, "set_corner_radius_all(")
	for corner: String in [
		"corner_radius_top_left", "corner_radius_top_right",
		"corner_radius_bottom_left", "corner_radius_bottom_right",
	]:
		# Only an ASSIGNMENT counts; reading one back is harmless.
		var needle: String = corner + " = "
		if stripped.contains(needle):
			return _int_after(stripped, needle)
	return 0


## First integer literal after [param prefix], or 0 when it is not a literal
## (a variable radius is not something this check can reason about).
func _int_after(line: String, prefix: String) -> int:
	var at: int = line.find(prefix)
	if at < 0:
		return 0
	var rest: String = line.substr(at + prefix.length())
	var digits: String = ""
	for c: String in rest:
		if c.is_valid_int() or (digits.is_empty() and c == "-"):
			digits += c
		else:
			break
	return int(digits) if not digits.is_empty() else 0
