extends SceneTree
func _initialize() -> void:
	var slugs := [
		&"trpg_archer", &"trpg_slime", &"trpg_werewolf", &"trpg_blood_monster_a", &"trpg_demon_a", &"trpg_bat",
		&"trpg_acid_ooze", &"trpg_fog_giant", &"trpg_werewolf_stalker", &"trpg_zombie_giant",
	]
	for slug: StringName in slugs:
		var skin: SpriteFrames = ContentRegistryHub.load_by_slug(&"sprites", slug) as SpriteFrames
		var etype: EnemyTypeResource = ContentRegistryHub.load_by_slug(&"enemy_types", slug) as EnemyTypeResource
		assert(skin != null, "missing skin %s" % slug)
		assert(etype != null, "missing type %s" % slug)
		assert(skin.has_animation(&"idle"))
		assert(skin.has_animation(&"run"))
		assert(skin.has_animation(&"death"))
		assert(etype.skin != null)
		print("OK ", slug, " anims=", skin.get_animation_names())
	print("TRPG_VERIFY_PASS")
	quit(0)
