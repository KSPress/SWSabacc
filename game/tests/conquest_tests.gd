extends SceneTree

var lib := CardLibrary.new()
var checks := 0
var failures := 0


func _init() -> void:
	lib.load_file("res://ip/data/cards.json")
	lib.load_file("res://data/custom_cards.json", true)
	for count in ConquestRun.SIZES:
		var campaign := ConquestRun.start(lib, 0, count, 41)
		check(campaign.state["worlds"].size() == count, "world count %d" % count)
		check(campaign.fleet(0)["cards"].size() == 21, "starting fleet")
		for faction in ConquestGalaxy.FACTIONS.size():
			var cards: Array = campaign.fleet(faction)["cards"]
			check(campaign._fitted_cards([], cards) == cards, "starting fleet obeys duplicate caps")
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
		check(planet["cards"].all(func(id):
			var card := lib.get_card(id)
			return local in card["traits"] or (world == "Kamino" and ConquestGalaxy.native_match(card, "native_republic_vehicle"))
		), world + " uses the lore card pool")
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
	test_era_production()
	test_fleet_copy_limits()
	test_factory_catalog()
	test_playable_commander()
	test_command_training()
	test_command_retreat()
	test_voluntary_withdrawal()
	test_local_catalogs()
	test_final_capture()
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
	check(run.available_milestone(0) == 4 and run.eligible_commanders(0, "Mandalore").has("SOR_014"), "Mandalorian leaders unlock on Mandalore")
	check(run.eligible_commanders(0, "Geonosis").has("KYB_005") and not run.eligible_commanders(0, "Geonosis").has("TWI_015"),
		"Geonosis unlocks the remnant droid commander and excludes Grievous")
	check(run.build_commander(0, "Mandalore", "SOR_014") and run.available_milestone(0) == 0,
		"milestone builds one independent fleet from local reserves")
	run = ConquestRun.new(lib, JSON.parse_string(JSON.stringify(run.state)))
	worlds = run.state["worlds"]
	check(run.available_milestone(0) == 0 and run.fleets(0).size() == 2,
		"reloading a JSON save does not unlock the same milestone a second time")
	check(run.fleet(0, 1)["leader"] == "SOR_014" and run.order(0, "Dathomir", 1), "second fleet accepts independent orders")
	for name in ["Kamino", "Naboo", "Kuat", "Kashyyyk"]:
		worlds[name]["owner"] = 0
	check(run.available_milestone(0) == 8, "second milestone unlocks at eight")
	check(run.build_commander(0, "Geonosis", "KYB_005"), "second milestone commissions the Geonosis leader")
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


func test_fleet_copy_limits() -> void:
	var run := ConquestRun.start(lib, 1, 16, 71)
	var world := "Yavin"
	var sibling := "Coruscant"
	var sites: Dictionary = run.state["worlds"]
	sites[sibling]["owner"] = 1
	for side in run.state["factions"]:
		side["next_order"] = 9999
	var task := run.fleet(1)
	task["cards"] = ["SOR_239", "SOR_239", "SOR_196"]
	sites[world]["cards"] = ["SEC_250", "SOR_196"]
	sites[sibling]["cards"] = ["SEC_250", "SOR_239"]
	check(not run.transfer(1, world, ["SOR_196"]), "a unique card has a one-copy fleet cap")
	check(run.transfer(1, sibling, ["SEC_250"]), "a reprint can fill the third non-unique spot")
	check(not run.transfer(1, world, ["SEC_250"]) and not run.transfer(1, sibling, ["SOR_239"]),
		"the in-flight third copy blocks a fourth from either world")
	check(sites[world]["cards"] == ["SEC_250", "SOR_196"], "blocked transfers leave reserves alone")
	run.tick(40)
	check(task["cards"].size() == 4 and task["cards"].back() == "SEC_250", "the legal reserve joins the fleet")
	run.state["shipments"].append({"faction": 1, "fleet": 0, "world": world, "cards": ["SOR_239"], "route": []})
	run._deliver(run.state["shipments"][0])
	check(task["cards"].size() == 4 and sites[world]["cards"].count("SOR_239") == 1,
		"excess copies from legacy shipments stay in planetary reserve")
	task["cards"].append_array(["SOR_239", "SOR_196"])
	var saved_reserve: int = sites[world]["cards"].size()
	run = ConquestRun.new(lib, JSON.parse_string(JSON.stringify(run.state)))
	check(run.fleet(1)["cards"].size() == 4 and run.state["worlds"][world]["cards"].size() == saved_reserve + 2,
		"existing saves move excess copies to planetary reserves")
	run.state["worlds"][world]["cards"] = ["SOR_239", "SOR_239", "SEC_250", "SEC_250",
		"SOR_196", "SOR_196", "SOR_095", "SOR_095", "SOR_095"]
	check(run.commissioning_cards(world).size() == 7, "commissioning counts only roster-eligible copies")


