extends "res://tests/shots.gd"
var checks := 0
var failures := 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", description)


func _run() -> void:
	Save.data = Save.default_data()
	Progression.ensure_account()
	var starter: Array = Save.data["vault"].duplicate()
	check(starter.size() > 30, "playable starter collection granted")
	check(Progression.deck_owned(CardDB.spotlight_for_mode("traditional")[0]), "starter deck is owned")
	var random := RandomNumberGenerator.new()
	random.seed = 8
	var restricted := DeckBuilder.auto_deck(CardDB.lib, "SOR_009", "HMW_019", 50, random, ["ground", "space"], 7, ["SOR_095"])
	check(restricted.size() == 3 and restricted.all(func(id): return id == "SOR_095"), "auto-build never adds locked cards or excess copies")
	var locked := ""
	for id in CardDB.lib.cards:
		if not Progression.owns(id) and CardDB.card(id).get("type") == "unit":
			locked = id
			break
	check(not locked.is_empty(), "new collection leaves cards to earn")
	Cosmetics.set_gm(true)
	check(Progression.owns(locked), "GM grants card access")
	check(Progression.grant("GM", "gm_test").is_empty(), "GM cannot earn packs for account")
	check(Progression.traditional_result("gm_game").is_empty() and Progression.state()["traditional"] == 0, "GM does not advance account pack meter")
	Cosmetics.set_gm(false)
	check(not Progression.owns(locked) and Save.data["vault"] == starter, "GM leaves account collection intact")
	check(Progression.traditional_result("a").is_empty(), "first traditional game no pack")
	check(Progression.traditional_result("a").is_empty() and Progression.state()["traditional"] == 1, "duplicate match cannot advance pack meter")
	check(not Progression.traditional_result("b").is_empty(), "second traditional game earns pack")
	var pack: Dictionary = Progression.packs()[0]
	var id: String = pack["id"]
	var cards: Array = pack["cards"].duplicate()
	check(cards.size() == 10, "ten-card pack")
	check(CardDB.card(cards[8])["type"] == "leader" and CardDB.card(cards[9])["type"] == "base", "guaranteed leader and base")
	check(CardDB.card(cards[7])["rarity"] in ["Rare", "Legendary"], "rare-or-better slot")
	var unique := {}
	for card in cards:
		unique[card] = true
	check(unique.size() == 10, "no duplicate slots in fresh pack")
	check(not Progression.reveal(id, 0), "sealed pack cannot reveal")
	check(not Progression.finish(id), "unopened pack cannot disappear")
	Progression.tear(id)
	check(Progression.reveal(id, 0) and Progression.owns(cards[0]), "reveal permanently unlocks card")
	check(not Progression.reveal(id, 0), "duplicate flip ignored")
	Save.load_save()
	check(Progression.packs()[0]["cards"] == cards and Progression.packs()[0]["revealed"] == [0], "pack contents and reveal survive restart")
	for index in range(1, 10):
		check(Progression.reveal(id, index), "reveal remaining slot")
	if not Progression.packs()[0].get("bonus", {}).is_empty():
		Progression.reveal_bonus(id)
	check(Progression.finish(id) and Progression.packs().is_empty(), "fully revealed pack can finish")
	check(Progression.grant("Test", "battle_pack:2").is_empty(), "reward identity cannot grant twice")
	# Save migration retains existing custom decks as usable playsets.
	Save.data = Save.default_data()
	Save.data["decks"] = [{"id": "legacy", "leader": cards[8], "base": cards[9], "cards": {cards[0]: 3}}]
	Progression.ensure_account()
	check(Progression.deck_owned(Save.data["decks"][0]), "existing custom decks survive collection migration")
	# End-of-run rewards use durable run identity, with no abandon farming.
	var spot: Dictionary = SpotlightFlow.spots()[0]
	var run := SpotlightRun.start(spot, CardDB.lib, 123, SpotlightFlow.spots())
	run["status"] = "abandoned"
	SpotlightFlow.save_run(run)
	SpotlightFlow.finish(run)
	check(Progression.packs().is_empty(), "abandoning fresh run earns no pack")
	run["status"] = "dead"
	run["stats"]["wins"] = 1
	SpotlightFlow.save_run(run)
	SpotlightFlow.finish(run)
	check(Progression.packs().size() == 1, "completed run with victory earns pack")
	# The Saga campaign's terminal node is an actual completed chapter run.
	var chapter: Dictionary = CardDB.episodes[4]["chapters"][0]
	var saga_run := CampaignRun.start(chapter, chapter["leader_options"][0], 987)
	Save.set_run(saga_run)
	var match_game := Match.new()
	match_game.setup(CardDB.lib, CampaignRun.match_config(saga_run, chapter, CampaignRun.node_by_id(chapter, "boss"), CampaignFlow.treasures_for(chapter)))
	match_game.winner = 0
	var result := CampaignFlow.on_match_end({"chapter_id": chapter["id"], "node_id": "boss"}, match_game)
	check(not result.get("pack", "").is_empty() and Progression.packs().size() == 2, "Saga completion grants pack")
	# Use a single pack for the visual flow below.
	Progression.packs().pop_back()
	Save.write()
	# UI: landscape/portrait, sealed, exploded cards, individual flips and resume.
	await _size(1280, 720)
	await _go("menu")
	check(get_tree().current_scene._buttons.get_child(0).text == "Campaigns" and get_tree().current_scene._buttons.get_child(1).text == "Battles", "two main mode entries")
	await _shot("menu_groups")
	await _go("hub", {"section": "campaigns"})
	await _shot("campaigns_hub")
	await _go("hub", {"section": "battles"})
	await _shot("battles_hub")
	await _go("packs")
	await _shot("pack_sealed")
	var screen := get_tree().current_scene
	screen._rip()
	await _wait(1.5)
	check(screen._slots.size() == 10 + (0 if screen._pack.get("bonus", {}).is_empty() else 1), "rip deals ten cards and any bonus")
	await _shot("pack_explosion_settled")
	screen._flip(screen._slots[7])
	await _wait(0.6)
	check(7 in Progression.packs()[0]["revealed"], "UI rare flip persists")
	await _shot("pack_rare_reveal")
	await _size(540, 960)
	await _wait(0.6)
	for slot in screen._slots:
		check(Rect2(Vector2.ZERO, screen.body.size).encloses(slot.get_rect()), "portrait card slot inside screen")
	await _shot("pack_portrait")
	for slot in screen._slots:
		if not slot.get_meta("index") in screen._pack["revealed"]:
			screen._flip(slot)
	await _wait(0.8)
	check(not screen._done.disabled, "collect button enabled after all flips")
	await _shot("pack_all_revealed")
	screen._advance()
	check(Progression.packs().is_empty(), "UI collect completes pack")
	_test_credits_and_episode()
	print("PROGRESSION: %d checks, %d failed" % [checks, failures])
	if failures:
		get_tree().quit(1)


