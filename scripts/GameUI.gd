extends CanvasLayer
class_name GameUI

const IconDrawerScript = preload("res://scripts/IconDrawer.gd")

signal biome_selected(idx: int)
signal species_selected(idx: int)
signal time_speed_changed(idx: int)
signal map_type_changed(idx: int)
signal regenerate_requested()
signal power_selected(idx: int)
signal chronicle_reply_submitted(text: String)

const BAR_H   := 72
const PANEL_H := 108    # taller panel: room for buttons + info strip
const BTN     := 54
const TAB_W   := 84.0
const GAP     := 4
const PAD     := 8

# ── Theme colours (web palette) ───────────────────────────────────────────────
const C_SURF    := Color(0.063, 0.082, 0.122, 0.97)   # #10151f
const C_SURF2   := Color(0.090, 0.118, 0.173, 0.97)   # #171e2e
const C_BORDER  := Color(0.142, 0.177, 0.267, 1.0)    # #242d44
const C_ACC     := Color(0.784, 0.573, 0.165)          # #c8922a
const C_TEXT    := Color(0.831, 0.800, 0.722)          # #d4ccb8
const C_MUTED   := Color(0.416, 0.392, 0.314)          # #6a6450

# ── Biomes ────────────────────────────────────────────────────────────────────
const BIOMES: Array[String]       = ["water",  "sand",   "grass",   "forest",  "mountain", "snow",      "jungle",    "swamp"]
const BIOME_ICONS: Array[String]  = ["biome_water","biome_sand","biome_grass","biome_forest","biome_mountain","biome_snow","biome_jungle","biome_swamp"]
const BIOME_LABELS: Array[String] = ["Agua",   "Arena",  "Pradera", "Bosque",  "Monte",    "Tundra",    "Jungla",    "Pantano"]
const BIOME_COLORS: Array[Color]  = [
	Color(0.165, 0.373, 0.659),   # water   – #2a5fa8
	Color(0.831, 0.722, 0.439),   # sand    – #d4b870
	Color(0.353, 0.620, 0.220),   # grass   – #5a9e38
	Color(0.176, 0.431, 0.176),   # forest  – #2d6e2d
	Color(0.541, 0.541, 0.604),   # mountain– #8a8a9a
	Color(0.753, 0.847, 0.941),   # snow    – #c0d8f0
	Color(0.102, 0.420, 0.125),   # jungle  – #1a6b20
	Color(0.282, 0.392, 0.196),   # swamp   – #486432
]
const BIOME_WALKABLE: Array[bool] = [false, true, true, true, false, false, true, true]
const BIOME_DESCS: Array[String]  = [
	"Intransitable · Océanos y mares",
	"Costas y desiertos · Alta movilidad",
	"Llanuras fértiles · Ideal para asentamientos",
	"Bosques templados · Refugio y madera",
	"Cimas rocosas · Solo enanos las dominan",
	"Tundra polar · Clima extremo, intransitable",
	"Jungla ecuatorial · Densa, húmeda, peligrosa",
	"Pantano · Recursos ocultos, movimiento lento",
]

# ── Poderes ───────────────────────────────────────────────────────────────────
const POWERS: Array[String]       = ["meteor",   "lightning", "fire",   "plague", "rain",    "blessing"]
const POWER_ICONS: Array[String]  = ["power_meteor","power_lightning","power_fire","power_plague","power_rain","power_blessing"]
const POWER_LABELS: Array[String] = ["Meteoro",  "Rayo",      "Fuego",  "Plaga",  "Lluvia",  "Bendic"]
const POWER_COLORS: Array[Color]  = [
	Color(0.92, 0.35, 0.08),
	Color(0.98, 0.94, 0.12),
	Color(1.00, 0.40, 0.04),
	Color(0.40, 0.90, 0.20),
	Color(0.18, 0.60, 0.98),
	Color(0.98, 0.88, 0.16),
]
const POWER_DESCS: Array[String] = [
	"Impacto masivo · destruye estructuras en el área",
	"Rayo certero · elimina un objetivo único",
	"Incendio · se propaga por bosques y praderas",
	"Plaga · reduce población del área afectada",
	"Lluvia · convierte arena en pradera, apaga fuegos",
	"Bendición · acelera el crecimiento de aliados",
]

