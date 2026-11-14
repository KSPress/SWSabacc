extends Node
## Durable account card entitlements and pre-rolled packs. One unlock grants a
## legal playset; packs never consume or replace existing collection entries.
signal changed

var _pools: Dictionary = {}
const PACK_PRICE := 1000
const GM_START_CREDITS := 1000000
const BATTLE_WIN := 100
const BATTLE_LOSS := 50
const RUN_BATTLE := 50
const EMBLEM_CHANCE := 0.125
const BACKGROUND_CHANCE := 0.05


func _ready() -> void:
	if Save.existing_account:
		ensure_account()
		_migrate_spotlight_starters()


func _migrate_spotlight_starters() -> void:
	var progress := state()
	if progress.has("starting_set") or progress.get("official_starters", false) or not CardDB.loaded:
		return
	var pair := CardDB.official_pair("LOF")
	if pair.size() != 2:
		return
	var ids: Array = []
	for deck in pair:
		ids.append_array([deck["leader"], deck["base"]] + deck["cards"].keys())
	progress["official_starters"] = true
	Save.unlock(ids)


func needs_welcome() -> bool:
	return not state()["initialized"]


func starting_sets() -> Array:
	return CardLibrary.BOOSTER_SETS.filter(func(code):
		return CardDB.official_pair(code).size() == 2 and not _pool(code).is_empty())


func claim_starting_set(code: String) -> bool:
	if not needs_welcome() or code not in starting_sets():
		return false
	var progress := state()
	for deck in CardDB.official_pair(code):
		for id in [deck["leader"], deck["base"]] + deck["cards"].keys():
			if id not in Save.data["vault"]:
				Save.data["vault"].append(id)
	for index in 3:
		_queue_pack("Welcome pack", code, true)
	var stats := account_stats()
	stats["credits_earned"] = int(stats["credits_earned"]) + PACK_PRICE
	Save.data["credits"] = _account_credits() + PACK_PRICE
	progress["initialized"] = true
	progress["starting_set"] = code
	Save.write()
	changed.emit()
	return true


func state() -> Dictionary:
	if not Save.data.get("progression") is Dictionary:
		Save.data["progression"] = {"initialized": false, "packs": [], "claimed": {}, "traditional": 0, "sequence": 0}
	# JSON numbers load as floats; normalize indexes for exact array membership.
	var progress: Dictionary = Save.data["progression"]
	for queue in [progress["packs"], progress.get("gm_packs", [])]:
		for pack in queue:
			pack["revealed"] = pack["revealed"].map(func(index): return int(index))
	return progress


func ensure_account() -> void:
	if state()["initialized"] or not CardDB.loaded:
		return
	var starter: Array = []
	# Two complete starter decks make the initial account playable. Preserve
	# every saved custom deck when migrating an existing installation.
	for deck in CardDB.spotlight_for_mode("traditional").slice(0, 2) + Save.decks():
		starter.append_array([deck.get("leader", ""), deck.get("base", "")])
		starter.append_array(deck.get("cards", {}).keys())
	Save.unlock(starter.filter(func(id): return CardDB.lib.has(id)))
	state()["initialized"] = true
	Save.write()


func owns(id: String) -> bool:
	return Cosmetics.state()["gm"] or id in Save.data.get("vault", [])


func owned_ids() -> Array:
	return CardDB.lib.cards.keys() if Cosmetics.state()["gm"] else Save.data.get("vault", [])


func deck_owned(deck: Dictionary) -> bool:
	for id in [deck.get("leader", ""), deck.get("base", "")] + deck.get("cards", {}).keys():
		if not owns(id):
			return false
	return true


func _pool(set_code: String) -> Array:
	if not _pools.has(set_code):
		_pools[set_code] = CardDB.lib.query("", {"set": set_code})
	return _pools[set_code]


func account_stats() -> Dictionary:
	if not Save.data.get("stats") is Dictionary:
		Save.data["stats"] = {}
	var stats: Dictionary = Save.data["stats"]
	stats.merge(Save.default_data()["stats"])
	# Older saves only kept the current wallet. It is a lower bound on lifetime earnings.
	stats["credits_earned"] = maxi(int(stats["credits_earned"]), _account_credits())
	return stats


func count_stat(category: String, id: String) -> void:
	if not id.is_empty():
		var counts: Dictionary = account_stats()[category]
		counts[id] = int(counts.get(id, 0)) + 1


func track_match(winner: int, aspects: Array, leader_id: String, played_aspects := {}) -> void:
	var stats := account_stats()
	stats["matches"] = int(stats["matches"]) + 1
	if winner == 0:
		stats["wins"] = int(stats["wins"]) + 1
	elif winner == 2:
		stats["draws"] = int(stats["draws"]) + 1
	var seen := {}
	for aspect in aspects:
		if not seen.has(aspect):
			count_stat("aspects", aspect)
			seen[aspect] = true
	var totals: Dictionary = stats["played_aspects"]
	for aspect in played_aspects:
		totals[aspect] = int(totals.get(aspect, 0)) + int(played_aspects[aspect])
	count_stat("leaders", leader_id)


func credits() -> int:
	if Cosmetics.state()["gm"]:
		return maxi(0, int(state().get("gm_credits", GM_START_CREDITS)))
	return _account_credits()


func _account_credits() -> int:
	return maxi(0, int(Save.data.get("credits", 0)))


func award_credits(identity: String, amount: int) -> int:
	var claimed: Dictionary = state()["claimed"]
	var key := "credits:" + identity
	if amount <= 0 or claimed.has(key):
		return 0
	claimed[key] = true
	var stats := account_stats()
	stats["credits_earned"] = int(stats["credits_earned"]) + amount
	Save.data["credits"] = _account_credits() + amount
	Save.write()
	changed.emit()
	return amount


