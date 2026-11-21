extends SceneTree

var lib := CardLibrary.new()
var checks := 0
var failures := 0


func _init() -> void:
	lib.load_file("res://ip/data/cards.json")
	for count in ConquestRun.SIZES:
		var campaign := ConquestRun.start(lib, 0, count, 41)
		check(campaign.state["worlds"].size() == count, "world count %d" % count)
		check(campaign.fleet(0)["cards"].size() == 21, "starting fleet")
		var found := {"Coruscant": true}
		var pending := ["Coruscant"]
		while not pending.is_empty():
			for name in campaign.neighbors(pending.pop_front()):
				if not found.has(name):
					found[name] = true
					pending.append(name)
		check(found.size() == count, "world routes remain connected")

	var run := ConquestRun.start(lib, 0, 8, 72)
	check(not run.order(0, "Kamino") and run.order(0, "Corellia"), "routes require friendly intermediate worlds")
	check(run.fleet(0)["world"] == "Coruscant" and run.player_battle().is_empty(), "orders require travel time")
	run.tick(1)
	check(run.travel_progress(run.fleet(0)) > 0 and run.travel_progress(run.fleet(0)) < 1, "fleet moves along lane")
	run.tick(20)
	var key := run.player_battle()
	check(not key.is_empty() and run.state["battles"][key]["world"] == "Corellia", "arrival creates an invasion battle")
	check(not run.fleet(1)["route"].is_empty() and not run.fleet(2)["route"].is_empty(), "bots issue real-time travel orders")
	check(run.state["factions"][0]["credits"] == 120 + ConquestRun.INCOME_PER_WORLD, "holding a planet generates income")

	var cfg := run.battle_config(key, true)
	check(cfg["players"][0]["leader"] == "SOR_010" and cfg["players"][1]["leader"].is_empty()
		and cfg["players"][1]["deck"].size() == 8, "unoccupied planet fights with a small militia")
	var m := Match.new()
	m.setup(lib, cfg)
	var lost: CardInst = m.players[0].hand[0]
	var before: int = run.fleet(0)["cards"].count(lost.id)
	m.players[0].hand.erase(lost)
	m._put_in_play(lost, lost.arena(), false)
	m.defeat(lost)
	m.players[0].discard.erase(lost)
	m._put_in_play(lost, lost.arena(), false)
	m.defeat(lost)
	check(m.roster_losses[0] == [lost.id], "the same defeated copy only counts once even if revived")
	var credits: int = run.state["factions"][0]["credits"]
	m.set_winner(0, "test conquest")
	var result := run.finish_battle(key, m, true)
	check(result["captured"] and run.state["worlds"]["Corellia"]["owner"] == 0, "victory captures the world")
	check(run.fleet(0)["cards"].count(lost.id) == before - 1 and run.finish_battle(key, m, true).is_empty(),
		"settlement removes one copy and cannot pay twice")
	check(int(run.state["factions"][0]["credits"]) == credits + ConquestRun.WIN_REWARD, "win pays conquest wallet")
	check(run.buy(0, "Corellia", "garrison") and run.state["worlds"]["Corellia"]["cards"].size() == 6, "garrisons add a defensive reserve")
	var local_cards: Array = run.state["worlds"]["Coruscant"]["cards"]
	check(run.transfer(0, "Coruscant", [local_cards[0]]) and run.state["shipments"].size() == 1, "remote reserve cards travel by lane")
	var fleet_size: int = run.fleet(0)["cards"].size()
	run.tick(20)
	check(run.fleet(0)["cards"].size() == fleet_size + 1 and run.state["shipments"].is_empty(), "shipment joins the stationed fleet")
	var restored := ConquestRun.new(lib, JSON.parse_string(JSON.stringify(run.state)))
	check(restored.player_battle() == run.player_battle() and restored.fleet(0)["cards"] == run.fleet(0)["cards"], "save round trip preserves campaign")

	run = ConquestRun.start(lib, 0, 8, 82)
	for world in ["Geonosis", "Kamino", "Mandalore"]:
		var planet: Dictionary = run.state["worlds"][world]
		planet["owner"] = 0
		planet["cards"] = []
		run.state["factions"][0]["credits"] = 200
		check(run.buy(0, world, "garrison") and run.buy(0, world, "troops"), world + " can recruit local troops")
		var local: String = ConquestRun.GALAXY.SPECIALTIES[world]
		check(planet["cards"].all(func(id): return local in lib.get_card(id)["traits"]), world + " uses the lore card pool")
	check(run.buy(0, "Mandalore", "frigates") and run.buy(0, "Mandalore", "produce"), "dockyard builds a space reinforcement pack")
	check(run.state["worlds"]["Mandalore"]["cards"].slice(-4).all(func(id): return lib.get_card(id)["arena"] == "space"), "dockyard builds space units")
	check(not run.can_buy(0, "Mandalore", "satellite"), "two occupied slots block construction")
	run.state["factions"][0]["credits"] = 250
	check(run.buy(0, "Kamino", "droids") and not run.can_buy(0, "Kamino", "troopers"), "second card factory is blocked")

	run = ConquestRun.start(lib, 0, 8, 112)
	check(run.order(1, "Coruscant"), "enemy can attack player home")
	run.tick(40)
	key = run.player_battle()
	cfg = run.battle_config(key, true)
	check(cfg["players"][0]["leader"] == "SOR_010" and not cfg["players"][0]["ai"], "human takes the defender seat")
	check(cfg["players"][1]["leader"] == "SOR_005", "the attacking fleet keeps its own leader")

	run = ConquestRun.start(lib, 0, 8, 87)
	check(run.order(1, "Mandalore"), "bot can attack a neutral world")
	run.tick(5)
	var ai_key: String = run.state["battles"].keys()[0]
	m = Match.new()
	m.setup(lib, run.battle_config(ai_key, false))
	for i in 500:
		if m.winner >= 0:
			break
		if m.pending.is_empty():
			AiBot.act(m)
		else:
			AiBot.choose(m)
	check(m.winner >= 0 and not run.finish_battle(ai_key, m, false).is_empty(), "a bot-only invasion plays to a result in the card engine")
	test_expanded_conquest()
	print("CONQUEST: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func test_expanded_conquest() -> void:
	for options in [[0, "JTL_006", "Coruscant"], [1, "JTL_012", "Yavin"], [2, "SEC_002", "Nal Hutta"]]:
		var run := ConquestRun.start(lib, options[0], 16, 12, options[1])
		check(run.fleet(options[0])["leader"] == options[1] and run.fleet(options[0])["world"] == options[2], "selected printing starts at home")
	var run := ConquestRun.start(lib, 0, 16, 17)
	var worlds: Dictionary = run.state["worlds"]
	for name in ["Corellia", "Mandalore", "Geonosis"]:
		worlds[name]["owner"] = 0
	check(run.available_milestone(0) == 4 and run.eligible_commanders(0, "Mandalore").has("TWI_010"), "Mandalorian leaders unlock on Mandalore")
	check(run.eligible_commanders(0, "Geonosis").has("TWI_015"), "Geonosis unlocks Separatist commanders")
	check(run.build_commander(0, "Mandalore", "TWI_010") and run.available_milestone(0) == 0,
		"milestone builds one independent fleet from local reserves")
	run = ConquestRun.new(lib, JSON.parse_string(JSON.stringify(run.state)))
	worlds = run.state["worlds"]
	check(run.available_milestone(0) == 0 and run.fleets(0).size() == 2,
		"reloading a JSON save does not unlock the same milestone a second time")
	check(run.fleet(0, 1)["leader"] == "TWI_010" and run.order(0, "Dathomir", 1), "second fleet accepts independent orders")
	for name in ["Kamino", "Naboo", "Kuat", "Kashyyyk"]:
		worlds[name]["owner"] = 0
	check(run.available_milestone(0) == 8, "second milestone unlocks at eight")
	check(run.build_commander(0, "Geonosis", "TWI_015"), "second milestone commissions the Geonosis leader")
	for name in ["Tatooine", "Hoth", "Endor", "Scarif"]:
		worlds[name]["owner"] = 0
	check(run.available_milestone(0) == 12, "third milestone unlocks at twelve")

	run = ConquestRun.start(lib, 0, 8, 119)
	check(not run.visible_to(0, "Yavin") and run.buy(0, "Coruscant", "probe"), "enemy locations begin concealed and probes cost credits")
	check(run.launch_probe(0, "Coruscant", "Yavin") and not run.visible_to(0, "Yavin"), "probes travel before revealing intel")
	for side in run.state["factions"]:
		side["next_order"] = 9999
	run.tick(40)
	check(run.visible_to(0, "Yavin") and run.state["probes"].is_empty(), "enemy fleet intercepts the scout after a brief reveal")
	run.tick(16)
	check(not run.visible_to(0, "Yavin") and run.buy(0, "Coruscant", "satellite") and run.visible_to(0, "Yavin"),
		"probe intelligence expires and satellite intelligence covers connected worlds")

	run = ConquestRun.start(lib, 0, 8, 85)
	run.state["factions"][1]["credits"] = 300
	check(run.buy(1, "Yavin", "orbital") and run.order(1, "Mandalore") and run.order(0, "Yavin"),
		"orbital defenses remain when a fleet departs")
	run.tick(40)
	var key := run.player_battle()
	var cfg := run.battle_config(key, true)
	check(cfg["rules"].arenas == ["space"] and cfg["players"][1]["deck"].size() == 8,
		"defense fleet fights with its persistent space-only roster")


func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + description)
