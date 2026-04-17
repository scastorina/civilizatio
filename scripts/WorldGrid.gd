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

func get_biome(cell: Vector2i) -> String:
	if not is_in_bounds(cell):
		return ""
	return _tiles[cell.y][cell.x]

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
