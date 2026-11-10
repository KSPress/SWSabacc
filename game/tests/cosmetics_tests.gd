extends "res://tests/shots.gd"

var checks := 0
var failures := 0


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", text)


func _run() -> void:
	Save.data = Save.default_data()
	Save.write()
	check(Cosmetics.catalog["emblems"].size() == 25, "25 supplied emblems")
	check(Cosmetics.catalog["cardbacks"].size() == 37, "37 cropped card backs")
	check(Cosmetics.background() == "datapad", "default datapad")
	check(not Cosmetics.equip("cardback", "vader"), "locked cardback cannot equip")
	var reward := Cosmetics.record_match(true, "win_1")
	check(not reward.is_empty() and Cosmetics.unlocked(reward["key"]), "victory unlocks an unearned item")
	check(Cosmetics.state()["earned"].size() == 4, "one item per win")
	check(Cosmetics.record_match(true, "win_1").is_empty(), "duplicate victory ignored")
	check(Save.data["stats"]["wins"] == 1, "duplicate does not increment wins")
	check(Cosmetics.record_match(false, "loss_1").is_empty(), "loss gives no cosmetic")
	var earned: Array = Cosmetics.state()["earned"].duplicate()
	Cosmetics.set_gm(true)
	check(Cosmetics.equip("emblem", "fett_crest"), "GM can equip locked emblem")
	check(Cosmetics.equip("background", "emblem"), "emblem background available with emblem")
	check(Cosmetics.equip("cardback", "vader"), "GM can equip cardback")
	check(Cosmetics.texture("cardback").get_size() == Vector2(500, 698), "normalized cardback aspect and resolution")
	Cosmetics.record_match(true, "gm_win")
	check(Cosmetics.state()["earned"] == earned, "GM does not alter earned account collection")
	Cosmetics.set_gm(false)
	check(Cosmetics.equipped("emblem") == "sabacc" and Cosmetics.equipped("cardback") == "default", "account loadout restored after GM")
	check(not Cosmetics.unlocked("cardback:vader") or "cardback:vader" in earned, "GM access removed")
	# Exhaust the real random pool: no duplicate unlocks and no empty rewards
	# until every known item has been earned.
	while Cosmetics.state()["earned"].size() < Cosmetics.all_items().size():
		var before: int = Cosmetics.state()["earned"].size()
		var item := Cosmetics.record_match(true, "earn_%d" % before)
		check(not item.is_empty() and Cosmetics.state()["earned"].size() == before + 1, "unique random reward")
	check(Cosmetics.record_match(true, "complete_collection").is_empty(), "completed pool does not duplicate rewards")
	Save.load_save()
	check(Cosmetics.state()["earned"].size() == Cosmetics.all_items().size(), "collection persisted")
	Cosmetics.equip("emblem", "fett_crest")
	Cosmetics.equip("background", "emblem")
	Cosmetics.equip("cardback", "mando")
	Appearance.begin_match([{"leader": "SOR_010", "base": "HMW_019"}, {"leader": "SOR_017", "base": "HMW_028"}])
	var friendly := Appearance.line_color()
	Appearance.set_acting_player(1)
	await _wait(1.4)
	check(Appearance.line_color() != friendly, "datapad fades to opponent colors")
	Appearance.set_acting_player(0)
	await _wait(1.4)
	check(Appearance.line_color().is_equal_approx(friendly), "datapad fades back to player colors")
	await _size(540, 960)
	await _go("customization")
	await _shot("profile_emblems_portrait")
	var screen := get_tree().current_scene
	screen._filter.select(1)
	screen._kind = "cardback"
	screen._populate()
	await _wait(0.5)
	await _shot("cardbacks_portrait")
	await _size(1280, 720)
	await _wait(0.5)
	await _shot("cardbacks_landscape")
	await _go("menu")
	await _shot("emblem_menu")
	# Use actual viewport input, not pressed.emit(), to catch overlapping controls.
	var position: Vector2 = get_tree().current_scene._profile_button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	await get_tree().process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		Input.parse_input_event(click)
		await get_tree().process_frame
	await _wait(0.8)
	check(get_tree().current_scene.get_script().resource_path.ends_with("customization.gd"), "real pointer reaches menu Profile button")
	await _go("settings")
	var gm := get_tree().current_scene.find_child("GMButton", true, false) as SabaccButton
	check(gm != null and gm.get_theme_stylebox("normal").border_color == Sabacc.C_EMPIRE, "GM button is red")
	gm.pressed.emit()
	check(Cosmetics.state()["gm"], "real settings GM toggle enables access")
	gm.pressed.emit()
	check(not Cosmetics.state()["gm"], "real settings toggle restores account")
	await _shot("settings_gm")
	var random := RandomNumberGenerator.new()
	random.seed = 18
	await _go("match", {"cfg": QuickMatch.make_config("SOR_010", "HMW_019", 0, "tempo", random)})
	await _wait(1)
	for i in 8:
		_resolve_setup(get_tree().current_scene)
		await _wait(0.35)
	await _shot("emblem_match")
	# Exercise the actual victory screen, including its repeat-call guard.
	Save.data = Save.default_data()
	var match_screen := get_tree().current_scene
	match_screen.m.winner = 0
	match_screen._game_over()
	check(Cosmetics.state()["earned"].size() == 4, "real victory screen awards a cosmetic")
	match_screen._game_over()
	check(Save.data["stats"]["wins"] == 1, "repeated victory screen cannot farm rewards")
	await _wait(0.5)
	await _shot("victory_reward")
	print("COSMETICS: %d checks, %d failed" % [checks, failures])
	if failures:
		get_tree().quit(1)
