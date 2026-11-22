class_name ConquestRun
extends RefCounted

const GALAXY := preload("res://engine/conquest_galaxy.gd")
const SIZES := [8, 16, 32]
const FLEET_LIMIT := 30
const FLEET_COPY_LIMIT := 3
const ORBITAL_LIMIT := 10
const RESERVE_LIMIT := 24
const MIN_FLEET := 8
const INCOME_PERIOD := 12.0
const INCOME_PER_WORLD := 8
const WIN_REWARD := 35
const MIN_TRAVEL := 3.0
const SPEED := 25.0
const BOT_ORDER_PERIOD := 16.0
const BOT_REBUILD_TIME := 28.0
const COMMAND_HP := 30
const RECOVERY_PERIOD := 60.0
const RECOVERY_HP := 10
const TRAINING := {
	"health": ["Command endurance (+5 maximum HP)", 55, 2],
	"resources": ["Logistics (+1 starting resource)", 60, 2],
	"command_shield": ["Command shield (blocks one hit)", 45, 1],
	"experience": ["Experience token on each copy", 30, 1],
	"shield": ["Shield token on each copy", 30, 1],
	"equipment": ["Fit permanent equipment to each copy", 45, 1],
	"opening": ["Start with this unit in play", 55, 1],
}
const TRAINING_EQUIPMENT := ["SOR_069", "SEC_070", "SHD_174", "SOR_121"]
const PRICES := {"garrison": 65, "dockyard": 55, "troops": 25, "ships": 35, "commission": 40}
const MILESTONES := [4, 8, 12]
const FACILITIES := {
	"vehicles": ["Vehicle Depot", 55], "fighters": ["Hangar Bay", 55], "troopers": ["Barracks", 50],
	"droids": ["Droid Depot", 50], "frigates": ["Dockyard", 65], "capital": ["Space Station", 80],
	"officers": ["Officers' Quarters", 55], "government": ["Government HQ", 55], "armory": ["Armory", 50],
	"fortification": ["Base Fortification", 65], "garrison": ["Garrison", 65],
	"orbital": ["Defense Fleet", 80], "satellite": ["Satellite Network", 45], "training": ["Training Center", 65],
}
const FACTORIES := ["vehicles", "fighters", "troopers", "droids", "frigates", "capital", "officers", "government", "armory"]
const FACTORY_TRAITS := {
	"vehicles": "vehicle", "fighters": "fighter", "troopers": "trooper", "droids": "droid",
	"capital": "capital ship", "government": "official",
}
const OFFICER_RANKS := [
	"admiral ", "captain ", "colonel ", "commander ", "general ", "lieutenant ", "major ", "moff ",
]
const ARMORY_EXCLUDED := [
	"Darth Revan's Lightsabers", "Darth Maul's Lightsaber", "Qui-Gon Jinn's Lightsaber",
	"Ahsoka's Padawan Lightsaber", "Master's Lightsaber", "Mace Windu's Lightsaber",
]
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
	for name in GALAXY.worlds_for_size(size):
		var home := GALAXY.FACTIONS.find_custom(func(faction): return faction["home"] == name)
		data["worlds"][name] = {"owner": home, "facilities": ["garrison"] if home >= 0 else [], "orbital_cards": [], "probes": 0,
			"cards": run._recruit(name, home, false, 7 if home >= 0 else 6) + run._recruit(name, home, true, 2)}
	for faction in GALAXY.FACTIONS.size():
		var home: String = GALAXY.FACTIONS[faction]["home"]
		var cards := run._recruit(home, faction, false, 13, true)
		cards.append_array(run._recruit(home, faction, true, 8, true, cards))
		var commander: String = GALAXY.FACTIONS[faction]["leader"]
		if faction == player and leader in GALAXY.leader_variants(library, faction, "", true):
			commander = leader
		data["factions"].append({"credits": 120, "next_order": 12.0 + faction * 2.0, "milestones": [],
			"fleet": run._new_fleet(home, cards, commander), "extra_fleets": []})
	return run


