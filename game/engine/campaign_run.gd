class_name CampaignRun
extends RefCounted
## Roguelike chapter run logic (spec 5.1–5.4). Pure functions over a plain
## Dictionary so the run serialises straight into the save file.
##
## run = {chapter, leader, deck[], base_hp_bonus, base_damage, current, visited[],
##        treasures[], node_seed, status: "active"|"won"|"lost", last_rewards{}}


static func start(chapter: Dictionary, leader: String, seed_value: int) -> Dictionary:
	return {
		"chapter": chapter["id"], "leader": leader,
		"deck": starting_deck(chapter, leader),
		"base_hp_bonus": 0, "base_damage": 0, "credits": 0, "consecutive_clears": 0,
		"starts_at_chapter_one": int(chapter.get("number", 1)) == 1, "card_upgrades": {},
		"current": "", "visited": [], "treasures": [],
		"node_seed": seed_value, "status": "active", "fights": 0,
		"route_version": chapter.get("route_version", 0),
		"starter_revision": chapter.get("starter_revision", 0),
		"reward_id": "%s_%s" % [Time.get_unix_time_from_system(), seed_value],
	}


static func starting_deck(chapter: Dictionary, leader: String) -> Array:
	var deck: Array = chapter.get("starting_deck", []).duplicate()
	var companion: String = chapter.get("leader_companions", {}).get(leader, "")
	if not companion.is_empty():
		deck.append(companion)
	return deck


static func update_starter_deck(run: Dictionary, chapter: Dictionary) -> bool:
	var revision := int(chapter.get("starter_revision", 0))
	if revision <= int(run.get("starter_revision", 0)):
		return false
	var deck: Array = run["deck"]
	for pair in chapter.get("starter_replacements", []):
		var index := deck.find(pair[0])
		if index >= 0:
			deck[index] = pair[1]
	run["starter_revision"] = revision
	return true


## Add optional event branches without changing the underlying story encounters.
static func route(chapter: Dictionary, run: Dictionary) -> Dictionary:
	var slots: Array = chapter.get("choice_slots", [])
	if slots.is_empty():
		return chapter
	var routed := chapter.duplicate(true)
	var map: Dictionary = routed["map"]
	var picked: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run.get("node_seed", 0)) ^ 47129
	for slot in slots:
		var candidates: Array = slot["events"].filter(func(id): return id not in picked)
		if candidates.is_empty():
			continue
		var event: String = candidates[rng.randi_range(0, candidates.size() - 1)]
		picked.append(event)
		var bypass := "bypass_" + event
		var anchor: String = slot.get("alternate_before", {}).get(event, slot["before"])
		var rows: Array = map["rows"]
		for i in rows.size():
			if anchor not in rows[i]:
				continue
			var onward: Array = rows[i].duplicate()
			var branch := [event, bypass]
			if i > 0:
				for previous in rows[i - 1]:
					map["edges"][previous] = branch.duplicate()
			rows.insert(i, branch)
			map["edges"][event] = onward.duplicate()
			map["edges"][bypass] = onward
			routed["nodes"].append({"id": bypass, "type": "event", "title": "Continue onward",
				"desc": "Stay on the main route.", "event": {"choices": [{"label": "Continue"}]}})
			break
	routed["nodes"] = routed["nodes"].filter(func(node): return not node.get("optional_choice", false) or node["id"] in picked)
	return routed


static func scene_for(run: Dictionary, chapter: Dictionary, node: Dictionary) -> String:
	var scenes: Array = node.get("scenes", [])
	if scenes.is_empty():
		return chapter.get("board_theme", "space")
	var seed_value := int(run.get("node_seed", 0)) + str(node["id"]).hash()
	return scenes[posmod(seed_value, scenes.size())]


static func remaining_background(run: Dictionary, chapter: Dictionary, earned: Array) -> String:
	var choices: Array = chapter.get("background_rewards", []).filter(func(id): return "background:" + id not in earned)
	if choices.is_empty():
		return ""
	return choices[posmod(int(run.get("node_seed", 0)), choices.size())]


static func available_nodes(run: Dictionary, chapter: Dictionary) -> Array:
	if run.has("pending_event_battle"):
		return [run["pending_event_battle"]]
	var map: Dictionary = chapter.get("map", {})
	if run.get("current", "") == "":
		return map.get("rows", [[]])[0]
	return map.get("edges", {}).get(run["current"], [])