func test_factory_catalog() -> void:
	var run := ConquestRun.start(lib, 0, 8, 74)
	var home := "Coruscant"
	check(run.factory_catalog(0, home).is_empty() and not run.manufacture(0, home, "SOR_128"),
		"Manufacturing requires a factory")
	check(run.buy(0, home, "troopers"), "Build a barracks for direct manufacturing")
	var catalog := run.factory_catalog(0, home)
	check(not catalog.is_empty() and catalog.all(func(id): return run._fits_factory(lib.get_card(id), "troopers")),
		"The catalog contains the factory's actual products")
	var reserves: Array = run.state["worlds"][home]["cards"]
	var count := reserves.size()
	var credits: int = run.state["factions"][0]["credits"]
	var id: String = catalog[0]
	check(not run.manufacture(0, home, "SOR_231") and not run.manufacture(1, home, id),
		"Out-of-catalog and foreign factory purchases are rejected")
	check(run.manufacture(0, home, id) and reserves.size() == count + 1 and reserves.back() == id
		and int(run.state["factions"][0]["credits"]) == credits - run.manufacture_price(id),
		"Manufacturing adds the selected card and charges its listed price")
	run.state["factions"][0]["credits"] = 0
	check(not run.manufacture(0, home, id), "Cannot manufacture without enough credits")
	run.state["factions"][0]["credits"] = 1000
	reserves.resize(ConquestRun.RESERVE_LIMIT)
	check(not run.manufacture(0, home, id), "A full reserve blocks manufacturing")


