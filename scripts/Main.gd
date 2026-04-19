extends Node2D

const TILE_SIZE := 16
const WORLD_WIDTH := 96
const WORLD_HEIGHT := 54
const INITIAL_HUMANS := 20
const MAX_HUMANS := 200
const MOVE_TICK_SECONDS := 0.35
const BIOMES: Array[String] = ["water", "sand", "grass", "forest", "mountain", "snow", "jungle", "swamp"]
const MAP_PRESETS: Array[String] = ["random", "earth_like", "continent"]
const TIME_SPEEDS: Array[float] = [0.0, 1.0, 2.0, 5.0, 10.0]
const SPECIES_LIBRARY: Array[Dictionary] = [
	{
		"name": "Humanos", "color": Color(1.0, 0.92, 0.80),
		"preferred": ["grass", "sand", "forest"],
		"avoided":   ["mountain"],
		"combat": 1.0, "defense": 1.0, "evo_rate": 1.0,
	},
	{
		"name": "Elfos",   "color": Color(0.75, 0.95, 0.75),
		"preferred": ["forest"],
		"avoided":   ["sand", "mountain"],
		"combat": 0.7, "defense": 1.1, "evo_rate": 1.5,
	},
	{
		"name": "Enanos",  "color": Color(0.82, 0.75, 0.62),
		"preferred": ["mountain", "forest"],
		"avoided":   ["sand"],
		"combat": 1.1, "defense": 2.0, "evo_rate": 0.9,
	},
	{
		"name": "Orcos",   "color": Color(0.65, 0.80, 0.55),
		"preferred": ["sand", "grass", "mountain"],
		"avoided":   [],
		"combat": 1.8, "defense": 0.8, "evo_rate": 0.7,
	},
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
var _species_resources: Dictionary = {}
var _species_fleets: Dictionary = {}
var _species_armies: Dictionary = {}   # species -> int: land army count
var _species_pressures: Dictionary = {}
var _territory_names: Dictionary = {}
var _chronicle: Array[String] = []
var _chronicle_colors: Array[Color] = []
var _known_kingdoms: Dictionary = {}
var world_year := 0
var _active_advice: Dictionary = {}
var _next_advice_year := 16
var _sea_route_cache: Dictionary = {}

const TECH_THRESHOLDS: Array[float] = [100.0, 300.0, 700.0]
const CHRONICLE_MAX := 40
const FORTIFICATION_NAMES: Array[String] = ["sin defensa", "valla de madera", "muralla de piedra", "bastion de hierro"]
const RESOURCE_KEYS: Array[String] = ["food", "wood", "stone", "iron"]
const SAVE_FILE_PATH := "user://savegame.json"
const SPECIES_RELIGIONS: Dictionary = {
	"Humanos": "Fe Sagrada",
	"Elfos":   "Sendero Eterno",
	"Enanos":  "Forja Divina",
	"Orcos":   "Culto de Sangre",
}

var current_speed_idx := 1
var current_map_idx := 0
var mouse_painting := false
var last_painted_cell := Vector2i(-1, -1)
var _panning := false
var _pan_origin := Vector2.ZERO
var _cam_origin := Vector2.ZERO
var _trade_routes: Array[Dictionary] = []
var _relations: Dictionary = {}
var _war_pairs: Dictionary = {}
var _alliance_pairs: Dictionary = {}
var _battle_markers: Array[Dictionary] = []
var _settlement_cluster_cache: Array = []
var _territory_cluster_cache: Array = []

# ── Species special systems ───────────────────────────────────────────────────
# Dwarf Libro de Agravios: { "Enanos|Orcos" -> int grievance_points }
var _species_grievances: Dictionary = {}
# Forest tiles cleared per species key pair (used for elf deforestation detection)
# { "Elfos|Humanos" -> int tiles_cleared_this_era }
var _deforestation_log: Dictionary = {}
# Tick counter since last war per species (for orc inactivity system)
var _last_war_tick: Dictionary = {}
# Orc pending tribute demand: { "Orcos|Humanos" -> { "amount": float, "expires": int } }
var _tribute_pending: Dictionary = {}
# Track which era (every 200 ticks) we last fired species events
var _last_species_event_era: Dictionary = {}

const GameHUDScript = preload("res://scripts/GameHUD.gd")
const WorldEffectsScript = preload("res://scripts/WorldEffects.gd")
const SpeciesDataScript = preload("res://scripts/SpeciesData.gd")

var ui: GameUI
var hud: Node2D
var camera: Camera2D
var world_effects = WorldEffectsScript.new()
var _fire_cells: Dictionary = world_effects.fire_cells
var _effects: Array[Dictionary] = world_effects.effects

func _ready() -> void:
	rng.randomize()
	for sp: Dictionary in SPECIES_LIBRARY:
		var n := sp["name"] as String
		_species_colors[n]  = sp["color"] as Color
		_species_combat[n]  = sp["combat"] as float
		_species_defense[n] = sp["defense"] as float
		_species_tech[n]    = 0
		_species_research[n] = 0.0
		_species_resources[n] = _make_resource_stock()
		_species_fleets[n] = {"trade": 0, "war": 0}
		_species_armies[n] = 0
		_species_pressures[n] = _make_pressure_state()
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
	ui.chronicle_reply_submitted.connect(_on_chronicle_reply_submitted)
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
		_update_resources_and_fleets()
		_resolve_combat()
		_decay_dead_territories()
		_update_technology()
		world_effects.tick(world_grid, humans, rng)
		_update_trade_v2()
		_update_religions()
		_update_diplomacy()
		_tick_species_events()
		_resolve_expired_tributes()
		_update_chronicle_advice()
		_advance_battle_markers()
		ticked = true
	if ticked:
		queue_redraw()
		_refresh_hud()
	elif not _trade_routes.is_empty() or world_effects.has_active_visuals() or not _battle_markers.is_empty():
		queue_redraw()

	# Keep minimap camera indicator up to date every frame
	_update_minimap_cam_rect()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if ui != null and ui.is_reply_input_focused():
			return
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_regenerate_world()
			return
		if event.keycode == KEY_F5:
			_save_game()
			return
		if event.keycode == KEY_F9:
			_load_game()
			return
		if event.keycode == KEY_N and event.ctrl_pressed:
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
			# Track deforestation for elf sensitivity
			var old_biome := world_grid.get_biome(cell)
			if old_biome == "forest" and biome != "forest":
				_on_forest_tile_cleared(cell)
			world_grid.set_biome(cell, biome)
			_build_and_push_minimap()
			queue_redraw()
		"entities":
			if world_grid.is_walkable(cell) and not _has_human_in_cell(cell):
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
		_species_resources[n] = _make_resource_stock()
		_species_fleets[n] = {"trade": 0, "war": 0}
		_species_armies[n] = 0
		_species_pressures[n] = _make_pressure_state()
	_territory_names.clear()
	_chronicle.clear()
	_chronicle_colors.clear()
	_known_kingdoms.clear()
	world_effects.reset()
	_trade_routes.clear()
	_relations.clear()
	_war_pairs.clear()
	_alliance_pairs.clear()
	_battle_markers.clear()
	_active_advice.clear()
	_next_advice_year = 16
	_sea_route_cache.clear()
	_species_grievances.clear()
	_deforestation_log.clear()
	_last_war_tick.clear()
	_tribute_pending.clear()
	_last_species_event_era.clear()
	world_year = 0
	world_grid.generate(MAP_PRESETS[current_map_idx])
	# Initialize base relations from SpeciesData matrix
	for ii in SPECIES_LIBRARY.size():
		for jj in range(ii + 1, SPECIES_LIBRARY.size()):
			var sa := SPECIES_LIBRARY[ii]["name"] as String
			var sb := SPECIES_LIBRARY[jj]["name"] as String
			var base_rel := SpeciesDataScript.base_relation(sa, sb)
			if base_rel != 0.0:
				_set_relation(sa, sb, base_rel)
	# Init last war tick so orcs don't trigger immediately
	for sp: Dictionary in SPECIES_LIBRARY:
		_last_war_tick[sp["name"] as String] = 0
	_spawn_initial_humans()
	_settlement_cluster_cache = _find_settlement_clusters()
	_territory_cluster_cache  = _find_territory_clusters()
	ui.set_chronicle_prompt("", false)
	_build_and_push_minimap()
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
	var avoided: Array[String] = []
	if species.has("avoided"):
		avoided.assign(species["avoided"])
	var human := Human.new()
	human.setup(cell, TILE_SIZE, species["name"], species["color"], preferred,
		species["combat"] as float, species["defense"] as float, species["evo_rate"] as float, avoided)
	human.religion = SPECIES_RELIGIONS.get(species["name"] as String, "") as String
	world_grid.set_owner(cell, species["name"] as String)
	add_child(human)
	humans.append(human)

func _serialize_human(human: Human) -> Dictionary:
	return {
		"x": human.grid_position.x,
		"y": human.grid_position.y,
		"species": human.species_name,
		"evolution_score": human.evolution_score,
		"age_ticks": human.age_ticks,
		"battles_won": human.battles_won,
		"is_hero": human.is_hero,
		"hero_name": human.hero_name,
		"infected": human.infected,
		"on_fire": human.on_fire,
		"religion": human.religion,
	}

func _restore_human(state: Dictionary) -> void:
	var species_name := state.get("species", "Humanos") as String
	var species := _find_species(species_name)
	if species.is_empty():
		return
	var cell := Vector2i(state.get("x", 0) as int, state.get("y", 0) as int)
	if not world_grid.is_in_bounds(cell):
		return
	_spawn_human_at(cell, species)
	var human: Human = humans.back() as Human
	if human == null:
		return
	human.evolution_score = state.get("evolution_score", 0.0) as float
	human.age_ticks = state.get("age_ticks", 0) as int
	human.battles_won = state.get("battles_won", 0) as int
	human.is_hero = state.get("is_hero", false) as bool
	human.hero_name = state.get("hero_name", "") as String
	human.infected = state.get("infected", false) as bool
	human.on_fire = state.get("on_fire", false) as bool
	human.religion = state.get("religion", SPECIES_RELIGIONS.get(species_name, "") as String) as String

func _serialize_fire_cells() -> Array:
	var out: Array = []
	for cell: Vector2i in world_effects.fire_cells.keys():
		out.append({
			"x": cell.x,
			"y": cell.y,
			"age": world_effects.fire_cells[cell] as int,
		})
	return out

func _restore_fire_cells(data: Array) -> void:
	world_effects.fire_cells.clear()
	for entry in data:
		if entry is Dictionary:
			var d := entry as Dictionary
			var cell := Vector2i(d.get("x", 0) as int, d.get("y", 0) as int)
			world_effects.fire_cells[cell] = d.get("age", 0) as int

func _save_game() -> bool:
	var save_data := {
		"version": 1,
		"world_year": world_year,
		"current_speed_idx": current_speed_idx,
		"current_map_idx": current_map_idx,
		"move_tick_accumulator": move_tick_accumulator,
		"world_grid": world_grid.export_state(),
		"humans": [],
		"species_tech": _species_tech.duplicate(true),
		"species_research": _species_research.duplicate(true),
		"species_resources": _species_resources.duplicate(true),
		"species_fleets": _species_fleets.duplicate(true),
		"species_armies": _species_armies.duplicate(true),
		"species_pressures": _species_pressures.duplicate(true),
		"relations": _relations.duplicate(true),
		"war_pairs": _war_pairs.duplicate(true),
		"alliance_pairs": _alliance_pairs.duplicate(true),
		"chronicle": _chronicle.duplicate(true),
		"chronicle_colors": _chronicle_colors.duplicate(true),
		"territory_names": _territory_names.duplicate(true),
		"known_kingdoms": _known_kingdoms.duplicate(true),
		"species_grievances": _species_grievances.duplicate(true),
		"deforestation_log": _deforestation_log.duplicate(true),
		"last_war_tick": _last_war_tick.duplicate(true),
		"tribute_pending": _tribute_pending.duplicate(true),
		"last_species_event_era": _last_species_event_era.duplicate(true),
		"active_advice": _active_advice.duplicate(true),
		"next_advice_year": _next_advice_year,
		"fire_cells": _serialize_fire_cells(),
	}
	for human: Human in humans:
		(save_data["humans"] as Array).append(_serialize_human(human))
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		_log_event("Año %d: Error al guardar partida" % world_year, "")
		return false
	file.store_string(JSON.stringify(save_data))
	file.close()
	_log_event("Año %d: Partida guardada correctamente" % world_year, "")
	return true

func _load_game() -> bool:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		_log_event("Año %d: No existe una partida guardada" % world_year, "")
		return false
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file == null:
		_log_event("Año %d: No se pudo abrir la partida guardada" % world_year, "")
		return false
	var raw_text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		_log_event("Año %d: Savegame inválido" % world_year, "")
		return false
	var data := parsed as Dictionary
	var grid_data := data.get("world_grid", {}) as Dictionary
	if not world_grid.import_state(grid_data):
		_log_event("Año %d: Savegame incompatible con el tamaño del mundo" % world_year, "")
		return false

	for human in humans:
		human.queue_free()
	humans.clear()
	world_effects.reset()
	_trade_routes.clear()
	_battle_markers.clear()
	_sea_route_cache.clear()

	world_year = data.get("world_year", 0) as int
	move_tick_accumulator = data.get("move_tick_accumulator", 0.0) as float
	current_speed_idx = clampi(data.get("current_speed_idx", current_speed_idx) as int, 0, TIME_SPEEDS.size() - 1)
	current_map_idx = clampi(data.get("current_map_idx", current_map_idx) as int, 0, MAP_PRESETS.size() - 1)
	if ui != null:
		ui.set_speed_idx(current_speed_idx)

	_species_tech = (data.get("species_tech", _species_tech) as Dictionary).duplicate(true)
	_species_research = (data.get("species_research", _species_research) as Dictionary).duplicate(true)
	_species_resources = (data.get("species_resources", _species_resources) as Dictionary).duplicate(true)
	_species_fleets = (data.get("species_fleets", _species_fleets) as Dictionary).duplicate(true)
	_species_armies = (data.get("species_armies", _species_armies) as Dictionary).duplicate(true)
	_species_pressures = (data.get("species_pressures", _species_pressures) as Dictionary).duplicate(true)
	_relations = (data.get("relations", _relations) as Dictionary).duplicate(true)
	_war_pairs = (data.get("war_pairs", _war_pairs) as Dictionary).duplicate(true)
	_alliance_pairs = (data.get("alliance_pairs", _alliance_pairs) as Dictionary).duplicate(true)
	_chronicle = (data.get("chronicle", _chronicle) as Array).duplicate(true)
	_chronicle_colors = (data.get("chronicle_colors", _chronicle_colors) as Array).duplicate(true)
	_territory_names = (data.get("territory_names", _territory_names) as Dictionary).duplicate(true)
	_known_kingdoms = (data.get("known_kingdoms", _known_kingdoms) as Dictionary).duplicate(true)
	_species_grievances = (data.get("species_grievances", _species_grievances) as Dictionary).duplicate(true)
	_deforestation_log = (data.get("deforestation_log", _deforestation_log) as Dictionary).duplicate(true)
	_last_war_tick = (data.get("last_war_tick", _last_war_tick) as Dictionary).duplicate(true)
	_tribute_pending = (data.get("tribute_pending", _tribute_pending) as Dictionary).duplicate(true)
	_last_species_event_era = (data.get("last_species_event_era", _last_species_event_era) as Dictionary).duplicate(true)
	_active_advice = (data.get("active_advice", _active_advice) as Dictionary).duplicate(true)
	_next_advice_year = data.get("next_advice_year", _next_advice_year) as int

	var humans_data := data.get("humans", []) as Array
	for hdata in humans_data:
		if hdata is Dictionary:
			_restore_human(hdata as Dictionary)
	_restore_fire_cells(data.get("fire_cells", []) as Array)

	_build_and_push_minimap()
	_settlement_cluster_cache = _find_settlement_clusters()
	_territory_cluster_cache  = _find_territory_clusters()
	_refresh_hud()
	queue_redraw()
	_log_event("Año %d: Partida cargada correctamente" % world_year, "")
	return true

func _move_humans() -> void:
	var occupied := {}
	for human in humans:
		occupied[_cell_key(human.grid_position)] = true

	_shuffle_humans()
	for human in humans:
		occupied.erase(_cell_key(human.grid_position))
		var next := human.choose_next_cell(world_grid, rng, occupied)
		# Track deforestation: non-elf moving into a forest tile triggers elf sensitivity
		if human.species_name != "Elfos" and world_grid.get_biome(next) == "forest":
			var prev_owner := world_grid.get_owner(next)
			if prev_owner != human.species_name and prev_owner != "Elfos":
				_on_forest_tile_cleared(next)
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
			var pair_key := _diplomacy_key(human.species_name, target_owner)
			if _alliance_pairs.has(pair_key):
				continue
			var def_bonus: float = _species_defense.get(target_owner, 1.0)
			var fort_level := world_grid.get_fortification(target)
			var tech_atk := 1.25 if (_species_tech.get(human.species_name, 0) as int) >= 2 else 1.0
			var tech_def := 2.0  if (_species_tech.get(target_owner, 0) as int) >= 3 else 1.0
			var war_bonus := 1.5 if _war_pairs.has(pair_key) else 1.0
			var army_atk := 1.0 + float(_species_armies.get(human.species_name, 0) as int) * 0.06
			var army_def := 1.0 + float(_species_armies.get(target_owner, 0) as int) * 0.04
			# Habitat modifiers: attacker gets combat bonus on their biome, defender gets defense bonus
			var atk_biome := world_grid.get_biome(human.grid_position)
			var def_biome := world_grid.get_biome(target)
			var atk_hmod := SpeciesDataScript.habitat_mod(human.species_name, atk_biome)
			var def_hmod := SpeciesDataScript.habitat_mod(target_owner, def_biome)
			var habitat_atk := atk_hmod["combat"] as float
			var habitat_def := def_hmod["defense"] as float
			var chance := _conquest_chance(world_grid.get_structure(target), fort_level) * human.combat_bonus * tech_atk * war_bonus * army_atk * habitat_atk / (def_bonus * tech_def * army_def * habitat_def)
			var success := rng.randf() < chance
			if _war_pairs.has(pair_key) or fort_level > 0 or success:
				_record_battle_marker(human.grid_position, target, human.species_name, target_owner, success, fort_level)
			if success:
				world_grid.set_owner(target, human.species_name)
				human.battles_won += 1
				_set_relation(human.species_name, target_owner, _get_relation(human.species_name, target_owner) - 0.015)
				# Dwarf Libro de Agravios: track attacks against dwarves
				if target_owner == "Enanos":
					var g_key := _diplomacy_key("Enanos", human.species_name)
					_species_grievances[g_key] = (_species_grievances.get(g_key, 0) as int) + SpeciesDataScript.grievance_points("ataque_ciudad")
				# Track last war tick per species for orc inactivity
				_last_war_tick[human.species_name] = world_year
				_last_war_tick[target_owner] = world_year
				if human.battles_won == 5 and not human.is_hero:
					human.is_hero = true
					human.hero_name = _generate_hero_name(human.species_name, human.battles_won ^ human.age_ticks ^ human.grid_position.x)
					_log_event("Año %d: ¡%s se convirtió en leyenda de los %s!" % [world_year, human.hero_name, human.species_name], human.species_name)

func _conquest_chance(structure: String, fort_level: int) -> float:
	var base := 0.05
	match structure:
		"camp":    base = 0.03
		"village": base = 0.02
		"town":    base = 0.01
	return base / (1.0 + float(fort_level) * 0.75)

func _update_evolution() -> void:
	var to_remove: Array[Human] = []
	for human in humans:
		var cell := human.grid_position
		var biome := world_grid.get_biome(cell)
		# Apply habitat evo modifier from SpeciesData
		var hmod := SpeciesDataScript.habitat_mod(human.species_name, biome)
		human.evolution_score += (hmod["evo"] as float)
		human.update_evolution(biome)
		var prev_structure := world_grid.get_structure(cell)
		var prev_fort := world_grid.get_fortification(cell)
		world_grid.tick_presence(cell, human.species_name)
		var tech_level := _species_tech.get(human.species_name, 0) as int
		if tech_level >= 1:
			world_grid.tick_presence(cell, human.species_name)
		var new_structure := world_grid.get_structure(cell)
		var new_fort := world_grid.update_fortification(cell, human.species_name, tech_level)
		if new_fort > prev_fort and not _spend_resources(human.species_name, _fortification_cost(new_fort)):
			world_grid.set_fortification(cell, prev_fort)
			new_fort = prev_fort
		if new_structure != prev_structure:
			match new_structure:
				"camp":   _log_event("Año %d: Los %s establecieron un campamento" % [world_year, human.species_name], human.species_name)
				"village":_log_event("Año %d: Los %s fundaron una aldea" % [world_year, human.species_name], human.species_name)
				"town":   _log_event("Año %d: ¡Los %s erigieron una ciudad!" % [world_year, human.species_name], human.species_name)
		if new_fort > prev_fort:
			_log_event("Ano %d: Los %s levantaron %s" % [world_year, human.species_name, _fortification_name(new_fort)], human.species_name)
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
	_update_settlement_infrastructure()
	if humans.size() < MAX_HUMANS:
		for human in humans.duplicate():
			var repro_threshold := 10.0 if (_species_tech.get(human.species_name, 0) as int) >= 3 else 15.0
			var pressure_state := _species_pressures.get(human.species_name, _make_pressure_state()) as Dictionary
			if (pressure_state.get("starving", false) as bool) or (pressure_state.get("capacity_left", 0) as int) <= 0:
				continue
			if human.evolution_score > repro_threshold and humans.size() < MAX_HUMANS:
				var reproduction_chance := 0.01 * clampf(1.0 - (pressure_state.get("pressure", 0.0) as float) * 0.75, 0.2, 1.0)
				if rng.randf() < reproduction_chance:
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

func _event_flavor(species: String, text: String) -> String:
	var lower := text.to_lower()
	if lower.contains("guerra"):
		return "Los exploradores advierten que las fronteras tiemblan y los arsenales empiezan a vaciarse."
	if lower.contains("tregua") or lower.contains("alianza"):
		return "Los mercados respiran y los ancianos creen que el equilibrio puede durar unos pocos anos mas."
	if lower.contains("ciudad") or lower.contains("aldea") or lower.contains("campamento"):
		return "Nuevos hogares, talleres y hornos cambian el pulso del territorio."
	if lower.contains("mercante") or lower.contains("ruta comercial") or lower.contains("puerto"):
		return "La riqueza depende ahora de mantener costas seguras y mares abiertos."
	if lower.contains("hambre") or lower.contains("crisis") or lower.contains("colapsar"):
		return "Los graneros se vacian y la gente exige decisiones antes de abandonar las calles."
	if lower.contains("tecnolog"):
		return "Los artesanos convierten ideas en herramientas y eso altera el equilibrio con sus vecinos."
	if lower.contains("defensa") or lower.contains("muralla") or lower.contains("valla") or lower.contains("bastion"):
		return "Cada piedra levantada protege vidas, pero tambien consume recursos que faltan en otros barrios."
	if species != "":
		return "Los cronistas de los %s juran que este cambio marcara una nueva etapa para su pueblo." % species
	return "Los cronistas anotan el suceso mientras el mundo sigue girando sin esperar respuesta."

func _log_event(text: String, species: String, detail: String = "") -> void:
	var entry := text
	var extra := detail if detail != "" else _event_flavor(species, text)
	if extra != "":
		entry += " " + extra
	_chronicle.append(entry)
	_chronicle_colors.append(_species_colors.get(species, Color(0.8, 0.8, 0.8)) as Color)
	if _chronicle.size() > CHRONICLE_MAX:
		_chronicle.pop_front()
		_chronicle_colors.pop_front()

func _fortification_name(level: int) -> String:
	return FORTIFICATION_NAMES[clampi(level, 0, FORTIFICATION_NAMES.size() - 1)]

func _offer_advice(topic: String, species: String, prompt: String, options: Array[String], expires_in: int = 18) -> void:
	if not _active_advice.is_empty():
		return
	_active_advice = {
		"topic": topic,
		"species": species,
		"prompt": prompt,
		"options": options,
		"expires": world_year + expires_in,
	}
	_next_advice_year = world_year + expires_in + 24
	_log_event("Ano %d: El consejo de los %s pide audiencia" % [world_year, species], species, prompt)

func _update_chronicle_advice() -> void:
	if not _active_advice.is_empty():
		if world_year >= (_active_advice.get("expires", world_year + 1) as int):
			var sp := _active_advice.get("species", "") as String
			_log_event("Ano %d: Nadie respondio al consejo de los %s" % [world_year, sp], sp, "El mundo siguio avanzando y las decisiones quedaron en manos de la inercia.")
			_active_advice.clear()
		return
	if world_year < _next_advice_year:
		return
	for sp: String in _species_pressures.keys():
		var state := _species_pressures.get(sp, {}) as Dictionary
		if (state.get("starving", false) as bool) and (state.get("capacity", 0) as int) > 0:
			_offer_advice("food", sp, "Falta comida en %s. Elige una respuesta." % sp, ["Grano", "Racion", "Migrar"])
			return
	for key: String in _war_pairs.keys():
		var parts := key.split("|")
		if parts.size() == 2:
			_offer_advice("war", parts[0], "La guerra crece entre %s y %s. Elige la postura del consejo." % [parts[0], parts[1]], ["Muro", "Paz", "Saqueo"])
			return
	for species: String in _species_fleets.keys():
		var fleet := _fleet_state(species)
		var ports := _gather_ports().get(species, []) as Array
		if (fleet.get("trade", 0) as int) > 0 and ports.size() >= 2:
			var sea_routes := 0
			for route: Dictionary in _trade_routes:
				if route.get("mode", "land") == "sea" and route.get("species", "") == species:
					sea_routes += 1
			if sea_routes == 0:
				_offer_advice("port", species, "Los puertos de %s quedaron aislados. Elige la prioridad." % species, ["Puerto", "Costa", "Flota"])
				return

func _on_chronicle_reply_submitted(text: String) -> void:
	if _active_advice.is_empty():
		_log_event("Ano %d: Llegaron palabras tardias al salon del consejo" % world_year, "", "El mensaje no encontro una consulta abierta, pero los escribas lo archivaron igualmente.")
		return
	var answer := text.to_lower().strip_edges()
	var topic := _active_advice.get("topic", "") as String
	var species := _active_advice.get("species", "") as String
	var resolved := false
	match topic:
		"food":
			if answer.contains("grano") or answer.contains("comida") or answer.contains("campo"):
				var stock := _resource_stock(species)
				stock["food"] = (stock.get("food", 0.0) as float) + 14.0
				_log_event("Ano %d: El consejo ordena sembrar mas para los %s" % [world_year, species], species, "Se abren nuevos graneros y los campesinos reciben prioridad sobre otras obras.")
				resolved = true
			elif answer.contains("racion"):
				for human in humans:
					if human.species_name == species:
						human.evolution_score += 1.2
				_log_event("Ano %d: Los %s aceptan racionamiento" % [world_year, species], species, "La disciplina evita un colapso inmediato, aunque el pueblo murmura en las plazas.")
				resolved = true
			elif answer.contains("migr"):
				for human in humans:
					if human.species_name == species:
						human.evolution_score += 0.5
				_log_event("Ano %d: Los %s impulsan migraciones hacia nuevas tierras" % [world_year, species], species, "Las familias buscan valles menos saturados y el centro urbano gana un respiro.")
				resolved = true
		"war":
			if answer.contains("muro") or answer.contains("defen"):
				var stock := _resource_stock(species)
				stock["stone"] = (stock.get("stone", 0.0) as float) + 8.0
				stock["wood"] = (stock.get("wood", 0.0) as float) + 6.0
				_log_event("Ano %d: Los %s priorizan murallas y reservas" % [world_year, species], species, "Los maestros de obra reciben recursos extra y las ciudades se preparan para un asedio largo.")
				resolved = true
			elif answer.contains("paz") or answer.contains("trato"):
				for key: String in _war_pairs.keys():
					if key.contains(species):
						var parts := key.split("|")
						if parts.size() == 2:
							_set_relation(parts[0], parts[1], _get_relation(parts[0], parts[1]) + 0.20)
				_log_event("Ano %d: Los %s envian emisarios de paz" % [world_year, species], species, "No garantiza tregua inmediata, pero enfria el deseo de seguir perdiendo sangre.")
				resolved = true
			elif answer.contains("saque") or answer.contains("flota"):
				var fleet := _fleet_state(species)
				fleet["war"] = (fleet.get("war", 0) as int) + 1
				_log_event("Ano %d: Los %s redoblan la presion militar" % [world_year, species], species, "Los capitanes reciben permiso para hostigar rutas enemigas y acelerar la guerra.")
				resolved = true
		"port":
			if answer.contains("puerto") or answer.contains("muelle"):
				var stock := _resource_stock(species)
				stock["wood"] = (stock.get("wood", 0.0) as float) + 10.0
				_log_event("Ano %d: Los %s expanden sus muelles" % [world_year, species], species, "Los carpinteros buscan una costa mejor conectada para abrir la siguiente ruta comercial.")
				resolved = true
			elif answer.contains("costa") or answer.contains("territ"):
				for human in humans:
					if human.species_name == species:
						human.evolution_score += 0.8
				_log_event("Ano %d: Los %s son empujados hacia la costa" % [world_year, species], species, "Las patrullas buscan ensenadas y deltas donde fundar puertos menos encerrados.")
				resolved = true
			elif answer.contains("flota") or answer.contains("barco"):
				var fleet := _fleet_state(species)
				fleet["trade"] = (fleet.get("trade", 0) as int) + 1
				_log_event("Ano %d: Los %s construyen naves para explorar nuevas rutas" % [world_year, species], species, "Los astilleros prueban caminos mas largos en busca de agua abierta y puertos aliados.")
				resolved = true
	if not resolved:
		_log_event("Ano %d: El consejo recibe una respuesta ambigua: '%s'" % [world_year, text], species, "Los asesores toman nota, pero la orden no cambia el rumbo de inmediato.")
	_active_advice.clear()

func _record_battle_marker(from_cell: Vector2i, to_cell: Vector2i, attacker: String, defender: String, success: bool, fort_level: int) -> void:
	_battle_markers.append({
		"from": from_cell,
		"to": to_cell,
		"attacker": attacker,
		"defender": defender,
		"success": success,
		"fort": fort_level,
		"age": 0,
		"max_age": 12,
	})
	if _battle_markers.size() > 90:
		_battle_markers.pop_front()

func _advance_battle_markers() -> void:
	var to_remove: Array[int] = []
	for i in _battle_markers.size():
		_battle_markers[i]["age"] = (_battle_markers[i]["age"] as int) + 1
		if (_battle_markers[i]["age"] as int) >= (_battle_markers[i]["max_age"] as int):
			to_remove.append(i)
	for i in range(to_remove.size() - 1, -1, -1):
		_battle_markers.remove_at(to_remove[i])

func _make_resource_stock() -> Dictionary:
	return {
		"food": 20.0,
		"wood": 12.0,
		"stone": 4.0,
		"iron": 0.0,
	}

func _make_pressure_state() -> Dictionary:
	return {
		"capacity": 0,
		"capacity_left": 0,
		"food_balance": 0.0,
		"food": 0.0,
		"pressure": 0.0,
		"starving": false,
		"overcrowding": 0,
	}

func _resource_stock(species: String) -> Dictionary:
	if not _species_resources.has(species):
		_species_resources[species] = _make_resource_stock()
	return _species_resources[species] as Dictionary

func _fleet_state(species: String) -> Dictionary:
	if not _species_fleets.has(species):
		_species_fleets[species] = {"trade": 0, "war": 0}
	return _species_fleets[species] as Dictionary

func _has_resources(species: String, cost: Dictionary) -> bool:
	var stock := _resource_stock(species)
	for key: String in cost.keys():
		if (stock.get(key, 0.0) as float) < (cost[key] as float):
			return false
	return true

func _spend_resources(species: String, cost: Dictionary) -> bool:
	if not _has_resources(species, cost):
		return false
	var stock := _resource_stock(species)
	for key: String in cost.keys():
		stock[key] = (stock.get(key, 0.0) as float) - (cost[key] as float)
	return true

func _fortification_cost(level: int) -> Dictionary:
	match level:
		1: return {"wood": 8.0, "stone": 0.0, "iron": 0.0, "food": 0.0}
		2: return {"wood": 4.0, "stone": 10.0, "iron": 0.0, "food": 0.0}
		3: return {"wood": 2.0, "stone": 8.0, "iron": 8.0, "food": 0.0}
		_: return {}

func _ship_cost(mode: String) -> Dictionary:
	if mode == "war":
		return {"wood": 14.0, "stone": 0.0, "iron": 6.0, "food": 2.0}
	return {"wood": 10.0, "stone": 0.0, "iron": 2.0, "food": 2.0}

func _army_cost(tech: int) -> Dictionary:
	# Higher tech = more iron required, less stone
	return {"wood": 0.0, "stone": maxf(4.0 - float(tech), 1.0), "iron": float(tech) * 1.5, "food": 2.0}

func _settlement_capacity(data: Dictionary, tech: int) -> int:
	var capacity := 6
	capacity += (data.get("camp", 0) as int) * 6
	capacity += (data.get("village", 0) as int) * 14
	capacity += (data.get("town", 0) as int) * 28
	capacity += (data.get("housing", 0) as int) * 5
	capacity += (data.get("farm", 0) as int) * 2
	capacity += (data.get("dock", 0) as int) * 3
	capacity += tech * 4
	return capacity

func _downgraded_structure(structure: String) -> String:
	match structure:
		"town":
			return "village"
		"village":
			return "camp"
		"camp":
			return ""
	return structure

func _improvement_counts() -> Dictionary:
	var counts: Dictionary = {}
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var cell := Vector2i(x, y)
			var owner := world_grid.get_owner(cell)
			if owner == "":
				continue
			if not counts.has(owner):
				counts[owner] = {"farm": 0, "mine": 0, "housing": 0, "dock": 0, "forest": 0, "camp": 0, "town": 0, "village": 0}
			var c: Dictionary = counts[owner]
			var improvement := world_grid.get_improvement(cell)
			if improvement != "":
				c[improvement] = (c.get(improvement, 0) as int) + 1
			var biome := world_grid.get_biome(cell)
			if biome == "forest":
				c["forest"] = (c.get("forest", 0) as int) + 1
			match world_grid.get_structure(cell):
				"camp":
					c["camp"] = (c.get("camp", 0) as int) + 1
				"town":
					c["town"] = (c.get("town", 0) as int) + 1
				"village":
					c["village"] = (c.get("village", 0) as int) + 1
	return counts

func _species_population_counts() -> Dictionary:
	var counts: Dictionary = {}
	for human in humans:
		counts[human.species_name] = (counts.get(human.species_name, 0) as int) + 1
	return counts

func _apply_famine_losses(species: String, count: int) -> void:
	var losses := 0
	var chosen := {}
	for _i in range(count):
		var target: Human = null
		var worst_score := 999999.0
		for human in humans:
			if human.species_name != species:
				continue
			if chosen.has(human):
				continue
			var score := human.evolution_score + float(human.age_ticks) * 0.004
			if score < worst_score:
				worst_score = score
				target = human
		if target == null:
			break
		chosen[target] = true
		target.evolution_score = -25.0
		losses += 1
	if losses > 0:
		_log_event("Ano %d: El hambre golpea a los %s y mueren %d habitantes" % [world_year, species, losses], species)

func _apply_settlement_collapse(species: String, severity: float) -> bool:
	var best_improvement := Vector2i(-1, -1)
	var best_improvement_score := -1
	var best_fort := Vector2i(-1, -1)
	var best_fort_score := -1
	var best_structure := Vector2i(-1, -1)
	var best_structure_score := -1
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var cell := Vector2i(x, y)
			if world_grid.get_owner(cell) != species:
				continue
			var structure := world_grid.get_structure(cell)
			var improvement := world_grid.get_improvement(cell)
			var fort := world_grid.get_fortification(cell)
			if improvement != "":
				var improvement_score := 0
				match improvement:
					"farm":
						improvement_score = 5
					"housing":
						improvement_score = 4
					"dock":
						improvement_score = 3
					"mine":
						improvement_score = 2
					_:
						improvement_score = 1
				if structure == "":
					improvement_score += 2
				if improvement_score > best_improvement_score:
					best_improvement_score = improvement_score
					best_improvement = cell
			if fort > 0:
				var fort_score := fort * 2
				if structure == "":
					fort_score += 1
				if fort_score > best_fort_score:
					best_fort_score = fort_score
					best_fort = cell
			if structure != "":
				var structure_score := 0
				match structure:
					"town":
						structure_score = 3
					"village":
						structure_score = 2
					"camp":
						structure_score = 1
				if structure_score > best_structure_score:
					best_structure_score = structure_score
					best_structure = cell

	if best_improvement != Vector2i(-1, -1):
		var old_improvement := world_grid.get_improvement(best_improvement)
		world_grid.set_improvement(best_improvement, "")
		_log_event("Ano %d: La crisis de los %s arruina sus %s" % [world_year, species, old_improvement], species)
		return true
	if best_fort != Vector2i(-1, -1):
		var new_fort := maxi(world_grid.get_fortification(best_fort) - 1, 0)
		world_grid.set_fortification(best_fort, new_fort)
		_log_event("Ano %d: Los %s abandonan parte de sus defensas" % [world_year, species], species)
		return true
	if severity >= 0.95 and best_structure != Vector2i(-1, -1):
		var old_structure := world_grid.get_structure(best_structure)
		world_grid.set_structure(best_structure, _downgraded_structure(old_structure))
		world_grid.set_fortification(best_structure, maxi(world_grid.get_fortification(best_structure) - 1, 0))
		_log_event("Ano %d: Los %s ven colapsar un %s" % [world_year, species, old_structure], species)
		return true
	return false

func _apply_population_pressure(species: String, pop: int, capacity: int, food_balance: float, food_stock: float, pressure: float) -> void:
	var state := _species_pressures.get(species, _make_pressure_state()) as Dictionary
	var overcrowding := maxi(pop - capacity, 0)
	var starving := food_stock < maxf(4.0, float(pop) * 0.12) or food_balance < -1.5
	state["capacity"] = capacity
	state["capacity_left"] = maxi(capacity - pop, 0)
	state["food_balance"] = food_balance
	state["food"] = food_stock
	state["pressure"] = pressure
	state["starving"] = starving
	state["overcrowding"] = overcrowding
	_species_pressures[species] = state
	if pop <= 0:
		return

	var evo_penalty := pressure * 0.025 + float(overcrowding) * 0.002
	if starving:
		evo_penalty += 0.04
	for human in humans:
		if human.species_name == species:
			human.evolution_score -= evo_penalty

	if starving and food_stock <= 1.0 and world_year % 6 == 0:
		_apply_famine_losses(species, 2 if pressure >= 0.9 and pop >= 8 else 1)
	if pressure >= 0.55 and world_year % 10 == 0:
		_apply_settlement_collapse(species, pressure)

func _update_resources_and_fleets() -> void:
	var improvements := _improvement_counts()
	var pops := _species_population_counts()
	var ports := _gather_ports()
	for sp: Dictionary in SPECIES_LIBRARY:
		var name := sp["name"] as String
		var stock := _resource_stock(name)
		var fleet := _fleet_state(name)
		var data: Dictionary = improvements.get(name, {"farm": 0, "mine": 0, "housing": 0, "dock": 0, "forest": 0, "camp": 0, "town": 0, "village": 0})
		var pop := pops.get(name, 0) as int
		var tech := _species_tech.get(name, 0) as int
		var food_balance := float(data.get("farm", 0) as int) * 1.6 + float(data.get("dock", 0) as int) * 0.25 - float(pop) * 0.22
		stock["food"] = (stock.get("food", 0.0) as float) + food_balance
		stock["wood"] = (stock.get("wood", 0.0) as float) + float(data.get("forest", 0) as int) * 0.12 + float(data.get("housing", 0) as int) * 0.05 + float(data.get("dock", 0) as int) * 0.08
		stock["stone"] = (stock.get("stone", 0.0) as float) + float(data.get("mine", 0) as int) * 0.55
		if tech >= 2:
			stock["iron"] = (stock.get("iron", 0.0) as float) + float(data.get("mine", 0) as int) * 0.28
		else:
			stock["iron"] = (stock.get("iron", 0.0) as float) + float(data.get("mine", 0) as int) * 0.08
		for key: String in RESOURCE_KEYS:
			stock[key] = clampf(stock.get(key, 0.0) as float, 0.0, 999.0)
		var capacity := _settlement_capacity(data, tech)
		var overcrowding := maxi(pop - capacity, 0)
		var pressure := clampf(float(overcrowding) / maxf(float(capacity), 1.0) + maxf(-food_balance, 0.0) * 0.12 + maxf(3.0 - (stock.get("food", 0.0) as float), 0.0) * 0.08, 0.0, 1.4)
		_apply_population_pressure(name, pop, capacity, food_balance, stock.get("food", 0.0) as float, pressure)
		var port_count := (ports.get(name, []) as Array).size()
		var desired_trade := mini(port_count, 1 + tech)
		while (fleet.get("trade", 0) as int) < desired_trade and _spend_resources(name, _ship_cost("trade")):
			fleet["trade"] = (fleet.get("trade", 0) as int) + 1
			_log_event("Ano %d: Los %s construyeron un mercante" % [world_year, name], name)
		var in_war := false
		for key: String in _war_pairs.keys():
			if key.contains(name):
				in_war = true
				break
		var desired_war := mini(port_count, 1 + tech) if in_war else 0
		while (fleet.get("war", 0) as int) < desired_war and _spend_resources(name, _ship_cost("war")):
			fleet["war"] = (fleet.get("war", 0) as int) + 1
			_log_event("Ano %d: Los %s botaron una flota de guerra" % [world_year, name], name)
		if not in_war:
			fleet["war"] = maxi((fleet.get("war", 0) as int) - 1, 0)
		# ── Land armies (tech >= 1) ──────────────────────────────────────────
		if tech >= 1:
			var army := _species_armies.get(name, 0) as int
			# Army upkeep: each unit eats 0.30 food per tick
			var upkeep := float(army) * 0.30
			stock["food"] = maxf((stock.get("food", 0.0) as float) - upkeep, 0.0)
			if (stock.get("food", 0.0) as float) <= 0.0 and army > 0:
				army = maxi(army - 1, 0)
				_species_armies[name] = army
			# Build new units if resources allow
			var desired_army := mini(2 + tech * 2 + (2 if in_war else 0), 10)
			while army < desired_army and _spend_resources(name, _army_cost(tech)):
				army += 1
				_species_armies[name] = army
				_log_event("Año %d: Los %s reclutaron un ejército" % [world_year, name], name)
		else:
			_species_armies[name] = 0

func _has_adjacent_biome(cell: Vector2i, biome: String) -> bool:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for dir in dirs:
		if world_grid.get_biome(cell + dir) == biome:
			return true
	return false

func _adjacent_water_cell(cell: Vector2i) -> Vector2i:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for dir in dirs:
		var next := cell + dir
		if world_grid.get_biome(next) == "water":
			return next
	return Vector2i(-1, -1)

func _nearest_settlement_core(cell: Vector2i, owner: String) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 999
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var candidate := cell + Vector2i(dx, dy)
			if world_grid.get_owner(candidate) != owner:
				continue
			var structure := world_grid.get_structure(candidate)
			if structure == "":
				continue
			var score := 0
			match structure:
				"town": score = 0
				"village": score = 1
				"camp": score = 2
				_: score = 3
			var distance := absi(dx) + absi(dy) + score
			if distance < best_distance:
				best_distance = distance
				best = {
					"cell": candidate,
					"structure": structure,
					"distance": absi(dx) + absi(dy),
				}
	return best

func _planned_improvement(cell: Vector2i, owner: String) -> String:
	var nearby := _nearest_settlement_core(cell, owner)
	if nearby.is_empty():
		return ""
	var structure := world_grid.get_structure(cell)
	var core_structure := nearby["structure"] as String
	var distance := nearby["distance"] as int
	var tech_level := _species_tech.get(owner, 0) as int
	var biome := world_grid.get_biome(cell)
	var near_water := _has_adjacent_biome(cell, "water")
	var near_mountain := _has_adjacent_biome(cell, "mountain")

	if structure == "town" and near_water and tech_level >= 1:
		return "dock"
	if structure in ["village", "town"] and near_mountain and tech_level >= 1:
		return "mine"
	if structure != "":
		return ""

	if core_structure == "town" and near_water and distance <= 1 and tech_level >= 1:
		return "dock"
	# Dwarves can mine in forest tiles too (not just mountain-adjacent)
	var can_mine_here := near_mountain or (SpeciesDataScript.mine_non_mountain_allowed(owner) and biome == "forest")
	if can_mine_here and distance <= 2 and tech_level >= 1:
		return "mine"
	# Elves grow food in forests; others need grass/sand
	var can_farm := (biome == "grass" or biome == "sand") or (owner == "Elfos" and biome == "forest")
	if can_farm and distance <= 2:
		return "farm"
	if core_structure in ["village", "town"] and distance <= 1:
		return "housing"
	return ""

func _update_settlement_infrastructure() -> void:
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var cell := Vector2i(x, y)
			var owner := world_grid.get_owner(cell)
			if owner == "":
				world_grid.set_improvement(cell, "")
				continue
			world_grid.set_improvement(cell, _planned_improvement(cell, owner))

func _gather_ports() -> Dictionary:
	var ports: Dictionary = {}
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var cell := Vector2i(x, y)
			if world_grid.get_improvement(cell) != "dock":
				continue
			var owner := world_grid.get_owner(cell)
			var water_cell := _adjacent_water_cell(cell)
			if owner == "" or water_cell == Vector2i(-1, -1):
				continue
			if not ports.has(owner):
				ports[owner] = []
			(ports[owner] as Array).append({"land": cell, "water": water_cell})
	return ports

func _sea_path_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return "%d:%d|%d:%d" % [a.x, a.y, b.x, b.y]
	return "%d:%d|%d:%d" % [b.x, b.y, a.x, a.y]

func _find_sea_path(start: Vector2i, goal: Vector2i, max_steps: int = 96) -> Array[Vector2i]:
	if start == goal:
		return [start]
	if world_grid.get_biome(start) != "water" or world_grid.get_biome(goal) != "water":
		return []
	var cache_key := _sea_path_key(start, goal)
	if _sea_route_cache.has(cache_key):
		var cached: Array[Vector2i] = []
		cached.assign(_sea_route_cache[cache_key] as Array)
		return cached
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var queue: Array[Vector2i] = [start]
	var visited := {start: true}
	var came_from := {}
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current.distance_to(start) > float(max_steps):
			continue
		for dir in dirs:
			var next := current + dir
			if not world_grid.is_in_bounds(next):
				continue
			if visited.has(next):
				continue
			if world_grid.get_biome(next) != "water":
				continue
			visited[next] = true
			came_from[next] = current
			if next == goal:
				var path: Array[Vector2i] = [goal]
				var step := goal
				while came_from.has(step):
					step = came_from[step] as Vector2i
					path.push_front(step)
					if step == start:
						break
				_sea_route_cache[cache_key] = path.duplicate()
				return path
			queue.push_back(next)
	_sea_route_cache[cache_key] = []
	return []

func _best_reachable_port_pair(port_list: Array, max_steps: int = 96) -> Dictionary:
	var best: Dictionary = {}
	var best_len := 999999
	for i in port_list.size():
		for j in range(i + 1, port_list.size()):
			var from_port := port_list[i] as Dictionary
			var to_port := port_list[j] as Dictionary
			var path := _find_sea_path(from_port["water"] as Vector2i, to_port["water"] as Vector2i, max_steps)
			if path.is_empty():
				continue
			if path.size() < best_len:
				best_len = path.size()
				best = {
					"from": from_port,
					"to": to_port,
					"path": path,
				}
	return best

func _best_reachable_enemy_ports(a_ports: Array, b_ports: Array, max_steps: int = 120) -> Dictionary:
	var best: Dictionary = {}
	var best_len := 999999
	for pa: Dictionary in a_ports:
		for pb: Dictionary in b_ports:
			var path := _find_sea_path(pa["water"] as Vector2i, pb["water"] as Vector2i, max_steps)
			if path.is_empty():
				continue
			if path.size() < best_len:
				best_len = path.size()
				best = {"from": pa, "to": pb, "path": path}
	return best

func _append_trade_route_if_missing(routes: Array[Dictionary], route: Dictionary) -> void:
	for existing: Dictionary in routes:
		if existing["mode"] != route["mode"]:
			continue
		if (existing["from"] == route["from"] and existing["to"] == route["to"]) or (existing["from"] == route["to"] and existing["to"] == route["from"]):
			return
	routes.append(route)

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
		var base_gain := research_gain[sp_name] as float
		# Apply per-species tech speed multiplier
		var speed_mult := SpeciesDataScript.tech_speed_mult(sp_name)
		# Orcs (and others) get bonus research during wars
		var in_war := false
		for key: String in _war_pairs.keys():
			if key.contains(sp_name):
				in_war = true
				break
		if in_war:
			speed_mult += SpeciesDataScript.tech_war_bonus(sp_name)
		_species_research[sp_name] = (_species_research.get(sp_name, 0.0) as float) + base_gain * speed_mult
		var lvl: int = _species_tech.get(sp_name, 0) as int
		if lvl < TECH_THRESHOLDS.size() and (_species_research[sp_name] as float) >= TECH_THRESHOLDS[lvl]:
			_species_tech[sp_name] = lvl + 1
			_log_event("Año %d: Los %s alcanzaron tecnología nivel %d" % [world_year, sp_name, lvl + 1], sp_name)

func _diplomacy_key(a: String, b: String) -> String:
	if a < b: return a + "|" + b
	return b + "|" + a

func _get_relation(a: String, b: String) -> float:
	return _relations.get(_diplomacy_key(a, b), 0.0) as float

func _set_relation(a: String, b: String, val: float) -> void:
	_relations[_diplomacy_key(a, b)] = clampf(val, -1.0, 1.0)

func _dominant_religion(species: String) -> String:
	var counts: Dictionary = {}
	for h in humans:
		if h.species_name == species and h.religion != "":
			counts[h.religion] = (counts.get(h.religion, 0) as int) + 1
	var best := ""
	var best_n := 0
	for r: String in counts.keys():
		if (counts[r] as int) > best_n:
			best_n = counts[r] as int
			best = r
	return best

func _dominant_religions_for_species(species_list: Array) -> Dictionary:
	var species_set: Dictionary = {}
	for sp in species_list:
		species_set[sp as String] = true
	var counters: Dictionary = {}
	for h in humans:
		if h.religion == "" or not species_set.has(h.species_name):
			continue
		if not counters.has(h.species_name):
			counters[h.species_name] = {}
		var rel_counts: Dictionary = counters[h.species_name] as Dictionary
		rel_counts[h.religion] = (rel_counts.get(h.religion, 0) as int) + 1
	var dominant: Dictionary = {}
	for sp in species_list:
		var species := sp as String
		var rel_counts := counters.get(species, {}) as Dictionary
		var best_rel := ""
		var best_n := 0
		for r: String in rel_counts.keys():
			var n := rel_counts[r] as int
			if n > best_n:
				best_n = n
				best_rel = r
		dominant[species] = best_rel
	return dominant

func _update_religions() -> void:
	for human in humans:
		for other in humans:
			if other == human or other.species_name == human.species_name:
				continue
			if (human.grid_position - other.grid_position).length() <= 1.5:
				if rng.randf() < 0.0004:
					human.religion = other.religion

	if world_year % 80 != 0:
		return
	var species_pops: Dictionary = {}
	var species_rel_counts: Dictionary = {}
	for h in humans:
		if h.religion == "":
			continue
		if not species_pops.has(h.species_name):
			species_pops[h.species_name] = 0
			species_rel_counts[h.species_name] = {}
		species_pops[h.species_name] = (species_pops[h.species_name] as int) + 1
		var d: Dictionary = species_rel_counts[h.species_name]
		d[h.religion] = (d.get(h.religion, 0) as int) + 1
	for sp: String in species_rel_counts.keys():
		var total: int = species_pops[sp] as int
		if total < 3:
			continue
		var d: Dictionary = species_rel_counts[sp]
		for r: String in d.keys():
			var pct := float(d[r] as int) / float(total)
			var native := SPECIES_RELIGIONS.get(sp, "") as String
			if pct > 0.60 and r != native:
				_log_event("Año %d: Los %s abrazan %s" % [world_year, sp, r], sp)

func _update_diplomacy() -> void:
	var living: Dictionary = {}
	for h in humans:
		living[h.species_name] = true
	var sp_list: Array = living.keys()
	var dominant_religions := _dominant_religions_for_species(sp_list)
	var cross_trade_pairs: Dictionary = {}
	for r: Dictionary in _trade_routes:
		if r.get("mode", "") != "cross":
			continue
		var rsa := r.get("species", "") as String
		var rsb := r.get("partner", "") as String
		if rsa == "" or rsb == "":
			continue
		cross_trade_pairs[_diplomacy_key(rsa, rsb)] = true

	# ── Passive grievance decay (dwarves) ─────────────────────────────────────
	if world_year % 100 == 0:
		var keys_to_update: Array = _species_grievances.keys().duplicate()
		for g_key: String in keys_to_update:
			var g := _species_grievances.get(g_key, 0) as int
			if g > 0:
				_species_grievances[g_key] = maxi(g - 1, 0)

	for i in sp_list.size():
		for j in range(i + 1, sp_list.size()):
			var a: String = sp_list[i]
			var b: String = sp_list[j]
			var key := _diplomacy_key(a, b)
			var rel := _get_relation(a, b)

			if not _war_pairs.has(key):
				rel += 0.0008
			else:
				rel -= 0.001

			var dom_a := dominant_religions.get(a, "") as String
			var dom_b := dominant_religions.get(b, "") as String
			if dom_a == dom_b and dom_a != "":
				rel += 0.002

			# ── Human trade diplomacy bonus ────────────────────────────────────
			# Humans improve relations faster with active cross-species trade
			if cross_trade_pairs.has(key):
				if a == "Humanos" or b == "Humanos":
					rel += 0.0015   # humans are better diplomats through trade

			# ── Orc Respeto por la Fuerza ─────────────────────────────────────
			# Orcs respect strong militaries; weak ones invite aggression
			if a == "Orcos" or b == "Orcos":
				var orc_sp  := a if a == "Orcos" else b
				var other_sp := b if a == "Orcos" else a
				var orc_army   := (_species_armies.get(orc_sp, 0) as int)
				var other_army := (_species_armies.get(other_sp, 0) as int)
				var other_tech := (_species_tech.get(other_sp, 0) as int)
				# Strength score = army + tech*2
				var other_strength := float(other_army + other_tech * 2)
				var orc_strength   := float(orc_army + (_species_tech.get(orc_sp, 0) as int) * 2)
				if other_strength >= orc_strength * 0.8:
					rel += 0.0005   # respect for strength
				elif other_strength < orc_strength * 0.4:
					rel -= 0.0008   # seeing weakness

			_set_relation(a, b, rel)
			rel = _get_relation(a, b)

			# ── Dwarf Libro de Agravios war trigger ────────────────────────────
			# If dwarves have high grievance against a species, they declare war
			var enano_sp := ""
			var aggressor_sp := ""
			if a == "Enanos":
				enano_sp = a; aggressor_sp = b
			elif b == "Enanos":
				enano_sp = b; aggressor_sp = a
			if enano_sp != "":
				var g_key := _diplomacy_key("Enanos", aggressor_sp)
				var grievance := _species_grievances.get(g_key, 0) as int
				if grievance >= SpeciesDataScript.dwarf_grievance_war_threshold() and not _war_pairs.has(key):
					_war_pairs[key] = true
					_species_grievances[g_key] = 0  # reset after declaring war
					_log_event("Año %d: ¡Los Enanos desempolvaron el Libro de Agravios! Guerra declarada contra los %s." % [world_year, aggressor_sp], "Enanos")
				elif grievance >= SpeciesDataScript.dwarf_grievance_warning_threshold() and not _war_pairs.has(key):
					# Diplomatic warning before war
					if world_year % 80 == 0:
						_log_event("Año %d: Los Enanos exigen reparaciones a los %s. Agravio acumulado: %d." % [world_year, aggressor_sp, grievance], "Enanos")
						_set_relation("Enanos", aggressor_sp, _get_relation("Enanos", aggressor_sp) - 0.05)

			# ── War declaration threshold (species-specific aggressiveness) ────
			var ai_a := SpeciesDataScript.ai_personality(a)
			var ai_b := SpeciesDataScript.ai_personality(b)
			var agr_a := (ai_a.get("agresividad", 0.5) as float)
			var agr_b := (ai_b.get("agresividad", 0.5) as float)
			# Threshold: aggressive species go to war at less negative relation
			var war_threshold := -0.55 + (maxf(agr_a, agr_b) - 0.5) * 0.20
			if rel < war_threshold and not _war_pairs.has(key) and not _alliance_pairs.has(key):
				_war_pairs[key] = true
				_last_war_tick[a] = world_year
				_last_war_tick[b] = world_year
				_log_event("Año %d: ¡Los %s declaran guerra a los %s!" % [world_year, a, b], a)
				# Dwarf grievance: being attacked by non-dwarves adds to the book
				if b == "Enanos":
					var g_key2 := _diplomacy_key("Enanos", a)
					_species_grievances[g_key2] = (_species_grievances.get(g_key2, 0) as int) + SpeciesDataScript.grievance_points("ataque_ciudad")
				elif a == "Enanos":
					var g_key2 := _diplomacy_key("Enanos", b)
					_species_grievances[g_key2] = (_species_grievances.get(g_key2, 0) as int) + SpeciesDataScript.grievance_points("ataque_ciudad")

			# ── Peace threshold (diplomatic species forgive sooner) ────────────
			var dip_a := (ai_a.get("diplomacia", 0.5) as float)
			var dip_b := (ai_b.get("diplomacia", 0.5) as float)
			var peace_threshold := -0.25 - (maxf(dip_a, dip_b) - 0.5) * 0.10
			if _war_pairs.has(key) and rel > peace_threshold:
				_war_pairs.erase(key)
				_log_event("Año %d: Los %s y los %s firman una tregua" % [world_year, a, b], a)

			if rel > 0.50 and not _alliance_pairs.has(key) and not _war_pairs.has(key):
				_alliance_pairs[key] = true
				_log_event("Año %d: ¡%s y %s forman una alianza sagrada!" % [world_year, a, b], a)

			if _alliance_pairs.has(key) and rel < 0.15:
				_alliance_pairs.erase(key)
				_log_event("Año %d: La alianza entre %s y %s se disuelve" % [world_year, a, b], a)

func _update_trade_v2() -> void:
	var towns: Dictionary = {}
	var ports := _gather_ports()
	_sea_route_cache.clear()
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
			_append_trade_route_if_missing(new_routes, {"from": a, "to": b, "species": species, "mode": "land"})

	for species: String in ports.keys():
		var sp_ports: Array = ports[species]
		var trade_fleets := (_fleet_state(species).get("trade", 0) as int)
		if trade_fleets <= 0 or sp_ports.size() < 2:
			continue
		var best_pair := _best_reachable_port_pair(sp_ports, 120)
		if best_pair.is_empty():
			continue
		var port_a := best_pair["from"] as Dictionary
		var port_b := best_pair["to"] as Dictionary
		var path := best_pair["path"] as Array
		if path.size() < 2:
			continue
		for _i in range(mini(trade_fleets, 2)):
			_append_trade_route_if_missing(new_routes, {
				"from": port_a["water"] as Vector2i,
				"to": port_b["water"] as Vector2i,
				"species": species,
				"mode": "sea",
				"port_from": port_a["land"] as Vector2i,
				"port_to": port_b["land"] as Vector2i,
				"path": path,
			})

	# ── Cross-species trade between towns of different non-warring species ───────
	var all_sp := towns.keys()
	for ai in all_sp.size():
		for bi in range(ai + 1, all_sp.size()):
			var sp_a := all_sp[ai] as String
			var sp_b := all_sp[bi] as String
			if _war_pairs.has(_diplomacy_key(sp_a, sp_b)):
				continue  # no trade during active war
			var ta_list: Array = towns[sp_a]
			var tb_list: Array = towns[sp_b]
			var best_d := 28.0  # inter-species routes require closer towns
			var best_a := Vector2i(-1, -1)
			var best_b := Vector2i(-1, -1)
			for ta: Vector2i in ta_list:
				for tb: Vector2i in tb_list:
					var d := (ta as Vector2i).distance_to(tb as Vector2i)
					if d < best_d:
						best_d = d; best_a = ta; best_b = tb
			if best_a == Vector2i(-1, -1):
				continue
			_append_trade_route_if_missing(new_routes, {
				"from": best_a, "to": best_b,
				"species": sp_a, "partner": sp_b, "mode": "cross"
			})

	for r: Dictionary in new_routes:
		var existed := false
		for old: Dictionary in _trade_routes:
			if old.get("mode", "land") == r.get("mode", "land") and ((old["from"] == r["from"] and old["to"] == r["to"]) or (old["from"] == r["to"] and old["to"] == r["from"])):
				existed = true
				break
		if not existed:
			var mode := r.get("mode", "land") as String
			if mode == "sea":
				_log_event("Ano %d: Los %s botaron una flota comercial" % [world_year, r["species"] as String], r["species"] as String)
			elif mode == "cross":
				var partner := r.get("partner", "?") as String
				_log_event("Año %d: %s y %s abrieron una ruta comercial internacional" % [world_year, r["species"] as String, partner], r["species"] as String)
			else:
				_log_event("Ano %d: Los %s abrieron una ruta comercial" % [world_year, r["species"] as String], r["species"] as String)

	_trade_routes = new_routes

	# ── Benefits for all trade hubs ───────────────────────────────────────────
	var trade_hubs: Dictionary = {}
	var cross_hubs: Dictionary = {}  # hubs where cross-species trade happens
	for r: Dictionary in _trade_routes:
		var mode := r.get("mode", "land") as String
		if mode == "sea":
			trade_hubs[r["port_from"] as Vector2i] = r["species"] as String
			trade_hubs[r["port_to"]   as Vector2i] = r["species"] as String
		elif mode == "cross":
			trade_hubs[r["from"] as Vector2i] = r["species"] as String
			trade_hubs[r["to"]   as Vector2i] = r.get("partner", r["species"] as String) as String
			cross_hubs[r["from"] as Vector2i] = true
			cross_hubs[r["to"]   as Vector2i] = true
			# Trading partners' relations improve over time
			var sp_a2 := r["species"] as String
			var sp_b2 := r.get("partner", "") as String
			if sp_b2 != "":
				_set_relation(sp_a2, sp_b2, minf(1.0, _get_relation(sp_a2, sp_b2) + 0.002))
		else:
			trade_hubs[r["from"] as Vector2i] = r["species"] as String
			trade_hubs[r["to"]   as Vector2i] = r["species"] as String

	for human in humans:
		for hub_cell: Vector2i in trade_hubs.keys():
			if (human.grid_position - hub_cell).length() <= 2.5:
				var is_dock := world_grid.get_improvement(hub_cell) == "dock"
				var is_cross := cross_hubs.has(hub_cell)
				# Species-specific trade bonus (Humans benefit most)
				var species_trade_mult := SpeciesDataScript.trade_evo_bonus(human.species_name)
				var base_bonus := 0.025 if is_cross else (0.015 if is_dock else 0.010)
				var bonus := base_bonus * (species_trade_mult / 0.015)
				human.evolution_score += bonus
				break

func _path_to_points(path: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for cell: Vector2i in path:
		points.append(Vector2((cell.x + 0.5) * TILE_SIZE, (cell.y + 0.5) * TILE_SIZE))
	return points

func _path_progress_position(path: Array, t: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	if path.size() == 1:
		var only := path[0] as Vector2i
		return Vector2((only.x + 0.5) * TILE_SIZE, (only.y + 0.5) * TILE_SIZE)
	var points := _path_to_points(path)
	var lengths: Array[float] = []
	var total := 0.0
	for i in range(points.size() - 1):
		var seg := points[i].distance_to(points[i + 1])
		lengths.append(seg)
		total += seg
	if total <= 0.0:
		return points[0]
	var target := clampf(t, 0.0, 1.0) * total
	var walked := 0.0
	for i in range(lengths.size()):
		var seg_len := lengths[i] as float
		if walked + seg_len >= target:
			var local_t := (target - walked) / maxf(seg_len, 0.001)
			return points[i].lerp(points[i + 1], local_t)
		walked += seg_len
	return points[points.size() - 1]

func _apply_power_at(cell: Vector2i) -> void:
	var power: String = GameUI.POWERS[ui.selected_power]
	world_effects.apply_power(power, cell, world_grid, humans, world_year, Callable(self, "_log_event"))

func _draw() -> void:
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var cell := Vector2i(x, y)
			var biome := world_grid.get_biome(cell)
			# Checkerboard variation: alternate light/dark per-tile for texture depth
			var c := _biome_dark_color(biome) if (x * 7 + y * 13) % 4 < 2 else _biome_color(biome)
			var owner := world_grid.get_owner(cell)
			if owner != "":
				var sc: Color = _species_colors.get(owner, Color.WHITE)
				c = c.lerp(sc, 0.45)
			draw_rect(Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE), c)
			_draw_biome_detail(x, y, biome)

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
			var fort_lvl := world_grid.get_fortification(cell)
			if fort_lvl > 0:
				_draw_fortification(cx, cy, fort_lvl, sc)

	# Improvements around settlements
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var imp_cell := Vector2i(x, y)
			var improvement := world_grid.get_improvement(imp_cell)
			if improvement == "":
				continue
			var owner := world_grid.get_owner(imp_cell)
			var sc: Color = _species_colors.get(owner, Color.WHITE)
			var cx := (x + 0.5) * TILE_SIZE
			var cy := (y + 0.5) * TILE_SIZE
			match improvement:
				"housing": _draw_housing(cx, cy, sc)
				"farm": _draw_farm(cx, cy, sc)
				"mine": _draw_mine(cx, cy, sc)
				"dock": _draw_dock(cx, cy, sc)

	for cluster in _settlement_cluster_cache:
		_draw_settlement_perimeter(cluster)

	# Territory borders
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var owner := world_grid.get_owner(Vector2i(x, y))
			if owner == "":
				continue
			var bc: Color = (_species_colors.get(owner, Color.WHITE) as Color).lightened(0.35)
			var px := float(x * TILE_SIZE)
			var py := float(y * TILE_SIZE)
			_draw_border_segment(owner, Vector2i(x, y), Vector2i(x + 1, y), Vector2(px + TILE_SIZE, py), Vector2(px + TILE_SIZE, py + TILE_SIZE), bc)
			_draw_border_segment(owner, Vector2i(x, y), Vector2i(x - 1, y), Vector2(px, py), Vector2(px, py + TILE_SIZE), bc)
			_draw_border_segment(owner, Vector2i(x, y), Vector2i(x, y + 1), Vector2(px, py + TILE_SIZE), Vector2(px + TILE_SIZE, py + TILE_SIZE), bc)
			_draw_border_segment(owner, Vector2i(x, y), Vector2i(x, y - 1), Vector2(px, py), Vector2(px + TILE_SIZE, py), bc)

	# Fire overlay
	for cell: Vector2i in _fire_cells.keys():
		var ft: int = _fire_cells[cell] as int
		var alpha := lerpf(0.92, 0.46, float(ft) / 40.0)
		var px := float(cell.x * TILE_SIZE)
		var py := float(cell.y * TILE_SIZE)
		var ts := float(TILE_SIZE)
		var tms := float(Time.get_ticks_msec())
		var flicker  := sin(tms * 0.018 + float(cell.x * 3 + cell.y * 7)) * 0.5 + 0.5
		var flicker2 := sin(tms * 0.022 + float(cell.x * 5 + cell.y * 11) + 1.2) * 0.5 + 0.5
		# Base ember glow
		draw_rect(Rect2(px, py, ts, ts), Color(0.88, 0.26, 0.0, alpha * 0.82))
		# Left flame tongue
		var lh := ts * (0.44 + flicker * 0.32)
		draw_colored_polygon(PackedVector2Array([
			Vector2(px+ts*0.05, py+ts), Vector2(px+ts*0.50, py+ts),
			Vector2(px+ts*0.22, py+ts-lh),
		]), Color(1.0, 0.46+flicker*0.24, 0.0, alpha))
		# Right flame tongue
		var rh := ts * (0.38 + flicker2 * 0.36)
		draw_colored_polygon(PackedVector2Array([
			Vector2(px+ts*0.50, py+ts), Vector2(px+ts*0.95, py+ts),
			Vector2(px+ts*0.78, py+ts-rh),
		]), Color(1.0, 0.40+flicker2*0.22, 0.0, alpha))
		# Center tall flame
		var ch := ts * (0.56 + (flicker+flicker2) * 0.20)
		draw_colored_polygon(PackedVector2Array([
			Vector2(px+ts*0.22, py+ts), Vector2(px+ts*0.78, py+ts),
			Vector2(px+ts*0.50, py+ts-ch),
		]), Color(1.0, 0.60+flicker*0.28, 0.04, alpha * 0.96))
		# Yellow-white inner core
		draw_colored_polygon(PackedVector2Array([
			Vector2(px+ts*0.35, py+ts*0.74), Vector2(px+ts*0.65, py+ts*0.74),
			Vector2(px+ts*0.50, py+ts*0.74-ch*0.52),
		]), Color(1.0, 0.94, 0.42, alpha * 0.76))

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
				var radius := lerpf(1.5, float(TILE_SIZE) * 5.2, minf(t * 2.5, 1.0))
				var ialpha := lerpf(1.0, 0.0, t)
				# Outer shockwave ring
				draw_circle(Vector2(cx, cy), radius * 1.35, Color(0.48, 0.28, 0.10, ialpha * 0.20))
				# Main blast disk
				draw_circle(Vector2(cx, cy), radius, Color(1.0, 0.66, 0.16, ialpha * 0.80))
				draw_circle(Vector2(cx, cy), radius, Color(0.92, 0.44, 0.06, ialpha * 0.52), false, 2.5)
				# White-hot core
				draw_circle(Vector2(cx, cy), radius * 0.36, Color(1.0, 1.0, 0.90, ialpha * 0.92))
				# Flying debris chunks
				if t < 0.65:
					for di in 6:
						var da := deg_to_rad(float(di) * 60.0 + t * 55.0)
						var dd := radius * (0.55 + float(di % 3) * 0.28)
						draw_circle(Vector2(cx + cos(da)*dd, cy + sin(da)*dd), 2.5, Color(1.0, 0.52, 0.10, ialpha * 0.88))
			"lightning":
				var lalpha := lerpf(1.0, 0.0, t)
				# Bolt segments (zigzag from top of screen to target cell)
				var z0 := Vector2(cx + 4.0, 0.0)
				var z1 := Vector2(cx - 6.0, cy * 0.36)
				var z2 := Vector2(cx + 5.0, cy * 0.64)
				var z3 := Vector2(cx, cy)
				# Outer glow (thick, pale blue-white)
				var glow_c := Color(0.80, 0.84, 1.0, lalpha * 0.44)
				draw_line(z0, z1, glow_c, 7.0)
				draw_line(z1, z2, glow_c, 7.0)
				draw_line(z2, z3, glow_c, 8.0)
				# Core bright bolt (yellow-white)
				draw_line(z0, z1, Color(1.0, 1.0, 0.62, lalpha), 2.5)
				draw_line(z1, z2, Color(1.0, 1.0, 0.62, lalpha), 2.5)
				draw_line(z2, z3, Color(1.0, 1.0, 1.0,  lalpha), 3.0)
				# Side branch (visible only in first half)
				if t < 0.45:
					var ba := lalpha * (1.0 - t / 0.45)
					draw_line(z2, z2 + Vector2(10.0, 14.0), Color(1.0, 1.0, 0.72, ba), 1.5)
					draw_line(z2 + Vector2(10.0, 14.0), z2 + Vector2(17.0, 27.0), Color(1.0, 1.0, 0.68, ba * 0.65), 1.2)
				# Ground impact flash
				if t < 0.22:
					var fi := (0.22 - t) / 0.22
					draw_circle(z3, float(TILE_SIZE) * 2.0 * fi, Color(1.0, 1.0, 0.85, 0.46 * fi))
			"rain":
				var ralpha := lerpf(0.68, 0.0, t)
				var time_ms := float(Time.get_ticks_msec())
				for di in range(-5, 6):
					for dj in range(-5, 6):
						var base_rx := cx + float(di) * TILE_SIZE
						var base_ry := cy + float(dj) * TILE_SIZE
						# Animate drop positions scrolling downward
						var drop_off := fmod(time_ms * 0.12 + float(di*7 + dj*13) * 3.7, float(TILE_SIZE))
						var ry := base_ry + drop_off
						draw_line(Vector2(base_rx + 1.5, ry - 5.0), Vector2(base_rx - 0.5, ry + 3.0),
							Color(0.52, 0.80, 1.0, ralpha), 1.0)
			"blessing":
				var balpha := lerpf(0.82, 0.0, t)
				var brad := lerpf(0.0, float(TILE_SIZE) * 3.8, t)
				# Soft glow disk
				draw_circle(Vector2(cx, cy), brad, Color(1.0, 0.94, 0.28, balpha * 0.30))
				# Ring border
				draw_circle(Vector2(cx, cy), brad, Color(1.0, 0.88, 0.18, balpha * 0.60), false, 2.0)
				# Eight radiating rays rotating outward
				for ri in 8:
					var ra := deg_to_rad(float(ri) * 45.0 + t * 135.0)
					var ri_r := brad * 0.28
					var ro_r := brad * (0.75 + 0.25 * sin(float(ri) * 1.57 + t * 6.28))
					draw_line(
						Vector2(cx + cos(ra)*ri_r, cy + sin(ra)*ri_r),
						Vector2(cx + cos(ra)*ro_r, cy + sin(ra)*ro_r),
						Color(1.0, 0.92, 0.36, balpha * 0.64), 1.5)

	# Active battle markers
	for marker: Dictionary in _battle_markers:
		var from_cell: Vector2i = marker["from"] as Vector2i
		var to_cell: Vector2i = marker["to"] as Vector2i
		var attacker: String = marker["attacker"] as String
		var defender: String = marker["defender"] as String
		var success: bool = marker["success"] as bool
		var fort: int = marker["fort"] as int
		var age: int = marker["age"] as int
		var max_age: int = marker["max_age"] as int
		var t_battle := float(age) / float(max_age)
		var attack_color := (_species_colors.get(attacker, Color(1.0, 0.4, 0.4)) as Color).lightened(0.25)
		var defend_color := (_species_colors.get(defender, Color(1.0, 0.8, 0.4)) as Color).lightened(0.10)
		var alpha_battle := lerpf(0.95, 0.0, t_battle)
		var a_pos := Vector2((from_cell.x + 0.5) * TILE_SIZE, (from_cell.y + 0.5) * TILE_SIZE)
		var b_pos := Vector2((to_cell.x + 0.5) * TILE_SIZE, (to_cell.y + 0.5) * TILE_SIZE)
		var mid := a_pos.lerp(b_pos, 0.5)
		draw_line(a_pos, b_pos, Color(attack_color.r, attack_color.g, attack_color.b, alpha_battle * 0.55), 1.5)
		draw_line(mid + Vector2(-3, -3), mid + Vector2(3, 3), Color(1.0, 0.95, 0.8, alpha_battle), 2.0)
		draw_line(mid + Vector2(-3, 3), mid + Vector2(3, -3), Color(1.0, 0.95, 0.8, alpha_battle), 2.0)
		if fort > 0:
			# Siege ring — pulsing shield around fortified defender
			var siege_pulse := 0.6 + 0.4 * sin(float(Time.get_ticks_msec()) / 180.0 + float(to_cell.x * 7 + to_cell.y))
			var siege_r := 6.5 + float(fort) * 2.0
			draw_circle(b_pos, siege_r, Color(defend_color.r, defend_color.g, defend_color.b, alpha_battle * 0.14 * siege_pulse))
			draw_arc(b_pos, siege_r, 0.0, TAU, 24, Color(defend_color.r, defend_color.g, defend_color.b, alpha_battle * 0.90), float(fort) * 0.8 + 1.0)
			# Catapult arrow: attacker fires a projectile arc toward defender
			var proj_t := fmod(float(Time.get_ticks_msec()) / 500.0, 1.0)
			var proj_pos := a_pos.lerp(b_pos, proj_t)
			var arc_offset := -sin(proj_t * PI) * 6.0
			proj_pos.y += arc_offset
			draw_circle(proj_pos, 1.8, Color(1.0, 0.65, 0.10, alpha_battle * 0.85))
		if success:
			# Conquest flash
			draw_circle(mid, 4.0, Color(1.0, 0.45, 0.20, alpha_battle))
			draw_circle(b_pos, 3.0 * (1.0 - float(age) / float(max_age)), Color(1.0, 0.80, 0.20, alpha_battle * 0.7))
		else:
			draw_circle(mid, 2.0, Color(0.95, 0.95, 1.0, alpha_battle * 0.9))

	# Army presence indicators (peacetime & war)
	_draw_peacetime_armies()
	_draw_war_armies()

	# Trade routes
	for route: Dictionary in _trade_routes:
		var ra: Vector2i = route["from"] as Vector2i
		var rb: Vector2i = route["to"] as Vector2i
		var rsp: String  = route["species"] as String
		var mode := route.get("mode", "land") as String
		var partner := route.get("partner", "") as String
		var rc: Color = (_species_colors.get(rsp, Color.WHITE) as Color).lightened(0.25)
		var route_path := route.get("path", []) as Array
		var wp_a := Vector2((ra.x + 0.5) * TILE_SIZE, (ra.y + 0.5) * TILE_SIZE)
		var wp_b := Vector2((rb.x + 0.5) * TILE_SIZE, (rb.y + 0.5) * TILE_SIZE)

		if mode == "cross":
			# Cross-species: draw two half-lines in each species' color + glow
			var pc: Color = (_species_colors.get(partner, Color.WHITE) as Color).lightened(0.25)
			var mid := wp_a.lerp(wp_b, 0.5)
			draw_line(wp_a, mid, Color(rc.r, rc.g, rc.b, 0.55), 2.0)
			draw_line(mid, wp_b, Color(pc.r, pc.g, pc.b, 0.55), 2.0)
			# Animated exchange marker at midpoint
			var mt := fmod(float(Time.get_ticks_msec()) / 1800.0, 1.0)
			var mp := wp_a.lerp(wp_b, mt)
			draw_circle(mp, 3.2, Color(1.0, 0.92, 0.35, 0.88))
			draw_circle(mp, 1.8, Color(0.85, 0.65, 0.15, 0.95))
			# Endpoint diamonds
			draw_colored_polygon(PackedVector2Array([
				wp_a + Vector2(0,-4), wp_a + Vector2(4,0), wp_a + Vector2(0,4), wp_a + Vector2(-4,0)
			]), Color(rc.r, rc.g, rc.b, 0.80))
			draw_colored_polygon(PackedVector2Array([
				wp_b + Vector2(0,-4), wp_b + Vector2(4,0), wp_b + Vector2(0,4), wp_b + Vector2(-4,0)
			]), Color(pc.r, pc.g, pc.b, 0.80))
		else:
			rc.a = 0.72 if mode == "sea" else 0.60
			if route_path.size() >= 2:
				var points := _path_to_points(route_path)
				for i in range(points.size() - 1):
					draw_line(points[i], points[i + 1], rc, 2.0 if mode == "sea" else 1.5)
			else:
				draw_line(wp_a, wp_b, rc, 2.0 if mode == "sea" else 1.5)
			var caravan_t := fmod(float(Time.get_ticks_msec()) / 2000.0, 1.0)
			var caravan_pos := _path_progress_position(route_path, caravan_t) if route_path.size() >= 2 else wp_a.lerp(wp_b, caravan_t)
			if mode == "sea":
				draw_line(caravan_pos + Vector2(-2.5, 2.0), caravan_pos + Vector2(2.5, 2.0), Color(0.82, 0.56, 0.28, 0.95), 1.5)
				draw_colored_polygon(PackedVector2Array([
					caravan_pos + Vector2(-2.5, 1.5),
					caravan_pos + Vector2(0.0, -2.5),
					caravan_pos + Vector2(2.5, 1.5),
				]), Color(0.92, 0.92, 0.86, 0.92))
			else:
				draw_circle(caravan_pos, 2.8, Color(0.95, 0.80, 0.35, 0.95))
				draw_circle(caravan_pos, 1.5, Color(0.60, 0.38, 0.12, 0.95))

	var ports_for_war := _gather_ports()
	for war_key: String in _war_pairs.keys():
		var parts := war_key.split("|")
		if parts.size() != 2:
			continue
		if (_fleet_state(parts[0]).get("war", 0) as int) <= 0 and (_fleet_state(parts[1]).get("war", 0) as int) <= 0:
			continue
		var a_ports: Array = ports_for_war.get(parts[0], [])
		var b_ports: Array = ports_for_war.get(parts[1], [])
		if a_ports.is_empty() or b_ports.is_empty():
			continue
		var best_route := _best_reachable_enemy_ports(a_ports, b_ports, 120)
		if best_route.is_empty():
			continue
		var war_path := best_route.get("path", []) as Array
		if war_path.size() < 2:
			continue
		var war_points := _path_to_points(war_path)
		var war_pulse := 0.45 + 0.55 * sin(float(Time.get_ticks_msec()) / 220.0)
		for i in range(war_points.size() - 1):
			draw_line(war_points[i], war_points[i + 1], Color(1.0, 0.22, 0.10, 0.25 + 0.25 * war_pulse), 2.2)
		var raid_pos := _path_progress_position(war_path, fmod(float(Time.get_ticks_msec()) / 2300.0, 1.0))
		draw_circle(raid_pos, 3.0, Color(1.0, 0.35, 0.15, 0.85))
		draw_line(raid_pos + Vector2(-3, 2), raid_pos + Vector2(3, 2), Color(0.35, 0.18, 0.08, 0.9), 1.2)

	# Alliance lines between allied species towns
	if not _alliance_pairs.is_empty():
		var sp_capitals: Dictionary = {}
		for y2 in range(world_grid.height):
			for x2 in range(world_grid.width):
				var cc := Vector2i(x2, y2)
				if world_grid.get_structure(cc) == "town":
					var own := world_grid.get_owner(cc)
					if own != "" and not sp_capitals.has(own):
						sp_capitals[own] = cc
		var pulse := 0.55 + 0.45 * sin(float(Time.get_ticks_msec()) / 600.0)
		for ak: String in _alliance_pairs.keys():
			var parts := ak.split("|")
			if parts.size() < 2:
				continue
			var sa: String = parts[0]; var sb: String = parts[1]
			if not sp_capitals.has(sa) or not sp_capitals.has(sb):
				continue
			var ca: Vector2i = sp_capitals[sa] as Vector2i
			var cb: Vector2i = sp_capitals[sb] as Vector2i
			var wa := Vector2((ca.x + 0.5) * TILE_SIZE, (ca.y + 0.5) * TILE_SIZE)
			var wb := Vector2((cb.x + 0.5) * TILE_SIZE, (cb.y + 0.5) * TILE_SIZE)
			draw_line(wa, wb, Color(1.0, 0.88, 0.20, 0.35 * pulse), 2.0)
			draw_circle(wa, 5.0 * pulse, Color(1.0, 0.88, 0.20, 0.6 * pulse))
			draw_circle(wb, 5.0 * pulse, Color(1.0, 0.88, 0.20, 0.6 * pulse))

	# Religion symbols on towns
	for y3 in range(world_grid.height):
		for x3 in range(world_grid.width):
			var tc := Vector2i(x3, y3)
			if world_grid.get_structure(tc) != "town":
				continue
			var town_owner := world_grid.get_owner(tc)
			if town_owner == "":
				continue
			var dom_rel := _dominant_religion(town_owner)
			var rx := (x3 + 0.5) * TILE_SIZE
			var ry := float(y3) * TILE_SIZE - 3.0
			_draw_religion_symbol(rx, ry, dom_rel)

	# Territory labels
	for cluster in _territory_cluster_cache:
		var cpos: Vector2 = cluster["center"]
		var sp: String   = cluster["species"]
		var seed: String = cluster["seed"]
		var name := _territory_name(seed, sp)
		var tc: Color = (_species_colors.get(sp, Color.WHITE) as Color).lightened(0.5)
		var tw := float(name.length() * 6 + 6)
		draw_rect(Rect2(cpos.x - tw * 0.5, cpos.y - 6.0, tw, 10.0), Color(0, 0, 0, 0.6))
		draw_string(ThemeDB.fallback_font, Vector2(cpos.x - tw * 0.5 + 3.0, cpos.y + 2.5),
			name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, tc)


func _draw_war_armies() -> void:
	if _war_pairs.is_empty():
		return
	var at_war: Dictionary = {}
	for key: String in _war_pairs.keys():
		var parts := key.split("|")
		if parts.size() == 2:
			at_war[parts[0]] = true
			at_war[parts[1]] = true

	var sp_positions: Dictionary = {}
	for human in humans:
		if not at_war.has(human.species_name):
			continue
		if not sp_positions.has(human.species_name):
			sp_positions[human.species_name] = []
		(sp_positions[human.species_name] as Array).append(human.grid_position)

	for sp: String in sp_positions.keys():
		var positions: Array = sp_positions[sp]
		var visited: Dictionary = {}
		for pos: Vector2i in positions:
			if visited.has(pos):
				continue
			var cluster: Array[Vector2i] = []
			var queue: Array[Vector2i] = [pos]
			while not queue.is_empty():
				var cur: Vector2i = queue.pop_back()
				if visited.has(cur):
					continue
				visited[cur] = true
				cluster.append(cur)
				for op: Vector2i in positions:
					if not visited.has(op) and cur.distance_to(op) <= 4.0:
						queue.push_back(op)
			if cluster.size() < 3:
				continue
			var sx := 0; var sy := 0
			for cp: Vector2i in cluster:
				sx += cp.x; sy += cp.y
			var centroid := Vector2(
				(float(sx) / cluster.size() + 0.5) * TILE_SIZE,
				(float(sy) / cluster.size() + 0.5) * TILE_SIZE
			)
			_draw_army_banner(centroid, sp, cluster.size())

func _draw_peacetime_armies() -> void:
	if _species_armies.is_empty():
		return
	# Build set of species currently at war
	var at_war: Dictionary = {}
	for key: String in _war_pairs.keys():
		var parts := key.split("|")
		if parts.size() == 2:
			at_war[parts[0]] = true
			at_war[parts[1]] = true

	# Track which species have already had a shield drawn (one per species)
	var drawn: Dictionary = {}
	for cluster: Dictionary in _territory_cluster_cache:
		var sp: String = cluster["species"] as String
		if drawn.has(sp):
			continue
		var army_count: int = (_species_armies.get(sp, 0) as int)
		if army_count <= 0:
			continue
		if at_war.has(sp):
			continue  # war armies use _draw_war_armies() banners instead
		var cpos: Vector2 = cluster["center"] as Vector2
		_draw_peacetime_shield(cpos, sp, army_count)
		drawn[sp] = true

func _draw_peacetime_shield(pos: Vector2, species: String, army_count: int) -> void:
	var sc: Color = (_species_colors.get(species, Color.WHITE) as Color)
	var dim := Color(sc.r * 0.70, sc.g * 0.70, sc.b * 0.70, 0.72)
	var border := dim.darkened(0.35)
	# Shield outline (pentagon-ish)
	var sh := 7.0
	var shield_pts := PackedVector2Array([
		pos + Vector2(-sh,       -sh * 0.90),
		pos + Vector2( sh,       -sh * 0.90),
		pos + Vector2( sh * 1.1,  sh * 0.10),
		pos + Vector2( 0.0,       sh * 1.20),
		pos + Vector2(-sh * 1.1,  sh * 0.10),
	])
	draw_colored_polygon(shield_pts, dim)
	draw_polyline(PackedVector2Array([
		shield_pts[0], shield_pts[1], shield_pts[2],
		shield_pts[3], shield_pts[4], shield_pts[0],
	]), border, 1.0)
	# Cross emblem inside
	draw_line(pos + Vector2(0, -sh * 0.55), pos + Vector2(0, sh * 0.50), border, 1.2)
	draw_line(pos + Vector2(-sh * 0.55, -sh * 0.20), pos + Vector2(sh * 0.55, -sh * 0.20), border, 1.2)
	# Unit dots below shield
	var dot_n := mini(army_count, 9)
	for i in dot_n:
		var dx := (float(i) - float(dot_n - 1) * 0.5) * 3.2
		draw_circle(pos + Vector2(dx, sh * 1.60), 1.4, Color(sc.r, sc.g, sc.b, 0.68))

func _draw_army_banner(pos: Vector2, species: String, count: int) -> void:
	var sc: Color = (_species_colors.get(species, Color.WHITE) as Color).lightened(0.05)
	var pulse := 0.72 + 0.28 * sin(float(Time.get_ticks_msec()) / 380.0)
	# Shadow
	draw_circle(pos + Vector2(1, 1), 4.5, Color(0, 0, 0, 0.28))
	# Pole
	draw_line(pos + Vector2(0, 9), pos + Vector2(0, -10), Color(0.45, 0.32, 0.18, 0.95), 1.5)
	# Flag waving
	var wave := sin(float(Time.get_ticks_msec()) / 220.0) * 1.5
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0,  -10),
		pos + Vector2(9 + wave, -7 + wave * 0.4),
		pos + Vector2(8 + wave, -4 + wave * 0.3),
		pos + Vector2(0,  -4),
	]), Color(sc.r, sc.g, sc.b, 0.88 * pulse))
	draw_polyline(PackedVector2Array([
		pos + Vector2(0, -10),
		pos + Vector2(9 + wave, -7 + wave * 0.4),
		pos + Vector2(8 + wave, -4 + wave * 0.3),
		pos + Vector2(0, -4),
	]), sc.darkened(0.3), 0.8)
	# Unit dots below
	var dot_n := mini(count, 9)
	for i in dot_n:
		var dx := (float(i) - float(dot_n - 1) * 0.5) * 3.5
		draw_circle(pos + Vector2(dx, 12), 1.6, Color(sc.r, sc.g, sc.b, 0.80))

