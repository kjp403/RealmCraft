@tool
extends Node
## In-hand sizing gate for the square 32x32 Ascension weapon icons. Every type
## scene must carry a square_icon_scale that puts an Ascension weapon at roughly
## the same on-screen size as the atlas art it replaces — at 1.0 they towered
## over it. Hammers are the deliberate exception (heavies stay big).
##
## Sizes are measured from the icon's OPAQUE bounding box, not its 32x32 canvas:
## the icons pad differently (a tome fills far less of the square than a
## greatsword), so canvas size is not a usable stand-in for what the player sees.
##
## Run: godot --headless --path . tools/verify_weapon_grip.tscn

const ASCENSION_DIR: String = "res://assets/sprites/items/weapons/ascension/"
## type scene -> [expected scale, sample icon, authored in-hand long side px]
const TYPES: Dictionary = {
	"res://source/common/gameplay/items/weapons/sword/sword.tscn":
		[0.68, "sword_godsteel.png", 31.2],
	"res://source/common/gameplay/items/weapons/wand/wand.tscn":
		[0.7, "wand_astral.png", 32.0],
	"res://source/common/gameplay/items/weapons/book/book.tscn":
		[0.5, "book_astral.png", 16.0],
	"res://source/common/gameplay/items/weapons/bow/wooden_bow.tscn":
		[0.8, "bow_eclipse.png", 32.0],
}
## Heavies keep full size on purpose — assert it, so a future sweep can't
## quietly shrink them back.
const HEAVY: Dictionary = {
	"res://source/common/gameplay/items/weapons/hammer/hammer.tscn": 1.0,
}
## How far a type may sit from its authored art before it reads as out of place.
const TOLERANCE_PX: float = 6.0

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	for path: String in TYPES:
		var spec: Array = TYPES[path]
		var scale: float = _scale_of(path)
		_check(
			is_equal_approx(scale, float(spec[0])),
			"%s scale is %.2f (want %.2f)" % [path.get_file(), scale, float(spec[0])]
		)
		var authored: float = float(spec[2])
		# The grip turns the square icon 45 degrees, so what the player sees along
		# the weapon's long axis is the DIAGONAL of its opaque box.
		var box: Vector2 = _opaque_box(ASCENSION_DIR + String(spec[1]))
		var drawn: float = box.length() * scale
		_check(
			absf(drawn - authored) <= TOLERANCE_PX,
			"%s draws %.1fpx vs %.1fpx of authored art (icon box %dx%d)" % [
				path.get_file(), drawn, authored, int(box.x), int(box.y)
			]
		)
	for path: String in HEAVY:
		var scale: float = _scale_of(path)
		_check(
			is_equal_approx(scale, float(HEAVY[path])),
			"%s (heavy) keeps scale %.2f, got %.2f" % [path.get_file(), float(HEAVY[path]), scale]
		)
	_finish()


## square_icon_scale as the SCENE ships it (no grip pass — that is client-gated
## and a headless tool reads as a server).
func _scale_of(path: String) -> float:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		_check(false, "%s failed to load" % path)
		return -1.0
	var weapon: Weapon = scene.instantiate() as Weapon
	if weapon == null:
		_check(false, "%s root is not a Weapon" % path)
		return -1.0
	var scale: float = weapon.square_icon_scale
	weapon.free()
	return scale


## Size of the icon's non-transparent content, which is what the player reads as
## the weapon — the 32x32 canvas around it is mostly padding on some types.
func _opaque_box(path: String) -> Vector2:
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		_check(false, "%s failed to load" % path)
		return Vector2.ZERO
	var image: Image = texture.get_image()
	var used: Rect2i = image.get_used_rect()
	return Vector2(used.size)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY_PASS")
	else:
		for f: String in _failures:
			printerr("FAIL: %s" % f)
		printerr("VERIFY_FAIL (%d)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