func _new_fleet(world: String, cards: Array, leader := "") -> Dictionary:
	return {"world": world, "cards": cards, "leader": leader, "leader_alive": not leader.is_empty(),
		"route": [], "arrival": 0.0, "departed": 0.0, "engagement": "", "retreating": false,
		"command_damage": 0, "recovery": 0.0, "training": {}}


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
		side["retired_leaders"] = side.get("retired_leaders", [])
		for task in fleets(i):
			task.merge({"retreating": false, "command_damage": 0, "recovery": 0.0, "training": {}})
			if not task["leader_alive"]:
				_retire_leader(i, task["leader"])
			var old_deck: Array = task["cards"]
			task["cards"] = _fitted_cards([], old_deck)
			var overflow := _without_cards(old_deck, task["cards"])
			if not overflow.is_empty():
				var home: String = task["world"]
				if not state["worlds"].has(home) or int(state["worlds"][home]["owner"]) != i:
					home = _owned_world(i)
				if home.is_empty():
					if not side.has("unassigned_reserves"):
						side["unassigned_reserves"] = []
					side["unassigned_reserves"].append_array(overflow)
				else:
					state["worlds"][home]["cards"].append_array(overflow)
	for planet in state["worlds"].values():
		var old_deck: Array = planet["orbital_cards"]
		planet["orbital_cards"] = _fitted_cards([], old_deck, ORBITAL_LIMIT)
		planet["cards"].append_array(_without_cards(old_deck, planet["orbital_cards"]))


func _next_seed() -> int:
	state["serial"] = int(state["serial"]) + 1
	return int(state["seed"]) + int(state["serial"]) * 7919


func _recruit(world: String, faction: int, ships: bool, amount: int, fit_deck := false, existing := []) -> Array:
	var specialty: String = GALAXY.SPECIALTIES.get(world, GALAXY.FACTIONS[faction]["trait"] if faction >= 0 else "")
	var key := "militia/%s/%s/%s" % [world, faction, ships]
	if not _pools.has(key):
		var pool: Array = []
		var fallback: Array = []
		for id in lib.cards:
			var card: Dictionary = lib.cards[id]
			var matching := _local_match(card, world, faction, specialty)
			if not _production_card(card, matching) or not GALAXY.era_unit(card):
				continue
			if (card.get("arena") == "space") != ships or int(card.get("cost", 0)) > (6 if ships else 4):
				continue
			if matching:
				pool.append(id)
			if not ("heroism" in card.get("aspects", []) or "villainy" in card.get("aspects", [])):
				fallback.append(id)
		_pools[key] = pool if not pool.is_empty() else fallback
	return _draw_fleet_cards(_pools[key], amount, existing) if fit_deck else _draw_production(_pools[key], amount)


func _local_match(card: Dictionary, world: String, faction: int, specialty: String) -> bool:
	var native := GALAXY.native_recruits(world, faction)
	if not native.is_empty():
		return native.keys().any(func(roster): return GALAXY.native_match(card, roster))
	return specialty in card["traits"]


func _production_card(card: Dictionary, local := false) -> bool:
	if local and card["id"] in ["IC27_024", "KYB_007"]:
		return true
	return (not card.get("custom", false) and card.get("set") in CardLibrary.BOOSTER_SETS
		and card.get("implemented") in ["full", "vanilla"])


func _draw_production(pool: Array, amount: int) -> Array:
	if pool.is_empty() or amount <= 0:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = _next_seed()
	var result := []
	for i in amount:
		result.append(pool[rng.randi_range(0, pool.size() - 1)])
	return result


func _fleet_card_key(id: String) -> String:
	var data := lib.get_card(id)
	return "%s\n%s" % [str(data.get("name", id)).to_lower(), str(data.get("subtitle", "")).to_lower()]


func _fitted_cards(existing: Array, candidates: Array, limit := FLEET_LIMIT) -> Array:
	var counts := {}
	for id in existing:
		var key := _fleet_card_key(id)
		counts[key] = int(counts.get(key, 0)) + 1
	var accepted := []
	for id in candidates:
		if existing.size() + accepted.size() >= limit:
			break
		var key := _fleet_card_key(id)
		var copies: int = counts.get(key, 0)
		if copies < (1 if lib.get_card(id).get("unique", false) else FLEET_COPY_LIMIT):
			counts[key] = copies + 1
			accepted.append(id)
	return accepted


