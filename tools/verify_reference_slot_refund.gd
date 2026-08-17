@tool
extends Node
## Gate for the failed-re-equip refund rule.
##
## On spawn the server re-equips saved gear and, when a piece won't go back on,
## returns it to the bag rather than losing it. Right for a helmet, which
## physically left the bag on equip. Wrong for ammo, which is slotted BY
## REFERENCE -- the stack never left, so "returning" it mints a free arrow.
##
## Run: godot --headless --path . tools/verify_reference_slot_refund.tscn

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var arrow: Item = _item("bronze_arrow")
	var helmet: Item = _item("iron_helmet")

	_check(arrow is AmmoItem, "bronze_arrow loads as an AmmoItem")
	_check(helmet != null and helmet is not AmmoItem, "iron_helmet loads and is not ammo")

	_check(
		ServerInstance.is_reference_slotted(&"ammo", arrow),
		"ammo is reference-slotted (no refund -- it never left the bag)"
	)
	_check(
		not ServerInstance.is_reference_slotted(&"helmet", helmet),
		"a helmet is NOT reference-slotted (still refunded, as before)"
	)
	# The usual reason a re-equip fails is an id that no longer resolves. The
	# slot key is then the only thing left to judge by, so it must carry the call
	# on its own -- this is the case that actually dupes in the wild.
	_check(
		ServerInstance.is_reference_slotted(&"ammo", null),
		"a retired ammo id is still caught by its slot alone"
	)
	_check(
		not ServerInstance.is_reference_slotted(&"torso", null),
		"a retired armour id is still refunded (no behaviour change)"
	)
	_finish()


func _item(slug: String) -> Item:
	var id: int = ContentRegistryHub.id_from_slug(&"items", StringName(slug))
	return ContentRegistryHub.load_by_id(&"items", id)


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
