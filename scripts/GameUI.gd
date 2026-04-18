extends CanvasLayer
class_name GameUI

signal biome_selected(idx: int)
signal species_selected(idx: int)
signal time_speed_changed(idx: int)
signal map_type_changed(idx: int)
signal regenerate_requested()
signal power_selected(idx: int)
signal chronicle_reply_submitted(text: String)

const BAR_H := 52
const PANEL_H := 68
const BTN := 46
const GAP := 4
const PAD := 10

const BIOMES: Array[String] = ["water", "sand", "grass", "forest", "mountain"]
const BIOME_ICONS: Array[String] = ["~", ":", "#", "Y", "^"]
const BIOME_COLORS: Array[Color] = [
	Color(0.20, 0.45, 0.85),
	Color(0.85, 0.80, 0.50),
	Color(0.30, 0.70, 0.30),
	Color(0.10, 0.45, 0.15),
	Color(0.45, 0.45, 0.45),
]

var selected_biome := 2
var selected_species := 0
var selected_power := 0
var current_speed_idx := 1
var current_map_idx := 0
var active_tab := "terrain"

const POWERS: Array[String]       = ["meteor",  "lightning", "fire",   "plague", "rain",   "blessing"]
const POWER_LABELS: Array[String] = ["Meteoro", "Rayo",      "Fuego",  "Plaga",  "Lluvia", "Bendicion"]
const POWER_COLORS: Array[Color]  = [
	Color(1.0, 0.35, 0.10),
	Color(1.0, 0.95, 0.20),
	Color(1.0, 0.50, 0.05),
	Color(0.55, 0.90, 0.25),
	Color(0.30, 0.65, 1.00),
	Color(1.00, 0.88, 0.20),
]

var _tab_btns: Dictionary = {}
var _biome_btns: Array[Button] = []
var _species_btns: Array[Button] = []
var _power_btns: Array[Button] = []
var _speed_btns: Dictionary = {}
var _map_btns: Dictionary = {}
var _tool_panel: Panel
var _terrain_content: Control
var _entity_content: Control
var _world_content: Control
var _power_content: Control
var _species_data: Array[Dictionary] = []
var _chronicle_prompt_label: Label
var _chronicle_reply_buttons: Array[Button] = []

func _ready() -> void:
	layer = 10

func setup_species(species: Array[Dictionary]) -> void:
	_species_data = species
	_build()

func _build() -> void:
	var bar := Panel.new()
	bar.anchor_left = 0.0; bar.anchor_top = 1.0
	bar.anchor_right = 1.0; bar.anchor_bottom = 1.0
	bar.offset_top = -BAR_H; bar.offset_bottom = 0.0
	bar.offset_left = 0.0; bar.offset_right = 0.0
	_style_panel(bar, Color(0.07, 0.07, 0.07, 0.96))
	add_child(bar)

	_tool_panel = Panel.new()
	_tool_panel.anchor_left = 0.0; _tool_panel.anchor_top = 1.0
	_tool_panel.anchor_right = 1.0; _tool_panel.anchor_bottom = 1.0
	_tool_panel.offset_top = -(BAR_H + PANEL_H); _tool_panel.offset_bottom = -BAR_H
	_tool_panel.offset_left = 0.0; _tool_panel.offset_right = 0.0
	_style_panel(_tool_panel, Color(0.10, 0.10, 0.10, 0.96))
	add_child(_tool_panel)

	_build_bar(bar)
	_build_terrain_content()
	_build_entity_content()
	_build_world_content()
	_build_power_content()
	_show_tab(active_tab)