func _draw_fleet_cards(pool: Array, amount: int, existing: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _next_seed()
	var candidates := pool.duplicate()
	var deck := existing.duplicate()
	var drawn := []
	while drawn.size() < amount and not candidates.is_empty():
		var id: String = candidates[rng.randi_range(0, candidates.size() - 1)]
		if _fitted_cards(deck, [id]).is_empty():
			var key := _fleet_card_key(id)
			candidates = candidates.filter(func(candidate): return _fleet_card_key(candidate) != key)
			continue
		deck.append(id)
		drawn.append(id)
	return drawn


func _without_cards(cards: Array, removed: Array) -> Array:
	var remaining := cards.duplicate()
	for id in removed:
		remaining.erase(id)
	return remaining


func _native_pool(roster: String) -> Array:
	if not _pools.has(roster):
		var candidates := []
		for id in lib.cards:
			var card := lib.get_card(id)
			if GALAXY.era_unit(card) and GALAXY.native_match(card, roster) and _production_card(card, true):
				candidates.append(id)
		_pools[roster] = candidates
	return _pools[roster]


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
	if state["status"] != "active" or not idle(task) or not task["leader_alive"] or task["cards"].is_empty():
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
	if item in TRAINING:
		return TRAINING[item][1]
	if item == "probe":
		return PROBE_PRICE
	return PRICES.get(item, 25)


func can_buy(faction: int, world: String, item: String) -> bool:
	var site: Dictionary = state["worlds"][world]
	if not _can_manage(faction, world) or int(state["factions"][faction]["credits"]) < price(item):
		return false
	if item in FACILITIES:
		return site["facilities"].size() < 2 and not item in site["facilities"] and (not item in FACTORIES or _factory(world).is_empty())
	if item in GALAXY.native_recruits(world, faction):
		return site["cards"].size() < RESERVE_LIMIT and not _native_pool(item).is_empty()
	match item:
		"produce": return not _factory(world).is_empty() and site["cards"].size() < RESERVE_LIMIT
		"troops": return "garrison" in site["facilities"] and site["cards"].size() < 12
		"repair_orbit": return "orbital" in site["facilities"] and site["orbital_cards"].size() < ORBITAL_LIMIT
		"probe": return int(site["probes"]) < 3
		"commission": return fleet(faction)["world"].is_empty() and commissioning_cards(world).size() >= MIN_FLEET
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
	if item in GALAXY.native_recruits(world, faction):
		site["cards"].append_array(_draw_production(_native_pool(item), mini(4, RESERVE_LIMIT - site["cards"].size())))
	funds["credits"] = int(funds["credits"]) - price(item)
	if item in FACILITIES:
		site["facilities"].append(item)
	match item:
		"garrison", "troops":
			site["cards"].append_array(_recruit(world, faction, false, mini(6 if item == "garrison" else 4, RESERVE_LIMIT - site["cards"].size())))
		"orbital", "repair_orbit":
			site["orbital_cards"].append_array(_recruit(world, faction, true,
				mini(8, ORBITAL_LIMIT - site["orbital_cards"].size()), true, site["orbital_cards"]))
		"probe":
			site["probes"] = int(site["probes"]) + 1
		"commission":
			var primary := fleet(faction)
			var commander: String = primary["leader"] if primary["leader_alive"] else ""
			var cards := commissioning_cards(world)
			funds["fleet"] = _new_fleet(world, cards, commander)
			site["cards"] = _without_cards(site["cards"], cards)
	return true


func training_rank(task: Dictionary, perk: String, card_id := "") -> int:
	var training: Dictionary = task["training"]
	match perk:
		"opening": return int(not training.get("opening", "").is_empty())
		"experience", "shield": return int(perk in training.get("units", {}).get(card_id, []))
		"equipment": return int(training.get("equipment", {}).has(card_id))
	return int(training.get(perk, 0))


func can_train(faction: int, world: String, index: int, perk: String, card_id := "") -> bool:
	var task := fleet(faction, index)
	if not perk in TRAINING or not _can_manage(faction, world) or task["world"] != world or not idle(task):
		return false
	if not "training" in state["worlds"][world]["facilities"] or int(state["factions"][faction]["credits"]) < price(perk):
		return false
	if perk in ["opening", "experience", "shield", "equipment"]:
		if not card_id in task["cards"] or lib.get_card(card_id).get("type") != "unit":
			return false
	else:
		if perk in ["health", "command_shield"] and not task["leader_alive"]:
			return false
	return training_rank(task, perk, card_id) < TRAINING[perk][2]


func equipment_for(card_id: String) -> Array:
	var vehicle: bool = "vehicle" in lib.get_card(card_id).get("traits", [])
	return TRAINING_EQUIPMENT.filter(func(id): return id != "SHD_174" if vehicle else id != "SOR_121")


func train(faction: int, world: String, index: int, perk: String, card_id := "", equipment := "") -> bool:
	if not can_train(faction, world, index, perk, card_id):
		return false
	if perk == "equipment" and not equipment in equipment_for(card_id):
		return false
	var task := fleet(faction, index)
	var training: Dictionary = task["training"]
	match perk:
		"opening":
			training["opening"] = card_id
		"equipment":
			if not training.has("equipment"):
				training["equipment"] = {}
			training["equipment"][card_id] = equipment
		"experience", "shield":
			if not training.has("units"):
				training["units"] = {}
			if not training["units"].has(card_id):
				training["units"][card_id] = []
			training["units"][card_id].append(perk)
		_:
			training[perk] = training_rank(task, perk) + 1
	state["factions"][faction]["credits"] = int(state["factions"][faction]["credits"]) - price(perk)
	return true


func command_max_hp(task: Dictionary) -> int:
	return COMMAND_HP + 5 * training_rank(task, "health")


func _produce(world: String, faction: int, factory: String, amount: int) -> Array:
	return _draw_production(_factory_cards(world, faction, factory), amount)


func _factory_cards(world: String, faction: int, factory: String) -> Array:
	var key := "factory/%s/%d/%s" % [world, faction, factory]
	if not _pools.has(key):
		_pools[key] = _factory_pool(world, faction, factory)
	return _pools[key]


func _production_choices(faction: int, world: String, local: bool) -> Array:
	if int(state["worlds"][world]["owner"]) != faction:
		return []
	if local:
		var cards := []
		for roster in GALAXY.native_recruits(world, faction):
			cards.append_array(_native_pool(roster))
		return cards
	var factory := _factory(world)
	return [] if factory.is_empty() else _factory_cards(world, faction, factory)


func factory_catalog(faction: int, world: String, local := false) -> Array:
	var seen := {}
	var cards := []
	for id in _production_choices(faction, world, local):
		var key := _fleet_card_key(id)
		if not seen.has(key):
			seen[key] = true
			cards.append(id)
	cards.sort_custom(func(a, b):
		var first := lib.get_card(a)
		var second := lib.get_card(b)
		return int(first["cost"]) < int(second["cost"]) if first["cost"] != second["cost"] else str(first["name"]) < str(second["name"]))
	return cards


func manufacture_price(id: String) -> int:
	return 6 + 2 * int(lib.get_card(id).get("cost", 0))


func can_manufacture(faction: int, world: String, id: String, local := false) -> bool:
	return _can_manage(faction, world) \
		and state["worlds"][world]["cards"].size() < RESERVE_LIMIT \
		and int(state["factions"][faction]["credits"]) >= manufacture_price(id) \
		and id in _production_choices(faction, world, local)


func manufacture(faction: int, world: String, id: String, local := false) -> bool:
	if not can_manufacture(faction, world, id, local):
		return false
	state["worlds"][world]["cards"].append(id)
	var side: Dictionary = state["factions"][faction]
	side["credits"] = int(side["credits"]) - manufacture_price(id)
	return true


func _factory_pool(world: String, faction: int, factory: String) -> Array:
	var specialty: String = GALAXY.SPECIALTIES.get(world, GALAXY.FACTIONS[faction]["trait"])
	var pool := []
	var local := []
	var thematic := []
	for id in lib.cards:
		var data := lib.get_card(id)
		var matching := _local_match(data, world, faction, specialty)
		if not _production_card(data, matching) or not _fits_factory(data, factory):
			continue
		pool.append(id)
		if factory == "armory":
			continue
		if matching:
			local.append(id)
		elif GALAXY.FACTIONS[faction]["trait"] in data["traits"]:
			thematic.append(id)
	return local if not local.is_empty() else (thematic if not thematic.is_empty() else pool)


func _fits_factory(card: Dictionary, factory: String) -> bool:
	var traits: Array = card["traits"]
	if factory == "armory":
		return (card.get("type") == "upgrade" and not card["name"] in ARMORY_EXCLUDED
			and traits.any(func(tag): return tag in ["item", "armor", "weapon", "modification"])
			and not traits.any(func(tag): return tag in GALAXY.LATER_OR_EARLIER_TRAITS))
	if not GALAXY.era_unit(card):
		return false
	if factory == "officers":
		var full_name: String = card["name"].to_lower()
		return "officer" in traits or OFFICER_RANKS.any(func(rank): return full_name.begins_with(rank))
	if factory == "government":
		return "official" in traits
	var ships := factory in ["fighters", "frigates", "capital"]
	if (card.get("arena") == "space") != ships:
		return false
	if factory == "frigates":
		return "frigate" in traits or "frigate" in card["name"].to_lower()
	return FACTORY_TRAITS.get(factory, "") in traits


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
	existing.append_array(state["factions"][faction].get("retired_leaders", []))
	for delivery in state["shipments"]:
		if int(delivery["faction"]) == faction and delivery.has("leader"):
			existing.append(lib.get_card(delivery["leader"]).get("name", ""))
	return GALAXY.leader_variants(lib, faction, world).filter(func(id): return not lib.get_card(id)["name"] in existing)


func _retire_leader(faction: int, leader: String) -> void:
	var side: Dictionary = state["factions"][faction]
	var retired: Array = side.get("retired_leaders", [])
	var name: String = lib.get_card(leader).get("name", "")
	if not name.is_empty() and not name in retired:
		retired.append(name)
	side["retired_leaders"] = retired


func can_send_replacement(faction: int, origin: String, index: int) -> bool:
	var task := fleet(faction, index)
	if not _can_manage(faction, origin) or not idle(task) or task["leader_alive"]:
		return false
	if int(state["factions"][faction]["credits"]) < price("commission") or eligible_commanders(faction, origin).is_empty():
		return false
	if state["shipments"].any(func(delivery): return delivery.has("leader") and int(delivery["faction"]) == faction and int(delivery["fleet"]) == index):
		return false
	return origin == task["world"] or not path(faction, origin, task["world"], true).is_empty()


func send_replacement(faction: int, origin: String, index: int, leader: String) -> bool:
	if not can_send_replacement(faction, origin, index) or not leader in eligible_commanders(faction, origin):
		return false
	var task := fleet(faction, index)
	var side: Dictionary = state["factions"][faction]
	side["credits"] = int(side["credits"]) - price("commission")
	var delivery := {"faction": faction, "fleet": index, "world": origin, "leader": leader,
		"route": path(faction, origin, task["world"], true)}
	if delivery["route"].is_empty():
		_assign_commander(task, leader)
	else:
		_depart(delivery)
		state["shipments"].append(delivery)
	return true


func _assign_commander(task: Dictionary, leader: String) -> void:
	task["leader"] = leader
	task["leader_alive"] = true
	task["command_damage"] = 0
	task["recovery"] = 0.0


func build_commander(faction: int, world: String, leader: String) -> bool:
	var milestone := available_milestone(faction)
	var funds: Dictionary = state["factions"][faction]
	if milestone == 0 or not _can_manage(faction, world) or int(funds["credits"]) < price("commission") or not leader in eligible_commanders(faction, world):
		return false
	var site: Dictionary = state["worlds"][world]
	var cards := commissioning_cards(world)
	if cards.size() < MIN_FLEET:
		return false
	funds["credits"] = int(funds["credits"]) - price("commission")
	funds["milestones"].append(milestone)
	funds["extra_fleets"].append(_new_fleet(world, cards, leader))
	site["cards"] = _without_cards(site["cards"], cards)
	return true


func commissioning_cards(world: String) -> Array:
	return _fitted_cards([], state["worlds"][world]["cards"], MIN_FLEET)


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


func transfer_candidates(faction: int, index: int, candidates: Array) -> Array:
	var assigned: Array = fleet(faction, index)["cards"].duplicate()
	for shipment in state["shipments"]:
		if int(shipment["faction"]) == faction and int(shipment["fleet"]) == index:
			assigned.append_array(shipment.get("cards", []))
	return _fitted_cards(assigned, candidates)


func transfer(faction: int, origin: String, ids: Array, index := 0) -> bool:
	var task := fleet(faction, index)
	var defense: Dictionary = state["worlds"][origin]
	if state["status"] != "active" or not idle(task) or int(defense["owner"]) != faction or _contested(origin):
		return false
	if ids.is_empty() or transfer_candidates(faction, index, ids).size() != ids.size():
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
		var accepted := _fitted_cards(task["cards"], cards)
		task["cards"].append_array(accepted)
		cards = _without_cards(cards, accepted)
	state["worlds"][world]["cards"].append_array(cards)
	state["shipments"].erase(shipment)


func _move_replacement(delivery: Dictionary) -> bool:
	var faction := int(delivery["faction"])
	var task := fleet(faction, int(delivery["fleet"]))
	var origin: String = delivery["world"]
	if int(state["worlds"][origin]["owner"]) != faction:
		var refuge := _retreat_route(faction, origin)
		if refuge.is_empty():
			state["shipments"].erase(delivery)
			return true
		origin = refuge.back()
		delivery["world"] = origin
		delivery["route"] = []
	if not delivery["route"].is_empty():
		var next: String = delivery["route"][0]
		if _contested(next):
			return false
		delivery["route"].clear()
		if int(state["worlds"][next]["owner"]) == faction:
			origin = next
			delivery["world"] = origin
	if task["leader_alive"] or task["world"].is_empty():
		state["factions"][faction]["credits"] = int(state["factions"][faction]["credits"]) + price("commission")
		state["shipments"].erase(delivery)
		return true
	if not idle(task):
		return false
	if origin == task["world"] and not _contested(origin):
		_assign_commander(task, delivery["leader"])
		state["shipments"].erase(delivery)
		return true
	delivery["route"] = path(faction, origin, task["world"], true)
	if delivery["route"].is_empty():
		state["factions"][faction]["credits"] = int(state["factions"][faction]["credits"]) + price("commission")
		state["shipments"].erase(delivery)
		return true
	_depart(delivery)
	return true


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
			if task["leader_alive"] and task["engagement"].is_empty() and int(task["command_damage"]) > 0:
				task["recovery"] = float(task["recovery"]) + delta
				var intervals := floori(float(task["recovery"]) / RECOVERY_PERIOD)
				if intervals > 0:
					task["command_damage"] = maxi(0, int(task["command_damage"]) - intervals * RECOVERY_HP)
					task["recovery"] = fmod(float(task["recovery"]), RECOVERY_PERIOD)
					changed = true
			if task["route"].is_empty() or float(task["arrival"]) > float(state["time"]):
				continue
			var next: String = task["route"][0]
			if _contested(next):
				continue
			task["route"].pop_front()
			if task["retreating"]:
				task["world"] = next
				if task["route"].is_empty():
					_retreat(faction, task, next)
				else:
					_depart(task)
			elif int(state["worlds"][next]["owner"]) != faction:
				task["route"].clear()
				_begin_battle(faction, next, index)
			else:
				task["last_world"] = task["world"]
				task["world"] = next
				if not task["route"].is_empty():
					_depart(task)
			changed = true
	for shipment in state["shipments"].duplicate():
		if float(shipment["arrival"]) > float(state["time"]):
			continue
		if shipment.has("leader"):
			changed = _move_replacement(shipment) or changed
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


func _retreat_route(faction: int, origin: String, preferred := "", leave_origin := false) -> Array:
	var pending := [origin]
	var costs := {origin: 0.0}
	var previous := {}
	var fallback := []
	while not pending.is_empty():
		pending.sort_custom(func(a, b): return costs[a] < costs[b])
		var from: String = pending.pop_front()
		if int(state["worlds"][from]["owner"]) == faction and (from != origin or not leave_origin):
			var route := []
			var step := from
			while step != origin:
				route.push_front(step)
				step = previous[step]
			if preferred.is_empty() or from == preferred:
				return route
			if fallback.is_empty():
				fallback = route
		for next in neighbors(from):
			var cost := float(costs[from]) + travel_duration(from, next)
			if cost < float(costs.get(next, INF)):
				costs[next] = cost
				previous[next] = from
				if not next in pending:
					pending.append(next)
	return fallback


func _retreat(faction: int, task: Dictionary, from: String, route := []) -> void:
	task["route"] = _retreat_route(faction, from) if route.is_empty() else route
	task["retreating"] = not task["route"].is_empty()
	if task["retreating"]:
		task["world"] = from
		_depart(task)
	else:
		task["world"] = from if int(state["worlds"][from]["owner"]) == faction else ""


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
	if not task["leader_alive"]:
		for world in state["worlds"]:
			if can_send_replacement(faction, world, index):
				send_replacement(faction, world, index, eligible_commanders(faction, world)[0])
				break
		return
	if int(state["worlds"][origin]["owner"]) == faction and task["cards"].size() < 18:
		var reserve: Array = state["worlds"][origin]["cards"]
		if reserve.size() < 8:
			buy(faction, origin, "garrison")
			buy(faction, origin, "troops")
			buy(faction, origin, "produce")
		var cards := transfer_candidates(faction, index, reserve)
		transfer(faction, origin, cards.slice(0, mini(18 - task["cards"].size(), maxi(0, reserve.size() - 3))), index)
	if int(task["command_damage"]) >= RECOVERY_HP:
		return
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
		"origin": fleet(attacker, index)["world"],
		"fleet_defense": field_fleet, "defense_index": defense_index, "attack_index": index,
		"orbital": not field_fleet and not defense["orbital_cards"].is_empty(), "seed": seed_value}
	fleet(attacker, index)["engagement"] = key
	if field_fleet:
		fleet(defender, defense_index)["engagement"] = key
	if int(state["player"]) in [attacker, defender]:
		state["report"] = "Battle for %s ready." % world


