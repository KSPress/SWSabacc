extends Button
## Watches the same pointer as Button, while a hold consumes its purchase.

signal held

var hold_fired := false
var _hold := Timer.new()
var _down_at := Vector2.ZERO
var _touch_index := -1


func _ready() -> void:
	_hold.one_shot = true
	_hold.wait_time = 0.45
	_hold.timeout.connect(func():
		hold_fired = true
		held.emit())
	add_child(_hold)
	mouse_exited.connect(_hold.stop)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		hold_fired = false
	if event is InputEventScreenTouch and event.pressed and _touch_index < 0:
		_touch_index = event.index
		_begin_hold(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _touch_index < 0:
			_begin_hold(event.position)
		else:
			if not event.pressed:
				_hold.stop()


func _begin_hold(local_point: Vector2) -> void:
	hold_fired = false
	_down_at = get_global_transform_with_canvas() * local_point
	_hold.start()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.index == _touch_index and not event.pressed:
		_touch_index = -1
		_hold.stop()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_hold.stop()
	elif not _hold.is_stopped() and ((event is InputEventMouseMotion and _touch_index < 0)
		or (event is InputEventScreenDrag and event.index == _touch_index)) and event.position.distance_to(_down_at) > 16.0:
		_hold.stop()
		hold_fired = true