# ── Tabs ──────────────────────────────────────────────────────────────────────
const TAB_DEFS: Array[Array] = [
	["terrain",  "tab_terrain",  "Terreno",  Color(0.18, 0.82, 0.36)],
	["entities", "tab_entities", "Entes",    Color(0.95, 0.58, 0.14)],
	["world",    "tab_world",    "Mundo",    Color(0.18, 0.62, 0.96)],
	["powers",   "tab_powers",   "Poderes",  Color(0.95, 0.22, 0.22)],
]

# ── Velocidad ─────────────────────────────────────────────────────────────────
const SPEED_DEFS: Array[Array] = [
	[0, "pause",   Color(0.88, 0.22, 0.22)],
	[1, "speed_1", Color(0.22, 0.82, 0.38)],
	[2, "speed_2", Color(0.55, 0.84, 0.22)],
	[3, "speed_3", Color(0.95, 0.85, 0.18)],
	[4, "speed_4", Color(0.95, 0.50, 0.12)],
]

# ── Especies: stats normalizados [combate, defensa, diplomacia, expansion] ────
# Basados en SPECIES_LIBRARY (Main.gd) + IA params (design doc)
const SPECIES_STATS: Array[Array] = [
	[0.50, 0.50, 0.70, 0.75],   # Humanos  (combat 1.0, def 1.0, dip 70, exp 75)
	[0.35, 0.55, 0.60, 0.25],   # Elfos    (combat 0.7, def 1.1, dip 60, exp 25)
	[0.55, 1.00, 0.50, 0.35],   # Enanos   (combat 1.1, def 2.0, dip 50, exp 35)
	[0.90, 0.40, 0.30, 0.65],   # Orcos    (combat 1.8, def 0.8, dip 30, exp 65)
]
const SPECIES_STAT_LABELS: Array[String] = ["⚔", "🛡", "🤝", "↗"]
const SPECIES_DESCS: Array[String] = [
	"Adaptables · Comercio y diplomacia ante todo",
	"Longevos · Custodios mágicos del bosque",
	"Forjadores · Memoria perfecta de agravios",
	"Guerreros · Honor clan y fuerza sobre todo",
]

# ── Estado ────────────────────────────────────────────────────────────────────
var selected_biome    := 2
var selected_species  := 0
var selected_power    := 0
var current_speed_idx := 1
var current_map_idx   := 0
var active_tab        := "terrain"

var _tab_btns:     Dictionary      = {}
var _tab_accents:  Dictionary      = {}   # ColorRect accent lines per tab
var _biome_btns:   Array[Button]   = []
var _species_btns: Array[Button]   = []
var _power_btns:   Array[Button]   = []
var _speed_btns:   Dictionary      = {}
var _map_btns:     Dictionary      = {}
var _tool_panel:   Panel
var _terrain_content:  Control
var _entity_content:   Control
var _world_content:    Control
var _power_content:    Control
var _species_data:     Array[Dictionary] = []

var _biome_info_lbl:   Label = null
var _species_info_lbl: Label = null
var _power_info_lbl:   Label = null

var _chronicle_prompt_label:  Label
var _chronicle_reply_buttons: Array[Button] = []

# ── API pública ───────────────────────────────────────────────────────────────

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

# ── Construcción ──────────────────────────────────────────────────────────────

