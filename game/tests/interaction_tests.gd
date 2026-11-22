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
	Sabacc.settings["anim_speed"] = 1.0
	Sabacc.settings["perf_mode"] = false
	if only in ["conquest", "conquest-duel"]:
		if only == "conquest":
			await _test_conquest()
		else:
			await _size(390, 844)
			await _test_conquest_duel()
		print("CONQUEST INPUT: %d checks, %d failed" % [checks, failures])
		if failures:
			get_tree().quit(1)
			await get_tree().process_frame
		return
	if only == "sabacc_war":
		await _test_sabacc_war()
		print("SABACC WAR INPUT: %d checks, %d failed" % [checks, failures])
		if failures:
			get_tree().quit(1)
			await get_tree().process_frame
		return
	if only == "campaign_update":
		await _test_campaign_update()
		print("CAMPAIGN UPDATE: %d checks, %d failed" % [checks, failures])
		if failures:
			get_tree().quit(1)
			await get_tree().process_frame
		return
	if only == "trigger_picker":
		await _test_trigger_picker()
		print("TRIGGER PICKER INPUT: %d checks, %d failed" % [checks, failures])
		if failures:
			get_tree().quit(1)
			await get_tree().process_frame
		return
	if only == "tie_advanced":
		await _test_tie_advanced_target_picker()
		print("TIE ADVANCED INPUT: %d checks, %d failed" % [checks, failures])
		if failures:
			get_tree().quit(1)
			await get_tree().process_frame
		return
	await _go("res://ui/screens/boot.tscn")
	await _wait(4.5)
	var welcome := get_tree().current_scene
	check(welcome.scene_file_path.ends_with("welcome.tscn"), "Fresh save reaches the welcome screen")
	check(Progression.starting_sets().size() == 9, "All nine main booster sets are offered")
	if welcome.scene_file_path.ends_with("welcome.tscn"):
		await _shot("welcome")
		var homeworlds := _button(welcome, "Homeworlds")
		welcome._scroll.ensure_control_visible(homeworlds)
		await _wait(0.3)
		await _click(homeworlds)
		await _click(_button(welcome, "Choose this set"))
	check(get_tree().current_scene.scene_file_path.ends_with("main_menu.tscn"), "Choosing a set reaches the menu")
	check(Progression.credits() == 1000 and Progression.packs().size() == 3 and Progression.packs().all(func(pack): return pack["set"] == "HMW"), "Welcome grants three matching packs and 1,000 credits")
	check(CardDB.official_pair("HMW").all(Progression.deck_owned), "Both selected official decks are unlocked")
	check(not Progression.claim_starting_set("SOR"), "The starter gift can only be collected once")
	Save.load_save()
	check(not Progression.needs_welcome(), "Welcome choice survives save reload")
	Save.data = Save.default_data()
	Progression.ensure_account()
	check(not Router._busy and Router._fade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "splash transition releases input")
	Cosmetics.set_gm(true)
	Cosmetics.equip("background", "emblem")
	Cosmetics.set_gm(false)
	Progression.award_credits("stats-test", 1200)
	Progression.buy_pack("ASH")
	Cosmetics.record_match(true, "stats-win", 0, ["command", "command", "heroism"], "SOR_017", {"aggression": 5})
	Cosmetics.record_match(false, "stats-loss", 1, ["command", "villainy"], "SOR_017")
	Cosmetics.record_match(false, "stats-draw", 2, ["aggression"], "SOR_009")
	Save.load_save()
	var stats := Progression.account_stats()
	check(stats["matches"] == 3 and stats["wins"] == 1 and stats["draws"] == 1, "Account preserves wins, losses and draws")
	check(stats["aspects"]["command"] == 2 and stats["leaders"]["SOR_017"] == 2, "Favorites count a deck aspect once per match")
	check(stats["boosters"]["ASH"] == 1 and stats["credits_earned"] == 1200 and Progression.credits() == 200, "Stats retain gross credits and paid boosters")
	var stats_menu := get_tree().current_scene
	await _click(stats_menu._stats_button)
	check(get_tree().current_scene.scene_file_path.ends_with("account_stats.tscn"), "Main menu stats icon opens Account Stats")
	var stats_screen := get_tree().current_scene
	await _shot("account-stats")
	var wallet := stats_screen.get_node("AccountCredits")
	check(wallet._amount.text == "200", "Account Stats shows the shared balance without a suffix")
	check(stats["played_aspects"].get("aggression", 0) == 5 and not stats["played_aspects"].has("command"),
		"Favorite aspect uses cards played rather than the leader and base")
	Progression.award_credits("wallet-million-test", 1000100)
	check(wallet._amount.text == "1m", "Wallet abbreviates seven-digit balances")
	await _click(wallet)
	check(wallet._amount.text == "1000300", "Wallet tap shows the exact balance")
	await _click(wallet)
	check(wallet._amount.text == "1m", "Wallet tap collapses the balance")
	await _go("menu")
	var routes := [["PLAY", "play_carousel"], ["Collection Vault", "collection"], ["Customization", "customization"], ["Settings", "settings_screen"], ["Profile", "customization"]]
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
		await _click(_button(scene, "PLAY"))
		check(get_tree().current_scene.scene_file_path.ends_with("play_carousel.tscn"), "PLAY clickable after inspect close")
		var carousel := get_tree().current_scene
		check(carousel._open.text == "Campaigns", "Campaigns is selected first")
		var center: Vector2 = carousel._stage.get_global_rect().get_center()
		await _drag(center, center + Vector2(-100, 0))
		check(carousel._open.text == "Battles", "swiping the cards selects Battles")
		await _drag(center, center + Vector2(-100, 0))
		check(carousel._open.text == "Galactic Conquest" and not carousel._open.disabled, "Conquest is available from PLAY")
		var cancel := InputEventKey.new()
		cancel.keycode = KEY_ESCAPE
		cancel.pressed = true
		get_viewport().push_input(cancel, true)
		await _wait(0.65)
		check(get_tree().current_scene.scene_file_path.ends_with("main_menu.tscn"), "Escape returns to menu")
		print("INPUT RATIO COMPLETE ", dims)
	await _test_tie_advanced_target_picker()
	print("INTERACTION: %d checks, %d failed" % [checks, failures])
	if failures:
		get_tree().quit(1)
		await get_tree().process_frame


