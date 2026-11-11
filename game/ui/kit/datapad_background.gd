class_name DatapadBackground
extends Control
## Orbital schematics adapted from Star Wars Skirmish's HoloBackground:
## slow rings, circuit traces, scan beam, cross markers and Aurebesh readouts.

var _time := 0.0
var _badge: ProfileBadge
var emblem_override := ""
var force_datapad := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Appearance.changed.connect(queue_redraw)
	resized.connect(queue_redraw)
	_badge = ProfileBadge.new()
	_badge.background_mode = true
	add_child(_badge)
	Cosmetics.changed.connect(_refresh_emblem)
	resized.connect(_refresh_emblem)
	_refresh_emblem()


func _refresh_emblem() -> void:
	_badge.visible = not force_datapad and (not emblem_override.is_empty() or Cosmetics.background() == "emblem")
	_badge.emblem_id = emblem_override
	var extent := minf(size.x * 0.8, size.y * 0.78)
	_badge.size = Vector2.ONE * extent
	_badge.position = (size - _badge.size) / 2.0


func _process(delta: float) -> void:
	if not Sabacc.perf():
		_time += delta
		queue_redraw()


func _line(a: Vector2, b: Vector2, color: Color) -> void:
	draw_line(a, b, Color(color, 0.035), 7.0, true)
	draw_line(a, b, Color(color, 0.22), 1.2, true)