func _build() -> void:
	# Panel de herramientas  — #171e2e con línea de acento
	_tool_panel = Panel.new()
	_tool_panel.anchor_left   = 0.0; _tool_panel.anchor_top    = 1.0
	_tool_panel.anchor_right  = 1.0; _tool_panel.anchor_bottom = 1.0
	_tool_panel.offset_top    = -(BAR_H + PANEL_H)
	_tool_panel.offset_bottom = -BAR_H
	_style_panel(_tool_panel, C_SURF2, true)
	add_child(_tool_panel)

	# Barra inferior  — #090c12
	var bar := Panel.new()
	bar.anchor_left   = 0.0; bar.anchor_top    = 1.0
	bar.anchor_right  = 1.0; bar.anchor_bottom = 1.0
	bar.offset_top    = -BAR_H; bar.offset_bottom = 0.0
	_style_panel(bar, Color(0.035, 0.047, 0.071, 0.98), false)
	add_child(bar)

	_build_bar(bar)
	_build_terrain_content()
	_build_entity_content()
	_build_world_content()
	_build_power_content()
	_show_tab(active_tab)


func _build_bar(bar: Panel) -> void:
	var x  := float(PAD)
	var yc := float(BAR_H - BTN) / 2.0

	# ── Botones de pestaña con acento de color ──
	for td: Array in TAB_DEFS:
		var tid   := td[0] as String
		var ticon := td[1] as String
		var tlbl  := td[2] as String
		var tcol  := td[3] as Color
		var btn   := _make_icon_btn(ticon, tlbl, tcol, TAB_W, float(BTN))
		btn.position = Vector2(x, yc)
		bar.add_child(btn)
		_tab_btns[tid] = btn
		# Línea de acento superior (activa = opaca, inactiva = transparente)
		var acc := ColorRect.new()
		acc.position = Vector2(3.0, 0.0)
		acc.size     = Vector2(TAB_W - 6.0, 3.0)
		acc.color    = Color(tcol.r, tcol.g, tcol.b, 0.0)
		acc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(acc)
		_tab_accents[tid] = acc
		btn.pressed.connect(func(): _on_tab(tid))
		x += TAB_W + GAP

	x += PAD; _divider(bar, x, yc); x += GAP + 5.0

	# ── Botones de velocidad ──
	for sd: Array in SPEED_DEFS:
		var si   := sd[0] as int
		var sico := sd[1] as String
		var scol := sd[2] as Color
		var btn  := _make_icon_btn(sico, "", scol, 46.0, float(BTN))
		btn.position = Vector2(x, yc)
		bar.add_child(btn)
		_speed_btns[si] = btn
		btn.pressed.connect(func(): _on_speed(si))
		x += 46.0 + GAP

	x += PAD; _divider(bar, x, yc); x += GAP + 5.0

	# ── Botón regenerar ──
	var regen := _make_icon_btn("regen", "Nuevo", C_ACC, 62.0, float(BTN))
	regen.position = Vector2(x, yc)
	bar.add_child(regen)
	regen.pressed.connect(func(): regenerate_requested.emit())
	x += 66.0 + GAP + PAD

	# ── Consejo / crónica ──
	_chronicle_prompt_label = Label.new()
	_chronicle_prompt_label.position = Vector2(x, yc + 2.0)
	_chronicle_prompt_label.size = Vector2(220.0, 18.0)
	_chronicle_prompt_label.text = "Consejo:"
	_chronicle_prompt_label.add_theme_font_size_override("font_size", 11)
	_chronicle_prompt_label.add_theme_color_override("font_color", C_ACC)
	bar.add_child(_chronicle_prompt_label)

	for i in range(3):
		var reply_btn := _make_text_btn(Color(0.80, 0.65, 0.22), 90.0, 28.0)
		reply_btn.position = Vector2(x + i * 94.0, yc + 20.0)
		reply_btn.visible = false
		var oi := i
		reply_btn.pressed.connect(func(): _on_chronicle_reply_pressed(oi))
		bar.add_child(reply_btn)
		_chronicle_reply_buttons.append(reply_btn)

	_refresh_speed_highlights()
	_refresh_tab_highlights()


# ── Contenidos de pestañas ─────────────────────────────────────────────────────

