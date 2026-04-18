extends Control
class_name IconDrawer

## Draws a vector icon inside its bounds.
## Set icon_type and icon_color before adding to the scene tree.

var icon_type:  String = ""
var icon_color: Color  = Color.WHITE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var w  := size.x
	var h  := size.y
	var cx := w * 0.5
	var cy := h * 0.5
	var s  := minf(w, h) * 0.40
	var ic := icon_color

	match icon_type:

		# ── Tab buttons ───────────────────────────────────────────────────────

		"tab_terrain":
			# Two overlapping mountain silhouettes + ground line
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*1.05, cy+s*0.72),
				Vector2(cx-s*0.10, cy-s*0.82),
				Vector2(cx+s*0.72, cy+s*0.72),
			]), ic.darkened(0.22))
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*0.22, cy+s*0.72),
				Vector2(cx+s*0.54, cy-s*0.44),
				Vector2(cx+s*1.05, cy+s*0.72),
			]), ic)
			draw_line(
				Vector2(cx-s*1.10, cy+s*0.72),
				Vector2(cx+s*1.10, cy+s*0.72),
				ic.lightened(0.35), 1.5)

		"tab_entities":
			# Standing person silhouette
			draw_circle(Vector2(cx, cy-s*0.62), s*0.32, ic)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*0.34, cy-s*0.24),
				Vector2(cx+s*0.34, cy-s*0.24),
				Vector2(cx+s*0.26, cy+s*0.72),
				Vector2(cx-s*0.26, cy+s*0.72),
			]), ic)

		"tab_world":
			# Globe: filled ocean disk + grid lines
			draw_circle(Vector2(cx, cy), s*0.82, ic.darkened(0.54))
			draw_circle(Vector2(cx, cy), s*0.82, ic, false, 2.0)
			draw_line(Vector2(cx-s*0.82, cy),         Vector2(cx+s*0.82, cy),         ic.lightened(0.16), 1.2)
			draw_line(Vector2(cx-s*0.70, cy-s*0.44),  Vector2(cx+s*0.70, cy-s*0.44),  ic.darkened(0.08),  0.8)
			draw_line(Vector2(cx-s*0.70, cy+s*0.44),  Vector2(cx+s*0.70, cy+s*0.44),  ic.darkened(0.08),  0.8)
			draw_line(Vector2(cx,         cy-s*0.83), Vector2(cx,         cy+s*0.83), ic.lightened(0.10), 0.8)

		"tab_powers":
			_draw_bolt(cx, cy, s, ic)

		# ── Speed buttons ─────────────────────────────────────────────────────

		"pause":
			draw_rect(Rect2(cx-s*0.54, cy-s*0.70, s*0.36, s*1.40), ic)
			draw_rect(Rect2(cx+s*0.18, cy-s*0.70, s*0.36, s*1.40), ic)

		"speed_1":
			_draw_arrow(cx, cy, s, ic)

		"speed_2":
			_draw_arrow(cx-s*0.40, cy, s, ic)
			_draw_arrow(cx+s*0.40, cy, s, ic)

		"speed_3":
			_draw_arrow(cx-s*0.70, cy, s, ic)
			_draw_arrow(cx,        cy, s, ic)
			_draw_arrow(cx+s*0.70, cy, s, ic)

		"speed_4":
			for i in 4:
				_draw_arrow(cx + (float(i)-1.5)*s*0.54, cy, s*0.88, ic)

		# ── Biome buttons ─────────────────────────────────────────────────────

		"biome_water":
			for i in 2:
				var wy := cy + float(i)*s*0.50 - s*0.30
				draw_arc(Vector2(cx-s*0.28, wy), s*0.44, PI, TAU, 10, ic,                 2.0)
				draw_arc(Vector2(cx+s*0.50, wy), s*0.38, PI, TAU,  8, ic.lightened(0.22), 1.5)

		"biome_sand":
			# Sun with rays
			draw_circle(Vector2(cx, cy-s*0.44), s*0.28, ic)
			for i in 6:
				var ra := deg_to_rad(float(i)*60.0)
				draw_line(
					Vector2(cx+cos(ra)*s*0.40, cy-s*0.44+sin(ra)*s*0.40),
					Vector2(cx+cos(ra)*s*0.62, cy-s*0.44+sin(ra)*s*0.62),
					ic, 1.5)
			# Wavy ground
			draw_arc(Vector2(cx-s*0.40, cy+s*0.46), s*0.28, 0.0, PI, 8, ic.lightened(0.20), 2.0)
			draw_arc(Vector2(cx+s*0.20, cy+s*0.46), s*0.28, 0.0, PI, 8, ic.lightened(0.14), 2.0)

		"biome_grass":
			# Three V-shaped grass blades
			for i in 3:
				var bx := cx + (float(i)-1.0)*s*0.58
				draw_line(Vector2(bx, cy+s*0.56), Vector2(bx-s*0.22, cy-s*0.60), ic, 2.0)
				draw_line(Vector2(bx, cy+s*0.56), Vector2(bx+s*0.22, cy-s*0.60), ic, 2.0)

		"biome_forest":
			# Tree: trunk + layered canopy circles
			draw_rect(Rect2(cx-s*0.16, cy+s*0.14, s*0.32, s*0.60), ic.darkened(0.40))
			draw_circle(Vector2(cx, cy+s*0.10), s*0.48, ic)
			draw_circle(Vector2(cx, cy-s*0.12), s*0.40, ic.lightened(0.06))
			draw_circle(Vector2(cx, cy-s*0.32), s*0.28, ic.lightened(0.18))

		"biome_mountain":
			# Two-tone triangle + snow cap
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx,        cy-s*0.80),
				Vector2(cx-s*0.72, cy+s*0.62),
				Vector2(cx,        cy+s*0.62),
			]), ic.lightened(0.18))
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx,        cy-s*0.80),
				Vector2(cx,        cy+s*0.62),
				Vector2(cx+s*0.72, cy+s*0.62),
			]), ic.darkened(0.28))
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx,        cy-s*0.80),
				Vector2(cx-s*0.22, cy-s*0.40),
				Vector2(cx+s*0.22, cy-s*0.40),
			]), Color(0.96, 0.96, 0.98, 0.96))
			draw_line(
				Vector2(cx-s*0.76, cy+s*0.62),
				Vector2(cx+s*0.76, cy+s*0.62),
				ic.darkened(0.30), 1.5)

		# ── Power buttons ─────────────────────────────────────────────────────

		"power_meteor":
			# Trail (fading circles)
			for i in 4:
				var tt  := float(i) / 3.0
				var tca := Color(ic.r, ic.g, ic.b, 0.22+tt*0.45)
				draw_circle(
					Vector2(cx-s*0.55+tt*s*0.40, cy-s*0.55+tt*s*0.40),
					s*(0.05+tt*0.10), tca)
			# Rock body
			draw_circle(Vector2(cx+s*0.22, cy+s*0.22), s*0.36, ic)
			draw_circle(Vector2(cx+s*0.22, cy+s*0.22), s*0.36, ic.darkened(0.30), false, 1.5)
			# Highlight
			draw_circle(Vector2(cx+s*0.08, cy+s*0.06), s*0.14, ic.lightened(0.40))

		"power_lightning":
			_draw_bolt(cx, cy, s, ic)

		"power_fire":
			# Outer flame body
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*0.44, cy+s*0.72),
				Vector2(cx+s*0.44, cy+s*0.72),
				Vector2(cx+s*0.22, cy+s*0.04),
				Vector2(cx+s*0.50, cy+s*0.24),
				Vector2(cx+s*0.04, cy-s*0.78),
				Vector2(cx-s*0.50, cy+s*0.24),
				Vector2(cx-s*0.22, cy+s*0.04),
			]), ic)
			# Inner hot core
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*0.22, cy+s*0.72),
				Vector2(cx+s*0.22, cy+s*0.72),
				Vector2(cx,        cy-s*0.24),
			]), Color(1.0, 0.96, 0.55, 0.90))

		"power_plague":
			# Skull: round head + eye sockets + nose + jaw + teeth
			draw_circle(Vector2(cx, cy-s*0.12), s*0.58, ic)
			draw_circle(Vector2(cx, cy-s*0.12), s*0.58, ic.darkened(0.25), false, 1.5)
			# Eye sockets
			draw_circle(Vector2(cx-s*0.22, cy-s*0.18), s*0.17, Color(0.06, 0.05, 0.05, 0.92))
			draw_circle(Vector2(cx+s*0.22, cy-s*0.18), s*0.17, Color(0.06, 0.05, 0.05, 0.92))
			# Nose triangle
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*0.09, cy+s*0.06),
				Vector2(cx+s*0.09, cy+s*0.06),
				Vector2(cx,        cy+s*0.22),
			]), Color(0.06, 0.05, 0.05, 0.85))
			# Jaw block
			draw_rect(Rect2(cx-s*0.38, cy+s*0.30, s*0.76, s*0.36), ic)
			draw_rect(Rect2(cx-s*0.38, cy+s*0.30, s*0.76, s*0.36), ic.darkened(0.30), false, 1.0)
			# Teeth gaps
			for i in 3:
				draw_rect(
					Rect2(cx-s*0.30+float(i)*s*0.28, cy+s*0.32, s*0.16, s*0.30),
					Color(0.06, 0.05, 0.05, 0.88))

		"power_rain":
			# Cloud (overlapping circles + fill rect)
			draw_circle(Vector2(cx-s*0.18, cy-s*0.26), s*0.34, ic)
			draw_circle(Vector2(cx+s*0.22, cy-s*0.32), s*0.28, ic)
			draw_circle(Vector2(cx-s*0.44, cy-s*0.16), s*0.24, ic)
			draw_rect(Rect2(cx-s*0.68, cy-s*0.26, s*0.98, s*0.34), ic)
			# Rain drops
			for i in 4:
				var dx := cx - s*0.46 + float(i)*s*0.30
				draw_line(Vector2(dx, cy+s*0.22), Vector2(dx-s*0.08, cy+s*0.64), ic.lightened(0.26), 1.5)

		"power_blessing":
			# Star burst: filled circle + 8 main rays + 8 thin diagonal rays
			draw_circle(Vector2(cx, cy), s*0.34, ic)
			for i in 8:
				var ra := deg_to_rad(float(i)*45.0)
				draw_line(
					Vector2(cx+cos(ra)*s*0.44, cy+sin(ra)*s*0.44),
					Vector2(cx+cos(ra)*s*0.82, cy+sin(ra)*s*0.82),
					ic, 2.0)
			for i in 8:
				var ra := deg_to_rad(float(i)*45.0 + 22.5)
				draw_line(
					Vector2(cx+cos(ra)*s*0.38, cy+sin(ra)*s*0.38),
					Vector2(cx+cos(ra)*s*0.60, cy+sin(ra)*s*0.60),
					ic.lightened(0.20), 1.0)

		# ── Map type buttons ──────────────────────────────────────────────────

		"map_random":
			# Dice with 3 dots
			var half := s*0.68
			draw_rect(Rect2(cx-half, cy-half, half*2.0, half*2.0), ic.darkened(0.38))
			draw_rect(Rect2(cx-half, cy-half, half*2.0, half*2.0), ic, false, 2.0)
			draw_circle(Vector2(cx-half*0.44, cy-half*0.44), s*0.13, ic)
			draw_circle(Vector2(cx,           cy),           s*0.13, ic)
			draw_circle(Vector2(cx+half*0.44, cy+half*0.44), s*0.13, ic)

		"map_earthlike":
			# Globe with continent blobs
			draw_circle(Vector2(cx, cy), s*0.78, ic.darkened(0.52))
			draw_circle(Vector2(cx, cy), s*0.78, ic, false, 1.5)
			draw_circle(Vector2(cx-s*0.20, cy-s*0.18), s*0.32, ic.lightened(0.20))
			draw_circle(Vector2(cx+s*0.32, cy+s*0.22), s*0.24, ic.lightened(0.12))
			draw_circle(Vector2(cx-s*0.30, cy+s*0.32), s*0.20, ic.lightened(0.08))

		"map_continent":
			# Single large island in ocean
			draw_circle(Vector2(cx, cy), s*0.78, ic.darkened(0.52))
			draw_circle(Vector2(cx, cy), s*0.78, ic, false, 1.5)
			draw_circle(Vector2(cx, cy-s*0.05), s*0.50, ic.lightened(0.18))
			draw_circle(Vector2(cx, cy-s*0.05), s*0.38, ic.lightened(0.06))

		# ── Regen button ──────────────────────────────────────────────────────

		"regen":
			# Circular refresh arrow
			draw_arc(Vector2(cx, cy), s*0.66, deg_to_rad(40.0), deg_to_rad(340.0), 22, ic, 2.5)
			# Arrowhead at end of arc (at ~340°)
			var ea := deg_to_rad(340.0)
			var ex := cx + cos(ea)*s*0.66
			var ey := cy + sin(ea)*s*0.66
			draw_colored_polygon(PackedVector2Array([
				Vector2(ex,          ey),
				Vector2(ex-s*0.26,   ey-s*0.10),
				Vector2(ex-s*0.10,   ey+s*0.26),
			]), ic)

		# ── Species buttons ───────────────────────────────────────────────────

		"species_humanos":
			# Classic person silhouette
			draw_circle(Vector2(cx, cy-s*0.56), s*0.30, ic)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*0.34, cy-s*0.20),
				Vector2(cx+s*0.34, cy-s*0.20),
				Vector2(cx+s*0.26, cy+s*0.70),
				Vector2(cx-s*0.26, cy+s*0.70),
			]), ic)

		"species_elfos":
			# Slim figure + pointed ears
			draw_circle(Vector2(cx, cy-s*0.58), s*0.28, ic)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*0.28, cy-s*0.66), Vector2(cx-s*0.28, cy-s*0.44), Vector2(cx-s*0.60, cy-s*0.78)
			]), ic)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx+s*0.28, cy-s*0.66), Vector2(cx+s*0.28, cy-s*0.44), Vector2(cx+s*0.60, cy-s*0.78)
			]), ic)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*0.22, cy-s*0.24),
				Vector2(cx+s*0.22, cy-s*0.24),
				Vector2(cx+s*0.16, cy+s*0.70),
				Vector2(cx-s*0.16, cy+s*0.70),
			]), ic)

		"species_enanos":
			# Wide & short: iron helmet + big beard
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*0.44, cy-s*0.34),
				Vector2(cx+s*0.44, cy-s*0.34),
				Vector2(cx+s*0.34, cy-s*0.80),
				Vector2(cx-s*0.34, cy-s*0.80),
			]), ic.darkened(0.32))
			draw_rect(Rect2(cx-s*0.52, cy-s*0.38, s*1.04, s*0.12), ic.darkened(0.46))
			# Beard (light)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*0.46, cy-s*0.24),
				Vector2(cx+s*0.46, cy-s*0.24),
				Vector2(cx+s*0.40, cy+s*0.72),
				Vector2(cx-s*0.40, cy+s*0.72),
			]), ic.lightened(0.26))
			draw_line(Vector2(cx, cy+s*0.10), Vector2(cx, cy+s*0.72), ic.darkened(0.18), 1.5)

		"species_orcos":
			# Big head + ivory tusks + wide body
			draw_circle(Vector2(cx, cy-s*0.36), s*0.50, ic)
			var ivory_c := Color(0.94, 0.90, 0.76)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*0.12, cy-s*0.04), Vector2(cx-s*0.28, cy-s*0.04), Vector2(cx-s*0.24, cy+s*0.28)
			]), ivory_c)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx+s*0.12, cy-s*0.04), Vector2(cx+s*0.28, cy-s*0.04), Vector2(cx+s*0.24, cy+s*0.28)
			]), ivory_c)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx-s*0.50, cy+s*0.18),
				Vector2(cx+s*0.50, cy+s*0.18),
				Vector2(cx+s*0.44, cy+s*0.72),
				Vector2(cx-s*0.44, cy+s*0.72),
			]), ic)


# ── Private helpers ───────────────────────────────────────────────────────────

func _draw_arrow(cx: float, cy: float, s: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - s*0.32, cy - s*0.54),
		Vector2(cx - s*0.32, cy + s*0.54),
		Vector2(cx + s*0.44, cy),
	]), col)


func _draw_bolt(cx: float, cy: float, s: float, col: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(cx + s*0.26, cy - s*0.88),
		Vector2(cx - s*0.22, cy - s*0.04),
		Vector2(cx + s*0.10, cy - s*0.04),
		Vector2(cx - s*0.26, cy + s*0.88),
	])
	# Outer glow
	draw_polyline(pts, Color(col.r, col.g, col.b, 0.32), s*0.44, false)
	# Solid bolt
	draw_polyline(pts, col, s*0.28, false)
	# Bright core
	draw_polyline(pts, Color(1.0, 1.0, 0.90, 0.62), s*0.10, false)
