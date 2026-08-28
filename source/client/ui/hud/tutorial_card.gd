extends Control
## One onboarding lesson: dim backdrop, centered card, a title, a body and a
## single dismiss button. Same shape and z as WelcomeScreen, but reusable and
## step-aware because the Charter Intake tour shows several of these in a row.
##
## Deliberately NO class_name: the coach preloads it by path, so a fresh clone
## can run the tour before the editor has re-registered global classes.

signal dismissed

const CARD_WIDTH: float = 460.0

var title_text: String = ""
## BBCode is enabled — bullets are written as plain "· " lines on purpose so the
## text reads the same in any theme.
var body_text: String = ""
## Optional "Step 2 of 4" line under the title. Empty = no step line.
var step_text: String = ""
var button_text: String = "Got it"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A lesson owns the screen while it is up, exactly like the first-run welcome.
	z_index = 4096

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.08, 0.6)
	add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	center.add_child(panel)

	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(pad)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 12)
	pad.add_child(vbox)

	var title: Label = Label.new()
	title.text = title_text
	title.add_theme_font_size_override(&"font_size", 20)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	vbox.add_child(title)

	if not step_text.is_empty():
		var step: Label = Label.new()
		step.text = step_text
		step.add_theme_font_size_override(&"font_size", 11)
		step.add_theme_color_override(&"font_color", Color(0.72, 0.76, 0.85))
		vbox.add_child(step)

	var body: RichTextLabel = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(CARD_WIDTH - 44.0, 0)
	body.add_theme_constant_override(&"line_separation", 5)
	body.add_theme_font_size_override(&"normal_font_size", 13)
	# The theme's bold face renders a size up; pin it or every [b] shoves the line.
	body.add_theme_font_size_override(&"bold_font_size", 13)
	body.add_theme_font_size_override(&"italics_font_size", 13)
	body.text = body_text
	vbox.add_child(body)

	var dismiss: Button = Button.new()
	dismiss.text = button_text
	dismiss.custom_minimum_size = Vector2(0, 38)
	dismiss.pressed.connect(_on_dismissed)
	vbox.add_child(dismiss)


func _on_dismissed() -> void:
	dismissed.emit()
	queue_free()
