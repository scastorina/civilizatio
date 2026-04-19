extends RefCounted
class_name WorldGrid

var width: int
var height: int

var _rng := RandomNumberGenerator.new()
var _tiles: Array = []
var _owners: Array = []
var _presence: Array = []
var _structures: Array = []
var _fortifications: Array = []
var _improvements: Array = []

func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	_rng.randomize()

func generate(preset: String = "random") -> void:
	_clear_owners()
	match preset:
		"earth_like":
			_generate_earth_like()
		"continent":
			_generate_continent()
		_:
			_generate_random()

func _clear_owners() -> void:
	_owners.clear()
	_presence.clear()
	_structures.clear()
	_fortifications.clear()
	_improvements.clear()
	for _y in range(height):
		var orow: Array = []
		var prow: Array = []
		var srow: Array = []
		var frow: Array = []
		var irow: Array = []
		for _x in range(width):
			orow.append("")
			prow.append(0)
			srow.append("")
			frow.append(0)
			irow.append("")
		_owners.append(orow)
		_presence.append(prow)
		_structures.append(srow)
		_fortifications.append(frow)
		_improvements.append(irow)

func get_owner(cell: Vector2i) -> String:
	if not is_in_bounds(cell) or cell.y >= _owners.size():
		return ""
	var row: Array = _owners[cell.y]
	if cell.x >= row.size():
		return ""
	return row[cell.x]

func set_owner(cell: Vector2i, species: String) -> void:
	if not is_in_bounds(cell) or cell.y >= _owners.size():
		return
	var row: Array = _owners[cell.y]
	if cell.x >= row.size():
		return
	if row[cell.x] != species:
		row[cell.x] = species
		_owners[cell.y] = row
		if cell.y < _presence.size() and cell.x < (_presence[cell.y] as Array).size():
			_presence[cell.y][cell.x] = 0
		if cell.y < _structures.size() and cell.x < (_structures[cell.y] as Array).size():
			_structures[cell.y][cell.x] = ""
		if cell.y < _fortifications.size() and cell.x < (_fortifications[cell.y] as Array).size():
			_fortifications[cell.y][cell.x] = 0
		if cell.y < _improvements.size() and cell.x < (_improvements[cell.y] as Array).size():
			_improvements[cell.y][cell.x] = ""

func tick_presence(cell: Vector2i, species: String) -> void:
	if not is_in_bounds(cell) or cell.y >= _owners.size():
		return
	if (_owners[cell.y] as Array)[cell.x] != species:
		return
	_presence[cell.y][cell.x] += 1
	var p: int = _presence[cell.y][cell.x]
	if p >= 500:
		_structures[cell.y][cell.x] = "town"
	elif p >= 150:
		_structures[cell.y][cell.x] = "village"
	elif p >= 40:
		_structures[cell.y][cell.x] = "camp"

func get_structure(cell: Vector2i) -> String:
	if not is_in_bounds(cell) or cell.y >= _structures.size():
		return ""
	var row: Array = _structures[cell.y]
	if cell.x >= row.size():
		return ""
	return row[cell.x]

func set_structure(cell: Vector2i, structure: String) -> void:
	if not is_in_bounds(cell) or cell.y >= _structures.size():
		return
	var row: Array = _structures[cell.y]
	if cell.x >= row.size():
		return
	_structures[cell.y][cell.x] = structure

func get_fortification(cell: Vector2i) -> int:
	if not is_in_bounds(cell) or cell.y >= _fortifications.size():
		return 0
	var row: Array = _fortifications[cell.y]
	if cell.x >= row.size():
		return 0
	return row[cell.x] as int

func set_fortification(cell: Vector2i, level: int) -> void:
	if not is_in_bounds(cell) or cell.y >= _fortifications.size():
		return
	var row: Array = _fortifications[cell.y]
	if cell.x >= row.size():
		return
	_fortifications[cell.y][cell.x] = max(level, 0)