func _draw_religion_symbol(cx: float, cy: float, religion: String) -> void:
	match religion:
		"Fe Sagrada":
			draw_line(Vector2(cx, cy - 4), Vector2(cx, cy + 4), Color(1.0, 0.95, 0.70, 0.9), 1.5)
			draw_line(Vector2(cx - 2.5, cy - 1.5), Vector2(cx + 2.5, cy - 1.5), Color(1.0, 0.95, 0.70, 0.9), 1.5)
		"Sendero Eterno":
			for si in range(5):
				var oa := deg_to_rad(-90.0 + si * 72.0)
				var ia := deg_to_rad(-90.0 + si * 72.0 + 36.0)
				var pa := Vector2(cx + cos(oa) * 4.0, cy + sin(oa) * 4.0)
				var pb := Vector2(cx + cos(ia) * 2.0, cy + sin(ia) * 2.0)
				draw_line(pa, pb, Color(0.70, 1.0, 0.70, 0.9), 1.0)
		"Forja Divina":
			draw_rect(Rect2(cx - 2.5, cy - 1.5, 5.0, 3.5), Color(0.80, 0.70, 0.50, 0.9))
			draw_line(Vector2(cx, cy - 1.5), Vector2(cx, cy - 5.0), Color(0.60, 0.50, 0.35, 0.9), 1.5)
		"Culto de Sangre":
			draw_circle(Vector2(cx, cy - 1.0), 3.5, Color(0.85, 0.15, 0.15, 0.80))
			draw_line(Vector2(cx - 2.0, cy + 2.5), Vector2(cx, cy - 0.5), Color(0.85, 0.15, 0.15, 0.9), 1.5)
			draw_line(Vector2(cx + 2.0, cy + 2.5), Vector2(cx, cy - 0.5), Color(0.85, 0.15, 0.15, 0.9), 1.5)

