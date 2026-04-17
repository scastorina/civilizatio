extends Node2D

const TILE_SIZE := 16
const WORLD_WIDTH := 96
const WORLD_HEIGHT := 54

var rng := RandomNumberGenerator.new()
var world: Array = []

func _ready() -> void:
	rng.randomize()
	_generate_world()
	queue_redraw()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		_generate_world()
		queue_redraw()

func _generate_world() -> void:
	world.clear()
	for y in range(WORLD_HEIGHT):
		var row: Array = []
		for x in range(WORLD_WIDTH):
			var value := rng.randf()
			if value < 0.18:
				row.append("water")
			elif value < 0.24:
				row.append("sand")
			elif value < 0.72:
				row.append("grass")
			elif value < 0.88:
				row.append("forest")
			else:
				row.append("mountain")
		world.append(row)

func _draw() -> void:
	for y in range(WORLD_HEIGHT):
		for x in range(WORLD_WIDTH):
			var biome: String = world[y][x]
			draw_rect(Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE), _biome_color(biome))
	draw_string(ThemeDB.fallback_font, Vector2(10, 18), "Enter = regenerar mundo", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)

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
