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

# ── Aesthetic theme constants (web palette) ───────────────────────────────────
const C_SURF    := Color(0.063, 0.082, 0.122, 0.92)   # --surf  #10151f
const C_SURF2   := Color(0.090, 0.118, 0.173, 0.94)   # --surf2 #171e2e
const C_SURF3   := Color(0.118, 0.153, 0.251, 0.94)   # --surf3 #1e2740
const C_BORDER  := Color(0.142, 0.177, 0.267, 1.0)    # --border #242d44
const C_ACC     := Color(0.784, 0.573, 0.165)          # --acc  #c8922a
const C_TEXT    := Color(0.831, 0.800, 0.722)          # --text #d4ccb8
const C_MUTED   := Color(0.416, 0.392, 0.314)          # --muted #6a6450

# War-flash state (set each tick from Main.gd)
var war_active: bool = false
var _hud_tick: int = 0

var _minimap_tex: ImageTexture = null
var _minimap_w := 0
var _minimap_h := 0
# Viewport rectangle on the minimap (in minimap-pixel coords), set each frame
var _minimap_cam_rect := Rect2()

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

func update_minimap(pixels: PackedByteArray, w: int, h: int) -> void:
	_minimap_w = w
	_minimap_h = h
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGB8, pixels)
	if _minimap_tex == null:
		_minimap_tex = ImageTexture.create_from_image(img)
	else:
		_minimap_tex.update(img)
	queue_redraw()

func update_minimap_camera(cam_rect: Rect2) -> void:
	_minimap_cam_rect = cam_rect
	queue_redraw()