# ── Species event system ──────────────────────────────────────────────────────

func _tick_species_events() -> void:
	var living: Dictionary = {}
	for h in humans:
		living[h.species_name] = true

	for sp: String in living.keys():
		var era := world_year / 200
		var era_key := sp + "|" + str(era)
		if _last_species_event_era.has(era_key):
			continue  # one event per species per era

		match sp:
			"Humanos":  _try_human_event(sp, era_key)
			"Elfos":    _try_elf_event(sp, era_key)
			"Orcos":    _try_orc_event(sp, era_key)
			"Enanos":   _try_enano_event(sp, era_key)

func _try_human_event(sp: String, era_key: String) -> void:
	var stock := _resource_stock(sp)
	var active_routes := 0
	for r: Dictionary in _trade_routes:
		if r.get("species", "") == sp or r.get("partner", "") == sp:
			active_routes += 1
	# Trade boom: 3+ active routes
	if active_routes >= 3 and rng.randf() < 0.30:
		stock["food"] = (stock.get("food", 0.0) as float) + 10.0
		stock["iron"] = (stock.get("iron", 0.0) as float) + 6.0
		for h in humans:
			if h.species_name == sp:
				h.evolution_score += 1.5
		_log_event("Año %d: ¡Los Humanos viven un Auge Comercial! El oro fluye por las rutas de intercambio." % world_year, sp)
		_last_species_event_era[era_key] = true
		return
	# Expansionary fever: high population + no war
	var pop := 0
	for h in humans:
		if h.species_name == sp:
			pop += 1
	if pop >= 30 and not _any_war(sp) and rng.randf() < 0.25:
		for h in humans:
			if h.species_name == sp:
				h.evolution_score += 0.8
		_log_event("Año %d: Los Humanos sienten fiebre de expansión. Nuevas tierras llaman a los colonos." % world_year, sp)
		_last_species_event_era[era_key] = true