static func node_by_id(chapter: Dictionary, id: String) -> Dictionary:
	for n in chapter.get("nodes", []):
		if n.get("id", "") == id:
			return n
	return {}


static func max_base_hp(run: Dictionary, chapter: Dictionary) -> int:
	return int(chapter.get("base_hp_override", 18)) + int(run.get("base_hp_bonus", 0))


static func damage_after_victory(run: Dictionary, chapter: Dictionary, damage: int) -> int:
	return clampi(damage - int(chapter.get("repair_after_win", 0)), 0, max_base_hp(run, chapter) - 1)


static func event_effect(run: Dictionary, node: Dictionary, choice: Dictionary) -> Dictionary:
	var effect: Dictionary = choice.get("effect", {}).duplicate(true)
	var outcomes: Array = choice.get("outcomes", [])
	if not outcomes.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(run["node_seed"]) ^ str(node["id"]).hash()
		var total := 0
		for outcome in outcomes:
			total += int(outcome["weight"])
		var roll := posmod(rng.randi_range(0, total - 1) + int(choice.get("draw_offset", 0)), total)
		for outcome in outcomes:
			roll -= int(outcome["weight"])
			if roll < 0:
				effect.merge(outcome["effect"], true)
				break
	if choice.has("cost"):
		effect["cost"] = choice["cost"]
	return effect


static func treasure_effects(run: Dictionary, treasures: Dictionary) -> Dictionary:
	var out := {"extra_resources": 0, "first_unit_experience": 0, "extra_hand": 0, "tokens": []}
	for t in run.get("treasures", []):
		var e: Dictionary = treasures.get(t, {}).get("effect", {})
		for k in ["extra_resources", "first_unit_experience", "extra_hand"]:
			out[k] += int(e.get(k, 0))
		if e.has("add_token"):
			out["tokens"].append(e["add_token"])
	return out


## Builds the Match.setup() config for a combat node.
static func match_config(run: Dictionary, chapter: Dictionary, node: Dictionary, treasures: Dictionary) -> Dictionary:
	var rd := {"ruleset": chapter.get("ruleset", "campaign"), "base_hp_override": 0,
		"arenas": node.get("arenas", chapter.get("arenas", ["ground", "space"])),
		"turn_mode": node.get("turn_mode", "alternating")}
	rd.merge(chapter.get("battle_rules", {}), true)
	rd.merge(node.get("battle_rules", {}), true)
	var rules := RuleSet.from_dict(rd)
	rules.base_hp_override = 0
	var te := treasure_effects(run, treasures)
	var tokens: Array = node.get("claimable_tokens", ["initiative"]).duplicate()
	for t in te["tokens"]:
		if not (t in tokens):
			tokens.append(t)
	var enemy := encounter_enemy(run, node)
	var objective: Dictionary = node.get("objective", {"type": "standard"})
	var base_id: String = node.get("base", chapter.get("base_sequence", [""])[0])
	var deck: Array = run["deck"].duplicate()
	var disabled: Array = run.get("disabled_cards", []) if int(run.get("disabled_battles", 0)) > 0 else []
	deck = deck.filter(func(id): return id not in disabled)
	for id in node.get("deploy_from_deck", []):
		deck.erase(id)
	var enemy_opening: Array = enemy.get("preplaced", []).duplicate()
	var player_opening: Array = node.get("player_preplaced", []).filter(func(unit): return unit["id"] not in disabled).duplicate(true)
	var oil_bath_card: String = run.get("oil_bath_card", "")
	if oil_bath_card in node.get("deploy_from_deck", []):
		for unit in player_opening:
			if unit["id"] == oil_bath_card:
				unit.get_or_add("flags", {})["campaign_oil_bath"] = true
				oil_bath_card = ""
				break
	if str(run.get("next_enemy_card", "")) != "":
		enemy_opening.append({"id": run["next_enemy_card"], "ready": false})
	if node["id"] == "boss" and chapter["id"] == "ep4_ch2_deathstar":
		var change := int(run.get("hangar_troopers", 0))
		if change < 0:
			for i in range(enemy_opening.size() - 1, -1, -1):
				if enemy_opening[i]["id"] == "SOR_128" and change < 0:
					enemy_opening.remove_at(i)
					change += 1
		else:
			for _i in change:
				enemy_opening.append({"id": "SOR_128", "ready": false})
	return {
		"seed": int(run.get("node_seed", 0)) + int(run.get("fights", 0)) * 7919,
		"rules": rules,
		"tokens": tokens,
		"objective": objective,
		"first": node.get("first", -1),
		"linked_duel_cards": chapter.get("linked_duel_cards", []),
		"lando_space_campaign": chapter.get("lando_space_campaign", false),
		"players": [
			{
				"name": "Rebel Alliance", "leader": run["leader"], "base": base_id,
				"support_leader": run.get("support_leader", ""),
				"deploy_leader_at_start": chapter.get("deploy_leader_at_start", false),
				"opening_leader_shield": node.get("opening_leader_shield", false),
				"opening_leader_hp": int(chapter.get("opening_leader_hp", 0)),
				"deck": deck, "ai": false,
				"base_hp": max_base_hp(run, chapter), "base_damage": int(run.get("base_damage", 0)),
				"preplaced": player_opening,
				"oil_bath_card": oil_bath_card,
				"bonus_hand": node.get("player_bonus_hand", []),
				"extra_resources": te["extra_resources"] + int(run.get("starting_resource_bonus", 0)) + int(node.get("player_extra_resources", chapter.get("player_extra_resources", 0))),
				"first_unit_experience": te["first_unit_experience"],
				"extra_hand": te["extra_hand"], "card_upgrades": run.get("card_upgrades", {}),
				"leader_mods": run.get("leader_mods", {}),
			},
			{
				"name": enemy.get("name", "Enemy"), "leader": enemy.get("leader", ""),
				"base": enemy.get("base", base_id), "deck": enemy.get("deck", []), "ai": true,
				"profile": enemy.get("ai_profile", "tempo"), "hero_skin": enemy.get("hero_skin", ""),
				"base_hp": enemy_base_hp(enemy, objective),
				"preplaced": enemy_opening,
			},
		],
	}


