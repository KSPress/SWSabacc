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
		"deck": chapter.get("starting_deck", []).duplicate(),
		"base_hp_bonus": 0, "base_damage": 0, "credits": 0, "consecutive_clears": 0,
		"starts_at_chapter_one": int(chapter.get("number", 1)) == 1, "card_upgrades": {},
		"current": "", "visited": [], "treasures": [],
		"node_seed": seed_value, "status": "active", "fights": 0,
		"route_version": chapter.get("route_version", 0),
		"reward_id": "%s_%s" % [Time.get_unix_time_from_system(), seed_value],
	}


static func available_nodes(run: Dictionary, chapter: Dictionary) -> Array:
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
	var base_id: String = node.get("base", chapter.get("base_sequence", [""])[0])
	var deck: Array = run["deck"].duplicate()
	for id in node.get("deploy_from_deck", []):
		deck.erase(id)
	return {
		"seed": int(run.get("node_seed", 0)) + int(run.get("fights", 0)) * 7919,
		"rules": rules,
		"tokens": tokens,
		"objective": node.get("objective", {"type": "standard"}),
		"first": node.get("first", -1),
		"players": [
			{
				"name": "Rebel Alliance", "leader": run["leader"], "base": base_id,
				"deck": deck, "ai": false,
				"base_hp": max_base_hp(run, chapter), "base_damage": int(run.get("base_damage", 0)),
				"preplaced": node.get("player_preplaced", []),
				"bonus_hand": node.get("player_bonus_hand", []),
				"extra_resources": te["extra_resources"] + int(node.get("player_extra_resources", 0)),
				"first_unit_experience": te["first_unit_experience"],
				"extra_hand": te["extra_hand"], "card_upgrades": run.get("card_upgrades", {}),
			},
			{
				"name": enemy.get("name", "Enemy"), "leader": enemy.get("leader", ""),
				"base": enemy.get("base", base_id), "deck": enemy.get("deck", []), "ai": true,
				"profile": enemy.get("ai_profile", "tempo"), "hero_skin": enemy.get("hero_skin", ""),
				"base_hp": int(enemy.get("hp", 12)), "preplaced": enemy.get("preplaced", []),
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


static func buy_service(run: Dictionary, chapter: Dictionary, node: Dictionary, offer: Dictionary, card_id := "") -> bool:
	if run.get("status") != "active" or node["id"] not in available_nodes(run, chapter) or offer not in node.get("offers", []):
		return false
	var cost := int(offer["cost"])
	var used: Dictionary = run.get("shop_purchases", {})
	var key := "%s/%s" % [node["id"], offer["id"]]
	if cost < 0 or cost > int(run.get("credits", 0)) or used.has(key):
		return false
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
	return run.get("shop_purchases", {}).has("%s/%s" % [node["id"], offer["id"]])


static func complete_node(run: Dictionary, node_id: String) -> void:
	run["current"] = node_id
	run["visited"].append(node_id)