func _try_elf_event(sp: String, era_key: String) -> void:
	# Count forest tiles owned by elves
	var forest_tiles := 0
	var total_tiles := 0
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var cell := Vector2i(x, y)
			if world_grid.get_owner(cell) == sp:
				total_tiles += 1
				if world_grid.get_biome(cell) == "forest":
					forest_tiles += 1
	# Forest coverage check
	if total_tiles > 0:
		var forest_pct := float(forest_tiles) / float(total_tiles)
		if forest_pct < 0.40 and rng.randf() < 0.40:
			for h in humans:
				if h.species_name == sp:
					h.evolution_score -= 1.0
			_log_event("Año %d: El territorio élfico pierde su cobertura forestal. Los druidas lloran por el bosque menguante." % world_year, sp)
			_last_species_event_era[era_key] = true
			return
	# Floración: high forest coverage + peace
	if total_tiles > 0 and float(forest_tiles) / float(total_tiles) >= 0.70 and not _any_war(sp) and rng.randf() < 0.35:
		var stock := _resource_stock(sp)
		stock["food"] = (stock.get("food", 0.0) as float) + 12.0
		for h in humans:
			if h.species_name == sp:
				h.evolution_score += 2.0
		_log_event("Año %d: ¡Los bosques élficos florecen en primavera sagrada! El Árbol Madre irradia vida." % world_year, sp)
		_last_species_event_era[era_key] = true

