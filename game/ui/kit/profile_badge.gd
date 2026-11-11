class_name ProfileBadge
extends Control
## A profile emblem with its own miniature datapad and orbiting traces.

var emblem_id := ""
var background_mode := false
var draw_disc := true
var _time := 0.0
var _lean := Vector2.ZERO
var _touch := Vector2.ZERO
var _touching := false
var _touch_device := false
var _noise := FastNoiseLite.new()
var _random := RandomNumberGenerator.new()
var _next_glitch := 2.0
var _glitch_left := 0.0
var _flicker := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Cosmetics.changed.connect(queue_redraw)
	Appearance.changed.connect(queue_redraw)
	_random.randomize()
	_noise.seed = absi(hash(emblem_id if not emblem_id.is_empty() else Cosmetics.equipped("emblem")))
	_noise.frequency = 0.8
	_next_glitch = _random.randf_range(1.0, 5.0)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch_device = true
		_touching = event.pressed
		_touch = event.position
	elif event is InputEventScreenDrag:
		_touch = event.position


func _process(delta: float) -> void:
	if Sabacc.perf():
		_lean = Vector2.ZERO
		_flicker = 1.0
		return
	_time += delta
	var pointer := get_global_transform_with_canvas().affine_inverse() * _touch if _touching else get_local_mouse_position()
	var target := (pointer - size / 2) / maxf(1, minf(size.x, size.y) / 2)
	if _touch_device and not _touching:
		target = Vector2.ZERO
	if not background_mode and target.length() > 2:
		target = Vector2.ZERO
	_lean = _lean.lerp(target.limit_length(1.0), 1 - exp(-delta * 5))
	_next_glitch -= delta
	_glitch_left = maxf(0, _glitch_left - delta)
	if _next_glitch <= 0:
		_glitch_left = _random.randf_range(0.035, 0.14)
		_next_glitch = _random.randf_range(1.2, 6.0)
	_flicker = 0.93 + _noise.get_noise_1d(_time * 9) * 0.07
	if _glitch_left > 0:
		_flicker *= 0.55 + _random.randf() * 0.3
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) * 0.45
	draw_set_transform(center + _lean * radius * 0.035, _lean.x * 0.035, Vector2(1 - absf(_lean.y) * 0.035, 1 - absf(_lean.x) * 0.035))
	center = Vector2.ZERO
	var alpha := 0.22 if background_mode else 1.0
	var identity := emblem_id if not emblem_id.is_empty() else Cosmetics.equipped("emblem")
	var primary := Cosmetics.emblem_color(identity)
	if not background_mode and draw_disc:
		draw_circle(center, radius, primary.darkened(0.94))
	for i in 3:
		var color := Cosmetics.emblem_color(identity, i)
		var angle := _time * (0.08 + i * 0.025) + i * 1.8
		draw_arc(center, radius * (0.8 + i * 0.08), angle, angle + PI * 1.4, 80, Color(color, alpha * 0.65), 1.4, true)
		var point := center + Vector2.from_angle(angle) * radius * (0.8 + i * 0.08)
		draw_circle(point, 2.0, Color(color, alpha))
	var texture := Cosmetics.texture("emblem", emblem_id if not emblem_id.is_empty() else Cosmetics.equipped("emblem"))
	if texture:
		var extent := Vector2.ONE * radius * 1.45
		draw_texture_rect(texture, Rect2(center - extent / 2.0, extent), false, Color(1, 1, 1, alpha * _flicker))
		# Keep transmission detail outside the glyph. Opaque, full-width dark
		# scan bars looked like rendering corruption and obscured the emblem.
		if background_mode:
			for i in 8:
				var y := center.y + (i - 3.5) * radius * 0.18
				var edge := radius * (0.78 + sin(_time * 0.16 + i) * 0.025)
				for side in [-1, 1]:
					draw_line(Vector2(center.x + side * edge, y), Vector2(center.x + side * (edge + radius * 0.07), y), Color(primary, alpha * 0.4), 1.0, true)
			var y := center.y - radius + fposmod(_time * 18, radius * 2)
			draw_line(Vector2(center.x - radius * 0.7, y), Vector2(center.x + radius * 0.7, y), Color(primary, alpha * 0.18), 1.0, true)