func _build_bar(bar: Panel) -> void:
	var x := float(PAD)
	var yc := (BAR_H - BTN) / 2.0

	var tabs: Array[Array] = [
		["terrain",  "Terreno",   Color(0.55, 0.85, 0.45)],
		["entities", "Entidades", Color(0.95, 0.70, 0.40)],
		["world",    "Mundo",     Color(0.45, 0.70, 0.95)],
		["powers",   "Poderes",   Color(1.00, 0.50, 0.20)],
	]
	for td in tabs:
		var btn := _make_tab_btn(td[1] as String, td[2] as Color)
		btn.position = Vector2(x, yc)
		btn.size.x = 88.0
		bar.add_child(btn)
		var tk: String = td[0]
		_tab_btns[tk] = btn
		btn.pressed.connect(func(): _on_tab(tk))
		x += 88.0 + GAP

	x += PAD; _divider(bar, x, yc); x += GAP + 4.0

	var speeds: Array[Array] = [
		[0, "||",  Color(0.95, 0.40, 0.40)],
		[1, "1x",  Color(0.55, 0.95, 0.55)],
		[2, "2x",  Color(0.55, 0.95, 0.55)],
		[3, "5x",  Color(0.95, 0.95, 0.40)],
		[4, "10x", Color(0.95, 0.60, 0.20)],
	]
	for sd in speeds:
		var btn := _make_icon_btn(sd[1] as String, sd[2] as Color)
		btn.position = Vector2(x, yc)
		bar.add_child(btn)
		var si: int = sd[0]
		_speed_btns[si] = btn
		btn.pressed.connect(func(): _on_speed(si))
		x += BTN + GAP

	x += PAD; _divider(bar, x, yc); x += GAP + 4.0

	var regen := _make_icon_btn("↺ GEN", Color(1.0, 0.60, 0.20))
	regen.position = Vector2(x, yc)
	regen.size.x = BTN + 20.0
	bar.add_child(regen)
	regen.pressed.connect(func(): regenerate_requested.emit())

	_chronicle_prompt_label = Label.new()
	_chronicle_prompt_label.position = Vector2(x + 92.0, yc + 2.0)
	_chronicle_prompt_label.size = Vector2(220.0, 18.0)
	_chronicle_prompt_label.text = "Consejo:"
	_chronicle_prompt_label.add_theme_font_size_override("font_size", 11)
	_chronicle_prompt_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.46))
	bar.add_child(_chronicle_prompt_label)

	for i in range(3):
		var reply_btn := _make_icon_btn("...", Color(0.82, 0.68, 0.28))
		reply_btn.position = Vector2(x + 92.0 + i * 88.0, yc + 18.0)
		reply_btn.size = Vector2(84.0, 26.0)
		reply_btn.visible = false
		var option_idx := i
		reply_btn.pressed.connect(func(): _on_chronicle_reply_pressed(option_idx))
		bar.add_child(reply_btn)
		_chronicle_reply_buttons.append(reply_btn)

	_refresh_speed_highlights()
	_refresh_tab_highlights()

func _build_terrain_content() -> void:
	_terrain_content = Control.new()
	_terrain_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_panel.add_child(_terrain_content)

	var x := float(PAD)
	var yc := (PANEL_H - BTN) / 2.0
	_content_label(_terrain_content, "PINTAR:", x, yc)
	x += 62.0

	for i in BIOMES.size():
		var btn := _make_biome_btn(i)
		btn.position = Vector2(x, yc)
		_terrain_content.add_child(btn)
		_biome_btns.append(btn)
		var ci: int = i
		btn.pressed.connect(func(): _on_biome(ci))
		x += BTN + GAP

	_refresh_biome_highlights()

func _build_entity_content() -> void:
	_entity_content = Control.new()
	_entity_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_panel.add_child(_entity_content)

	var x := float(PAD)
	var yc := (PANEL_H - BTN) / 2.0
	_content_label(_entity_content, "SPAWN:", x, yc)
	x += 62.0

	for i in _species_data.size():
		var sp: Dictionary = _species_data[i]
		var btn := _make_species_btn(sp["name"] as String, sp["color"] as Color)
		btn.position = Vector2(x, yc)
		_entity_content.add_child(btn)
		_species_btns.append(btn)
		var si: int = i
		btn.pressed.connect(func(): _on_species(si))
		x += 86.0 + GAP

	_refresh_species_highlights()

func _build_world_content() -> void:
	_world_content = Control.new()
	_world_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_panel.add_child(_world_content)

	var x := float(PAD)
	var yc := (PANEL_H - BTN) / 2.0
	_content_label(_world_content, "MAPA:", x, yc)
	x += 62.0

	var maps: Array[Array] = [
		[0, "Aleatorio",   Color(0.70, 0.70, 0.95)],
		[1, "Tipo Tierra", Color(0.45, 0.85, 0.55)],
		[2, "Continente",  Color(0.40, 0.75, 0.95)],
	]
	for md in maps:
		var btn := _make_icon_btn(md[1] as String, md[2] as Color)
		btn.position = Vector2(x, yc)
		btn.size.x = 96.0
		_world_content.add_child(btn)
		var mi: int = md[0]
		_map_btns[mi] = btn
		btn.pressed.connect(func(): _on_map(mi))
		x += 96.0 + GAP

	_refresh_map_highlights()