func _try_orc_event(sp: String, era_key: String) -> void:
	# Inactivity: no war for too long causes internal conflict
	var ticks_since_war := world_year - (_last_war_tick.get(sp, 0) as int)
	if ticks_since_war > SpeciesDataScript.orc_inactivity_war_ticks() and rng.randf() < 0.45:
		for h in humans:
			if h.species_name == sp:
				h.evolution_score -= 0.8
		_log_event("Año %d: La paz pudre los campamentos orcos. Los clanes se enfrentan por el liderazgo." % world_year, sp)
		_last_species_event_era[era_key] = true
		return
	# Tribute demand: orcs demand tribute from weakest neighbor
	_try_orc_tribute_demand(sp)
	_last_species_event_era[era_key] = true

func _try_orc_tribute_demand(orc_sp: String) -> void:
	var orc_army := (_species_armies.get(orc_sp, 0) as int)
	var best_target := ""
	var best_weakness := -1.0
	var living: Dictionary = {}
	for h in humans:
		living[h.species_name] = true
	for sp: String in living.keys():
		if sp == orc_sp:
			continue
		var key := _diplomacy_key(orc_sp, sp)
		if _war_pairs.has(key) or _alliance_pairs.has(key):
			continue
		var target_army := (_species_armies.get(sp, 0) as int)
		var target_tech := (_species_tech.get(sp, 0) as int)
		var orc_strength := float(orc_army + (_species_tech.get(orc_sp, 0) as int) * 2)
		var tgt_strength := float(target_army + target_tech * 2)
		# Orcs demand tribute if they're meaningfully stronger
		if orc_strength >= tgt_strength + 2.0:
			var weakness := orc_strength - tgt_strength
			if weakness > best_weakness:
				best_weakness = weakness
				best_target = sp
	if best_target == "" or rng.randf() > 0.50:
		return
	var tribute_key := _diplomacy_key(orc_sp, best_target)
	if _tribute_pending.has(tribute_key):
		return
	var amount := 8.0 + best_weakness * 1.5
	_tribute_pending[tribute_key] = {"amount": amount, "expires": world_year + 60, "demander": orc_sp, "target": best_target}
	_log_event("Año %d: Los Orcos exigen tributo a los %s (%s recursos). ¡Rechazarlo tiene consecuencias!" % [world_year, best_target, str(int(amount))], orc_sp)

