extends "res://tests/interaction_tests.gd"
## Drives the campaign token and Pilot choices through the live portrait board.


func _run() -> void:
	Save.data = Save.default_data()
	await _size(570, 1280)
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
