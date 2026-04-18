extends Node2D

const TILE_SIZE := 16
const WORLD_WIDTH := 96
const WORLD_HEIGHT := 54
const INITIAL_HUMANS := 20
const MAX_HUMANS := 200
const MOVE_TICK_SECONDS := 0.35
const BIOMES: Array[String] = ["water", "sand", "grass", "forest", "mountain"]
const MAP_PRESETS: Array[String] = ["random", "earth_like", "continent"]
const TIME_SPEEDS: Array[float] = [0.0, 1.0, 2.0, 5.0, 10.0]
const SPECIES_LIBRARY: Array[Dictionary] = [
	{"name": "Humanos", "color": Color(1.0, 0.92, 0.80), "preferred": ["grass", "forest"],   "combat": 1.0, "defense": 1.0, "evo_rate": 1.0},
	{"name": "Elfos",   "color": Color(0.75, 0.95, 0.75), "preferred": ["forest", "grass"],   "combat": 0.6, "defense": 0.8, "evo_rate": 2.0},
	{"name": "Enanos",  "color": Color(0.82, 0.75, 0.62), "preferred": ["mountain", "forest"],"combat": 0.9, "defense": 2.5, "evo_rate": 0.8},
	{"name": "Orcos",   "color": Color(0.65, 0.80, 0.55), "preferred": ["sand", "grass"],     "combat": 2.0, "defense": 0.7, "evo_rate": 0.6},
]

var rng := RandomNumberGenerator.new()
var world_grid := WorldGrid.new(WORLD_WIDTH, WORLD_HEIGHT)
var humans: Array[Human] = []
var move_tick_accumulator := 0.0
var _species_colors: Dictionary = {}
var _species_combat: Dictionary = {}
var _species_defense: Dictionary = {}
var _species_tech: Dictionary = {}
var _species_research: Dictionary = {}
var _territory_names: Dictionary = {}
var _chronicle: Array[String] = []
var _chronicle_colors: Array[Color] = []
var _known_kingdoms: Dictionary = {}
var world_year := 0

const TECH_THRESHOLDS: Array[float] = [100.0, 300.0, 700.0]
const CHRONICLE_MAX := 40

var current_speed_idx := 1
var current_map_idx := 0
var mouse_painting := false
var last_painted_cell := Vector2i(-1, -1)
var _panning := false
var _pan_origin := Vector2.ZERO
var _cam_origin := Vector2.ZERO
var _fire_cells: Dictionary = {}
var _effects: Array[Dictionary] = []
var _trade_routes: Array[Dictionary] = []

const GameHUDScript = preload("res://scripts/GameHUD.gd")

var ui: GameUI
var hud: Node2D
var camera: Camera2D

func _ready() -> void:
	rng.randomize()
	for sp: Dictionary in SPECIES_LIBRARY:
		var n := sp["name"] as String
		_species_colors[n]  = sp["color"] as Color
		_species_combat[n]  = sp["combat"] as float
		_species_defense[n] = sp["defense"] as float
		_species_tech[n]    = 0
		_species_research[n] = 0.0
	camera = Camera2D.new()
	camera.zoom = Vector2(2.0, 2.0)
	camera.position = Vector2(WORLD_WIDTH * TILE_SIZE * 0.5, WORLD_HEIGHT * TILE_SIZE * 0.5)
	add_child(camera)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = GameHUDScript.new()
	hud_layer.add_child(hud)

	ui = GameUI.new()
	add_child(ui)
	ui.setup_species(SPECIES_LIBRARY)
	ui.time_speed_changed.connect(func(idx): current_speed_idx = idx)
	ui.map_type_changed.connect(func(idx): current_map_idx = idx)
	ui.regenerate_requested.connect(_regenerate_world)
	ui.power_selected.connect(func(_idx): pass)
	_regenerate_world()

func _process(delta: float) -> void:
	var speed := TIME_SPEEDS[current_speed_idx]
	if speed == 0.0:
		return
	move_tick_accumulator += delta * speed
	var ticked := false
	while move_tick_accumulator >= MOVE_TICK_SECONDS:
		move_tick_accumulator -= MOVE_TICK_SECONDS
		world_year += 1
		_move_humans()
		_update_evolution()
		_resolve_combat()
		_decay_dead_territories()
		_update_technology()
		_tick_fire()
		_tick_plague()
		_advance_effects()
		_update_trade()
		ticked = true
	if ticked:
		queue_redraw()
		_refresh_hud()
	elif not _trade_routes.is_empty() or not _effects.is_empty() or not _fire_cells.is_empty():
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_regenerate_world()
			return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.15).clamp(Vector2(0.5, 0.5), Vector2(8.0, 8.0))
			_clamp_camera()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.15).clamp(Vector2(0.5, 0.5), Vector2(8.0, 8.0))
			_clamp_camera()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
			if event.pressed:
				_pan_origin = event.position
				_cam_origin = camera.position
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			mouse_painting = event.pressed
			if event.pressed:
				last_painted_cell = Vector2i(-1, -1)
				_apply_tool_at(event.position)
			else:
				last_painted_cell = Vector2i(-1, -1)

	if event is InputEventMouseMotion:
		if _panning:
			camera.position = _cam_origin - (event.position - _pan_origin) / camera.zoom.x
			_clamp_camera()
		elif mouse_painting:
			_apply_tool_at(event.position)