func _test_conquest() -> void:
	await _size(360, 640)
	await _go("play", {"selected": 2})
	await _click(_button(get_tree().current_scene, "Galactic Conquest"))
	var screen := get_tree().current_scene
	await _click(_button(screen, "Rebels"))
	await _click(_button(screen, "16 planets"))
	check(screen._leader_name.text.begins_with("Luke Skywalker"), "Selecting Rebels equips Luke")
	check(get_viewport().get_visible_rect().encloses(_button(screen, "Start conquest").get_global_rect()),
		"Faction setup fits a compact portrait screen")
	for index in screen._leader_picker.item_count:
		if screen._leader_picker.get_item_metadata(index) == "JTL_012":
			screen._leader_picker.item_selected.emit(index)
			break
	await _shot("conquest-faction")
	await _click(_button(screen, "Start conquest"))
	for side in Conquest.run.state["factions"]:
		side["next_order"] = 9999
	Conquest.run.state["next_income"] = 9999
	check(Conquest.run.state["worlds"].size() == 16 and Conquest.run.state["player"] == 1, "Create the selected galaxy")
	check(Conquest.run.fleet(1)["leader"] == "JTL_012", "The chosen leader printing commands the first fleet")
	check(screen._map._planet_art.has("Mandalore") and screen._map._planet_art.has("Hoth"), "Supplied cutouts load on the galaxy map")
	var deployed_art := Art.get_now(CardDB.card("JTL_012")["art"], true)
	check(deployed_art != Art.placeholder and screen._map._deployed_leader_art("JTL_012") == deployed_art,
		"The fleet displays its selected leader's deployed artwork")
	_check_conquest_layout(screen, true)
	await _shot("conquest-compact-portrait")
	await _size(540, 960)
	await _test_factory_catalog(screen)
	await _shot("conquest-portrait")
	var map_top := Vector2(get_viewport().get_visible_rect().size.x * 0.5, screen.header.position.y - 8.0)
	var top_offset: float = screen._map.camera_offset.x
	await _drag(map_top, map_top - Vector2(65, 0))
	check(screen._map.camera_offset.x < top_offset, "Drag input works above the header")
	await _click(_button(screen, "Locate fleet"))
	var center: Vector2 = screen._map.get_global_rect().get_center()
	var initial_x: float = screen._map.camera_offset.x
	await _drag(center, center - Vector2(115, 0))
	check(screen._map.camera_offset.x < initial_x, "Dragging pans the strategic galaxy map")
	await _click(_button(screen, "Locate fleet"))
	var initial_zoom: float = screen._map.zoom
	var anchor := center + Vector2(50, 30)
	var anchor_local: Vector2 = screen._map.get_global_transform().affine_inverse() * anchor
	var coordinate: Vector2 = (anchor_local - screen._map.camera_offset) / screen._map.zoom
	for button in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var wheel := InputEventMouseButton.new()
		wheel.pressed = true
		wheel.button_index = button
		wheel.position = anchor
		wheel.global_position = anchor
		get_viewport().push_input(wheel, true)
		if button == MOUSE_BUTTON_WHEEL_UP:
			check(screen._map.zoom > initial_zoom and (coordinate * screen._map.zoom + screen._map.camera_offset).distance_to(anchor_local) < 2.0,
				"Mouse wheel zooms in around the cursor")
		wheel.pressed = false
		get_viewport().push_input(wheel, true)
	check(is_equal_approx(screen._map.zoom, initial_zoom), "Mouse wheel zooms back out")
	var selected: String = screen._selected
	_conquest_touch(0, center - Vector2(55, 0), true)
	_conquest_touch(1, center + Vector2(55, 0), true)
	var pinch := InputEventScreenDrag.new()
	pinch.index = 1
	pinch.position = center + Vector2(110, 0)
	get_viewport().push_input(pinch, true)
	check(screen._map.zoom > initial_zoom, "Spreading two fingers zooms in")
	pinch.position = center + Vector2(55, 0)
	get_viewport().push_input(pinch, true)
	check(is_equal_approx(screen._map.zoom, initial_zoom), "Pinching two fingers zooms out")
	_conquest_touch(1, center + Vector2(55, 0), false)
	_conquest_touch(0, center - Vector2(55, 0), false)
	check(screen._selected == selected, "Releasing a pinch does not select a planet")
	var pan_before: Vector2 = screen._map.camera_offset
	_conquest_touch(0, center, true)
	pinch.index = 0
	pinch.position = center - Vector2(70, 0)
	get_viewport().push_input(pinch, true)
	_conquest_touch(0, pinch.position, false)
	check(screen._map.camera_offset.x < pan_before.x and screen._selected == selected, "One-finger dragging pans without selecting")
	await _click(_button(screen, "Locate fleet"))
	var target: Vector2 = screen._map.get_global_transform() * screen._map.world_position("Mandalore")
	_conquest_touch(0, target, true)
	_conquest_touch(0, target, false)
	check(screen._selected == "Mandalore" and not screen._orders.disabled, "Tap a neighbor to select the marked planet")
	await _size(1280, 720)
	_check_conquest_layout(screen, false)
	for edge in ["Dathomir", "Hoth", "Kamino"]:
		screen._map.center_on(edge)
		check(screen._map._camera_region.has_point(screen._map.world_position(edge)),
			"Centering %s clears the command overlays" % edge)
	var map_center: Vector2 = screen._map.size * 0.5
	var map_zoom: float = screen._map.zoom
	check(screen._map._symbols.has("mandalore") and screen._map._symbols.has("rebels"),
		"Special worlds and factions load the supplied transparent icons")
	var colors := {
		"Coruscant": ["Empire", Color.WHITE], "Yavin": ["Rebels", Color("#ff9d41")],
		"Nal Hutta": ["Hutts", Color("#63d88c")], "Kamino": ["Republic", Color("#f0525e")],
		"Geonosis": ["Separatists", Color("#68a5ff")],
	}
	for world in colors:
		screen._selected = world
		screen._refresh()
		check(colors[world][0] in screen._world_info.text
			and screen._world_info.get_theme_color("font_color") == colors[world][1],
			"Planet control panel uses %s colors" % colors[world][0])
	var kamino: Dictionary = Conquest.run.state["worlds"]["Kamino"]
	kamino["owner"] = 1
	screen._selected = "Kamino"
	screen._refresh()
	check("Rebels" in screen._world_info.text and screen._world_info.get_theme_color("font_color") == colors["Yavin"][1],
		"Capturing a local territory gives it the victor's color")
	kamino["owner"] = -1
	screen._selected = "Mandalore"
	screen._refresh()
	screen._map.zoom_at(0.75 / map_zoom, map_center, map_center)
	screen._map.center_on("Nal Hutta")
	var worlds: Dictionary = Conquest.run.state["worlds"]
	for pair in [["Corellia", 0], ["Mandalore", 1], ["Kashyyyk", 2]]:
		worlds[pair[0]]["owner"] = pair[1]
	await get_tree().process_frame
	await _shot("conquest-faction-colors")
	for world in ["Corellia", "Mandalore", "Kashyyyk"]:
		worlds[world]["owner"] = -1
	screen._map.zoom_at(map_zoom / screen._map.zoom, map_center, map_center)
	screen._map.center_on("Mandalore")
	await get_tree().process_frame
	await _shot("conquest-landscape")
	await _click(screen._orders)
	var task := Conquest.run.fleet(1)
	check(task["route"] == ["Mandalore"] and Conquest.run.player_battle().is_empty(), "Attack sends the fleet through hyperspace")
	task["arrival"] = Conquest.run.state["time"]
	await _wait(0.55)
	check(screen._battle.visible, "Arrival prepares the battle")
	await _size(390, 844)
	_check_conquest_layout(screen, true)
	await _shot("conquest-battle-ready-portrait")
	await _click(screen._battle)
	var match_screen := get_tree().current_scene
	check(match_screen.params.get("mode") == "conquest" and match_screen.m.players[1].leader == null,
		"Militia battle opens in the actual match scene with a leaderless defender")
	check(match_screen.params.get("battle_world") == "Mandalore", "Battle loads the selected planet backdrop")
	check(match_screen.theme_bg._planet == ConquestGalaxy.supplied_planet("Mandalore"), "The battle uses the same supplied planet art")
	check(match_screen.m.players[0].base.max_hp() == 30 and match_screen.m.players[0].base.name() == "Luke Skywalker",
		"The match HUD uses 30 HP command instead of a base card")
	await _wait_for_conquest_turn(match_screen)
	var commander: CardInst = match_screen.m.players[0].base
	var token: UnitToken = match_screen.tokens.get(commander.uid)
	check(token != null and token.inst == match_screen.m.players[0].leader and commander.deployed
		and not match_screen.hud[0].leader_view.visible and not match_screen.hud[0].base_view.visible
		and match_screen._command_slots[0].has_point(token.center_global()),
		"One deployed Sabacc commander occupies the command slot")
	_check_commander_slot(match_screen, token)
	await _size(1280, 720)
	_check_commander_slot(match_screen, token)
	await _shot("conquest-commander-landscape")
	await _size(390, 844)
	await _wait(0.8)
	await _shot("conquest-battle-background")
	if token:
		await _click(token, UnitToken.FACE_CENTER / token.size)
		if match_screen.menu_popup:
			await _click(_button(match_screen.menu_popup, "Attack"))
		check(match_screen._selected == token, "Tapping the commander selects it as attacker")
		await _click(match_screen.hud[1].base_view)
		check(commander.exhausted and match_screen.m.players[1].base.damage > 0, "The commander attacks from the base slot")
		await _wait(0.8)
	await _wait_for_conquest_turn(match_screen)
	check(not match_screen.retreat_btn.disabled, "The commander can retreat during their action")
	await _click(match_screen.retreat_btn)
	var withdraw := _button(match_screen, "Withdraw to Yavin 4")
	check(withdraw != null, "Retreat confirms the departure world")
	if withdraw:
		await _click(withdraw)
		await _click(_button(match_screen, "Return to galaxy"))
		await _wait(0.3)
		screen = get_tree().current_scene
		check(task["retreating"] and task["route"] == ["Yavin"] and task["leader_alive"], "Retreat returns a living commander through hyperspace")
		task["arrival"] = Conquest.run.state["time"]
		await _wait(0.45)
		check(task["world"] == "Yavin" and not task["retreating"], "The fleet arrives back at its departure world")
		screen._selected = "Mandalore"
		screen._refresh()
		await _click(screen._orders)
		task["arrival"] = Conquest.run.state["time"]
		await _wait(0.55)
		await _click(screen._battle)
		match_screen = get_tree().current_scene
		await _wait_for_conquest_turn(match_screen)
	match_screen.m.set_winner(0, "Conquest smoke test")
	match_screen._game_over()
	await _wait(0.4)
	await _click(_button(match_screen, "Return to galaxy"))
	await _wait(0.4)
	screen = get_tree().current_scene
	check(Conquest.run.state["worlds"]["Mandalore"]["owner"] == 1 and Progression.credits() == 0,
		"Battle captures the planet and pays only conquest credits")
	await _click(_button(screen, "Planet production"))
	var garrison := _button(screen, "Build garrison")
	check(garrison != null and not garrison.disabled, "Production offers a garrison on a captured world")
	if garrison:
		var owner: Node = garrison
		while owner and not owner is ScrollContainer:
			owner = owner.get_parent()
		if owner:
			owner.ensure_control_visible(garrison)
			await _wait(0.2)
		await _click(garrison)
	check("garrison" in Conquest.run.state["worlds"]["Mandalore"]["facilities"], "Garrison build persists through the real UI")
	Conquest.run.state["factions"][1]["credits"] = 300
	Conquest.persist()
	var training_center := _button(screen, "Build training center")
	check(training_center != null and not training_center.disabled, "Planet production offers a Training Center")
	if training_center:
		var training_scroll: Node = training_center
		while training_scroll and not training_scroll is ScrollContainer:
			training_scroll = training_scroll.get_parent()
		if training_scroll:
			training_scroll.ensure_control_visible(training_center)
			await _wait(0.2)
		await _click(training_center)
	var training_button := _button(screen, "Train selected fleet")
	check(training_button != null and not training_button.disabled, "Stationed fleets can use the Training Center")
	if training_button:
		await _click(training_button)
		var health := _button(screen, "Command endurance")
		check(health != null and not health.disabled, "The Training Center offers command endurance")
		if health:
			await _click(health)
	check(Conquest.run.command_max_hp(Conquest.run.fleet(1)) == 35, "A UI training purchase adds five command HP")
	await _shot("conquest-training")
	check(Conquest.save_slot(1, "Mandalore captured"), "Write a named slot")
	check(Conquest.save_slot(1, "Mandalore checkpoint"), "Overwrite a named slot")
	Conquest.run.state["worlds"]["Mandalore"]["owner"] = -1
	check(Conquest.load_slot(1) and Conquest.run.state["worlds"]["Mandalore"]["owner"] == 1,
		"Loading restores the saved map and overwrites only the autosave")
	await _test_conquest_duel()