func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var is_emblem := not force_datapad and (not emblem_override.is_empty() or Cosmetics.background() == "emblem")
	var identity := emblem_override if not emblem_override.is_empty() else Cosmetics.equipped("emblem")
	var primary := Cosmetics.emblem_color(identity, 0) if is_emblem else (Appearance.line_color(0) if force_datapad else Appearance.backdrop_color(0))
	var secondary := Cosmetics.emblem_color(identity, 1) if is_emblem else (Appearance.line_color(1) if force_datapad else Appearance.backdrop_color(1))
	var tertiary := Cosmetics.emblem_color(identity, 2) if is_emblem else (Appearance.line_color(2) if force_datapad else Appearance.backdrop_color(2))
	draw_rect(Rect2(Vector2.ZERO, size), primary.darkened(0.95) if force_datapad or not emblem_override.is_empty() else Appearance.preset()["base"])
	# A visible ambient wash accompanies the traces, especially for short AI turns.
	draw_rect(Rect2(Vector2.ZERO, size), Color(primary, 0.045))
	draw_circle(size * Vector2(0.68, 0.48), size.length() * 0.48, Color(secondary, 0.025))
	if is_emblem:
		_draw_emblem_field(identity, primary, secondary)
		return
	for x in range(0, ceili(size.x), 96):
		for y in range(0, ceili(size.y), 96):
			var p := Vector2(x, y)
			draw_line(p - Vector2(4, 0), p + Vector2(4, 0), Color(secondary, 0.12), 1.0)
			draw_line(p - Vector2(0, 4), p + Vector2(0, 4), Color(secondary, 0.12), 1.0)
	var anchor := size * Vector2(0.77, 0.86)
	var unit := minf(size.x, size.y * 0.75)
	for i in 5:
		var radius := unit * (0.12 + i * 0.18)
		var center := anchor + Vector2(-0.32, -1).normalized() * radius
		var col := Appearance.line_color(i) if force_datapad else Appearance.backdrop_color(i)
		draw_arc(center, radius, 0, TAU, 128, Color(col, 0.035), 7.0, true)
		draw_arc(center, radius, 0, TAU, 128, Color(col, 0.24), 1.1, true)
		var angle := _time * (0.07 + i * 0.013) + i
		draw_arc(center, radius, angle, angle + 0.4, 20, Color(col, 0.5), 2.0, true)
		draw_circle(center + Vector2.from_angle(angle) * radius, 2.5, Color(col, 0.8))
	for angle in [-150.0, -122.0, -96.0, -58.0]:
		_line(anchor, anchor + Vector2.from_angle(deg_to_rad(angle)) * size.length(), secondary)
	_line(Vector2(0, size.y * 0.58), anchor, primary)
	var center := size * Vector2(0.24, 0.29)
	var radius := unit * 0.28
	for i in 48:
		var angle := i * TAU / 48 + _time * 0.04
		var dir := Vector2.from_angle(angle)
		draw_line(center + dir * radius, center + dir * (radius + (10 if i % 4 == 0 else 4)), Color(tertiary, 0.22), 1.0, true)
	var beam_y := fposmod(_time * 24.0, size.y)
	draw_rect(Rect2(0, beam_y, size.x, 1.5), Color(primary, 0.12))
	if Sabacc.settings.get("show_aurebesh", true):
		draw_string(Sabacc.font_aurebesh, size * Vector2(0.08, 0.12), "SABACC // TACTICAL ARCHIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(primary, 0.22))
		draw_string(Sabacc.font_aurebesh, size * Vector2(0.55, 0.94), "ORBITAL LINK // 2187", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(secondary, 0.22))


func _path(points: PackedVector2Array, color: Color) -> void:
	draw_polyline(points, Color(color, 0.035), 6, true)
	draw_polyline(points, Color(color, 0.24), 1.1, true)


func _polygon(center: Vector2, radius: float, sides: int, angle: float, color: Color, stretch := Vector2.ONE) -> void:
	var points := PackedVector2Array()
	for i in sides + 1:
		points.append(center + Vector2.from_angle(angle + i * TAU / sides) * radius * stretch)
	_path(points, color)


func _draw_emblem_field(id: String, primary: Color, secondary: Color) -> void:
	var c := size / 2
	var r := minf(size.x, size.y) * 0.46
	var t := _time
	match id:
		"rebel_alliance":
			for i in 14:
				var points := PackedVector2Array()
				for j in 40:
					var x := (j / 39.0 - 0.5) * size.x * 1.3
					points.append(c + Vector2(x, x * x / (r * 2) - r + i * 19 + sin(t * 0.14 + i) * 6))
				_path(points, primary)
		"rebel_gold":
			for i in 36:
				var d := Vector2.from_angle(i * TAU / 36 + t * 0.018)
				_line(c + d * r * 0.58, c + d * r * (1.3 + (i % 3) * 0.14), primary)
		"rust_starbird":
			for i in 48:
				var p := Vector2(fposmod(i * 173.3, size.x), fposmod(i * 97.1 - t * (5 + i % 7), size.y))
				draw_circle(p, 1.5 + i % 3, Color(primary, 0.10 + 0.08 * sin(i + t)))
			for i in 4:
				draw_arc(c, r * (0.6 + i * 0.25), i + t * 0.025, i + t * 0.025 + 2.2, 60, Color(secondary, 0.18), 1, true)
		"phoenix":
			for i in 18:
				var points := PackedVector2Array()
				for j in 36:
					var y := j / 35.0 * size.y
					points.append(Vector2(size.x * i / 17.0 + sin(y / r * 2 - t * 0.2 + i * 0.3) * 42, y))
				_path(points, primary)
		"new_republic":
			for i in 8:
				_polygon(c, r * (0.45 + i * 0.14), 72, t * 0.02 * (1 if i % 2 else -1), primary, Vector2(1.7, 0.65))
				draw_circle(c + Vector2.from_angle(t * (0.035 + i * 0.005) + i) * r * (0.45 + i * 0.14) * Vector2(1.7, 0.65), 2.2, Color(secondary, 0.5))
		"galactic_empire":
			for i in 6:
				var a := i * TAU / 6 + t * 0.018
				_line(c + Vector2.from_angle(a) * r * 0.4, c + Vector2.from_angle(a) * r * 2, primary)
				for j in 4:
					draw_arc(c, r * (0.65 + j * 0.22), a + 0.08, a + 0.8, 30, Color(secondary, 0.22), 2, true)
		"imperial_grey":
			for i in 16:
				var y := size.y * i / 15.0
				_line(Vector2(0, y), Vector2(size.x, y), secondary)
			var x := fposmod(t * 35, size.x)
			draw_rect(Rect2(x - 35, 0, 70, size.y), Color(primary, 0.045))
			_line(Vector2(x, 0), Vector2(x, size.y), primary)
		"galactic_republic":
			for i in 7:
				_polygon(c, r * (0.4 + i * 0.15), 12, t * 0.018 + i * 0.03, primary)
			for i in 12:
				var d := Vector2.from_angle(i * TAU / 12 + t * 0.018)
				_line(c + d * r, c + d * r * 1.6, secondary)
		"old_republic":
			for i in 10:
				var rr := r * (0.4 + i * 0.12)
				draw_arc(c, rr, PI + t * 0.005, TAU + t * 0.005, 70, Color(primary, 0.23), 1.2, true)
				_line(c + Vector2(-rr, 0), Vector2(c.x - rr, size.y), secondary)
				_line(c + Vector2(rr, 0), Vector2(c.x + rr, size.y), secondary)
		"separatists":
			for x in 8:
				for y in 7:
					var p := Vector2(size.x * x / 7, size.y * y / 6 + (x % 2) * 35)
					_polygon(p, 40 + sin(t * 0.3 + x + y) * 3, 6, PI / 6, primary)
		"sabacc":
			for i in 12:
				var p := Vector2(fposmod(i * 193.0 + t * 8, size.x + 160) - 80, fposmod(i * 157.0, size.y))
				_path(PackedVector2Array([p + Vector2(-35, -68), p + Vector2(35, -68), p + Vector2(65, 0), p + Vector2(35, 68), p + Vector2(-35, 68), p + Vector2(-65, 0), p + Vector2(-35, -68)]), primary)
		"fett_crest":
			for i in 5:
				var p := Vector2(size.x * (0.15 + i * 0.17), size.y * (0.25 + 0.18 * sin(t * 0.08 + i * 1.7)))
				draw_arc(p, 40 + i * 9, t * 0.09, t * 0.09 + 5.3, 50, Color(primary, 0.23), 1.1, true)
				_line(p - Vector2(65, 0), p + Vector2(65, 0), secondary)
				_line(p - Vector2(0, 65), p + Vector2(0, 65), secondary)
		"deaths_head":
			for i in 18:
				var y := size.y * i / 17
				var reach := r * (0.3 + 0.55 * absf(sin(i * 0.4 + t * 0.04)))
				_path(PackedVector2Array([Vector2(c.x - reach, y + 12), Vector2(c.x - reach * 0.8, y), Vector2(c.x + reach * 0.8, y), Vector2(c.x + reach, y + 12)]), primary)
		"sith_empire":
			for i in 9:
				draw_arc(c, r * (0.6 + i * 0.1), t * 0.04 + i * 0.4, t * 0.04 + i * 0.4 + 4.5, 90, Color(primary, 0.22), 1.5, true)
			draw_circle(c, r * 0.58, Appearance.preset()["base"])
		"sith_eternal":
			for i in 10:
				_polygon(c, r * (0.4 + i * 0.15), 4, PI / 2 + sin(t * 0.06) * 0.08, primary, Vector2(0.65, 1.25))
		"twin_blades":
			for i in 12:
				var offset := (i - 5.5) * 35 + sin(t * 0.12) * 18
				_line(Vector2(0, c.y + offset - r), Vector2(size.x, c.y + offset + r), primary)
				_line(Vector2(0, c.y + offset + r), Vector2(size.x, c.y + offset - r), secondary)
		"crimson_block":
			for i in 10:
				var extent := Vector2(r * (0.4 + i * 0.16), r * (0.3 + i * 0.11)) * (1 + sin(t * 0.15 + i * 0.4) * 0.025)
				draw_rect(Rect2(c - extent, extent * 2), Color(primary, 0.23), false, 1.1)
		"red_horizon":
			var horizon := size.y * 0.43
			_line(Vector2(0, horizon), Vector2(size.x, horizon), primary)
			for i in 20:
				_line(Vector2(c.x, horizon), Vector2(size.x * (i - 4) / 11, size.y), secondary)
			for i in 10:
				var y := horizon + pow(fposmod(i * 0.1 + t * 0.015, 1), 2) * (size.y - horizon)
				_line(Vector2(0, y), Vector2(size.x, y), primary)
		"iron_crest":
			for i in 12:
				var y := fposmod(i * 95 + t * 9, size.y + 100) - 50
				_path(PackedVector2Array([Vector2(0, y), Vector2(c.x, y + r * 0.35), Vector2(size.x, y)]), primary)
		"red_slash":
			for i in 24:
				var x := fposmod(i * 110 + t * 15, size.x + size.y) - size.y
				_line(Vector2(x, 0), Vector2(x + size.y, size.y), primary)
		"medic_cross":
			for i in 6:
				var y := size.y * (i + 0.5) / 6
				var x := fposmod(t * 40 + i * 131, size.x)
				_path(PackedVector2Array([Vector2(0, y), Vector2(x - 42, y), Vector2(x - 22, y - 15), Vector2(x - 10, y + 32), Vector2(x + 8, y - 52), Vector2(x + 24, y), Vector2(size.x, y)]), primary)
		"hex_shield":
			for i in 9:
				_polygon(c, r * (0.35 + i * 0.14), 6, -PI / 2 + sin(t * 0.08) * 0.025, primary)
		"red_cipher":
			for i in 40:
				var p := Vector2((i % 8) * size.x / 7, (i / 8) * size.y / 4)
				if sin(i * 2.1 + t * 0.25) > -0.25:
					_path(PackedVector2Array([p, p + Vector2(45, 0), p + Vector2(45, 30), p + Vector2(80, 30)]), primary)
		"ember_stripes":
			for i in 20:
				var x := fposmod(i * 97 + t * (12 + i % 4), size.x + 220) - 110
				var y := size.y * i / 19
				_line(Vector2(x, y), Vector2(x + 160, y - 30), primary)
		"twin_spires":
			for side in [-1, 1]:
				for i in 8:
					var x: float = c.x + side * (r * 0.3 + i * 18)
					_path(PackedVector2Array([Vector2(x, size.y), Vector2(x, r * 0.3 + i * 20), Vector2(c.x + side * 15, 0)]), primary)
			for i in 8:
				var y := fposmod(i * 120 + t * 8, size.y)
				_line(Vector2(c.x - r * 0.3, y), Vector2(c.x + r * 0.3, y), secondary)
	if Sabacc.settings.get("show_aurebesh", true):
		draw_string(Sabacc.font_aurebesh, Vector2(30, size.y - 35), id.to_upper().replace("_", " ") + " // HOLO SIGNATURE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(primary, 0.22))