func _clamp_camera() -> void:
	var half := get_viewport_rect().size * 0.5 / camera.zoom.x
	camera.position.x = clampf(camera.position.x, half.x, WORLD_WIDTH  * TILE_SIZE - half.x)
	camera.position.y = clampf(camera.position.y, half.y, WORLD_HEIGHT * TILE_SIZE - half.y)

func _apply_tool_at(pos: Vector2) -> void:
	var cell := _mouse_to_cell(pos)
	if cell == last_painted_cell:
		return
	last_painted_cell = cell
	if not world_grid.is_in_bounds(cell):
		return

	match ui.active_tab:
		"terrain":
			var biome: String = GameUI.BIOMES[ui.selected_biome]
			if (biome == "water" or biome == "mountain") and _has_human_in_cell(cell):
				return
			world_grid.set_biome(cell, biome)
			queue_redraw()
		"entities":
			if world_grid.is_walkable(cell) and not _has_human_in_cell(cell) and humans.size() < MAX_HUMANS:
				_spawn_human_at(cell, SPECIES_LIBRARY[ui.selected_species])
				queue_redraw()
		"powers":
			_apply_power_at(cell)
			queue_redraw()

func _regenerate_world() -> void:
	move_tick_accumulator = 0.0
	for n: String in _species_tech.keys():
		_species_tech[n] = 0
		_species_research[n] = 0.0
	_territory_names.clear()
	_chronicle.clear()
	_chronicle_colors.clear()
	_known_kingdoms.clear()
	_fire_cells.clear()
	_effects.clear()
	_trade_routes.clear()
	world_year = 0
	world_grid.generate(MAP_PRESETS[current_map_idx])
	_spawn_initial_humans()
	queue_redraw()

func _spawn_initial_humans() -> void:
	for human in humans:
		human.queue_free()
	humans.clear()

	var walkable := world_grid.get_all_walkable_cells()
	_shuffle_cells(walkable)

	var count := mini(INITIAL_HUMANS, walkable.size())
	for i in range(count):
		var species: Dictionary = SPECIES_LIBRARY[i % SPECIES_LIBRARY.size()]
		_spawn_human_at(walkable[i], species)

func _spawn_human_at(cell: Vector2i, species: Dictionary) -> void:
	var preferred: Array[String] = []
	preferred.assign(species["preferred"])
	var human := Human.new()
	human.setup(cell, TILE_SIZE, species["name"], species["color"], preferred,
		species["combat"] as float, species["defense"] as float, species["evo_rate"] as float)
	world_grid.set_owner(cell, species["name"] as String)
	add_child(human)
	humans.append(human)

func _move_humans() -> void:
	var occupied := {}
	for human in humans:
		occupied[_cell_key(human.grid_position)] = true

	_shuffle_humans()
	for human in humans:
		occupied.erase(_cell_key(human.grid_position))
		var next := human.choose_next_cell(world_grid, rng, occupied)
		human.set_grid_position(next)
		world_grid.set_owner(next, human.species_name)
		occupied[_cell_key(next)] = true

func _resolve_combat() -> void:
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for human in humans:
		for dir in dirs:
			var target := human.grid_position + dir
			if not world_grid.is_walkable(target):
				continue
			var target_owner := world_grid.get_owner(target)
			if target_owner == "" or target_owner == human.species_name:
				continue
			var def_bonus: float = _species_defense.get(target_owner, 1.0)
			var tech_atk := 1.25 if (_species_tech.get(human.species_name, 0) as int) >= 2 else 1.0
			var tech_def := 2.0  if (_species_tech.get(target_owner, 0) as int) >= 3 else 1.0
			var chance := _conquest_chance(world_grid.get_structure(target)) * human.combat_bonus * tech_atk / (def_bonus * tech_def)
			if rng.randf() < chance:
				world_grid.set_owner(target, human.species_name)
				human.battles_won += 1
				if human.battles_won == 5 and not human.is_hero:
					human.is_hero = true
					human.hero_name = _generate_hero_name(human.species_name, human.battles_won ^ human.age_ticks ^ human.grid_position.x)
					_log_event("Año %d: ¡%s se convirtió en leyenda de los %s!" % [world_year, human.hero_name, human.species_name], human.species_name)

