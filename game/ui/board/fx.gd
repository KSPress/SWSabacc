class_name Fx
extends RefCounted

## Controls that react to light from bolts and impacts (UnitToken, base and
## leader tiles). Each implements apply_light(color: Color, amount: float, from: Vector2).
static var light_targets: Array = []


static func light_at(pos: Vector2, col: Color, radius: float, strength: float) -> void:
	for t in light_targets:
		if not is_instance_valid(t) or not t.is_visible_in_tree():
			continue
		var r: Rect2 = t.get_global_rect()
		var d := r.get_center().distance_to(pos) - maxf(r.size.x, r.size.y) * 0.35
		var k := clampf(1.0 - d / radius, 0.0, 1.0)
		if k > 0.0:
			t.apply_light(col, k * k * strength, pos)
## GPU-cheap combat effects (spec 8.4): lightsaber swipes coloured per character,
## blaster bolts, impact rings/sparks, shield shatter, floating numbers, banners.
## All effects are self-freeing nodes added to an fx layer Control.


static func float_text(layer: Control, at: Vector2, text: String, col: Color, size := 40) -> void:
	var l := UIKit.label(text, size, col, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", Sabacc.font_title)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.size = Vector2(160, 60)
	l.pivot_offset = l.size / 2.0
	layer.add_child(l)
	l.global_position = at - l.size / 2.0
	l.scale = Vector2(0.4, 0.4)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.25, 1.25), Sabacc.anim(0.14)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, Sabacc.anim(0.1))
	tw.parallel().tween_property(l, "position:y", l.position.y - 70, Sabacc.anim(0.9)).set_delay(Sabacc.anim(0.1))
	tw.tween_property(l, "modulate:a", 0.0, Sabacc.anim(0.3))
	tw.tween_callback(l.queue_free)


