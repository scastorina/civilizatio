extends RefCounted

class_name CivilizatioMenuFunctionsPatch

func build_menu_root(panel: Panel) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.0
	vb.anchor_top = 0.0
	vb.anchor_right = 1.0
	vb.anchor_bottom = 1.0
	vb.offset_left = 16
	vb.offset_top = 16
	vb.offset_right = -16
	vb.offset_bottom = -16
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	return vb

func add_centered_label(vb: VBoxContainer, text: String, font_size: int = 14) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	vb.add_child(label)
	return label

func add_left_label(vb: VBoxContainer, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb.add_child(label)
	return label

func add_selector(vb: VBoxContainer, items: Array[String], selected: int, on_selected: Callable) -> OptionButton:
	var selector := OptionButton.new()
	for idx in items.size():
		selector.add_item(items[idx], idx)
	selector.selected = clampi(selected, 0, items.size() - 1)
	selector.item_selected.connect(func(idx: int): on_selected.call(idx))
	vb.add_child(selector)
	return selector

func add_action_button(vb: VBoxContainer, text: String, on_pressed: Callable, minimum_height: int = 42) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, minimum_height)
	button.pressed.connect(func(): on_pressed.call())
	vb.add_child(button)
	return button