func _conquest_chance(structure: String) -> float:
	match structure:
		"camp":    return 0.03
		"village": return 0.02
		"town":    return 0.01
		_:         return 0.05

func _update_evolution() -> void:
	var to_remove: Array[Human] = []
	for human in humans:
		var cell := human.grid_position
		human.update_evolution(world_grid.get_biome(cell))
		var prev_structure := world_grid.get_structure(cell)
		world_grid.tick_presence(cell, human.species_name)
		if (_species_tech.get(human.species_name, 0) as int) >= 1:
			world_grid.tick_presence(cell, human.species_name)
		var new_structure := world_grid.get_structure(cell)
		if new_structure != prev_structure:
			match new_structure:
				"camp":   _log_event("Año %d: Los %s establecieron un campamento" % [world_year, human.species_name], human.species_name)
				"village":_log_event("Año %d: Los %s fundaron una aldea" % [world_year, human.species_name], human.species_name)
				"town":   _log_event("Año %d: ¡Los %s erigieron una ciudad!" % [world_year, human.species_name], human.species_name)
		match world_grid.get_structure(cell):
			"village": human.evolution_score += 0.02
			"town":    human.evolution_score += 0.05
		if human.is_dead():
			to_remove.append(human)
	for dead in to_remove:
		if dead.is_hero:
			_log_event("Año %d: %s, héroe de los %s, ha caído" % [world_year, dead.hero_name, dead.species_name], dead.species_name)
		humans.erase(dead)
		dead.queue_free()
	var living_after: Dictionary = {}
	for h in humans:
		living_after[h.species_name] = true
	for dead2 in to_remove:
		if not living_after.has(dead2.species_name):
			_log_event("Año %d: ¡Los %s han sido erradicados del mundo!" % [world_year, dead2.species_name], dead2.species_name)
	if humans.size() < MAX_HUMANS:
		for human in humans.duplicate():
			var repro_threshold := 10.0 if (_species_tech.get(human.species_name, 0) as int) >= 3 else 15.0
			if human.evolution_score > repro_threshold and humans.size() < MAX_HUMANS:
				if rng.randf() < 0.01:
					_try_reproduce(human)

func _try_reproduce(parent: Human) -> void:
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for dir in dirs:
		var cell := parent.grid_position + dir
		if world_grid.is_walkable(cell) and not _has_human_in_cell(cell):
			var sp := _find_species(parent.species_name)
			if not sp.is_empty():
				_spawn_human_at(cell, sp)
				parent.evolution_score -= 8.0
			return

func _find_species(sp_name: String) -> Dictionary:
	for sp: Dictionary in SPECIES_LIBRARY:
		if sp["name"] == sp_name:
			return sp
	return {}

func _decay_dead_territories() -> void:
	var living: Dictionary = {}
	for human in humans:
		living[human.species_name] = true
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var cell := Vector2i(x, y)
			var owner := world_grid.get_owner(cell)
			if owner != "" and not living.has(owner):
				if rng.randf() < 0.03:
					world_grid.set_owner(cell, "")

func _log_event(text: String, species: String) -> void:
	_chronicle.append(text)
	_chronicle_colors.append(_species_colors.get(species, Color(0.8, 0.8, 0.8)) as Color)
	if _chronicle.size() > CHRONICLE_MAX:
		_chronicle.pop_front()
		_chronicle_colors.pop_front()

func _generate_hero_name(species: String, seed: int) -> String:
	var h := seed & 0x7FFFFFFF
	match species:
		"Humanos":
			var f: Array[String] = ["Rodrigo","Carlos","Isabel","Pedro","Alicia","Diego","Lucía","Marcos"]
			var l: Array[String] = ["el Valiente","el Grande","la Sabia","el Conquistador","la Feroz","de Hierro"]
			return f[h % f.size()] + " " + l[(h >> 3) % l.size()]
		"Elfos":
			var f: Array[String] = ["Aelindra","Silmor","Thalion","Galadwen","Ithilorn","Faelith","Mithwen"]
			var l: Array[String] = ["el Eterno","la Luminosa","el Veloz","el Sabio","la Inmortal","del Bosque"]
			return f[h % f.size()] + " " + l[(h >> 3) % l.size()]
		"Enanos":
			var f: Array[String] = ["Thordin","Bromkul","Kargdar","Durnok","Morbrak","Gorzum","Kazdul"]
			var l: Array[String] = ["Mano de Piedra","el Férreo","Rompe-Montañas","el Forjador","Casco de Acero"]
			return f[h % f.size()] + " " + l[(h >> 3) % l.size()]
		"Orcos":
			var f: Array[String] = ["Gromash","Urgak","Raktor","Skulgar","Vrukash","Zagmor","Drakul"]
			var l: Array[String] = ["el Destructor","Sangre-Roja","el Imparable","el Salvaje","Rompe-Reinos"]
			return f[h % f.size()] + " " + l[(h >> 3) % l.size()]
	return "El Desconocido"

