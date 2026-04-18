extends Node2D

const TILE_SIZE := 16
const WORLD_WIDTH := 96
const WORLD_HEIGHT := 54
const INITIAL_HUMANS := 20
const MAX_HUMANS := 150
const MOVE_TICK_SECONDS := 0.35
const BIOMES: Array[String] = ["water", "sand", "grass", "forest", "mountain"]

var rng := RandomNumberGenerator.new()
var world_grid := WorldGrid.new(WORLD_WIDTH, WORLD_HEIGHT)
var humans: Array[Human] = []
var move_tick_accumulator := 0.0

var time_speed := 1
var map_type := "random"
var current_tool := "paint"
var selected_biome_idx := 2
var mouse_painting := false
var last_painted_cell := Vector2i(-1, -1)

var ui: GameUI

func _ready() -> void:
	rng.randomize()
	ui = GameUI.new()
	add_child(ui)
	ui.biome_selected.connect(func(idx): selected_biome_idx = idx)
	ui.tool_changed.connect(func(tool): current_tool = tool)
	ui.time_speed_changed.connect(func(speed): time_speed = speed)
	ui.map_type_changed.connect(_on_map_type_changed)
	ui.regenerate_requested.connect(_regenerate_world)
	_regenerate_world()

func _process(delta: float) -> void:
	if time_speed == 0:
		return
	move_tick_accumulator += delta * time_speed
	while move_tick_accumulator >= MOVE_TICK_SECONDS:
		move_tick_accumulator -= MOVE_TICK_SECONDS
		_tick_world()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_regenerate_world()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_painting = event.pressed
		if event.pressed:
			last_painted_cell = Vector2i(-1, -1)
			_apply_tool_at(event.position)
		else:
			last_painted_cell = Vector2i(-1, -1)

	if event is InputEventMouseMotion and mouse_painting:
		_apply_tool_at(event.position)

func _apply_tool_at(pos: Vector2) -> void:
	var cell := _mouse_to_cell(pos)
	if cell == last_painted_cell:
		return
	last_painted_cell = cell
	if not world_grid.is_in_bounds(cell):
		return

	match current_tool:
		"paint":
			var biome: String = BIOMES[selected_biome_idx]
			if (biome == "water" or biome == "mountain") and _has_human_in_cell(cell):
				return
			world_grid.set_biome(cell, biome)
			queue_redraw()
		"spawn":
			if world_grid.is_walkable(cell) and not _has_human_in_cell(cell) and humans.size() < MAX_HUMANS:
				_spawn_human_at(cell)
				queue_redraw()

func _on_map_type_changed(map: String) -> void:
	map_type = map

func _regenerate_world() -> void:
	move_tick_accumulator = 0.0
	match map_type:
		"continents":
			world_grid.generate_continents()
		"world":
			world_grid.generate_world()
		_:
			world_grid.generate()
	_spawn_initial_humans()
	queue_redraw()

func _spawn_initial_humans() -> void:
	for human in humans:
		human.queue_free()
	humans.clear()

	var walkable := world_grid.get_all_walkable_cells()
	_shuffle_cells(walkable)

	var count := mini(INITIAL_HUMANS, walkable.size())
	for i in range(count):
		_spawn_human_at(walkable[i])

func _spawn_human_at(cell: Vector2i) -> void:
	var human := Human.new()
	human.setup(cell, TILE_SIZE)
	add_child(human)
	humans.append(human)

func _tick_world() -> void:
	_move_humans()
	_age_and_reproduce()
	queue_redraw()

func _move_humans() -> void:
	var occupied := {}
	for human in humans:
		occupied[_cell_key(human.grid_position)] = true

	_shuffle_humans()
	for human in humans:
		occupied.erase(_cell_key(human.grid_position))
		var next := human.choose_next_cell(world_grid, rng, occupied)
		human.set_grid_position(next)
		occupied[_cell_key(next)] = true

func _age_and_reproduce() -> void:
	var to_remove: Array[Human] = []
	var new_children: Array[Human] = []

	var occupied := {}
	for human in humans:
		occupied[_cell_key(human.grid_position)] = true

	for human in humans:
		if not human.tick_age():
			to_remove.append(human)
			continue
		if human.can_reproduce() and humans.size() + new_children.size() < MAX_HUMANS:
			var child_cell := _find_adjacent_empty(human.grid_position, occupied)
			if child_cell != Vector2i(-1, -1):
				var child := Human.new()
				child.setup_child(child_cell, TILE_SIZE, human, rng)
				new_children.append(child)
				occupied[_cell_key(child_cell)] = true
				human.on_reproduced()

	for dead in to_remove:
		humans.erase(dead)
		dead.queue_free()

	for child in new_children:
		add_child(child)
		humans.append(child)

func _find_adjacent_empty(pos: Vector2i, occupied: Dictionary) -> Vector2i:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for dir in dirs:
		var cell := pos + dir
		if world_grid.is_walkable(cell) and not occupied.has(_cell_key(cell)):
			return cell
	return Vector2i(-1, -1)

func _draw() -> void:
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			draw_rect(
				Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE),
				_biome_color(world_grid.get_biome(Vector2i(x, y)))
			)

	var max_gen := 0
	for h in humans:
		if h.generation > max_gen:
			max_gen = h.generation

	var spd_text := "PAUSA" if time_speed == 0 else "%dx" % time_speed
	draw_rect(Rect2(0, 0, 220, 64), Color(0.0, 0.0, 0.0, 0.55))
	draw_string(ThemeDB.fallback_font, Vector2(8, 18),
		"Poblacion: %d / %d" % [humans.size(), MAX_HUMANS], HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(ThemeDB.fallback_font, Vector2(8, 36),
		"Generacion max: %d" % max_gen, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(ThemeDB.fallback_font, Vector2(8, 54),
		"Velocidad: %s  Mapa: %s" % [spd_text, map_type], HORIZONTAL_ALIGNMENT_LEFT, -1, 13)

func _mouse_to_cell(mouse_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(mouse_pos.x / TILE_SIZE)), int(floor(mouse_pos.y / TILE_SIZE)))

func _has_human_in_cell(cell: Vector2i) -> bool:
	for human in humans:
		if human.grid_position == cell:
			return true
	return false

func _shuffle_cells(items: Array[Vector2i]) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := items[i]; items[i] = items[j]; items[j] = tmp

func _shuffle_humans() -> void:
	for i in range(humans.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := humans[i]; humans[i] = humans[j]; humans[j] = tmp

func _cell_key(cell: Vector2i) -> String:
	return "%s:%s" % [cell.x, cell.y]

func _biome_color(biome: String) -> Color:
	match biome:
		"water":    return Color(0.20, 0.45, 0.85)
		"sand":     return Color(0.85, 0.80, 0.50)
		"grass":    return Color(0.30, 0.70, 0.30)
		"forest":   return Color(0.10, 0.45, 0.15)
		"mountain": return Color(0.45, 0.45, 0.45)
		_:          return Color.WHITE
