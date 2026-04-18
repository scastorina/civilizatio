extends Node2D

const TILE_SIZE := 16
const WORLD_WIDTH := 96
const WORLD_HEIGHT := 54
const HUMAN_COUNT := 20
const MOVE_TICK_SECONDS := 0.35
const BIOMES: Array[String] = ["water", "sand", "grass", "forest", "mountain"]
const MAP_PRESETS: Array[String] = ["random", "earth_like", "continent"]
const MAP_PRESET_LABELS: Array[String] = ["Aleatorio", "Tipo Tierra", "Continente"]
const TIME_SPEEDS: Array[float] = [1.0, 2.0, 5.0, 10.0]
const SPECIES_LIBRARY: Array[Dictionary] = [
	{"name": "Humanos", "color": Color(1.0, 0.92, 0.80), "preferred": ["grass", "forest"]},
	{"name": "Elfos", "color": Color(0.75, 0.95, 0.75), "preferred": ["forest", "grass"]},
	{"name": "Enanos", "color": Color(0.82, 0.75, 0.62), "preferred": ["mountain", "forest"]},
	{"name": "Orcos", "color": Color(0.65, 0.80, 0.55), "preferred": ["sand", "grass"]},
]

var rng := RandomNumberGenerator.new()
var world_grid := WorldGrid.new(WORLD_WIDTH, WORLD_HEIGHT)
var humans: Array[Human] = []
var move_tick_accumulator := 0.0

var editor_enabled := false
var selected_biome_idx := 2
var selected_map_preset_idx := 0
var selected_species_count := 3
var selected_time_speed_idx := 0

var ui_layer: CanvasLayer
var map_option: OptionButton
var species_slider: HSlider
var species_value_label: Label
var time_speed_option: OptionButton

func _ready() -> void:
	rng.randomize()
	_build_config_menu()
	_regenerate_world()

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		_regenerate_world()

	if editor_enabled:
		return

	var time_scale := TIME_SPEEDS[selected_time_speed_idx]
	move_tick_accumulator += delta * time_scale
	while move_tick_accumulator >= MOVE_TICK_SECONDS:
		move_tick_accumulator -= MOVE_TICK_SECONDS
		_move_humans()
		_update_evolution()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_editor_hotkeys(event.keycode)

	if not editor_enabled:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _mouse_to_cell(event.position)
		if not world_grid.is_in_bounds(cell):
			return
		var biome: String = BIOMES[selected_biome_idx]
		if (biome == "water" or biome == "mountain") and _has_human_in_cell(cell):
			return
		world_grid.set_biome(cell, biome)
		queue_redraw()

func _build_config_menu() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 90)
	panel.size = Vector2(260, 210)
	ui_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Configuración"
	vbox.add_child(title)

	var map_label := Label.new()
	map_label.text = "Mapa"
	vbox.add_child(map_label)

	map_option = OptionButton.new()
	for label in MAP_PRESET_LABELS:
		map_option.add_item(label)
	map_option.select(selected_map_preset_idx)
	map_option.item_selected.connect(_on_map_preset_selected)
	vbox.add_child(map_option)

	var species_label := Label.new()
	species_label.text = "Cantidad de especies"
	vbox.add_child(species_label)

	species_slider = HSlider.new()
	species_slider.min_value = 1
	species_slider.max_value = SPECIES_LIBRARY.size()
	species_slider.step = 1
	species_slider.value = selected_species_count
	species_slider.value_changed.connect(_on_species_slider_changed)
	vbox.add_child(species_slider)

	species_value_label = Label.new()
	species_value_label.text = "Especies activas: %s" % selected_species_count
	vbox.add_child(species_value_label)

	var speed_label := Label.new()
	speed_label.text = "Adelantador de tiempo"
	vbox.add_child(speed_label)

	time_speed_option = OptionButton.new()
	for speed in TIME_SPEEDS:
		time_speed_option.add_item("x%s" % speed)
	time_speed_option.select(selected_time_speed_idx)
	time_speed_option.item_selected.connect(_on_time_speed_selected)
	vbox.add_child(time_speed_option)

	var apply_button := Button.new()
	apply_button.text = "Aplicar y regenerar"
	apply_button.pressed.connect(_on_apply_config_pressed)
	vbox.add_child(apply_button)

func _on_map_preset_selected(index: int) -> void:
	selected_map_preset_idx = index

func _on_species_slider_changed(value: float) -> void:
	selected_species_count = int(value)
	species_value_label.text = "Especies activas: %s" % selected_species_count