func _update_technology() -> void:
	var research_gain: Dictionary = {}
	for human in humans:
		if not research_gain.has(human.species_name):
			research_gain[human.species_name] = 0.0
		if human.evolution_score > 0.0:
			research_gain[human.species_name] += human.evolution_score * 0.05
	for sp_name: String in research_gain.keys():
		_species_research[sp_name] = (_species_research.get(sp_name, 0.0) as float) + research_gain[sp_name]
		var lvl: int = _species_tech.get(sp_name, 0) as int
		if lvl < TECH_THRESHOLDS.size() and (_species_research[sp_name] as float) >= TECH_THRESHOLDS[lvl]:
			_species_tech[sp_name] = lvl + 1
			_log_event("Año %d: Los %s alcanzaron tecnología nivel %d" % [world_year, sp_name, lvl + 1], sp_name)

func _update_trade() -> void:
	var towns: Dictionary = {}
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var cell := Vector2i(x, y)
			if world_grid.get_structure(cell) == "town":
				var owner := world_grid.get_owner(cell)
				if owner != "":
					if not towns.has(owner):
						towns[owner] = []
					(towns[owner] as Array).append(cell)

	var new_routes: Array[Dictionary] = []
	for species: String in towns.keys():
		var sp_towns: Array = towns[species]
		for i in sp_towns.size():
			var best_dist := 999999.0
			var best_j := -1
			for j in sp_towns.size():
				if j == i:
					continue
				var dist := (sp_towns[i] as Vector2i).distance_to(sp_towns[j] as Vector2i)
				if dist < best_dist and dist < 35.0:
					best_dist = dist
					best_j = j
			if best_j < 0:
				continue
			var a: Vector2i = sp_towns[i] as Vector2i
			var b: Vector2i = sp_towns[best_j] as Vector2i
			var already := false
			for r: Dictionary in new_routes:
				if (r["from"] == a and r["to"] == b) or (r["from"] == b and r["to"] == a):
					already = true
					break
			if not already:
				new_routes.append({"from": a, "to": b, "species": species})

	for r: Dictionary in new_routes:
		var existed := false
		for old: Dictionary in _trade_routes:
			if (old["from"] == r["from"] and old["to"] == r["to"]) or (old["from"] == r["to"] and old["to"] == r["from"]):
				existed = true
				break
		if not existed:
			_log_event("Año %d: Los %s abrieron una ruta comercial" % [world_year, r["species"] as String], r["species"] as String)

	_trade_routes = new_routes

	var trade_towns: Dictionary = {}
	for r: Dictionary in _trade_routes:
		trade_towns[r["from"] as Vector2i] = true
		trade_towns[r["to"] as Vector2i] = true
	for human in humans:
		for town_cell: Vector2i in trade_towns.keys():
			if (human.grid_position - town_cell).length() <= 2.0:
				human.evolution_score += 0.01
				break

func _apply_power_at(cell: Vector2i) -> void:
	var power: String = GameUI.POWERS[ui.selected_power]
	match power:
		"meteor":   _power_meteor(cell)
		"lightning":_power_lightning(cell)
		"fire":     _power_fire(cell)
		"plague":   _power_plague(cell)
		"rain":     _power_rain(cell)
		"blessing": _power_blessing(cell)

func _power_meteor(center: Vector2i) -> void:
	_effects.append({"type": "impact", "cell": center, "age": 0, "max_age": 20})
	_log_event("Año %d: ¡Un meteorito cayo del cielo!" % world_year, "")
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var c := center + Vector2i(dx, dy)
			if not world_grid.is_in_bounds(c):
				continue
			var dist := absf(float(dx)) + absf(float(dy))
			if dist > 4:
				continue
			if world_grid.get_biome(c) != "water":
				world_grid.set_biome(c, "sand")
				world_grid.set_owner(c, "")
			_fire_cells.erase(c)
	for human in humans.duplicate():
		if (human.grid_position - center).length() <= 3.5:
			human.evolution_score = -50.0

func _power_lightning(cell: Vector2i) -> void:
	_effects.append({"type": "lightning", "cell": cell, "age": 0, "max_age": 8})
	for human in humans.duplicate():
		if human.grid_position == cell:
			human.evolution_score = -50.0
			return
	if world_grid.get_structure(cell) != "":
		world_grid.set_owner(cell, "")
	elif world_grid.is_walkable(cell):
		_fire_cells[cell] = 0

func _power_fire(cell: Vector2i) -> void:
	if world_grid.is_walkable(cell) and world_grid.get_biome(cell) != "sand":
		_fire_cells[cell] = 0

func _power_plague(center: Vector2i) -> void:
	_log_event("Año %d: ¡Una plaga se extiende por las tierras!" % world_year, "")
	for human in humans:
		if (human.grid_position - center).length() <= 4.0:
			human.infected = true