func update_fortification(cell: Vector2i, species: String, tech_level: int) -> int:
	if not is_in_bounds(cell) or cell.y >= _owners.size():
		return 0
	var orow: Array = _owners[cell.y]
	if cell.x >= orow.size():
		return 0
	if orow[cell.x] != species:
		return get_fortification(cell)
	if cell.y >= _fortifications.size() or cell.x >= (_fortifications[cell.y] as Array).size():
		return 0
	var current := _fortifications[cell.y][cell.x] as int
	var structure := get_structure(cell)
	if cell.y >= _presence.size() or cell.x >= (_presence[cell.y] as Array).size():
		return current
	var presence := _presence[cell.y][cell.x] as int
	var target_level := current

	if structure != "" and presence >= 60:
		target_level = maxi(target_level, 1)
	if (structure == "village" or structure == "town") and tech_level >= 1 and presence >= 220:
		target_level = maxi(target_level, 2)
	if structure == "town" and tech_level >= 3 and presence >= 520:
		target_level = maxi(target_level, 3)

	if target_level != current:
		_fortifications[cell.y][cell.x] = target_level
	return _fortifications[cell.y][cell.x] as int

func get_improvement(cell: Vector2i) -> String:
	if not is_in_bounds(cell) or cell.y >= _improvements.size():
		return ""
	var row: Array = _improvements[cell.y]
	if cell.x >= row.size():
		return ""
	return row[cell.x]

func set_improvement(cell: Vector2i, improvement: String) -> void:
	if not is_in_bounds(cell) or cell.y >= _improvements.size():
		return
	var row: Array = _improvements[cell.y]
	if cell.x >= row.size():
		return
	_improvements[cell.y][cell.x] = improvement

# ── Noise helpers ──────────────────────────────────────────────────────────────

func _generate_noise_grid() -> Array:
	var grid: Array = []
	for y in range(height):
		var row: Array = []
		for x in range(width):
			row.append(_rng.randf())
		grid.append(row)
	return grid

## Box-blur smoothing: `passes` × 3×3 average over the grid.
func _smooth_noise(grid: Array, passes: int) -> Array:
	var cur := grid
	for _p in range(passes):
		var next: Array = []
		for y in range(height):
			var row: Array = []
			for x in range(width):
				var s := 0.0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						s += cur[clampi(y+dy, 0, height-1)][clampi(x+dx, 0, width-1)] as float
				row.append(s / 9.0)
			next.append(row)
		cur = next
	return cur

# ── Multi-continent "Earth-like" ───────────────────────────────────────────────
# 5-6 continent seeds placed with minimum separation.
# Biomes follow latitude + interior distance rules.
func _generate_earth_like() -> void:
	_tiles.clear()
	var noise := _smooth_noise(_generate_noise_grid(), 3)

	# Place 5 continent seeds with minimum mutual distance
	const NUM_C := 5
	var seeds: Array[Vector2] = []
	var tries := 0
	while seeds.size() < NUM_C and tries < 400:
		tries += 1
		var cand := Vector2(
			_rng.randf_range(0.08, 0.92) * float(width),
			_rng.randf_range(0.08, 0.92) * float(height))
		var min_sep := float(min(width, height)) * 0.28
		var ok := true
		for s: Vector2 in seeds:
			if cand.distance_to(s) < min_sep:
				ok = false; break
		if ok:
			seeds.append(cand)

	var base_r := float(min(width, height)) * 0.22

	for y in range(height):
		var row: Array = []
		var lat := absf((float(y) / float(height - 1)) * 2.0 - 1.0)
		for x in range(width):
			var n := noise[y][x] as float
			var best := 0.0
			for seed: Vector2 in seeds:
				var r := base_r * (0.55 + n * 0.85)
				var inf := maxf(0.0, 1.0 - seed.distance_to(Vector2(x, y)) / r)
				best = maxf(best, inf)

			var biome: String
			if   best < 0.06:                              biome = "water"
			elif best < 0.15:                              biome = "sand"    # beach
			elif lat  > 0.92:                              biome = "snow"    # polar caps
			elif lat  > 0.84:                              biome = "mountain"
			elif lat  > 0.66:                              biome = "forest"
			elif lat  < 0.08 and best > 0.20:              biome = "jungle"  # equatorial
			elif lat  < 0.14 and n > 0.60:                 biome = "sand"    # tropical desert
			elif best > 0.70 and n > 0.66:                 biome = "mountain"
			elif n    > 0.55 and best > 0.28:              biome = "forest"
			else:                                          biome = "grass"
			row.append(biome)
		_tiles.append(row)

