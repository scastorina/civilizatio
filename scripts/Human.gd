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
var infected := false
var on_fire := false
var religion := ""

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
	if infected:
		evolution_score -= 0.08
	if on_fire:
		evolution_score -= 0.20
	evolution_score = clamp(evolution_score, -50.0, 200.0)

func set_grid_position(next: Vector2i) -> void:
	grid_position = next
	_update_world_position()

func _update_world_position() -> void:
	position = Vector2((grid_position.x + 0.5) * tile_size, (grid_position.y + 0.5) * tile_size)

func _draw() -> void:
	var health := clampf((evolution_score + 20.0) / 40.0, 0.0, 1.0)
	var c := species_color.lerp(Color(0.4, 0.08, 0.08), 1.0 - health)
	if infected:
		c = c.lerp(Color(0.55, 0.90, 0.20), 0.55)
	if on_fire:
		c = c.lerp(Color(1.0, 0.35, 0.0), 0.70)
	var dk := c.darkened(0.50)
	var s := float(tile_size) * 0.44
	# Drop shadow
	draw_circle(Vector2(s * 0.10, s * 0.20), s * 0.54, Color(0.0, 0.0, 0.0, 0.24))
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
	var gold := Color(1.0, 0.88, 0.10)
	var tip  := s * 1.70
	var pts  := PackedVector2Array()
	for i in range(5):
		var oa := deg_to_rad(-90.0 + i * 72.0)
		var ia := deg_to_rad(-90.0 + i * 72.0 + 36.0)
		pts.append(Vector2(cos(oa), sin(oa)) * s * 0.60 + Vector2(0.0, -tip))
		pts.append(Vector2(cos(ia), sin(ia)) * s * 0.24 + Vector2(0.0, -tip))
	draw_colored_polygon(pts, gold)
	draw_polyline(pts, Color(0.85, 0.65, 0.0), 1.0)

# ── Humanos ─────────────────────────────────────────────────────────────────
# Balanced meeple: round head, trapezoid torso, visible eyes and smile
func _draw_human(c: Color, dk: Color, s: float) -> void:
	# Torso
	draw_colored_polygon(PackedVector2Array([
		Vector2(-s*0.36, -s*0.16), Vector2(s*0.36, -s*0.16),
		Vector2(s*0.28,  s*0.62),  Vector2(-s*0.28, s*0.62),
	]), c)
	draw_polyline(PackedVector2Array([
		Vector2(-s*0.36, -s*0.16), Vector2(s*0.36, -s*0.16),
		Vector2(s*0.28,  s*0.62),  Vector2(-s*0.28, s*0.62),
		Vector2(-s*0.36, -s*0.16),
	]), dk, 1.0)
	# Head
	var hc := Vector2(0.0, -s*0.60)
	draw_circle(hc, s*0.42, c)
	draw_circle(hc, s*0.42, dk, false, 1.0)
	# Eyes (white sclera + dark pupil)
	draw_circle(hc + Vector2(-s*0.14, -s*0.06), s*0.13, Color(1.0, 1.0, 1.0, 0.92))
	draw_circle(hc + Vector2( s*0.14, -s*0.06), s*0.13, Color(1.0, 1.0, 1.0, 0.92))
	draw_circle(hc + Vector2(-s*0.14, -s*0.06), s*0.08, dk)
	draw_circle(hc + Vector2( s*0.14, -s*0.06), s*0.08, dk)
	# Smile
	draw_arc(hc + Vector2(0.0, s*0.08), s*0.16, deg_to_rad(20.0), deg_to_rad(160.0), 6, dk, 1.0)

# ── Elfos ────────────────────────────────────────────────────────────────────
# Slim and tall; large filled triangular ears are the key identifier
func _draw_elf(c: Color, dk: Color, s: float) -> void:
	# Slim torso
	draw_colored_polygon(PackedVector2Array([
		Vector2(-s*0.24, -s*0.18), Vector2(s*0.24, -s*0.18),
		Vector2(s*0.17,  s*0.62),  Vector2(-s*0.17, s*0.62),
	]), c)
	draw_polyline(PackedVector2Array([
		Vector2(-s*0.24, -s*0.18), Vector2(s*0.24, -s*0.18),
		Vector2(s*0.17,  s*0.62),  Vector2(-s*0.17, s*0.62),
		Vector2(-s*0.24, -s*0.18),
	]), dk, 1.0)
	# Head
	var hc := Vector2(0.0, -s*0.64)
	draw_circle(hc, s*0.37, c)
	draw_circle(hc, s*0.37, dk, false, 1.0)
	# Big pointed ears (filled triangles)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-s*0.37, -s*0.76), Vector2(-s*0.37, -s*0.52),
		Vector2(-s*0.76, -s*0.88),
	]), c)
	draw_polyline(PackedVector2Array([
		Vector2(-s*0.37, -s*0.76), Vector2(-s*0.37, -s*0.52),
		Vector2(-s*0.76, -s*0.88), Vector2(-s*0.37, -s*0.76),
	]), dk, 1.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(s*0.37, -s*0.76), Vector2(s*0.37, -s*0.52),
		Vector2(s*0.76, -s*0.88),
	]), c)
	draw_polyline(PackedVector2Array([
		Vector2(s*0.37, -s*0.76), Vector2(s*0.37, -s*0.52),
		Vector2(s*0.76, -s*0.88), Vector2(s*0.37, -s*0.76),
	]), dk, 1.0)
	# Almond eyes (white sclera + dark pupil)
	draw_circle(hc + Vector2(-s*0.13, -s*0.04), s*0.12, Color(1.0, 1.0, 1.0, 0.88))
	draw_circle(hc + Vector2( s*0.13, -s*0.04), s*0.12, Color(1.0, 1.0, 1.0, 0.88))
	draw_circle(hc + Vector2(-s*0.13, -s*0.04), s*0.07, dk)
	draw_circle(hc + Vector2( s*0.13, -s*0.04), s*0.07, dk)

