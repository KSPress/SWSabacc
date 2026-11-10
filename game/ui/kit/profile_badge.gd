class_name ProfileBadge
extends Control
## A profile emblem with its own miniature datapad and orbiting traces.

var emblem_id := ""
var background_mode := false
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Cosmetics.changed.connect(queue_redraw)
	Appearance.changed.connect(queue_redraw)


func _process(delta: float) -> void:
	if not Sabacc.perf():
		_time += delta
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) * 0.45
	var alpha := 0.22 if background_mode else 1.0
	if not background_mode:
		draw_circle(center, radius, Color("07111b"))
	for i in 3:
		var color := Appearance.line_color(i)
		var angle := _time * (0.08 + i * 0.025) + i * 1.8
		draw_arc(center, radius * (0.8 + i * 0.08), angle, angle + PI * 1.4, 80, Color(color, alpha * 0.65), 1.4, true)
		var point := center + Vector2.from_angle(angle) * radius * (0.8 + i * 0.08)
		draw_circle(point, 2.0, Color(color, alpha))
	var texture := Cosmetics.texture("emblem", emblem_id if not emblem_id.is_empty() else Cosmetics.equipped("emblem"))
	if texture:
		var extent := Vector2.ONE * radius * 1.45
		var flicker := 1.0 if Sabacc.perf() else 0.88 + 0.12 * sin(_time * 7.7)
		draw_texture_rect(texture, Rect2(center - extent / 2.0, extent), false, Color(1, 1, 1, alpha * flicker))
		# Scan bars and small digital slices make the oversized background glyph
		# read as a transmission rather than an opaque image behind the cards.
		if background_mode:
			for i in 16:
				var y := center.y - radius * 0.7 + i * radius * 0.09
				draw_line(Vector2(center.x - radius * 0.7, y), Vector2(center.x + radius * 0.7, y), Color("06101b"), 2.5)
			var y := center.y - radius + fposmod(_time * 18, radius * 2)
			draw_line(Vector2(center.x - radius * 0.75, y), Vector2(center.x + radius * 0.75, y), Color(Appearance.line_color(), 0.14), 1.3)
