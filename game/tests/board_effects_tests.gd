extends "res://tests/cinematic_tests.gd"


func capture_effect(name: String, token: UnitToken) -> void:
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.save_png(out.path_join(name + ".png"))
	var screen_center := token.get_global_transform_with_canvas() * Vector2(UnitToken.SIZE.x / 2, UnitToken.HEX_H / 2)
	var viewport_scale := Vector2(shot.get_size()) / get_viewport().get_visible_rect().size
	var center := Vector2i(screen_center * viewport_scale)
	var detail := shot.get_region(Rect2i(center - Vector2i(105, 91), Vector2i(210, 180)))
	detail.save_png(out.path_join(name + "-detail.png"))


func _run() -> void:
	Save.data = Save.default_data()
	Sabacc.settings["perf_mode"] = false
	Sabacc.settings["anim_speed"] = 1.0
	await _size(1920, 1080)
	await _go("match")
	var screen := get_tree().current_scene
	var battle: Match = screen.m
	for i in 24:
		_resolve_setup(screen)
		await _wait(0.35)
		if battle.phase == "action" and battle.pending.is_empty() and not screen.busy:
			break
	check(battle.phase == "action" and battle.pending.is_empty() and not screen.busy, "match setup complete")
	if failures:
		get_tree().quit(1)
		return
	battle.players[1].is_ai = false
	for card_id in ["TWI_015", "TWI_034", "SEC_187", "TS26_050", "HMW_008", "HMW_159"]:
		var grievous := battle._new_inst(card_id, 0)
		var style := AttackStyle.of(grievous)
		check(style["style"] == "saber" and style["palette"] == "green", card_id + " uses a green slash without the Force trait")
	for existing in battle.all_units():
		battle.players[existing.controller].units.erase(existing)
		existing.zone = "removed"

	var unit := battle._new_inst("SOR_095", 0)
	var ally := battle._new_inst("SOR_237", 0)
	var third := battle._new_inst("SOR_128", 0)
	battle._put_in_play(unit, "ground", false)
	battle._put_in_play(ally, "space", false)
	unit.mods.append({"kw": "sentinel"})
	unit.mods.append({"kw": "coordinate"})
	battle.attach_token(unit, "shield")
	battle.attach_token(unit, "shield")
	battle.take_events()
	screen._sync()
	await _wait(0.3)
	var token: UnitToken = screen.tokens[unit.uid]
	var layers := token.effects
	check(layers._opacity["sentinel"] > 0.9, "granted Sentinel visible")
	check(layers._opacity["shield"] > 0.9, "attached Shields visible")
	check(layers._opacity["coordinate"] == 0.0, "Coordinate off with two units")
	battle._put_in_play(third, "ground", false)
	battle.take_events()
	screen._sync()
	await _wait(0.3)
	check(layers._opacity["coordinate"] > 0.9, "Coordinate active across arenas")
	await capture_effect("01-stacked-keywords", token)

	unit.damage = 2
	battle.heal(unit, 1)
	await screen._drain()
	await _wait(0.37)
	check(layers._heal_age < UnitEffects.PLAY_TIME and layers._opacity["shield"] > 0.9 and layers._opacity["coordinate"] > 0.9, "healing stacks with board status")
	await capture_effect("02-healing-with-keywords", token)
	await _wait(0.5)
	check(layers._heal_age >= UnitEffects.PLAY_TIME, "mist finishes")

	check(battle.deal_damage(unit, 2, null) == 0 and unit.shield_count() == 1, "damage spends one Shield")
	screen._drain()
	await _wait(0.54)
	check(layers._break_age < UnitEffects.PLAY_TIME and layers._opacity["shield"] == 0.0, "shatter replaces the struck bubble")
	check(layers._opacity["coordinate"] > 0.9 and layers._opacity["sentinel"] > 0.9, "other keywords stay visible during shatter")
	await capture_effect("03-shield-break", token)
	await _wait(0.55)
	check(layers._opacity["shield"] > 0.9, "remaining Shield returns")

	battle.defeat(unit.upgrades[0])
	await screen._drain()
	await _wait(0.35)
	check(layers._opacity["shield"] == 0.0, "last Shield removed by an effect")
	battle.defeat(third)
	await screen._drain()
	screen._sync()
	await _wait(0.4)
	check(unit.has_kw("coordinate") and layers._opacity["coordinate"] == 0.0, "Coordinate fades when the threshold is lost")
	check(layers._opacity["sentinel"] > 0.9, "Sentinel remains after Coordinate deactivates")
	unit.mods.clear()
	screen._sync()
	await _wait(0.3)
	check(layers._opacity["sentinel"] == 0.0, "removed Sentinel fades")
	await capture_effect("04-effects-cleared", token)

	var attacker := battle._new_inst("SHD_172", 0)
	var defender := battle._new_inst("SOR_095", 1)
	battle._put_in_play(attacker, "ground", false)
	battle._put_in_play(defender, "ground", false)
	battle.take_events()
	screen._sync()
	await _wait(0.4)
	battle.active = 0
	var enemy_base: CardInst = battle.players[1].base
	var previous_damage := enemy_base.damage
	check(battle.do_action({"a": "attack", "uid": attacker.uid, "target": defender.uid}), "Overwhelm attack resolves")
	check(enemy_base.damage == previous_damage + 7, "base takes only the excess damage")
	var attack_events := battle.events.filter(func(event): return event["t"] in ["attack", "overwhelm"])
	check(attack_events.size() == 2 and attack_events[0]["target"] == defender.uid and attack_events[1]["target"] == enemy_base.uid, "one unit attack and one base animation")
	var attacker_token: UnitToken = screen.tokens[attacker.uid]
	var base_center: Vector2 = screen._card_center(enemy_base)
	screen._drain()
	var reached_base := false
	for i in 180:
		await get_tree().process_frame
		if attacker_token.z_index == 20 and attacker_token.center_global().distance_to(base_center) < 75.0:
			reached_base = true
			await _shot("05-overwhelm-base")
			break
	check(reached_base, "the same attack animation reaches the base")
	await _wait(1.1)

	var next_attacker := battle._new_inst("SHD_172", 0)
	var shielded_defender := battle._new_inst("SOR_095", 1)
	battle._put_in_play(next_attacker, "ground", false)
	battle._put_in_play(shielded_defender, "ground", false)
	battle.attach_token(shielded_defender, "shield")
	battle.take_events()
	battle.active = 0
	previous_damage = enemy_base.damage
	check(battle.do_action({"a": "attack", "uid": next_attacker.uid, "target": shielded_defender.uid}), "attack on Shield resolves")
	check(enemy_base.damage == previous_damage and not battle.events.any(func(event): return event["t"] == "overwhelm"), "a Shield prevents the replay and base damage")

	await screen._drain()
	var tie := battle._new_inst("SOR_231", 0)
	battle._put_in_play(tie, "space", false)
	battle.take_events()
	screen._sync()
	await _wait(0.4)
	var shots: Array[String] = []
	var impacts: Array[Vector2] = []
	var observe := func(node):
		if node is CombatSprite:
			if node.sheet_name.ends_with(" HIT"):
				(func(): impacts.append(node.global_position)).call_deferred()
			else:
				shots.append(node.sheet_name)
	screen.fx_layer.child_entered_tree.connect(observe)
	screen._anim_attack(tie, enemy_base)
	for frame in 120:
		await get_tree().process_frame
		if not shots.is_empty() and impacts.is_empty():
			await _wait(0.10)
			await _shot("06-twin-bolt-flight")
			break
	for frame in 120:
		await get_tree().process_frame
		if impacts.size() >= 2:
			await _wait(0.09)
			await _shot("07-twin-bolt-impact")
			break
	await _wait(0.85)
	screen.fx_layer.child_entered_tree.disconnect(observe)
	check(shots.size() in [2, 4, 6] and impacts.size() == shots.size(), "a vehicle fires one to three pairs with one impact per bolt")
	if impacts.size() >= 2:
		check(not impacts[0].is_equal_approx(impacts[1])
			and ((impacts[0] + impacts[1]) * 0.5).distance_to(base_center) < 1.0,
			"the two bolt impacts land on opposite sides of the base center")
	var swordsman := battle._new_inst("TWI_034", 0)
	battle._put_in_play(swordsman, "ground", false)
	battle.take_events()
	screen._sync()
	await _wait(0.35)
	screen._anim_attack(swordsman, enemy_base)
	await _wait(0.36)
	var slashes: Array = screen.fx_layer.get_children().filter(func(child):
		return child is CombatSprite and child.sheet_name.begins_with("Slash Green "))
	check(slashes.size() == 1 and slashes[0].global_position.distance_to(base_center) < 1.0,
		"Grievous slash plays on the target after the lunge")
	await _shot("08-grievous-slash")
	await _wait(0.55)
	await _size(570, 1280)
	var neutral := battle._new_inst("ASH_172", 0)
	battle._put_in_play(neutral, "space", false)
	battle.take_events()
	screen._sync()
	await _wait(0.4)
	shots.clear()
	impacts.clear()
	screen.fx_layer.child_entered_tree.connect(observe)
	screen._anim_attack(neutral, enemy_base)
	await _wait(0.30)
	await _shot("09-yellow-vehicle-bolts")
	await _wait(0.30)
	await _shot("10-yellow-vehicle-impact")
	await _wait(0.85)
	screen.fx_layer.child_entered_tree.disconnect(observe)
	check(shots.size() in [2, 4, 6] and shots.all(func(name): return name == "Bolt Yellow")
		and impacts.size() == shots.size(), "A neutral vehicle uses yellow sheets and pairs every bolt with a hit")

	print("BOARD EFFECTS: %d checks, %d failed" % [checks, failures])
	if failures:
		get_tree().quit(1)