func test_playable_commander() -> void:
	var run := ConquestRun.start(lib, 0, 8, 74)
	run._begin_battle(0, "Yavin")
	var m := Match.new()
	m.setup(lib, run.battle_config(run.player_battle(), false))
	while not m.pending.is_empty():
		AiBot.choose(m)
	var vader: CardInst = m.players[0].leader
	var luke: CardInst = m.players[1].leader
	check(vader == m.players[0].base and vader.in_play() and vader.deployed and not vader.exhausted,
		"The primary commander starts deployed and ready as the only base")
	check(m.trigger_sources().count(vader) == 1 and m.all_units().count(vader) == 1
		and Effects.candidates(m, {"kind": "unit_or_base"}, {"ctl": 0}).count(vader) == 1,
		"The command card is a single source and choice target")
	check(vader.abilities_with("action").size() == 1 and vader.abilities_with("on_attack").size() == 1
		and not {"a": "deploy"} in m.legal_actions(0), "The tactical commander can use front and deployed abilities without another deployment")
	var foe := m._new_inst("SOR_046", 1)
	m._put_in_play(foe, "ground", false)
	var shot := {"a": "attack", "uid": vader.uid, "target": foe.uid}
	check(shot in m.legal_actions(0) and m.do_action(shot), "Commanders can attack a normal unit")
	if not m.pending.is_empty():
		m.submit_choice([])
	check(vader.exhausted and vader.damage == foe.printed_power() and foe.damage == vader.printed_power(),
		"Attacking a unit deals and receives normal combat damage")
	var xwing := m._new_inst("SOR_237", 1)
	m._put_in_play(xwing, "space", false)
	check(vader.uid in m.attack_targets(xwing) and vader.uid in m.attack_targets(foe),
		"Both arenas can attack the commander as their opposing base")
	var armor := m._new_inst("SOR_069", 0)
	check(vader in Effects.upgrade_targets(m, 0, armor), "A regular upgrade can target the commander")
	var max_hp := vader.max_hp()
	m.attach_upgrade(armor, vader, {"pre_equipped": true})
	check(armor.attached_to == vader and armor in vader.upgrades and vader.max_hp() == max_hp + armor.printed_hp(),
		"Attached upgrades modify the same health used by the base")
	var before := vader.damage
	m.begin_attack(xwing, vader)
	m.pump()
	check(vader.damage == before + xwing.printed_power() and xwing.damage == 0 and luke.damage == 0,
		"An ordinary base attack damages the commander without defensive retaliation")
	m.attach_token(vader, "shield")
	check(m.deal_damage(m.players[0].base, 4, null) == 0 and vader.shield_count() == 0,
		"A shield attached to the unit protects it from base damage")
	m = Match.new()
	m.setup(lib, run.battle_config(run.player_battle(), false))
	while not m.pending.is_empty():
		AiBot.choose(m)
	vader = m.players[0].leader
	luke = m.players[1].leader
	var trooper := m._new_inst("SOR_128", 0)
	trooper.zone = "hand"
	m.players[0].hand.append(trooper)
	check(m.do_action({"a": "play", "uid": trooper.uid}) and m.do_action({"a": "pass"}),
		"A Villainy card primes the commander's front-side action")
	check(m.do_action({"a": "ability", "uid": vader.uid, "idx": 0})
		and m.submit_choice([luke.uid]) and m.submit_choice([luke.uid])
		and vader.exhausted and luke.damage == 2,
		"The front-side action resolves from the base slot against both unit and base roles")