func _test_credits_and_episode() -> void:
	Save.data = Save.default_data()
	check(Progression.credits() == 0, "wallet starts at zero")
	check(Progression.award_credits("battle:win", Progression.BATTLE_WIN) == 100, "win credits")
	check(Progression.award_credits("battle:loss", Progression.BATTLE_LOSS) == 50, "loss credits")
	check(Progression.award_credits("battle:win", 100) == 0 and Progression.credits() == 150, "battle credits pay once")
	check(Progression.buy_pack("TWI").is_empty() and Progression.credits() == 150, "unaffordable pack leaves the wallet alone")
	Progression.award_credits("fund-purchase", 850)
	check(Progression.buy_pack("unknown").is_empty() and Progression.credits() == 1000, "unknown set leaves the wallet alone")
	var purchased := Progression.buy_pack("TWI")
	check(not purchased.is_empty() and Progression.credits() == 0, "purchase consumes exactly 1,000 credits")
	Save.load_save()
	var pack: Dictionary = Progression.packs()[0]
	check(pack["id"] == purchased and pack["set"] == "TWI"
		and pack["cards"].all(func(id): return CardDB.card(id)["set"] == "TWI")
		and Progression.credits() == 0, "single-set purchase and wallet persist together")

	var chapters: Array = CardDB.episodes[4]["chapters"]
	for index in chapters.size():
		var ch: Dictionary = chapters[index]
		CampaignFlow.start_run(ch, ch["leader_options"][0])
		var run := Save.run()
		check(int(run["credits"]) == [0, 30, 80][index], "Saga carries the remaining run balance")
		var game := Match.new()
		var boss := CampaignRun.node_by_id(ch, "boss")
		game.setup(CardDB.lib, CampaignRun.match_config(run, ch, boss, CampaignFlow.treasures_for(ch)))
		game.winner = 0
		var outcome := CampaignFlow.on_match_end({"chapter_id": ch["id"], "node_id": "boss"}, game)
		check(CampaignFlow.multiplier(run) == [1.5, 2.0, 3.0][index], "consecutive Saga clear increases the payout multiplier")
		if index == 0:
			run["credits"] = int(run["credits"]) - 20
			Save.set_run(run)
			Save.load_save()
		if index < 2:
			check(Progression.credits() == 0, "checkpoint retains run credits outside the wallet")
		else:
			check(outcome.get("payout", 0) == 390 and Progression.credits() == 390, "full run pays three times the net credits")
			check(CampaignFlow.cash_out(run) == 0, "Saga cash-out is idempotent")

	var spot: Dictionary = SpotlightFlow.spots()[0]
	var spotlight := SpotlightFlow.start(spot["id"])
	var next: String = SpotlightRun.available_nodes(spotlight)[0]
	SpotlightRun.on_battle_end(spotlight, next, true, 3, CardDB.lib)
	check(spotlight["credits"] == 50 and Progression.credits() == 390, "Spotlight battle funds the run")
	SpotlightRun.apply_effect(spotlight, {"credits": -20, "heal": 6}, CardDB.lib, RandomNumberGenerator.new())
	check(spotlight["credits"] == 30 and Progression.credits() == 390, "Spotlight shop only spends run credits")
	spotlight["status"] = "abandoned"
	check(SpotlightFlow.finish(spotlight) == 30 and Progression.credits() == 420, "Spotlight deposits the unspent balance")
	check(SpotlightFlow.finish(spotlight) == 0, "Spotlight cash-out is idempotent")
