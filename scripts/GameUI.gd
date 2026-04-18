extends CanvasLayer
class_name GameUI

signal biome_selected(idx: int)
signal species_selected(idx: int)
signal time_speed_changed(idx: int)
signal map_type_changed(idx: int)
signal regenerate_requested()
signal power_selected(idx: int)
signal chronicle_reply_submitted(text: String)

const BAR_H   := 72
const PANEL_H := 78
const BTN     := 56
const TAB_W   := 80.0
const GAP     := 5
const PAD     := 10

const BIOMES: Array[String]       = ["water",  "sand", "grass", "forest", "mountain"]
const BIOME_ICONS: Array[String]  = ["≈",      ":",    "#",     "Y",      "^"]
const BIOME_LABELS: Array[String] = ["Agua",   "Arena","Hierba","Bosque", "Montaña"]
const BIOME_COLORS: Array[Color]  = [
	Color(0.20, 0.45, 0.85),
	Color(0.85, 0.80, 0.50),
	Color(0.30, 0.70, 0.30),
	Color(0.10, 0.45, 0.15),
	Color(0.45, 0.45, 0.45),
]

const POWERS: Array[String]        = ["meteor",  "lightning","fire",  "plague","rain",   "blessing"]
const POWER_ICONS: Array[String]   = ["*",       "!",        "~",     "x",     ",,,",    "+"]
const POWER_LABELS: Array[String]  = ["Meteoro", "Rayo",     "Fuego", "Plaga", "Lluvia", "Bendicion"]
const POWER_COLORS: Array[Color]   = [
	Color(1.0, 0.35, 0.10),
	Color(1.0, 0.95, 0.20),
	Color(1.0, 0.50, 0.05),
	Color(0.55, 0.90, 0.25),
	Color(0.30, 0.65, 1.00),
	Color(1.00, 0.88, 0.20),
]

# Tab definitions: [id, icon_char, label, color]
const TAB_DEFS: Array[Array] = [
	["terrain",  "///", "Terreno",  Color(0.50, 0.82, 0.40)],
	["entities", "o o", "Unidades", Color(0.95, 0.68, 0.35)],
	["world",    "~~~", "Mundo",    Color(0.40, 0.68, 0.95)],
	["powers",   "***", "Poderes",  Color(1.00, 0.48, 0.18)],
]

var selected_biome    := 2
var selected_species  := 0
var selected_power    := 0
var current_speed_idx := 1
var current_map_idx   := 0
var active_tab        := "terrain"

var _tab_btns:    Dictionary      = {}
var _biome_btns:  Array[Button]   = []
var _species_btns:Array[Button]   = []
var _power_btns:  Array[Button]   = []
var _speed_btns:  Dictionary      = {}
var _map_btns:    Dictionary      = {}
var _tool_panel:  Panel
var _terrain_content:  Control
var _entity_content:   Control
var _world_content:    Control
var _power_content:    Control
var _species_data:     Array[Dictionary] = []

var _chronicle_prompt_label:   Label
var _chronicle_reply_buttons:  Array[Button] = []

# ── Public API ───────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10

func setup_species(species: Array[Dictionary]) -> void:
	_species_data = species
	_build()

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

# ── Build ────────────────────────────────────────────────────────────────────

func _build() -> void:
	# Tool panel (above bar)
	_tool_panel = Panel.new()
	_tool_panel.anchor_left   = 0.0; _tool_panel.anchor_top    = 1.0
	_tool_panel.anchor_right  = 1.0; _tool_panel.anchor_bottom = 1.0
	_tool_panel.offset_top    = -(BAR_H + PANEL_H)
	_tool_panel.offset_bottom = -BAR_H
	_tool_panel.offset_left   = 0.0
	_tool_panel.offset_right  = 0.0
	_style_panel(_tool_panel, Color(0.08, 0.08, 0.12, 0.97))
	add_child(_tool_panel)

	# Main bar
	var bar := Panel.new()
	bar.anchor_left   = 0.0; bar.anchor_top    = 1.0
	bar.anchor_right  = 1.0; bar.anchor_bottom = 1.0
	bar.offset_top    = -BAR_H; bar.offset_bottom = 0.0
	bar.offset_left   = 0.0;   bar.offset_right  = 0.0
	_style_panel(bar, Color(0.06, 0.06, 0.09, 0.97))
	add_child(bar)

	_build_bar(bar)
	_build_terrain_content()
	_build_entity_content()
	_build_world_content()
	_build_power_content()
	_show_tab(active_tab)