func _draw() -> void:
	_hud_tick += 1
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size

	# ── Stats panel (top-left) ──────────────────────────────────────────────────
	var sw := 340.0
	var sh := 10.0 + stats_lines.size() * 16.0 + 6.0
	draw_rect(Rect2(0, 0, sw, sh), C_SURF)
	draw_rect(Rect2(0, sh - 1, sw, 1), C_BORDER)   # bottom accent line
	var sy := 15.0
	for i in stats_lines.size():
		var c := stats_colors[i] if i < stats_colors.size() else C_TEXT
		draw_string(font, Vector2(8, sy), stats_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)
		sy += 16.0

	# ── Chronicle panel (top-right) ─────────────────────────────────────────────
	var cp_w := 280.0
	var cx0 := vp.x - cp_w - 4.0
	var vis := mini(chronicle.size(), 18)
	var cp_h := 22.0 + vis * 13.0 + 4.0
	draw_rect(Rect2(cx0 - 4, 0, cp_w + 8, cp_h), C_SURF)
	draw_rect(Rect2(cx0 - 4, cp_h - 1, cp_w + 8, 1), C_BORDER)
	draw_string(font, Vector2(cx0, 14), "CRÓNICA  Año %d" % world_year, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_ACC)
	var start_i := maxi(0, chronicle.size() - 18)
	var cry := 27.0
	for i in range(start_i, chronicle.size()):
		var ec := chronicle_colors[i] if i < chronicle_colors.size() else C_TEXT
		draw_string(font, Vector2(cx0, cry), chronicle[i], HORIZONTAL_ALIGNMENT_LEFT, int(cp_w), 9, ec.lightened(0.15))
		cry += 13.0

	if advisory_text != "":
		var ay := cp_h + 4.0
		var ah := 32.0
		draw_rect(Rect2(cx0 - 4, ay, cp_w + 8, ah), C_SURF2)
		draw_rect(Rect2(cx0 - 4, ay, 2, ah), C_ACC)  # left accent stripe
		draw_string(font, Vector2(cx0 + 4, ay + 12.0), "Consejo del consejo" if advisory_waiting else "Consejo archivado", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_ACC)
		draw_string(font, Vector2(cx0 + 4, ay + 24.0), advisory_text, HORIZONTAL_ALIGNMENT_LEFT, int(cp_w), 9, C_TEXT)
		cp_h += ah + 4.0

	if not hero_lines.is_empty():
		var hy := cp_h + 4.0
		var hp_h := 18.0 + hero_lines.size() * 13.0 + 4.0
		draw_rect(Rect2(cx0 - 4, hy, cp_w + 8, hp_h), C_SURF2)
		draw_rect(Rect2(cx0 - 4, hy, 2, hp_h), Color(0.784, 0.706, 0.125))  # gold left stripe
		draw_string(font, Vector2(cx0 + 4, hy + 13), "HÉROES VIVOS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.784, 0.706, 0.125))
		var hcy := hy + 26.0
		for i in hero_lines.size():
			var hc := hero_colors[i] if i < hero_colors.size() else C_ACC
			draw_string(font, Vector2(cx0 + 4, hcy), hero_lines[i], HORIZONTAL_ALIGNMENT_LEFT, int(cp_w), 9, hc.lightened(0.25))
			hcy += 13.0

	# ── Minimap (bottom-left, above toolbar) ────────────────────────────────────
	if _minimap_tex == null or _minimap_w == 0:
		_draw_vignette(vp)
		return

	const TOOLBAR_H := 152.0   # BAR_H(72) + PANEL_H(78) + 2px gap
	const MM_SCALE  := 2.0     # pixels per world tile
	var mm_w := float(_minimap_w) * MM_SCALE
	var mm_h := float(_minimap_h) * MM_SCALE
	var mm_x := 4.0
	var mm_y := vp.y - TOOLBAR_H - mm_h - 6.0

	# Background + border
	draw_rect(Rect2(mm_x - 2, mm_y - 14, mm_w + 4, 14), C_SURF)
	draw_string(font, Vector2(mm_x + 2, mm_y - 4), "MAPA", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_MUTED)
	draw_rect(Rect2(mm_x - 2, mm_y - 2, mm_w + 4, mm_h + 4), C_SURF)
	draw_texture_rect(_minimap_tex, Rect2(mm_x, mm_y, mm_w, mm_h), false)
	draw_rect(Rect2(mm_x, mm_y, mm_w, mm_h), C_BORDER, false, 1.0)

	# Camera viewport indicator
	if _minimap_cam_rect.size.x > 0:
		var scaled_rect := Rect2(
			mm_x + _minimap_cam_rect.position.x * MM_SCALE,
			mm_y + _minimap_cam_rect.position.y * MM_SCALE,
			_minimap_cam_rect.size.x * MM_SCALE,
			_minimap_cam_rect.size.y * MM_SCALE,
		)
		draw_rect(scaled_rect, Color(1.0, 1.0, 1.0, 0.12))
		draw_rect(scaled_rect, Color(0.784, 0.573, 0.165, 0.70), false, 1.0)   # golden cam rect

	# ── Vignette + war flash (drawn last, on top of everything) ─────────────────
	_draw_vignette(vp)
	if war_active:
		_draw_war_flash(vp)


# ── Visual overlay helpers ────────────────────────────────────────────────────

func _draw_vignette(vp: Vector2) -> void:
	# Approximate radial gradient vignette using 4 vertex-coloured triangles.
	# Centre is transparent; corners are dark (matches render.js rgba(0,0,0,0.45)).
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	var dark  := Color(0.0, 0.0, 0.0, 0.45)
	var clear := Color(0.0, 0.0, 0.0, 0.0)
	draw_colored_polygon(PackedVector2Array([Vector2(cx, cy), Vector2(0.0, 0.0), Vector2(vp.x, 0.0)]),    PackedColorArray([clear, dark, dark]))
	draw_colored_polygon(PackedVector2Array([Vector2(cx, cy), Vector2(vp.x, 0.0), Vector2(vp.x, vp.y)]), PackedColorArray([clear, dark, dark]))
	draw_colored_polygon(PackedVector2Array([Vector2(cx, cy), Vector2(vp.x, vp.y), Vector2(0.0, vp.y)]), PackedColorArray([clear, dark, dark]))
	draw_colored_polygon(PackedVector2Array([Vector2(cx, cy), Vector2(0.0, vp.y), Vector2(0.0, 0.0)]),    PackedColorArray([clear, dark, dark]))


func _draw_war_flash(vp: Vector2) -> void:
	# Subtle pulsing red screen tint when any war is active (matches render.js rgba(220,30,30,0.04))
	var pulse := 0.5 + 0.5 * sin(float(_hud_tick) * 0.15)
	draw_rect(Rect2(0.0, 0.0, vp.x, vp.y), Color(0.863, 0.118, 0.118, 0.04 * pulse))
