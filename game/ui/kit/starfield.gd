class_name Starfield
extends Control
## Cheap animated background: parallax star layers, optional hyperspace streaks
## and an optional backdrop image with slow Ken Burns drift. Static in perf mode.

var backdrop: Texture2D
var backdrop_alpha := 0.55
var preset_override: Dictionary = {}
var _location := ""
var _spec: Dictionary = {}
var _photo: Texture2D
var hyperspace := 0.0     # 0..1 streak amount (animate for transitions)
var drift := Vector2(-6, 2)
var _stars: Array = []
var _t := 0.0
var _datapad: DatapadBackground
var _film: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_datapad = DatapadBackground.new()
	UIKit.fill_rect(_datapad)
	add_child(_datapad)
	_film = SagaScenes.film_layer()
	add_child(_film)
	UIKit.fill_rect(_film)
	Appearance.changed.connect(_retheme)
	_retheme()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 160:
		_stars.append({"p": Vector2(rng.randf(), rng.randf()), "z": rng.randf_range(0.2, 1.0), "tw": rng.randf() * TAU})
	resized.connect(queue_redraw)


func _process(dt: float) -> void:
	if _spec["kind"] != "space":
		return
	if Sabacc.perf() and hyperspace <= 0.0:
		return
	_t += dt
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _spec["base"])
	if _film.visible:
		return
	if _photo:
		var source_size := _photo.get_size()
		var covered := source_size * maxf(size.x / source_size.x, size.y / source_size.y)
		draw_texture_rect(_photo, Rect2((size - covered) * 0.5, covered), false)
		draw_rect(Rect2(Vector2.ZERO, size), Color(_spec["base"], 0.37))
		return
	if _spec["kind"] == "datapad":
		return
	if backdrop and _location.is_empty():
		var art_size := backdrop.get_size()
		var covered := art_size * maxf(size.x / art_size.x, size.y / art_size.y)
		draw_texture_rect(backdrop, Rect2((size - covered) * 0.5, covered), false, Color(1, 1, 1, backdrop_alpha * 0.48))
	var center := size / 2.0
	if _spec == Appearance.PRESETS["space_nebula"]:
		for i in 24:
			var pos := size * Vector2(0.55 + 0.25 * sin(i * 0.4 + _t * 0.015), 0.3 + 0.25 * cos(i * 0.3))
			draw_circle(pos, size.length() * 0.14, Color(Appearance.color_at(i), 0.008))
	for s in _stars:
		var p: Vector2 = s["p"]
		var z: float = s["z"]
		var pos := Vector2(fposmod(p.x * size.x + drift.x * _t * z, size.x), fposmod(p.y * size.y + drift.y * _t * z, size.y))
		var tw := 0.6 + 0.4 * sin(_t * 2.0 + s["tw"])
		var col := Color(0.8, 0.9, 1.0, z * tw * (0.5 if backdrop else 0.9))
		if hyperspace > 0.0 or _spec == Appearance.PRESETS["space_hyperspace"]:
			var dir := (pos - center).normalized()
			draw_line(pos, pos + dir * maxf(0.3, hyperspace) * 120.0 * z, col, 1.5 * z)
		else:
			draw_circle(pos, 1.6 * z, col)


func _retheme() -> void:
	_spec = Appearance.preset(_location) if preset_override.is_empty() else preset_override
	_datapad.visible = _spec["kind"] == "datapad"
	_datapad.preset_override = preset_override
	_datapad.force_datapad = not preset_override.is_empty()
	_datapad._refresh_emblem()
	_datapad.queue_redraw()
	_photo = Cosmetics.background_texture(_spec.get("art", "")) if _spec["kind"] == "planet" else null
	SagaScenes.set_film_photo(_film, _photo, _spec.get("film", false))
	queue_redraw()


func set_location(location: String) -> void:
	_location = location
	_retheme()