## Keep the same encounter on preview, save reload and replay of a battle.
static func encounter_enemy(run: Dictionary, node: Dictionary) -> Dictionary:
	var enemy: Dictionary = node.get("enemy", {}).duplicate()
	var variants: Array = node.get("enemy_variants", [])
	if not variants.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(run.get("node_seed", 0)) + str(node["id"]).hash() * 7919
		enemy.merge(variants[rng.randi_range(0, variants.size() - 1)], true)
	return enemy


static func enemy_base_hp(enemy: Dictionary, objective: Dictionary) -> int:
	return int(enemy.get("hp", 12)) + (2 if objective.get("type", "standard") == "standard" else 0)


static func completion_pack_size(run: Dictionary, chapter: Dictionary) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run.get("node_seed", 0)) * 7919 + str(chapter["id"]).hash()
	return rng.randi_range(8, 12)


## Offer `n` distinct reward cards; higher tiers bias toward rarer/pricier cards.
static func roll_rewards(run: Dictionary, chapter: Dictionary, node: Dictionary, lib: CardLibrary, n := 3) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run.get("node_seed", 0)) * 31 + int(run.get("fights", 0))
	var pool: Array = []
	for id in node.get("reward_pool", chapter.get("reward_pool", [])):
		if lib.has(id):
			pool.append(id)
	var tier := int(node.get("reward_tier", 1))
	var out: Array = []
	var guard := 0
	while out.size() < n and not pool.is_empty() and guard < 200:
		guard += 1
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		if id in out:
			continue
		var cost := int(lib.get_card(id).get("cost", 0))
		if tier <= 1 and cost >= 5 and rng.randf() < 0.6:
			continue
		if tier >= 3 and cost <= 1 and rng.randf() < 0.5:
			continue
		out.append(id)
	return out


static func roll_treasures(run: Dictionary, chapter: Dictionary, n := 2) -> Array:
	var owned: Array = run.get("treasures", [])
	var out: Array = []
	for t in chapter.get("treasures", []):
		if not (t in owned) and out.size() < n:
			out.append(t)
	return out


