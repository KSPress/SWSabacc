extends "res://tests/interaction_tests.gd"


func _choice(scene: Node) -> Button:
	for tile in scene._grid.get_children():
		var last: Node = tile.get_child(tile.get_child_count() - 1) if tile.get_child_count() else null
		if last is Button and not last.text.begins_with("Equipped"):
			return last
	return null


func _touch(at: Vector2, down: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = at
	touch.pressed = down
	get_viewport().push_input(touch, true)
	# Android's emulated mouse path drives BaseButton taps.
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.position = at
	mouse.global_position = at
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = down
	get_viewport().push_input(mouse, true)
	await get_tree().process_frame


func _swipe(at: Vector2, distance: float) -> void:
	await _drag(at, Vector2(0, -distance))


func _drag(at: Vector2, shift: Vector2) -> void:
	await _touch(at, true)
	for i in 6:
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = at + shift * (i + 1) / 6
		event.relative = shift / 6
		get_viewport().push_input(event, true)
		var mouse := InputEventMouseMotion.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION
		mouse.position = event.position
		mouse.global_position = event.position
		mouse.relative = event.relative
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(mouse, true)
		await get_tree().process_frame
	await _touch(at + shift, false)
	await _wait(0.15)


func _run() -> void:
	Save.data = Save.default_data()
	Progression.ensure_account()
	Cosmetics.set_gm(true)
	Input.emulate_touch_from_mouse = true
	print("Touchscreen/emulation available: ", DisplayServer.is_touchscreen_available())
	await _size(540, 960)
	await _go("collection")
	var vault := get_tree().current_scene
	var vault_scroll: ScrollContainer = vault._scroll
	var first: Control = vault_scroll._tiles[0].get_child(0)
	await _swipe(first.get_global_rect().get_center(), 310)
	check(vault_scroll.scroll_vertical > 100 and vault.find_children("*", "InspectOverlay", true, false).is_empty(),
		"Vault swipes beginning on a card vault_scroll without opening it")
	vault_scroll.scroll_vertical = int(vault_scroll.get_v_scroll_bar().max_value)
	await _wait(0.2)
	check(vault_scroll._tiles.has(vault_scroll._ids.size() - 1) and vault_scroll._tiles.size() < 100, "Last card is reachable without loading the full catalog")
	vault_scroll.scroll_vertical = 0
	await _wait(0.2)
	await _click(vault._filters._set_button)
	var set_panel: ModalPanel = vault.find_children("*", "ModalPanel", true, false)[0]
	var twilight: Button
	for button in set_panel.box.get_children():
		if button is Button and button.get_child(0).get_child(-1).text == "Twilight of the Republic":
			twilight = button
			break
	check(twilight != null and twilight.get_child(0).get_child(0).texture != null, "Set chooser shows the Twilight logo")
	await _click(twilight)
	var filters = vault._filters
	filters.filters.merge({"type": "unit", "aspects": ["command", "heroism"], "trait": "republic"}, true)
	filters.changed.emit()
	check(vault_scroll._ids.size() > 0 and vault_scroll._ids.all(func(id):
		var card := CardDB.card(id)
		return (card["set"] == "TWI" and card["type"] == "unit" and "republic" in card["traits"]
			and "command" in card["aspects"] and "heroism" in card["aspects"])), "Set, type, trait and two aspects combine")
	var found_keyword := ""
	for id in vault_scroll._ids:
		var keywords := CardLibrary.keyword_names(CardDB.card(id))
		if not keywords.is_empty():
			found_keyword = keywords[0]
			break
	check(not found_keyword.is_empty(), "Filtered Republic units include printed keywords")
	filters.filters["keyword"] = found_keyword
	filters.changed.emit()
	check(vault_scroll._ids.size() > 0 and vault_scroll._ids.all(func(id):
		return found_keyword in CardLibrary.keyword_names(CardDB.card(id))), "Keyword combines with the other card filters")
	await _go("deck_editor")
	var editor := get_tree().current_scene
	var pool: ScrollContainer = editor._pool_scroll
	var first_card: Control = pool._tiles[0].get_child(0)
	await _swipe(first_card.get_global_rect().get_center(), 310)
	check(pool.scroll_vertical > 100 and editor.deck["cards"].is_empty(), "Swiping deck cards scrolls without adding them")
	pool.scroll_vertical = 0
	await _wait(0.2)
	await _click(pool._tiles[0].get_child(0))
	check(editor.deck["cards"].size() == 1, "Tapping a deck card still adds it")
	await _click(editor._leader_slot)
	var leader_picker: CardPicker = editor.find_children("*", "CardPicker", true, false)[0]
	check(leader_picker._card_filters != null, "Leader selection uses the same card filters")
	for dimensions in [[360, 640], [1280, 720]]:
		await _size(dimensions[0], dimensions[1])
		for kind in ["emblem", "cardback", "background"]:
			await _go("customization")
			var scene := get_tree().current_scene
			scene._kind = kind
			scene._populate()
			await _wait(0.3)
			if only == "baseline":
				# Restore the previous native-only scroll/input hierarchy.
				scene._scroll.set_script(null)
				scene._canvas.mouse_filter = Control.MOUSE_FILTER_STOP
				for image in scene._grid.find_children("*", "TextureRect", true, false):
					image.mouse_filter = Control.MOUSE_FILTER_STOP
			# A short viewport also exercises the small background catalogue.
			scene._scroll.size.y = minf(scene._scroll.size.y, 320)
			await _wait(0.15)
			var scroll: ScrollContainer = scene._scroll
			check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "scrollable " + kind)
			var preview: Control = scene._grid.get_child(0).get_child(0)
			var start: Vector2 = preview.get_global_rect().get_center()
			var expected := mini(130, roundi(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page))
			await _swipe(start, 130)
			check(absi(scroll.scroll_vertical - expected) <= 2, "finger swipe on preview without double movement %s %s" % [kind, dimensions])
			scroll.scroll_vertical = 0
			await _wait(0.1)
			var button := _choice(scene)
			var selected := Cosmetics.equipped(kind)
			await _swipe(button.get_global_rect().get_center(), 30)
			check(scroll.scroll_vertical > 14, "finger swipe starts on button " + kind)
			check(Cosmetics.equipped(kind) == selected, "swipe does not equip " + kind)
			scroll.scroll_vertical = 0
			await _wait(0.1)
			selected = Cosmetics.equipped(kind)
			button = _choice(scene)
			await _drag(button.get_global_rect().get_center(), Vector2(40, 0))
			check(Cosmetics.equipped(kind) == selected, "horizontal swipe does not equip " + kind)
			preview = scene._grid.get_child(0).get_child(0)
			var pan := InputEventPanGesture.new()
			pan.position = preview.get_global_rect().get_center()
			pan.delta = Vector2(0, 4)
			get_viewport().push_input(pan, true)
			await get_tree().process_frame
			check(scroll.scroll_vertical > 0, "trackpad pan reaches scroll " + kind)
			scroll.scroll_vertical = 0
			await _wait(0.1)
			selected = Cosmetics.equipped(kind)
			button = _choice(scene)
			var at := button.get_global_rect().get_center()
			await _touch(at, true)
			await _touch(at, false)
			await _wait(0.2)
			check(Cosmetics.equipped(kind) != selected, "stationary finger tap still equips " + kind)
	print("TOUCH SCROLL: %d checks, %d failed" % [checks, failures])
	if failures:
		get_tree().quit(1)
