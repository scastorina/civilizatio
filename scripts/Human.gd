extends Node2D
class_name Human

var grid_position: Vector2i = Vector2i.ZERO
var tile_size: int = 16
var species_name: String = "Humanos"
var species_color: Color = Color(1.0, 0.92, 0.80)
var preferred_biomes: Array[String] = []
var evolution_score := 0.0
var age_ticks := 0

func setup(p_grid_position: Vector2i, p_tile_size: int, p_species_name: String, p_species_color: Color, p_preferred_biomes: Array[String]) -> void:
	grid_position = p_grid_position
	tile_size = p_tile_size
	species_name = p_species_name
	species_color = p_species_color
	preferred_biomes = p_preferred_biomes.duplicate()
	evolution_score = 0.0
	age_ticks = 0
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

	var best_cells: Array[Vector2i] = []
	var best_score := -999
	for dir in directions:
		var next := grid_position + dir
		if not grid.is_walkable(next):
			continue
		var key := "%s:%s" % [next.x, next.y]
		if occupied.has(key):
			continue

		var score := 1
		var biome := grid.get_biome(next)
		if preferred_biomes.has(biome):
			score += 2
		if grid.get_owner(next) == species_name:
			score += 1
			match grid.get_structure(next):
				"village": score += 1
				"town":    score += 2
		if score > best_score:
			best_score = score
			best_cells.clear()
			best_cells.append(next)
		elif score == best_score:
			best_cells.append(next)

	if best_cells.is_empty():
		return grid_position
	return best_cells[rng.randi_range(0, best_cells.size() - 1)]

func update_evolution(current_biome: String) -> void:
	age_ticks += 1
	if preferred_biomes.has(current_biome):
		evolution_score += 0.03
	else:
		evolution_score -= 0.01
	evolution_score = clamp(evolution_score, -50.0, 200.0)

func set_grid_position(next: Vector2i) -> void:
	grid_position = next
	_update_world_position()

func _update_world_position() -> void:
	position = Vector2((grid_position.x + 0.5) * tile_size, (grid_position.y + 0.5) * tile_size)

func _draw() -> void:
	draw_circle(Vector2.ZERO, tile_size * 0.28, species_color)
	draw_circle(Vector2.ZERO, tile_size * 0.14, Color(0.20, 0.15, 0.12))
