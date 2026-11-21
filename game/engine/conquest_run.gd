class_name ConquestRun
extends RefCounted

const GALAXY := preload("res://engine/conquest_galaxy.gd")
const SIZES := [8, 16, 32]
const FLEET_LIMIT := 30
const RESERVE_LIMIT := 24
const MIN_FLEET := 8
const INCOME_PERIOD := 12.0
const INCOME_PER_WORLD := 8
const WIN_REWARD := 35
const MIN_TRAVEL := 3.0
const SPEED := 25.0
const BOT_ORDER_PERIOD := 16.0
const BOT_REBUILD_TIME := 28.0
const PRICES := {"garrison": 65, "dockyard": 55, "troops": 25, "ships": 35, "commission": 40}
const MILESTONES := [4, 8, 12]
const FACILITIES := {
	"vehicles": ["Vehicle Depot", 55], "fighters": ["Hangar Bay", 55], "troopers": ["Barracks", 50],
	"droids": ["Droid Depot", 50], "frigates": ["Dockyard", 65], "capital": ["Space Station", 80],
	"fortification": ["Base Fortification", 65], "garrison": ["Garrison", 65],
	"orbital": ["Defense Fleet", 80], "satellite": ["Satellite Network", 45],
}
const FACTORIES := ["vehicles", "fighters", "troopers", "droids", "frigates", "capital"]
const PROBE_PRICE := 20

var state: Dictionary
var lib: CardLibrary
var _pools := {}


func _init(library: CardLibrary, data: Dictionary) -> void:
	lib = library
	state = data
	if not state.is_empty():
		_upgrade_save()


static func start(library: CardLibrary, player: int, size: int, seed_value: int, leader := "") -> ConquestRun:
	var data := {"player": player, "size": size, "seed": seed_value, "time": 0.0, "next_income": INCOME_PERIOD,
		"serial": 0, "worlds": {}, "factions": [], "battles": {}, "shipments": [], "probes": [], "intel": [{}, {}, {}], "status": "active",
		"report": "Select a world and send your fleet along a hyperspace route."}
	var run := ConquestRun.new(library, data)
	for name in GALAXY.WORLDS.keys().slice(0, size):
		var home := GALAXY.FACTIONS.find_custom(func(faction): return faction["home"] == name)
		data["worlds"][name] = {"owner": home, "facilities": ["garrison"] if home >= 0 else [], "orbital_cards": [], "probes": 0,
			"cards": run._recruit(name, home, false, 7 if home >= 0 else 6) + run._recruit(name, home, true, 2)}
	for faction in GALAXY.FACTIONS.size():
		var home: String = GALAXY.FACTIONS[faction]["home"]
		var cards := run._recruit(home, faction, false, 13) + run._recruit(home, faction, true, 8)
		var commander: String = GALAXY.FACTIONS[faction]["leader"]
		if faction == player and leader in GALAXY.leader_variants(library, faction, "", true):
			commander = leader
		data["factions"].append({"credits": 120, "next_order": 12.0 + faction * 2.0, "milestones": [],
			"fleet": run._new_fleet(home, cards, commander), "extra_fleets": []})
	return run


func _new_fleet(world: String, cards: Array, leader := "") -> Dictionary:
	return {"world": world, "cards": cards, "leader": leader, "leader_alive": not leader.is_empty(),
		"route": [], "arrival": 0.0, "departed": 0.0, "engagement": ""}


func _upgrade_save() -> void:
	if not state.has("probes"):
		state["probes"] = []
		state["intel"] = [{}, {}, {}]
	for planet in state["worlds"].values():
		if not planet.has("facilities"):
			planet["facilities"] = []
			if planet.get("garrison", false):
				planet["facilities"].append("garrison")
			if planet.get("dockyard", false):
				planet["facilities"].append("frigates")
			planet["orbital_cards"] = []
			planet["probes"] = 0
	for i in state["factions"].size():
		var side: Dictionary = state["factions"][i]
		if not side.has("extra_fleets"):
			side["extra_fleets"] = []
			side["milestones"] = []
			side["fleet"]["leader"] = GALAXY.FACTIONS[i]["leader"]
			side["fleet"]["leader_alive"] = side.get("leader_alive", true)
		# JSON loads numbers as floats and Array membership is type-sensitive.
		side["milestones"] = side["milestones"].map(func(value): return int(value))