func _test_conquest_duel() -> void:
	Conquest.start(1, 32, "JTL_012")
	var run := Conquest.run
	for side in run.state["factions"]:
		side["next_order"] = 9999
	await _go("conquest")
	var map: Control = get_tree().current_scene._map
	var positions: Dictionary = map._planet_icon_centers
	check(positions.size() == 10, "All ten special worlds reserve a spot above their planet")
	var markers_clear := true
	for world in positions:
		var center: Vector2 = positions[world]
		var planet: Vector2 = ConquestGalaxy.WORLDS[world]
		var marker := Rect2(center - Vector2.ONE * 17.0, Vector2.ONE * 34.0)
		markers_clear = markers_clear and marker.end.y < planet.y - map._planet_radius(world)
		for neighbor in run.state["worlds"]:
			var radius: float = map._planet_radius(neighbor)
			var point: Vector2 = ConquestGalaxy.WORLDS[neighbor]
			var body := Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
			markers_clear = markers_clear and not marker.intersects(body) and not marker.intersects(map._world_label_rect(neighbor))
	check(markers_clear, "The enlarged special badges clear other planets and their names")
	map.center_on("Geonosis")
	await _shot("conquest-world-insignia")
	run._begin_battle(0, "Yavin")
	Conquest.persist()
	Conquest.play_battle(run.player_battle())
	await _wait(0.8)
	var battle := get_tree().current_scene
	check(battle.get("m") is Match, "A fleet battle opens the live match board")
	if not battle.get("m") is Match:
		return
	await _wait_for_conquest_turn(battle)
	var enemy = battle.m.players[1].base
	var opponent: UnitToken = battle.tokens.get(enemy.uid)
	var player: UnitToken = battle.tokens.get(battle.m.players[0].base.uid)
	check(opponent != null and opponent.inst == battle.m.players[1].leader and enemy.deployed
		and enemy.max_hp() == 30 and not battle.hud[1].base_view.visible and not battle.hud[1].leader_view.visible,
		"The opposing leader uses the same deployed commander token and replaces the base")
	if not player or not opponent:
		return
	_check_commander_pair(battle, player, opponent)
	await _shot("conquest-commanders-portrait")
	await _size(1280, 720)
	_check_commander_pair(battle, player, opponent)
	await _shot("conquest-commanders-landscape")
	await _click(player, UnitToken.FACE_CENTER / player.size)
	if battle.menu_popup:
		await _click(_button(battle.menu_popup, "Attack"))
	var before: int = enemy.damage
	await _click(opponent, UnitToken.FACE_CENTER / opponent.size)
	check(enemy.damage > before, "The opposing horizontal commander accepts combat input")