# ── Single continent + island chains ──────────────────────────────────────────
func _generate_continent() -> void:
	_tiles.clear()
	var noise := _smooth_noise(_generate_noise_grid(), 3)

	var center := Vector2(
		_rng.randf_range(0.30, 0.70) * float(width),
		_rng.randf_range(0.30, 0.70) * float(height))
	var main_r := float(min(width, height)) * 0.35

	# 3-5 island chains orbiting the main continent
	var num_islands := _rng.randi_range(3, 5)
	var islands: Array = []
	for _i in num_islands:
		var angle := _rng.randf() * TAU
		var dist  := main_r * _rng.randf_range(0.80, 1.55)
		var ic    := center + Vector2(cos(angle), sin(angle)) * dist
		ic = Vector2(clampf(ic.x, 4.0, float(width) - 4.0), clampf(ic.y, 4.0, float(height) - 4.0))
		islands.append({"c": ic, "r": main_r * _rng.randf_range(0.11, 0.24)})

	for y in range(height):
		var row: Array = []
		for x in range(width):
			var n   := noise[y][x] as float
			var pos := Vector2(float(x), float(y))

			# Main continent
			var best := maxf(0.0, 1.0 - pos.distance_to(center) / (main_r * (0.55 + n * 0.85)))
			# Island influences (capped at 0.65 so they're smaller)
			for idata: Dictionary in islands:
				var ir  := (idata["r"] as float) * (0.55 + n * 0.85)
				var ii  := maxf(0.0, 1.0 - pos.distance_to(idata["c"] as Vector2) / ir)
				best = maxf(best, ii * 0.65)

			var biome: String
			if   best < 0.06:                        biome = "water"
			elif best < 0.16:                        biome = "sand"
			elif best > 0.72 and n > 0.65:           biome = "mountain"
			elif best > 0.58 and n < 0.32:           biome = "jungle"  # moist interior
			elif best > 0.42 and n > 0.52:           biome = "forest"
			else:                                    biome = "grass"
			row.append(biome)
		_tiles.append(row)

# ── Archipelago (many small scattered islands) ─────────────────────────────────
func _generate_random() -> void:
	_tiles.clear()
	var noise := _smooth_noise(_generate_noise_grid(), 2)

	var num_islands := _rng.randi_range(8, 15)
	var islands: Array = []
	for _i in num_islands:
		islands.append({
			"c": Vector2(_rng.randf_range(0.05, 0.95) * float(width),
			             _rng.randf_range(0.05, 0.95) * float(height)),
			"r": _rng.randf_range(float(min(width, height)) * 0.04,
			                      float(min(width, height)) * 0.20),
		})

	for y in range(height):
		var row: Array = []
		for x in range(width):
			var n   := noise[y][x] as float
			var pos := Vector2(float(x), float(y))
			var best := 0.0
			for idata: Dictionary in islands:
				var ir := (idata["r"] as float) * (0.55 + n * 0.85)
				best = maxf(best, maxf(0.0, 1.0 - pos.distance_to(idata["c"] as Vector2) / ir))

			var biome: String
			if   best < 0.07:               biome = "water"
			elif best < 0.18:               biome = "sand"
			elif best > 0.68 and n > 0.70:  biome = "mountain"
			elif best > 0.40 and n > 0.55:  biome = "forest"
			else:                           biome = "grass"
			row.append(biome)
		_tiles.append(row)

func get_biome(cell: Vector2i) -> String:
	if not is_in_bounds(cell) or cell.y >= _tiles.size():
		return ""
	var row: Array = _tiles[cell.y]
	if cell.x >= row.size():
		return ""
	return row[cell.x]

func set_biome(cell: Vector2i, biome: String) -> void:
	if not is_in_bounds(cell) or cell.y >= _tiles.size():
		return
	var row: Array = _tiles[cell.y]
	if cell.x >= row.size():
		return
	_tiles[cell.y][cell.x] = biome

func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

func is_walkable(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	var biome: String = get_biome(cell)
	return biome != "water" and biome != "mountain" and biome != "snow"

func get_all_walkable_cells() -> Array[Vector2i]:
	var walkable: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			if is_walkable(cell):
				walkable.append(cell)
	return walkable
