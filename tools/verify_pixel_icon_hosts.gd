extends Node
## Gate: a PixelIcon mounted on a UI slot must actually have a non-zero size.
##
## WHY. PixelIcon._fit drives icon.size directly, but a Container re-imposes
## size = combined minimum on its children on every sort, and a mounted icon
## reports a (0,0) minimum (EXPAND_IGNORE_SIZE). Mounting into a CenterContainer
## therefore collapsed the icon to 0x0 and the slot rendered EMPTY — with no
## error logged anywhere. That is what emptied the skilling board, the character
## daily tracker and the chest reward ledger.
##
## This gate rebuilds the real slot structure those three screens use
## (PanelContainer slot -> host -> PixelIcon.mount) with the REAL PixelIcon, and
## asserts the fitted icon is visible. It also asserts the Container form still
## fails, so the gate cannot quietly stop testing anything.

const SLOT: Vector2 = Vector2(44, 44)

var _failed: bool = false


func _ready() -> void:
	var root: Control = Control.new()
	root.size = Vector2(400, 200)
	add_child(root)
	await get_tree().process_frame

	var art: Texture2D = _make_art()

	var plain: Control = Control.new()
	plain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plain_size: Vector2 = await _probe(root, plain, art)

	var container: CenterContainer = CenterContainer.new()
	var container_size: Vector2 = await _probe(root, container, art)

	_check(plain_size.x > 0.0 and plain_size.y > 0.0,
		"plain Control host renders the icon (size %s)" % plain_size)
	_check(container_size.x == 0.0,
		"Container host still collapses the icon (size %s) - the bug this gate guards"
		% container_size)

	if _failed:
		print("VERIFY_FAIL verify_pixel_icon_hosts")
		get_tree().quit(1)
	else:
		print("VERIFY_PASS verify_pixel_icon_hosts")
		get_tree().quit(0)


## Build the real slot structure and return the mounted icon's final size.
func _probe(root: Control, host: Control, art: Texture2D) -> Vector2:
	var slot: PanelContainer = PanelContainer.new()
	slot.custom_minimum_size = SLOT
	slot.add_theme_stylebox_override(&"panel", PixelUI.slot_style())
	root.add_child(slot)
	slot.add_child(host)
	var icon: TextureRect = PixelIcon.mount(host, art)
	# Two frames: one for the deferred _fit, one for any container re-sort after it.
	await get_tree().process_frame
	await get_tree().process_frame
	return icon.size


func _make_art() -> Texture2D:
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return ImageTexture.create_from_image(img)


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true