func _check_commander_pair(screen: Control, player: UnitToken, opponent: UnitToken) -> void:
	_check_commander_slot(screen, player)
	var arena: Rect2 = screen._arena_area
	var rect := opponent.get_global_rect()
	check(is_equal_approx(opponent.scale.x, player.scale.x)
		and absf(opponent.center_global().x - player.center_global().x) < 2.0,
		"Both commander cards share a scale and centerline")
	check(rect.end.y <= arena.position.y and get_viewport().get_visible_rect().encloses(rect)
		and not rect.intersects(screen.tracker.get_global_rect()),
		"The opposing card fits above the arena and clears the objective")
	check(screen.tokens.values().all(func(token: UnitToken):
		if token.inst.is_commander():
			return true
		var lane: Rect2 = screen.arena_rects[token.inst.zone + "_" + str(token.inst.controller)]
		return lane.has_point(token.center_global())), "Deployed units stay in their lanes after rotation")


func _wait_for_conquest_turn(screen: Control) -> void:
	for attempt in 20:
		if screen.m.can_act(0) and not screen.busy:
			return
		if not screen.busy and screen.m.phase == "setup":
			_resolve_setup(screen)
		await _wait(0.25)


func _check_commander_slot(screen: Control, token: UnitToken) -> void:
	var rect := token.get_global_rect()
	var center := get_viewport().get_visible_rect().get_center().x
	check(absf(token.center_global().x - center) < 2.0 and token.scale.x > 1.25,
		"The enlarged horizontal commander is centered (position %s, scale %s)" % [token.center_global(), token.scale])
	check(rect.position.y >= screen._arena_area.end.y and rect.end.y <= screen._hand_top
		and not rect.intersects(screen.retreat_btn.get_global_rect()),
		"The commander fits between the arena and hand without covering Retreat")


