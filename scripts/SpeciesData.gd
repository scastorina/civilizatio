extends RefCounted
class_name SpeciesData

# ── Habitat modifiers ─────────────────────────────────────────────────────────
# Returns { "evo": float, "combat": float, "defense": float }
# evo    : added to evolution_score per tick when in this biome
# combat : multiplier applied on top of species base combat stat
# defense: multiplier applied on top of species base defense stat
static func habitat_mod(species: String, biome: String) -> Dictionary:
	var base := {"evo": 0.0, "combat": 1.0, "defense": 1.0}
	match species:
		"Humanos":
			match biome:
				"grass":    base = {"evo":  0.012, "combat": 1.00, "defense": 1.00}
				"sand":     base = {"evo":  0.004, "combat": 0.95, "defense": 0.95}
				"forest":   base = {"evo": -0.003, "combat": 0.88, "defense": 0.92}
				"mountain": base = {"evo": -0.012, "combat": 0.75, "defense": 0.80}
		"Elfos":
			match biome:
				"forest":   base = {"evo":  0.030, "combat": 1.25, "defense": 1.45}
				"grass":    base = {"evo":  0.008, "combat": 0.95, "defense": 1.00}
				"sand":     base = {"evo": -0.025, "combat": 0.70, "defense": 0.75}
				"mountain": base = {"evo": -0.018, "combat": 0.65, "defense": 0.80}
		"Enanos":
			match biome:
				"mountain": base = {"evo":  0.022, "combat": 1.20, "defense": 1.60}
				"forest":   base = {"evo":  0.004, "combat": 0.88, "defense": 1.10}
				"grass":    base = {"evo": -0.004, "combat": 0.82, "defense": 0.82}
				"sand":     base = {"evo": -0.015, "combat": 0.75, "defense": 0.75}
		"Orcos":
			match biome:
				"sand":     base = {"evo":  0.014, "combat": 1.15, "defense": 1.05}
				"grass":    base = {"evo":  0.010, "combat": 1.08, "defense": 1.00}
				"forest":   base = {"evo":  0.001, "combat": 0.92, "defense": 0.88}
				"mountain": base = {"evo":  0.008, "combat": 1.05, "defense": 1.12}
	return base

# ── Tech research speed multiplier ───────────────────────────────────────────
# Multiplies how fast a species accumulates research points
static func tech_speed_mult(species: String) -> float:
	match species:
		"Humanos": return 1.00   # balanced
		"Elfos":   return 0.70   # slow academic, but gets magic bonus elsewhere
		"Enanos":  return 0.88   # strong in engineering, average overall
		"Orcos":   return 0.60   # learn primarily through conquest
	return 1.0

# Extra research boost when at war (Orcos learn by fighting)
static func tech_war_bonus(species: String) -> float:
	match species:
		"Orcos":   return 0.35   # +35% research during active war
		"Enanos":  return 0.10   # defensive mastery under pressure
		"Humanos": return 0.05
		"Elfos":   return 0.0
	return 0.0

# ── Base relations between species pairs ─────────────────────────────────────
# Returns value in [-1, 1]
static func base_relation(sp_a: String, sp_b: String) -> float:
	var pair := [sp_a, sp_b]
	pair.sort()
	var key := (pair[0] as String) + "|" + (pair[1] as String)
	match key:
		"Elfos|Humanos":    return  0.15
		"Humanos|Orcos":    return -0.10
		"Enanos|Humanos":   return  0.20
		"Elfos|Orcos":      return -0.25
		"Elfos|Enanos":     return  0.05
		"Enanos|Orcos":     return -0.35
	return 0.0

# ── War trigger weights ───────────────────────────────────────────────────────
# How likely a species is to declare war for a given reason (0–1)
static func war_trigger_weight(species: String, trigger: String) -> float:
	var weights: Dictionary = {}
	match species:
		"Humanos":
			weights = {
				"expansion":        0.80, "recursos":        0.75,
				"ruta_comercial":   0.70, "aliado_atacado":  0.65,
				"vecino_debil":     0.60, "religion":        0.40,
				"venganza":         0.55,
			}
		"Elfos":
			weights = {
				"deforestacion":    0.95, "sitio_sagrado":   0.90,
				"ataque_aldea":     0.85, "ruptura_pacto":   0.70,
				"expansion":        0.20, "vecino_debil":    0.08,
			}
		"Orcos":
			weights = {
				"vecino_debil":     0.85, "recursos_escasos": 0.80,
				"tributo_rechazado":0.90, "expansion":        0.65,
				"humillacion":      0.75, "inactividad_larga":0.65,
			}
		"Enanos":
			weights = {
				"invasion_tunel":   0.95, "robo_recursos":   0.90,
				"contrato_roto":    0.85, "ataque_mina":     0.90,
				"agravio_maximo":   1.00, "profanacion":     0.95,
				"expansion":        0.20, "vecino_debil":    0.15,
			}
	return weights.get(trigger, 0.30)

