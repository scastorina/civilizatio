extends Node2D

const TILE_SIZE := 16
const WORLD_WIDTH := 96
const WORLD_HEIGHT := 54
const INITIAL_HUMANS := 20
const MAX_HUMANS := 200
const MOVE_TICK_SECONDS := 0.35
const BIOMES: Array[String] = ["water", "sand", "grass", "forest", "mountain"]
const MAP_PRESETS: Array[String] = ["random", "earth_like", "continent"]
const TIME_SPEEDS: Array[float] = [0.0, 1.0, 2.0, 5.0, 10.0]
const SPECIES_LIBRARY: Array[Dictionary] = [
	{"name": "Humanos", "color": Color(1.0, 0.92, 0.80), "preferred": ["grass", "forest"]},
	{"name": "Elfos",   "color": Color(0.75, 0.95, 0.75), "preferred": ["forest", "grass"]},
	{"name": "Enanos",  "color": Color(0.82, 0.75, 0.62), "preferred": ["mountain", "forest"]},
	{"name": "Orcos",   "color": Color(0.65, 0.80, 0.55), "preferred": ["sand", "grass"]},
]

var rng := RandomNumberGenerator.new()
var world_grid := WorldGrid.new(WORLD_WIDTH, WORLD_HEIGHT)
var humans: Array[Human] = []
var move_tick_accumulator := 0.0
var _species_colors: Dictionary = {}

var current_speed_idx := 1
var current_map_idx := 0
var mouse_painting := false
var last_painted_cell := Vector2i(-1, -1)

var ui: GameUI

func _ready() -> void:
	rng.randomize()
	for sp: Dictionary in SPECIES_LIBRARY:
		_species_colors[sp["name"] as String] = sp["color"] as Color
	ui = GameUI.new()
	add_child(ui)
	ui.setup_species(SPECIES_LIBRARY)
	ui.time_speed_changed.connect(func(idx): current_speed_idx = idx)
	ui.map_type_changed.connect(func(idx): current_map_idx = idx)
	ui.regenerate_requested.connect(_regenerate_world)
	_regenerate_world()

func _process(delta: float) -> void:
	var speed := TIME_SPEEDS[current_speed_idx]
	if speed == 0.0:
		return
	move_tick_accumulator += delta * speed
	var ticked := false
	while move_tick_accumulator >= MOVE_TICK_SECONDS:
		move_tick_accumulator -= MOVE_TICK_SECONDS
		_move_humans()
		_update_evolution()
		ticked = true
	if ticked:
		queue_redraw()

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

	match ui.active_tab:
		"terrain":
			var biome: String = GameUI.BIOMES[ui.selected_biome]
			if (biome == "water" or biome == "mountain") and _has_human_in_cell(cell):
				return
			world_grid.set_biome(cell, biome)
			queue_redraw()
		"entities":
			if world_grid.is_walkable(cell) and not _has_human_in_cell(cell) and humans.size() < MAX_HUMANS:
				_spawn_human_at(cell, SPECIES_LIBRARY[ui.selected_species])
				queue_redraw()

func _regenerate_world() -> void:
	move_tick_accumulator = 0.0
	world_grid.generate(MAP_PRESETS[current_map_idx])
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
		var species: Dictionary = SPECIES_LIBRARY[i % SPECIES_LIBRARY.size()]
		_spawn_human_at(walkable[i], species)

func _spawn_human_at(cell: Vector2i, species: Dictionary) -> void:
	var preferred: Array[String] = []
	preferred.assign(species["preferred"])
	var human := Human.new()
	human.setup(cell, TILE_SIZE, species["name"], species["color"], preferred)
	world_grid.set_owner(cell, species["name"] as String)
	add_child(human)
	humans.append(human)

func _move_humans() -> void:
	var occupied := {}
	for human in humans:
		occupied[_cell_key(human.grid_position)] = true

	_shuffle_humans()
	for human in humans:
		occupied.erase(_cell_key(human.grid_position))
		var next := human.choose_next_cell(world_grid, rng, occupied)
		human.set_grid_position(next)
		world_grid.set_owner(next, human.species_name)
		occupied[_cell_key(next)] = true

func _update_evolution() -> void:
	for human in humans:
		human.update_evolution(world_grid.get_biome(human.grid_position))

func _draw() -> void:
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var cell := Vector2i(x, y)
			var c := _biome_color(world_grid.get_biome(cell))
			var owner := world_grid.get_owner(cell)
			if owner != "":
				var sc: Color = _species_colors.get(owner, Color.WHITE)
				c = c.lerp(sc, 0.30)
			draw_rect(Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE), c)

	# Species stats overlay (top-left)
	var stats := _species_stats()
	var overlay_h := 20.0 + stats.size() * 18.0
	draw_rect(Rect2(0, 0, 230, overlay_h), Color(0.0, 0.0, 0.0, 0.55))
	var oy := 16.0
	for line in stats:
		draw_string(ThemeDB.fallback_font, Vector2(8, oy), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		oy += 18.0

func _species_stats() -> Array[String]:
	var result: Array[String] = []
	var stats: Dictionary = {}
	for human in humans:
		if not stats.has(human.species_name):
			stats[human.species_name] = {"count": 0, "evo": 0.0}
		stats[human.species_name]["count"] += 1
		stats[human.species_name]["evo"] += human.evolution_score
	for sp_name: String in stats.keys():
		var count: int = stats[sp_name]["count"]
		var evo: float = stats[sp_name]["evo"] / maxf(float(count), 1.0)
		result.append("%s: %d  evo:%.1f" % [sp_name, count, evo])
	if result.is_empty():
		result.append("Sin entidades — usa tab Entidades")
	return result

func _mouse_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE_SIZE)), int(floor(pos.y / TILE_SIZE)))

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