func _conquest_touch(index: int, at: Vector2, down: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = at
	touch.pressed = down
	get_viewport().push_input(touch, true)


func _check_conquest_layout(screen: Control, stacked: bool) -> void:
	var viewport := get_viewport().get_visible_rect()
	var panel: Rect2 = screen._command_panel.get_global_rect()
	var buttons: Rect2 = screen._command_scroll.get_global_rect().grow(1.0)
	check(screen._map.get_global_rect().is_equal_approx(viewport), "The map reaches all four screen edges")
	check(viewport.encloses(panel) and viewport.encloses(screen.header.get_global_rect()) and
		viewport.encloses(screen._toolbar.get_global_rect()), "Map controls fit inside the screen")
	check(screen._command_grid.columns == (2 if stacked else 1)
		and screen._command_grid.get_children().all(func(control):
			return not control.visible or buttons.encloses(control.get_global_rect())),
		"Visible commands fit the %s panel" % ("portrait" if stacked else "landscape"))


func _test_factory_catalog(screen: Control) -> void:
	await _click(_button(screen, "Planet production"))
	var barracks := _button(screen, "Build barracks")
	var scroller: Node = barracks.get_parent()
	while scroller and not scroller is ScrollContainer:
		scroller = scroller.get_parent()
	if scroller:
		scroller.ensure_control_visible(barracks)
		await _wait(0.2)
	await _click(barracks)
	await _click(_button(screen, "Factory catalog"))
	var factory_script := preload("res://ui/kit/conquest_factory_card.gd")
	var cards := screen.find_children("*", "Button", true, false).filter(func(button):
		return button.is_visible_in_tree() and button.get_script() == factory_script)
	check(not cards.is_empty(), "Factory menu shows manufacture choices as Sabacc cards")
	if cards.is_empty():
		return
	var choice: Button = cards[0]
	var id: String = choice.card["id"]
	var run := Conquest.run
	var credits: int = run.state["factions"][1]["credits"]
	var reserve: Array = run.state["worlds"]["Yavin"]["cards"]
	var copies := reserve.count(id)
	await _shot("conquest-factory-cards")
	await _click(choice)
	check(reserve.count(id) == copies + 1 and int(run.state["factions"][1]["credits"]) == credits - choice.credits,
		"Tapping a priced factory card adds the exact choice to planetary reserves")
	await _click(_button(screen, "Back"))
	await _click(_button(screen, "Back"))


func _test_sabacc_war() -> void:
	var war := preload("res://engine/cantina_war.gd")
	await _size(540, 960)
	await _go("play")
	var carousel := get_tree().current_scene
	for i in 3:
		var center: Vector2 = carousel._stage.get_global_rect().get_center()
		await _drag(center, center + Vector2(-100, 0))
	check(carousel._open.text == "Mini Games" and carousel._cards.size() == 4, "Swipe through the fourth Play card")
	await _click(carousel._open)
	var menu := get_tree().current_scene
	check(_button(menu, "Sabacc War").disabled, "New accounts see a locked Sabacc War option")
	await _shot("mini-games-locked")
	Save.clear_chapter(war.UNLOCK_CHAPTER)
	var progress := Progression.state()
	progress["sabacc_war"] = {"decks": [[8, 2, 3, 4, 6, 1, 5, 7], [7, 1, 2, 3, 4, 6, 5, 8]], "shuffle": 1}
	Save.data["credits"] = 20
	await _go("mini_games")
	menu = get_tree().current_scene
	check(not _button(menu, "Sabacc War").disabled, "Episode I Chapter 1 unlocks the standalone table")
	Sabacc.settings["music_enabled"] = true
	Music._apply()
	var old_track := Music.current_path
	await _click(_button(menu, "Sabacc War"))
	var table := get_tree().current_scene
	check(table.bg._location == "saga_cantina" and Music.current_path.ends_with("cantina_band.mp3") and Music.player.playing,
		"War switches to the Cantina background and soundtrack")
	await _click(table._deal)
	check(table._dealing and table._deal.disabled and table._back.disabled, "The hand settles once while cards animate")
	await _wait(5.0)
	check(table._remaining == [3, 3] and table._burned.size() == 6 and Progression.credits() == 30
		and table._amount.text == "30" and table._delta.text == "+10", "Face clash plays three cards down, reveals the fourth, shrinks the decks, and awards ten")
	await _shot("sabacc-war-portrait")
	await _size(1280, 720)
	await _shot("sabacc-war-landscape")
	var deck_top: TextureRect = table._decks[0][2]
	await _drag(deck_top.get_global_rect().get_center(), table.body.global_position + table._face_centers[0])
	await _wait(0.40)
	check(table._waiting_flip and table._cards[0].visible, "Dragging from the player deck deals face down and waits for a tap")
	await _click(table._cards[0])
	await _wait(1.0)
	check(table._remaining == [2, 2] and Progression.credits() == 20 and table._amount.text == "20" and table._delta.text == "-10",
		"The next hand uses the same decks and subtracts the lost stake")
	await _click(table._back)
	check(Music.current_path == old_track and get_tree().current_scene.scene_file_path.ends_with("mini_games.tscn"),
		"Leaving standalone War returns to Mini Games and resumes the soundtrack")

	await _size(540, 960)
	var chapter := CardDB.chapter("ep4_ch1_tatooine")
	var run := CampaignRun.start(chapter, "SEC_015", 82)
	for seed_value in 100:
		run = CampaignRun.start(chapter, "SEC_015", seed_value)
		if "cantina_war" in CampaignRun.route(chapter, run)["map"]["edges"]:
			break
	run["current"] = "cantina_duel"
	run["credits"] = 30
	run["war_table"] = {"decks": [[6, 1], [4, 2]]}
	Save.set_run(run)
	await _go("chapter", {"chapter_id": chapter["id"]})
	var chapter_map := get_tree().current_scene
	await _click(chapter_map._nodes["cantina_war"])
	table = get_tree().current_scene
	await _click(table._deal)
	await _wait(1.0)
	check(int(Save.run()["credits"]) == 40 and Progression.credits() == 20 and table._amount.text == "40",
		"The campaign table pays into the run wallet only")
	await _click(table._back)
	check(Save.run()["current"] == "cantina_war" and get_tree().current_scene.scene_file_path.ends_with("chapter_map.tscn"),
		"Leaving the Tatooine table completes the node and returns to the chapter map")
	for answer in ["Yes", "No"]:
		chapter_map = get_tree().current_scene
		var choice_node := CampaignRun.node_by_id(chapter, "black_sphere")
		if not chapter_map._nodes.has("black_sphere"):
			chapter_map._nodes["black_sphere"] = preload("res://ui/screens/chapter_map.gd").NodeButton.new()
			chapter_map.body.add_child(chapter_map._nodes["black_sphere"])
		chapter_map._nodes["black_sphere"].state = "available"
		chapter_map._open_node(choice_node)
		await _wait(0.85)
		var card := chapter_map._panel.find_child(answer + "Card", true, false) as TextureButton
		check(card != null and not card.disabled, "%s artwork is an active card" % answer)
		if card:
			if answer == "Yes":
				await _shot("sabacc-event-choices")
				await _size(1280, 720)
				await _shot("sabacc-event-choices-landscape")
			await _click(card)
			await _wait(1.4)
			check(Save.run()["current"] == "black_sphere", "%s card resolves the event by pointer input" % answer)


func _test_campaign_update() -> void:
	await _size(570, 1080)
	Sabacc.settings["music_volume"] = 0.5
	Sabacc.settings["music_enabled"] = true
	Music._apply()
	var quiet := Music.player.volume_db
	var track := Music.current_path
	await _go("res://ui/screens/boot.tscn")
	var boot := get_tree().current_scene
	check(boot.scene_file_path.ends_with("boot.tscn") and Music.player.volume_db >= quiet + 15.0
		and Music.current_path == track, "The logo boosts the current track without restarting it")
	await _click(boot)
	await _wait(0.8)
	check(get_tree().current_scene.scene_file_path.ends_with("welcome.tscn") and is_equal_approx(Music.player.volume_db, quiet),
		"Skipping the logo fades to the regular menu level")
	Sabacc.settings["music_enabled"] = false
	Music._apply()
	check(not Music.player.playing, "The startup boost respects the music setting")
	check(SpotlightFlow.start("sor_luke").is_empty(), "An unowned Spotlight deck cannot start a run")
	check(Progression.claim_starting_set("SOR"), "Selecting Spark of Rebellion grants the Spotlight pair")

	var chapter := CardDB.chapter("ep4_ch1_tatooine")
	var boss: Dictionary = chapter["nodes"].filter(func(node): return node["type"] == "boss")[0]
	var on_route: Array = chapter["map"]["edges"].keys().filter(func(id): return boss["id"] in chapter["map"]["edges"][id])
	var rewards := {}
	for size in [8, 12]:
		for seed_value in range(40):
			var saga := CampaignRun.start(chapter, chapter["leader_options"][0], seed_value)
			if CampaignRun.completion_pack_size(saga, chapter) != size:
				continue
			saga["current"] = on_route[0]
			Save.set_run(saga)
			var battle := Match.new()
			battle.setup(CardDB.lib, CampaignRun.match_config(saga, chapter, boss, {}))
			battle.set_winner(0, "test")
			var result := CampaignFlow.on_match_end({"chapter_id": chapter["id"], "node_id": boss["id"]}, battle)
			var scenes: Array = result.get("backgrounds", [])
			check(scenes.size() == (2 if size == 8 else 1) and ("saga_docking_94_icon" in scenes) == (size == 8)
				and scenes.all(func(id): return Cosmetics.unlocked("background:" + id)),
				"Each Tatooine victory earns a different scene and only the first grants the Docking Bay icon")
			rewards[size] = result.get("pack", "")
			break
	for size in [8, 12]:
		var id: String = rewards.get(size, "")
		var packs := Progression.packs().filter(func(pack): return pack["id"] == id)
		check(packs.size() == 1 and packs[0]["cards"].size() == size and packs[0]["cards"].all(func(cid):
			return CardDB.card(cid).get("set") == packs[0]["set"]), "Saga granted a %d-card pack from a single set" % size)
		if packs.size() == 1:
			Progression.tear(id)
			for index in packs[0]["cards"].size():
				Progression.reveal(id, index)
			check(packs[0]["revealed"].size() == size, "The %d-card Saga pack reveals every slot" % size)

	var run := SpotlightFlow.start("sor_luke")
	check(not run.is_empty() and SpotlightRun.deck_size(run) == 20, "An owned Spotlight starts with an abbreviated deck")
	var first: String = SpotlightRun.available_nodes(run)[0]
	SpotlightRun.on_battle_end(run, first, true, 0, CardDB.lib)
	run["pending_reward"] = {}
	SpotlightFlow.save_run(run)
	await _go("spotlight_run", {"deck_id": run["deck_id"]})
	var screen := get_tree().current_scene
	var shops := SpotlightRun.available_nodes(run).filter(func(id): return SpotlightRun.node(run, id)["type"] == "shop")
	check(not shops.is_empty(), "The opening battle unlocks a market route")
	if shops.is_empty():
		return
	await _click(screen._nodes[shops[0]])
	var trade := _button(screen, "Trade one card")
	check(trade != null and not trade.disabled, "The generated market offers a card exchange")
	if not trade or trade.disabled:
		return
	var count := SpotlightRun.deck_size(run)
	await _click(trade)
	await _click(_find_card(screen))
	await _click(_find_card(screen))
	check(shops[0] in run.get("shop_traded", []) and SpotlightRun.deck_size(run) == count,
		"A portrait market trade swaps cards without changing deck size")


func _test_trigger_picker() -> void:
	await _size(570, 1280)
	var options := range(18)
	var labels := options.map(func(i): return "Ability %02d · Choose a friendly unit and give it an Experience token" % i)
	var choice := ChoicePanel.open(self, Match.new(), {"kind": "option", "op": "_ordered_triggers", "min": 1,
		"prompt": "Choose the next attack ability to resolve", "options": options, "labels": labels})
	var submitted: Array = []
	choice.submitted.connect(func(selection): submitted.assign(selection))
	await _wait(0.3)
	var scroll: ScrollContainer = choice.find_children("*", "ScrollContainer", true, false).front()
	var final_button := _button(choice, "Ability 17")
	check(scroll.get_v_scroll_bar().visible and final_button != null, "Long trigger lists can scroll on portrait layouts")
	if final_button:
		scroll.ensure_control_visible(final_button)
		await _wait(0.3)
		await _click(final_button)
	check(submitted == [17], "A player can scroll and select the last trigger")


func _test_tie_advanced_target_picker() -> void:
	for scenario in ["portrait", "landscape", "no_target"]:
		var portrait: bool = scenario != "landscape"
		var no_target: bool = scenario == "no_target"
		await _size(570 if portrait else 1280, 1280 if portrait else 720)
		var rules := RuleSet.premier()
		rules.aspect_penalties = false
		rules.allow_mulligan = false
		rules.starting_hand = 0
		rules.starting_resources = 0
		var preplaced: Array = [{"id": "SOR_237"}]
		if not no_target:
			preplaced.append_array([{"id": "SOR_128", "ready": false}, {"id": "SOR_225"}])
		await _go("match", {"cfg": {"rules": rules, "seed": 31, "first": 0, "players": [
			{"leader": "SOR_010", "base": "SOR_023", "ai": false, "bonus_hand": ["SOR_231"],
				"deck": ["SOR_225", "SOR_225", "SOR_225", "SOR_225"], "extra_resources": 4,
				"preplaced": preplaced},
			{"leader": "SOR_005", "base": "SOR_029", "ai": false},
		]}})
		var screen := get_tree().current_scene
		var battle: Match = screen.m
		var tie: CardInst = battle.players[0].hand[0]
		for _i in 18:
			if not screen.busy and screen.hand.cards.has(tie.uid):
				break
			await _wait(0.1)
		check(not screen.busy and screen.hand.cards.has(tie.uid), "TIE Advanced match can accept input")
		if screen.busy or not screen.hand.cards.has(tie.uid):
			continue
		var card: CardView = screen.hand.cards[tie.uid]
		await _wait(0.45)
		await _drag_hand_card_to_board(card)
		if no_target:
			var notice: Label
			for _i in 18:
				notice = screen.fx_layer.find_children("*", "Label", true, false).filter(func(label):
					return label.text == "TIE ADVANCED: NO OTHER FRIENDLY IMPERIAL UNIT IN PLAY.").front() if screen.fx_layer.find_children("*", "Label", true, false).any(func(label):
					return label.text == "TIE ADVANCED: NO OTHER FRIENDLY IMPERIAL UNIT IN PLAY.") else null
				if notice:
					break
				await _wait(0.1)
			check(tie.in_play() and not screen.prompt_bar.visible and battle.pending.is_empty() and battle.active == 1,
				"With no eligible unit, TIE Advanced plays and the turn continues")
			check(notice != null, "The board explains why no Experience was granted")
			if notice and DisplayServer.get_name() != "headless":
				await _wait(0.35)
				await _shot("tie-advanced-no-eligible-imperial")
			continue
		for _i in 18:
			if screen.prompt_bar.visible:
				break
			await _wait(0.1)
		check(tie.in_play() and screen.prompt_bar.visible, "Dragging TIE Advanced onto the board opens its required target prompt")
		if not screen.prompt_bar.visible:
			continue
		var rebel: CardInst = battle.players[0].units[0]
		var ground: CardInst = battle.players[0].units[1]
		var space: CardInst = battle.players[0].units[2]
		check(screen.tokens[ground.uid].highlight == UnitToken.Hi.TARGET and screen.tokens[space.uid].highlight == UnitToken.Hi.TARGET
			and screen.tokens[rebel.uid].highlight == UnitToken.Hi.NONE, "Board highlights eligible Imperials in both arenas")
		if DisplayServer.get_name() != "headless":
			await _shot("tie-advanced-%s-targets" % ("portrait" if portrait else "landscape"))
		await _click(screen.tokens[rebel.uid], Vector2(0.5, 0.35))
		check(screen.prompt_bar.visible and rebel.upgrades.is_empty(), "Tapping a non-Imperial leaves the prompt open")
		var target := ground if portrait else space
		await _click(screen.tokens[target.uid], Vector2(0.5, 0.35))
		check(battle.pending.is_empty() and not screen.prompt_bar.visible and target.upgrades.size() == 2,
			"Selecting a highlighted Imperial gives it both Experience tokens")


func _drag_hand_card_to_board(card: CardView) -> void:
	var start := card.get_global_transform_with_canvas() * (card.size * Vector2(0.5, 0.22))
	var finish := get_viewport().get_visible_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = finish
	motion.global_position = finish
	motion.relative = finish - start
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = finish
	release.global_position = finish
	get_viewport().push_input(release, true)
