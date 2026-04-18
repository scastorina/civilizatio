extends Node2D

const TILE_SIZE := 16
const WORLD_WIDTH := 96
const WORLD_HEIGHT := 54
const HUMAN_COUNT := 20
const MOVE_TICK_SECONDS := 0.35
const BIOMES: Array[String] = ["water", "sand", "grass", "forest", "mountain"]

var rng := RandomNumberGenerator.new()
var world_grid := WorldGrid.new(WORLD_WIDTH, WORLD_HEIGHT)
var humans: Array[Human] = []
var move_tick_accumulator := 0.0

var editor_enabled := false
var selected_biome_idx := 2

func _ready() -> void:
	rng.randomize()
	_regenerate_world()

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		_regenerate_world()

	if editor_enabled:
		return

	move_tick_accumulator += delta
	while move_tick_accumulator >= MOVE_TICK_SECONDS:
		move_tick_accumulator -= MOVE_TICK_SECONDS
		_move_humans()

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
	world_grid.generate()
	_spawn_humans()
	queue_redraw()

func _spawn_humans() -> void:
	for human in humans:
		human.queue_free()
	humans.clear()

	var walkable_cells := world_grid.get_all_walkable_cells()
	_shuffle_vector2i_array(walkable_cells)

	var spawn_count := mini(HUMAN_COUNT, walkable_cells.size())
	for i in range(spawn_count):
		var human := Human.new()
		human.setup(walkable_cells[i], TILE_SIZE)
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

func _draw() -> void:
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var biome := world_grid.get_biome(Vector2i(x, y))
			draw_rect(Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE), _biome_color(biome))

	draw_string(ThemeDB.fallback_font, Vector2(10, 18), "Enter = regenerar mundo", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(ThemeDB.fallback_font, Vector2(10, 36), "Humanos: %s (sin superposición)" % humans.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(ThemeDB.fallback_font, Vector2(10, 54), "Editor: %s (E)" % ("ON" if editor_enabled else "OFF"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(ThemeDB.fallback_font, Vector2(10, 72), "Bioma editor: %s (1-5)" % BIOMES[selected_biome_idx], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)

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