func _on_time_speed_selected(index: int) -> void:
	selected_time_speed_idx = index
	queue_redraw()

func _on_apply_config_pressed() -> void:
	_regenerate_world()

func _handle_editor_hotkeys(keycode: int) -> void:
	match keycode:
		KEY_E:
			editor_enabled = not editor_enabled
			queue_redraw()
		KEY_1:
			selected_biome_idx = 0
			queue_redraw()
		KEY_2:
			selected_biome_idx = 1
			queue_redraw()
		KEY_3:
			selected_biome_idx = 2
			queue_redraw()
		KEY_4:
			selected_biome_idx = 3
			queue_redraw()
		KEY_5:
			selected_biome_idx = 4
			queue_redraw()

func _regenerate_world() -> void:
	move_tick_accumulator = 0.0
	world_grid.generate(MAP_PRESETS[selected_map_preset_idx])
	_spawn_humans()
	queue_redraw()

func _active_species() -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	for i in range(selected_species_count):
		active.append(SPECIES_LIBRARY[i])
	return active

func _spawn_humans() -> void:
	for human in humans:
		human.queue_free()
	humans.clear()

	var walkable_cells := world_grid.get_all_walkable_cells()
	_shuffle_vector2i_array(walkable_cells)

	var active_species := _active_species()
	var spawn_count := mini(HUMAN_COUNT, walkable_cells.size())
	for i in range(spawn_count):
		var species := active_species[i % active_species.size()]
		var human := Human.new()
		human.setup(
			walkable_cells[i],
			TILE_SIZE,
			species["name"],
			species["color"],
			species["preferred"]
		)
		add_child(human)
		humans.append(human)

func _move_humans() -> void:
	var occupied := {}
	for human in humans:
		occupied[_cell_key(human.grid_position)] = true

	for human in humans:
		occupied.erase(_cell_key(human.grid_position))
		var next := human.choose_next_cell(world_grid, rng, occupied)
		human.set_grid_position(next)
		occupied[_cell_key(next)] = true

func _update_evolution() -> void:
	for human in humans:
		var current_biome := world_grid.get_biome(human.grid_position)
		human.update_evolution(current_biome)

func _draw() -> void:
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var biome := world_grid.get_biome(Vector2i(x, y))
			draw_rect(Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE), _biome_color(biome))

	draw_string(ThemeDB.fallback_font, Vector2(10, 18), "Enter = regenerar mundo", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(ThemeDB.fallback_font, Vector2(10, 36), "Humanos: %s (sin superposición)" % humans.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(ThemeDB.fallback_font, Vector2(10, 54), "Editor: %s (E)" % ("ON" if editor_enabled else "OFF"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(ThemeDB.fallback_font, Vector2(10, 72), "Bioma editor: %s (1-5)" % BIOMES[selected_biome_idx], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(ThemeDB.fallback_font, Vector2(10, 90), "Tiempo: x%s" % TIME_SPEEDS[selected_time_speed_idx], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(ThemeDB.fallback_font, Vector2(10, 108), _species_summary_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)

func _species_summary_text() -> String:
	var stats := {}
	for human in humans:
		if not stats.has(human.species_name):
			stats[human.species_name] = {"count": 0, "evo_sum": 0.0}
		stats[human.species_name]["count"] += 1
		stats[human.species_name]["evo_sum"] += human.evolution_score

	var parts: Array[String] = []
	for name in stats.keys():
		var count: int = stats[name]["count"]
		var evo_avg: float = stats[name]["evo_sum"] / maxf(float(count), 1.0)
		parts.append("%s:%s(%.1f)" % [name, count, evo_avg])
	return "Evolución: " + ", ".join(parts)

func _mouse_to_cell(mouse_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(mouse_pos.x / TILE_SIZE)), int(floor(mouse_pos.y / TILE_SIZE)))

func _has_human_in_cell(cell: Vector2i) -> bool:
	for human in humans:
		if human.grid_position == cell:
			return true
	return false

func _shuffle_vector2i_array(items: Array[Vector2i]) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := items[i]
		items[i] = items[j]
		items[j] = tmp

func _cell_key(cell: Vector2i) -> String:
	return "%s:%s" % [cell.x, cell.y]

func _biome_color(biome: String) -> Color:
	match biome:
		"water":
			return Color(0.20, 0.45, 0.85)
		"sand":
			return Color(0.85, 0.80, 0.50)
		"grass":
			return Color(0.30, 0.70, 0.30)
		"forest":
			return Color(0.10, 0.45, 0.15)
		"mountain":
			return Color(0.45, 0.45, 0.45)
		_:
			return Color.WHITE