func _build_power_content() -> void:
	_power_content = Control.new()
	_power_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_panel.add_child(_power_content)

	var x := float(PAD)
	var yc := (PANEL_H - BTN) / 2.0
	_content_label(_power_content, "PODER:", x, yc)
	x += 62.0

	for i in POWERS.size():
		var btn := _make_power_btn(i)
		btn.position = Vector2(x, yc)
		_power_content.add_child(btn)
		_power_btns.append(btn)
		var pi: int = i
		btn.pressed.connect(func(): _on_power(pi))
		x += 76.0 + GAP

	_refresh_power_highlights()

func _show_tab(tab: String) -> void:
	_terrain_content.visible = tab == "terrain"
	_entity_content.visible = tab == "entities"
	_world_content.visible = tab == "world"
	_power_content.visible = tab == "powers"
	_tool_panel.visible = true

func _on_tab(tab: String) -> void:
	if active_tab == tab:
		_tool_panel.visible = not _tool_panel.visible
		return
	active_tab = tab
	_show_tab(tab)
	_refresh_tab_highlights()

func _on_biome(idx: int) -> void:
	selected_biome = idx
	_refresh_biome_highlights()
	biome_selected.emit(idx)

func _on_species(idx: int) -> void:
	selected_species = idx
	_refresh_species_highlights()
	species_selected.emit(idx)

func _on_speed(idx: int) -> void:
	current_speed_idx = idx
	_refresh_speed_highlights()
	time_speed_changed.emit(idx)

func _on_map(idx: int) -> void:
	current_map_idx = idx
	_refresh_map_highlights()
	map_type_changed.emit(idx)

func _on_power(idx: int) -> void:
	selected_power = idx
	_refresh_power_highlights()
	power_selected.emit(idx)

func _on_chronicle_reply_pressed(idx: int) -> void:
	if idx < 0 or idx >= _chronicle_reply_buttons.size():
		return
	var label := _chronicle_reply_buttons[idx].text.strip_edges()
	if label == "":
		return
	chronicle_reply_submitted.emit(label)

func set_chronicle_prompt(text: String, waiting: bool, options: Array[String] = []) -> void:
	if _chronicle_prompt_label == null:
		return
	_chronicle_prompt_label.text = text if waiting else "Consejo:"
	for i in _chronicle_reply_buttons.size():
		var btn := _chronicle_reply_buttons[i]
		if waiting and i < options.size():
			btn.text = options[i]
			btn.visible = true
			btn.disabled = false
		else:
			btn.text = ""
			btn.visible = false
			btn.disabled = true

func is_reply_input_focused() -> bool:
	return false

func _refresh_tab_highlights() -> void:
	for key in _tab_btns:
		if key == active_tab:
			_tab_btns[key].add_theme_stylebox_override("normal", _style(Color(0.20, 0.20, 0.10), Color.YELLOW, 2))
		else:
			_tab_btns[key].add_theme_stylebox_override("normal", _style(Color(0.12, 0.12, 0.12), Color(0.28, 0.28, 0.28), 2))

func _refresh_biome_highlights() -> void:
	for i in _biome_btns.size():
		var c := BIOME_COLORS[i]
		if i == selected_biome:
			_biome_btns[i].add_theme_stylebox_override("normal", _style(c, Color.YELLOW, 3))
		else:
			_biome_btns[i].add_theme_stylebox_override("normal", _style(c.darkened(0.4), c, 2))

func _refresh_species_highlights() -> void:
	for i in _species_btns.size():
		if i == selected_species:
			_species_btns[i].add_theme_stylebox_override("normal", _style(Color(0.22, 0.22, 0.10), Color.YELLOW, 3))
		else:
			_species_btns[i].add_theme_stylebox_override("normal", _style(Color(0.12, 0.12, 0.12), Color(0.28, 0.28, 0.28), 2))

func _refresh_speed_highlights() -> void:
	for key in _speed_btns:
		if key == current_speed_idx:
			_speed_btns[key].add_theme_stylebox_override("normal", _style(Color(0.20, 0.20, 0.10), Color.YELLOW, 3))
		else:
			_speed_btns[key].add_theme_stylebox_override("normal", _style(Color(0.12, 0.12, 0.12), Color(0.28, 0.28, 0.28), 2))

func _refresh_map_highlights() -> void:
	for key in _map_btns:
		if key == current_map_idx:
			_map_btns[key].add_theme_stylebox_override("normal", _style(Color(0.20, 0.20, 0.10), Color.YELLOW, 3))
		else:
			_map_btns[key].add_theme_stylebox_override("normal", _style(Color(0.12, 0.12, 0.12), Color(0.28, 0.28, 0.28), 2))