func _try_enano_event(sp: String, era_key: String) -> void:
	var stock := _resource_stock(sp)
	# Festival de cerveza: peace + food stockpile
	var food := stock.get("food", 0.0) as float
	if food > 40.0 and not _any_war(sp) and rng.randf() < 0.35:
		for h in humans:
			if h.species_name == sp:
				h.evolution_score += 1.5
		stock["food"] = food - 8.0   # cerveza consume reservas
		_log_event("Año %d: ¡Los Enanos celebran el Gran Festival de Cerveza! La moral y la lealtad de los clanes se refuerzan." % world_year, sp)
		_last_species_event_era[era_key] = true
		return
	# Discover new vein: mine tiles present
	var mine_count := 0
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			if world_grid.get_owner(Vector2i(x, y)) == sp and world_grid.get_improvement(Vector2i(x, y)) == "mine":
				mine_count += 1
	if mine_count >= 2 and rng.randf() < 0.30:
		stock["iron"] = (stock.get("iron", 0.0) as float) + 20.0
		stock["stone"] = (stock.get("stone", 0.0) as float) + 15.0
		_log_event("Año %d: ¡Los mineros enanos descubren una nueva veta profunda! Las bóvedas se llenan de mineral." % world_year, sp)
		_last_species_event_era[era_key] = true

