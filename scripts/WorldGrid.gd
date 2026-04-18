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
	if not is_in_bounds(cell):
		return ""
	return _owners[cell.y][cell.x]

func set_owner(cell: Vector2i, species: String) -> void:
	if not is_in_bounds(cell):
		return
	if _owners[cell.y][cell.x] != species:
		_owners[cell.y][cell.x] = species
		_presence[cell.y][cell.x] = 0
		_structures[cell.y][cell.x] = ""
		_fortifications[cell.y][cell.x] = 0
		_improvements[cell.y][cell.x] = ""

func tick_presence(cell: Vector2i, species: String) -> void:
	if not is_in_bounds(cell):
		return
	if _owners[cell.y][cell.x] != species:
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
	if not is_in_bounds(cell):
		return ""
	return _structures[cell.y][cell.x]

func get_fortification(cell: Vector2i) -> int:
	if not is_in_bounds(cell):
		return 0
	return _fortifications[cell.y][cell.x] as int

func update_fortification(cell: Vector2i, species: String, tech_level: int) -> int:
	if not is_in_bounds(cell):
		return 0
	if _owners[cell.y][cell.x] != species:
		return get_fortification(cell)
	var current := _fortifications[cell.y][cell.x] as int
	var structure := get_structure(cell)
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
	if not is_in_bounds(cell):
		return ""
	return _improvements[cell.y][cell.x]

func set_improvement(cell: Vector2i, improvement: String) -> void:
	if not is_in_bounds(cell):
		return
	_improvements[cell.y][cell.x] = improvement

func _generate_random() -> void:
	_tiles.clear()
	for y in range(height):
		var row: Array = []
		for x in range(width):
			var value := _rng.randf()
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
		_tiles.append(row)

func _generate_earth_like() -> void:
	_tiles.clear()
	for y in range(height):
		var row: Array = []
		var latitude: float = absf((float(y) / float(height - 1)) * 2.0 - 1.0)
		for x in range(width):
			var continental_noise := _rng.randf()
			var biome := "grass"
			if continental_noise < 0.35:
				biome = "water"
			elif latitude > 0.80:
				biome = "mountain"
			elif latitude > 0.65:
				biome = "forest"
			elif latitude < 0.15 and continental_noise > 0.70:
				biome = "sand"
			elif continental_noise > 0.85:
				biome = "mountain"
			row.append(biome)
		_tiles.append(row)

func _generate_continent() -> void:
	_tiles.clear()
	var center := Vector2(width * 0.5, height * 0.5)
	var max_distance: float = min(width, height) * 0.42
	for y in range(height):
		var row: Array = []
		for x in range(width):
			var distance := Vector2(x, y).distance_to(center)
			var value := _rng.randf()
			if distance > max_distance + _rng.randf_range(-3.0, 3.0):
				row.append("water")
			elif distance > max_distance * 0.85:
				row.append("sand")
			elif value > 0.82:
				row.append("mountain")
			elif value > 0.58:
				row.append("forest")
			else:
				row.append("grass")
		_tiles.append(row)

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
	var biome: String = get_biome(cell)
	return biome != "water" and biome != "mountain"

func get_all_walkable_cells() -> Array[Vector2i]:
	var walkable: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			if is_walkable(cell):
				walkable.append(cell)
	return walkable
