class_name Starfield
extends Control
## Cheap animated background: parallax star layers, optional hyperspace streaks
## and an optional backdrop image with slow Ken Burns drift. Static in perf mode.

var backdrop: Texture2D
var backdrop_alpha := 0.55
var hyperspace := 0.0     # 0..1 streak amount (animate for transitions)
var drift := Vector2(-6, 2)
var _stars: Array = []
var _t := 0.0
var _datapad: DatapadBackground


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_datapad = DatapadBackground.new()
	UIKit.fill_rect(_datapad)
	add_child(_datapad)
	Appearance.changed.connect(_retheme)
	_retheme()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 160:
		_stars.append({"p": Vector2(rng.randf(), rng.randf()), "z": rng.randf_range(0.2, 1.0), "tw": rng.randf() * TAU})
	resized.connect(queue_redraw)


func _process(dt: float) -> void:
	if Appearance.preset()["kind"] == "planet":
		return
	if Sabacc.perf() and hyperspace <= 0.0:
		return
	_t += dt
	queue_redraw()


func _draw() -> void:
	var spec := Appearance.preset()
	draw_rect(Rect2(Vector2.ZERO, size), spec["base"])
	if spec["kind"] == "datapad":
		return
	var photo: Texture2D = Cosmetics.background_texture(spec.get("art", "")) if spec["kind"] == "planet" else null
	if photo:
		var ts := photo.get_size()
		var sc := maxf(size.x / ts.x, size.y / ts.y) * (1.08 + 0.03 * sin(_t * 0.07))
		var ds := ts * sc
		var off := (size - ds) / 2.0 + Vector2(sin(_t * 0.05), cos(_t * 0.04)) * 12.0
		draw_texture_rect(photo, Rect2(off, ds), false, Color(1, 1, 1, 0.38))
		draw_rect(Rect2(Vector2.ZERO, size), Color(Sabacc.C_BG, 0.25))
	var center := size / 2.0
	if Sabacc.settings.get("theme") == "space_nebula":
		for i in 24:
			var pos := size * Vector2(0.55 + 0.25 * sin(i * 0.4 + _t * 0.015), 0.3 + 0.25 * cos(i * 0.3))
			draw_circle(pos, size.length() * 0.14, Color(Appearance.color_at(i), 0.008))
	for s in _stars:
		var p: Vector2 = s["p"]
		var z: float = s["z"]
		var pos := Vector2(fposmod(p.x * size.x + drift.x * _t * z, size.x), fposmod(p.y * size.y + drift.y * _t * z, size.y))
		var tw := 0.6 + 0.4 * sin(_t * 2.0 + s["tw"])
		var col := Color(0.8, 0.9, 1.0, z * tw * (0.5 if backdrop else 0.9))
		if hyperspace > 0.0 or Sabacc.settings.get("theme") == "space_hyperspace":
			var dir := (pos - center).normalized()
			draw_line(pos, pos + dir * maxf(0.3, hyperspace) * 120.0 * z, col, 1.5 * z)
		else:
			draw_circle(pos, 1.6 * z, col)


func _retheme() -> void:
	_datapad.visible = Appearance.preset()["kind"] == "datapad"
	queue_redraw()
