extends RefCounted
class_name WorldGrid

var width: int
var height: int

var _rng := RandomNumberGenerator.new()
var _tiles: Array = []

func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	_rng.randomize()

func generate() -> void:
	_tiles.clear()
	for y in range(height):
		var row: Array = []
		for x in range(width):
			var v := _rng.randf()
			if v < 0.18:
				row.append("water")
			elif v < 0.24:
				row.append("sand")
			elif v < 0.72:
				row.append("grass")
			elif v < 0.88:
				row.append("forest")
			else:
				row.append("mountain")
		_tiles.append(row)

func generate_continents() -> void:
	_tiles.clear()
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.04
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0

	for y in range(height):
		var row: Array = []
		for x in range(width):
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			row.append(_elevation_to_biome(n))
		_tiles.append(row)

func generate_world() -> void:
	_tiles.clear()
	var elev := FastNoiseLite.new()
	elev.seed = _rng.randi()
	elev.frequency = 0.025
	elev.fractal_octaves = 5
	elev.fractal_gain = 0.5
	elev.fractal_lacunarity = 2.0

	var moisture := FastNoiseLite.new()
	moisture.seed = _rng.randi()
	moisture.frequency = 0.06
	moisture.fractal_octaves = 3

	for y in range(height):
		var row: Array = []
		for x in range(width):
			var e := (elev.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var m := (moisture.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			row.append(_biome_from_elev_moisture(e, m))
		_tiles.append(row)

func _elevation_to_biome(n: float) -> String:
	if n < 0.35:
		return "water"
	elif n < 0.43:
		return "sand"
	elif n < 0.67:
		return "grass"
	elif n < 0.82:
		return "forest"
	else:
		return "mountain"

func _biome_from_elev_moisture(e: float, m: float) -> String:
	if e < 0.33:
		return "water"
	if e < 0.40:
		return "sand"
	if e > 0.78:
		return "mountain"
	if m > 0.55:
		return "forest"
	return "grass"

func get_biome(cell: Vector2i) -> String:
	if not is_in_bounds(cell):
		return ""
	return _tiles[cell.y][cell.x]

func set_biome(cell: Vector2i, biome: String) -> void:
	if not is_in_bounds(cell):
		return
	_tiles[cell.y][cell.x] = biome

func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

func is_walkable(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	var b := get_biome(cell)
	return b != "water" and b != "mountain"

func get_all_walkable_cells() -> Array[Vector2i]:
	var walkable: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			if is_walkable(cell):
				walkable.append(cell)
	return walkable
