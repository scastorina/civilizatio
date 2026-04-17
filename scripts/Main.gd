extends Node2D

const TILE_SIZE := 16
const WORLD_WIDTH := 96
const WORLD_HEIGHT := 54
const HUMAN_COUNT := 20
const MOVE_TICK_SECONDS := 0.35

var rng := RandomNumberGenerator.new()
var world_grid := WorldGrid.new(WORLD_WIDTH, WORLD_HEIGHT)
var humans: Array[Human] = []
var move_tick_accumulator := 0.0

func _ready() -> void:
	rng.randomize()
	_regenerate_world()

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		_regenerate_world()

	move_tick_accumulator += delta
	while move_tick_accumulator >= MOVE_TICK_SECONDS:
		move_tick_accumulator -= MOVE_TICK_SECONDS
		_move_humans()

func _regenerate_world() -> void:
	world_grid.generate()
	_spawn_humans()
	queue_redraw()

func _spawn_humans() -> void:
	for human in humans:
		human.queue_free()
	humans.clear()

	var occupied := {}
	for _i in range(HUMAN_COUNT):
		var spawn := world_grid.get_random_walkable_cell()
		if not world_grid.is_walkable(spawn):
			continue

		var key := "%s:%s" % [spawn.x, spawn.y]
		if occupied.has(key):
			continue
		occupied[key] = true

		var human := Human.new()
		human.setup(world_grid, spawn, TILE_SIZE)
		add_child(human)
		humans.append(human)

func _move_humans() -> void:
	for human in humans:
		human.tick_move(rng)

func _draw() -> void:
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var biome := world_grid.get_biome(Vector2i(x, y))
			draw_rect(Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE), _biome_color(biome))

	draw_string(ThemeDB.fallback_font, Vector2(10, 18), "Enter = regenerar mundo", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(ThemeDB.fallback_font, Vector2(10, 36), "Humanos: %s (mueven por ticks)" % humans.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)

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