func _build_terrain_content() -> void:
	_terrain_content = Control.new()
	_terrain_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_panel.add_child(_terrain_content)

	var btn_y := float(PAD) + 14.0
	var x     := float(PAD)

	# Encabezado de sección
	_section_label(_terrain_content, "PINTAR BIOMA", x, float(PAD) - 2.0)
	x += 90.0

	for i in BIOMES.size():
		var btn := _make_icon_btn(BIOME_ICONS[i], BIOME_LABELS[i], BIOME_COLORS[i], float(BTN), float(BTN))
		btn.position = Vector2(x, btn_y)
		_terrain_content.add_child(btn)
		_biome_btns.append(btn)
		var ci := i
		btn.pressed.connect(func(): _on_biome(ci))
		x += float(BTN) + GAP

	# Separador horizontal
	var sep := ColorRect.new()
	sep.position = Vector2(0.0, btn_y + float(BTN) + 4.0)
	sep.size     = Vector2(1200.0, 1.0)
	sep.color    = C_BORDER
	_terrain_content.add_child(sep)

	# Info strip: icono walkable + descripción del bioma seleccionado
	_biome_info_lbl = Label.new()
	_biome_info_lbl.position = Vector2(float(PAD), btn_y + float(BTN) + 8.0)
	_biome_info_lbl.size     = Vector2(900.0, 18.0)
	_biome_info_lbl.add_theme_font_size_override("font_size", 11)
	_biome_info_lbl.add_theme_color_override("font_color", C_TEXT)
	_terrain_content.add_child(_biome_info_lbl)

	_refresh_biome_highlights()
	_update_biome_info()


func _build_entity_content() -> void:
	_entity_content = Control.new()
	_entity_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_panel.add_child(_entity_content)

	var btn_y := float(PAD) + 14.0
	var x     := float(PAD)

	_section_label(_entity_content, "INVOCAR ESPECIE", x, float(PAD) - 2.0)
	x += 110.0

	for i in _species_data.size():
		var sp    := _species_data[i] as Dictionary
		var sname := sp["name"] as String
		var scol  := sp["color"] as Color
		var btn   := _make_species_btn("species_" + sname.to_lower(), sname, scol, 90.0, float(BTN), i)
		btn.position = Vector2(x, btn_y)
		_entity_content.add_child(btn)
		_species_btns.append(btn)
		var si := i
		btn.pressed.connect(func(): _on_species(si))
		x += 94.0 + GAP

	# Separador
	var sep := ColorRect.new()
	sep.position = Vector2(0.0, btn_y + float(BTN) + 4.0)
	sep.size     = Vector2(1200.0, 1.0)
	sep.color    = C_BORDER
	_entity_content.add_child(sep)

	# Info strip
	_species_info_lbl = Label.new()
	_species_info_lbl.position = Vector2(float(PAD), btn_y + float(BTN) + 8.0)
	_species_info_lbl.size     = Vector2(900.0, 18.0)
	_species_info_lbl.add_theme_font_size_override("font_size", 11)
	_species_info_lbl.add_theme_color_override("font_color", C_TEXT)
	_entity_content.add_child(_species_info_lbl)

	_refresh_species_highlights()
	_update_species_info()


func _build_world_content() -> void:
	_world_content = Control.new()
	_world_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_panel.add_child(_world_content)

	var btn_y := float(PAD) + 14.0
	var x     := float(PAD)

	_section_label(_world_content, "TIPO DE MAPA", x, float(PAD) - 2.0)
	x += 90.0

	var maps: Array[Array] = [
		[0, "map_random",    "Archipiélago", Color(0.58, 0.55, 0.90)],
		[1, "map_earthlike", "Tipo Tierra",  Color(0.22, 0.75, 0.45)],
		[2, "map_continent", "Continente",   Color(0.18, 0.65, 0.92)],
	]
	var map_descs: Array[String] = [
		"8-15 islas dispersas · biomas variados",
		"5 continentes · polos de nieve · junglas ecuatoriales",
		"Un continente grande + islas satélite · interior con jungla",
	]
	for md: Array in maps:
		var mi  := md[0] as int
		var ico := md[1] as String
		var lbl := md[2] as String
		var col := md[3] as Color
		var btn := _make_icon_btn(ico, lbl, col, 110.0, float(BTN))
		btn.position = Vector2(x, btn_y)
		_world_content.add_child(btn)
		_map_btns[mi] = btn
		var mii := mi
		var desc_lbl := Label.new()
		desc_lbl.text = map_descs[mi]
		desc_lbl.position = Vector2(x, btn_y + float(BTN) + 6.0)
		desc_lbl.size = Vector2(108.0, 28.0)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color", C_MUTED)
		_world_content.add_child(desc_lbl)
		btn.pressed.connect(func(): _on_map(mii))
		x += 114.0 + GAP

	_refresh_map_highlights()