func _next_seed() -> int:
	state["serial"] = int(state["serial"]) + 1
	return int(state["seed"]) + int(state["serial"]) * 7919


func _recruit(world: String, faction: int, ships: bool, amount: int) -> Array:
	var specialty: String = GALAXY.SPECIALTIES.get(world, GALAXY.FACTIONS[faction]["trait"] if faction >= 0 else "")
	var key := "%s/%s" % [specialty, ships]
	if not _pools.has(key):
		var pool: Array = []
		var fallback: Array = []
		for id in lib.cards:
			var card: Dictionary = lib.cards[id]
			if card.get("type") != "unit" or card.get("custom", false) or card.get("implemented") not in ["full", "vanilla"]:
				continue
			if (card.get("arena") == "space") != ships or int(card.get("cost", 0)) > (6 if ships else 4):
				continue
			if card.get("set") not in CardLibrary.BOOSTER_SETS:
				continue
			if specialty in card.get("traits", []):
				pool.append(id)
			if not ("heroism" in card.get("aspects", []) or "villainy" in card.get("aspects", [])):
				fallback.append(id)
		_pools[key] = pool if not pool.is_empty() else fallback
	var choices: Array = _pools[key]
	if choices.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = _next_seed()
	var result: Array = []
	for i in amount:
		result.append(choices[rng.randi_range(0, choices.size() - 1)])
	return result


func fleet(faction: int, index := 0) -> Dictionary:
	return fleets(faction)[index]


func fleets(faction: int) -> Array:
	var side: Dictionary = state["factions"][faction]
	return [side["fleet"]] + side["extra_fleets"]


func neighbors(world: String) -> Array:
	var found := []
	for lane in GALAXY.LANES:
		if lane[0] == world and state["worlds"].has(lane[1]):
			found.append(lane[1])
		elif lane[1] == world and state["worlds"].has(lane[0]):
			found.append(lane[0])
	return found


func path(faction: int, origin: String, destination: String, friendly_only := false) -> Array:
	if origin == destination or not state["worlds"].has(destination) or not state["worlds"].has(origin):
		return []
	if friendly_only and int(state["worlds"][destination]["owner"]) != faction:
		return []
	var frontier := [origin]
	var previous := {origin: ""}
	while not frontier.is_empty():
		var from: String = frontier.pop_front()
		for to in neighbors(from):
			if previous.has(to) or (to != destination and int(state["worlds"][to]["owner"]) != faction):
				continue
			previous[to] = from
			if to == destination:
				var route := [destination]
				while previous[route[0]] != origin:
					route.push_front(previous[route[0]])
				return route
			frontier.append(to)
	return []


func travel_duration(from: String, to: String) -> float:
	return maxf(MIN_TRAVEL, GALAXY.lane_distance(from, to) / SPEED)


func _depart(traveler: Dictionary) -> void:
	traveler["departed"] = state["time"]
	traveler["arrival"] = float(state["time"]) + travel_duration(traveler["world"], traveler["route"][0])


func travel_progress(traveler: Dictionary) -> float:
	var time := float(state["time"]) - float(traveler["departed"])
	return clampf(time / maxf(0.01, float(traveler["arrival"]) - float(traveler["departed"])), 0.0, 1.0)


func order(faction: int, to: String, index := 0) -> bool:
	var task := fleet(faction, index)
	if state["status"] != "active" or not idle(task) or task["cards"].is_empty():
		return false
	var route := path(faction, task["world"], to)
	if route.is_empty():
		return false
	task["route"] = route
	_depart(task)
	return true


