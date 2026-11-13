extends "res://tests/shots.gd"
## Exercise the GUI input pipeline rather than emitting button signals.
var checks := 0
var failures := 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", description)


func _button(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and node.text.begins_with(text):
			return node
	return null


func _click(control: Control, fraction := Vector2(0.5, 0.5)) -> void:
	var at := control.get_global_transform_with_canvas() * (control.size * fraction)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)
	await _wait(0.08)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = at
		event.global_position = at
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await _wait(0.65)


func _run() -> void:
	Save.data = Save.default_data()
	Progression.ensure_account()
	Sabacc.settings["anim_speed"] = 1.0
	Sabacc.settings["perf_mode"] = false
	await _go("res://ui/screens/boot.tscn")
	await _wait(1.7)
	check(get_tree().current_scene.scene_file_path.ends_with("main_menu.tscn"), "real splash reaches menu")
	check(not Router._busy and Router._fade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "splash transition releases input")
	Cosmetics.set_gm(true)
	Cosmetics.equip("background", "emblem")
	var routes := [["Campaigns", "mode_hub"], ["Battles", "mode_hub"], ["Deck Builder", "decks"], ["Collection Vault", "collection"], ["Card Packs", "pack_opening"], ["Customization", "customization"], ["Settings", "settings_screen"], ["Profile", "customization"]]
	for dims in [[360, 640], [540, 1200], [1280, 720], [2560, 1080]]:
		await _size(dims[0], dims[1])
		await _go("menu")
		var menu := get_tree().current_scene
		var bounds: Array[Rect2] = []
		for button in menu._buttons.get_children():
			var rect: Rect2 = button.get_global_rect()
			check(menu.get_viewport_rect().encloses(rect), "menu button stays in view %s %s" % [button.text, dims])
			check(not bounds.any(func(previous): return previous.intersects(rect)), "menu button stays separate %s %s" % [button.text, dims])
			bounds.append(rect)
		for route in routes:
			await _go("menu")
			var scene := get_tree().current_scene
			var button := _button(scene, route[0])
			check(button != null, "button exists " + route[0])
			if button == null:
				continue
			await _click(button)
			check(get_tree().current_scene.scene_file_path.ends_with(route[1] + ".tscn"), "pointer navigation %s %s" % [route[0], dims])
			check(not Router._busy and Router._fade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "navigation releases input")
		await _go("menu")
		var scene := get_tree().current_scene
		await _click(scene._floaters[1])
		var overlays := scene.find_children("*", "InspectOverlay", true, false)
		check(overlays.size() == 1, "showcase pointer opens inspector %s" % [dims])
		if overlays.size():
			var overlay: InspectOverlay = overlays[0]
			await _click(overlay._card)
			check(is_instance_valid(overlay._expanded), "pointer expands anatomy")
			if is_instance_valid(overlay._expanded):
				var action := _button(overlay._expanded, "Back to card")
				check(overlay.get_viewport_rect().encloses(action.get_global_rect()), "expanded close always on screen")
				check(not overlay._expanded._scroll.is_ancestor_of(action), "expanded close outside scroll content")
				await _click(_button(overlay._expanded, "Back to card"))
				check(not is_instance_valid(overlay._expanded), "expanded modal removed")
			await _click(overlay._card)
			Router._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
			await _wait(0.3)
			check(is_instance_valid(overlay) and not is_instance_valid(overlay._expanded), "Android Back closes only expanded dossier")
			await _click(_button(overlay, "Close"))
			check(scene.find_children("*", "InspectOverlay", true, false).is_empty(), "inspector removed")
		await _click(_button(scene, "Battles"))
		check(get_tree().current_scene.scene_file_path.ends_with("mode_hub.tscn"), "menu clickable after inspect close")
		var cancel := InputEventKey.new()
		cancel.keycode = KEY_ESCAPE
		cancel.pressed = true
		get_viewport().push_input(cancel, true)
		await _wait(0.65)
		check(get_tree().current_scene.scene_file_path.ends_with("main_menu.tscn"), "Escape returns to menu")
		print("INPUT RATIO COMPLETE ", dims)
	print("INTERACTION: %d checks, %d failed" % [checks, failures])
	if failures:
		get_tree().quit(1)
