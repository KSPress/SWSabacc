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
	test_command_training()
	test_command_retreat()
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
	var tie: CardInst = ps.units[0]
	check(ps.base.max_hp() == 40 and ps.leader.max_hp() == 40 and ps.resources.size() == 4,
		"training health and starting resources persist across save and setup")
	check(tie.id == "SOR_231" and not tie.exhausted and tie.shield_count() == 1
		and tie.upgrades.any(func(up): return up.id == "SOR_121") and tie.power() > tie.printed_power(),
		"opening unit starts ready with attached equipment, Experience and Shield")
	check(m.deal_damage(ps.base, 5, null) == 0 and ps.base.damage == 0, "trained command shield absorbs the first hit")
	m.deal_damage(ps.base, 16, null)
	m._deploy_leader(0)
	check(ps.leader.in_play() and ps.leader.remaining_hp() == 24, "deployment retains command wounds")
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
	check(m.players[0].base.max_hp() == 30 and m.players[0].base.data.get("conquest_command", false),
		"untrained fleet command starts at 30 HP")
	m.deal_damage(m.players[0].base, 30, null)
	m._state_based()
	check(m.winner == 1 and m.roster_leader_lost[0], "undeployed commander death ends the match")
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
	m._deploy_leader(0)
	m.defeat(m.players[0].leader)
	m._state_based()
	check(m.winner == 1 and m.roster_leader_lost[0], "direct defeat of the deployed commander also ends battle")


func test_era_production() -> void:
	var campaign := ConquestRun.start(lib, 0, 16, 73)
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
