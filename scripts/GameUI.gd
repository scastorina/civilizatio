extends CanvasLayer
class_name GameUI

signal biome_selected(idx: int)
signal tool_changed(tool: String)
signal time_speed_changed(speed: int)
signal map_type_changed(map: String)
signal regenerate_requested()

const TOOLBAR_H := 68
const BTN := 48
const GAP := 5
const PAD := 10

const BIOMES: Array[String] = ["water", "sand", "grass", "forest", "mountain"]
const BIOME_COLORS: Array[Color] = [
	Color(0.20, 0.45, 0.85),
	Color(0.85, 0.80, 0.50),
	Color(0.30, 0.70, 0.30),
	Color(0.10, 0.45, 0.15),
	Color(0.45, 0.45, 0.45),
]
const BIOME_ICONS: Array[String] = ["~", ":", "#", "Y", "^"]

var selected_biome := 2
var current_tool := "paint"
var current_speed := 1
var current_map := "random"

var _biome_btns: Array[Button] = []
var _tool_btns: Dictionary = {}
var _speed_btns: Dictionary = {}
var _map_btns: Dictionary = {}

func _ready() -> void:
	layer = 10
	_build()

func _build() -> void:
	var bg := Panel.new()
	bg.anchor_left = 0.0
	bg.anchor_top = 1.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_top = -TOOLBAR_H
	bg.offset_bottom = 0.0
	bg.offset_left = 0.0
	bg.offset_right = 0.0
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.07, 0.07, 0.07, 0.95)
	bg_style.border_width_top = 2
	bg_style.border_color = Color(0.30, 0.30, 0.30)
	bg.add_theme_stylebox_override("panel", bg_style)
	add_child(bg)

	var x := float(PAD)
	var yc := float((TOOLBAR_H - BTN) / 2)

	# Biomes
	_section_label(bg, "BIOMA", x, 3.0)
	for i in BIOMES.size():
		var btn := _make_biome_btn(i)
		btn.position = Vector2(x, yc)
		bg.add_child(btn)
		_biome_btns.append(btn)
		var ci: int = i
		btn.pressed.connect(func(): _on_biome(ci))
		x += BTN + GAP
	x += PAD
	_divider(bg, x, yc)
	x += GAP + 4.0

	# Tools
	_section_label(bg, "HERR.", x, 3.0)
	var tool_defs := [["paint", "P", Color(0.95, 0.95, 0.55)], ["spawn", "H", Color(0.95, 0.70, 0.50)]]
	for td: Array in tool_defs:
		var btn := _make_icon_btn(td[1] as String, td[2] as Color)
		btn.position = Vector2(x, yc)
		bg.add_child(btn)
		_tool_btns[td[0]] = btn
		var tk: String = td[0]
		btn.pressed.connect(func(): _on_tool(tk))
		x += BTN + GAP
	x += PAD
	_divider(bg, x, yc)
	x += GAP + 4.0

	# Time
	_section_label(bg, "TIEMPO", x, 3.0)
	var speed_defs := [[0, "||", Color(0.95, 0.40, 0.40)], [1, "1x", Color(0.55, 0.95, 0.55)],
		[2, "2x", Color(0.55, 0.95, 0.55)], [5, "5x", Color(0.95, 0.95, 0.40)],
		[10, "10x", Color(0.95, 0.60, 0.20)]]
	for sd: Array in speed_defs:
		var btn := _make_icon_btn(sd[1] as String, sd[2] as Color)
		btn.position = Vector2(x, yc)
		bg.add_child(btn)
		_speed_btns[sd[0]] = btn
		var sv: int = sd[0]
		btn.pressed.connect(func(): _on_speed(sv))
		x += BTN + GAP
	x += PAD
	_divider(bg, x, yc)
	x += GAP + 4.0

	# Map
	_section_label(bg, "MAPA", x, 3.0)
	var map_defs := [["random", "R", Color(0.70, 0.70, 0.95)],
		["continents", "C", Color(0.45, 0.85, 0.55)],
		["world", "W", Color(0.40, 0.75, 0.95)]]
	for md: Array in map_defs:
		var btn := _make_icon_btn(md[1] as String, md[2] as Color)
		btn.position = Vector2(x, yc)
		bg.add_child(btn)
		_map_btns[md[0]] = btn
		var mk: String = md[0]
		btn.pressed.connect(func(): _on_map(mk))
		x += BTN + GAP
	x += PAD
	_divider(bg, x, yc)
	x += GAP + 4.0

	# Regenerate
	var regen := _make_icon_btn("GEN", Color(1.0, 0.60, 0.20))
	regen.position = Vector2(x, yc)
	regen.size.x = BTN + 14.0
	bg.add_child(regen)
	regen.pressed.connect(func(): regenerate_requested.emit())

	_refresh_highlights()

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
	btn.add_theme_stylebox_override("pressed", _style(color, Color.YELLOW, 3))
	btn.add_theme_stylebox_override("focus", _style(color.darkened(0.4), color, 2))
	return btn