func test_command_training() -> void:
	var run := ConquestRun.start(lib, 0, 8, 72)
	for side in run.state["factions"]:
		side["next_order"] = 9999
	var home := "Coruscant"
	var task := run.fleet(0)
	task["cards"] = ["SOR_231", "SOR_231"] + run.fleet(0)["cards"]
	run.state["factions"][0]["credits"] = 1000
	check(not run.can_train(0, home, 0, "health") and run.buy(0, home, "training"), "a Training Center is required")
	check(not run.can_buy(0, home, "armory"), "the Training Center occupies a normal building slot")
	for perk in ["health", "resources"]:
		check(run.train(0, home, 0, perk) and run.train(0, home, 0, perk)
			and not run.train(0, home, 0, perk), perk + " purchases respect their caps")
	check(run.train(0, home, 0, "command_shield"), "training adds a recurring command shield")
	for perk in ["opening", "shield", "experience"]:
		check(run.train(0, home, 0, perk, "SOR_231") and not run.train(0, home, 0, perk, "SOR_231"),
			perk + " is purchased once for the TIE Advanced")
	check(not run.train(0, home, 0, "equipment", "SOR_231", "SHD_174")
		and run.train(0, home, 0, "equipment", "SOR_231", "SOR_121"), "permanent equipment enforces printed vehicle requirements")
	var total := run.price("training") + 2 * run.price("health") + 2 * run.price("resources")
	for perk in ["command_shield", "opening", "shield", "experience", "equipment"]:
		total += run.price(perk)
	check(run.state["factions"][0]["credits"] == 1000 - total, "the wallet is charged only for valid purchases")
	run = ConquestRun.new(lib, JSON.parse_string(JSON.stringify(run.state)))
	task = run.fleet(0)
	run._begin_battle(0, "Corellia")
	var key := run.player_battle()
	var cfg := run.battle_config(key, false)
	check(not cfg["players"][0].has("base") and not cfg["rules"].aspect_penalties and not cfg["rules"].hero_villain_gate,
		"Conquest supplies no base cards or aspect restrictions")
	check(cfg["players"][0]["deck"].count("SOR_231") == task["cards"].count("SOR_231") - 1,
		"the preplayed unit uses a real fleet copy")
	var m := Match.new()
	m.setup(lib, cfg)
	var ps: PlayerState = m.players[0]
	while not m.pending.is_empty():
		AiBot.choose(m)
	var tie: CardInst = ps.units.filter(func(unit): return unit.id == "SOR_231")[0]
	check(ps.base.max_hp() == 40 and ps.leader.max_hp() == 40 and ps.resources.size() == 4,
		"training health and starting resources persist across save and setup")
	check(tie.id == "SOR_231" and not tie.exhausted and tie.shield_count() == 1
		and tie.upgrades.any(func(up): return up.id == "SOR_121") and tie.power() > tie.printed_power(),
		"opening unit starts ready with attached equipment, Experience and Shield")
	check(m.deal_damage(ps.base, 5, null) == 0 and ps.base.damage == 0, "trained command shield absorbs the first hit")
	m.deal_damage(ps.base, 16, null)
	check(ps.leader.in_play() and ps.leader.remaining_hp() == 24, "The deployed commander uses live base health")
	m.deal_damage(ps.leader, 3, null)
	m.heal(ps.leader, 2)
	check(ps.base.damage == 17 and ps.leader.damage == 17, "deployed commander damage and healing use the same pool")
	m.defeat(tie)
	check(m.roster_losses[0] == ["SOR_231"], "preplayed copies are permanently lost when defeated")
	m.set_winner(0, "test victory")
	run.finish_battle(key, m, false)
	check(task["command_damage"] == 17, "surviving commander retains damage after battle")
	run.tick(59)
	check(task["command_damage"] == 17, "recovery waits a full minute")
	run._begin_battle(0, "Naboo")
	run.tick(3)
	check(task["command_damage"] == 17, "engaged commanders do not heal on the strategic clock")
	key = run.player_battle()
	cfg = run.battle_config(key, true)
	check(cfg["players"][0]["base_damage"] == 17, "the next battle starts with existing wounds")
	m = Match.new()
	m.setup(lib, cfg)
	m.set_winner(0, "test victory")
	run.finish_battle(key, m, true)
	run.tick(60)
	check(task["command_damage"] == 7, "ambient recovery heals ten HP per minute after battle")
	run.tick(60)
	check(task["command_damage"] == 0, "recovery stops at full health")


