class_name LiveTooltipButton
extends Button
## Button whose hover tooltip can change while the mouse stays on it.
## Godot snapshots [member Control.tooltip_text] when the popup opens; this
## returns a label that keeps reading the live string.

class _LiveLabel extends Label:
	var source: Control

	func _process(_delta: float) -> void:
		if source == null or not is_instance_valid(source):
			return
		var next: String = source.tooltip_text
		if text == next:
			return
		text = next
		_fit_popup()

	func _fit_popup() -> void:
		custom_minimum_size = Vector2.ZERO
		reset_size()
		custom_minimum_size = get_combined_minimum_size()
		var node: Node = get_parent()
		while node != null:
			if node is Window:
				(node as Window).reset_size()
				break
			if node is Control:
				(node as Control).reset_size()
			node = node.get_parent()


func _make_custom_tooltip(for_text: String) -> Object:
	var label := _LiveLabel.new()
	label.text = for_text
	label.source = self
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = &"TooltipLabel"
	return label
