extends RefCounted
class_name WorldEffects

var fire_cells: Dictionary = {}
var effects: Array[Dictionary] = []


func reset() -> void:
	fire_cells.clear()
	effects.clear()


func has_active_visuals() -> bool:
	return not fire_cells.is_empty() or not effects.is_empty()


func apply_power(power: String, center: Vector2i, world_grid: WorldGrid, humans: Array, world_year: int, log_event: Callable) -> void:
	match power:
		"meteor":    _power_meteor(center, world_grid, humans, world_year, log_event)
		"lightning": _power_lightning(center, world_grid, humans)
		"fire":      _power_fire(center, world_grid)
		"plague":    _power_plague(center, humans, world_year, log_event)
		"rain":      _power_rain(center, humans)
		"blessing":  _power_blessing(center, humans, world_year, log_event)


func tick(world_grid: WorldGrid, humans: Array, rng: RandomNumberGenerator) -> void:
	_tick_fire(world_grid, humans, rng)
	_tick_plague(humans, rng)
	_advance_effects()

func _build_humans_by_cell(humans: Array) -> Dictionary:
	var by_cell: Dictionary = {}
	for human: Human in humans:
		var cell := human.grid_position
		if not by_cell.has(cell):
			by_cell[cell] = []
		(by_cell[cell] as Array).append(human)
	return by_cell


func _power_meteor(center: Vector2i, world_grid: WorldGrid, humans: Array, world_year: int, log_event: Callable) -> void:
	effects.append({"type": "impact", "cell": center, "age": 0, "max_age": 20})
	log_event.call("Ano %d: Un meteorito cayo del cielo!" % world_year, "")
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var cell := center + Vector2i(dx, dy)
			if not world_grid.is_in_bounds(cell):
				continue
			var dist := absf(float(dx)) + absf(float(dy))
			if dist > 4:
				continue
			if world_grid.get_biome(cell) != "water":
				world_grid.set_biome(cell, "sand")
				world_grid.set_owner(cell, "")
			fire_cells.erase(cell)
	for human: Human in humans.duplicate():
		if (human.grid_position - center).length() <= 3.5:
			human.evolution_score = -50.0


func _power_lightning(cell: Vector2i, world_grid: WorldGrid, humans: Array) -> void:
	effects.append({"type": "lightning", "cell": cell, "age": 0, "max_age": 8})
	for human: Human in humans.duplicate():
		if human.grid_position == cell:
			human.evolution_score = -50.0
			return
	if world_grid.get_structure(cell) != "":
		world_grid.set_owner(cell, "")
	elif world_grid.is_walkable(cell):
		fire_cells[cell] = 0


func _power_fire(cell: Vector2i, world_grid: WorldGrid) -> void:
	if world_grid.is_walkable(cell) and world_grid.get_biome(cell) != "sand":
		fire_cells[cell] = 0


func _power_plague(center: Vector2i, humans: Array, world_year: int, log_event: Callable) -> void:
	log_event.call("Ano %d: Una plaga se extiende por las tierras!" % world_year, "")
	for human: Human in humans:
		if (human.grid_position - center).length() <= 4.0:
			human.infected = true


func _power_rain(center: Vector2i, humans: Array) -> void:
	effects.append({"type": "rain", "cell": center, "age": 0, "max_age": 15})
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			fire_cells.erase(center + Vector2i(dx, dy))
	for human: Human in humans:
		if (human.grid_position - center).length() <= 4.0:
			human.on_fire = false
			human.evolution_score += 3.0


func _power_blessing(center: Vector2i, humans: Array, world_year: int, log_event: Callable) -> void:
	effects.append({"type": "blessing", "cell": center, "age": 0, "max_age": 18})
	log_event.call("Ano %d: Una bendicion divina ilumina la tierra" % world_year, "")
	for human: Human in humans:
		if (human.grid_position - center).length() <= 3.0:
			human.evolution_score += 10.0
			human.infected = false


func _tick_fire(world_grid: WorldGrid, humans: Array, rng: RandomNumberGenerator) -> void:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var new_fires: Array[Vector2i] = []
	var to_erase: Array[Vector2i] = []
	var humans_by_cell := _build_humans_by_cell(humans)
	for cell: Vector2i in fire_cells.keys():
		fire_cells[cell] = (fire_cells[cell] as int) + 1
		var humans_here := humans_by_cell.get(cell, []) as Array
		for human: Human in humans_here:
			human.on_fire = true
		if (fire_cells[cell] as int) > 40:
			world_grid.set_owner(cell, "")
			if world_grid.get_biome(cell) == "forest":
				world_grid.set_biome(cell, "sand")
			to_erase.append(cell)
			continue
		if rng.randf() < 0.08:
			var direction := dirs[rng.randi_range(0, 3)]
			var next_cell := cell + direction
			if world_grid.is_in_bounds(next_cell) and world_grid.is_walkable(next_cell) and not fire_cells.has(next_cell):
				var biome := world_grid.get_biome(next_cell)
				var spread_chance := 0.6 if biome == "forest" else (0.3 if biome == "grass" else 0.1)
				if rng.randf() < spread_chance:
					new_fires.append(next_cell)
	for cell: Vector2i in to_erase:
		fire_cells.erase(cell)
	for cell: Vector2i in new_fires:
		fire_cells[cell] = 0
	for human: Human in humans:
		if not fire_cells.has(human.grid_position):
			human.on_fire = false


func _tick_plague(humans: Array, rng: RandomNumberGenerator) -> void:
	var infected_counts: Dictionary = {}
	for human: Human in humans:
		if human.infected:
			infected_counts[human.grid_position] = (infected_counts.get(human.grid_position, 0) as int) + 1
	for human: Human in humans:
		if human.infected:
			continue
		var exposure := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				exposure += infected_counts.get(human.grid_position + Vector2i(dx, dy), 0) as int
		if exposure <= 0:
			continue
		var infection_chance := 1.0 - pow(0.96, float(exposure))
		if rng.randf() < infection_chance:
			human.infected = true


func _advance_effects() -> void:
	var to_remove: Array[int] = []
	for i in effects.size():
		effects[i]["age"] = (effects[i]["age"] as int) + 1
		if (effects[i]["age"] as int) >= (effects[i]["max_age"] as int):
			to_remove.append(i)
	for i in range(to_remove.size() - 1, -1, -1):
		effects.remove_at(to_remove[i])