func test_command_retreat() -> void:
	var run := ConquestRun.start(lib, 0, 8, 72)
	for side in run.state["factions"]:
		side["next_order"] = 9999
	run.state["worlds"]["Corellia"]["owner"] = 0
	run.fleet(0)["world"] = "Corellia"
	check(run.order(0, "Naboo"), "a living commander can invade")
	run.tick(40)
	var key := run.player_battle()
	var m := Match.new()
	m.setup(lib, run.battle_config(key, false))
	check(m.players[0].base.max_hp() == 30 and m.players[0].base.is_commander(),
		"untrained fleet command starts at 30 HP")
	m.deal_damage(m.players[0].base, 30, null)
	m._state_based()
	check(m.winner == 1 and m.roster_leader_lost[0], "Depleting commander health ends the match")
	var survivors: Array = run.fleet(0)["cards"].duplicate()
	var result := run.finish_battle(key, m, true)
	check(result["leader_lost"] and run.fleet(0)["retreating"] and run.fleet(0)["route"] == ["Corellia"],
		"the survivors retreat along the nearest route even when the capital is held")
	run = ConquestRun.new(lib, JSON.parse_string(JSON.stringify(run.state)))
	run.tick(40)
	var task := run.fleet(0)
	check(run.idle(task) and task["world"] == "Corellia" and task["cards"] == survivors,
		"retreat and surviving roster persist across save and reload")
	check(not run.order(0, "Naboo") and not run.order(0, "Coruscant") and run._defender_index(0, "Corellia") == 0,
		"leaderless fleet is available to defend and cannot attack or move")
	var commander: String = run.eligible_commanders(0, "Coruscant")[0]
	check(not run.eligible_commanders(0, "Coruscant").has("SOR_010"), "a defeated character cannot be recommissioned")
	check(run.send_replacement(0, "Coruscant", 0, commander) and not task["leader_alive"]
		and not run.can_send_replacement(0, "Coruscant", 0), "new commander travels separately and cannot be ordered twice")
	run = ConquestRun.new(lib, JSON.parse_string(JSON.stringify(run.state)))
	run.tick(40)
	task = run.fleet(0)
	check(task["leader"] == commander and task["leader_alive"] and task["command_damage"] == 0
		and run.order(0, "Naboo"), "delivery restores an existing fleet to active command")
	run.tick(40)
	m = Match.new()
	m.setup(lib, run.battle_config(run.player_battle(), false))
	m.defeat(m.players[0].leader)
	m._state_based()
	check(m.winner == 1 and m.roster_leader_lost[0], "direct defeat of the deployed commander also ends battle")


func test_era_production() -> void:
	var campaign := ConquestRun.start(lib, 0, 32, 73)
	var worlds: Dictionary = campaign.state["worlds"]
	var funds: Dictionary = campaign.state["factions"][0]
	for group in [["Coruscant", "officers"], ["Corellia", "government"], ["Naboo", "armory"]]:
		var world: String = group[0]
		var factory: String = group[1]
		worlds[world]["owner"] = 0
		worlds[world]["cards"] = []
		funds["credits"] = 200
		var price := campaign.price(factory) + campaign.price("produce")
		check(campaign.buy(0, world, factory) and campaign.buy(0, world, "produce"), "new factories take credits and produce reserves")
		var cards: Array = worlds[world]["cards"]
		check(cards.size() == 4 and funds["credits"] == 200 - price and cards.all(func(id): return campaign._fits_factory(lib.get_card(id), factory)),
			"%s produces only its category" % factory)
		check(not campaign.can_buy(0, world, "troopers"), "new factories count toward the existing one-factory limit")
	var equipment := campaign._factory_pool("Naboo", 0, "armory")
	for item_type in ["weapon", "armor", "modification"]:
		check(equipment.any(func(id): return item_type in lib.get_card(id)["traits"]), "Armory includes " + item_type)
	check(equipment.has("SOR_121") and not equipment.has("LOF_238"), "Armory supports era equipment and excludes Revan's blades")

	for world in ConquestGalaxy.NATIVE_RECRUITS:
		worlds[world]["owner"] = 0
		worlds[world]["facilities"] = ["fortification", "satellite"]
		for entry in ConquestGalaxy.NATIVE_RECRUITS[world]:
			worlds[world]["cards"] = []
			funds["credits"] = 200
			check(campaign.buy(0, world, entry), "native procurement works with both building slots occupied")
			var cards: Array = worlds[world]["cards"]
			check(cards.size() == 4 and cards.all(func(id): return ConquestGalaxy.native_match(lib.get_card(id), entry)), entry + " recruits its own units")
	for faction in 3:
		check(campaign.eligible_commanders(faction, "Kamino").has("TS26_006"), "Kamino recruits Rex for any occupier")
		check(campaign.eligible_commanders(faction, "Tatooine").has("HMW_018"), "Tatooine recruits the Tusken leader")
		check(campaign.eligible_commanders(faction, "Kashyyyk").has("HMW_009"), "Kashyyyk recruits Chewbacca")
		var geonosis := campaign.eligible_commanders(faction, "Geonosis")
		check(geonosis.has("KYB_005") and not geonosis.has("TWI_005") and not geonosis.has("HMW_008"),
			"local droid commander replaces dead Clone Wars leaders")
	check(not ConquestGalaxy.era_unit(lib.get_card("TWI_034")) and not ConquestGalaxy.era_unit(lib.get_card("LOF_130")),
		"dead Clone Wars characters and ancient characters are outside the recruitment roster")

	var cfg := {
		"rules": RuleSet.campaign(),
		"first": 0,
		"players": [
			{"leader": "KYB_005", "base": "SOR_023", "deck": ["TWI_228", "TWI_228", "TWI_228", "TWI_228", "TWI_228", "TWI_228"], "ai": false,
				"preplaced": [{"id": "TWI_228", "arena": "space"}, {"id": "SOR_095", "arena": "ground"}]},
			{"leader": "", "base": "SOR_025", "deck": ["SOR_095", "SOR_095", "SOR_095", "SOR_095", "SOR_095", "SOR_095"], "ai": true}
		]
	}
	cfg["rules"].allow_mulligan = false
	var battle := Match.new()
	battle.setup(lib, cfg)
	var droid: CardInst = battle.players[0].units[0]
	var trooper: CardInst = battle.players[0].units[1]
	battle.submit_choice(battle.pending["options"].slice(0, 2))
	AiBot.choose(battle)
	var leader: CardInst = battle.players[0].leader
	check(battle.do_action({"a": "ability", "uid": leader.uid, "idx": 0}) and battle.pending["options"] == [droid.uid]
		and not battle.submit_choice([trooper.uid]) and battle.submit_choice([droid.uid]) and droid.upgrades.size() == 1,
		"Kalani can give Experience to a Droid in the real battle engine")


