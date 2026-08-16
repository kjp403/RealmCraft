extends Map
## Overworld Fungus Cave. Bound Lira and Wren used to stand on the Heart pack
## (detection 200 / slam 125), so opening quest UI rooted the player in the
## middle of a fight. Snap them to the Cave Master bar on load so a stale
## transform cannot put them back in the pit.

const LIRA_BAR_POS: Vector2 = Vector2(792, 82)
const WREN_BAR_POS: Vector2 = Vector2(889, 163)


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_place_quest_npcs_in_bar()


func _place_quest_npcs_in_bar() -> void:
	var lira: Node2D = get_node_or_null(^"LiraVoss") as Node2D
	if lira != null:
		lira.position = LIRA_BAR_POS
	var wren: Node2D = get_node_or_null(^"CaveScribeWren") as Node2D
	if wren != null:
		wren.position = WREN_BAR_POS