func _make_icon_btn(icon: String, color: Color) -> Button:
	var btn := Button.new()
	btn.size = Vector2(BTN, BTN)
	btn.text = icon
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_color_hover", Color.WHITE)
	btn.add_theme_stylebox_override("normal", _style(Color(0.12, 0.12, 0.12), Color(0.30, 0.30, 0.30), 2))
	btn.add_theme_stylebox_override("hover", _style(Color(0.20, 0.20, 0.20), color, 2))
	btn.add_theme_stylebox_override("pressed", _style(color.darkened(0.5), color, 3))
	btn.add_theme_stylebox_override("focus", _style(Color(0.12, 0.12, 0.12), Color(0.30, 0.30, 0.30), 2))
	return btn

func _style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = bw
	s.border_width_right = bw
	s.border_width_top = bw
	s.border_width_bottom = bw
	s.border_color = border
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	return s

func _section_label(parent: Control, text: String, x: float, y: float) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, y)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	parent.add_child(lbl)

func _divider(parent: Control, x: float, y: float) -> void:
	var d := ColorRect.new()
	d.position = Vector2(x, y)
	d.size = Vector2(2.0, float(BTN))
	d.color = Color(0.25, 0.25, 0.25)
	parent.add_child(d)

func _on_biome(idx: int) -> void:
	selected_biome = idx
	_refresh_highlights()
	biome_selected.emit(idx)

func _on_tool(tool: String) -> void:
	current_tool = tool
	_refresh_highlights()
	tool_changed.emit(tool)

func _on_speed(speed: int) -> void:
	current_speed = speed
	_refresh_highlights()
	time_speed_changed.emit(speed)

func _on_map(map: String) -> void:
	current_map = map
	_refresh_highlights()
	map_type_changed.emit(map)

func _refresh_highlights() -> void:
	for i in _biome_btns.size():
		var sel := i == selected_biome
		var c := BIOME_COLORS[i]
		if sel:
			_biome_btns[i].add_theme_stylebox_override("normal", _style(c, Color.YELLOW, 3))
		else:
			_biome_btns[i].add_theme_stylebox_override("normal", _style(c.darkened(0.4), c, 2))
	for key in _tool_btns:
		_highlight_icon_btn(_tool_btns[key], key == current_tool)
	for key in _speed_btns:
		_highlight_icon_btn(_speed_btns[key], key == current_speed)
	for key in _map_btns:
		_highlight_icon_btn(_map_btns[key], key == current_map)

func _highlight_icon_btn(btn: Button, selected: bool) -> void:
	if selected:
		btn.add_theme_stylebox_override("normal", _style(Color(0.22, 0.22, 0.10), Color.YELLOW, 3))
	else:
		btn.add_theme_stylebox_override("normal", _style(Color(0.12, 0.12, 0.12), Color(0.30, 0.30, 0.30), 2))
