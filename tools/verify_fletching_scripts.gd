extends SceneTree
## Compile check for the runtime scripts Fletching touches. `--check-only` runs
## without autoloads registered, so it false-flags every Client/Toaster
## reference; loading under a real SceneTree is the honest test.

func _init() -> void:
	var paths: PackedStringArray = [
		"res://source/common/gameplay/items/ammo_item.gd",
		"res://source/common/gameplay/items/gear_item.gd",
		"res://source/common/gameplay/jobs/job_perks.gd",
		"res://source/common/gameplay/jobs/job_registry.gd",
		"res://source/common/gameplay/maps/components/mineable_node.gd",
		"res://source/common/gameplay/maps/components/mineable_node_resource.gd",
		"res://source/common/gameplay/combat/ability/ability_collection/charge_shot/charge_ability.gd",
		"res://source/server/world/components/data_request_handlers/item.equip.gd",
		"res://source/server/world/components/data_request_handlers/craft.item.gd",
		"res://source/client/ui/menus/character/equipment_panel.gd",
		"res://source/client/ui/compact_menus/compact_equipment_host.gd",
	]
	var bad: int = 0
	for p: String in paths:
		var s: GDScript = load(p) as GDScript
		if s == null:
			print("VERIFY_FAIL load ", p)
			bad += 1
			continue
		var err: int = s.reload()
		if err != OK:
			print("VERIFY_FAIL compile(", err, ") ", p)
			bad += 1
		else:
			print("ok ", p)
	var slot: ItemSlot = load("res://source/common/gameplay/items/item_slot/slots/ammo.tres")
	if slot == null or slot.key != &"ammo":
		print("VERIFY_FAIL ammo slot")
		bad += 1
	else:
		print("ok ammo slot display=", slot.display_name)
	var smith: PackedScene = load("res://source/common/gameplay/maps/maps/smith_house/inside_map.tscn")
	if smith == null:
		print("VERIFY_FAIL smith_house scene")
		bad += 1
	else:
		print("ok smith_house scene")
	print("VERIFY_PASS scripts" if bad == 0 else "VERIFY_FAIL %d" % bad)
	quit(0 if bad == 0 else 1)