func _build_power_content() -> void:
	_power_content = Control.new()
	_power_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_panel.add_child(_power_content)

	var btn_y := float(PAD) + 14.0
	var x     := float(PAD)

	_section_label(_power_content, "USAR PODER DIVINO", x, float(PAD) - 2.0)
	x += 120.0

	for i in POWERS.size():
		var btn := _make_icon_btn(POWER_ICONS[i], POWER_LABELS[i], POWER_COLORS[i], float(BTN), float(BTN))
		btn.position = Vector2(x, btn_y)
		_power_content.add_child(btn)
		_power_btns.append(btn)
		var pi := i
		btn.pressed.connect(func(): _on_power(pi))
		x += float(BTN) + GAP

	# Separador
	var sep := ColorRect.new()
	sep.position = Vector2(0.0, btn_y + float(BTN) + 4.0)
	sep.size     = Vector2(1200.0, 1.0)
	sep.color    = C_BORDER
	_power_content.add_child(sep)

	# Info strip
	_power_info_lbl = Label.new()
	_power_info_lbl.position = Vector2(float(PAD), btn_y + float(BTN) + 8.0)
	_power_info_lbl.size     = Vector2(900.0, 18.0)
	_power_info_lbl.add_theme_font_size_override("font_size", 11)
	_power_info_lbl.add_theme_color_override("font_color", C_TEXT)
	_power_content.add_child(_power_info_lbl)

	_refresh_power_highlights()
	_update_power_info()


# ── Cambio de pestaña ─────────────────────────────────────────────────────────

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
	_update_biome_info()
	biome_selected.emit(idx)

func _on_species(idx: int) -> void:
	selected_species = idx
	_refresh_species_highlights()
	_update_species_info()
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
	_update_power_info()
	power_selected.emit(idx)

func _on_chronicle_reply_pressed(idx: int) -> void:
	if idx < 0 or idx >= _chronicle_reply_buttons.size():
		return
	var lbl := _chronicle_reply_buttons[idx].text.strip_edges()
	if lbl == "":
		return
	chronicle_reply_submitted.emit(lbl)


# ── Actualizar info strips ────────────────────────────────────────────────────

func _update_biome_info() -> void:
	if _biome_info_lbl == null:
		return
	var i := selected_biome
	if i < 0 or i >= BIOMES.size():
		return
	var walkable_str := "✓ Caminable" if BIOME_WALKABLE[i] else "✗ Bloqueado"
	var col := C_TEXT if BIOME_WALKABLE[i] else Color(0.95, 0.35, 0.35)
	_biome_info_lbl.add_theme_color_override("font_color", col)
	_biome_info_lbl.text = "%s  %s  ·  %s" % [BIOME_LABELS[i].to_upper(), walkable_str, BIOME_DESCS[i]]

func _update_species_info() -> void:
	if _species_info_lbl == null:
		return
	var i := selected_species
	if i >= _species_data.size() or i >= SPECIES_DESCS.size():
		return
	var sname := (_species_data[i] as Dictionary)["name"] as String
	var desc  := SPECIES_DESCS[i] if i < SPECIES_DESCS.size() else ""
	var stats := SPECIES_STATS[i] if i < SPECIES_STATS.size() else [0.5, 0.5, 0.5, 0.5]
	var stat_str := ""
	var labels := ["Cbt", "Def", "Dip", "Exp"]
	for j in 4:
		var pct := int((stats[j] as float) * 100.0)
		stat_str += "  %s %d%%" % [labels[j], pct]
	_species_info_lbl.text = "%s · %s  |%s" % [sname.to_upper(), desc, stat_str]

