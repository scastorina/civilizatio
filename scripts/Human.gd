extends Node2D
class_name Human

var grid_position: Vector2i = Vector2i.ZERO
var tile_size: int = 16

func setup(p_grid_position: Vector2i, p_tile_size: int) -> void:
	grid_position = p_grid_position
	tile_size = p_tile_size
	_update_world_position()
	queue_redraw()

func choose_next_cell(grid: WorldGrid, rng: RandomNumberGenerator, occupied: Dictionary) -> Vector2i:
	var directions: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i.ZERO,
	]
	for i in range(directions.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp: Vector2i = directions[i]
		directions[i] = directions[j]
		directions[j] = temp

	for dir in directions:
		var next := grid_position + dir
		if not grid.is_walkable(next):
			continue
		var key := "%s:%s" % [next.x, next.y]
		if occupied.has(key):
			continue
		return next
	return grid_position

func set_grid_position(next: Vector2i) -> void:
	grid_position = next
	_update_world_position()

func _update_world_position() -> void:
	position = Vector2((grid_position.x + 0.5) * tile_size, (grid_position.y + 0.5) * tile_size)

func _draw() -> void:
	draw_circle(Vector2.ZERO, tile_size * 0.28, Color(1.0, 0.92, 0.80))
	draw_circle(Vector2.ZERO, tile_size * 0.14, Color(0.20, 0.15, 0.12))
