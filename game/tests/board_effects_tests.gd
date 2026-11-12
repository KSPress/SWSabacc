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
	for existing in battle.all_units():
		battle.players[existing.controller].units.erase(existing)
		existing.zone = "removed"

	var unit := battle._new_inst("SOR_095", 0)
	var ally := battle._new_inst("SOR_237", 0)
	var third := battle._new_inst("SOR_225", 0)
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

	print("BOARD EFFECTS: %d checks, %d failed" % [checks, failures])
	if failures:
		get_tree().quit(1)