## Applies an event / rest effect dict. Returns a short description.
static func apply_effect(run: Dictionary, chapter: Dictionary, e: Dictionary) -> String:
	var msg: Array = []
	if e.has("message"):
		msg.append(e["message"])
	for key in ["revealed_hand", "next_enemy_card", "disabled_cards", "disabled_battles", "hangar_troopers"]:
		if e.has(key):
			run[key] = e[key]
	for key in ["credits", "starting_resource_bonus", "base_damage"]:
		if e.has(key):
			run[key] = int(run.get(key, 0)) + int(e[key])
	if e.has("remove_id"):
		run["deck"].erase(e["remove_id"])
	if e.has("experience_id"):
		run["oil_bath_card"] = e["experience_id"]
	for id in e.get("add_cards", []):
		run["deck"].append(id)
		msg.append("Added a card to your deck.")
	if e.has("base_hp_bonus"):
		run["base_hp_bonus"] = int(run.get("base_hp_bonus", 0)) + int(e["base_hp_bonus"])
		msg.append("+%d max base HP." % int(e["base_hp_bonus"]))
	if e.has("heal"):
		var before := int(run.get("base_damage", 0))
		run["base_damage"] = maxi(0, int(run.get("base_damage", 0)) - int(e["heal"]))
		msg.append("Repaired %d damage." % (before - int(run["base_damage"])))
	if e.has("treasure"):
		run["treasures"].append(e["treasure"])
		msg.append("Treasure acquired.")
	return " ".join(msg)


static func shop_offers(run: Dictionary, node: Dictionary) -> Array:
	var offers: Array = node.get("offers", []).duplicate()
	var mods := [
		{"id": "early_deploy", "label": "Accelerated Deployment", "cost": 25, "leader_mod": true},
		{"id": "leader_armor", "label": "Reinforced Armor · +2 HP", "cost": 15, "leader_mod": true},
		{"id": "leader_weapon", "label": "Enhanced Weaponry · +1 power", "cost": 15, "leader_mod": true},
	]
	var seed_value := int(run.get("node_seed", 0)) ^ str(node["id"]).hash()
	var leaders := [run["leader"]]
	if run.has("support_leader"):
		leaders.append(run["support_leader"])
	for n in 2 + posmod(seed_value, 2):
		for leader in leaders:
			var offer: Dictionary = mods[posmod(seed_value + n, mods.size())].duplicate()
			offer["leader_id"] = leader
			offers.append(offer)
	return offers


static func buy_service(run: Dictionary, chapter: Dictionary, node: Dictionary, offer: Dictionary, card_id := "") -> bool:
	if run.get("status") != "active" or node["id"] not in available_nodes(run, chapter) or offer not in shop_offers(run, node):
		return false
	var cost := int(offer["cost"])
	var used: Dictionary = run.get("shop_purchases", {})
	var key := "%s/%s" % [node["id"], offer["id"]]
	if cost < 0 or cost > int(run.get("credits", 0)) or used.has(key):
		return false
	if offer.get("leader_mod", false):
		var mods: Array = run.get_or_add("leader_mods", {}).get_or_add(offer["leader_id"], [])
		if offer["id"] in mods:
			return false
		mods.append(offer["id"])
		run["credits"] -= cost
		return true
	var upgrades: Dictionary = run.get("card_upgrades", {})
	match offer["id"]:
		"duplicate", "experience":
			if card_id not in run["deck"] or (offer["id"] == "experience" and upgrades.has(card_id)):
				return false
			if offer["id"] == "duplicate":
				run["deck"].append(card_id)
			else:
				upgrades[card_id] = ["experience"]
				run["card_upgrades"] = upgrades
		"repair":
			if int(run.get("base_damage", 0)) <= 0:
				return false
			apply_effect(run, chapter, {"heal": offer["amount"]})
		_:
			apply_effect(run, chapter, {"add_cards": offer["cards"]})
	run["credits"] = int(run.get("credits", 0)) - cost
	used[key] = true
	run["shop_purchases"] = used
	return true


static func service_used(run: Dictionary, node: Dictionary, offer: Dictionary) -> bool:
	if offer.get("leader_mod", false):
		return offer["id"] in run.get("leader_mods", {}).get(offer["leader_id"], [])
	return run.get("shop_purchases", {}).has("%s/%s" % [node["id"], offer["id"]])


static func complete_node(run: Dictionary, node_id: String) -> void:
	run["current"] = node_id
	run["visited"].append(node_id)
