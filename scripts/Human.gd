extends Node2D
class_name Human

var grid_position: Vector2i = Vector2i.ZERO
var tile_size: int = 16
var species_name: String = "Humanos"
var species_color: Color = Color(1.0, 0.92, 0.80)
var preferred_biomes: Array[String] = []
var evolution_score := 0.0
var age_ticks := 0
var combat_bonus := 1.0
var defense_bonus := 1.0
var evo_rate := 1.0
var battles_won := 0
var is_hero := false
var hero_name := ""

func setup(p_grid_position: Vector2i, p_tile_size: int, p_species_name: String, p_species_color: Color, p_preferred_biomes: Array[String], p_combat: float = 1.0, p_defense: float = 1.0, p_evo_rate: float = 1.0) -> void:
	grid_position = p_grid_position
	tile_size = p_tile_size
	species_name = p_species_name
	species_color = p_species_color
	preferred_biomes = p_preferred_biomes.duplicate()
	combat_bonus = p_combat
	defense_bonus = p_defense
	evo_rate = p_evo_rate
	evolution_score = 0.0
	age_ticks = 0
	_update_world_position()
	queue_redraw()

func is_dead() -> bool:
	return evolution_score < -20.0

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
		if dir != Vector2i.ZERO and grid.get_owner(next) == species_name:
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
		evolution_score += 0.03 * evo_rate
	else:
		evolution_score -= 0.01
	evolution_score = clamp(evolution_score, -50.0, 200.0)

func set_grid_position(next: Vector2i) -> void:
	grid_position = next
	_update_world_position()

func _update_world_position() -> void:
	position = Vector2((grid_position.x + 0.5) * tile_size, (grid_position.y + 0.5) * tile_size)

func _draw() -> void:
	var health := clampf((evolution_score + 20.0) / 40.0, 0.0, 1.0)
	var c := species_color.lerp(Color(0.4, 0.08, 0.08), 1.0 - health)
	var dk := c.darkened(0.45)
	var s := tile_size * 0.30
	match species_name:
		"Humanos":  _draw_human(c, dk, s)
		"Elfos":    _draw_elf(c, dk, s)
		"Enanos":   _draw_dwarf(c, dk, s)
		"Orcos":    _draw_orc(c, dk, s)
		_:
			draw_circle(Vector2.ZERO, s, c)
	if is_hero:
		_draw_hero_marker(s)

func _draw_hero_marker(s: float) -> void:
	var gold := Color(1.0, 0.85, 0.20)
	var tip := s * 1.55
	var pts := PackedVector2Array()
	for i in range(5):
		var outer_a := deg_to_rad(-90.0 + i * 72.0)
		var inner_a := deg_to_rad(-90.0 + i * 72.0 + 36.0)
		pts.append(Vector2(cos(outer_a), sin(outer_a)) * s * 0.55 + Vector2(0, -tip))
		pts.append(Vector2(cos(inner_a), sin(inner_a)) * s * 0.22 + Vector2(0, -tip))
	draw_colored_polygon(pts, gold)

func _draw_human(c: Color, dk: Color, s: float) -> void:
	draw_circle(Vector2(0, -s * 0.62), s * 0.42, c)
	draw_circle(Vector2(0, -s * 0.62), s * 0.42, dk, false, 1.0)
	var body := PackedVector2Array([
		Vector2(-s*0.38, -s*0.18), Vector2(s*0.38, -s*0.18),
		Vector2(s*0.30, s*0.62),   Vector2(-s*0.30, s*0.62),
	])
	draw_colored_polygon(body, c)
	draw_polyline(body, dk, 1.0)

func _draw_elf(c: Color, dk: Color, s: float) -> void:
	draw_circle(Vector2(0, -s * 0.62), s * 0.38, c)
	draw_circle(Vector2(0, -s * 0.62), s * 0.38, dk, false, 1.0)
	draw_line(Vector2(-s*0.34, -s*0.88), Vector2(-s*0.54, -s*1.18), c, 1.5)
	draw_line(Vector2(s*0.34, -s*0.88),  Vector2(s*0.54, -s*1.18),  c, 1.5)
	var body := PackedVector2Array([
		Vector2(-s*0.28, -s*0.22), Vector2(s*0.28, -s*0.22),
		Vector2(s*0.20, s*0.60),   Vector2(-s*0.20, s*0.60),
	])
	draw_colored_polygon(body, c)
	draw_polyline(body, dk, 1.0)

func _draw_dwarf(c: Color, dk: Color, s: float) -> void:
	draw_circle(Vector2(0, -s * 0.48), s * 0.45, c)
	draw_circle(Vector2(0, -s * 0.48), s * 0.45, dk, false, 1.0)
	draw_circle(Vector2(0, -s * 0.05), s * 0.30, c.lightened(0.25))
	var body := PackedVector2Array([
		Vector2(-s*0.48, -s*0.10), Vector2(s*0.48, -s*0.10),
		Vector2(s*0.44, s*0.52),   Vector2(-s*0.44, s*0.52),
	])
	draw_colored_polygon(body, c)
	draw_polyline(body, dk, 1.0)

func _draw_orc(c: Color, dk: Color, s: float) -> void:
	draw_circle(Vector2(0, -s * 0.52), s * 0.50, c)
	draw_circle(Vector2(0, -s * 0.52), s * 0.50, dk, false, 1.0)
	draw_line(Vector2(-s*0.22, -s*0.18), Vector2(-s*0.28, s*0.08), Color(0.95, 0.95, 0.85), 1.5)
	draw_line(Vector2(s*0.22, -s*0.18),  Vector2(s*0.28, s*0.08),  Color(0.95, 0.95, 0.85), 1.5)
	var body := PackedVector2Array([
		Vector2(-s*0.46, -s*0.10), Vector2(s*0.46, -s*0.10),
		Vector2(s*0.40, s*0.58),   Vector2(-s*0.40, s*0.58),
	])
	draw_colored_polygon(body, c)
	draw_polyline(body, dk, 1.0)
