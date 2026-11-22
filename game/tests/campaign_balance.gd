extends "res://tests/run_tests.gd"

func _init() -> void:
	lib.load_file("res://ip/data/cards.json")
	lib.load_file("res://data/custom_cards.json", true)
	if "saga_balance" in OS.get_cmdline_user_args():
		var episode: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/ep4.json"))
		test_saga_balance(episode)
		quit(1 if failures else 0)
		return
	if "saga" in OS.get_cmdline_user_args():
		var episode: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/ep4.json"))
		simulate_chapter(episode["chapters"][1], 20)
		quit(1 if failures else 0)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/spotlight_decks.json"))
	var spots: Array = data["decks"].filter(func(d): return "traditional" in d.get("modes", []))
	var rows: Array = []
	for spot in spots:
		var wins := 0
		var rounds := 0
		for seed_value in 6:
			var run := SpotlightRun.start(spot, lib, 2000 + seed_value, spots)
			var available := SpotlightRun.available_nodes(run)
			var node: Dictionary = {}
			for id in available:
				var candidate := SpotlightRun.node(run, id)
				if candidate.has("enemy"):
					node = candidate
					break
			if node.is_empty():
				continue
			var config := SpotlightRun.match_config(run, node)
			config["players"][0]["ai"] = true
			var match_game := Match.new()
			match_game.setup(lib, config)
			for step in 4000:
				if match_game.is_over():
					break
				if not match_game.pending.is_empty():
					AiBot.choose(match_game)
				else:
					AiBot.act(match_game)
			check(match_game.is_over(), "first encounter finishes")
			wins += int(match_game.winner == 0)
			rounds += match_game.round_num
		rows.append({"deck": spot["id"], "wins": wins, "games": 6, "rounds": rounds / 6.0})
		print("BALANCE ", rows.back())
	var path := "res://../build/qa/packs/balance.json"
	if not OS.get_cmdline_user_args().is_empty():
		path = OS.get_cmdline_user_args()[0]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "  "))
	print("BALANCE CHECKS ", passes, " passed, ", failures, " failed")
	quit(1 if failures else 0)


func test_saga_balance(episode: Dictionary) -> void:
	var tatooine: Dictionary = episode["chapters"][0]
	var raid := CampaignRun.node_by_id(tatooine, "tusken_raid")
	var raid_wins := 0
	for seed_value in 16:
		var run := CampaignRun.start(tatooine, tatooine["leader_options"][0], seed_value * 101)
		var battle := play_saga_battle(run, tatooine, raid, episode, true)
		raid_wins += int(battle.winner == 0)
		if battle.winner != 0:
			print("RAID loss seed ", run["node_seed"], " round ", battle.round_num)
	print("RAID with one missed Krayt Call: %d/16 cleared" % raid_wins)
	check(raid_wins >= 14, "Tusken Raid allows a missed Krayt Call on most tested opening draws")
	for chapter in episode["chapters"]:
		for leader in chapter["leader_options"]:
			var clears := 0
			for seed_value in [10, 37, 71, 103, 120, 158]:
				clears += int(play_saga_route(chapter, leader, episode, seed_value))
			print("ROUTES %s / %s: %d/6 cleared" % [chapter["id"], leader, clears])
			check(clears > 0, "%s / %s can clear a full route" % [chapter["id"], leader])


func play_saga_route(chapter: Dictionary, leader: String, episode: Dictionary, seed_value: int) -> bool:
	var run := CampaignRun.start(chapter, leader, seed_value)
	var path_index := seed_value
	while not CampaignRun.available_nodes(run, chapter).is_empty():
		var available := CampaignRun.available_nodes(run, chapter)
		var id: String = available[path_index % available.size()]
		var node := CampaignRun.node_by_id(chapter, id)
		path_index += 1
		if node.has("enemy"):
			var battle := play_saga_battle(run, chapter, node, episode)
			if battle.winner != 0:
				print("ROUTE loss %s / %s / %d at %s (round %d)" % [chapter["id"], leader, seed_value, id, battle.round_num])
				return false
			run["credits"] += 50
			run["base_damage"] = CampaignRun.damage_after_victory(run, chapter, battle.players[0].base.damage)
			run["fights"] += 1
			run["deck"].append_array(node.get("pickups", [node["pickup"]] if node.has("pickup") else []))
			var rewards := CampaignRun.roll_rewards(run, chapter, node, lib)
			if not rewards.is_empty():
				run["deck"].append(rewards[0])
			if node["type"] == "boss":
				return true
		elif node["type"] == "event":
			CampaignRun.apply_effect(run, chapter, node["event"]["choices"][0]["effect"])
		elif node.get("shop", false):
			for offer in node.get("offers", []):
				if offer["id"] in ["repair", "recruit_jawas"]:
					CampaignRun.buy_service(run, chapter, node, offer)
		elif node["type"] == "rest" and "heal" in node.get("rest", {}).get("options", ["heal"]):
			CampaignRun.apply_effect(run, chapter, {"heal": 8})
		CampaignRun.complete_node(run, id)
	return false


func play_saga_battle(run: Dictionary, chapter: Dictionary, node: Dictionary, episode: Dictionary, miss_call := false) -> Match:
	var battle := Match.new()
	battle.setup(lib, CampaignRun.match_config(run, chapter, node, episode.get("treasures", {})))
	for _step in 2000:
		if battle.is_over():
			break
		if not battle.pending.is_empty():
			AiBot.choose(battle)
			continue
		if miss_call and battle.active == 0 and battle.round_num == 2:
			# Leave the call unused this round while continuing to defend with cards.
			var best := {"a": "pass"}
			var score := 0.6
			for action in battle.legal_actions(0):
				if action.get("token") == "krayt_call":
					continue
				var value := AiBot.score_action(battle, 0, action)
				if value > score:
					best = action
					score = value
			battle.do_action(best)
		else:
			AiBot.act(battle)
	check(battle.is_over(), "%s reaches a result" % node["id"])
	return battle