func player_battle() -> String:
	if state["status"] != "active":
		return ""
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
			return card.get("arena") == "space" or card.has("pilot") or card.get("type") != "unit")
	var attacker_spec := _battle_side(attacker, attack_cards, assault, 20, orbit)
	var defender_hp := 20 if battle["fleet_defense"] or orbit else (18 if "garrison" in planet["facilities"] else 12)
	var defender_spec := _battle_side(defender, defense_cards, defending, defender_hp, orbit)
	defender_spec["command_shields"] += int("fortification" in planet["facilities"])
	var human_is_defender := human and defender == int(state["player"])
	var players := [defender_spec, attacker_spec] if human_is_defender else [attacker_spec, defender_spec]
	players[0]["ai"] = not human
	var rules := RuleSet.new()
	rules.name = "conquest"
	rules.aspect_penalties = false
	rules.hero_villain_gate = false
	rules.starting_hand = 4
	rules.allow_mulligan = false
	rules.deck_out_damage = 2
	if orbit:
		rules.arenas = ["space"]
	return {"rules": rules, "players": players, "seed": int(battle["seed"]),
		"first": 1 if human_is_defender else 0, "track_roster_losses": true, "objective": {"type": "conquest"}}


func _battle_side(faction: int, cards: Array, task: Dictionary, local_hp: int, orbit: bool) -> Dictionary:
	var side: Dictionary = GALAXY.FACTIONS[faction] if faction >= 0 else {}
	var leader: String = task["leader"] if task.get("leader_alive", false) else ""
	var training: Dictionary = task.get("training", {})
	var queue := _fitted_cards([], cards)
	var preplaced := []
	var opening: String = training.get("opening", "")
	if opening in queue and (not orbit or lib.get_card(opening).get("arena") == "space"):
		queue.erase(opening)
		preplaced.append({"id": opening, "roster": true, "ready": true})
	return {"name": side.get("name", "Local militia"), "leader": leader, "deck": queue, "ai": true,
		"command_name": lib.get_card(leader).get("name", "Local command" if task.is_empty() else "Acting command"),
		"command_hp": local_hp if leader.is_empty() else command_max_hp(task),
		"base_damage": 0 if leader.is_empty() else int(task["command_damage"]),
		"command_shields": 0 if leader.is_empty() else int(training.get("command_shield", 0)),
		"extra_resources": int(training.get("resources", 0)), "card_upgrades": training.get("units", {}),
		"training_equipment": training.get("equipment", {}),
		"preplaced": preplaced, "profile": "defensive" if task.is_empty() else "tempo"}