func _power_rain(center: Vector2i) -> void:
	_effects.append({"type": "rain", "cell": center, "age": 0, "max_age": 15})
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var c := center + Vector2i(dx, dy)
			_fire_cells.erase(c)
	for human in humans:
		if (human.grid_position - center).length() <= 4.0:
			human.on_fire = false
			human.evolution_score += 3.0

func _power_blessing(center: Vector2i) -> void:
	_effects.append({"type": "blessing", "cell": center, "age": 0, "max_age": 18})
	_log_event("Año %d: Una bendicion divina ilumina la tierra" % world_year, "")
	for human in humans:
		if (human.grid_position - center).length() <= 3.0:
			human.evolution_score += 10.0
			human.infected = false

func _tick_fire() -> void:
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	var new_fires: Array[Vector2i] = []
	var to_erase: Array[Vector2i] = []
	for cell: Vector2i in _fire_cells.keys():
		_fire_cells[cell] = (_fire_cells[cell] as int) + 1
		for human in humans:
			if human.grid_position == cell:
				human.on_fire = true
		if (_fire_cells[cell] as int) > 40:
			world_grid.set_owner(cell, "")
			if world_grid.get_biome(cell) == "forest":
				world_grid.set_biome(cell, "sand")
			to_erase.append(cell)
			continue
		if rng.randf() < 0.08:
			var d := dirs[rng.randi_range(0, 3)]
			var nb := cell + d
			if world_grid.is_in_bounds(nb) and world_grid.is_walkable(nb) and not _fire_cells.has(nb):
				var b := world_grid.get_biome(nb)
				var spread_chance := 0.6 if b == "forest" else (0.3 if b == "grass" else 0.1)
				if rng.randf() < spread_chance:
					new_fires.append(nb)
	for cell in to_erase:
		_fire_cells.erase(cell)
	for cell in new_fires:
		_fire_cells[cell] = 0
	for human in humans:
		if not _fire_cells.has(human.grid_position):
			human.on_fire = false

func _tick_plague() -> void:
	var infected_positions: Array[Vector2i] = []
	for human in humans:
		if human.infected:
			infected_positions.append(human.grid_position)
	for human in humans:
		if human.infected:
			continue
		for ipos in infected_positions:
			if (human.grid_position - ipos).length() <= 1.5:
				if rng.randf() < 0.04:
					human.infected = true
					break

func _advance_effects() -> void:
	var to_remove: Array[int] = []
	for i in _effects.size():
		_effects[i]["age"] = (_effects[i]["age"] as int) + 1
		if (_effects[i]["age"] as int) >= (_effects[i]["max_age"] as int):
			to_remove.append(i)
	for i in range(to_remove.size() - 1, -1, -1):
		_effects.remove_at(to_remove[i])