func _update_power_info() -> void:
	if _power_info_lbl == null:
		return
	var i := selected_power
	if i < 0 or i >= POWERS.size():
		return
	_power_info_lbl.text = "%s  ·  %s" % [POWER_LABELS[i].to_upper(), POWER_DESCS[i]]


# ── Highlights ────────────────────────────────────────────────────────────────

func _refresh_tab_highlights() -> void:
	for td: Array in TAB_DEFS:
		var tid  := td[0] as String
		var tcol := td[3] as Color
		if not _tab_btns.has(tid):
			continue
		var is_active := tid == active_tab
		(_tab_btns[tid] as Button).add_theme_stylebox_override("normal", _style_btn(tcol, is_active))
		# Acento de color en la parte superior del botón activo
		if _tab_accents.has(tid):
			(_tab_accents[tid] as ColorRect).color = tcol if is_active else Color(0.0, 0.0, 0.0, 0.0)

func _refresh_biome_highlights() -> void:
	for i in _biome_btns.size():
		_biome_btns[i].add_theme_stylebox_override("normal",
			_style_btn(BIOME_COLORS[i], i == selected_biome))

func _refresh_species_highlights() -> void:
	for i in _species_btns.size():
		var c := (_species_data[i] as Dictionary)["color"] as Color
		_species_btns[i].add_theme_stylebox_override("normal",
			_style_btn(c, i == selected_species))

func _refresh_speed_highlights() -> void:
	for sd: Array in SPEED_DEFS:
		var si  := sd[0] as int
		var sc  := sd[2] as Color
		if _speed_btns.has(si):
			(_speed_btns[si] as Button).add_theme_stylebox_override("normal",
				_style_btn(sc, si == current_speed_idx))

func _refresh_map_highlights() -> void:
	var map_colors: Array[Color] = [Color(0.58, 0.55, 0.90), Color(0.22, 0.75, 0.45), Color(0.18, 0.65, 0.92)]
	for key in _map_btns:
		var ki := key as int
		var c  := map_colors[clampi(ki, 0, map_colors.size() - 1)]
		(_map_btns[key] as Button).add_theme_stylebox_override("normal",
			_style_btn(c, ki == current_map_idx))

func _refresh_power_highlights() -> void:
	for i in _power_btns.size():
		_power_btns[i].add_theme_stylebox_override("normal",
			_style_btn(POWER_COLORS[i], i == selected_power))


# ── Fábricas de widgets ────────────────────────────────────────────────────────

func _make_icon_btn(icon_type: String, label: String, color: Color,
		w: float = BTN, h: float = BTN) -> Button:
	var btn := Button.new()
	btn.size = Vector2(w, h)
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	btn.add_theme_stylebox_override("normal",  _style_btn(color, false))
	btn.add_theme_stylebox_override("hover",   _style_flat(color.darkened(0.08), Color.WHITE, 3))
	btn.add_theme_stylebox_override("pressed", _style_flat(color.darkened(0.04), Color.WHITE, 3))
	btn.add_theme_stylebox_override("focus",   _style_btn(color, false))

	if label == "":
		var dr := IconDrawerScript.new()
		dr.icon_type  = icon_type
		dr.icon_color = Color.WHITE
		dr.position   = Vector2.ZERO
		dr.size       = Vector2(w, h)
		btn.add_child(dr)
		return btn

	var icon_h := h * 0.60
	var dr2 := IconDrawerScript.new()
	dr2.icon_type  = icon_type
	dr2.icon_color = Color.WHITE
	dr2.position   = Vector2(0.0, 2.0)
	dr2.size       = Vector2(w, icon_h - 2.0)
	btn.add_child(dr2)

	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(1.0, icon_h)
	name_lbl.size     = Vector2(w - 2.0, h * 0.38)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
	name_lbl.clip_text = true
	btn.add_child(name_lbl)
	return btn


