extends Node2D
class_name Human

var grid_position: Vector2i = Vector2i.ZERO
var tile_size: int = 16

var age := 0
var max_age := 200
var generation := 0
var hue := 0.0
var reproduce_cooldown := 0
var reproduce_every := 80

func setup(p_pos: Vector2i, p_tile_size: int) -> void:
	grid_position = p_pos
	tile_size = p_tile_size
	max_age = 150 + randi_range(0, 100)
	reproduce_every = 60 + randi_range(0, 40)
	hue = randf()
	_sync_position()
	queue_redraw()

func setup_child(p_pos: Vector2i, p_tile_size: int, parent: Human, rng: RandomNumberGenerator) -> void:
	grid_position = p_pos
	tile_size = p_tile_size
	generation = parent.generation + 1
	max_age = clampi(parent.max_age + rng.randi_range(-20, 20), 50, 400)
	reproduce_every = clampi(parent.reproduce_every + rng.randi_range(-10, 10), 20, 200)
	hue = fmod(parent.hue + rng.randf_range(-0.04, 0.04) + 1.0, 1.0)
	_sync_position()
	queue_redraw()

func tick_age() -> bool:
	age += 1
	if reproduce_cooldown > 0:
		reproduce_cooldown -= 1
	return age < max_age

func can_reproduce() -> bool:
	return reproduce_cooldown <= 0

func on_reproduced() -> void:
	reproduce_cooldown = reproduce_every

func choose_next_cell(grid: WorldGrid, rng: RandomNumberGenerator, occupied: Dictionary) -> Vector2i:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i.ZERO,
	]
	for i in range(dirs.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := dirs[i]; dirs[i] = dirs[j]; dirs[j] = tmp

	for dir in dirs:
		var next := grid_position + dir
		if not grid.is_walkable(next):
			continue
		if occupied.has("%s:%s" % [next.x, next.y]):
			continue
		return next
	return grid_position

func set_grid_position(pos: Vector2i) -> void:
	grid_position = pos
	_sync_position()

func _sync_position() -> void:
	position = Vector2((grid_position.x + 0.5) * tile_size, (grid_position.y + 0.5) * tile_size)

func _draw() -> void:
	var life_ratio := 1.0 - float(age) / float(max_age)
	var gen_t := minf(float(generation) / 20.0, 1.0)
	var sat := lerpf(0.25, 0.65, gen_t)
	var val := lerpf(0.55, 1.0, life_ratio)
	var radius := tile_size * lerpf(0.24, 0.30, gen_t)
	var body := Color.from_hsv(hue, sat, val)
	var inner := Color.from_hsv(hue, minf(sat + 0.3, 1.0), val * 0.35)
	draw_circle(Vector2.ZERO, radius, body)
	draw_circle(Vector2.ZERO, radius * 0.5, inner)
