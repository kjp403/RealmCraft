extends Label
## Over-head name. For Players with a staff_role, a small rank badge sits to the
## left of the name (Admin crown / Moderator mask).


const RANK_ICON_ADMIN := preload("res://assets/sprites/ui/ranks/admin.png")
const RANK_ICON_MODERATOR := preload("res://assets/sprites/ui/ranks/moderator.png")
const BADGE_PX := 14.0
## Gap between badge right edge and the first letter of the name (label space).
const BADGE_GAP := 3.0
## Optical lift so the 14px icon sits on the glyph mid-line (font_size 32).
const BADGE_Y_NUDGE := -2.0


var _badge: TextureRect
var _title_label: Label


func _ready() -> void:
	if multiplayer.is_server():
		return
	# Shrink-wrap to glyphs — the scene placeholder rect is wide and center-
	# aligned, which parked the badge far left of the actual letters.
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var parent_node: Node = get_parent()
	if parent_node.has_signal(&"display_name_changed"):
		parent_node.display_name_changed.connect(_on_display_name_changed)
	if parent_node is Player:
		var player: Player = parent_node as Player
		player.staff_role_changed.connect(_on_staff_role_changed)
		player.display_title_changed.connect(_on_display_title_changed)
		_apply_badge(player.staff_role)
		_apply_title(player.display_title)
	# Seed text if the sync already landed before this label was ready.
	if parent_node.get("display_name") != null:
		text = str(parent_node.get("display_name"))
	_recenter()


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


func _on_display_title_changed(title: String) -> void:
	_apply_title(title)
	_recenter()


func _apply_title(title: String) -> void:
	var shown: String = title.strip_edges()
	if shown.is_empty():
		if _title_label != null:
			TitleVfx.apply_to_label(_title_label, "")
			_title_label.visible = false
		return
	if _title_label == null:
		_title_label = Label.new()
		_title_label.name = "TitleVfxLabel"
		_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_title_label.add_theme_font_size_override(&"font_size", 28)
		_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_label.scale = scale
		# Nameplate depth. The title hangs off the Character, which draws at world
		# z, so at the default 0 it ties with the body sprite and loses to
		# anything drawn later - the player's own sprite, foliage, a prop. The
		# mastery titles made that visible because their particle layer sits above
		# the glyphs and was getting clipped by the head it was floating over.
		# z_as_relative off so the depth is absolute and does not drift with
		# whatever the character is parented under.
		_title_label.z_as_relative = false
		_title_label.z_index = TitleParticles.NAMEPLATE_Z
		var host: Node = get_parent()
		if host != null:
			host.add_child(_title_label)
	_title_label.text = "« %s »" % shown
	_title_label.visible = true
	TitleVfx.apply_to_label(_title_label, shown)


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
	# Label is scaled 0.2 on the Character scene. Shrink-wrap to the glyphs,
	# park the badge snug left of the first letter, then center the whole
	# [badge|name] group under the character.
	reset_size()
	var left_extent: float = 0.0
	if _badge != null and is_instance_valid(_badge):
		left_extent = BADGE_PX + BADGE_GAP
		_badge.position = Vector2(
			-(BADGE_PX + BADGE_GAP),
			(size.y - BADGE_PX) * 0.5 + BADGE_Y_NUDGE
		)
	# group_left = position.x - left_extent * scale.x
	# group_right = position.x + size.x * scale.x
	# center at 0 → position.x = -(size.x - left_extent) * scale.x / 2
	position.x = -(size.x - left_extent) * scale.x * 0.5
	if _title_label != null and _title_label.visible:
		_title_label.reset_size()
		_title_label.scale = scale
		_title_label.position = Vector2(
			-_title_label.size.x * scale.x * 0.5,
			position.y - _title_label.size.y * scale.y - 1.0
		)
