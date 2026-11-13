extends "res://tests/interaction_tests.gd"
## Drives the campaign token and Pilot choices through the live portrait board.


func _run() -> void:
	Save.data = Save.default_data()
	await _size(570, 1280)
	var pack_id := Progression.grant("Input test", "pack-input-test")
	Progression.tear(pack_id)
	await _go("menu")
	var menu := get_tree().current_scene
	check(menu._buttons.get_child(0).get_script().resource_path.ends_with("/menu_button.gd"),
		"Portrait menu uses the redesigned menu buttons")
	check(_button(menu, "Card Packs") == null and _button(menu, "Deck Builder") == null,
		"Card Packs and Deck Builder live inside the Collection Vault")
	await _click(_button(menu, "Collection Vault"))
	var vault := get_tree().current_scene
	check(_button(vault, "Deck Builder") != null, "Collection Vault exposes Deck Builder")
	await _click(_button(vault, "Card Packs"))
	check(_button(vault, "Buy pack").disabled, "Insufficient credits disable pack purchases")
	await _click(_button(vault, "Open packs"))
	var pack_screen := get_tree().current_scene
	var slots: Array = pack_screen._slots.duplicate()
	for slot in slots:
		await _click(slot)
	check(not pack_screen._done.disabled and pack_screen._pack["revealed"].size() == 10,
		"All portrait pack rewards reveal through their artwork and enable collection")
	await _go("collection")
	vault = get_tree().current_scene
	Progression.award_credits("input-test-funds", 1000)
	await _click(_button(vault, "Card Packs"))
	await _click(_button(vault, "Buy pack"))
	var purchased := get_tree().current_scene
	check(purchased._pack["source"] == "Purchased pack" and purchased._pack["set"] == "SOR"
		and purchased._pack["id"] != pack_id and Progression.credits() == 0,
		"Portrait Vault purchases and opens the selected set pack")
	var chapter := CardDB.chapter("ep4_ch1_tatooine")
	var node := CampaignRun.node_by_id(chapter, "n7")
	var run := CampaignRun.start(chapter, "SEC_015", 212)
	run["base_damage"] = 15
	var config := CampaignRun.match_config(run, chapter, node, {})
	config["first"] = 0
	config["players"][1]["ai"] = false
	config["rules"].allow_mulligan = false
	config["rules"].starting_resources = 0
	await _go("match", {"mode": "quick", "title": node["title"], "cfg": config})
	var screen := get_tree().current_scene
	await _finish_setup(screen)
	var m: Match = screen.m
	var krayt := _button(screen.tray, "Krayt Call")
	check(krayt != null and krayt.disabled, "Krayt Call is disabled until it can defeat a Tusken")
	var tusken := m._new_inst("HMW_224", 1)
	m._put_in_play(tusken, "ground", false)
	for i in 12:
		var trooper := m._new_inst("SOR_128", 1)
		m._put_in_play(trooper, "ground", false)
	screen.coin.holder = 1
	screen.coin.position = screen.coin_pos(1)
	screen._sync()
	await _wait(0.45)
	krayt = _button(screen.tray, "Krayt Call")
	check(krayt != null and not krayt.disabled and krayt.autowrap_mode == TextServer.AUTOWRAP_OFF,
		"Krayt Call is enabled and stays on one line")
	check(screen.tokens.values().all(func(token): return get_viewport().get_visible_rect().encloses(token.get_global_rect())),
		"All units on the crowded board stay on-screen")
	if only == "capture":
		await _shot("krayt-call-button")
	await _click(krayt)
	for i in 40:
		if not screen.busy:
			break
		await _wait(0.15)
	check(screen.prompt_bar.visible and screen.prompt_label.text.begins_with("Krayt Call"),
		"Clicking Krayt Call prompts for the Tusken")
	check(not screen.prompt_bar.get_global_rect().intersects(screen.coin.get_global_rect()),
		"The prompt clears the initiative token")
	if only == "capture":
		await _shot("krayt-call-target")
	screen._submit_targets([m.players[1].base.uid])
	check(screen.prompt_bar.visible and not m.pending.is_empty(), "An invalid target leaves the prompt available")
	await _click(screen.tokens[tusken.uid])
	check(tusken.zone == "discard" and m.pending.is_empty() and m.active == 1, "Clicking the Tusken resolves and hands over the turn")

	await _go("match")
	screen = get_tree().current_scene
	await _finish_setup(screen)
	m = screen.m
	m.active = 0
	m.players[1].is_ai = false
	m.rules.aspect_penalties = false
	var host := m._new_inst("SOR_237", 0)
	m._put_in_play(host, m.arena_for(host), false)
	var pilot := m._new_inst("JTL_058", 0)
	pilot.zone = "hand"
	m.players[0].hand.append(pilot)
	for resource in m.players[0].resources:
		resource.exhausted = false
	screen._sync()
	await _wait(0.45)
	var pilot_card: CardView
	for child in screen.hand.get_children():
		if child is CardView and child.inst == pilot:
			pilot_card = child
			break
	check(pilot_card != null, "Pilot appears in hand")
	if pilot_card:
		await _click(pilot_card)
		var pilot_button := _button(screen, "Play as Pilot")
		check(pilot_button != null, "Clicking a Pilot offers its upgrade action")
		if pilot_button:
			await _click(pilot_button)
			await _wait(0.6)
			await _click(screen.tokens[host.uid])
			check(pilot.attached_to == host and host.has_kw("sentinel"), "Selecting the Vehicle attaches the Pilot")
	if pilot.attached_to == host:
		m.active = 0
		m.push_frame([{"op": "defeat", "t": {"s": "choose", "kind": "upgrade"}}], {"ctl": 0})
		m.pump()
		screen._step()
		await _wait(0.6)
		var pickers := screen.find_children("*", "ChoicePanel", true, false)
		check(pickers.size() == 1, "An upgrade target opens a card picker")
		if pickers.size() == 1:
			var picker: ChoicePanel = pickers[0]
			await _click(picker._views[pilot.uid])
			await _click(_button(picker, "Confirm"))
			check(pilot.zone == "discard" and not host.has_kw("sentinel"), "The chosen upgrade is removed")
	m.active = 0
	var base := m._new_inst("LOF_028", 0)
	base.zone = "base"
	m.players[0].base = base
	screen.hud[0].bind(m.players[0])
	var payer := m._new_inst("SOR_095", 0)
	m._put_in_play(payer, "ground", false)
	m.players[0].force_token = false
	screen._sync()
	await _wait(0.35)
	var tile: Control = screen.hud[0].base_view
	var from := tile.get_global_rect().get_center()
	await _drag(from, from + Vector2(0, -45))
	await _wait(0.4)
	var use := _button(screen, "Action [exhaust a friendly unit]")
	check(use != null and not use.disabled, "Dragging the base opens its legal action")
	if use:
		await _click(use)
		await _click(screen.tokens[payer.uid])
		check(payer.exhausted and m.players[0].force_token, "Tomb of Eilram exhausts the chosen unit and grants the Force")
	m.active = 0
	var drag_pilot := m._new_inst("JTL_058", 0)
	drag_pilot.zone = "hand"
	m.players[0].hand.append(drag_pilot)
	for resource in m.players[0].resources:
		resource.exhausted = false
	screen._sync()
	await _wait(0.45)
	for child in screen.hand.get_children():
		if child is CardView and child.inst == drag_pilot:
			await _drag(child.get_global_rect().get_center(), screen.tokens[host.uid].get_global_rect().get_center())
			break
	await _wait(0.55)
	check(drag_pilot.attached_to == host and m.pending.is_empty(), "Dragging a hand Pilot onto a Vehicle attaches without a picker")
	if drag_pilot.is_pilot_upgrade():
		m.defeat(drag_pilot)
		m.pump()
	m.active = 0
	var leader := m._new_inst("JTL_006", 0)
	leader.zone = "leader"
	m.players[0].leader = leader
	for i in 6 - m.players[0].resources.size():
		m.move_to_resources(0, m.players[0].deck[0])
	screen.hud[0].bind(m.players[0])
	screen._sync()
	await _wait(0.5)
	await _drag(screen.hud[0].leader_view.get_global_rect().get_center(), screen.tokens[host.uid].get_global_rect().get_center())
	for i in 50:
		if not screen.busy:
			break
		await _wait(0.15)
	check(leader.attached_to == host and host.is_leader_unit(), "Dragging the leader tile deploys it directly onto a Vehicle")
	m.active = 0
	for i in 6 - m.players[0].resources.size():
		m.move_to_resources(0, m.players[0].deck[0])
	for resource in m.players[0].resources:
		resource.exhausted = false
	var fortification := m._new_inst("HMW_095", 0)
	fortification.zone = "hand"
	m.players[0].hand.append(fortification)
	screen._sync()
	await _wait(0.5)
	for child in screen.hand.get_children():
		if child is CardView and child.inst == fortification:
			await _drag(child.get_global_rect().get_center(), tile.get_global_rect().get_center())
			break
	for i in 50:
		if not screen.busy:
			break
		await _wait(0.15)
	var tab: Button = screen.hud[0].fortification_tab
	check(fortification.attached_to == base and tab.visible and tab.text == fortification.name(),
		"Dragging Fortify onto the base displays the named attachment")
	if tab.visible:
		m.active = 0
		screen._sync()
		await _click(tab)
		check(_button(screen, "Inspect " + fortification.name()) != null, "Fortification tab opens the attached card")

		var fort_action := _button(screen, "Action [defeat this upgrade]")
		check(fort_action != null and not fort_action.disabled, "Fortification tab offers its printed action")
		if fort_action:
			await _click(fort_action)
			await _wait(0.5)
			await _click(screen.tokens[payer.uid])
			check(fortification.zone == "discard" and payer.flags.get("skip_regroup_ready", false) and not tab.visible,
				"Using the Fortification action applies its effect and removes the tab")

	var cantina_run := CampaignRun.start(chapter, chapter["leader_options"][0], 616)
	cantina_run["credits"] = 50
	cantina_run["base_damage"] = 10
	for parent in chapter["map"]["edges"]:
		if "rest" in chapter["map"]["edges"][parent]:
			cantina_run["current"] = parent
			break
	Save.set_run(cantina_run)
	var wallet_before := Progression.credits()
	await _go("chapter", {"chapter_id": chapter["id"]})
	var map := get_tree().current_scene
	await _click(map._nodes["rest"])
	var repair := _button(map, "Repair 8 base damage")
	check(repair != null and not repair.disabled, "Cantina offers a repair for run credits")
	if repair:
		await _click(repair)
		await _wait(1.5)
		check(Save.run()["credits"] == 30 and Save.run()["base_damage"] == 2
			and "rest" in Save.run()["visited"] and Progression.credits() == wallet_before,
			"Cantina spends 20 from the run and leaves the Vault wallet alone")

	print("CAMPAIGN INPUT: %d checks, %d failed" % [checks, failures])
	if failures:
		get_tree().quit(1)


func _finish_setup(screen: Control) -> void:
	for i in 12:
		_resolve_setup(screen)
		if not screen.m.pending.is_empty() and screen.m.pending["player"] == 1:
			AiBot.choose(screen.m)
			screen._step()
		await _wait(0.5)
		if screen.m.phase == "action" and screen.m.pending.is_empty() and not screen.busy:
			break
	check(screen.m.phase == "action" and not screen.busy, "Battle setup reaches the action phase")
