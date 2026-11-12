extends Node
## Durable account card entitlements and pre-rolled packs. One unlock grants a
## legal playset; packs never consume or replace existing collection entries.
signal changed

var _pools: Dictionary = {}
const PACK_PRICE := 1000
const BATTLE_WIN := 100
const BATTLE_LOSS := 50
const RUN_BATTLE := 50
const EMBLEM_CHANCE := 0.125
const BACKGROUND_CHANCE := 0.05


func _ready() -> void:
	ensure_account()


func state() -> Dictionary:
	if not Save.data.get("progression") is Dictionary:
		Save.data["progression"] = {"initialized": false, "packs": [], "claimed": {}, "traditional": 0, "sequence": 0}
	# JSON numbers load as floats; normalize indexes for exact array membership.
	for pack in Save.data["progression"]["packs"]:
		pack["revealed"] = pack["revealed"].map(func(index): return int(index))
	return Save.data["progression"]


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


func _pool(kind: String, rarity: String, set_code: String) -> Array:
	var key := set_code + ":" + kind + ":" + rarity
	if not _pools.has(key):
		var pool: Array = []
		for id in CardDB.lib.cards:
			var card := CardDB.card(id)
			if card.get("custom", false) or card.get("set") != set_code:
				continue
			if kind == "main" and not card.get("type") in ["unit", "event", "upgrade"]:
				continue
			if kind != "main" and card.get("type") != kind:
				continue
			if rarity != "" and str(card.get("rarity", "")).to_lower() != rarity:
				continue
			pool.append(id)
		pool.sort()
		_pools[key] = pool
	return _pools[key]


func credits() -> int:
	return maxi(0, int(Save.data.get("credits", 0)))


func award_credits(identity: String, amount: int) -> int:
	var claimed: Dictionary = state()["claimed"]
	var key := "credits:" + identity
	if amount <= 0 or claimed.has(key):
		return 0
	claimed[key] = true
	Save.data["credits"] = credits() + amount
	Save.write()
	changed.emit()
	return amount


func buy_pack(set_code: String) -> String:
	if credits() < PACK_PRICE or not set_code in CardLibrary.BOOSTER_SETS:
		return ""
	var id := _queue_pack("Purchased pack", set_code)
	if id.is_empty():
		return ""
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


func _queue_pack(source: String, set_code: String) -> String:
	var s := state()
	var random := RandomNumberGenerator.new()
	random.randomize()
	var cards: Array = []
	var reserved: Array = Save.data.get("vault", []).duplicate()
	for pack in s["packs"]:
		reserved.append_array(pack["cards"])
	var slots := ["common", "common", "common", "common", "common", "uncommon", "uncommon",
		"legendary" if random.randf() < 0.125 else "rare", "leader", "base"]
	for slot in slots:
		var kind: String = slot if slot in ["leader", "base"] else "main"
		var pool := _pool(kind, "" if kind != "main" else slot, set_code)
		if pool.is_empty():
			pool = _pool(kind, "rare" if slot == "legendary" else "", set_code)
		if pool.is_empty():
			return ""
		var fresh: Array = pool.filter(func(id): return not id in reserved)
		var unused: Array = pool.filter(func(id): return not id in cards)
		var choices: Array = fresh if not fresh.is_empty() else (unused if not unused.is_empty() else pool)
		var picked: String = choices[random.randi_range(0, choices.size() - 1)]
		cards.append(picked)
		reserved.append(picked)
	s["sequence"] += 1
	var id := "pack_%d" % s["sequence"]
	s["packs"].append({"id": id, "source": source, "set": set_code, "cards": cards, "revealed": [], "torn": false,
		"bonus": roll_cosmetic(random), "bonus_revealed": false})
	return id


func packs() -> Array:
	return state()["packs"]


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
		Save.unlock([pack["cards"][index]])
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


func roll_cosmetic(random: RandomNumberGenerator) -> Dictionary:
	var roll := random.randf()
	var kind := "background" if roll < BACKGROUND_CHANCE else ("emblem" if roll < BACKGROUND_CHANCE + EMBLEM_CHANCE else "")
	if kind.is_empty():
		return {}
	var reserved: Array = Cosmetics.state()["earned"].duplicate()
	for pack in packs():
		if not pack.get("bonus", {}).is_empty():
			reserved.append(pack["bonus"]["key"])
	var choices: Array = Cosmetics.all_items().filter(func(item): return item["kind"] == kind and not item["key"] in reserved)
	if choices.is_empty():
		return {}
	var reward: Dictionary = choices[random.randi_range(0, choices.size() - 1)].duplicate()
	reward["rarity"] = "Legendary" if kind == "background" else "Rare"
	return reward


func reveal_bonus(id: String) -> bool:
	for pack in packs():
		if pack["id"] != id or not pack["torn"] or pack.get("bonus_revealed", false) or pack.get("bonus", {}).is_empty():
			continue
		pack["bonus_revealed"] = true
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
