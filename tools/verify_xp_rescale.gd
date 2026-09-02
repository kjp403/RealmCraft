extends SceneTree

## Loads the rescaled crafting stations / salvage table and prints recipe counts
## plus the XP span of each, so a text-level edit to the .tres files is proven to
## still parse and bind rather than merely looking right as text.
##
## Run under `-s`, where autoloads are absent and a few unrelated client scripts
## fail to compile; recipes whose output_item comes back null are counted and
## reported rather than treated as failures, because that is an artefact of the
## tool environment, not of the resource. Compare a run against a clean tree
## before reading any non-zero `null_out` as a regression.

const PATHS: Array[String] = [
	"res://source/common/gameplay/crafting/resources/anvil.tres",
	"res://source/common/gameplay/crafting/resources/furnace.tres",
	"res://source/common/gameplay/crafting/resources/alchemy_station.tres",
	"res://source/common/gameplay/crafting/resources/salvage_table.tres",
]


func _init() -> void:
	var failed: int = 0
	for path: String in PATHS:
		var res: Resource = load(path)
		if res == null:
			print("FAIL  could not load ", path)
			failed += 1
			continue

		# Both station types expose `recipes`, but they are unrelated classes —
		# the salvage table is a SalvageTable, not a CraftingStationResource.
		var recipes: Array = []
		var station: CraftingStationResource = res as CraftingStationResource
		var salvage: SalvageTable = res as SalvageTable
		if station != null:
			recipes.assign(station.recipes)
		elif salvage != null:
			recipes.assign(salvage.recipes)
		else:
			print("FAIL  unrecognised resource type: ", path)
			failed += 1
			continue

		var lo: int = 1 << 30
		var hi: int = 0
		var null_out: int = 0
		for recipe: Resource in recipes:
			if recipe == null:
				print("FAIL  null recipe entry in ", path.get_file())
				failed += 1
				continue
			lo = mini(lo, int(recipe.get(&"xp_reward")))
			hi = maxi(hi, int(recipe.get(&"xp_reward")))
			if recipe.get(&"output_item") == null:
				null_out += 1
		if lo > hi:
			lo = 0
		print("OK    %-24s recipes=%3d  xp=%d..%d  null_out=%d" % [
			path.get_file(), recipes.size(), lo, hi, null_out
		])
	print("")
	print("FAILURES: ", failed)
	quit(1 if failed > 0 else 0)