func _build_bar(bar: Panel) -> void:
	var x   := float(PAD)
	var yc  := (BAR_H - BTN) / 2.0

	# ── Tab buttons ──
	for td: Array in TAB_DEFS:
		var tid   := td[0] as String
		var ticon := td[1] as String
		var tlbl  := td[2] as String
		var tcol  := td[3] as Color
		var btn   := _make_icon_btn(ticon, tlbl, tcol, TAB_W, BTN)
		btn.position = Vector2(x, yc)
		bar.add_child(btn)
		_tab_btns[tid] = btn
		btn.pressed.connect(func(): _on_tab(tid))
		x += TAB_W + GAP

	x += PAD; _divider(bar, x, yc); x += GAP + 6.0

	# ── Speed buttons ──
	var speeds: Array[Array] = [
		[0, "||",  Color(0.90, 0.30, 0.30)],
		[1, "1x",  Color(0.45, 0.90, 0.45)],
		[2, "2x",  Color(0.45, 0.90, 0.45)],
		[3, "5x",  Color(0.95, 0.88, 0.30)],
		[4, "10x", Color(0.95, 0.55, 0.18)],
	]
	for sd: Array in speeds:
		var si   := sd[0] as int
		var slbl := sd[1] as String
		var scol := sd[2] as Color
		var btn  := _make_icon_btn(slbl, "", scol, float(BTN), float(BTN))
		btn.position = Vector2(x, yc)
		bar.add_child(btn)
		_speed_btns[si] = btn
		btn.pressed.connect(func(): _on_speed(si))
		x += float(BTN) + GAP

	x += PAD; _divider(bar, x, yc); x += GAP + 6.0

	# ── Regen button ──
	var regen := _make_icon_btn("↺", "Generar", Color(1.0, 0.55, 0.18), float(BTN) + 24.0, float(BTN))
	regen.position = Vector2(x, yc)
	bar.add_child(regen)
	regen.pressed.connect(func(): regenerate_requested.emit())
	x += float(BTN) + 30.0 + GAP

	x += PAD + 4.0

	# ── Chronicle advice ──
	_chronicle_prompt_label = Label.new()
	_chronicle_prompt_label.position = Vector2(x, yc + 2.0)
	_chronicle_prompt_label.size = Vector2(240.0, 18.0)
	_chronicle_prompt_label.text = "Consejo:"
	_chronicle_prompt_label.add_theme_font_size_override("font_size", 11)
	_chronicle_prompt_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.46))
	bar.add_child(_chronicle_prompt_label)

	for i in range(3):
		var reply_btn := _make_icon_btn("...", "", Color(0.82, 0.68, 0.28), 86.0, 28.0)
		reply_btn.position = Vector2(x + i * 90.0, yc + 20.0)
		reply_btn.visible = false
		var oi := i
		reply_btn.pressed.connect(func(): _on_chronicle_reply_pressed(oi))
		bar.add_child(reply_btn)
		_chronicle_reply_buttons.append(reply_btn)

	_refresh_speed_highlights()
	_refresh_tab_highlights()

func _build_terrain_content() -> void:
	_terrain_content = Control.new()
	_terrain_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_panel.add_child(_terrain_content)

	var x  := float(PAD)
	var yc := (PANEL_H - BTN) / 2.0
	_content_label(_terrain_content, "PINTAR:", x, yc)
	x += 68.0

	for i in BIOMES.size():
		var btn := _make_icon_btn(BIOME_ICONS[i], BIOME_LABELS[i], BIOME_COLORS[i], float(BTN), float(BTN))
		btn.position = Vector2(x, yc)
		_terrain_content.add_child(btn)
		_biome_btns.append(btn)
		var ci := i
		btn.pressed.connect(func(): _on_biome(ci))
		x += float(BTN) + GAP

	_refresh_biome_highlights()

