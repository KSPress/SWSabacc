extends "res://tests/run_tests.gd"

func _init() -> void:
	lib.load_file("res://ip/data/cards.json")
	lib.load_file("res://data/custom_cards.json", true)
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
