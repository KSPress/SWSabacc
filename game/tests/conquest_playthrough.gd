extends SceneTree
## Play full strategy campaigns with live rival orders and actual tactical AI.
## The scripted player uses the same travel, production and battle APIs as the UI.

var lib := CardLibrary.new()


func _init() -> void:
	lib.load_file("res://ip/data/cards.json")
	var successes := 0
	for scenario in [[8, 2, 119, "SEC_002"], [16, 1, 72, "JTL_012"], [32, 0, 85, "JTL_006"]]:
		successes += int(play(scenario[0], scenario[1], scenario[2], scenario[3]))
	print("FULL CONQUEST: %d/3 campaigns reached victory" % successes)
	quit(0 if successes == 3 else 1)


func play(size: int, player: int, seed_value: int, leader: String) -> bool:
	var run := ConquestRun.start(lib, player, size, seed_value, leader)
	var battles := 0
	var victories := 0
	var defenses := 0
	var casualties := 0
	var income_intervals := 0
	var saves := 0
	for turn in 3600:
		if run.state["status"] != "active":
			break
		var old_income: float = run.state["next_income"]
		run.tick(1)
		income_intervals += int(float(run.state["next_income"]) > old_income)
		for key in run.state["battles"].keys():
			var encounter: Dictionary = run.state["battles"][key]
			var human := player in [int(encounter["attacker"]), int(encounter["defender"])]
			var config := run.battle_config(key, human)
			config["players"][0]["ai"] = true
			var battle := Match.new()
			battle.setup(lib, config)
			for action in 500:
				if battle.winner >= 0:
					break
				if battle.pending.is_empty():
					AiBot.act(battle)
				else:
					var previous_choices := battle.history.size()
					AiBot.choose(battle)
					if battle.history.size() == previous_choices:
						printerr("Invalid tactical choice in battle for ", encounter["world"], ": ", battle.pending)
						return false
				battle.events.clear()
			if battle.winner < 0:
				printerr("Tactical battle stalled at ", encounter["world"])
				return false
			var result := run.finish_battle(key, battle, human)
			battles += 1
			if human:
				victories += int(battle.winner == 0)
				defenses += int(int(encounter["defender"]) == player)
				casualties += int(result["losses"])
		if turn % 17 == 15:
			run = ConquestRun.new(lib, JSON.parse_string(JSON.stringify(run.state)))
			saves += 1
		if turn % 3 == 0 and run.state["status"] == "active":
			give_orders(run, player)
		var held := owned(run, player).size()
		if (run.state["status"] == "won") != (held == size):
			printerr("Victory disagrees with planet ownership")
			return false
	var held := owned(run, player).size()
	print("%d worlds · %s · %d/%d planets · %d battles · %d player victories · %d defenses · %d cards lost · %d income ticks · %d reloads · milestones %s" % [
		size, run.state["status"], held, size, battles, victories, defenses, casualties, income_intervals, saves,
		str(run.state["factions"][player]["milestones"])])
	return run.state["status"] == "won"


func owned(run: ConquestRun, player: int) -> Array:
	return run.state["worlds"].keys().filter(func(world): return int(run.state["worlds"][world]["owner"]) == player)


func give_orders(run: ConquestRun, player: int) -> void:
	var planets := owned(run, player)
	var fleets := run.fleets(player)
	for world in planets:
		if not run.available_milestone(player):
			break
		var leaders := run.eligible_commanders(player, world)
		if not leaders.is_empty():
			run.build_commander(player, world, leaders[0])
	if run.fleet(player)["world"].is_empty():
		for world in planets:
			if run.buy(player, world, "commission"):
				break
			run.buy(player, world, "garrison")
			run.buy(player, world, "troops")
	for index in fleets.size():
		var fleet := run.fleet(player, index)
		if not run.idle(fleet):
			continue
		var origin: String = fleet["world"]
		if origin in planets:
			var site: Dictionary = run.state["worlds"][origin]
			run.buy(player, origin, "garrison")
			run.buy(player, origin, "fighters")
			var ships: int = fleet["cards"].filter(func(id): return lib.get_card(id).get("arena") == "space").size()
			if ships < 9:
				run.buy(player, origin, "produce")
			if site["cards"].size() < 12 and fleet["cards"].size() < 26:
				run.buy(player, origin, "troops")
			var take_count := mini(ConquestRun.FLEET_LIMIT - int(fleet["cards"].size()), maxi(0, int(site["cards"].size()) - 6))
			var take: Array = site["cards"].slice(0, take_count)
			run.transfer(player, origin, take, index)
		var goal := ""
		var best := INF
		for name in run.state["worlds"]:
			if name in planets or run._contested(name):
				continue
			var route := run.path(player, origin, name)
			if route.is_empty():
				continue
			var site: Dictionary = run.state["worlds"][name]
			var defender := int(site["owner"])
			var stationed := defender >= 0 and run._defender_index(defender, name) >= 0
			var score: float = route.size() * 2.0 + run.travel_duration(origin, route[0]) * 0.2
			score += (5.0 if stationed else 0.0) + site["cards"].size() * 0.16
			if score < best:
				goal = name
				best = score
		if not goal.is_empty() and fleet["cards"].size() >= 13:
			run.order(player, goal, index)