func _refresh_power_highlights() -> void:
	for i in _power_btns.size():
		var c := POWER_COLORS[i]
		if i == selected_power:
			_power_btns[i].add_theme_stylebox_override("normal", _style(c.darkened(0.2), Color.YELLOW, 3))
		else:
			_power_btns[i].add_theme_stylebox_override("normal", _style(c.darkened(0.55), c, 2))

func _make_power_btn(idx: int) -> Button:
	var color := POWER_COLORS[idx]
	var btn := Button.new()
	btn.size = Vector2(76.0, BTN)
	btn.text = POWER_LABELS[idx]
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", color.lightened(0.4))
	btn.add_theme_color_override("font_color_hover", Color.WHITE)
	btn.add_theme_stylebox_override("normal", _style(color.darkened(0.55), color, 2))
	btn.add_theme_stylebox_override("hover", _style(color.darkened(0.3), Color.WHITE, 3))
	btn.add_theme_stylebox_override("focus", _style(color.darkened(0.55), color, 2))
	return btn

func _make_biome_btn(idx: int) -> Button:
	var color := BIOME_COLORS[idx]
	var btn := Button.new()
	btn.size = Vector2(BTN, BTN)
	btn.tooltip_text = BIOMES[idx].capitalize()
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = BIOME_ICONS[idx]
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", color.lightened(0.5))
	btn.add_theme_color_override("font_color_hover", Color.WHITE)
	btn.add_theme_stylebox_override("normal", _style(color.darkened(0.4), color, 2))
	btn.add_theme_stylebox_override("hover", _style(color.darkened(0.2), Color.WHITE, 3))
	btn.add_theme_stylebox_override("focus", _style(color.darkened(0.4), color, 2))
	return btn

func _make_species_btn(sp_name: String, color: Color) -> Button:
	var btn := Button.new()
	btn.size = Vector2(86.0, BTN)
	btn.text = sp_name
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", color.lightened(0.3))
	btn.add_theme_color_override("font_color_hover", Color.WHITE)
	btn.add_theme_stylebox_override("normal", _style(color.darkened(0.5), color, 2))
	btn.add_theme_stylebox_override("hover", _style(color.darkened(0.3), Color.WHITE, 3))
	btn.add_theme_stylebox_override("focus", _style(color.darkened(0.5), color, 2))
	return btn

func _make_tab_btn(label: String, color: Color) -> Button:
	var btn := Button.new()
	btn.size = Vector2(88.0, BTN)
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_color_hover", Color.WHITE)
	btn.add_theme_stylebox_override("normal", _style(Color(0.12, 0.12, 0.12), Color(0.28, 0.28, 0.28), 2))
	btn.add_theme_stylebox_override("hover", _style(Color(0.18, 0.18, 0.18), color, 2))
	btn.add_theme_stylebox_override("focus", _style(Color(0.12, 0.12, 0.12), Color(0.28, 0.28, 0.28), 2))
	return btn

func _make_icon_btn(icon: String, color: Color) -> Button:
	var btn := Button.new()
	btn.size = Vector2(BTN, BTN)
	btn.text = icon
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_color_hover", Color.WHITE)
	btn.add_theme_stylebox_override("normal", _style(Color(0.12, 0.12, 0.12), Color(0.28, 0.28, 0.28), 2))
	btn.add_theme_stylebox_override("hover", _style(Color(0.18, 0.18, 0.18), color, 2))
	btn.add_theme_stylebox_override("focus", _style(Color(0.12, 0.12, 0.12), Color(0.28, 0.28, 0.28), 2))
	return btn

func _content_label(parent: Control, text: String, x: float, yc: float) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, yc + (BTN - 16.0) / 2.0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50))
	parent.add_child(lbl)

func _style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = bw; s.border_width_right = bw
	s.border_width_top = bw; s.border_width_bottom = bw
	s.border_color = border
	s.corner_radius_top_left = 3; s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3; s.corner_radius_bottom_right = 3
	return s

func _style_panel(p: Panel, color: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_width_top = 2
	s.border_color = Color(0.22, 0.22, 0.22)
	p.add_theme_stylebox_override("panel", s)

func _divider(parent: Control, x: float, y: float) -> void:
	var d := ColorRect.new()
	d.position = Vector2(x, y)
	d.size = Vector2(2.0, float(BTN))
	d.color = Color(0.22, 0.22, 0.22)
	parent.add_child(d)