# ── Dwarf Libro de Agravios: grievance points per event ──────────────────────
static func grievance_points(event_type: String) -> int:
	match event_type:
		"contrato_roto":   return 40
		"ataque_ciudad":   return 30
		"robo_recursos":   return 25
		"invasion_tunel":  return 35
		"insulto_diplo":   return 15
		"deuda_impaga":    return 20
		"alianza_enemigo": return 15
		"ataque_mina":     return 30
	return 0

# ── AI personality ────────────────────────────────────────────────────────────
static func ai_personality(species: String) -> Dictionary:
	match species:
		"Humanos":
			return {
				"expansionismo": 0.75, "agresividad": 0.45, "diplomacia": 0.70,
				"comercio": 0.80,      "defensa": 0.55,     "oportunismo": 0.70,
				"respeto_naturaleza": 0.30, "memoria_agravio": 0.45, "honor": 0.50,
			}
		"Elfos":
			return {
				"expansionismo": 0.25, "agresividad": 0.30, "diplomacia": 0.60,
				"comercio": 0.45,      "defensa": 0.80,     "oportunismo": 0.25,
				"respeto_naturaleza": 1.00, "memoria_agravio": 0.80, "honor": 0.75,
			}
		"Orcos":
			return {
				"expansionismo": 0.65, "agresividad": 0.85, "diplomacia": 0.30,
				"comercio": 0.35,      "defensa": 0.45,     "oportunismo": 0.80,
				"respeto_naturaleza": 0.20, "memoria_agravio": 0.70, "honor": 0.70,
			}
		"Enanos":
			return {
				"expansionismo": 0.35, "agresividad": 0.45, "diplomacia": 0.50,
				"comercio": 0.75,      "defensa": 0.95,     "oportunismo": 0.35,
				"respeto_naturaleza": 0.35, "memoria_agravio": 0.98, "honor": 0.85,
			}
	return {}

# ── Species description strings ───────────────────────────────────────────────
static func description(species: String) -> String:
	match species:
		"Humanos":
			return "Adaptables, comerciantes y expansionistas. No son los mejores en nada, pero lo intentan todo."
		"Elfos":
			return "Antiguos, mágicos y vinculados al bosque. Lentos para actuar, implacables cuando lo hacen."
		"Orcos":
			return "Fuertes, tribales y honorables a su manera. Si tu ejército es débil y tu ciudad es rica, ya tomaron una decisión."
		"Enanos":
			return "Maestros de la forja, la piedra y el rencor. Si lo prometieron, lo cumplen. Si los traicionaron, tampoco lo olvidan."
	return ""

# ── Orc tribute demand: minimum relative strength to demand tribute ───────────
# Orcs demand tribute when their army is >= this ratio of target's army
static func orc_tribute_strength_ratio() -> float:
	return 0.65

# ── Elf deforestation thresholds ──────────────────────────────────────────────
# How many forest tiles need to be cleared near elf territory before triggering
static func elf_deforestation_warning_threshold() -> int:
	return 6

static func elf_deforestation_war_threshold() -> int:
	return 20

# ── Dwarf grievance thresholds ────────────────────────────────────────────────
static func dwarf_grievance_warning_threshold() -> int:
	return 35

static func dwarf_grievance_war_threshold() -> int:
	return 80

# ── Orc inactivity threshold (ticks without war before internal conflict) ─────
static func orc_inactivity_war_ticks() -> int:
	return 80

# ── Trade bonus multiplier per species (applied to evolution near trade hubs) ─
static func trade_evo_bonus(species: String) -> float:
	match species:
		"Humanos": return 0.040   # 60% more than base
		"Elfos":   return 0.020   # only if with peaceful partner
		"Enanos":  return 0.030   # strong commercial culture
		"Orcos":   return 0.008   # barely care about markets
	return 0.015

# ── Species-specific preferred improvement logic ──────────────────────────────
# Whether this species should build a mine in a non-mountain biome
static func mine_non_mountain_allowed(species: String) -> bool:
	return species == "Enanos"   # dwarves mine anywhere

# ── Species diplomacy description ─────────────────────────────────────────────
static func diplo_greeting(species: String) -> String:
	match species:
		"Humanos": return "Siempre hay espacio para un buen trato."
		"Elfos":   return "El bosque recuerda. Nosotros también."
		"Orcos":   return "¿Eres fuerte o vienes a perder el tiempo?"
		"Enanos":  return "Un trato justo es mejor que mil palabras."
	return ""

static func diplo_threat(species: String) -> String:
	match species:
		"Humanos": return "No obligues a nuestra mano a actuar."
		"Elfos":   return "Cada árbol talado es una flecha apuntada hacia ti."
		"Orcos":   return "Tu ejército duerme. El nuestro no."
		"Enanos":  return "Lo anotamos. Todo. Y cobramos con intereses."
	return ""