func idle(task: Dictionary) -> bool:
	return not task["world"].is_empty() and task["route"].is_empty() and task["engagement"].is_empty()


func _factory(world: String) -> String:
	for item in state["worlds"][world]["facilities"]:
		if item in FACTORIES:
			return item
	return ""


func _can_manage(faction: int, world: String) -> bool:
	return state["status"] == "active" and int(state["worlds"][world]["owner"]) == faction and not _contested(world)


func price(item: String) -> int:
	if item in FACILITIES:
		return FACILITIES[item][1]
	if item == "probe":
		return PROBE_PRICE
	return PRICES.get(item, 25)


func can_buy(faction: int, world: String, item: String) -> bool:
	var site: Dictionary = state["worlds"][world]
	if not _can_manage(faction, world) or int(state["factions"][faction]["credits"]) < price(item):
		return false
	if item in FACILITIES:
		return site["facilities"].size() < 2 and not item in site["facilities"] and (not item in FACTORIES or _factory(world).is_empty())
	match item:
		"produce": return not _factory(world).is_empty() and site["cards"].size() < RESERVE_LIMIT
		"troops": return "garrison" in site["facilities"] and site["cards"].size() < 12
		"repair_orbit": return "orbital" in site["facilities"] and site["orbital_cards"].size() < 10
		"probe": return int(site["probes"]) < 3
		"commission": return fleet(faction)["world"].is_empty() and site["cards"].size() >= MIN_FLEET
	return false


func buy(faction: int, world: String, item: String) -> bool:
	if not can_buy(faction, world, item):
		return false
	var site: Dictionary = state["worlds"][world]
	var funds: Dictionary = state["factions"][faction]
	if item == "produce":
		var cards := _produce(world, faction, _factory(world), mini(4, RESERVE_LIMIT - site["cards"].size()))
		if cards.is_empty():
			return false
		site["cards"].append_array(cards)
	funds["credits"] = int(funds["credits"]) - price(item)
	if item in FACILITIES:
		site["facilities"].append(item)
	match item:
		"garrison", "troops":
			site["cards"].append_array(_recruit(world, faction, false, mini(6 if item == "garrison" else 4, RESERVE_LIMIT - site["cards"].size())))
		"orbital", "repair_orbit":
			site["orbital_cards"].append_array(_recruit(world, faction, true, mini(8, 10 - site["orbital_cards"].size())))
		"probe":
			site["probes"] = int(site["probes"]) + 1
		"commission":
			var primary := fleet(faction)
			var commander: String = primary["leader"] if primary["leader_alive"] else ""
			funds["fleet"] = _new_fleet(world, site["cards"].slice(0, MIN_FLEET), commander)
			site["cards"] = site["cards"].slice(MIN_FLEET)
	return true


func _produce(world: String, faction: int, factory: String, amount: int) -> Array:
	var tags: Array = {"vehicles": ["vehicle"], "fighters": ["fighter"], "troopers": ["trooper"],
		"droids": ["droid"], "frigates": ["frigate", "transport", "capital ship"], "capital": ["capital ship"]}[factory]
	var ships := factory in ["fighters", "frigates", "capital"]
	var specialty: String = GALAXY.SPECIALTIES.get(world, GALAXY.FACTIONS[faction]["trait"])
	var pool := []
	var local := []
	var thematic := []
	for id in lib.cards:
		var data := lib.get_card(id)
		if data.get("type") != "unit" or data.get("set") not in CardLibrary.BOOSTER_SETS or data.get("implemented") not in ["full", "vanilla"]:
			continue
		if (data.get("arena") == "space") != ships:
			continue
		var traits: Array = data["traits"]
		if not tags.any(func(tag): return tag in traits):
			continue
		if factory == "frigates" and not ("frigate" in traits or "frigate" in data["name"].to_lower()):
			continue
		pool.append(id)
		if specialty in traits:
			local.append(id)
		elif GALAXY.FACTIONS[faction]["trait"] in traits:
			thematic.append(id)
	var choices := local if not local.is_empty() else (thematic if not thematic.is_empty() else pool)
	if choices.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = _next_seed()
	var cards := []
	for i in amount:
		cards.append(choices[rng.randi_range(0, choices.size() - 1)])
	return cards