## Botón de especie con icono, nombre y mini-barras de estadísticas
func _make_species_btn(icon_type: String, label: String, color: Color,
		w: float, h: float, sp_idx: int) -> Button:
	var btn := Button.new()
	btn.size = Vector2(w, h)
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	btn.add_theme_stylebox_override("normal",  _style_btn(color, false))
	btn.add_theme_stylebox_override("hover",   _style_flat(color.darkened(0.08), Color.WHITE, 3))
	btn.add_theme_stylebox_override("pressed", _style_flat(color.darkened(0.04), Color.WHITE, 3))
	btn.add_theme_stylebox_override("focus",   _style_btn(color, false))

	# Icono (parte superior 52%)
	var icon_h := h * 0.52
	var dr := IconDrawerScript.new()
	dr.icon_type  = icon_type
	dr.icon_color = Color.WHITE
	dr.position   = Vector2(0.0, 2.0)
	dr.size       = Vector2(w, icon_h - 2.0)
	btn.add_child(dr)

	# Nombre
	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(1.0, icon_h)
	name_lbl.size     = Vector2(w - 2.0, 14.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.clip_text = true
	btn.add_child(name_lbl)

	# Mini barras de estadísticas [⚔ Def Dip Exp]
	var stats := SPECIES_STATS[sp_idx] if sp_idx < SPECIES_STATS.size() else [0.5, 0.5, 0.5, 0.5]
	var bar_top_y := icon_h + 16.0
	var total_bar_w := w - 8.0
	var bar_w := total_bar_w / 4.0 - 1.0
	for j in 4:
		var stat_val := clampf(stats[j] as float, 0.0, 1.0)
		var bx := 4.0 + j * (bar_w + 1.0)
		# Fondo de barra
		var bg := ColorRect.new()
		bg.position = Vector2(bx, bar_top_y)
		bg.size     = Vector2(bar_w, 6.0)
		bg.color    = Color(0.08, 0.08, 0.10, 0.80)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(bg)
		# Relleno proporcional
		var fill := ColorRect.new()
		fill.position = Vector2(bx, bar_top_y)
		fill.size     = Vector2(bar_w * stat_val, 6.0)
		fill.color    = color.lightened(0.25)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(fill)

	return btn


func _make_text_btn(color: Color, w: float, h: float) -> Button:
	var btn := Button.new()
	btn.size = Vector2(w, h)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("normal",  _style_btn(color, false))
	btn.add_theme_stylebox_override("hover",   _style_flat(color.darkened(0.12), Color.WHITE, 3))
	btn.add_theme_stylebox_override("pressed", _style_flat(color.darkened(0.05), Color.WHITE, 3))
	btn.add_theme_stylebox_override("focus",   _style_btn(color, false))
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color",       Color.WHITE)
	btn.add_theme_color_override("font_color_hover", Color.WHITE)
	return btn


func _section_label(parent: Control, text: String, x: float, top: float) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, top)
	lbl.size = Vector2(120.0, 14.0)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", C_ACC)   # acento dorado
	parent.add_child(lbl)


func _style_btn(color: Color, selected: bool) -> StyleBoxFlat:
	if selected:
		return _style_flat(color.darkened(0.08), Color.WHITE, 3)
	else:
		return _style_flat(color.darkened(0.42), color.lightened(0.18), 2)


func _style_flat(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left   = bw; s.border_width_right  = bw
	s.border_width_top    = bw; s.border_width_bottom = bw
	s.border_color = border
	s.corner_radius_top_left     = 5
	s.corner_radius_top_right    = 5
	s.corner_radius_bottom_left  = 5
	s.corner_radius_bottom_right = 5
	return s


func _style_panel(p: Panel, color: Color, top_accent: bool) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_width_top = 2
	s.border_color = C_BORDER if top_accent else Color(0.071, 0.086, 0.133)
	p.add_theme_stylebox_override("panel", s)


func _divider(parent: Control, x: float, y: float) -> void:
	var d := ColorRect.new()
	d.position = Vector2(x, y + 6.0)
	d.size     = Vector2(1.0, float(BTN) - 12.0)
	d.color    = Color(0.142, 0.177, 0.267, 0.90)
	parent.add_child(d)