func _any_war(species: String) -> bool:
	for key: String in _war_pairs.keys():
		if key.contains(species):
			return true
	return false

# ── Elf deforestation sensitivity ─────────────────────────────────────────────
func _on_forest_tile_cleared(cell: Vector2i) -> void:
	# Only relevant when elves exist in the world
	var elf_nearby := false
	for h in humans:
		if h.species_name == "Elfos" and h.grid_position.distance_to(cell) <= 12.0:
			elf_nearby = true
			break
	if not elf_nearby:
		return
	# Who owns (or last owned) this tile — the responsible party
	var former_owner := world_grid.get_owner(cell)
	# If the tile belongs to elves themselves or is unclaimed, no penalty
	if former_owner == "Elfos" or former_owner == "":
		return
	var log_key := _diplomacy_key("Elfos", former_owner)
	_deforestation_log[log_key] = (_deforestation_log.get(log_key, 0) as int) + 1
	var count := _deforestation_log.get(log_key, 0) as int
	_set_relation("Elfos", former_owner, _get_relation("Elfos", former_owner) - 0.012)
	if count == SpeciesDataScript.elf_deforestation_warning_threshold():
		_log_event("Año %d: Los Elfos protestan por la tala de %s cerca de sus bosques sagrados." % [world_year, former_owner], "Elfos")
	elif count >= SpeciesDataScript.elf_deforestation_war_threshold():
		var war_key := _diplomacy_key("Elfos", former_owner)
		if not _war_pairs.has(war_key):
			_war_pairs[war_key] = true
			_last_war_tick["Elfos"] = world_year
			_log_event("Año %d: ¡Los Elfos declaran guerra a los %s por destrucción masiva de sus bosques sagrados!" % [world_year, former_owner], "Elfos")

# ── Tribute resolution ────────────────────────────────────────────────────────
func _resolve_expired_tributes() -> void:
	var to_erase: Array[String] = []
	for trib_key: String in _tribute_pending.keys():
		var t := _tribute_pending[trib_key] as Dictionary
		if world_year >= (t.get("expires", 0) as int):
			var demander := t.get("demander", "") as String
			var target   := t.get("target", "")   as String
			# Tribute expired = rejected -> relation penalty, possible war
			if demander != "" and target != "":
				_set_relation(demander, target, _get_relation(demander, target) - 0.15)
				_last_war_tick[demander] = world_year
				if rng.randf() < 0.60 and not _war_pairs.has(_diplomacy_key(demander, target)):
					_war_pairs[_diplomacy_key(demander, target)] = true
					_log_event("Año %d: Los %s rechazaron el tributo. Los Orcos desenvainan sus armas." % [world_year, target], demander)
				else:
					_log_event("Año %d: El tributo exigido a los %s venció sin respuesta." % [world_year, target], demander)
			to_erase.append(trib_key)
	for k: String in to_erase:
		_tribute_pending.erase(k)

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
			if world_grid.get_improvement(cell) != "":
				stats[owner]["buildings"] += 1
	for sp_name: String in stats.keys():
		var pop: int = stats[sp_name]["pop"]
		var tiles: int = stats[sp_name]["tiles"]
		if pop == 0 and tiles == 0:
			continue
		var evo: float = stats[sp_name]["evo"] / maxf(float(pop), 1.0)
		var buildings: int = stats[sp_name]["buildings"]
		var tech: int = _species_tech.get(sp_name, 0) as int
		var stock := _resource_stock(sp_name)
		var fleets := _fleet_state(sp_name)
		var pressure_state := _species_pressures.get(sp_name, _make_pressure_state()) as Dictionary
		var dom_rel := _dominant_religion(sp_name)
		var line := "%s: %d pop  %d terr  tec:%d  evo:%.1f" % [sp_name, pop, tiles, tech, evo]
		line += "  cap:%d/%d" % [pop, pressure_state.get("capacity", 0) as int]
		line += "  f:%.0f m:%.0f p:%.0f h:%.0f" % [
			stock.get("food", 0.0) as float,
			stock.get("wood", 0.0) as float,
			stock.get("stone", 0.0) as float,
			stock.get("iron", 0.0) as float,
		]
		var trade_f := fleets.get("trade", 0) as int
		var war_f := fleets.get("war", 0) as int
		if trade_f > 0 or war_f > 0:
			line += "  fl:%d/%d" % [trade_f, war_f]
		if pressure_state.get("starving", false) as bool:
			line += "  [HAMBRE]"
		elif (pressure_state.get("overcrowding", 0) as int) > 0:
			line += "  [HACINADOS]"
		if dom_rel != "" and dom_rel != (SPECIES_RELIGIONS.get(sp_name, "") as String):
			line += "  [" + dom_rel + "]"
		if pop == 0 and tiles > 0:
			line += "  [EXTINTO]"
		result.append(line)
	if result.is_empty():
		result.append("Sin entidades — usa tab Entidades")
		return result
	# ── Special system status ────────────────────────────────────────────────
	var special_lines: Array[String] = []
	# Dwarf grievances
	for g_key: String in _species_grievances.keys():
		var g := _species_grievances.get(g_key, 0) as int
		if g > 0:
			var parts := g_key.split("|")
			if parts.size() == 2:
				var who := parts[0] if parts[0] == "Enanos" else parts[1]
				var whom := parts[1] if parts[0] == "Enanos" else parts[0]
				special_lines.append("📖 Agravio Enano vs %s: %d/80" % [whom, g])
	# Pending tributes
	for trib_key: String in _tribute_pending.keys():
		var t := _tribute_pending[trib_key] as Dictionary
		var tgt := t.get("target", "?") as String
		var expires := t.get("expires", 0) as int
		special_lines.append("💰 Tributo exigido a %s (vence año %d)" % [tgt, expires])
	# Deforestation warnings
	for def_key: String in _deforestation_log.keys():
		var cnt := _deforestation_log.get(def_key, 0) as int
		if cnt >= SpeciesDataScript.elf_deforestation_warning_threshold():
			var parts := def_key.split("|")
			if parts.size() == 2:
				var other := parts[1] if parts[0] == "Elfos" else parts[0]
				special_lines.append("🌲 Deforestación élfica (%s): %d/20" % [other, cnt])

	if not special_lines.is_empty():
		result.append("── Sistemas Especiales ──")
		result.append_array(special_lines)

	var has_diplo := false
	for key: String in _war_pairs.keys():
		var p := key.split("|")
		if p.size() == 2:
			if not has_diplo:
				result.append("── Diplomacia ──")
				has_diplo = true
			result.append("⚔ %s vs %s" % [p[0], p[1]])
	for key: String in _alliance_pairs.keys():
		var p := key.split("|")
		if p.size() == 2:
			if not has_diplo:
				result.append("── Diplomacia ──")
				has_diplo = true
			result.append("★ %s ↔ %s" % [p[0], p[1]])
	# Relations summary (only non-neutral pairs)
	var has_rel := false
	for ii in SPECIES_LIBRARY.size():
		for jj in range(ii + 1, SPECIES_LIBRARY.size()):
			var sa := SPECIES_LIBRARY[ii]["name"] as String
			var sb := SPECIES_LIBRARY[jj]["name"] as String
			var rel := _get_relation(sa, sb)
			if absf(rel) >= 0.10:
				if not has_rel:
					result.append("── Relaciones ──")
					has_rel = true
				var bar := ""
				if rel >= 0.50:   bar = "+++"
				elif rel >= 0.25: bar = "++"
				elif rel >= 0.10: bar = "+"
				elif rel <= -0.50: bar = "---"
				elif rel <= -0.25: bar = "--"
				else:              bar = "-"
				result.append("%s %s ↔ %s" % [bar, sa, sb])
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

func _find_settlement_clusters() -> Array:
	var clusters: Array = []
	var visited := {}
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in range(world_grid.height):
		for x in range(world_grid.width):
			var start := Vector2i(x, y)
			if visited.has(start):
				continue
			var owner := world_grid.get_owner(start)
			var structure := world_grid.get_structure(start)
			var improvement := world_grid.get_improvement(start)
			if owner == "" or (structure == "" and improvement == ""):
				visited[start] = true
				continue
			var queue: Array[Vector2i] = [start]
			var cells: Array[Vector2i] = []
			var max_fort := 0
			while not queue.is_empty():
				var cell: Vector2i = queue.pop_back()
				if visited.has(cell):
					continue
				if world_grid.get_owner(cell) != owner:
					continue
				if world_grid.get_structure(cell) == "" and world_grid.get_improvement(cell) == "":
					continue
				visited[cell] = true
				cells.append(cell)
				max_fort = maxi(max_fort, world_grid.get_fortification(cell))
				for dir in dirs:
					var next := cell + dir
					if world_grid.is_in_bounds(next) and not visited.has(next):
						queue.push_back(next)
			if cells.size() > 0:
				clusters.append({"species": owner, "cells": cells, "fort": max_fort})
	return clusters

func _draw_settlement_perimeter(cluster: Dictionary) -> void:
	var fort_level := cluster["fort"] as int
	if fort_level <= 0:
		return
	var species: String = cluster["species"] as String
	var sp_color: Color = _species_colors.get(species, Color.WHITE) as Color
	var wall_color := Color(0.58, 0.36, 0.18).lerp(sp_color, 0.20)
	var wall_width := 2.2
	var inner_color := wall_color.darkened(0.25)
	match fort_level:
		2:
			wall_color = Color(0.68, 0.70, 0.74).lerp(sp_color, 0.15)
			inner_color = wall_color.darkened(0.30)
			wall_width = 3.0
		3:
			wall_color = Color(0.45, 0.50, 0.58).lerp(sp_color, 0.20)
			inner_color = sp_color.lightened(0.15)
			wall_width = 3.8
	var cell_set := {}
	for cell: Vector2i in cluster["cells"]:
		cell_set[cell] = true

	for cell: Vector2i in cluster["cells"]:
		var px := float(cell.x * TILE_SIZE)
		var py := float(cell.y * TILE_SIZE)
		if not cell_set.has(cell + Vector2i(1, 0)):
			draw_line(Vector2(px + TILE_SIZE, py), Vector2(px + TILE_SIZE, py + TILE_SIZE), wall_color, wall_width)
			if fort_level >= 2:
				draw_line(Vector2(px + TILE_SIZE - 1.5, py), Vector2(px + TILE_SIZE - 1.5, py + TILE_SIZE), inner_color, 1.0)
		if not cell_set.has(cell + Vector2i(-1, 0)):
			draw_line(Vector2(px, py), Vector2(px, py + TILE_SIZE), wall_color, wall_width)
			if fort_level >= 2:
				draw_line(Vector2(px + 1.5, py), Vector2(px + 1.5, py + TILE_SIZE), inner_color, 1.0)
		if not cell_set.has(cell + Vector2i(0, 1)):
			draw_line(Vector2(px, py + TILE_SIZE), Vector2(px + TILE_SIZE, py + TILE_SIZE), wall_color, wall_width)
			if fort_level >= 2:
				draw_line(Vector2(px, py + TILE_SIZE - 1.5), Vector2(px + TILE_SIZE, py + TILE_SIZE - 1.5), inner_color, 1.0)
		if not cell_set.has(cell + Vector2i(0, -1)):
			draw_line(Vector2(px, py), Vector2(px + TILE_SIZE, py), wall_color, wall_width)
			if fort_level >= 2:
				draw_line(Vector2(px, py + 1.5), Vector2(px + TILE_SIZE, py + 1.5), inner_color, 1.0)

	# Corner towers for stone and iron walls
	if fort_level >= 2:
		var tower_r := 2.5 if fort_level == 2 else 3.5
		var tower_c := wall_color.lightened(0.12)
		for cell: Vector2i in cluster["cells"]:
			for cdx: int in [0, 1]:
				for cdy: int in [0, 1]:
					var cx_i: int = cell.x + cdx
					var cy_i: int = cell.y + cdy
					# Count how many of the 4 tiles sharing this corner are in the set
					var n := 0
					for nx: int in [cx_i - 1, cx_i]:
						for ny: int in [cy_i - 1, cy_i]:
							if cell_set.has(Vector2i(nx, ny)):
								n += 1
					# Only draw at convex outer corners (exactly 1 tile from cluster)
					if n == 1:
						var wp := Vector2(float(cx_i * TILE_SIZE), float(cy_i * TILE_SIZE))
						draw_circle(wp, tower_r, tower_c)
						if fort_level == 3:
							draw_circle(wp, tower_r * 0.55, sp_color.lightened(0.30))

	# Battlements (crenellations) on top walls for iron level
	if fort_level == 3:
		var batt_c := sp_color.lightened(0.35)
		for cell: Vector2i in cluster["cells"]:
			if not cell_set.has(cell + Vector2i(0, -1)):
				var px := float(cell.x * TILE_SIZE)
				var py := float(cell.y * TILE_SIZE)
				var step := 4.0
				var bt := px
				while bt < px + float(TILE_SIZE) - step:
					draw_rect(Rect2(bt + 0.5, py - 3.0, step * 0.45, 3.0), batt_c)
					bt += step