func _draw() -> void:
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var cell := Vector2i(x, y)
			var c := _biome_color(world_grid.get_biome(cell))
			var owner := world_grid.get_owner(cell)
			if owner != "":
				var sc: Color = _species_colors.get(owner, Color.WHITE)
				c = c.lerp(sc, 0.45)
			draw_rect(Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE), c)

	# Structures
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var cell := Vector2i(x, y)
			var structure := world_grid.get_structure(cell)
			if structure == "":
				continue
			var owner := world_grid.get_owner(cell)
			var sc: Color = _species_colors.get(owner, Color.WHITE)
			var cx := (x + 0.5) * TILE_SIZE
			var cy := (y + 0.5) * TILE_SIZE
			match structure:
				"camp":    _draw_camp(cx, cy, sc)
				"village": _draw_village(cx, cy, sc)
				"town":    _draw_town(cx, cy, sc)

	# Territory borders
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var owner := world_grid.get_owner(Vector2i(x, y))
			if owner == "":
				continue
			var bc: Color = (_species_colors.get(owner, Color.WHITE) as Color).lightened(0.35)
			var px := float(x * TILE_SIZE)
			var py := float(y * TILE_SIZE)
			if world_grid.get_owner(Vector2i(x + 1, y)) != owner:
				draw_line(Vector2(px + TILE_SIZE, py), Vector2(px + TILE_SIZE, py + TILE_SIZE), bc, 1.5)
			if world_grid.get_owner(Vector2i(x - 1, y)) != owner:
				draw_line(Vector2(px, py), Vector2(px, py + TILE_SIZE), bc, 1.5)
			if world_grid.get_owner(Vector2i(x, y + 1)) != owner:
				draw_line(Vector2(px, py + TILE_SIZE), Vector2(px + TILE_SIZE, py + TILE_SIZE), bc, 1.5)
			if world_grid.get_owner(Vector2i(x, y - 1)) != owner:
				draw_line(Vector2(px, py), Vector2(px + TILE_SIZE, py), bc, 1.5)

	# Fire overlay
	for cell: Vector2i in _fire_cells.keys():
		var ft: int = _fire_cells[cell] as int
		var alpha := lerpf(0.85, 0.4, float(ft) / 40.0)
		var fire_c := Color(1.0, 0.40 + rng.randf() * 0.2, 0.0, alpha)
		draw_rect(Rect2(cell.x * TILE_SIZE, cell.y * TILE_SIZE, TILE_SIZE, TILE_SIZE), fire_c)
		draw_rect(Rect2(cell.x * TILE_SIZE + 3, cell.y * TILE_SIZE - 2, TILE_SIZE - 6, 4), Color(1.0, 0.85, 0.0, alpha * 0.8))

	# Special effects (impact, lightning, rain, blessing)
	for eff: Dictionary in _effects:
		var ec: Vector2i = eff["cell"] as Vector2i
		var age: int = eff["age"] as int
		var max_age: int = eff["max_age"] as int
		var t := float(age) / float(max_age)
		var cx := (ec.x + 0.5) * TILE_SIZE
		var cy := (ec.y + 0.5) * TILE_SIZE
		match eff["type"] as String:
			"impact":
				var radius := lerpf(2.0, float(TILE_SIZE) * 4.5, minf(t * 3.0, 1.0))
				var ialpha := lerpf(1.0, 0.0, t)
				draw_circle(Vector2(cx, cy), radius, Color(1.0, 0.85, 0.3, ialpha * 0.7))
				draw_circle(Vector2(cx, cy), radius * 0.5, Color(1.0, 1.0, 1.0, ialpha * 0.5))
			"lightning":
				var lalpha := lerpf(1.0, 0.0, t)
				var top := Vector2(cx, 0.0)
				draw_line(top, Vector2(cx + 4, cy * 0.4), Color(1.0, 1.0, 0.5, lalpha), 2.0)
				draw_line(Vector2(cx + 4, cy * 0.4), Vector2(cx - 3, cy * 0.7), Color(1.0, 1.0, 0.5, lalpha), 2.0)
				draw_line(Vector2(cx - 3, cy * 0.7), Vector2(cx, cy), Color(1.0, 1.0, 1.0, lalpha), 3.0)
			"rain":
				var ralpha := lerpf(0.5, 0.0, t)
				for di in range(-4, 5):
					for dj in range(-4, 5):
						var rx := cx + di * TILE_SIZE + rng.randf_range(-3, 3)
						var ry := cy + dj * TILE_SIZE
						draw_line(Vector2(rx, ry - 4), Vector2(rx - 1, ry + 2), Color(0.5, 0.75, 1.0, ralpha), 1.0)
			"blessing":
				var balpha := lerpf(0.7, 0.0, t)
				var brad := lerpf(0.0, float(TILE_SIZE) * 3.5, t)
				draw_circle(Vector2(cx, cy), brad, Color(1.0, 0.95, 0.3, balpha * 0.4))
				draw_circle(Vector2(cx, cy), brad, Color(1.0, 0.9, 0.2, balpha * 0.6), false, 2.0)

	# Trade routes
	var anim_t := fmod(float(Time.get_ticks_msec()) / 300.0, 1.0)
	for route: Dictionary in _trade_routes:
		var ra: Vector2i = route["from"] as Vector2i
		var rb: Vector2i = route["to"] as Vector2i
		var rsp: String  = route["species"] as String
		var rc: Color    = (_species_colors.get(rsp, Color.WHITE) as Color).lightened(0.25)
		rc.a = 0.60
		var wp_a := Vector2((ra.x + 0.5) * TILE_SIZE, (ra.y + 0.5) * TILE_SIZE)
		var wp_b := Vector2((rb.x + 0.5) * TILE_SIZE, (rb.y + 0.5) * TILE_SIZE)
		var total_len := wp_a.distance_to(wp_b)
		var dir := (wp_b - wp_a).normalized()
		var period := 7.0
		var seg_start := anim_t * period
		while seg_start < total_len:
			var seg_end := minf(seg_start + 4.0, total_len)
			draw_line(wp_a + dir * seg_start, wp_a + dir * seg_end, rc, 1.5)
			seg_start += period
		var caravan_t := fmod(float(Time.get_ticks_msec()) / 2000.0, 1.0)
		var caravan_pos := wp_a.lerp(wp_b, caravan_t)
		draw_circle(caravan_pos, 2.8, Color(0.95, 0.80, 0.35, 0.95))
		draw_circle(caravan_pos, 1.5, Color(0.60, 0.38, 0.12, 0.95))

	# Territory labels
	for cluster in _find_territory_clusters():
		var cpos: Vector2 = cluster["center"]
		var sp: String   = cluster["species"]
		var seed: String = cluster["seed"]
		var name := _territory_name(seed, sp)
		var tc: Color = (_species_colors.get(sp, Color.WHITE) as Color).lightened(0.5)
		var tw := float(name.length() * 6 + 6)
		draw_rect(Rect2(cpos.x - tw * 0.5, cpos.y - 6.0, tw, 10.0), Color(0, 0, 0, 0.6))
		draw_string(ThemeDB.fallback_font, Vector2(cpos.x - tw * 0.5 + 3.0, cpos.y + 2.5),
			name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, tc)