func withdrawal_plan(key: String) -> Array:
	if state["status"] != "active" or not state["battles"].has(key):
		return []
	var battle: Dictionary = state["battles"][key]
	var player := int(state["player"])
	var attacking: bool = battle["attacker"] == player
	if not attacking and (battle["defender"] != player or not battle["fleet_defense"]):
		return []
	var task := fleet(player, int(battle.get("attack_index" if attacking else "defense_index", 0)))
	if not task["leader_alive"]:
		return []
	var departure: String = battle.get("origin", task["world"]) if attacking else task.get("last_world", "")
	return _retreat_route(player, battle["world"], departure, true)


func withdraw_player(key: String, match_game: Match) -> Dictionary:
	if not match_game.can_act(0):
		return {}
	var route := withdrawal_plan(key)
	if route.is_empty():
		return {}
	match_game.set_winner(1, "Fleet withdrew")
	return finish_battle(key, match_game, true, route)


func finish_battle(key: String, match_game: Match, human: bool, withdrawal := []) -> Dictionary:
	if state["status"] != "active" or not state["battles"].has(key) or match_game.winner < 0:
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
	_update_command(attacker, attacker_fleet, match_game, attacker_side)
	if battle["fleet_defense"]:
		_update_command(defender, defense, match_game, 1 - attacker_side)
	var captured := match_game.winner == attacker_side
	var victor := attacker if captured else (defender if match_game.winner == 1 - attacker_side else -1)
	if captured:
		planet["owner"] = attacker
		var retreat := _retreat_route(defender, world) if defender >= 0 else []
		var refuge: String = retreat.back() if not retreat.is_empty() else ""
		if battle["fleet_defense"]:
			_retreat(defender, defense, world, withdrawal)
		if defender >= 0:
			for task in fleets(defender):
				if idle(task) and task["world"] == world:
					_retreat(defender, task, world)
		if not refuge.is_empty():
			state["worlds"][refuge]["cards"].append_array(planet["cards"] + planet["orbital_cards"])
		planet["cards"] = []
		planet["cards"].append_array(state["factions"][attacker].get("unassigned_reserves", []))
		state["factions"][attacker].erase("unassigned_reserves")
		planet["orbital_cards"] = []
		planet["facilities"] = []
		planet["probes"] = 0
		attacker_fleet["last_world"] = attacker_fleet["world"]
		attacker_fleet["world"] = world
	elif not withdrawal.is_empty():
		_retreat(attacker, attacker_fleet, world, withdrawal)
	elif not attacker_fleet["leader_alive"] or int(state["worlds"][attacker_fleet["world"]]["owner"]) != attacker:
		_retreat(attacker, attacker_fleet, world)
	if victor >= 0:
		var side: Dictionary = state["factions"][victor]
		side["credits"] = int(side["credits"]) + WIN_REWARD
	if not captured and attacker != int(state["player"]):
		var rival: Dictionary = state["factions"][attacker]
		rival["next_order"] = maxf(float(rival["next_order"]), float(state["time"]) + BOT_REBUILD_TIME)
	for task in [attacker_fleet, defense] if battle["fleet_defense"] else [attacker_fleet]:
		task["engagement"] = ""
		if task["cards"].is_empty() and not task["leader_alive"]:
			task["world"] = ""
			task["route"].clear()
			task["retreating"] = false
	state["battles"].erase(key)
	var player := int(state["player"])
	var losses: int = match_game.roster_losses[0].size() if human else 0
	var leader_lost: bool = human and match_game.roster_leader_lost[0]
	var reply := {"world": world, "captured": captured, "losses": losses, "leader_lost": leader_lost,
		"credits": WIN_REWARD if victor == player else 0}
	if human:
		state["report"] = "%s · %d cards lost%s" % [world, losses, " · +%d credits" % reply["credits"] if reply["credits"] else ""]
		if leader_lost:
			state["report"] += " · Commander lost"
		if not withdrawal.is_empty():
			reply["destination"] = withdrawal.back()
			state["report"] += " · Withdrawing to %s" % GALAXY.display_name(reply["destination"])
	var held: int = state["worlds"].values().filter(func(site): return int(site["owner"]) == player).size()
	if held == state["worlds"].size():
		state["status"] = "won"
	elif held == 0 and fleets(player).all(func(task): return task["world"].is_empty()):
		state["status"] = "lost"
	return reply


func _apply_losses(force: Dictionary, match_game: Match, side: int, roster := "cards") -> void:
	for id in match_game.roster_losses[side]:
		force[roster].erase(id)


func _update_command(faction: int, task: Dictionary, match_game: Match, side: int) -> void:
	if match_game.roster_leader_lost[side]:
		_retire_leader(faction, task["leader"])
		task["leader_alive"] = false
	task["command_damage"] = clampi(match_game.players[side].base.damage, 0, command_max_hp(task) - 1) if task["leader_alive"] else 0
	task["recovery"] = 0.0
	var opening: String = task["training"].get("opening", "")
	if not opening in task["cards"]:
		task["training"].erase("opening")