func buy_pack(set_code: String) -> String:
	if credits() < PACK_PRICE or not set_code in preload("res://ui/kit/set_art.gd").SETS:
		return ""
	var id := _queue_pack("Purchased pack", set_code)
	if id.is_empty():
		return ""
	if Cosmetics.state()["gm"]:
		state()["gm_credits"] = credits() - PACK_PRICE
	else:
		count_stat("boosters", set_code)
		Save.data["credits"] = credits() - PACK_PRICE
	Save.write()
	changed.emit()
	return id


func grant(source: String, identity: String) -> String:
	var s := state()
	if Cosmetics.state()["gm"] or s["claimed"].has(identity):
		return ""
	var set_code: String = CardLibrary.BOOSTER_SETS.pick_random()
	var id := _queue_pack(source, set_code)
	if not id.is_empty():
		s["claimed"][identity] = true
		Save.write()
		changed.emit()
	return id


func _queue_pack(source: String, set_code: String, account_pack := false) -> String:
	var s := state()
	var random := RandomNumberGenerator.new()
	random.randomize()
	var cards: Array = []
	var pool := _pool(set_code)
	if pool.is_empty():
		return ""
	for index in 10:
		cards.append(pool[random.randi_range(0, pool.size() - 1)])
	s["sequence"] += 1
	var id := "pack_%d" % s["sequence"]
	var queue: Array = s["packs"] if account_pack else packs()
	queue.append({"id": id, "source": source, "set": set_code, "cards": cards, "revealed": [], "torn": false,
		"bonus": roll_cosmetic(random, set_code), "bonus_revealed": false})
	return id


func packs() -> Array:
	var progress := state()
	if Cosmetics.state()["gm"]:
		if not progress.has("gm_packs"):
			progress["gm_packs"] = []
		return progress["gm_packs"]
	return progress["packs"]


func tear(id: String) -> void:
	for pack in packs():
		if pack["id"] == id:
			pack["torn"] = true
			Save.write()


func reveal(id: String, index: int) -> bool:
	for pack in packs():
		if pack["id"] != id or not pack["torn"] or index < 0 or index >= pack["cards"].size() or index in pack["revealed"]:
			continue
		pack["revealed"].append(index)
		var card_id: String = pack["cards"][index]
		var gm: bool = Cosmetics.state()["gm"]
		var test_cards: Array = state().get("gm_cards", [])
		if card_id in Save.data["vault"] or (gm and card_id in test_cards):
			var amount := randi_range(50, 100)
			var refunds: Dictionary = pack.get("refunds", {})
			refunds[str(index)] = amount
			pack["refunds"] = refunds
			if gm:
				state()["gm_credits"] = credits() + amount
				Save.write()
				changed.emit()
			else:
				award_credits("duplicate:%s:%d" % [id, index], amount)
		elif gm:
			test_cards.append(card_id)
			state()["gm_cards"] = test_cards
			Save.write()
			changed.emit()
		else:
			Save.unlock([card_id])
			changed.emit()
		return true
	return false


func finish(id: String) -> bool:
	for pack in packs():
		if pack["id"] == id and pack["revealed"].size() == pack["cards"].size() and (pack.get("bonus", {}).is_empty() or pack.get("bonus_revealed", false)):
			packs().erase(pack)
			Save.write()
			changed.emit()
			return true
	return false


func roll_cosmetic(random: RandomNumberGenerator, set_code := "") -> Dictionary:
	var roll := random.randf()
	var kind := "background" if roll < BACKGROUND_CHANCE else ("emblem" if roll < BACKGROUND_CHANCE + EMBLEM_CHANCE else "")
	if kind.is_empty():
		return {}
	var reserved: Array = Cosmetics.state()["earned"].duplicate()
	if Cosmetics.state()["gm"]:
		reserved.append_array(state().get("gm_cosmetics", []))
	for pack in packs():
		if not pack.get("bonus", {}).is_empty():
			reserved.append(pack["bonus"]["key"])
	var choices: Array = Cosmetics.all_items().filter(func(item): return item["kind"] == kind and not item["key"] in reserved)
	if choices.is_empty():
		return {}
	var set_background := preload("res://ui/kit/set_art.gd").background_id(set_code)
	if kind == "background":
		var matching := choices.filter(func(item): return item["id"] == set_background)
		if not matching.is_empty():
			choices = matching
	var reward: Dictionary = choices[random.randi_range(0, choices.size() - 1)].duplicate()
	reward["rarity"] = "Legendary" if kind == "background" else "Rare"
	return reward


func reveal_bonus(id: String) -> bool:
	for pack in packs():
		if pack["id"] != id or not pack["torn"] or pack.get("bonus_revealed", false) or pack.get("bonus", {}).is_empty():
			continue
		pack["bonus_revealed"] = true
		if Cosmetics.state()["gm"]:
			var test_cosmetics: Array = state().get("gm_cosmetics", [])
			test_cosmetics.append(pack["bonus"]["key"])
			state()["gm_cosmetics"] = test_cosmetics
		else:
			Cosmetics.award(pack["bonus"]["key"])
		Save.write()
		changed.emit()
		return true
	return false


func traditional_result(identity: String) -> String:
	if Cosmetics.state()["gm"]:
		return ""
	var s := state()
	var key := "battle:" + identity
	if s["claimed"].has(key):
		return ""
	s["claimed"][key] = true
	s["traditional"] += 1
	Save.write()
	if int(s["traditional"]) % 2 == 0:
		return grant("Two traditional battles", "battle_pack:%d" % s["traditional"])
	changed.emit()
	return ""