func test_voluntary_withdrawal() -> void:
	var run := ConquestRun.start(lib, 0, 8, 81)
	for side in run.state["factions"]:
		side["next_order"] = 9999
	var worlds: Dictionary = run.state["worlds"]
	worlds["Corellia"]["owner"] = 0
	var task := run.fleet(0)
	task["world"] = "Corellia"
	run._begin_battle(0, "Naboo")
	var key := run.player_battle()
	check(run.withdrawal_plan(key) == ["Corellia"], "an invading commander can return to the departure planet")
	var cards: Array = task["cards"].duplicate()
	var loss: String = cards.pop_front()
	var m := Match.new()
	m.setup(lib, run.battle_config(key, true))
	_ready_to_act(m)
	m.roster_losses[0].append(loss)
	m.deal_damage(m.players[0].base, 16, null)
	var result := run.withdraw_player(key, m)
	check(result.get("destination") == "Corellia" and not result["leader_lost"] and result["losses"] == 1
		and task["cards"] == cards and task["command_damage"] == 16 and task["leader_alive"],
		"retreat keeps surviving cards and existing commander wounds")
	check(task["world"] == "Naboo" and task["route"] == ["Corellia"] and worlds["Naboo"]["owner"] == -1,
		"retreat travels through hyperspace without occupying the target")
	check(run.finish_battle(key, m, true).is_empty(), "settled retreat cannot be paid or processed twice")
	run.tick(60)
	check(run.idle(task) and task["world"] == "Corellia" and task["command_damage"] == 6,
		"returning fleet can rest, reinforce and move again")

	task["last_world"] = "Coruscant"
	run._begin_battle(1, "Corellia")
	key = run.player_battle()
	check(run.withdrawal_plan(key) == ["Coruscant"], "the defender retreats to its previous friendly planet")
	worlds["Coruscant"]["owner"] = 1
	check(run.withdrawal_plan(key).is_empty(), "a fleet cannot withdraw when every other friendly planet has fallen")
	worlds["Naboo"]["owner"] = 0
	m = Match.new()
	m.setup(lib, run.battle_config(key, true))
	_ready_to_act(m)
	result = run.withdraw_player(key, m)
	check(result.get("destination") == "Naboo" and worlds["Corellia"]["owner"] == 1
		and task["cards"] == cards and task["leader_alive"],
		"a withdrawing defender yields the planet and falls back to another friendly world when needed")


