extends Button

var expanded := false
var _amount: Label
var _width_animation: Tween


func _ready() -> void:
	flat = true
	custom_minimum_size.y = 30
	focus_mode = Control.FOCUS_ALL
	var content := UIKit.credit_label("")
	content.position = Vector2(13, 1)
	_amount = content.get_node("Amount")
	_amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	pressed.connect(func():
		expanded = not expanded
		refresh(true))
	resized.connect(queue_redraw)
	refresh()


func refresh(animate := false) -> void:
	var balance := Progression.credits()
	_amount.text = str(balance) if expanded else _compact(balance)
	tooltip_text = "%d • Tap to %s" % [balance, "collapse" if expanded else "expand"]
	var target := 58.0 + _amount.get_combined_minimum_size().x
	if _width_animation:
		_width_animation.kill()
	if animate and not Sabacc.perf():
		_width_animation = create_tween()
		_width_animation.tween_property(self, "size:x", target, Sabacc.anim(0.16)).set_trans(Tween.TRANS_QUAD)
	else:
		size.x = target
	queue_redraw()


static func _compact(balance: int) -> String:
	if balance >= 1000000:
		return _scaled(balance, 1000000, "m")
	if balance >= 1000:
		return _scaled(balance, 1000, "k")
	return str(balance)


static func _scaled(balance: int, unit: int, suffix: String) -> String:
	var truncated := floorf(10.0 * balance / unit) / 10.0
	return (str(int(truncated)) if truncated == floorf(truncated) else "%.1f" % truncated) + suffix


func _draw() -> void:
	var width := size.x
	var height := size.y
	var points := PackedVector2Array([Vector2(0, height / 2), Vector2(10, 1), Vector2(width - 10, 1),
		Vector2(width, height / 2), Vector2(width - 10, height - 1), Vector2(10, height - 1)])
	draw_colored_polygon(points, Color("292012"))
	points.append(points[0])
	draw_polyline(points, Sabacc.C_GOLD, 1.8, true)