func _species_stats() -> Array[String]:
	var result: Array[String] = []
	var stats: Dictionary = {}
	for sp: Dictionary in SPECIES_LIBRARY:
		stats[sp["name"] as String] = {"pop": 0, "evo": 0.0, "tiles": 0, "buildings": 0}
	for human in humans:
		if stats.has(human.species_name):
			stats[human.species_name]["pop"] += 1
			stats[human.species_name]["evo"] += human.evolution_score
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var cell := Vector2i(x, y)
			var owner := world_grid.get_owner(cell)
			if owner == "" or not stats.has(owner):
				continue
			stats[owner]["tiles"] += 1
			if world_grid.get_structure(cell) != "":
				stats[owner]["buildings"] += 1
	for sp_name: String in stats.keys():
		var pop: int = stats[sp_name]["pop"]
		var tiles: int = stats[sp_name]["tiles"]
		if pop == 0 and tiles == 0:
			continue
		var evo: float = stats[sp_name]["evo"] / maxf(float(pop), 1.0)
		var buildings: int = stats[sp_name]["buildings"]
		var tech: int = _species_tech.get(sp_name, 0) as int
		var line := "%s: %d pop  %d terr  %d edif  tec:%d  evo:%.1f" % [sp_name, pop, tiles, buildings, tech, evo]
		if pop == 0 and tiles > 0:
			line += "  [EXTINTO]"
		result.append(line)
	if result.is_empty():
		result.append("Sin entidades — usa tab Entidades")
	return result

func _find_territory_clusters() -> Array:
	var clusters: Array = []
	var visited := {}
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var start := Vector2i(x, y)
			if visited.has(start):
				continue
			var owner := world_grid.get_owner(start)
			if owner == "":
				visited[start] = true
				continue
			var queue: Array[Vector2i] = [start]
			var cells: Array[Vector2i] = []
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				if visited.has(c):
					continue
				if world_grid.get_owner(c) != owner:
					continue
				visited[c] = true
				cells.append(c)
				for d in dirs:
					var nb := c + d
					if world_grid.is_in_bounds(nb) and not visited.has(nb):
						queue.push_back(nb)
			if cells.size() < 18:
				continue
			var sx := 0; var sy := 0
			for cc: Vector2i in cells:
				sx += cc.x; sy += cc.y
			var centroid := Vector2(
				(float(sx) / cells.size() + 0.5) * TILE_SIZE,
				(float(sy) / cells.size() + 0.5) * TILE_SIZE
			)
			var seed := "%s:%d:%d" % [owner, cells[0].x, cells[0].y]
			clusters.append({"species": owner, "center": centroid, "seed": seed})
	return clusters

func _territory_name(seed: String, species: String) -> String:
	if _territory_names.has(seed):
		return _territory_names[seed]
	var h := (seed.hash() & 0x7FFFFFFF)
	var name := ""
	match species:
		"Humanos":
			var p: Array[String] = ["Al","Val","Ar","Bel","Cal","Mar","San","Tor","Ros","Cas","Del","Mont"]
			var s: Array[String] = ["oria","ania","ia","heim","grad","ton","burg","dor","vel","mar","zar"]
			name = p[h % p.size()] + s[(h >> 4) % s.size()]
		"Elfos":
			var p: Array[String] = ["Ael","Sil","Thal","Mith","Gal","Erel","Fae","Ith","Lor","Nym"]
			var s: Array[String] = ["ndir","ador","ithil","wen","dor","ath","ion","mel","riel","val"]
			name = p[h % p.size()] + s[(h >> 4) % s.size()]
		"Enanos":
			var p: Array[String] = ["Thor","Brom","Durn","Karg","Mor","Gor","Dur","Kaz","Brak","Orm"]
			var s: Array[String] = ["heim","dal","grad","dun","thak","rim","gor","kul","dok","bur"]
			name = p[h % p.size()] + s[(h >> 4) % s.size()]
		"Orcos":
			var p: Array[String] = ["Gro","Ug","Rak","Mor","Gul","Zag","Krak","Druk","Skul","Vruk"]
			var s: Array[String] = ["ash","gor","mak","thak","gruk","nash","zug","bul","kash","rok"]
			name = p[h % p.size()] + s[(h >> 4) % s.size()]
		_:
			name = species
	_territory_names[seed] = name
	return name