# ── Enanos ────────────────────────────────────────────────────────────────────
# Short and wide; iron helmet + big forked beard
func _draw_dwarf(c: Color, dk: Color, s: float) -> void:
	# Wide squat torso
	draw_colored_polygon(PackedVector2Array([
		Vector2(-s*0.52, -s*0.10), Vector2(s*0.52, -s*0.10),
		Vector2(s*0.48,  s*0.52),  Vector2(-s*0.48, s*0.52),
	]), c)
	draw_polyline(PackedVector2Array([
		Vector2(-s*0.52, -s*0.10), Vector2(s*0.52, -s*0.10),
		Vector2(s*0.48,  s*0.52),  Vector2(-s*0.48, s*0.52),
		Vector2(-s*0.52, -s*0.10),
	]), dk, 1.0)
	# Head
	var hc := Vector2(0.0, -s*0.46)
	draw_circle(hc, s*0.42, c)
	draw_circle(hc, s*0.42, dk, false, 1.0)
	# Iron helmet (dome + brim)
	var helm_c := c.darkened(0.35)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-s*0.44, -s*0.48), Vector2(s*0.44, -s*0.48),
		Vector2(s*0.34,  -s*0.90), Vector2(-s*0.34, -s*0.90),
	]), helm_c)
	draw_rect(Rect2(-s*0.52, -s*0.50, s*1.04, s*0.14), helm_c.darkened(0.2))
	# Beard (large forked triangle, lightened)
	var beard_c := c.lightened(0.30)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-s*0.40, -s*0.08), Vector2(s*0.40, -s*0.08),
		Vector2(s*0.34,  s*0.46),  Vector2(-s*0.34, s*0.46),
	]), beard_c)
	# Beard fork lines
	draw_line(Vector2(0.0, s*0.15), Vector2(0.0, s*0.46), dk, 1.0)
	# Eyes under helmet (small, determined — white sclera + dark pupil)
	draw_circle(hc + Vector2(-s*0.15, -s*0.02), s*0.12, Color(1.0, 1.0, 1.0, 0.90))
	draw_circle(hc + Vector2( s*0.15, -s*0.02), s*0.12, Color(1.0, 1.0, 1.0, 0.90))
	draw_circle(hc + Vector2(-s*0.15, -s*0.02), s*0.08, dk)
	draw_circle(hc + Vector2( s*0.15, -s*0.02), s*0.08, dk)

# ── Orcos ─────────────────────────────────────────────────────────────────────
# Big head, angry V-brow, prominent upward ivory tusks
func _draw_orc(c: Color, dk: Color, s: float) -> void:
	# Wide brutish torso
	draw_colored_polygon(PackedVector2Array([
		Vector2(-s*0.52, -s*0.10), Vector2(s*0.52, -s*0.10),
		Vector2(s*0.46,  s*0.60),  Vector2(-s*0.46, s*0.60),
	]), c)
	draw_polyline(PackedVector2Array([
		Vector2(-s*0.52, -s*0.10), Vector2(s*0.52, -s*0.10),
		Vector2(s*0.46,  s*0.60),  Vector2(-s*0.46, s*0.60),
		Vector2(-s*0.52, -s*0.10),
	]), dk, 1.5)
	# Big head
	var hc := Vector2(0.0, -s*0.54)
	draw_circle(hc, s*0.52, c)
	draw_circle(hc, s*0.52, dk, false, 1.5)
	# Angry V-shaped brows
	draw_line(hc + Vector2(-s*0.44, -s*0.16), hc + Vector2(-s*0.10, -s*0.28), dk, 2.5)
	draw_line(hc + Vector2( s*0.44, -s*0.16), hc + Vector2( s*0.10, -s*0.28), dk, 2.5)
	# Small mean eyes (red-tinted sclera + dark pupil)
	draw_circle(hc + Vector2(-s*0.18, -s*0.08), s*0.14, Color(1.0, 0.82, 0.78, 0.88))
	draw_circle(hc + Vector2( s*0.18, -s*0.08), s*0.14, Color(1.0, 0.82, 0.78, 0.88))
	draw_circle(hc + Vector2(-s*0.18, -s*0.08), s*0.09, dk)
	draw_circle(hc + Vector2( s*0.18, -s*0.08), s*0.09, dk)
	# Ivory tusks (upward from jaw)
	var ivory := Color(0.96, 0.92, 0.78)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-s*0.12, -s*0.08), Vector2(-s*0.26, -s*0.08),
		Vector2(-s*0.22,  s*0.20),
	]), ivory)
	draw_colored_polygon(PackedVector2Array([
		Vector2( s*0.12, -s*0.08), Vector2( s*0.26, -s*0.08),
		Vector2( s*0.22,  s*0.20),
	]), ivory)
	draw_polyline(PackedVector2Array([
		Vector2(-s*0.12, -s*0.08), Vector2(-s*0.26, -s*0.08),
		Vector2(-s*0.22,  s*0.20), Vector2(-s*0.12, -s*0.08),
	]), dk, 0.8)
	draw_polyline(PackedVector2Array([
		Vector2( s*0.12, -s*0.08), Vector2( s*0.26, -s*0.08),
		Vector2( s*0.22,  s*0.20), Vector2( s*0.12, -s*0.08),
	]), dk, 0.8)
