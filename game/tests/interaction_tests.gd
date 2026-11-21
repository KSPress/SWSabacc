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
		check(carousel._open.text == "Galactic Conquest" and carousel._open.disabled, "Conquest is marked in development")
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
