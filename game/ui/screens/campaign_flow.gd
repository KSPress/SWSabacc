class_name CampaignFlow
extends RefCounted
## Glue between campaign screens, the save file and the match screen.


static func episode_data(ep: int) -> Dictionary:
	return CardDB.episodes.get(ep, {})


static func treasures_for(chapter: Dictionary) -> Dictionary:
	return episode_data(int(chapter.get("episode", 4))).get("treasures", {})


static func chapter_unlocked(chapter: Dictionary) -> bool:
	if int(chapter.get("number", 1)) == 1:
		return true
	var ep := episode_data(int(chapter.get("episode", 4)))
	for ch in ep.get("chapters", []):
		if int(ch.get("number", 0)) == int(chapter.get("number", 1)) - 1:
			return Save.is_cleared(ch["id"])
	return false


static func start_run(chapter: Dictionary, leader: String) -> void:
	var previous := Save.run()
	var run := CampaignRun.start(chapter, leader, randi())
	if can_continue(previous, chapter["id"]):
		for key in ["credits", "consecutive_clears", "starts_at_chapter_one", "reward_id", "card_upgrades"]:
			if previous.has(key):
				run[key] = previous[key]
	elif not previous.is_empty():
		cash_out(previous)
	Save.set_run(run)


static func can_continue(run: Dictionary, next: String) -> bool:
	if next.is_empty() or run.get("status") != "won" or run.get("cashed_out", false):
		return false
	return CardDB.chapter(run.get("chapter", "")).get("next_chapter", "") == next


static func needs_new_route(run: Dictionary, chapter: Dictionary) -> bool:
	return run.get("chapter") == chapter["id"] and run.get("status") == "active" \
		and int(run.get("route_version", 0)) != int(chapter.get("route_version", 0))


static func multiplier(run: Dictionary) -> float:
	if not run.get("starts_at_chapter_one", false):
		return 1.0
	return [1.0, 1.5, 2.0, 3.0][clampi(int(run.get("consecutive_clears", 0)), 0, 3)]


static func payout(run: Dictionary) -> int:
	return int(maxi(0, int(run.get("credits", 0))) * multiplier(run))


static func cash_out(run: Dictionary) -> int:
	if run.is_empty() or run.get("cashed_out", false) or run != Save.run():
		return 0
	run["cashed_out"] = true
	if run.get("status") == "active":
		run["status"] = "lost"
	var amount := payout(run)
	var earned := Progression.award_credits("saga:%s" % run.get("reward_id", run.get("node_seed", 0)), amount)
	if earned == 0:
		Save.write()
	return earned


static func start_node(chapter: Dictionary, node: Dictionary) -> void:
	var run := Save.run()
	if run.get("chapter") != chapter["id"] or run.get("status") != "active" \
		or needs_new_route(run, chapter) or node["id"] not in CampaignRun.available_nodes(run, chapter):
		return
	var cfg := CampaignRun.match_config(run, chapter, node, treasures_for(chapter))
	var theme: String = node.get("board_theme", chapter.get("board_theme", "space"))
	Router.go("match", {
		"mode": "campaign", "cfg": cfg, "theme": theme, "title": node.get("title", "Battle"),
		"chapter_id": chapter["id"], "node_id": node["id"], "run_id": run.get("reward_id", ""),
	})


## Called once when a campaign match ends. Mutates and saves the run.
static func on_match_end(params: Dictionary, m: Match) -> Dictionary:
	var chapter := CardDB.chapter(params["chapter_id"])
	var node := CampaignRun.node_by_id(chapter, params["node_id"])
	var run := Save.run()
	var won := m.winner == 0
	var res := {"won": won, "chapter_id": params["chapter_id"], "node_id": params["node_id"], "boss": node.get("type", "") == "boss"}
	if run.get("chapter") != chapter["id"] or run.get("status") != "active" or node.is_empty() \
		or needs_new_route(run, chapter) or node["id"] not in CampaignRun.available_nodes(run, chapter):
		return res
	if params.get("run_id", run.get("reward_id", "")) != run.get("reward_id", ""):
		return res
	run["fights"] = int(run.get("fights", 0)) + 1
	run["credits"] = int(run.get("credits", 0)) + Progression.RUN_BATTLE
	res["run_credits"] = Progression.RUN_BATTLE
	if won:
		var maxhp := CampaignRun.max_base_hp(run, chapter)
		run["base_damage"] = clampi(m.players[0].base.damage, 0, maxhp - 1)
		CampaignRun.complete_node(run, node["id"])
		var pickups: Array = node.get("pickups", [node["pickup"]] if node.has("pickup") else [])
		if not pickups.is_empty():
			run["deck"].append_array(pickups)
			res["pickups"] = pickups
		if res["boss"]:
			run["status"] = "won"
			if run.get("starts_at_chapter_one", false):
				run["consecutive_clears"] = int(run.get("consecutive_clears", 0)) + 1
			Save.clear_chapter(chapter["id"])
			res["unlocked"] = [] if Cosmetics.state()["gm"] else Save.unlock(chapter.get("unlocks_on_clear", []))
			res["pack"] = Progression.grant("Saga campaign run completed", "saga:%s:%s" % [chapter["id"], run.get("reward_id", run.get("node_seed", 0))])
		else:
			res["rewards"] = CampaignRun.roll_rewards(run, chapter, node, CardDB.lib)
			if int(node.get("reward_tier", 1)) >= 3:
				res["treasures"] = CampaignRun.roll_treasures(run, chapter)
	else:
		run["status"] = "lost"
	if not won or (res["boss"] and chapter.get("next_chapter", "").is_empty()):
		res["payout"] = cash_out(run)
	else:
		Save.set_run(run)
	return res


static func after_match(res: Dictionary) -> void:
	if res.get("won", false):
		Router.go("reward", res)
	else:
		Router.go("chapter", {"chapter_id": res["chapter_id"], "failed": true, "payout": res.get("payout", 0)})