func available_milestone(faction: int) -> int:
	var held := 0
	for planet in state["worlds"].values():
		if int(planet["owner"]) == faction:
			held += 1
	for milestone in MILESTONES:
		if held >= milestone and not milestone in state["factions"][faction]["milestones"]:
			return milestone
	return 0


func eligible_commanders(faction: int, world: String) -> Array:
	var existing := fleets(faction).map(func(task): return lib.get_card(task["leader"]).get("name", ""))
	return GALAXY.leader_variants(lib, faction, world).filter(func(id): return not lib.get_card(id)["name"] in existing)


func build_commander(faction: int, world: String, leader: String) -> bool:
	var milestone := available_milestone(faction)
	var funds: Dictionary = state["factions"][faction]
	if milestone == 0 or not _can_manage(faction, world) or int(funds["credits"]) < price("commission") or not leader in eligible_commanders(faction, world):
		return false
	var site: Dictionary = state["worlds"][world]
	if site["cards"].size() < MIN_FLEET:
		return false
	funds["credits"] = int(funds["credits"]) - price("commission")
	funds["milestones"].append(milestone)
	funds["extra_fleets"].append(_new_fleet(world, site["cards"].slice(0, MIN_FLEET), leader))
	site["cards"] = site["cards"].slice(MIN_FLEET)
	return true


func visible_to(faction: int, world: String) -> bool:
	var site: Dictionary = state["worlds"][world]
	if int(site["owner"]) == faction or float(state["intel"][faction].get(world, 0.0)) > float(state["time"]):
		return true
	for neighbor in neighbors(world):
		var nearby: Dictionary = state["worlds"][neighbor]
		if int(nearby["owner"]) == faction and "satellite" in nearby["facilities"]:
			return true
	return false


func launch_probe(faction: int, origin: String, target: String) -> bool:
	if not _can_manage(faction, origin) or int(state["worlds"][origin]["probes"]) <= 0:
		return false
	var route := path(faction, origin, target)
	if route.is_empty() or int(state["worlds"][target]["owner"]) == faction:
		return false
	state["worlds"][origin]["probes"] = int(state["worlds"][origin]["probes"]) - 1
	var probe := {"faction": faction, "world": origin, "route": route}
	_depart(probe)
	state["probes"].append(probe)
	return true


func _move_probes() -> bool:
	var changed := false
	for probe in state["probes"].duplicate():
		if float(probe["arrival"]) > float(state["time"]):
			continue
		probe["world"] = probe["route"].pop_front()
		var world: String = probe["world"]
		var planet: Dictionary = state["worlds"][world]
		var faction := int(probe["faction"])
		var owner := int(planet["owner"])
		if probe["route"].is_empty() or owner != faction:
			var intercepted: bool = not planet["orbital_cards"].is_empty() or (owner >= 0 and _defender_index(owner, world) >= 0)
			state["intel"][faction][world] = float(state["time"]) + (15.0 if intercepted else 60.0)
			if faction == int(state["player"]):
				state["report"] = "%s · %s" % [world, "Probe intercepted · 15s of intel" if intercepted else "Probe active · 60s of intel"]
			state["probes"].erase(probe)
		else:
			_depart(probe)
		changed = true
	return changed


func transfer(faction: int, origin: String, ids: Array, index := 0) -> bool:
	var task := fleet(faction, index)
	var defense: Dictionary = state["worlds"][origin]
	if state["status"] != "active" or not idle(task) or int(defense["owner"]) != faction or _contested(origin):
		return false
	if ids.is_empty() or task["cards"].size() + ids.size() > FLEET_LIMIT:
		return false
	var remaining: Array = defense["cards"].duplicate()
	for id in ids:
		if not id in remaining:
			return false
		remaining.erase(id)
	var route := path(faction, origin, task["world"], true)
	if origin != task["world"] and route.is_empty():
		return false
	defense["cards"] = remaining
	if route.is_empty():
		task["cards"].append_array(ids)
	else:
		var shipment := {"faction": faction, "fleet": index, "world": origin, "cards": ids.duplicate(), "route": route}
		_depart(shipment)
		state["shipments"].append(shipment)
	return true