func _draw_camp(cx: float, cy: float, sc: Color) -> void:
	var tent := PackedVector2Array([
		Vector2(cx, cy - 5.5),
		Vector2(cx - 4.5, cy + 3.0),
		Vector2(cx + 4.5, cy + 3.0),
	])
	draw_colored_polygon(tent, sc.darkened(0.1))
	draw_polyline(tent, sc.lightened(0.4), 1.0)
	draw_line(Vector2(cx, cy - 5.5), Vector2(cx, cy + 3.0), sc.lightened(0.4), 1.0)
	draw_rect(Rect2(cx - 1.2, cy + 0.5, 2.4, 2.5), sc.darkened(0.5))

func _draw_village(cx: float, cy: float, sc: Color) -> void:
	draw_rect(Rect2(cx - 4.0, cy - 0.5, 8.0, 5.5), Color(0.90, 0.84, 0.70))
	var roof := PackedVector2Array([
		Vector2(cx, cy - 6.0),
		Vector2(cx - 5.0, cy - 0.5),
		Vector2(cx + 5.0, cy - 0.5),
	])
	draw_colored_polygon(roof, sc.lerp(Color(0.70, 0.25, 0.20), 0.5))
	draw_polyline(roof, sc.darkened(0.3), 1.0)
	draw_rect(Rect2(cx - 1.3, cy + 2.0, 2.6, 3.0), Color(0.48, 0.30, 0.12))
	draw_rect(Rect2(cx + 1.5, cy + 0.2, 2.0, 1.8), Color(0.75, 0.88, 1.0))

func _draw_town(cx: float, cy: float, sc: Color) -> void:
	var stone := Color(0.72, 0.68, 0.62)
	var dark  := Color(0.22, 0.18, 0.14)
	draw_rect(Rect2(cx - 6.0, cy - 1.5, 12.0, 7.5), stone)
	draw_rect(Rect2(cx - 2.5, cy - 7.5, 5.0, 8.5), stone.darkened(0.1))
	for bx: float in [-4.5, -2.5, -0.5, 1.5, 3.5]:
		draw_rect(Rect2(cx + bx, cy - 3.5, 1.5, 2.0), stone)
	for bx2: float in [-2.5, -0.5, 1.5]:
		draw_rect(Rect2(cx + bx2, cy - 9.5, 1.5, 2.0), stone.darkened(0.1))
	draw_rect(Rect2(cx - 2.0, cy + 2.5, 4.0, 5.0), dark)
	draw_line(Vector2(cx, cy - 7.5), Vector2(cx, cy - 11.5), Color(0.55, 0.55, 0.55), 1.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, cy - 11.5), Vector2(cx + 4.0, cy - 9.8), Vector2(cx, cy - 8.2)
	]), sc.lightened(0.3))

func _mouse_to_cell(screen_pos: Vector2) -> Vector2i:
	var vp_center := get_viewport_rect().size * 0.5
	var world_pos := camera.position + (screen_pos - vp_center) / camera.zoom.x
	return Vector2i(int(floor(world_pos.x / TILE_SIZE)), int(floor(world_pos.y / TILE_SIZE)))

func _refresh_hud() -> void:
	var stats_lines: Array[String] = []
	var stats_colors: Array[Color] = []
	var raw := _species_stats()
	for sp: Dictionary in SPECIES_LIBRARY:
		var n := sp["name"] as String
		for line in raw:
			if (line as String).begins_with(n):
				stats_lines.append(line)
				stats_colors.append((_species_colors.get(n, Color.WHITE) as Color).lightened(0.2))
				break
	var hero_lines: Array[String] = []
	var hero_colors: Array[Color] = []
	for h in humans:
		if h.is_hero:
			hero_lines.append("★ %s (%s) — %d batallas" % [h.hero_name, h.species_name, h.battles_won])
			hero_colors.append((_species_colors.get(h.species_name, Color.WHITE) as Color))
	hud.refresh(stats_lines, stats_colors, _chronicle, _chronicle_colors, hero_lines, hero_colors, world_year)

func _has_human_in_cell(cell: Vector2i) -> bool:
	for human in humans:
		if human.grid_position == cell:
			return true
	return false

func _shuffle_cells(items: Array[Vector2i]) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := items[i]; items[i] = items[j]; items[j] = tmp

func _shuffle_humans() -> void:
	for i in range(humans.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := humans[i]; humans[i] = humans[j]; humans[j] = tmp

func _cell_key(cell: Vector2i) -> String:
	return "%s:%s" % [cell.x, cell.y]

func _biome_color(biome: String) -> Color:
	match biome:
		"water":    return Color(0.20, 0.45, 0.85)
		"sand":     return Color(0.85, 0.80, 0.50)
		"grass":    return Color(0.30, 0.70, 0.30)
		"forest":   return Color(0.10, 0.45, 0.15)
		"mountain": return Color(0.45, 0.45, 0.45)
		_:          return Color.WHITE