func _build_entity_content() -> void:
	_entity_content = Control.new()
	_entity_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_panel.add_child(_entity_content)

	var x  := float(PAD)
	var yc := (PANEL_H - BTN) / 2.0
	_content_label(_entity_content, "SPAWN:", x, yc)
	x += 68.0

	for i in _species_data.size():
		var sp    := _species_data[i] as Dictionary
		var sname := sp["name"] as String
		var scol  := sp["color"] as Color
		var icon  := sname.substr(0, 2).to_upper()
		var btn   := _make_icon_btn(icon, sname, scol, 86.0, float(BTN))
		btn.position = Vector2(x, yc)
		_entity_content.add_child(btn)
		_species_btns.append(btn)
		var si := i
		btn.pressed.connect(func(): _on_species(si))
		x += 86.0 + GAP

	_refresh_species_highlights()

func _build_world_content() -> void:
	_world_content = Control.new()
	_world_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_panel.add_child(_world_content)

	var x  := float(PAD)
	var yc := (PANEL_H - BTN) / 2.0
	_content_label(_world_content, "MAPA:", x, yc)
	x += 68.0

	var maps: Array[Array] = [
		[0, "?",  "Aleatorio",  Color(0.70, 0.70, 0.95)],
		[1, "E",  "Tipo Tierra",Color(0.45, 0.85, 0.55)],
		[2, "O",  "Continente", Color(0.40, 0.75, 0.95)],
	]
	for md: Array in maps:
		var mi  := md[0] as int
		var ico := md[1] as String
		var lbl := md[2] as String
		var col := md[3] as Color
		var btn := _make_icon_btn(ico, lbl, col, 100.0, float(BTN))
		btn.position = Vector2(x, yc)
		_world_content.add_child(btn)
		_map_btns[mi] = btn
		btn.pressed.connect(func(): _on_map(mi))
		x += 100.0 + GAP

	_refresh_map_highlights()

func _build_power_content() -> void:
	_power_content = Control.new()
	_power_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_panel.add_child(_power_content)

	var x  := float(PAD)
	var yc := (PANEL_H - BTN) / 2.0
	_content_label(_power_content, "PODER:", x, yc)
	x += 68.0

	for i in POWERS.size():
		var btn := _make_icon_btn(POWER_ICONS[i], POWER_LABELS[i], POWER_COLORS[i], float(BTN), float(BTN))
		btn.position = Vector2(x, yc)
		_power_content.add_child(btn)
		_power_btns.append(btn)
		var pi := i
		btn.pressed.connect(func(): _on_power(pi))
		x += float(BTN) + GAP

	_refresh_power_highlights()

# ── Tab / tool switching ─────────────────────────────────────────────────────

func _show_tab(tab: String) -> void:
	_terrain_content.visible = tab == "terrain"
	_entity_content.visible  = tab == "entities"
	_world_content.visible   = tab == "world"
	_power_content.visible   = tab == "powers"
	_tool_panel.visible      = true

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

# ── Highlight refresh ────────────────────────────────────────────────────────

func _refresh_tab_highlights() -> void:
	for td: Array in TAB_DEFS:
		var tid  := td[0] as String
		var tcol := td[3] as Color
		if not _tab_btns.has(tid):
			continue
		if tid == active_tab:
			_tab_btns[tid].add_theme_stylebox_override("normal",
				_style(tcol.darkened(0.25), Color.YELLOW, 3))
		else:
			_tab_btns[tid].add_theme_stylebox_override("normal",
				_style(tcol.darkened(0.60), tcol.darkened(0.10), 2))

func _refresh_biome_highlights() -> void:
	for i in _biome_btns.size():
		var c := BIOME_COLORS[i]
		if i == selected_biome:
			_biome_btns[i].add_theme_stylebox_override("normal", _style(c.darkened(0.15), Color.YELLOW, 3))
		else:
			_biome_btns[i].add_theme_stylebox_override("normal", _style(c.darkened(0.50), c, 2))

