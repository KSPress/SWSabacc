extends "res://tests/touch_scroll_tests.gd"
var heard: Array = []


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	Save.data = Save.default_data()
	Sabacc.settings["music_volume"] = 0.5
	Sabacc.settings["sfx_volume"] = 0.7
	Progression.ensure_account()
	Sfx.cue_played.connect(func(path): heard.append(path))
	check(Sfx.catalog.get("unused", []).is_empty(), "every supplied sound assigned")
	check(Sfx.catalog["music"].size() == 6, "six music tracks")
	var paths: Array = Sfx.catalog["music"].duplicate()
	for actor in Sfx.catalog["characters"].values():
		for clips in actor.values():
			paths.append_array(clips)
	for clips in Sfx.catalog["effects"].values():
		paths.append_array(clips)
	for path in paths:
		var stream = load(path)
		check(stream is AudioStream and stream.get_length() > 0, "decodable audio " + path.get_file())
	var luke := {"name": "Luke Skywalker", "type": "unit", "arena": "ground", "traits": ["force", "jedi"], "aspects": ["heroism"]}
	var villain := {"name": "Darth Vader", "type": "leader", "arena": "ground", "traits": ["force"], "aspects": ["villainy"]}
	check(Sfx.defeat_paths(luke, 0.049) == Sfx.catalog["effects"]["wilhelm"], "ground non-creature Wilhelm below 5 percent")
	check(Sfx.defeat_paths(luke, 0.05) == Sfx.character_paths(luke, "lose"), "5 percent boundary and LOSE on death")
	check(Sfx.character_paths(luke, "DIE") == Sfx.character_paths(luke, "LOSE"), "DIE and LOSE interchangeable")
	for traits in [["creature"], ["vehicle"]]:
		var unit := luke.duplicate(true)
		unit["traits"] = traits
		check(Sfx.defeat_paths(unit, 0.0) != Sfx.catalog["effects"]["wilhelm"], "no Wilhelm for " + str(traits))
		if "vehicle" in traits:
			check(Sfx.defeat_paths(unit, 0.049) == Sfx.catalog["effects"]["vehicle_easter_egg"], "vehicle Minecraft/Creeper 5 percent")
			check(Sfx.defeat_paths(unit, 0.05) != Sfx.catalog["effects"]["vehicle_easter_egg"], "vehicle rare explosion boundary")
	var space := luke.duplicate(true)
	space["arena"] = "space"
	check(Sfx.defeat_paths(space, 0.0) != Sfx.catalog["effects"]["wilhelm"], "space units excluded from Wilhelm")
	check(not Sfx.character_paths(villain, "action").is_empty(), "unlabeled character action clips")
	check(Sfx.character_key({"name": "Ben Kenobi"}) == "obi_wan kenobi", "Obi-Wan alias")
	var windu := {"name": "Mace Windu", "type": "leader", "traits": ["force", "jedi"]}
	Sfx.entered(windu)
	check(not Sfx.character_paths(windu, "played").is_empty() and heard.back() in Sfx.character_paths(windu, "played"),
		"Mace Windu leader deployment uses the same PLAYED clip as his unit cards")
	check(not Sfx.character_paths(windu, "lose").is_empty() and Sfx.character_paths(windu, "die") == Sfx.character_paths(windu, "lose"),
		"Mace Windu shares the LOSE clip for defeat and a leader loss")
	check(Sfx.shield_cue(false, 0.0499) == "shield_rare" and Sfx.shield_cue(false, 0.05) == "shield_gain",
		"Fortnite replaces Halo only below five percent")
	check(Sfx.shield_cue(true, 0.0) == "shield_break" and Sfx.shield_cue(true, 1.0) == "shield_break",
		"Shield breaks always use the Break cue")
	Sfx.shield_sound(true)
	check(heard.back() in Sfx.catalog["effects"]["shield_break"], "Shield break audio is playable")
	Sfx.entered(luke)
	check(heard.back() in Sfx.character_paths(luke, "played"), "PLAYED on entry")
	Sfx.entered({"name": "TIE Fighter"})
	check(heard.back() in Sfx.catalog["effects"]["tie_enter"], "TIE token entry")
	check(Sfx.attack_sound({"name": "TIE/ln Fighter"}, "ship") == "tie_shoot", "TIE shooting")
	Sfx.acted(villain)
	check(heard.back() in Sfx.character_paths(villain, "action"), "unlabeled on action")
	var winner := CardInst.new(1, "", villain)
	var loser := CardInst.new(2, "", luke)
	heard.clear()
	Sfx.result_cues(winner, loser, true)
	check(heard[0] in Sfx.catalog["effects"]["villain_win"] and heard[1] in Sfx.character_paths(luke, "lose"), "villain win and losing leader")
	heard.clear()
	Sfx.result_cues(loser, winner, true, ["heroism", "villainy"])
	check(heard[0] in Sfx.catalog["effects"]["hero_win"], "hero victory Cantina")
	check(Sfx.catalog["effects"]["villain_win"] == ["res://ip/audio/custom/imperial_march.mp3"],
		"Villainy victories use the supplied Imperial March")
	check(Sfx.character_paths(villain, "lose").all(func(path): return not path.contains("liar")),
		"Vader never uses the Anakin line")
	for winning_leader in [winner, loser]:
		var losing_leader := loser if winning_leader == winner else winner
		heard.clear()
		Sfx.result_cues(winning_leader, losing_leader, false)
		check(heard.size() == 1 and heard[0] in Sfx.character_paths(losing_leader.data, "lose"), "player defeat has only the losing leader cue")
	Sabacc.set_setting("music_enabled", true)
	var tracks: Array = [Music.current_path]
	for i in 5:
		Music._next_track()
		tracks.append(Music.current_path)
	var unique := {}
	for path in tracks:
		unique[path] = true
	check(unique.size() == 6, "shuffle plays every track before repeating")
	var last := Music.current_path
	Music._next_track()
	check(Music.current_path != last, "no repeat at shuffle boundary")
	check(Music.player.playing and Music.player.volume_db < -24, "music plays softly")
	Sabacc.set_setting("music_enabled", false)
	check(not Music.player.playing, "music toggle stops playback")
	Sabacc.set_setting("music_volume", 0.0)
	Sabacc.set_setting("music_enabled", true)
	check(not Music.player.playing, "zero volume stays silent")
	Sabacc.set_setting("music_enabled", false)
	await _size(540, 960)
	await _go("settings")
	var settings := get_tree().current_scene
	var slider: HSlider = settings._gm
	check(slider.custom_minimum_size.y >= 76, "large GM slider")
	var earned: Array = Cosmetics.state()["earned"].duplicate()
	var at := slider.get_global_rect().position + Vector2(28, slider.size.y / 2)
	await _drag(at, Vector2(slider.size.x - 56, 0))
	check(Cosmetics.state()["gm"], "finger drag right enables GM")
	if only == "visuals":
		await _shot("settings_gm")
	check(Cosmetics.state()["earned"] == earned, "GM preserves earned collection")
	at = slider.get_global_rect().end - Vector2(28, slider.size.y / 2)
	await _drag(at, Vector2(-slider.size.x + 56, 0))
	check(not Cosmetics.state()["gm"], "finger drag left restores progression")
	await _go("customization")
	var gallery := get_tree().current_scene
	var locked := 0
	for tile in gallery._grid.get_children():
		var button: Button = tile.get_child(tile.get_child_count() - 1)
		if button.disabled:
			locked += 1
			check(tile.get_child(0).material != null, "locked preview greyscale")
	check(locked > 0 and locked < gallery._grid.get_child_count(), "earned and locked items both displayed")
	if only == "visuals":
		await _shot("gallery_locked_portrait")
		gallery._kind = "background"
		gallery._populate()
		await _wait(0.5)
		await _shot("backgrounds_portrait")
	for dimensions in [[540, 960], [1280, 720]]:
		await _size(dimensions[0], dimensions[1])
		await _go("menu")
		var scene := get_tree().current_scene
		check(scene._buttons.get_child_count() == 8, "eight menu entries")
		check(scene._title_box.get_node("Logo").texture == Art.ui_texture("sabacc_title"), "custom title artwork")
		if only == "visuals":
			await _shot("menu_%dx%d" % dimensions)
		await _click(_button(scene, "Customization"))
		check(get_tree().current_scene.scene_file_path.ends_with("customization.tscn"), "menu customization pointer navigation")
	print("PRESENTATION: %d checks, %d failed" % [checks, failures])
	winner = null
	loser = null
	if failures:
		get_tree().quit(1)
		return
	await _go("menu")
	print("EXIT: clicking native Exit button")
	await _click(_button(get_tree().current_scene, "Exit"))
	printerr("FAIL: Exit did not terminate application")
	get_tree().quit(1)
