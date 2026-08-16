extends SceneTree
## Verify the cosmetics vertical slice loads end to end.
##   godot --headless --path . -s tools/verify_cosmetics.gd
##
## Checks the registry, every SpriteFrames, the Cosmetics facade, the admin-only
## instance + its map scene, the Curator NPC, and that the gate constants line up.

const VAULT_RES := "res://source/common/gameplay/maps/instance/instance_collection/vfx_vault.tres"
const VAULT_MAP := "res://source/common/gameplay/maps/maps/vfx_vault/vfx_vault.tscn"
const CURATOR := "res://source/common/gameplay/characters/npc/npcs/vfx_curator.tres"
const MENU := "res://source/client/ui/menus/cosmetics/cosmetics_menu.tscn"

var _fail: int = 0


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), label)
	if not ok:
		_fail += 1


func _initialize() -> void:
	print("-- registry --")
	var ids: Array[int] = Cosmetics.ids()
	_check(ids.size() == 22, "22 cosmetics registered (got %d)" % ids.size())

	var slots: Dictionary = {}
	var bad_frames: PackedStringArray = []
	for id: int in ids:
		var slot: StringName = Cosmetics.slot_of(id)
		slots[slot] = int(slots.get(slot, 0)) + 1
		var frames: SpriteFrames = Cosmetics.frames(id)
		if frames == null or not frames.has_animation(&"loop") \
				or frames.get_frame_count(&"loop") <= 0:
			bad_frames.append(String(Cosmetics.slug(id)))
	_check(bad_frames.is_empty(), "every cosmetic has a non-empty 'loop' anim %s" % str(bad_frames))
	print("        slots: ", slots)
	_check(
		Cosmetics.SLOTS.all(func(s: StringName) -> bool: return slots.has(s)),
		"every declared slot has content"
	)
	_check(Cosmetics.is_valid(0), "id 0 (unequipped) is valid")
	_check(not Cosmetics.is_valid(99999), "unknown id rejected")
	_check(Cosmetics.is_looping(Cosmetics.ids_in_slot(&"aura")[0]), "auras loop")
	_check(not Cosmetics.is_looping(Cosmetics.ids_in_slot(&"departure")[0]), "departures do not loop")

	print("-- ascended weapon vfx --")
	# One purchasable cosmetic in the weapon slot; the per-weapon effects are a
	# lookup keyed by art slug, NOT registry entries.
	var weapon_ids: Array[int] = Cosmetics.ids_in_slot(&"weapon")
	_check(weapon_ids.size() == 1, "exactly one weapon-slot cosmetic (got %d)" % weapon_ids.size())
	if not weapon_ids.is_empty():
		_check(Cosmetics.is_weapon_slot(weapon_ids[0]), "it reports the weapon slot")
	var asc_dir: String = "res://assets/sprites/items/weapons/ascension/"
	var missing: PackedStringArray = []
	var covered: int = 0
	for f: String in ResourceLoader.list_directory(asc_dir):
		if not f.ends_with(".png"):
			continue
		var icon: Texture2D = ResourceLoader.load(asc_dir + f) as Texture2D
		if icon == null:
			continue
		if Cosmetics.weapon_fx_for(icon) == null:
			missing.append(f)
		else:
			covered += 1
	_check(missing.is_empty(), "every Ascended weapon resolves an effect %s" % str(missing))
	_check(covered == 34, "34 Ascended weapons covered (got %d)" % covered)
	# A non-Ascended weapon must NOT light up — that is what keeps this tier-exclusive.
	var plain: Item = ContentRegistryHub.load_by_id(&"items",
		ContentRegistryHub.id_from_slug(&"items", &"sword_bronze")) as Item
	if plain != null:
		_check(Cosmetics.weapon_fx_for(plain.item_icon) == null,
			"a non-Ascended weapon resolves no effect")

	print("-- vault --")
	var vault: Resource = ResourceLoader.load(VAULT_RES)
	_check(vault != null and vault is AdminOnlyInstanceResource, "vault instance is AdminOnly")
	if vault is InstanceResource:
		var vr: InstanceResource = vault
		_check(vr.instance_name == &"vfx_vault", "instance_name is vfx_vault")
		_check(not vr.load_at_startup, "vault is NOT load_at_startup")
		_check(ResourceLoader.exists(vr.map_path), "map_path resolves: %s" % vr.map_path)
		# The gate must refuse a null/absent player rather than defaulting open.
		_check(not vr.can_join_instance(null), "can_join_instance(null) refuses")

	var map_scene: PackedScene = ResourceLoader.load(VAULT_MAP) as PackedScene
	_check(map_scene != null, "vault map scene loads")
	if map_scene != null:
		var inst: Node = map_scene.instantiate()
		_check(inst is Map, "vault root is a Map")
		var names: PackedStringArray = []
		for child: Node in inst.get_children():
			names.append(child.name)
		print("        nodes: ", names)
		_check(inst.has_node(^"Curator"), "Curator placed")
		_check(inst.has_node(^"Ground") and inst.has_node(^"Walls"), "tile layers present")
		# Arrival must exist with warper_id 0 and NO target, or get_spawn_position(0)
		# falls through to the Exit door (and warns on every entry).
		var arrival: Node = inst.get_node_or_null(^"Arrival")
		_check(arrival != null, "Arrival spawn marker present")
		if arrival != null:
			_check(int(arrival.get("warper_id")) == 0, "Arrival is warper_id 0")
			_check(arrival.get("target_instance") == null, "Arrival has no target (inert)")
			# Room floor spans world x -336..336, y 80..432 at 16 px tiles.
			var pos: Vector2 = arrival.position
			_check(
				pos.x > -336.0 and pos.x < 336.0 and pos.y > 80.0 and pos.y < 432.0,
				"Arrival is inside the room floor (%s)" % str(pos)
			)
		var exit_node: Node = inst.get_node_or_null(^"Exit")
		_check(exit_node != null and exit_node.get("target_instance") != null, "Exit leads somewhere")
		inst.free()

	print("-- npc --")
	var curator: Resource = ResourceLoader.load(CURATOR)
	_check(curator != null, "curator resource loads")
	if curator != null:
		var has_cosmetics: bool = false
		var has_titles: bool = false
		var has_skins: bool = false
		for i: NPCInteraction in curator.get("interactions"):
			if i is CosmeticsInteraction:
				has_cosmetics = true
			if i is TitlesInteraction:
				has_titles = true
			if i is SkinsInteraction:
				has_skins = true
		_check(has_cosmetics, "curator carries CosmeticsInteraction")
		_check(has_titles, "curator carries TitlesInteraction")
		_check(has_skins, "curator carries SkinsInteraction")
		_check(curator.get("skin") != null, "curator has a skin")

	print("-- client menu --")
	_check(ResourceLoader.exists(MENU), "cosmetics menu scene exists at the convention path")
	_check(
		ResourceLoader.exists("res://source/client/ui/menus/titles/titles_menu.tscn"),
		"titles menu scene exists at the convention path"
	)
	_check(
		ResourceLoader.exists("res://source/client/ui/menus/skins/skins_menu.tscn"),
		"skins menu scene exists at the convention path"
	)
	_check(
		ResourceLoader.exists("res://source/client/ui/menus/vault/vault_menu.tscn"),
		"vault menu scene exists at the convention path"
	)

	print("-- titles --")
	_check(TitleCatalog.premium_slugs().size() == 13, "13 premium titles in the vault roster")
	_check(TitleCatalog.has_vfx("Sovereign"), "Sovereign has title-text VFX")
	_check(TitleCatalog.has_vfx("Sapphire Supporter"), "donator titles still resolve")
	_check(TitleCatalog.has_vfx("Sapphire VIP"), "VIP donator titles still resolve")
	_check(not TitleCatalog.has_vfx("Iron Warden"), "quest titles stay flat")
	_check(TitleCatalog.is_premium_name("Ashen Crown"), "multi-word premium names resolve")
	_check(not TitleCatalog.is_premium_name("Sapphire Supporter"), "donator titles are not the shop set")
	var vault_titles: Array = TitleCatalog.vault_roster()
	_check(vault_titles.size() >= 20, "vault roster includes donator + premium titles")
	_check(str(vault_titles[0].get("name", "")).contains("Sapphire"), "donator titles lead the vault roster")
	_check(
		ResourceLoader.exists("res://source/server/world/components/data_request_handlers/titles.state.gd"),
		"titles.state handler exists"
	)
	_check(
		ResourceLoader.exists("res://source/server/world/components/data_request_handlers/titles.equip.gd"),
		"titles.equip handler exists"
	)

	print("-- vault skins --")
	var listed_n: int = 0
	for id: int in PlayerSkins.ids():
		if PlayerSkins.is_horizon_listed(id):
			listed_n += 1
	var dye_n: int = VaultSkins.STYLE_ORDER.size()
	var roster_n: int = VaultSkins.roster().size()
	_check(listed_n > 0, "wardrobe roster is non-empty (got %d)" % listed_n)
	_check(dye_n == 16, "16 vault dyes (got %d)" % dye_n)
	_check(roster_n == listed_n * dye_n, "every wardrobe skin has every dye (got %d)" % roster_n)
	var packed_knight: int = VaultSkins.pack(PlayerSkins.starter_skin_id(), VaultSkins.STYLE_GOLD)
	_check(VaultSkins.is_valid(packed_knight), "packed Gilded Knight is valid")
	_check(
		VaultSkins.base_skin_id(packed_knight) == PlayerSkins.starter_skin_id(),
		"packed id unpacks to the Knight sprite"
	)
	_check(VaultSkins.style_of(packed_knight) == VaultSkins.STYLE_GOLD, "packed id unpacks to Gilded")
	_check(VaultSkins.is_valid(PlayerSkins.starter_skin_id()), "legacy raw Knight id still resolves")
	_check(not VaultSkins.is_valid(0), "id 0 is not a prestige skin")
	_check(not VaultSkins.is_valid(99 * VaultSkins.STRIDE + 1), "unknown dye is rejected")
	_check(
		ResourceLoader.exists("res://source/server/world/components/data_request_handlers/vault_skins.state.gd"),
		"vault_skins.state handler exists"
	)
	_check(
		ResourceLoader.exists("res://source/server/world/components/data_request_handlers/vault_skins.equip.gd"),
		"vault_skins.equip handler exists"
	)
	_check(
		ResourceLoader.exists("res://source/common/gameplay/characters/player/vault_skin.gdshader"),
		"prestige skin shader exists"
	)

	print("-- gate --")
	_check(CommandPermissions.STAFF_PROTECT_PRIORITY == 2, "staff floor is admin (2)")
	# Assert against the role DATA, not ServerInstance.global_role_definitions: this
	# tool runs with -s, where autoloads (Client / ClientState) do not exist, so
	# instance_server.gd fails to compile and its static table stays empty. That is a
	# harness artifact, not a product bug -- and it fails CLOSED (see below).
	var roles_res: Resource = ResourceLoader.load("res://source/server/world/data/server_roles.tres")
	_check(roles_res != null, "server_roles.tres loads")
	if roles_res != null:
		var roles: Dictionary = roles_res.get_roles()
		_check(
			int(roles.get("admin", {}).get("priority", 0)) >= CommandPermissions.STAFF_PROTECT_PRIORITY,
			"admin role priority >= staff floor"
		)
		_check(
			int(roles.get("default", {}).get("priority", 99)) < CommandPermissions.STAFF_PROTECT_PRIORITY,
			"default role is below the staff floor"
		)
	# Fail-closed property: with the role table unavailable, effective_priority_global
	# returns 0 for every role, so the vault DENIES rather than admits. Never invert
	# this comparison — an "unknown means allowed" gate would open the vault to all.
	print("        role table entries visible here: ",
		ServerInstance.global_role_definitions.size())
	_check(
		CommandPermissions.effective_priority_global(null) < CommandPermissions.STAFF_PROTECT_PRIORITY,
		"null player is below the staff floor"
	)
	var nobody: PlayerResource = PlayerResource.new()
	nobody.display_name = "definitely_not_staff_%d" % Time.get_ticks_msec()
	_check(
		CommandPermissions.effective_priority_global(nobody) < CommandPermissions.STAFF_PROTECT_PRIORITY,
		"a roleless player is below the staff floor"
	)
	_check(nobody.cosmetic_id == 0, "players default to no cosmetic")
	_check(nobody.weapon_cosmetic_id == 0, "players default to no weapon cosmetic")
	_check(nobody.vault_skin_id == 0, "players default to no prestige skin")

	print("COSMETICS_VERIFY_%s failures=%d" % ["FAIL" if _fail else "PASS", _fail])
	quit(1 if _fail else 0)