func _refresh_species_highlights() -> void:
	for i in _species_btns.size():
		var c := (_species_data[i] as Dictionary)["color"] as Color
		if i == selected_species:
			_species_btns[i].add_theme_stylebox_override("normal", _style(c.darkened(0.15), Color.YELLOW, 3))
		else:
			_species_btns[i].add_theme_stylebox_override("normal", _style(c.darkened(0.55), c, 2))

func _refresh_speed_highlights() -> void:
	for key in _speed_btns:
		if key == current_speed_idx:
			_speed_btns[key].add_theme_stylebox_override("normal",
				_style(Color(0.22, 0.22, 0.08), Color.YELLOW, 3))
		else:
			_speed_btns[key].add_theme_stylebox_override("normal",
				_style(Color(0.10, 0.10, 0.14), Color(0.25, 0.25, 0.30), 2))

func _refresh_map_highlights() -> void:
	for key in _map_btns:
		var c: Color = Color(0.40, 0.75, 0.95)
		if key == 0: c = Color(0.70, 0.70, 0.95)
		elif key == 1: c = Color(0.45, 0.85, 0.55)
		if key == current_map_idx:
			_map_btns[key].add_theme_stylebox_override("normal", _style(c.darkened(0.15), Color.YELLOW, 3))
		else:
			_map_btns[key].add_theme_stylebox_override("normal", _style(c.darkened(0.55), c, 2))

func _refresh_power_highlights() -> void:
	for i in _power_btns.size():
		var c := POWER_COLORS[i]
		if i == selected_power:
			_power_btns[i].add_theme_stylebox_override("normal", _style(c.darkened(0.18), Color.YELLOW, 3))
		else:
			_power_btns[i].add_theme_stylebox_override("normal", _style(c.darkened(0.58), c, 2))

# ── Widget factories ─────────────────────────────────────────────────────────

# Two-line icon button: large symbol on top, small label below
func _make_icon_btn(icon: String, label: String, color: Color,
		w: float = BTN, h: float = BTN) -> Button:
	var btn := Button.new()
	btn.size = Vector2(w, h)
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_children = CanvasItem.CLIP_CHILDREN_ONLY

	# Background style
	btn.add_theme_stylebox_override("normal", _style(color.darkened(0.55), color.darkened(0.10), 2))
	btn.add_theme_stylebox_override("hover",  _style(color.darkened(0.30), Color.WHITE, 3))
	btn.add_theme_stylebox_override("pressed",_style(color.darkened(0.10), Color.YELLOW, 3))
	btn.add_theme_stylebox_override("focus",  _style(color.darkened(0.55), color.darkened(0.10), 2))

	if label == "":
		# Single-line centered (speed buttons, etc.)
		btn.text = icon
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color",       color.lightened(0.55))
		btn.add_theme_color_override("font_color_hover", Color.WHITE)
		return btn

	# Two-row layout: icon label on top, text label on bottom
	btn.text = ""

	var icon_lbl := Label.new()
	icon_lbl.text = icon
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.position = Vector2(0, 4)
	icon_lbl.size     = Vector2(w, h * 0.55)
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_lbl.add_theme_font_size_override("font_size", 20)
	icon_lbl.add_theme_color_override("font_color", color.lightened(0.60))
	btn.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(1, h * 0.58)
	name_lbl.size     = Vector2(w - 2.0, h * 0.38)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
	name_lbl.clip_text = true
	btn.add_child(name_lbl)

	return btn

func _content_label(parent: Control, text: String, x: float, yc: float) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, yc + (BTN - 16.0) / 2.0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.50, 0.50, 0.55))
	parent.add_child(lbl)

func _style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left   = bw; s.border_width_right  = bw
	s.border_width_top    = bw; s.border_width_bottom  = bw
	s.border_color = border
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4
	s.corner_radius_bottom_right = 4
	return s

func _style_panel(p: Panel, color: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_width_top = 1
	s.border_color = Color(0.20, 0.20, 0.26)
	p.add_theme_stylebox_override("panel", s)

func _divider(parent: Control, x: float, y: float) -> void:
	var d := ColorRect.new()
	d.position = Vector2(x, y + 4.0)
	d.size     = Vector2(2.0, float(BTN) - 8.0)
	d.color    = Color(0.22, 0.22, 0.28)
	parent.add_child(d)