func _draw_housing(cx: float, cy: float, sc: Color) -> void:
	var base := Color(0.84, 0.78, 0.66)
	draw_rect(Rect2(cx - 2.8, cy - 0.5, 5.6, 4.0), base)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, cy - 4.0), Vector2(cx - 3.5, cy - 0.5), Vector2(cx + 3.5, cy - 0.5)
	]), sc.lerp(Color(0.65, 0.24, 0.18), 0.45))

func _draw_farm(cx: float, cy: float, _sc: Color) -> void:
	var soil := Color(0.58, 0.40, 0.18, 0.85)
	for oy in [-3.0, -1.0, 1.0, 3.0]:
		draw_line(Vector2(cx - 5.5, cy + oy), Vector2(cx + 5.5, cy + oy), soil, 1.0)
	for sx in [-4.0, -1.5, 1.0, 3.5]:
		draw_line(Vector2(cx + sx, cy - 4.0), Vector2(cx + sx + 1.2, cy - 5.2), Color(0.55, 0.82, 0.28, 0.9), 1.0)

func _draw_mine(cx: float, cy: float, _sc: Color) -> void:
	var rock := Color(0.48, 0.48, 0.52)
	draw_rect(Rect2(cx - 4.5, cy - 2.5, 9.0, 5.0), rock)
	draw_line(Vector2(cx - 5.0, cy + 4.0), Vector2(cx - 1.0, cy - 3.5), Color(0.55, 0.34, 0.18), 1.4)
	draw_line(Vector2(cx - 1.0, cy - 3.5), Vector2(cx + 3.0, cy + 4.0), Color(0.78, 0.78, 0.80), 1.2)

func _draw_dock(cx: float, cy: float, sc: Color) -> void:
	var wood := Color(0.58, 0.38, 0.20)
	draw_line(Vector2(cx - 5.0, cy + 3.0), Vector2(cx + 5.0, cy + 3.0), wood, 1.8)
	for px in [-4.0, -1.0, 2.0]:
		draw_line(Vector2(cx + px, cy + 3.0), Vector2(cx + px, cy + 6.0), wood, 1.2)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 2.8, cy - 1.5), Vector2(cx, cy - 5.0), Vector2(cx + 2.8, cy - 1.5)
	]), sc.lightened(0.35))

func _draw_border_segment(owner: String, cell: Vector2i, neighbor: Vector2i, a: Vector2, b: Vector2, default_color: Color) -> void:
	var neighbor_owner := world_grid.get_owner(neighbor)
	if neighbor_owner == owner:
		return
	if neighbor_owner != "":
		var pair_key := _diplomacy_key(owner, neighbor_owner)
		if _war_pairs.has(pair_key):
			var pulse := 0.55 + 0.45 * sin(float(Time.get_ticks_msec()) / 140.0 + float(cell.x + cell.y))
			var war_color := Color(1.0, 0.20 + 0.30 * pulse, 0.10, 0.55 + 0.30 * pulse)
			draw_line(a, b, war_color, 3.0)
			var mid := a.lerp(b, 0.5)
			var attack_dir := (b - a).normalized()
			var normal := Vector2(-attack_dir.y, attack_dir.x)
			draw_line(mid - normal * 2.5, mid + attack_dir * 3.0, Color(1.0, 0.9, 0.35, 0.9), 1.4)
			draw_line(mid + normal * 2.5, mid - attack_dir * 3.0, Color(1.0, 0.9, 0.35, 0.9), 1.4)
			return
	draw_line(a, b, default_color, 1.5)

func _draw_fortification(cx: float, cy: float, level: int, sc: Color) -> void:
	match level:
		1:
			var wood := Color(0.56, 0.36, 0.18)
			draw_rect(Rect2(cx - 7.0, cy - 6.5, 14.0, 11.0), wood, false, 1.2)
			for px in [-5.5, -3.0, -0.5, 2.0, 4.5]:
				draw_line(Vector2(cx + px, cy + 4.8), Vector2(cx + px, cy - 6.5), wood.lightened(0.08), 1.2)
		2:
			var stone := Color(0.62, 0.64, 0.68)
			draw_rect(Rect2(cx - 7.5, cy - 7.0, 15.0, 12.0), stone, false, 1.8)
			for px in [-5.5, -2.5, 0.5, 3.5]:
				draw_rect(Rect2(cx + px, cy - 8.2, 1.7, 2.0), stone.darkened(0.08))
		3:
			var iron := Color(0.46, 0.50, 0.56)
			var glow := sc.lightened(0.15)
			draw_rect(Rect2(cx - 8.0, cy - 7.5, 16.0, 13.0), iron, false, 2.2)
			draw_rect(Rect2(cx - 5.0, cy - 9.0, 10.0, 2.0), glow.darkened(0.2))
			for px in [-5.5, -2.0, 1.5, 5.0]:
				draw_circle(Vector2(cx + px, cy - 1.5), 0.8, glow)

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
	for line: String in raw:
		stats_lines.append(line)
		if line.begins_with("──"):
			stats_colors.append(Color(0.55, 0.55, 0.55))
		elif line.begins_with("⚔"):
			stats_colors.append(Color(1.0, 0.35, 0.35))
		elif line.begins_with("★"):
			stats_colors.append(Color(1.0, 0.88, 0.20))
		else:
			var matched_color := Color(0.75, 0.75, 0.75)
			for sp: Dictionary in SPECIES_LIBRARY:
				if line.begins_with(sp["name"] as String):
					matched_color = (_species_colors.get(sp["name"] as String, Color.WHITE) as Color).lightened(0.2)
					break
			stats_colors.append(matched_color)
	var hero_lines: Array[String] = []
	var hero_colors: Array[Color] = []
	for h in humans:
		if h.is_hero:
			hero_lines.append("★ %s (%s) — %d batallas" % [h.hero_name, h.species_name, h.battles_won])
			hero_colors.append((_species_colors.get(h.species_name, Color.WHITE) as Color))
	var advisory_prompt := _active_advice.get("prompt", "") as String if not _active_advice.is_empty() else ""
	var advisory_options: Array[String] = []
	if not _active_advice.is_empty():
		advisory_options.assign(_active_advice.get("options", []) as Array)
	hud.war_active = not _war_pairs.is_empty()
	hud.refresh(stats_lines, stats_colors, _chronicle, _chronicle_colors, hero_lines, hero_colors, world_year, advisory_prompt, not _active_advice.is_empty())
	ui.set_chronicle_prompt(advisory_prompt, not _active_advice.is_empty(), advisory_options)

	# Update cluster caches (expensive operations, amortised once per tick)
	_settlement_cluster_cache = _find_settlement_clusters()
	_territory_cluster_cache  = _find_territory_clusters()

	# Minimap pixel data
	_build_and_push_minimap()

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
	# Colours matched to the web design palette (data.js BIOMES)
	match biome:
		"water":    return Color(0.165, 0.373, 0.659)   # #2a5fa8
		"sand":     return Color(0.831, 0.722, 0.439)   # #d4b870
		"grass":    return Color(0.353, 0.620, 0.220)   # #5a9e38
		"forest":   return Color(0.176, 0.431, 0.176)   # #2d6e2d
		"mountain": return Color(0.541, 0.541, 0.604)   # #8a8a9a
		"snow":     return Color(0.910, 0.941, 0.973)   # #e8f0f8
		"jungle":   return Color(0.102, 0.420, 0.125)   # #1a6b20
		"swamp":    return Color(0.282, 0.392, 0.196)   # #486432
		_:          return Color.WHITE

func _biome_dark_color(biome: String) -> Color:
	# Darker checkerboard variant (data.js BIOMES .dark)
	match biome:
		"water":    return Color(0.102, 0.247, 0.533)   # #1a3f88
		"sand":     return Color(0.706, 0.596, 0.314)   # #b49850
		"grass":    return Color(0.227, 0.494, 0.094)   # #3a7e18
		"forest":   return Color(0.114, 0.306, 0.114)   # #1d4e1d
		"mountain": return Color(0.416, 0.416, 0.478)   # #6a6a7a
		"snow":     return Color(0.753, 0.800, 0.847)   # #c0ccd8
		"jungle":   return Color(0.059, 0.290, 0.078)   # #0f4a14
		"swamp":    return Color(0.196, 0.275, 0.118)   # #324718
		_:          return Color.DARK_GRAY

# ── Per-tile biome detail decorations ─────────────────────────────────────────
# Called from _draw() for every tile; uses deterministic per-cell hashing
# so the pattern is stable across redraws without storing extra data.
func _draw_biome_detail(x: int, y: int, biome: String) -> void:
	var px := float(x) * TILE_SIZE
	var py := float(y) * TILE_SIZE
	var ts := float(TILE_SIZE)
	var hv  := float((x * 7919 + y * 2053) & 0xFF) / 255.0
	var hv2 := float((x * 3571 + y * 8191) & 0xFF) / 255.0
	var hv3 := float((x * 1021 + y * 4093) & 0xFF) / 255.0
	var hv4 := float((x * 2549 + y * 6143) & 0xFF) / 255.0
	match biome:
		"water":
			var wc := Color(0.72, 0.90, 1.0, 0.28)
			draw_arc(Vector2(px + ts*(0.15+hv*0.40),  py + ts*(0.28+hv2*0.25)), ts*0.22, PI, TAU, 7, wc, 1.0)
			draw_arc(Vector2(px + ts*(0.15+hv3*0.40), py + ts*(0.60+hv4*0.20)), ts*0.16, PI, TAU, 6, wc, 1.0)
		"sand":
			var sc := Color(0.60, 0.52, 0.26, 0.55)
			for i in 3:
				var ph  := float(((x + i*127)*7919 + y*2053) & 0xFF) / 255.0
				var ph2 := float((x*3571 + (y + i*91)*8191) & 0xFF) / 255.0
				draw_circle(Vector2(px + ts*(0.12+ph*0.76), py + ts*(0.12+ph2*0.76)), ts*(0.05+ph*0.06), sc)
		"grass":
			var bc := Color(0.12, 0.48, 0.12, 0.60)
			for i in 2:
				var ph  := float(((x+i*53)*7919 + y*2053) & 0xFF) / 255.0
				var ph2 := float((x*3571 + (y+i*71)*8191) & 0xFF) / 255.0
				var bx  := px + ts*(0.18+ph*0.64)
				var by  := py + ts*(0.55+ph2*0.32)
				var bh  := ts * 0.32
				draw_line(Vector2(bx, by), Vector2(bx - ts*0.09, by - bh), bc, 1.0)
				draw_line(Vector2(bx, by), Vector2(bx + ts*0.09, by - bh), bc, 1.0)
		"forest":
			var fc1 := Color(0.04, 0.22, 0.06, 0.84)
			var fc2 := Color(0.10, 0.38, 0.10, 0.68)
			draw_circle(Vector2(px + ts*(0.32+hv*0.36), py + ts*(0.34+hv2*0.32)), ts*0.40, fc1)
			draw_circle(Vector2(px + ts*(0.30+hv3*0.26), py + ts*(0.30+hv4*0.26)), ts*0.22, fc2)
		"mountain":
			var peak_x := px + ts*(0.28+hv*0.44)
			var peak_y := py + ts*(0.05+hv2*0.14)
			var base_y := py + ts*0.92
			var hw     := ts*(0.26+hv3*0.18)
			# Left face (lighter)
			draw_colored_polygon(PackedVector2Array([
				Vector2(peak_x, peak_y), Vector2(peak_x-hw, base_y), Vector2(peak_x, base_y),
			]), Color(0.72, 0.70, 0.66, 0.90))
			# Right face (darker)
			draw_colored_polygon(PackedVector2Array([
				Vector2(peak_x, peak_y), Vector2(peak_x, base_y), Vector2(peak_x+hw, base_y),
			]), Color(0.36, 0.34, 0.32, 0.90))
			# Snow cap
			draw_colored_polygon(PackedVector2Array([
				Vector2(peak_x, peak_y),
				Vector2(peak_x - hw*0.24, peak_y + ts*0.20),
				Vector2(peak_x + hw*0.24, peak_y + ts*0.20),
			]), Color(0.96, 0.96, 0.98, 0.94))
		"snow":
			# Snowflake dots + ice crack lines
			var sc := Color(1.0, 1.0, 1.0, 0.55)
			for i in 4:
				var ph  := float(((x + i*137)*7919 + y*2053) & 0xFF) / 255.0
				var ph2 := float((x*3571 + (y + i*89)*8191) & 0xFF) / 255.0
				draw_circle(Vector2(px + ts*(0.10+ph*0.80), py + ts*(0.10+ph2*0.80)), ts*(0.04+ph*0.03), sc)
			var ic_c := Color(0.60, 0.72, 0.84, 0.30)
			draw_line(Vector2(px+ts*(0.15+hv*0.28), py+ts*0.18), Vector2(px+ts*(0.52+hv2*0.18), py+ts*0.78), ic_c, 1.0)
		"jungle":
			# Dense overlapping canopy circles, darker than forest
			var jc1 := Color(0.05, 0.28, 0.06, 0.90)
			var jc2 := Color(0.10, 0.42, 0.12, 0.75)
			var jc3 := Color(0.18, 0.55, 0.18, 0.55)
			draw_circle(Vector2(px + ts*(0.22+hv*0.56),  py + ts*(0.38+hv2*0.38)), ts*0.44, jc1)
			draw_circle(Vector2(px + ts*(0.44+hv3*0.38), py + ts*(0.28+hv4*0.28)), ts*0.36, jc2)
			draw_circle(Vector2(px + ts*(0.18+hv2*0.42), py + ts*(0.20+hv3*0.26)), ts*0.28, jc3)
		"swamp":
			# Charco + juncos
			var wc := Color(0.18, 0.28, 0.12, 0.65)
			draw_circle(Vector2(px + ts*(0.22+hv*0.40), py + ts*(0.45+hv2*0.30)), ts*0.32, wc)
			# Juncos (líneas verticales)
			var rc := Color(0.22, 0.45, 0.12, 0.80)
			for i in 3:
				var ph := float(((x + i*97)*7919 + y*2053) & 0xFF) / 255.0
				var ph2 := float((x*3571 + (y+i*61)*8191) & 0xFF) / 255.0
				var rx := px + ts*(0.12 + ph*0.76)
				var ry := py + ts*(0.50 + ph2*0.20)
				draw_line(Vector2(rx, ry), Vector2(rx + ts*0.04, ry - ts*0.42), rc, 1.5)
				draw_circle(Vector2(rx + ts*0.04, ry - ts*0.44), ts*0.05, rc.darkened(0.20))

# ── Minimap ──────────────────────────────────────────────────────────────────

func _build_and_push_minimap() -> void:
	var mw := WORLD_WIDTH
	var mh := WORLD_HEIGHT
	var pixels := PackedByteArray()
	pixels.resize(mw * mh * 3)
	var idx := 0
	for y in range(mh):
		for x in range(mw):
			var cell := Vector2i(x, y)
			var bc := _biome_color(world_grid.get_biome(cell))
			var owner := world_grid.get_owner(cell)
			if owner != "":
				var sc := _species_colors.get(owner, Color.WHITE) as Color
				bc = bc.lerp(sc, 0.42)
			if world_effects.fire_cells.has(cell):
				bc = Color(0.90, 0.38, 0.08)
			var structure := world_grid.get_structure(cell)
			if structure == "town":
				bc = bc.lightened(0.30)
			elif structure == "village":
				bc = bc.lightened(0.16)
			pixels[idx]     = int(bc.r8)
			pixels[idx + 1] = int(bc.g8)
			pixels[idx + 2] = int(bc.b8)
			idx += 3
	hud.update_minimap(pixels, mw, mh)

func _update_minimap_cam_rect() -> void:
	if hud == null or camera == null:
		return
	var vp := get_viewport_rect().size
	var half := vp * 0.5 / camera.zoom.x
	var top_left  := (camera.position - half) / TILE_SIZE
	var bot_right := (camera.position + half) / TILE_SIZE
	hud.update_minimap_camera(Rect2(top_left, bot_right - top_left))