func _deliver(shipment: Dictionary) -> void:
	var faction := int(shipment["faction"])
	var task := fleet(faction, int(shipment.get("fleet", 0)))
	var world: String = shipment["world"]
	var cards: Array = shipment["cards"]
	if idle(task) and task["world"] == world:
		var room := maxi(0, FLEET_LIMIT - task["cards"].size())
		task["cards"].append_array(cards.slice(0, room))
		cards = cards.slice(room)
	state["worlds"][world]["cards"].append_array(cards)
	state["shipments"].erase(shipment)


func _contested(world: String) -> bool:
	return state["battles"].values().any(func(battle): return battle["world"] == world)


func tick(delta: float) -> bool:
	if state["status"] != "active":
		return false
	state["time"] = float(state["time"]) + delta
	var changed := false
	while float(state["time"]) >= float(state["next_income"]):
		state["next_income"] = float(state["next_income"]) + INCOME_PERIOD
		for world in state["worlds"].values():
			var owner := int(world["owner"])
			if owner >= 0:
				var side: Dictionary = state["factions"][owner]
				side["credits"] = int(side["credits"]) + INCOME_PER_WORLD
		changed = true
	for faction in GALAXY.FACTIONS.size():
		for index in fleets(faction).size():
			var task := fleet(faction, index)
			if task["route"].is_empty() or float(task["arrival"]) > float(state["time"]):
				continue
			var next: String = task["route"][0]
			if _contested(next):
				continue
			task["route"].pop_front()
			if int(state["worlds"][next]["owner"]) != faction:
				task["route"].clear()
				_begin_battle(faction, next, index)
			else:
				task["world"] = next
				if not task["route"].is_empty():
					_depart(task)
			changed = true
	for shipment in state["shipments"].duplicate():
		if float(shipment["arrival"]) > float(state["time"]):
			continue
		if _contested(shipment["route"][0]):
			continue
		var next: String = shipment["route"].pop_front()
		var faction := int(shipment["faction"])
		if int(state["worlds"][next]["owner"]) != faction:
			if int(state["worlds"][shipment["world"]]["owner"]) != faction:
				shipment["world"] = _owned_world(faction)
			if not shipment["world"].is_empty():
				_deliver(shipment)
			else:
				state["shipments"].erase(shipment)
		else:
			shipment["world"] = next
			if shipment["route"].is_empty():
				_deliver(shipment)
			else:
				_depart(shipment)
		changed = true
	for faction in GALAXY.FACTIONS.size():
		if faction == int(state["player"]):
			continue
		var side: Dictionary = state["factions"][faction]
		if float(side["next_order"]) <= float(state["time"]):
			side["next_order"] = float(state["time"]) + BOT_ORDER_PERIOD + faction * 0.75
			if available_milestone(faction):
				for world in state["worlds"]:
					if int(state["worlds"][world]["owner"]) != faction:
						continue
					var options := eligible_commanders(faction, world)
					if not options.is_empty() and build_commander(faction, world, options[0]):
						break
			for index in fleets(faction).size():
				_bot_order(faction, index)
			changed = true
	return _move_probes() or changed


func _owned_world(faction: int) -> String:
	for world in state["worlds"]:
		if int(state["worlds"][world]["owner"]) == faction:
			return world
	return ""


