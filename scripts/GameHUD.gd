extends Node2D
class_name GameHUD

var stats_lines: Array[String] = []
var stats_colors: Array[Color] = []
var chronicle: Array[String] = []
var chronicle_colors: Array[Color] = []
var hero_lines: Array[String] = []
var hero_colors: Array[Color] = []
var world_year := 0
var advisory_text := ""
var advisory_waiting := false

func refresh(
		p_stats: Array[String], p_stats_c: Array[Color],
		p_chron: Array[String], p_chron_c: Array[Color],
		p_heroes: Array[String], p_hero_c: Array[Color],
		p_year: int,
		p_advisory: String = "",
		p_waiting: bool = false) -> void:
	stats_lines = p_stats
	stats_colors = p_stats_c
	chronicle = p_chron
	chronicle_colors = p_chron_c
	hero_lines = p_heroes
	hero_colors = p_hero_c
	world_year = p_year
	advisory_text = p_advisory
	advisory_waiting = p_waiting
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size

	var sw := 340.0
	var sh := 10.0 + stats_lines.size() * 16.0 + 6.0
	draw_rect(Rect2(0, 0, sw, sh), Color(0.04, 0.04, 0.10, 0.84))
	var sy := 15.0
	for i in stats_lines.size():
		var c := stats_colors[i] if i < stats_colors.size() else Color(0.85, 0.85, 0.85)
		draw_string(font, Vector2(8, sy), stats_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)
		sy += 16.0

	var cp_w := 280.0
	var cx0 := vp.x - cp_w - 4.0
	var vis := mini(chronicle.size(), 18)
	var cp_h := 22.0 + vis * 13.0 + 4.0
	draw_rect(Rect2(cx0 - 4, 0, cp_w + 8, cp_h), Color(0.04, 0.04, 0.10, 0.84))
	draw_string(font, Vector2(cx0, 14), "CRONICA Ano %d" % world_year, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.88, 0.80, 0.40))
	var start_i := maxi(0, chronicle.size() - 18)
	var cry := 27.0
	for i in range(start_i, chronicle.size()):
		var ec := chronicle_colors[i] if i < chronicle_colors.size() else Color(0.8, 0.8, 0.8)
		draw_string(font, Vector2(cx0, cry), chronicle[i], HORIZONTAL_ALIGNMENT_LEFT, int(cp_w), 9, ec.lightened(0.2))
		cry += 13.0

	if advisory_text != "":
		var ay := cp_h + 4.0
		var ah := 32.0
		draw_rect(Rect2(cx0 - 4, ay, cp_w + 8, ah), Color(0.15, 0.10, 0.04, 0.92))
		draw_string(font, Vector2(cx0, ay + 12.0), "Consejo del consejo" if advisory_waiting else "Consejo archivado", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.86, 0.35))
		draw_string(font, Vector2(cx0, ay + 24.0), advisory_text, HORIZONTAL_ALIGNMENT_LEFT, int(cp_w), 9, Color(0.92, 0.92, 0.88))
		cp_h += ah + 4.0

	if hero_lines.is_empty():
		return
	var hy := cp_h + 4.0
	var hp_h := 18.0 + hero_lines.size() * 13.0 + 4.0
	draw_rect(Rect2(cx0 - 4, hy, cp_w + 8, hp_h), Color(0.08, 0.06, 0.02, 0.86))
	draw_string(font, Vector2(cx0, hy + 13), "HEROES VIVOS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.85, 0.20))
	var hcy := hy + 26.0
	for i in hero_lines.size():
		var hc := hero_colors[i] if i < hero_colors.size() else Color(1.0, 0.85, 0.20)
		draw_string(font, Vector2(cx0, hcy), hero_lines[i], HORIZONTAL_ALIGNMENT_LEFT, int(cp_w), 9, hc.lightened(0.3))
		hcy += 13.0
