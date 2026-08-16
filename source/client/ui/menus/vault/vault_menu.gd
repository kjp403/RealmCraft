extends MenuShell
## Staff VFX Vault — Titles, Skins, and Cosmetics each get a tab. Opened from
## the Curator. Individual Curator buttons jump to the matching tab via open(arg).


const TITLES_SCENE: PackedScene = preload("res://source/client/ui/menus/titles/titles_menu.tscn")
const SKINS_SCENE: PackedScene = preload("res://source/client/ui/menus/skins/skins_menu.tscn")
const COSMETICS_SCENE: PackedScene = preload("res://source/client/ui/menus/cosmetics/cosmetics_menu.tscn")

const TAB_TITLES := &"titles"
const TAB_SKINS := &"skins"
const TAB_COSMETICS := &"cosmetics"

var _tab: StringName = TAB_TITLES
var _tab_buttons: Dictionary = {}
var _panels: Dictionary = {}


func _ready() -> void:
	build_shell("The Vault", null, true)
	_build_layout()
	_select_tab(TAB_TITLES)


func open(arg: Variant = null) -> void:
	var key: String = str(arg).strip_edges().to_lower()
	match key:
		"skins":
			_select_tab(TAB_SKINS)
		"cosmetics":
			_select_tab(TAB_COSMETICS)
		_:
			_select_tab(TAB_TITLES)


func _build_layout() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)
	content.add_child(col)

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override(&"separation", 6)
	col.add_child(tabs)
	_add_tab_button(tabs, TAB_TITLES, "Titles")
	_add_tab_button(tabs, TAB_SKINS, "Skins")
	_add_tab_button(tabs, TAB_COSMETICS, "Cosmetics")

	var body: Control = Control.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	_embed(body, TAB_TITLES, TITLES_SCENE)
	_embed(body, TAB_SKINS, SKINS_SCENE)
	_embed(body, TAB_COSMETICS, COSMETICS_SCENE)


func _add_tab_button(row: HBoxContainer, id: StringName, label: String) -> void:
	var b: Button = Button.new()
	b.text = label
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 36)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override(&"font_size", 16)
	b.pressed.connect(_select_tab.bind(id))
	row.add_child(b)
	_tab_buttons[id] = b


func _embed(body: Control, id: StringName, scene: PackedScene) -> void:
	var panel: Control = scene.instantiate()
	panel.set_meta(&"embedded", true)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	_panels[id] = panel


func _select_tab(id: StringName) -> void:
	_tab = id
	for key: StringName in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = (key == id)
	for key: StringName in _panels:
		var panel: Control = _panels[key]
		panel.visible = (key == id)
