extends Node2D
class_name Human

var grid: WorldGrid
var grid_position: Vector2i = Vector2i.ZERO
var tile_size: int = 16

func setup(p_grid: WorldGrid, p_grid_position: Vector2i, p_tile_size: int) -> void:
	grid = p_grid
	grid_position = p_grid_position
	tile_size = p_tile_size
	_update_world_position()
	queue_redraw()

func tick_move(rng: RandomNumberGenerator) -> void:
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
		if grid.is_walkable(next):
			grid_position = next
			_update_world_position()
			break

func _update_world_position() -> void:
	position = Vector2((grid_position.x + 0.5) * tile_size, (grid_position.y + 0.5) * tile_size)

func _draw() -> void:
	draw_circle(Vector2.ZERO, tile_size * 0.28, Color(1.0, 0.92, 0.80))
	draw_circle(Vector2.ZERO, tile_size * 0.14, Color(0.20, 0.15, 0.12))
