class_name TouchScroll
extends ScrollContainer
## Follow a finger even when a child button consumes GUI mouse events.
## Taps remain button taps; crossing the drag threshold cancels their press.
var _finger := -1
var _start := Vector2.ZERO
var _offset := 0.0
var _dragging := false


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_finish()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _finger != -1 and event.index != _finger:
				return
			_finish()
			if not get_global_rect().has_point(event.position):
				return
			for control in find_children("*", "Range", true, false):
				if (control is HSlider or control is VSlider) and control.is_visible_in_tree() and control.get_global_rect().has_point(event.position):
					return
			var bar := get_v_scroll_bar()
			if bar.is_visible_in_tree() and bar.get_global_rect().has_point(event.position):
				return
			# Do not scroll a collection underneath an open inspector/dialog.
			for modal in get_tree().get_nodes_in_group("back_dismissible"):
				if modal.is_visible_in_tree():
					return
			_finger = event.index
			_start = event.position
			_offset = scroll_vertical
		elif not event.pressed and event.index == _finger:
			var was_dragging := _dragging
			_finish()
			if was_dragging:
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _finger:
		var distance: float = _start.y - event.position.y
		if not _dragging and event.position.distance_to(_start) > 14:
			_dragging = true
			propagate_notification(NOTIFICATION_SCROLL_BEGIN)
			scroll_started.emit()
		if _dragging:
			scroll_vertical = roundi(_offset + distance)
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	# Native ScrollContainer also handles emulated mouse dragging on Android.
	# Our finger path owns that gesture; avoid applying its movement twice.
	if _finger >= 0 and event.device == InputEvent.DEVICE_ID_EMULATION and (event is InputEventMouseButton or event is InputEventMouseMotion):
		accept_event()


func _finish() -> void:
	if _dragging:
		propagate_notification(NOTIFICATION_SCROLL_END)
		scroll_ended.emit()
	_finger = -1
	_dragging = false
