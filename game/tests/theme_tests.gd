extends "res://tests/shots.gd"
## Visual and behavioral checks; use an isolated APPDATA to protect user saves.

var failures := 0
var passes := 0


func check(ok: bool, message: String) -> void:
	if ok:
		passes += 1
	else:
		failures += 1
		printerr("FAIL: ", message)


func _run() -> void:
	var expected: Array[String] = ["aggression", "command", "villainy"]
	check(Appearance.aspects_for([{"aspects": ["aggression", "villainy"]}, {"aspects": ["command", "aggression"]}]) == expected, "unique combat aspects plus alignment")
	check(Appearance.aspects_for([{"aspects": ["heroism", "vigilance", "invalid"]}]) == ["vigilance", "heroism"], "unknown aspects ignored")
	check(Appearance.aspects_for([]).is_empty(), "empty deck uses theme accent")
	Appearance.set_deck("SOR_017", "HMW_019", ["SOR_095"])
	check(Appearance.deck_aspects.size() <= 3, "at most three deck accents")
	await _go("menu")
	var primary_button: SabaccButton = get_tree().current_scene._buttons.get_child(0)
	var before: Color = primary_button.get_theme_stylebox("normal").border_color
	Appearance.set_deck("SOR_010", "HMW_019")
	check(Appearance.deck_aspects == ["aggression", "vigilance", "villainy"], "match palette comes from selected leader and base")
	check(primary_button.get_theme_stylebox("normal").border_color != before, "existing button retints on deck change")
	Appearance.set_deck("SOR_017", "HMW_019")
	for id in Appearance.PRESETS:
		Sabacc.set_setting("theme", id)
		await _size(1280, 720)
		await _go("menu")
		var menu := get_tree().current_scene
		check(menu._buttons.position.y >= menu._title_box.position.y + menu._title_box.get_combined_minimum_size().y, "menu title avoids buttons " + id)
		await _shot("theme_" + id)
		check(Appearance.preset()["name"] == Appearance.PRESETS[id]["name"], "selected preset " + id)
	Sabacc.set_setting("theme", "datapad_imperial")
	Save.load_save()
	check(Save.data["settings"]["theme"] == "datapad_imperial", "theme persists to save")
	await _size(540, 960)
	await _go("settings")
	await _shot("theme_settings_portrait")
	var picker := get_tree().current_scene.find_child("ThemeSelector", true, false) as OptionButton
	check(picker != null and picker.item_count == 10, "all themes exposed in Options")
	picker.item_selected.emit(Appearance.PRESETS.keys().find("planet_tatooine"))
	check(Sabacc.settings["theme"] == "planet_tatooine", "selector changes the actual setting")
	# A complete legacy save should migrate, including decks and settings.
	var original := Save.data.duplicate(true)
	var legacy := Save.default_data()
	legacy["stats"]["matches"] = 42
	legacy["settings"]["theme"] = "datapad_outer_rim"
	var file := FileAccess.open(Save.LEGACY_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	DirAccess.remove_absolute(Save.PATH)
	Save.load_save()
	check(Save.data["stats"]["matches"] == 42 and FileAccess.file_exists(Save.PATH), "legacy save migrates without losing progress")
	Save.data = original
	Save.write()
	Sabacc.set_setting("theme", "datapad_republic")
	for sz in [[540, 960, "portrait"], [1280, 720, "landscape"], [480, 1040, "tall"]]:
		await _size(sz[0], sz[1])
		await _go("collection")
		var overlay := InspectOverlay.open(get_tree().current_scene, "SOR_095", Rect2(50, 100, 100, 140))
		await _wait(0.7)
		check(overlay._panels.size() == 4, "four radial dossiers " + sz[2])
		var card_rect := Rect2(overlay._card.position, overlay._card.base_size() * overlay._card.scale)
		check(card_rect.get_center().distance_to(overlay.get_viewport_rect().size / 2) < 2, "card centered " + sz[2])
		for panel in overlay._panels:
			check(not panel.get_rect().intersects(card_rect), "dossier avoids card " + sz[2])
		await _shot("inspect_radial_" + sz[2])
		overlay.close_overlay()
		await _wait(0.5)
		check(not is_instance_valid(overlay), "inspector closes " + sz[2])
	await _size(1280, 720)
	await _go("collection")
	var leader := InspectOverlay.open(get_tree().current_scene, "SOR_017")
	await _wait(0.5)
	leader._flip()
	await _wait(0.6)
	check(leader._back and leader._card.show_back_side, "leader flip updates card and dossiers")
	await _shot("inspect_leader_flipped")
	leader.close_overlay()
	await _wait(0.4)
	var detailed := InspectOverlay.open(get_tree().current_scene, "LOF_190")
	await _wait(0.5)
	check(detailed._panels[2].get_child(0).get_child(0).get_child_count() > 1, "keyword dossier contains explanations")
	await _shot("inspect_keywords")
	detailed.close_overlay()
	await _wait(0.4)
	for kind in ["base", "event", "upgrade"]:
		for id in CardDB.lib.cards:
			if CardDB.card(id).get("type") != kind:
				continue
			var typed := InspectOverlay.open(get_tree().current_scene, id)
			await _wait(0.4)
			check(typed._panels.size() == 4, "inspects " + kind)
			typed.close_overlay()
			await _wait(0.35)
			break
	Sabacc.set_setting("perf_mode", true)
	var simple := InspectOverlay.open(get_tree().current_scene, "SOR_095")
	await _wait(0.5)
	check(simple._blur == null, "performance mode avoids screen blur shader")
	await _shot("inspect_performance")
	simple.close_overlay()
	await _wait(0.4)
	Sabacc.set_setting("perf_mode", false)
	var random := RandomNumberGenerator.new()
	random.seed = 12
	await _go("match", {"cfg": QuickMatch.make_config("SOR_010", "HMW_019", 0, "tempo", random)})
	await _wait(2)
	await _shot("theme_match_datapad")
	check(Appearance.deck_aspects.size() >= 1, "match installs human deck palette")
	print("THEMES: %d passed, %d failed" % [passes, failures])
	if failures:
		get_tree().quit(1)