func _bot_order(faction: int, index: int) -> void:
	var task := fleet(faction, index)
	if task["world"].is_empty():
		if index > 0:
			return
		for world in state["worlds"]:
			if buy(faction, world, "commission"):
				return
			if buy(faction, world, "garrison") or buy(faction, world, "troops"):
				return
		return
	if not idle(task):
		return
	var origin: String = task["world"]
	if int(state["worlds"][origin]["owner"]) == faction and task["cards"].size() < 18:
		var reserve: Array = state["worlds"][origin]["cards"]
		if reserve.size() < 8:
			buy(faction, origin, "garrison")
			buy(faction, origin, "troops")
			buy(faction, origin, "produce")
		transfer(faction, origin, reserve.slice(0, mini(18 - task["cards"].size(), maxi(0, reserve.size() - 3))), index)
	var goal := ""
	var best := INF
	for world in state["worlds"]:
		var owner := int(state["worlds"][world]["owner"])
		if owner == faction or _contested(world):
			continue
		var route := path(faction, origin, world)
		if route.is_empty():
			continue
		var score := route.size() * 4.0 + travel_duration(origin, route[0]) * 0.2 + (1.8 if owner >= 0 else 0.0)
		if score < best:
			best = score
			goal = world
	if not goal.is_empty() and task["cards"].size() >= 5:
		order(faction, goal, index)


func _defender_index(faction: int, world: String) -> int:
	return fleets(faction).find_custom(func(task): return idle(task) and task["world"] == world)


func _begin_battle(attacker: int, world: String, index := 0) -> void:
	var defense: Dictionary = state["worlds"][world]
	var defender := int(defense["owner"])
	var defense_index := _defender_index(defender, world) if defender >= 0 else -1
	var field_fleet := defense_index >= 0
	var seed_value := _next_seed()
	var key := str(int(state["serial"]))
	state["battles"][key] = {"attacker": attacker, "defender": defender, "world": world,
		"fleet_defense": field_fleet, "defense_index": defense_index, "attack_index": index,
		"orbital": not field_fleet and not defense["orbital_cards"].is_empty(), "seed": seed_value}
	fleet(attacker, index)["engagement"] = key
	if field_fleet:
		fleet(defender, defense_index)["engagement"] = key
	if int(state["player"]) in [attacker, defender]:
		state["report"] = "Battle for %s ready." % world


func player_battle() -> String:
	for key in state["battles"]:
		var battle: Dictionary = state["battles"][key]
		if int(state["player"]) in [int(battle["attacker"]), int(battle["defender"])]:
			return key
	return ""


func battle_config(key: String, human: bool) -> Dictionary:
	var battle: Dictionary = state["battles"][key]
	var attacker := int(battle["attacker"])
	var defender := int(battle["defender"])
	var planet: Dictionary = state["worlds"][battle["world"]]
	var assault := fleet(attacker, int(battle.get("attack_index", 0)))
	var defending := fleet(defender, int(battle.get("defense_index", 0))) if battle["fleet_defense"] else {}
	var orbit: bool = battle.get("orbital", false)
	var defense_cards: Array = defending["cards"] if battle["fleet_defense"] else planet["orbital_cards" if orbit else "cards"]
	var attack_cards: Array = assault["cards"]
	if orbit:
		attack_cards = attack_cards.filter(func(id):
			var card := lib.get_card(id)
			return card.get("arena") == "space" or card.has("pilot"))
	var attacker_spec := _battle_side(attacker, attack_cards, assault, 20)
	var defender_hp := 20 if battle["fleet_defense"] or orbit else (18 if "garrison" in planet["facilities"] else 12)
	if "fortification" in planet["facilities"]:
		defender_hp += 6
	var defender_spec := _battle_side(defender, defense_cards, defending, defender_hp)
	var human_is_defender := human and defender == int(state["player"])
	var players := [defender_spec, attacker_spec] if human_is_defender else [attacker_spec, defender_spec]
	players[0]["ai"] = not human
	var rules := RuleSet.campaign()
	rules.name = "conquest"
	rules.starting_hand = 4
	rules.allow_mulligan = false
	rules.deck_out_damage = 2
	if orbit:
		rules.arenas = ["space"]
	return {"rules": rules, "players": players, "seed": int(battle["seed"]),
		"first": 1 if human_is_defender else 0, "track_roster_losses": true}


