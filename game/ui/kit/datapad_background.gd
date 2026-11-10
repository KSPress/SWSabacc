class_name DatapadBackground
extends Control
## Orbital schematics adapted from Star Wars Skirmish's HoloBackground:
## slow rings, circuit traces, scan beam, cross markers and Aurebesh readouts.

var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Appearance.changed.connect(queue_redraw)
	resized.connect(queue_redraw)


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
	draw_rect(Rect2(Vector2.ZERO, size), Appearance.preset()["base"])
	var primary := Appearance.color_at(0)
	var secondary := Appearance.color_at(1)
	var tertiary := Appearance.color_at(2)
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
		var col := Appearance.color_at(i)
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