static func banner(layer: Control, text: String, col: Color, sub := "") -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := layer.get_viewport_rect().size
	box.size = Vector2(vs.x, 140)
	box.position = Vector2(0, vs.y * 0.42 - 70)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size = box.size
	bar.position = box.position
	layer.add_child(bar)
	var l := UIKit.title(text, 56, col)
	box.add_child(l)
	if sub != "":
		box.add_child(UIKit.aurebesh(sub, 22))
	layer.add_child(box)
	box.modulate.a = 0.0
	bar.modulate.a = 0.0
	box.position.x = -vs.x * 0.3
	var tw := box.create_tween().set_parallel(true)
	tw.tween_property(box, "position:x", 0.0, Sabacc.anim(0.25)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 1.0, Sabacc.anim(0.2))
	tw.tween_property(bar, "modulate:a", 1.0, Sabacc.anim(0.2))
	tw.chain().tween_interval(Sabacc.anim(0.6))
	tw.chain().tween_property(box, "position:x", vs.x * 0.3, Sabacc.anim(0.25)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(box, "modulate:a", 0.0, Sabacc.anim(0.25))
	tw.parallel().tween_property(bar, "modulate:a", 0.0, Sabacc.anim(0.25))
	tw.chain().tween_callback(func():
		box.queue_free()
		bar.queue_free())


static func impact(layer: Control, at: Vector2, col: Color, big := false) -> void:
	var n := FxImpact.new()
	n.color = col
	n.big = big
	layer.add_child(n)
	n.global_position = at


static func shatter(layer: Control, at: Vector2) -> void:
	var s := FxImpact.new()
	s.color = Color(0.5, 0.9, 1.0)
	s.shards = true
	layer.add_child(s)
	s.global_position = at


## Arrow used while dragging an attacker toward a target.
class TargetArrow extends Node2D:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var color := Sabacc.C_EMPIRE
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var d := to - from
		var len := d.length()
		if len < 4:
			return
		var dir := d / len
		var n := Vector2(-dir.y, dir.x)
		var mid := from + d * 0.5 + n * minf(len * 0.18, 80.0)
		var pts := PackedVector2Array()
		for i in 21:
			var t := i / 20.0
			pts.append(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
		draw_polyline(pts, Color(color, 0.35), 14.0, true)
		draw_polyline(pts, color, 5.0, true)
		# moving chevrons
		for i in 5:
			var t := fposmod(_t * 0.8 + i / 5.0, 1.0)
			var p := from.lerp(mid, t).lerp(mid.lerp(to, t), t)
			draw_circle(p, 4.0, Color.WHITE)
		var tip_dir := (to - pts[18]).normalized()
		var tn := Vector2(-tip_dir.y, tip_dir.x)
		draw_colored_polygon(PackedVector2Array([to + tip_dir * 8, to - tip_dir * 22 + tn * 16, to - tip_dir * 22 - tn * 16]), color)
		draw_arc(to, 30.0 + 4.0 * sin(_t * 8.0), 0, TAU, 32, Color(color, 0.8), 3.0, true)


class FxImpact extends Node2D:
	var color := Color.WHITE
	var big := false
	var shards := false
	var _t := 0.0
	var _sparks: Array = []

	func _ready() -> void:
		var n := 0 if Sabacc.perf() else (14 if big else 8)
		for i in n:
			var a := randf() * TAU
			_sparks.append({"v": Vector2(cos(a), sin(a)) * randf_range(120, 380), "p": Vector2.ZERO})

	func _process(dt: float) -> void:
		_t += dt
		for s in _sparks:
			s["p"] += s["v"] * dt
			s["v"] *= 0.9
		queue_redraw()
		if _t > 0.5:
			queue_free()

	func _draw() -> void:
		if _t >= 0.5:
			return
		var k := _t / 0.5
		var r := (60.0 if big else 38.0) * (0.3 + k)
		draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(color, 1.0 - k), 6.0 * (1.0 - k) + 1.0, true)
		draw_circle(Vector2.ZERO, r * 0.35 * (1.0 - k), Color(1, 1, 1, 0.8 * (1.0 - k)))
		for s in _sparks:
			var p: Vector2 = s["p"]
			if shards:
				var d: Vector2 = s["v"].normalized() * 10.0
				draw_line(p, p + d, Color(color, 1.0 - k), 3.0)
			else:
				draw_line(p, p - s["v"] * 0.03, Color(color.lightened(0.4), 1.0 - k), 2.0)


class FxShockwave extends Node2D:
	var color := Color(1, 0.85, 0.6)
	var _t := 0.0
	var _rocks: Array = []

	func _ready() -> void:
		var n := 0 if Sabacc.perf() else 12
		for i in n:
			var a := randf() * TAU
			_rocks.append({"p": Vector2.ZERO, "v": Vector2(cos(a), sin(a) * 0.6) * randf_range(160, 420), "s": randf_range(3, 7)})

	func _process(dt: float) -> void:
		_t += dt
		for r in _rocks:
			r["p"] += r["v"] * dt
			r["v"] = r["v"] * 0.88 + Vector2(0, 600) * dt
		queue_redraw()
		if _t > 0.6:
			queue_free()

	func _draw() -> void:
		if _t >= 0.6:
			return
		var k := _t / 0.6
		draw_arc(Vector2.ZERO, 30.0 + k * 140.0, 0, TAU, 48, Color(color, (1.0 - k) * 0.9), 10.0 * (1.0 - k) + 1.0, true)
		draw_arc(Vector2.ZERO, 15.0 + k * 90.0, 0, TAU, 48, Color(1, 1, 1, (1.0 - k) * 0.6), 4.0, true)
		for r in _rocks:
			draw_rect(Rect2(r["p"], Vector2(r["s"], r["s"])), Color(0.55, 0.45, 0.35, 1.0 - k))


## Heavier blaster bolt: glow + white core, impact burst on arrival.
static func shockwave(layer: Control, at: Vector2) -> void:
	var s := FxShockwave.new()
	layer.add_child(s)
	s.global_position = at
	Sfx.play("defeat", 1.6)