func _ready_to_act(m: Match) -> void:
	for i in 10:
		if m.can_act(0):
			return
		if m.pending.is_empty():
			AiBot.act(m)
		else:
			AiBot.choose(m)


func test_local_catalogs() -> void:
	var run := ConquestRun.start(lib, 0, 32, 94)
	var worlds: Dictionary = run.state["worlds"]
	for item in [
		[0, "Lothal", ["SOR_180", "SEC_136", "IC27_024", "KYB_007"]],
		[1, "Lothal", ["SOR_050", "SOR_188", "SEC_155"]],
		[0, "Endor", ["SOR_128", "SOR_084", "ASH_143"]],
		[1, "Endor", ["ASH_166", "ASH_034"]],
		[2, "Naboo", ["LOF_192", "SEC_120", "LOF_247"]],
		[2, "Dathomir", ["LOF_059", "LOF_160", "ASH_050"]],
		[2, "Bespin", ["LAW_108", "SOR_063"]],
		[2, "Mandalore", ["SHD_258"]],
		[2, "Tatooine", ["HMW_221", "HMW_224"]],
		[2, "Geonosis", ["TWI_081", "TWI_230"]],
		[2, "Kamino", ["TWI_241", "TWI_111"]],
	]:
		var faction: int = item[0]
		var world: String = item[1]
		worlds[world]["owner"] = faction
		worlds[world]["cards"] = []
		run.state["factions"][faction]["credits"] = 500
		var catalog := run.factory_catalog(faction, world, true)
		var missing: Array = item[2].filter(func(id): return not id in catalog)
		check(missing.is_empty(), "%s offers the appropriate local printings (missing %s)" % [world, str(missing)])
		var id: String = item[2][0]
		check(run.manufacture(faction, world, id, true) and worlds[world]["cards"] == [id],
			"local purchase produces the selected card on " + world)
	check("LAW_003" in run.eligible_commanders(0, "Lothal")
		and not "LAW_003" in run.eligible_commanders(1, "Lothal")
		and "HMW_014" in run.eligible_commanders(1, "Endor"), "faction-specific commanders follow the roster")
	check("KYB_006" in run.eligible_commanders(2, "Tatooine") and "KYB_008" in run.eligible_commanders(2, "Dathomir"),
		"local Jawa and Nightsister commanders are commissionable")
	check(ConquestGalaxy.territory_icon("Endor", 0) == "endor-empire"
		and ConquestGalaxy.territory_icon("Lothal", 1) == "lothal-rebels", "planet insignia follow the occupier")


func test_final_capture() -> void:
	var run := ConquestRun.start(lib, 0, 8, 67)
	for name in run.state["worlds"]:
		run.state["worlds"][name]["owner"] = 0 if name != "Corellia" else -1
	run._begin_battle(1, "Mandalore")
	run._begin_battle(0, "Corellia")
	var keys: Array = run.state["battles"].keys()
	var incoming := Match.new()
	incoming.setup(lib, run.battle_config(keys[0], true))
	incoming.set_winner(1, "Invading fleet won")
	var final_attack := Match.new()
	final_attack.setup(lib, run.battle_config(keys[1], true))
	final_attack.set_winner(0, "Last planet captured")
	run.finish_battle(keys[1], final_attack, true)
	check(run.state["status"] == "won" and run.player_battle().is_empty(), "final capture closes the battle queue")
	check(run.finish_battle(keys[0], incoming, true).is_empty() and run.state["worlds"]["Mandalore"]["owner"] == 0,
		"a queued invasion cannot alter ownership after the final capture")
