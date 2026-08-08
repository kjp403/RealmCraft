extends Label
## Over-head name. For Players with a staff_role, a small rank badge sits to the
## left of the name (Admin crown / Moderator mask).


const RANK_ICON_ADMIN := preload("res://assets/sprites/ui/ranks/admin.png")
const RANK_ICON_MODERATOR := preload("res://assets/sprites/ui/ranks/moderator.png")
const BADGE_PX := 14.0

var _badge: TextureRect


func _ready() -> void:
	if multiplayer.is_server():
		return
	var parent_node: Node = get_parent()
	if parent_node.has_signal(&"display_name_changed"):
		parent_node.display_name_changed.connect(_on_display_name_changed)
	if parent_node is Player:
		var player: Player = parent_node as Player
		player.staff_role_changed.connect(_on_staff_role_changed)
		_apply_badge(player.staff_role)
	# Seed text if the sync already landed before this label was ready.
	if parent_node.get("display_name") != null:
		text = str(parent_node.get("display_name"))


func _notification(what: int) -> void:
	# Long text grows the rect rightward from the fixed left edge, and the 0.2
	# scale pivots at the top-left corner — recenter on the parent every resize.
	if what == NOTIFICATION_RESIZED:
		_recenter()


func _on_display_name_changed(new_name: String) -> void:
	text = new_name
	_recenter()


func _on_staff_role_changed(role: String) -> void:
	_apply_badge(role)
	_recenter()


func _apply_badge(role: String) -> void:
	var tex: Texture2D = null
	match role:
		"admin":
			tex = RANK_ICON_ADMIN
		"moderator":
			tex = RANK_ICON_MODERATOR
	if tex == null:
		if _badge != null:
			_badge.queue_free()
			_badge = null
		return
	if _badge == null:
		_badge = TextureRect.new()
		_badge.name = "RankBadge"
		_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_badge)
	_badge.texture = tex
	_badge.custom_minimum_size = Vector2(BADGE_PX, BADGE_PX)
	_badge.size = Vector2(BADGE_PX, BADGE_PX)


func _recenter() -> void:
	# Label is scaled 0.2 on the Character scene — keep the name centred, and
	# park the badge just left of the text in label-local space.
	var scaled_w: float = size.x * scale.x
	position.x = -scaled_w / 2.0
	if _badge != null and is_instance_valid(_badge):
		_badge.position = Vector2(-BADGE_PX - 4.0, (size.y - BADGE_PX) * 0.5)
