extends "res://tests/shots.gd"
var checks := 0
var failures := 0
var layout_issues: Array = []
var sizes := [[360, 640], [540, 1200], [768, 1024], [1024, 768], [1280, 720], [1920, 1080], [2560, 1080], [960, 540]]


func _go(screen: String, parameters := {}) -> void:
	Router.go(screen, parameters)
	await _wait(0.65)


func _shot(label: String) -> void:
	if only == "bounds":
		await get_tree().process_frame
		return
	await super._shot(label)


func _size(w: int, h: int) -> void:
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.min_size = Vector2i.ZERO
	get_tree().root.size = Vector2i(w, h)
	await _wait(0.7)
	# Windows can coalesce a resize with the orientation's content-scale change.
	if get_tree().root.size != Vector2i(w, h):
		get_tree().root.size = Vector2i(w, h)
		await _wait(0.5)
	check(get_tree().root.size == Vector2i(w, h), "actual window ratio %dx%d" % [w, h])


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", description)


func _run() -> void:
	Save.data = Save.default_data()
	Sabacc.set_setting("perf_mode", false)
	Progression.ensure_account()
	check(Cosmetics.palettes.size() == 25, "all 25 emblem palettes present")
	Cosmetics.set_gm(true)
	Cosmetics.equip("background", "emblem")
	for id in Cosmetics.palettes:
		Cosmetics.equip("emblem", id)
		var expected := Cosmetics.emblem_color(id)
		check(Appearance.backdrop_color().is_equal_approx(expected), "matching traces " + id)
		check(Appearance.preset()["base"].is_equal_approx(expected.darkened(0.95)), "matching base wash " + id)
	Cosmetics.equip("emblem", "sith_eternal")
	await _go("menu")
	var badge: ProfileBadge = get_tree().current_scene.bg._datapad._badge
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(20, 20)
	badge._input(touch)
	await _wait(0.3)
	check(badge._lean.length() > 0.1, "hologram follows finger position")
	var flicker: float = badge._flicker
	await _wait(0.23)
	check(not is_equal_approx(flicker, badge._flicker), "noise-driven irregular transmission")
	await _shot("emblem_red")
	Cosmetics.equip("emblem", "fett_crest")
	await _wait(0.3)
	await _shot("emblem_fett")
	Cosmetics.equip("background", "datapad")
	Appearance.begin_match([{"leader": "SOR_010", "base": "HMW_019"}, {"leader": "SOR_017", "base": "HMW_028"}])
	var friendly := Appearance.line_color()
	Appearance.set_acting_player(1)
	await _wait(0.2)
	check(not Appearance.line_color().is_equal_approx(friendly), "opponent fade visibly starts within 200 ms")
	await _wait(0.35)
	check(Appearance.line_color().is_equal_approx(Appearance._aspect_color(Appearance._enemy[0])), "opponent fade reaches enemy aspect")
	Appearance.set_acting_player(0)
	await _wait(0.55)
	check(Appearance.line_color().is_equal_approx(friendly), "friendly palette restored")
	Appearance.end_match()
	Cosmetics.set_gm(false)
	var random := RandomNumberGenerator.new()
	random.seed = 77
	var emblems := 0
	var backgrounds := 0
	for i in 2000:
		var reward := Progression.roll_cosmetic(random)
		if reward.get("kind") == "emblem":
			emblems += 1
		elif reward.get("kind") == "background":
			backgrounds += 1
	check(emblems > 190 and emblems < 320 and backgrounds > 60 and backgrounds < 140, "seeded rare cosmetic distribution")
	var pack_id := Progression.grant("Polish QA", "polish_test")
	var pack: Dictionary = Progression.packs()[0]
	pack["bonus"] = {"key": "emblem:sith_eternal", "id": "sith_eternal", "kind": "emblem", "name": "Sith Eternal", "rarity": "Rare"}
	pack["bonus_revealed"] = false
	check(not Progression.reveal_bonus(pack_id), "sealed cosmetic cannot reveal")
	Progression.tear(pack_id)
	check(Progression.reveal_bonus(pack_id) and Cosmetics.unlocked("emblem:sith_eternal"), "rare emblem adds to collection")
	check(not Progression.reveal_bonus(pack_id), "bonus cannot reveal twice")
	Save.load_save()
	check(Progression.packs()[0]["bonus_revealed"] and Cosmetics.unlocked("emblem:sith_eternal"), "bonus and ownership persist")
	pack = Progression.packs()[0]
	pack["bonus"] = {"key": "background:dathomir", "id": "dathomir", "kind": "background", "name": "Dathomir scene", "rarity": "Legendary"}
	pack["bonus_revealed"] = false
	pack["torn"] = false
	Save.write()
	await _size(1280, 720)
	await _go("packs")
	await _shot("pack_foil")
	var screen := get_tree().current_scene
	screen._rip()
	await _wait(0.4)
	await _shot("pack_breach")
	await _wait(1.3)
	check(screen._slots.size() == 11, "ten cards plus cosmetic bonus")
	await _shot("pack_fan")
	check(not Progression.finish(pack_id), "unrevealed bonus prevents collection discard")
	screen._flip(screen._slots[10])
	await _wait(0.6)
	check(Cosmetics.unlocked("background:dathomir"), "legendary scene revealed and unlocked")
	await _shot("pack_scene_bonus")
	if only == "visuals":
		for dimensions in [[1024, 768], [540, 1200], [2560, 1080]]:
			await _size(dimensions[0], dimensions[1])
			for route in ["decks", "customization", "collection"]:
				await _go(route)
				var current := get_tree().current_scene
				var center: float = current.body.get_global_rect().get_center().x if route == "collection" else current._scroll.get_global_rect().get_center().x
				check(absf(current._grid.get_global_rect().get_center().x - center) <= 9, "centered %s at %s" % [route, dimensions])
				if route == "collection":
					current._page = current._pages() - 1
					current._show_page()
					await _wait(0.15)
					check(absf(current._grid.get_global_rect().get_center().x - center) <= 2, "last page centered %s" % [str(dimensions)])
				await _shot("centered_%s_%s_%s" % [route, dimensions[0], dimensions[1]])
		print("POLISH VISUALS: %d checks, %d failed" % [checks, failures])
		if failures:
			get_tree().quit(1)
		return
	# Keep the saved open pack for the full responsive-layout matrix.
	Sabacc.set_setting("perf_mode", true)
	var starter: Dictionary = CardDB.spotlight_for_mode("traditional")[0].duplicate(true)
	starter["id"] = "layout_deck"
	Save.save_deck(starter)
	var chapter := CardDB.chapter("ep4_ch1_tatooine")
	CampaignFlow.start_run(chapter, chapter["leader_options"][0])
	var spot: Dictionary = SpotlightFlow.spots()[0]
	SpotlightFlow.start(spot["id"])
	var routes := [["menu", {}], ["hub", {"section": "campaigns"}], ["hub", {"section": "battles"}], ["settings", {}], ["customization", {}], ["collection", {}], ["decks", {}], ["deck_editor", {"deck_id": "layout_deck"}], ["quick", {"format": 0}], ["quick", {"format": 1}], ["episodes", {}], ["chapter", {"chapter_id": chapter["id"]}], ["spotlight", {}], ["spotlight_run", {"deck_id": spot["id"]}], ["packs", {}], ["reward", {"won": true, "chapter_id": chapter["id"], "rewards": ["SOR_095", "SOR_239", "SOR_220"], "treasures": ["kyber_shard"]}]]
	for dimensions in sizes:
		await _size(dimensions[0], dimensions[1])
		for route in routes:
			await _go(route[0], route[1])
			var label: String = "%s_%s_%s_%s" % [route[0], route[1].get("section", route[1].get("format", "")), dimensions[0], dimensions[1]]
			_audit_controls(get_tree().current_scene, label)
			await _shot(label)
		await _go("match", {"cfg": QuickMatch.make_config("SOR_010", "HMW_019", 0, "tempo", random)})
		_audit_controls(get_tree().current_scene, "mulligan_%s" % [str(dimensions)])
		await _shot("mulligan_%s_%s" % dimensions)
		for i in 8:
			_resolve_setup(get_tree().current_scene)
			await _wait(0.15)
		_audit_controls(get_tree().current_scene, "match_%s" % [str(dimensions)])
		await _shot("match_%s_%s" % dimensions)
		await _go("collection")
		var overlay := InspectOverlay.open(get_tree().current_scene, "SOR_095")
		await _wait(0.6)
		var card_rect := Rect2(overlay._card.position, overlay._card.base_size() * overlay._card.scale)
		check(card_rect.get_center().distance_to(overlay.get_viewport_rect().size / 2) < 2, "inspection centered %s" % [str(dimensions)])
		for panel in overlay._panels:
			check(not panel.get_rect().intersects(card_rect), "dossier avoids card %s" % [str(dimensions)])
		await _shot("inspection_%s_%s" % dimensions)
		overlay.close_overlay()
		await _wait(0.3)
		print("RATIO COMPLETE ", dimensions)
		_write_layout_report()
	var report := FileAccess.open(out.path_join("layout_issues.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(layout_issues, "  "))
	check(layout_issues.is_empty(), "%d layout issues" % layout_issues.size())
	print("POLISH: %d checks, %d failed; %d layout issues" % [checks, failures, layout_issues.size()])
	if failures:
		get_tree().quit(1)


func _write_layout_report() -> void:
	var file := FileAccess.open(out.path_join("layout_issues.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(layout_issues, "  "))


func _audit_controls(scene: Node, label: String) -> void:
	var buttons: Array = []
	var viewport := Rect2(Vector2.ZERO, scene.get_viewport_rect().size)
	for node in scene.find_children("*", "", true, false):
		if not node is BaseButton or not node.is_visible_in_tree():
			continue
		var rect: Rect2 = node.get_global_rect()
		var clipped := false
		var ancestor: Node = node.get_parent()
		while ancestor and ancestor != scene:
			if ancestor is Control and ancestor.clip_contents:
				clipped = true
				rect = rect.intersection(ancestor.get_global_rect())
			ancestor = ancestor.get_parent()
		if not clipped and not viewport.grow(2).encloses(rect):
			layout_issues.append({"screen": label, "issue": "outside viewport", "button": node.name, "text": node.text if node is Button else ""})
		rect = rect.intersection(viewport)
		if rect.size.x > 8 and rect.size.y > 8:
			buttons.append([node, rect.grow(-3)])
	for a in buttons.size():
		for b in range(a + 1, buttons.size()):
			if buttons[a][0].is_ancestor_of(buttons[b][0]) or buttons[b][0].is_ancestor_of(buttons[a][0]):
				continue
			if buttons[a][1].intersects(buttons[b][1]):
				layout_issues.append({"screen": label, "issue": "buttons overlap", "a": buttons[a][0].name, "b": buttons[b][0].name, "text_a": buttons[a][0].text if buttons[a][0] is Button else "", "text_b": buttons[b][0].text if buttons[b][0] is Button else ""})