func _battle_side(faction: int, cards: Array, task: Dictionary, hp: int) -> Dictionary:
	var side: Dictionary = GALAXY.FACTIONS[faction] if faction >= 0 else {}
	var leader := ""
	if task.get("leader_alive", false):
		leader = task["leader"]
	return {"name": side.get("name", "Local militia"), "leader": leader, "base": side.get("base", "SOR_025"),
		"deck": cards.duplicate(), "ai": true, "base_hp": hp, "profile": "defensive" if task.is_empty() else "tempo"}


func finish_battle(key: String, match_game: Match, human: bool) -> Dictionary:
	if not state["battles"].has(key) or match_game.winner < 0:
		return {}
	var battle: Dictionary = state["battles"][key]
	var attacker := int(battle["attacker"])
	var defender := int(battle["defender"])
	var world: String = battle["world"]
	var attacker_side := 1 if human and defender == int(state["player"]) else 0
	var attacker_fleet := fleet(attacker, int(battle.get("attack_index", 0)))
	var planet: Dictionary = state["worlds"][world]
	var defense := fleet(defender, int(battle.get("defense_index", 0))) if battle["fleet_defense"] else planet
	_apply_losses(attacker_fleet, match_game, attacker_side)
	_apply_losses(defense, match_game, 1 - attacker_side, "orbital_cards" if battle.get("orbital", false) else "cards")
	var captured := match_game.winner == attacker_side
	var victor := attacker if captured else (defender if match_game.winner == 1 - attacker_side else -1)
	if captured:
		planet["owner"] = attacker
		var refuge := _owned_world(defender) if defender >= 0 else ""
		if battle["fleet_defense"]:
			defense["world"] = refuge
		if defender >= 0:
			for task in fleets(defender):
				if idle(task) and task["world"] == world:
					task["world"] = refuge
		if not refuge.is_empty():
			state["worlds"][refuge]["cards"].append_array(planet["cards"] + planet["orbital_cards"])
		planet["cards"] = []
		planet["orbital_cards"] = []
		planet["facilities"] = []
		planet["probes"] = 0
		attacker_fleet["world"] = world
	elif int(state["worlds"][attacker_fleet["world"]]["owner"]) != attacker:
		attacker_fleet["world"] = _owned_world(attacker)
	if victor >= 0:
		var side: Dictionary = state["factions"][victor]
		side["credits"] = int(side["credits"]) + WIN_REWARD
	if not captured and attacker != int(state["player"]):
		var rival: Dictionary = state["factions"][attacker]
		rival["next_order"] = maxf(float(rival["next_order"]), float(state["time"]) + BOT_REBUILD_TIME)
	for task in [attacker_fleet, defense] if battle["fleet_defense"] else [attacker_fleet]:
		task["engagement"] = ""
		if task["cards"].is_empty():
			task["world"] = ""
	state["battles"].erase(key)
	var player := int(state["player"])
	var losses: int = match_game.roster_losses[0].size() if human else 0
	var reply := {"world": world, "captured": captured, "losses": losses, "credits": WIN_REWARD if victor == player else 0}
	if human:
		state["report"] = "%s · %d cards lost%s" % [world, losses, " · +%d credits" % reply["credits"] if reply["credits"] else ""]
	var held: int = state["worlds"].values().filter(func(site): return int(site["owner"]) == player).size()
	if held == state["worlds"].size():
		state["status"] = "won"
	elif held == 0 and fleets(player).all(func(task): return task["world"].is_empty()):
		state["status"] = "lost"
	return reply


func _apply_losses(force: Dictionary, match_game: Match, side: int, roster := "cards") -> void:
	for id in match_game.roster_losses[side]:
		force[roster].erase(id)
	if force.has("leader_alive") and match_game.roster_leader_lost[side]:
		force["leader_alive"] = false
