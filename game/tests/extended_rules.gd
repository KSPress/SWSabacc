extends "res://tests/run_tests.gd"


func _init() -> void:
	lib.load_file("res://ip/data/cards.json")
	lib.load_file("res://data/custom_cards.json", true)
	test_upgrade_targets()
	test_disclosure()
	test_continuous_printed_rules()
	test_next_unit_and_copy_limit()
	test_commanded_attacks()
	run_card_case(test_cross_arena_attacks, ["SOR_212", "JTL_259", "ASH_037"])
	run_card_case(test_red_leader_pilots, ["JTL_101"])
	run_card_case(test_relentless, ["SOR_089"])
	run_card_case(test_all_unit_selectors, ["SOR_039", "SEC_078", "TS26_016", "ASH_083"])
	run_card_case(test_fetts_firespray, ["SOR_184"])
	run_card_case(test_occupation_officer, ["HMW_242"])
	run_card_case(test_boba_disintegrator, ["SOR_179"])
	test_scaled_printed_effects()
	test_ambush_combat_auras()
	run_card_case(test_unit_departure, ["JTL_096"])
	test_attached_printed_rules()
	test_continuous_rules()
	test_capture_and_bounty()
	test_plot_and_fortify()
	test_fortifications()
	run_card_case(test_reported_card_abilities, ["ASH_172", "LOF_191", "LOF_016"])
	run_card_case(test_tie_advanced, ["SOR_231"])
	test_early_combat_and_tokens()
	test_shared_unit_triggers()
	test_attack_end_results()
	test_multiword_traits()
	test_support_and_recovery()
	test_coordinate_triggers()
	test_card_play_triggers()
	run_card_case(test_defeat_and_deploy_triggers, ["LOF_130", "TWI_025"])
	run_card_case(test_base_epic_actions, ["SOR_019"])
	test_attack_timing()
	test_play_sequence_choices()
	test_resource_and_return_costs()
	test_granted_ambush_on_play()
	test_staged_audit_cases()
	test_variable_printed_stats()
	test_optional_card_choices()
	test_campaign_krayt_call()
	test_campaign_attack_pressure()
	test_piloting()
	test_pilot_catalog()
	run_card_case(test_special_bases, ["JTL_024", "JTL_025", "JTL_028", "LOF_025", "LAW_029", "LAW_026", "LAW_019"])
	test_pilot_replacements()
	test_base_and_fortify_catalog()
	test_indirect_damage()
	test_multi_mode_events()
	test_printed_event_rules()
	test_play_discounts()
	test_advantage_and_weakness()
	test_ability_usage_limits()
	test_optional_trigger_limit()
	test_hands_and_force_events()
	test_next_regroup_effects()
	test_deck_search_filters()
	test_play_units_from_deck()
	test_play_from_discard()
	run_card_case(test_delayed_search_play, ["SHD_194", "LAW_074"])
	test_discard_selection_followups()
	test_immediate_replays()
	test_resources_and_action_start()
	test_combat_order_and_modifiers()
	test_phase_damage_history()
	test_search_and_bounty_payoffs()
	test_attack_trigger_order()
	test_entry_trigger_order()
	test_damage_and_heal_triggers()
	test_jabba_action_play_requirements()
	test_rebel_attack_sequences()
	test_upgrade_defeat_and_ready_aura()
	test_unit_control_changes()
	test_upgrade_search_filters()
	test_spotlight_rules()
	test_campaign_redesign()
	print("EXTENDED RULES: %d passed, %d failed" % [passes, failures])
	quit(1 if failures else 0)


func test_campaign_redesign() -> void:
	var episode: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/ep4.json"))
	var pack_sizes := {}
	for chapter in episode["chapters"]:
		for seed_value in range(24):
			var saga := CampaignRun.start(chapter, chapter["leader_options"][0], seed_value)
			var count := CampaignRun.completion_pack_size(saga, chapter)
			pack_sizes[count] = true
			check(count == CampaignRun.completion_pack_size(saga.duplicate(true), chapter), "Saga pack size survives a save reload")
		var saga := CampaignRun.start(chapter, chapter["leader_options"][0], 52)
		for node in chapter["nodes"]:
			if not node.has("enemy"):
				continue
			var config := CampaignRun.match_config(saga, chapter, node, {})
			var original := CampaignRun.encounter_enemy(saga, node)
			var extra := 2 if config["objective"].get("type", "standard") == "standard" else 0
			check(config["players"][1]["base_hp"] == int(original.get("hp", 12)) + extra,
				"Saga raises enemy base HP only in standard encounters")
	check(pack_sizes.size() == 5 and pack_sizes.has(8) and pack_sizes.has(12), "Saga completion rewards span 8–12 cards")

	var spots := spotlight_pool().filter(func(deck): return "traditional" in deck["modes"])
	var spot: Dictionary = spots.filter(func(deck): return deck["id"] == "twi_ahsoka")[0]
	var first := SpotlightRun.start(spot, lib, 1718, spots)
	check(first["map"] == SpotlightRun.start(spot, lib, 1718, spots)["map"]
		and first["map"] != SpotlightRun.start(spot, lib, 1719, spots)["map"], "Spotlight maps are seeded and vary between runs")
	var factions := {}
	var missions := {}
	for chapter in 4:
		var faction := SpotlightRun.chapter_faction(first)
		factions[faction["name"]] = true
		for node in first["map"]["nodes"].values():
			if not node.has("enemy"):
				continue
			var enemy: Dictionary = node["enemy"]
			if node["type"] == "boss":
				check(enemy["deck"].size() == 50 and enemy["preplaced"].is_empty() and enemy["leader"] != spot["leader"],
					"The chapter boss has a full deck and uses another leader")
			else:
				check(enemy["deck"].size() >= 17 and enemy["deck"].all(func(id):
					return faction["traits"].any(func(tag): return tag in lib.get_card(id).get("traits", []))),
					"The patrol deck is playable and every card fits the chapter theme")
			if node["type"] == "objective":
				missions[node["objective"]["type"]] = true
				check(node["title"] in faction["missions"], "Special missions use faction-specific titles")
		SpotlightRun.next_sector(first, lib, spots)
	check(factions.size() == 4 and missions.size() >= 2, "The first four chapters cycle all factions and vary objectives")

	var run := SpotlightRun.start(spot, lib, 42, spots)
	var starter: String = run["deck"].keys()[0]
	check(SpotlightRun.deck_size(run) == 20 and not SpotlightRun.remove_card(run, starter), "Run starts with 20 cards and cannot sell below the minimum")
	for row in run["map"]["rows"]:
		var available := SpotlightRun.available_nodes(run)
		check(not available.is_empty() and available[0] in row, "A themed route remains connected")
		var id: String = available[0]
		var node := SpotlightRun.node(run, id)
		if node.has("enemy"):
			var reward := SpotlightRun.on_battle_end(run, id, true, 0, lib)
			check(reward["reward"]["recovered"] > 0, "Winning a first-chapter battle recovers more of the Spotlight list")
		else:
			run["current"] = id
			run["visited"].append(id)
	var complete: bool = spot["cards"].keys().all(func(id): return int(run["owned"].get(id, 0)) == int(spot["cards"][id]))
	check(run["locked"].is_empty() and complete and SpotlightRun.deck_size(run) == 50,
		"Clearing the first boss recovers every original copy even without loot picks")
	var stock := SpotlightRun.shop_stock(run, lib, "test_market")
	var offer: String = stock.filter(func(id): return int(run["deck"].get(id, 0)) < 3 and id != starter).front()
	check(SpotlightRun.trade_card(run, starter, offer) and SpotlightRun.deck_size(run) == 50
		and not SpotlightRun.trade_card(run, offer, offer), "A market trade exchanges one active card without shrinking the deck")
	check(SpotlightRun.shop_stock(run, lib, "test_market") == stock, "Market stock stays fixed after a trade")


func run_card_case(test: Callable, ids: Array[String]) -> void:
	var passed_before := passes
	var failed_before := failures
	test.call()
	if failures == failed_before and passes > passed_before:
		for id in ids:
			print("CARD_RULE_CASE ", id)


func test_attack_trigger_order() -> void:
	var m := funded_match()
	var attacker := add_unit(m, 0, "SOR_095")
	var defender := add_unit(m, 1, "SOR_088")
	var attack_rule := {"trigger": "on_attack", "text": "Draw a card", "effects": [{"op": "draw"}]}
	var defense_rule := {"trigger": "when_attacked", "text": "Defeat the attacker", "effects": [{"op": "defeat", "t": {"s": "it"}}]}
	attacker.mods.append({"kw": "restore", "v": 1, "abilities": [attack_rule]})
	defender.mods.append({"abilities": [defense_rule]})
	m.players[0].base.damage = 3
	check(m.do_action({"a": "attack", "uid": attacker.uid, "target": defender.uid}) and m.pending.get("player") == 0
		and m.pending.get("options", []).size() == 2, "The active player chooses the first controller when both have triggers")
	check(m.submit_choice([1]) and attacker.zone == "discard" and m.pending.get("player") == 0,
		"The defender's trigger defeats the attacker before the attacker's abilities resolve")
	var restore_index: int = m.pending.get("labels", []).find_custom(func(label): return "Restore 1" in label)
	check(restore_index >= 0 and m.submit_choice([m.pending["options"][restore_index]]) and m.players[0].base.damage == 2
		and m.cards_drawn_this_phase[0] == 1 and defender.damage == 0,
		"The attacker controller orders the captured triggers even after the attacker leaves play")


func test_entry_trigger_order() -> void:
	for shield_first in [false, true]:
		var m := funded_match()
		var entering := add_unit(m, 0, "SOR_095", false)
		var defender := add_unit(m, 1, "SOR_095")
		entering.mods.append_array([{"kw": "shielded"}, {"kw": "ambush"}])
		m._on_unit_enters(entering, "when_played")
		m.pump()
		check(m.pending.get("op") == "_ordered_triggers" and m.submit_choice([0 if shield_first else 1]),
			"Shielded and Ambush can be ordered by their controller")
		check(defender.uid in m.pending.get("options", []) and m.submit_choice([defender.uid])
			and entering.in_play() == shield_first, "Resolving Shielded before Ambush prevents the retaliation from defeating the unit")


func test_cross_arena_attacks() -> void:
	var m := funded_match()
	var gunship := add_unit(m, 0, "SOR_212")
	var ground := add_unit(m, 1, "SOR_095")
	var space := add_unit(m, 1, "SOR_225")
	var ground_guard := add_unit(m, 1, "SOR_229")
	check(ground.uid in m.attack_targets(gunship) and space.uid in m.attack_targets(gunship),
		"Strafing Gunship can attack both arenas, even with a Sentinel in the other arena")
	var space_guard := add_unit(m, 1, "SOR_066")
	var screened := m.attack_targets(gunship)
	check(screened.size() == 2 and space_guard.uid in screened and ground_guard.uid in screened,
		"Space Sentinel protects the base and non-Sentinels, including ground units")
	gunship.mods.append({"kw": "saboteur"})
	check(m.do_action({"a": "attack", "uid": gunship.uid, "target": ground.uid}) and gunship.damage == 1,
		"Strafing Gunship with Saboteur attacks a ground unit and reduces its return damage by two")

	var ambush := funded_match()
	var airspeeder := put_in_hand(ambush, "JTL_259")
	var defender := add_unit(ambush, 1, "SOR_066")
	check(ambush.do_action({"a": "play", "uid": airspeeder.uid}) and defender.uid in ambush.pending.get("options", []),
		"Retrofitted Airspeeder can Ambush a space unit")
	check(ambush.submit_choice([defender.uid]) and defender.damage == airspeeder.data["power"] - 1,
		"Retrofitted Airspeeder deals one less combat damage to a space defender")

	var support := funded_match()
	var attacker := add_unit(support, 0, "SOR_095")
	var ship := add_unit(support, 1, "SOR_225")
	var red_leader := put_in_hand(support, "ASH_037")
	check(support.do_action({"a": "play", "uid": red_leader.uid}) and support.submit_choice([attacker.uid]),
		"Red Leader's Support can choose a ground unit")
	check(ship.uid in support.pending.get("options", []) and support.submit_choice([ship.uid]) and ship.zone == "discard",
		"Red Leader grants the ability to attack in either arena before a target is chosen")
	check(attacker.abilities_with("constant").all(func(ability): return ability.get("flag") != "attack_other_arena"),
		"The borrowed cross-arena ability expires after the attack")


func test_red_leader_pilots() -> void:
	var m := funded_match()
	var leader := put_in_hand(m, "JTL_101")
	var friendly_ship := add_unit(m, 0, "SOR_225")
	add_unit(m, 0, "JTL_034")
	add_unit(m, 1, "JTL_034")
	var pilot := m._new_inst("JTL_058", 0)
	m.attach_upgrade(pilot, friendly_ship)
	check(m.play_cost(0, leader) == 2, "Jump to Lightspeed Red Leader counts friendly Pilot units and upgrades only")
	check(m.do_action({"a": "play", "uid": leader.uid}), "Jump to Lightspeed Red Leader can be played at the discounted cost")
	var count: int = m.players[0].units.size()
	m.attach_upgrade(m._new_inst("JTL_058", 0), leader)
	m.pump()
	check(m.players[0].units.size() == count + 1 and m.players[0].units.back().name() == "X-Wing",
		"Attaching a Pilot to Jump to Lightspeed Red Leader creates an X-Wing")


func test_relentless() -> void:
	var m := funded_match()
	add_unit(m, 1, "SOR_089")
	var base: CardInst = m.players[0].base
	base.damage = 5
	var first := put_in_hand(m, "SOR_074")
	var ready: int = m.players[0].available()
	check(m.do_action({"a": "play", "uid": first.uid}) and first.zone == "discard"
		and m.pending.is_empty() and base.damage == 5 and m.players[0].available() == ready - 1
		and first in m.played_this_phase[0], "Relentless suppresses the first event after payment and still counts it as played")
	m.active = 0
	var second := put_in_hand(m, "SOR_074")
	check(m.do_action({"a": "play", "uid": second.uid}) and m.submit_choice([base.uid]) and base.damage == 2,
		"A later event resolves normally against Relentless")
	m.start_action_phase()
	m.active = 0
	var smuggled := m._new_inst("SHD_129", 0)
	m.move_to_resources(0, smuggled)
	var next_resource: CardInst = m.players[0].deck[0]
	ready = m.players[0].available()
	check(m.do_action({"a": "smuggle", "uid": smuggled.uid}) and smuggled.zone == "discard"
		and next_resource.zone == "resource" and next_resource.exhausted
		and m.players[0].available() == ready - 2 and m.pending.is_empty(),
		"The next round's first event is blanked even when smuggled and still pays its full Smuggle cost")

	var late := funded_match()
	base = late.players[0].base
	base.damage = 8
	first = put_in_hand(late, "SOR_074")
	check(late.do_action({"a": "play", "uid": first.uid}) and late.submit_choice([base.uid]) and base.damage == 5,
		"The first event resolves if Relentless has yet to enter play")
	add_unit(late, 0, "SOR_089")
	add_unit(late, 1, "SOR_089")
	late.active = 0
	second = put_in_hand(late, "SOR_074")
	check(late.do_action({"a": "play", "uid": second.uid}) and late.submit_choice([base.uid]) and base.damage == 2,
		"Relentless respects events already played and leaves its controller's events alone")
	late.start_action_phase()
	late.active = 0
	late.defeat(late.players[1].units[0])
	late.pump()
	first = put_in_hand(late, "SOR_074")
	check(late.do_action({"a": "play", "uid": first.uid}) and late.submit_choice([base.uid]) and base.damage == 0,
		"Only a live opposing Relentless blanks the first event")


func test_all_unit_selectors() -> void:
	var m := funded_match()
	var friendly_ground := add_unit(m, 0, "SOR_095")
	var enemy_ground := add_unit(m, 1, "SOR_095")
	var friendly_space := add_unit(m, 0, "SOR_225")
	var enemy_space := add_unit(m, 1, "SOR_225")
	var suppressor := put_in_hand(m, "SOR_039")
	check(m.do_action({"a": "play", "uid": suppressor.uid}) and m.pending.is_empty()
		and friendly_ground.exhausted and enemy_ground.exhausted and not friendly_space.exhausted
		and not enemy_space.exhausted, "AT-AT Suppressor exhausts all ground units on both sides and leaves space ready")
	m = funded_match()
	friendly_ground = add_unit(m, 0, "SOR_095")
	enemy_ground = add_unit(m, 1, "SOR_095")
	friendly_space = add_unit(m, 0, "SOR_225")
	enemy_space = add_unit(m, 1, "SOR_225")
	var disaster := put_in_hand(m, "SEC_078")
	check(m.do_action({"a": "play", "uid": disaster.uid}) and m.pending.is_empty()
		and friendly_space.zone == "discard" and enemy_space.zone == "discard"
		and friendly_ground.in_play() and enemy_ground.in_play(),
		"Hyperspace Disaster defeats allied and enemy space units while leaving ground intact")

	m = funded_match()
	friendly_ground = add_unit(m, 0, "SOR_095")
	enemy_space = add_unit(m, 1, "SOR_225")
	var king := put_in_hand(m, "TS26_016")
	check(m.do_action({"a": "play", "uid": king.uid}) and m.pending.is_empty()
		and friendly_ground.kw("restore") == 1 and enemy_space.kw("restore") == 1
		and king.kw("restore") == 1, "King Katuunko gives Restore to itself and both sides across arenas")
	m._expire("phase")
	check(friendly_ground.kw("restore") == 0 and enemy_space.kw("restore") == 0 and king.kw("restore") == 0,
		"King Katuunko's granted Restore expires with the phase")

	m = funded_match()
	var summa := add_unit(m, 0, "ASH_083")
	friendly_space = add_unit(m, 0, "SOR_225")
	enemy_space = add_unit(m, 1, "SOR_225")
	enemy_ground = add_unit(m, 1, "SOR_095")
	var enemy_base: CardInst = m.players[1].base
	check(m.do_action({"a": "attack", "uid": summa.uid, "target": enemy_base.uid})
		and friendly_space.zone == "discard" and enemy_space.zone == "discard"
		and summa.in_play() and enemy_ground.in_play() and enemy_base.damage == summa.power(),
		"Summa-verminoth defeats every other space unit on attack and still hits the base")


func test_fetts_firespray() -> void:
	for scenario in ["enemy", "hand", "boba_leader", "deployed_leader", "jango_unit", "boba_pilot"]:
		var m := funded_match()
		match scenario:
			"enemy":
				add_unit(m, 1, "SHD_138")
			"hand":
				put_in_hand(m, "SOR_179")
			"boba_leader", "deployed_leader":
				var boba := m._new_inst("SHD_008", 0)
				boba.zone = "leader"
				m.players[0].leader = boba
				if scenario == "deployed_leader":
					boba.deployed = true
					m._put_in_play(boba, "ground")
			"jango_unit":
				add_unit(m, 0, "SHD_138")
			"boba_pilot":
				var ship := add_unit(m, 0, "SOR_225")
				m.attach_upgrade(m._new_inst("JTL_189", 0), ship)
		var firespray := put_in_hand(m, "SOR_184")
		check(m.do_action({"a": "play", "uid": firespray.uid}) and firespray.in_play()
			and firespray.exhausted == (scenario in ["enemy", "hand"]), "Fett's Firespray checks title and control (%s)" % scenario)
	var action_match := funded_match()
	var firespray := add_unit(action_match, 0, "SOR_184", false)
	var unique := add_unit(action_match, 1, "SHD_138")
	var target := add_unit(action_match, 1, "SOR_095")
	var ready: int = action_match.players[0].available()
	check(action_match.do_action({"a": "ability", "uid": firespray.uid, "idx": 0})
		and unique.uid not in action_match.pending.get("options", []) and action_match.submit_choice([target.uid])
		and target.exhausted and action_match.players[0].available() == ready - 2,
		"Fett's Firespray can pay two resources to exhaust a non-unique unit while already exhausted")


func test_occupation_officer() -> void:
	for count in [5, 6, 7]:
		var rules := RuleSet.premier()
		rules.aspect_penalties = false
		var m := blank_match(rules)
		while m.players[0].resources.size() < count:
			m.move_to_resources(0, m.players[0].deck[0], true)
		while m.players[1].resources.size() < 7:
			m.move_to_resources(1, m.players[1].deck[0])
		var ally := add_unit(m, 0, "SOR_095")
		var foe := add_unit(m, 1, "SOR_066")
		var officer := put_in_hand(m, "HMW_242")
		check(m.do_action({"a": "play", "uid": officer.uid}), "Occupation Officer can be played with %d total resources" % count)
		if count == 5:
			check(m.pending.is_empty() and foe.upgrades.is_empty(), "The opponent's seven resources do not meet Occupation Officer's threshold")
			continue
		var targets: Array = m.pending.get("options", [])
		check(targets.size() == 3 and officer.uid in targets and ally.uid in targets and foe.uid in targets
			and m.pending.get("min") == 0, "Occupation Officer can target any unit or pass with %d total resources" % count)
		if count == 6:
			check(m.submit_choice([foe.uid]) and foe.upgrades.size() == 1 and foe.upgrades[0].name() == "Weakness"
				and foe.power() == foe.printed_power() - 1 and m.pending.is_empty(), "Occupation Officer attaches one Weakness at exactly six resources")
		else:
			check(m.submit_choice([]) and m.pending.is_empty() and foe.upgrades.is_empty()
				and ally.upgrades.is_empty() and officer.upgrades.is_empty(), "Passing Occupation Officer adds no token and completes the action")


func test_boba_disintegrator() -> void:
	for scenario in ["ready", "new", "old_exhausted", "base", "boba_first", "vambrace_first"]:
		var m := funded_match()
		var boba := add_unit(m, 0, "SOR_179")
		var target: CardInst = m.players[1].base if scenario == "base" else add_unit(m, 1, "SOR_046")
		if target.in_play():
			target.mods.append({"h": 2})
		if scenario != "new":
			m.end_round()
		m.active = 0
		if scenario in ["new", "old_exhausted"]:
			m.exhaust(target)
		if scenario in ["boba_first", "vambrace_first"]:
			m.attach_upgrade(m._new_inst("SHD_074", 0), boba)
		check(m.do_action({"a": "attack", "uid": boba.uid, "target": target.uid}), "Boba Fett attacks (%s)" % scenario)
		if scenario in ["boba_first", "vambrace_first"]:
			var labels: Array = m.pending.get("labels", [])
			var exhaust_option := labels.find_custom(func(label): return "Exhaust the defender" in label)
			check(exhaust_option >= 0 and m.submit_choice([exhaust_option if scenario == "vambrace_first" else 1 - exhaust_option]),
				"Boba Fett and the Vambrace can resolve in either order")
		var bonus := 3 if scenario in ["old_exhausted", "vambrace_first"] else 0
		check(target.damage == boba.power() + bonus and m.pending.is_empty(), "Boba Fett's conditional attack damage (%s)" % scenario)


func test_scaled_printed_effects() -> void:
	var m := funded_match()
	add_unit(m, 0, "SOR_095")
	add_unit(m, 0, "SOR_244")
	add_unit(m, 0, "SOR_225")
	var target := add_unit(m, 1, "SOR_088")
	var ackbar := put_in_hand(m, "SOR_097")
	check(m.do_action({"a": "play", "uid": ackbar.uid}) and m.submit_choice([target.uid]) and target.damage == 3,
		"Admiral Ackbar counts himself and the other units in the selected target's arena")

	var valance_match := funded_match()
	var valance := add_unit(valance_match, 0, "LAW_051")
	var ground := add_unit(valance_match, 1, "SOR_088")
	var extra_draw := valance_match._new_inst("SOR_095", 0)
	extra_draw.zone = "deck"
	valance_match.players[0].deck.append(extra_draw)
	valance_match.draw(0, 2)
	check(valance_match.do_action({"a": "attack", "uid": valance.uid, "target": valance_match.players[1].base.uid})
		and valance_match.submit_choice([ground.uid]) and ground.damage == 3,
		"Beilert Valance includes the draw from his On Attack together with earlier draws this phase")

	var purrgil_match := funded_match()
	var damaged := add_unit(purrgil_match, 0, "SOR_088")
	damaged.damage = damaged.max_hp() - 6
	add_unit(purrgil_match, 0, "HMW_067")
	var purrgil := put_in_hand(purrgil_match, "LOF_121")
	var original: int = purrgil_match.players[0].hand.size()
	check(purrgil_match.do_action({"a": "play", "uid": purrgil.uid}) and purrgil_match.players[0].hand.size() == original + 1,
		"Purrgil King draws for each friendly unit with seven remaining HP, excluding one with six")

	var sion_match := funded_match()
	var sion := put_in_hand(sion_match, "SEC_035")
	for _i in 2:
		sion_match.defeat(add_unit(sion_match, 1, "SOR_095"))
	sion_match.pump()
	check(sion_match.do_action({"a": "play", "uid": sion.uid}) and sion.power() == 7,
		"Darth Sion gains two Experience for the two enemy defeats this phase")
	sion_match.defeat(sion)
	sion_match.pump()
	check(sion.zone == "hand" and sion.power() == 5, "Darth Sion returns to hand using the power he had before losing upgrades")
	var untrained := add_unit(sion_match, 0, "SEC_035")
	sion_match.defeat(untrained)
	sion_match.pump()
	check(untrained.zone == "discard", "Darth Sion stays defeated below his power threshold")

	var raddus_match := funded_match()
	var raddus := add_unit(raddus_match, 0, "JTL_104")
	check(not raddus.has_kw("sentinel"), "Raddus does not count himself toward Sentinel")
	add_unit(raddus_match, 0, "JTL_102")
	check(raddus.has_kw("sentinel"), "Raddus gains Sentinel with another Resistance card")
	var enemy := add_unit(raddus_match, 1, "SOR_088")
	raddus_match.attach_token(raddus, "experience")
	raddus_match.defeat(raddus)
	raddus_match.pump()
	check(raddus_match.submit_choice([enemy.uid]) and enemy.zone == "discard",
		"Raddus deals nine When Defeated damage from his power with the upgrade")

	var wookiees := funded_match()
	add_unit(wookiees, 0, "SOR_196")
	add_unit(wookiees, 0, "HMW_046")
	var king := put_in_hand(wookiees, "HMW_123")
	var resources: int = wookiees.players[0].resources.size()
	var ready: int = wookiees.players[0].available()
	check(wookiees.do_action({"a": "play", "uid": king.uid}) and wookiees.players[0].resources.size() == resources + 2
		and wookiees.players[0].available() == ready - king.cost() + 2,
		"King Grakchawwaa resources and readies two cards for two other Wookiees")

	var pykes := funded_match()
	var ally := add_unit(pykes, 0, "SOR_095")
	var victim := add_unit(pykes, 1, "SOR_088")
	pykes.attach_token(ally, "experience")
	var backed := put_in_hand(pykes, "TS26_058")
	check(pykes.do_action({"a": "play", "uid": backed.uid}) and pykes.submit_choice([ally.uid])
		and pykes.submit_choice([victim.uid]) and victim.damage == 2,
		"Backed by the Pykes gives Experience before counting the tokens for its damage")


func test_ambush_combat_auras() -> void:
	var m := funded_match()
	add_unit(m, 0, "SHD_219")
	var purrgil := put_in_hand(m, "ASH_207")
	var defender := add_unit(m, 1, "LOF_121")
	check(m.do_action({"a": "play", "uid": purrgil.uid}) and m.submit_choice([defender.uid])
		and defender.damage == 5 and purrgil.damage == 1,
		"Heroic Purrgil gains two power and Enfys Nest weakens the defender during Ambush")
	m.exhaust(purrgil, false)
	m.begin_attack(purrgil, defender)
	m.pump()
	check(defender.damage == 8 and purrgil.damage == 5, "Both Ambush modifiers are absent from a regular attack")


func test_optional_trigger_limit() -> void:
	var m := funded_match()
	var gar := add_unit(m, 0, "ASH_047")
	var first := put_in_hand(m, "SOR_057")
	var second := put_in_hand(m, "SOR_057")
	var third := put_in_hand(m, "SOR_057")
	check(m.do_action({"a": "play", "uid": first.uid}) and m.submit_choice([gar.uid]) and m.pending.get("kind") == "yesno"
		and m.submit_choice([0]) and m.players[0].units.size() == 1,
		"Declining Gar Saxon's Mandalorian token leaves his once-per-round trigger available")
	m.active = 0
	check(m.do_action({"a": "play", "uid": second.uid}) and m.submit_choice([gar.uid]) and m.submit_choice([1])
		and m.players[0].units.size() == 2 and m.players[0].units.back().is_token,
		"Gar Saxon still creates a token after declining earlier in the round")
	m.active = 0
	check(m.do_action({"a": "play", "uid": third.uid}) and m.submit_choice([gar.uid]) and m.pending.is_empty()
		and m.players[0].units.size() == 2, "Gar Saxon's trigger is spent once he creates the token")


func test_hands_and_force_events() -> void:
	for use_force in [false, true]:
		var m := funded_match()
		var event := put_in_hand(m, "LOF_175")
		m.players[0].force_token = true
		check(m.do_action({"a": "play", "uid": event.uid}) and m.submit_choice([int(use_force)]),
			"Do or Do Not lets the player decline or spend their Force token")
		check(m.cards_drawn_this_phase[0] == 1 + int(use_force) and m.players[0].force_token != use_force,
			"Do or Do Not draws one when declined and two when the token is spent")

	var m := funded_match()
	var exhausted := add_unit(m, 0, "SOR_095", false)
	var ready := add_unit(m, 0, "SOR_095")
	var calm := put_in_hand(m, "LOF_054")
	check(m.do_action({"a": "play", "uid": calm.uid}) and m.submit_choice([ready.uid])
		and ready.exhausted and ready.shield_count() == 1 and ready.power() == 5,
		"Calm in the Storm exhausts a friendly unit and grants a Shield and two Experience")
	var second := put_in_hand(m, "LOF_054")
	m.active = 0
	check(m.do_action({"a": "play", "uid": second.uid}) and m.submit_choice([exhausted.uid]) and exhausted.upgrades.is_empty(),
		"Calm in the Storm gives nothing if the target was already exhausted")

	var saber_match := funded_match()
	var saber := put_in_hand(saber_match, "SOR_053")
	var throwing := put_in_hand(saber_match, "LOF_176")
	check(saber_match.do_action({"a": "play", "uid": throwing.uid}) and saber_match.pending.get("options", []) == [saber.uid],
		"Lightsaber Throw only offers Lightsaber cards to discard")
	check(saber_match.submit_choice([saber.uid]) and saber.zone == "discard" and saber_match.cards_drawn_this_phase[0] == 1,
		"Lightsaber Throw still draws if no ground unit can be damaged")

	var discarding := funded_match()
	var smoke := put_in_hand(discarding, "SOR_174")
	check(discarding.do_action({"a": "play", "uid": smoke.uid}) and discarding.pending.get("player") == 0,
		"Smoke and Cinders prompts the active player first")
	check(discarding.submit_choice(discarding.pending["options"].slice(0, discarding.pending["min"])) and discarding.pending.get("player") == 1,
		"Smoke and Cinders gives the second player their own discard choice")
	check(discarding.submit_choice(discarding.pending["options"].slice(0, discarding.pending["min"]))
		and discarding.players[0].hand.size() == 2 and discarding.players[1].hand.size() == 2,
		"Smoke and Cinders leaves both players with two cards")

	var recovery := funded_match()
	var defeated := add_unit(recovery, 0, "SOR_095")
	var kept := add_unit(recovery, 0, "SOR_225")
	var discarded := put_in_hand(recovery, "SOR_095")
	recovery.players[0].hand.erase(discarded)
	discarded.zone = "discard"
	recovery.players[0].discard.append(discarded)
	recovery.defeat(defeated)
	recovery.defeat(kept)
	var legion := put_in_hand(recovery, "SOR_091")
	check(recovery.do_action({"a": "play", "uid": legion.uid}) and defeated.zone == "hand" and kept.zone == "hand"
		and discarded.zone == "discard", "The Emperor's Legion only recovers units defeated this phase")

	var whispers_match := funded_match()
	var top := put_in_hand(whispers_match, "SOR_095")
	var bottom := put_in_hand(whispers_match, "SOR_225")
	var whispers := put_in_hand(whispers_match, "SEC_232")
	check(whispers_match.do_action({"a": "play", "uid": whispers.uid}) and whispers_match.submit_choice([top.uid])
		and not top.uid in whispers_match.pending.get("options", []) and whispers_match.submit_choice([bottom.uid])
		and whispers_match.players[0].deck.front() == top and whispers_match.players[0].deck.back() == bottom,
		"Kreia's Whispers places distinct cards on opposite ends of the deck")

	var black_sun := funded_match()
	var first := add_unit(black_sun, 1, "SOR_095")
	first.damage = 2
	var target := add_unit(black_sun, 1, "SOR_088")
	target.damage = 1
	var backed := put_in_hand(black_sun, "TS26_070")
	check(black_sun.do_action({"a": "play", "uid": backed.uid}) and black_sun.submit_choice([first.uid])
		and not first.uid in black_sun.pending.get("options", []) and black_sun.submit_choice([target.uid])
		and target.damage == 2 and first.zone == "discard",
		"Backed by Black Sun excludes the unit defeated by its first damage from its second effect")


func test_next_regroup_effects() -> void:
	var m := funded_match()
	var friendly := add_unit(m, 0, "SOR_095", false)
	var showdown := put_in_hand(m, "SHD_208")
	check(m.do_action({"a": "play", "uid": showdown.uid}) and not friendly.exhausted and m.winner < 0,
		"Final Showdown readies friendly units without ending the current action phase")
	m._end_action_phase()
	m.pump()
	check(m.winner == 1, "Final Showdown causes loss at the start of regroup")

	var seismic := funded_match()
	var own := add_unit(seismic, 0, "SOR_095")
	var enemy_ground := add_unit(seismic, 1, "SOR_095")
	var enemy_ship := add_unit(seismic, 1, "SOR_066")
	var bomb := put_in_hand(seismic, "HMW_054")
	check(seismic.do_action({"a": "play", "uid": bomb.uid}) and seismic.submit_choice([0]) and enemy_ground.damage == 0,
		"Seismic Detonation records the selected arena for regroup")
	seismic._end_action_phase()
	seismic.pump()
	check(enemy_ground.zone == "discard" and enemy_ship.damage == 0 and own.damage == 0 and seismic.next_regroup_effects.is_empty(),
		"Seismic Detonation hits the enemies in the chosen arena once")

	for contested in [false, true]:
		var confidence := funded_match()
		add_unit(confidence, 0, "SOR_225")
		var winning := put_in_hand(confidence, "SEC_145")
		check(confidence.do_action({"a": "play", "uid": winning.uid}) and confidence.submit_choice([1]) and confidence.winner < 0,
			"Confidence in Victory records the space arena without granting an immediate victory")
		if contested:
			add_unit(confidence, 1, "SOR_225")
		confidence._end_action_phase()
		confidence.pump()
		check(confidence.winner == (-1 if contested else 0), "Confidence in Victory rechecks arena control at regroup")
	var late := funded_match()
	var event := put_in_hand(late, "SEC_145")
	check(not Effects.has_hand_play(late, 0, {"kind": "event", "free": true}),
		"Confidence in Victory cannot be played by another card even on the opening action")
	check(late.do_action({"a": "pass"}), "Passing consumes the opening action")
	late.active = 0
	check(not late.legal_actions(0).any(func(a): return a.get("uid", 0) == event.uid),
		"Confidence in Victory is unavailable after the opening action")

	var delayed_discard := funded_match()
	var zorii := add_unit(delayed_discard, 0, "SHD_203")
	check(delayed_discard.do_action({"a": "attack", "uid": zorii.uid, "target": delayed_discard.players[1].base.uid})
		and delayed_discard.cards_drawn_this_phase[0] == 1 and delayed_discard.pending.is_empty(),
		"Zorii Bliss draws immediately on attack")
	delayed_discard.defeat(zorii)
	delayed_discard._end_action_phase()
	delayed_discard.pump()
	check(delayed_discard.pending.get("kind") == "hand" and delayed_discard.pending.get("player") == 0
		and delayed_discard.submit_choice([delayed_discard.pending["options"][0]]),
		"Zorii Bliss's regroup discard persists if Zorii is defeated")


func test_deck_search_filters() -> void:
	var m := funded_match()
	var deck := stage_search_deck(m, ["SOR_049", "SOR_095", "SOR_053", "SOR_225", "SOR_095", "SOR_095", "SOR_095", "SOR_095", "SOR_049"])
	var team := put_in_hand(m, "LAW_166")
	check(m.do_action({"a": "play", "uid": team.uid}) and m.pending.get("options", []) == [deck[0].uid],
		"Putting a Team Together offers only eligible units among the first eight cards")
	check(m.submit_choice([deck[0].uid]) and deck[0].zone == "hand" and m.players[0].deck.front() == deck[8],
		"Putting a Team Together draws the chosen card and puts the rest below the unsearched cards")

	var commission_match := funded_match()
	var supply := stage_search_deck(commission_match, ["SOR_053", "SOR_095", "SOR_250"])
	var commission := put_in_hand(commission_match, "SHD_127")
	check(commission_match.do_action({"a": "play", "uid": commission.uid})
		and commission_match.pending.get("options", []) == [supply[0].uid, supply[2].uid],
		"Commission offers Item and Transport cards of different types while excluding unrelated units")
	check(commission_match.submit_choice([supply[2].uid]) and supply[2].zone == "hand", "Commission draws the selected Transport")

	var mandalorians := funded_match()
	var found := stage_search_deck(mandalorians, ["ASH_047", "SOR_053", "SOR_095"])
	var event := put_in_hand(mandalorians, "SHD_253")
	check(mandalorians.do_action({"a": "play", "uid": event.uid})
		and mandalorians.pending.get("options", []) == [found[0].uid, found[1].uid],
		"This Is The Way offers a Mandalorian unit and a non-Mandalorian upgrade")
	check(mandalorians.submit_choice([found[0].uid, found[1].uid]) and found[0].zone == "hand" and found[1].zone == "hand"
		and mandalorians.cards_drawn_this_phase[0] == 2, "This Is The Way accepts both eligible types in one search")

	var matching := funded_match()
	var matching_deck := stage_search_deck(matching, ["SOR_053", "SOR_225", "SOR_095"])
	var droid := put_in_hand(matching, "LAW_145")
	check(matching.do_action({"a": "play", "uid": droid.uid}) and matching.pending.get("options", []) == [matching_deck[2].uid],
		"R2-D2 can count his own aspects and offers only units sharing a friendly aspect")
	check(matching.submit_choice([matching_deck[2].uid]) and matching_deck[2].zone == "hand", "R2-D2 draws the matching unit")


func test_play_units_from_deck() -> void:
	var m := funded_match()
	var deck := stage_search_deck(m, ["SOR_049", "SOR_095", "SOR_128", "SOR_225"])
	var u_wing := put_in_hand(m, "SOR_104")
	var ready: int = m.players[0].available()
	check(m.do_action({"a": "play", "uid": u_wing.uid}) and m.pending.get("effect", {}).get("combined_cost") == 7,
		"U-Wing Reinforcement opens a search constrained by the combined printed cost")
	check(not m.submit_choice([deck[0].uid, deck[1].uid]) and m.pending.get("kind") == "search",
		"U-Wing Reinforcement rejects eight combined cost without closing the search")
	check(m.submit_choice([deck[1].uid, deck[2].uid, deck[3].uid])
		and m.players[0].units == deck.slice(1) and deck[0].zone == "deck"
		and m.players[0].available() == ready - u_wing.cost() and m.cards_drawn_this_phase[0] == 0,
		"U-Wing Reinforcement plays the three chosen units in order for free and leaves the other card in the deck")

	var vader_match := funded_match()
	var enemies := stage_search_deck(vader_match, ["SOR_225", "SOR_128", "SOR_231", "SOR_095"])
	var vader := put_in_hand(vader_match, "SOR_087")
	check(vader_match.do_action({"a": "play", "uid": vader.uid})
		and vader_match.pending.get("op") == "_ordered_triggers" and vader_match.submit_choice([0])
		and vader_match.pending.get("options", []) == [enemies[0].uid, enemies[1].uid],
		"Darth Vader's Spark of Rebellion search filters by Villainy and printed cost")
	check(not AiBot.choose(vader_match).is_empty() and enemies[0].in_play() and enemies[1].in_play() and vader_match.pending.is_empty(),
		"The bot picks a legal group for Darth Vader and resolves the search")

	var beq_match := funded_match()
	var candidates := stage_search_deck(beq_match, ["SOR_244", "SOR_172"])
	var beq := put_in_hand(beq_match, "LOF_100")
	var before: int = beq_match.players[0].available()
	check(beq_match.do_action({"a": "play", "uid": beq.uid}) and beq_match.pending.get("options", []) == [candidates[0].uid]
		and beq_match.submit_choice([candidates[0].uid]) and candidates[0].in_play()
		and beq_match.players[0].available() == before - beq.cost() - candidates[0].cost() + 3,
		"Kelleran Beq plays the selected unit from the deck and pays its discounted cost")

	var sion_match := funded_match()
	var ships := stage_search_deck(sion_match, ["SOR_049", "SOR_066"])
	var eye := add_unit(sion_match, 0, "ASH_245")
	check(sion_match.do_action({"a": "ability", "uid": eye.uid, "idx": 0}) and sion_match.pending.get("options", []) == [ships[1].uid]
		and sion_match.submit_choice([ships[1].uid]) and eye.exhausted and ships[1].in_play() and not ships[1].exhausted,
		"Eye of Sion filters against its live power and the selected unit enters ready")

	var homeworlds := funded_match()
	var units := stage_search_deck(homeworlds, ["SOR_231", "JTL_063", "SOR_244"])
	var leader := put_in_hand(homeworlds, "HMW_043")
	check(homeworlds.do_action({"a": "play", "uid": leader.uid}) and homeworlds.pending.get("options", []) == [units[0].uid, units[1].uid]
		and homeworlds.submit_choice([units[1].uid, units[0].uid]) and homeworlds.submit_choice([units[1].uid])
		and units[0].zone == "discard" and units[1].damage == 2 and units[1].upgrades.size() == 2,
		"Homeworlds Vader plays two eligible units, resolves a When Played target, then damages both selections")

	var kalikori_match := funded_match()
	var keepers := stage_search_deck(kalikori_match, ["TWI_108", "SOR_095"])
	var host := add_unit(kalikori_match, 0, "SOR_177")
	var heirloom := put_in_hand(kalikori_match, "HMW_265")
	check(kalikori_match.do_action({"a": "play", "uid": heirloom.uid}) and kalikori_match.submit_choice([host.uid])
		and kalikori_match.pending.get("options", []) == [keepers[0].uid] and kalikori_match.submit_choice([keepers[0].uid])
		and keepers[0].in_play(), "Twi'lek Kalikori reacts to its host and searches for the matching trait")


func test_play_from_discard() -> void:
	var m := funded_match()
	var defeated := add_unit(m, 0, "SOR_095")
	m.defeat(defeated)
	var discarded := stage_discard(m, "SOR_128")
	var event := put_in_hand(m, "TWI_189")
	check(m.do_action({"a": "play", "uid": event.uid}) and m.pending.get("options", []) == [defeated.uid]
		and m.submit_choice([defeated.uid]) and defeated.in_play() and not defeated.exhausted
		and not defeated in m.players[0].discard and discarded.zone == "discard",
		"Unnatural Life plays only a unit defeated this phase and it enters ready")
	m._end_action_phase()
	m.pump()
	check(defeated.zone == "discard", "Unnatural Life defeats that unit at the beginning of regroup")

	var sneaking := funded_match()
	var returned := put_in_hand(sneaking, "SOR_095")
	var sneak := put_in_hand(sneaking, "SOR_219")
	check(sneaking.do_action({"a": "play", "uid": sneak.uid}) and sneaking.submit_choice([returned.uid])
		and returned.in_play() and not returned.exhausted, "Sneak Attack plays the unit ready")
	sneaking.return_to_hand(returned)
	sneaking.active = 0
	check(sneaking.do_action({"a": "play", "uid": returned.uid}), "The returned unit can be played again")
	sneaking._end_action_phase()
	sneaking.pump()
	check(returned.in_play(), "Sneak Attack's earlier regroup defeat leaves the replayed instance in play")

	for example in [["SOR_087", 0], ["SOR_088", 2]]:
		var palpatine := funded_match()
		var target := stage_discard(palpatine, example[0])
		var resurrection := put_in_hand(palpatine, "SHD_094")
		var affordable: int = palpatine.players[0].available()
		check(palpatine.do_action({"a": "play", "uid": resurrection.uid}) and palpatine.submit_choice([target.uid])
			and target.in_play() and palpatine.players[0].available() == affordable - resurrection.cost() - int(example[1]),
			"Palpatine's Return applies the correct discount for each unit's Force trait")

	var materials := funded_match()
	var saber := stage_discard(materials, "SOR_053")
	var guard := add_unit(materials, 0, "SOR_049")
	var repair := put_in_hand(materials, "LAW_245")
	check(materials.do_action({"a": "play", "uid": repair.uid}) and materials.submit_choice([saber.uid])
		and materials.submit_choice([guard.uid]) and saber.attached_to == guard,
		"Salvaged Materials plays a discounted Item from discard and attaches it normally")
	materials._end_action_phase()
	materials.pump()
	check(saber.zone == "discard" and saber.attached_to == null and guard.upgrades.is_empty(),
		"Salvaged Materials removes the temporary attachment at regroup")

	var fixing := funded_match()
	var eligible := stage_discard(fixing, "SOR_095")
	eligible.controller = 1  # The opponent controlled this unit before it went to its owner's discard pile.
	stage_discard(fixing, "SOR_225")
	stage_discard(fixing, "SOR_053")
	var mechanize := put_in_hand(fixing, "TS26_057")
	check(fixing.do_action({"a": "play", "uid": mechanize.uid}) and fixing.pending.get("options", []) == [eligible.uid]
		and fixing.submit_choice([eligible.uid]) and eligible in fixing.players[0].units and eligible.upgrades.size() == 1,
		"Mechanize replays a non-Vehicle unit and gives it Experience")


func test_delayed_search_play() -> void:
	var raid := funded_match()
	var finds := stage_search_deck(raid, ["SOR_095", "SOR_225"])
	var event := put_in_hand(raid, "SHD_194")
	check(raid.do_action({"a": "play", "uid": event.uid}) and raid.pending.get("options", []) == [finds[1].uid]
		and raid.submit_choice([finds[1].uid]) and finds[1].in_play() and not finds[1].exhausted,
		"Triple Dark Raid filters Vehicles and plays the selected unit ready")
	raid.events.clear()
	raid._end_action_phase()
	raid.pump()
	var bounce := raid.events.find_custom(func(e): return e.get("t") == "bounce" and e.get("uid") == finds[1].uid)
	var regroup := raid.events.find_custom(func(e): return e.get("t") == "phase" and e.get("phase") == "regroup")
	check(bounce >= 0 and regroup > bounce and finds[1].zone == "hand", "Triple Dark Raid returns the unit before regroup")

	var bike_match := funded_match()
	var wheel := stage_search_deck(bike_match, ["TWI_236"])[0] as CardInst
	var host := add_unit(bike_match, 0, "SOR_095")
	var raid_for_upgrade := put_in_hand(bike_match, "SHD_194")
	check(bike_match.do_action({"a": "play", "uid": raid_for_upgrade.uid}) and bike_match.submit_choice([wheel.uid])
		and bike_match.submit_choice([host.uid]) and wheel.attached_to == host, "Triple Dark Raid can play a Vehicle upgrade")
	bike_match._end_action_phase()
	bike_match.pump()
	check(wheel.zone == "hand" and host.upgrades.is_empty(), "Triple Dark Raid detaches and returns the Vehicle upgrade")

	var maz_match := funded_match()
	var maz := add_unit(maz_match, 0, "LAW_074")
	var choice := stage_search_deck(maz_match, ["SOR_177", "SOR_095"])[0] as CardInst
	check(maz_match.do_action({"a": "attack", "uid": maz.uid, "target": maz_match.players[1].base.uid})
		and maz_match.submit_choice([choice.uid]) and choice.in_play() and not choice.exhausted,
		"Maz Kanata searches on a survived attack and the Underworld unit enters ready")
	maz_match.attach_token(choice, "experience")
	maz_match.rules.regroup_draw = 0
	maz_match._end_action_phase()
	maz_match.pump()
	check(choice.zone == "deck" and maz_match.players[0].deck.back() == choice and choice.upgrades.is_empty(),
		"Maz Kanata puts the chosen entry on the bottom at regroup and removes its upgrades")

	var recycled := funded_match()
	var flight := put_in_hand(recycled, "SHD_194")
	var ship := stage_search_deck(recycled, ["SOR_225"])[0] as CardInst
	check(recycled.do_action({"a": "play", "uid": flight.uid}) and recycled.submit_choice([ship.uid]), "Triple Dark Raid stages a return")
	recycled.return_to_hand(ship)
	recycled.active = 0
	check(recycled.do_action({"a": "play", "uid": ship.uid}), "The same physical card can be played again")
	recycled._end_action_phase()
	recycled.pump()
	check(ship.in_play(), "The delayed effect leaves the new entry in play")


func test_discard_selection_followups() -> void:
	var m := funded_match()
	var reference := stage_discard(m, "SOR_095")
	var cards := stage_search_deck(m, ["SOR_128", "SOR_095", "SOR_225"])
	var event := put_in_hand(m, "LOF_219")
	check(m.do_action({"a": "play", "uid": event.uid}) and event.uid not in m.pending["options"]
		and m.submit_choice([reference.uid]) and m.pending.get("options", []) == [cards[0].uid, cards[1].uid],
		"Psychometry uses a different discard card and searches for any shared trait")
	check(m.submit_choice([cards[1].uid]) and cards[1].zone == "hand" and reference.zone == "discard",
		"Psychometry leaves the reference card in discard")

	var luminous := funded_match()
	var recovered_first := stage_discard(luminous, "SOR_049")
	var recovered_second := stage_discard(luminous, "SOR_087")
	var friendly := add_unit(luminous, 0, "SOR_095")
	var opposing := add_unit(luminous, 1, "SOR_128")
	var buff := put_in_hand(luminous, "LOF_104")
	check(luminous.do_action({"a": "play", "uid": buff.uid}) and luminous.submit_choice([recovered_first.uid, recovered_second.uid])
		and luminous.pending.get("min") == 2 and not luminous.submit_choice([friendly.uid]),
		"Luminous Beings requires a distinct target for each returned card")
	check(luminous.submit_choice([friendly.uid, opposing.uid]) and friendly.power() == 7 and opposing.power() == 7,
		"Luminous Beings buffs two chosen units")
	check(luminous.players[0].deck.slice(-2).has(recovered_first) and luminous.players[0].deck.slice(-2).has(recovered_second),
		"Luminous Beings puts both Force units at the bottom of the deck")

	var path := funded_match()
	var top := stage_search_deck(path, ["SOR_049", "SOR_095", "SOR_087"])
	var following := put_in_hand(path, "LOF_103")
	check(path.do_action({"a": "play", "uid": following.uid}) and path.submit_choice([top[2].uid, top[0].uid])
		and path.players[0].deck == [top[2], top[0], top[1]] and path.cards_drawn_this_phase[0] == 0,
		"Following the Path preserves the chosen top-deck order without drawing")


func test_immediate_replays() -> void:
	var addition := funded_match()
	var stolen := addition._new_inst("SOR_057", 1)
	stolen.zone = "discard"
	addition.players[1].discard.append(stolen)
	var host := add_unit(addition, 0, "SOR_095")
	addition.defeat(add_unit(addition, 1, "SOR_128"))
	var event := put_in_hand(addition, "TWI_040")
	check(addition.do_action({"a": "play", "uid": event.uid}) and addition.submit_choice([stolen.uid])
		and addition.submit_choice([host.uid]) and stolen.attached_to == host and stolen.controller == 0
		and stolen.owner == 1 and stolen not in addition.players[1].discard,
		"A Fine Addition plays an eligible upgrade from the opponent's discard under the acting player's control")

	var l3_match := funded_match()
	stage_search_deck(l3_match, ["SOR_095", "SOR_095", "SOR_095", "SOR_095"])
	add_unit(l3_match, 0, "HMW_215")
	var arms := put_in_hand(l3_match, "TS26_068")
	stage_discard(l3_match, "TS26_068")
	var before: int = l3_match.players[0].available()
	check(l3_match.do_action({"a": "play", "uid": arms.uid}) and l3_match.pending.get("options", []) == [arms.uid],
		"L3-37 offers the event just played even when another copy is in discard")
	check(l3_match.submit_choice([arms.uid]) and l3_match.pending.is_empty()
		and l3_match.cards_drawn_this_phase[0] == 4 and l3_match.players[0].available() == before - arms.cost(),
		"L3-37 repeats the event for free once without triggering itself a second time")

	var lama_match := funded_match()
	var lama := lama_match._new_inst("SEC_003", 0)
	lama.zone = "leader"
	lama_match.players[0].leader = lama
	var ground := add_unit(lama_match, 0, "SOR_095")
	var vehicle := add_unit(lama_match, 0, "SOR_225")
	var enemy := add_unit(lama_match, 1, "SOR_128")
	var protector := put_in_hand(lama_match, "SOR_057")
	check(lama_match.do_action({"a": "ability", "uid": lama.uid, "idx": 0}) and lama_match.submit_choice([protector.uid])
		and lama_match.pending.get("options", []) == [ground.uid] and not lama_match.submit_choice([vehicle.uid])
		and not lama_match.submit_choice([enemy.uid]), "Lama Su restricts attachment to a friendly non-Vehicle unit")
	check(lama_match.submit_choice([ground.uid]) and protector.attached_to == ground and ground.damage == 1,
		"Lama Su damages the actual recipient after attaching the upgrade")


func test_resources_and_action_start() -> void:
	var solo := funded_match()
	var han := solo._new_inst("SOR_017", 0)
	han.zone = "leader"
	solo.players[0].leader = han
	var investment := put_in_hand(solo, "SOR_095")
	var existing: CardInst = solo.players[0].resources[0]
	check(solo.do_action({"a": "ability", "uid": han.uid, "idx": 0}) and solo.submit_choice([investment.uid])
		and investment.zone == "resource" and not investment.exhausted and existing.zone == "resource",
		"Han Solo adds a ready resource and waits before charging his delayed cost")
	solo.start_action_phase()
	solo.pump()
	check(solo.pending.get("kind") == "resource" and solo.submit_choice([existing.uid]) and existing.zone == "discard"
		and investment.zone == "resource" and solo.next_action_effects.is_empty(),
		"Han Solo lets the player defeat any friendly resource at the next action phase")

	var plots := funded_match()
	var plotted := put_in_hand(plots, "SEC_036")
	plots.move_to_resources(0, plotted)
	var replacement := stage_search_deck(plots, ["SOR_128", "SOR_095"])[0] as CardInst
	var event := put_in_hand(plots, "SEC_245")
	var size_before: int = plots.players[0].resources.size()
	check(plots.do_action({"a": "play", "uid": event.uid}) and plots.pending.get("options", []) == [plotted.uid]
		and plots.submit_choice([plotted.uid]) and plotted.in_play(), "When Has Become Now selects only a resource with Plot")
	check(plots.players[0].resources.size() == size_before and replacement.zone == "resource" and replacement.exhausted
		and plots.players[0].deck.size() == 1, "A successful play replaces the resource exactly once")

	var no_plot := funded_match()
	var failed := put_in_hand(no_plot, "SEC_245")
	var without_plot: int = no_plot.players[0].resources.size()
	check(no_plot.do_action({"a": "play", "uid": failed.uid}) and no_plot.pending.is_empty()
		and no_plot.players[0].resources.size() == without_plot, "When Has Become Now adds no resource if no Plot card is played")

	var loss := funded_match()
	var lackeys := add_unit(loss, 0, "SHD_107")
	var spent: CardInst = loss.players[0].resources[0]
	loss.defeat(lackeys)
	loss.pump()
	check(loss.submit_choice([spent.uid]) and spent.zone == "discard" and lackeys.zone == "resource" and lackeys.exhausted,
		"Enterprising Lackeys can replace a chosen resource on defeat")


func test_combat_order_and_modifiers() -> void:
	for early in [false, true]:
		var m := funded_match()
		var stranger := add_unit(m, 0, "LAW_086")
		var marine := add_unit(m, 1, "SOR_095")
		check(m.do_action({"a": "attack", "uid": stranger.uid, "target": marine.uid}) and m.pending.get("kind") == "yesno"
			and m.submit_choice([int(early)]), "The Stranger offers the order of combat damage")
		check(stranger.damage == 3 and (marine.zone == "discard" if early else marine.damage == 1),
			"A surviving Stranger uses the updated Grit power only when he takes damage first")

	for first in [false, true]:
		var racer_match := funded_match()
		var racer := add_unit(racer_match, 0, "LAW_219")
		var rival := add_unit(racer_match, 1, "SOR_095")
		if not first:
			var earlier := add_unit(racer_match, 1, "SOR_128")
			racer_match.attacked_with[1].append(earlier.uid)
		check(racer_match.do_action({"a": "attack", "uid": racer.uid, "target": rival.uid}) and rival.zone == "discard"
			and racer.in_play() == first, "Anakin's Podracer strikes first only before any other unit has attacked")

	var swoop := funded_match()
	var ship := add_unit(swoop, 0, "SOR_237")
	var ground := add_unit(swoop, 1, "SOR_095")
	add_unit(swoop, 1, "SOR_066")
	var swoop_card := put_in_hand(swoop, "SHD_230")
	check(ground.uid not in swoop.attack_targets(ship) and swoop.do_action({"a": "play", "uid": swoop_card.uid})
		and swoop.submit_choice([ship.uid]) and ground.uid in swoop.pending.get("options", []),
		"Swoop Down grants Saboteur and cross-arena targeting before a defender is selected")
	check(swoop.submit_choice([ground.uid]) and ground.zone == "discard" and ship.damage == 1 and ship.power() == 2
		and not ship.has_kw("saboteur"), "Swoop Down applies both ground modifiers and removes them after combat")

	var speed := funded_match()
	var attacker := add_unit(speed, 0, "SOR_095")
	var defender := add_unit(speed, 1, "SOR_088")
	var protector := speed._new_inst("SOR_057", 1)
	speed.attach_upgrade(protector, defender)
	var elsewhere := add_unit(speed, 1, "SOR_128")
	var not_chosen := speed._new_inst("SOR_057", 1)
	speed.attach_upgrade(not_chosen, elsewhere)
	var event := put_in_hand(speed, "LOF_205")
	check(speed.do_action({"a": "play", "uid": event.uid}) and speed.submit_choice([attacker.uid]) and speed.submit_choice([defender.uid])
		and speed.pending.get("options", []) == [protector.uid], "Force Speed offers only non-unique upgrades attached to its defender")
	check(speed.submit_choice([protector.uid]) and protector.zone == "hand" and not_chosen.attached_to == elsewhere,
		"Force Speed returns the selected upgrade before combat and leaves other units' upgrades attached")

	var rukh_match := funded_match()
	var rukh := add_unit(rukh_match, 0, "SOR_085")
	var large := add_unit(rukh_match, 1, "SOR_049")
	check(rukh_match.do_action({"a": "attack", "uid": rukh.uid, "target": large.uid}) and large.zone == "discard"
		and rukh.in_play(), "Rukh defeats the damaged non-leader even when his combat damage was insufficient")


func test_phase_damage_history() -> void:
	var m := funded_match()
	var wounded := add_unit(m, 0, "SOR_095", false)
	var untouched := add_unit(m, 0, "SOR_225", false)
	m.deal_damage(wounded, 1, null)
	m.heal(wounded, 1)
	var leap := put_in_hand(m, "ASH_188")
	check(m.do_action({"a": "play", "uid": leap.uid}) and m.pending.get("options", []) == [wounded.uid]
		and m.submit_choice([wounded.uid]) and not wounded.exhausted and untouched.exhausted,
		"Galvanized Leap can ready a unit that was healed after taking damage this phase")

	var retaliation := funded_match()
	var invader := add_unit(retaliation, 1, "SOR_128")
	var bystander := add_unit(retaliation, 1, "SOR_088")
	retaliation.deal_damage(bystander, 1, null)
	retaliation.active = 1
	check(retaliation.do_action({"a": "attack", "uid": invader.uid, "target": retaliation.players[0].base.uid}),
		"The opponent records combat damage to the base through a normal attack")
	var answer := put_in_hand(retaliation, "SEC_077")
	check(retaliation.do_action({"a": "play", "uid": answer.uid}) and retaliation.pending.get("options", []) == [invader.uid]
		and retaliation.submit_choice([invader.uid]) and invader.zone == "discard",
		"Retaliation targets units that dealt base damage rather than units with damage on them")

	for damages_enemy in [false, true]:
		var tempest := funded_match()
		var ship := add_unit(tempest, 1, "SOR_066")
		var source := add_unit(tempest, 0, "SOR_095")
		tempest.deal_damage(tempest.players[int(damages_enemy)].base, 1, source)
		var assault := put_in_hand(tempest, "SEC_144")
		check(tempest.do_action({"a": "play", "uid": assault.uid}) and ship.damage == (2 if damages_enemy else 0),
			"Tempest Assault requires damage dealt to an enemy base this phase")

	var qui_match := funded_match()
	var leader := qui_match._new_inst("SOR_010", 1)
	leader.deployed = true
	qui_match.players[1].leader = leader
	qui_match._put_in_play(leader, "ground", false)
	qui_match.active = 1
	check(qui_match.do_action({"a": "attack", "uid": leader.uid, "target": qui_match.players[0].base.uid})
		and qui_match.submit_choice([]), "The deployed enemy leader attacks the base and skips his optional damage")
	var qui_gon := put_in_hand(qui_match, "HMW_078")
	check(qui_match.do_action({"a": "play", "uid": qui_gon.uid}) and qui_match.pending.get("options", []) == [leader.uid]
		and qui_match.submit_choice([leader.uid]) and leader.zone == "leader" and qui_gon.zone == "discard",
		"Qui-Gon can defeat the leader that attacked the base and is defeated in return")

	var control := funded_match()
	var raider := add_unit(control, 1, "SOR_128")
	control.begin_attack(raider, control.players[0].base)
	control.pump()
	control.take_control(raider, 0)
	control.exhaust(raider, false)
	control.begin_attack(raider, control.players[1].base)
	control.pump()
	check(Effects.matches(control, raider, {"attacked_your_base": true}, {"ctl": 0}) and
		Effects.matches(control, raider, {"attacked_your_base": true}, {"ctl": 1}),
		"Both bases remember an attacker that changed sides mid-phase")


func test_search_and_bounty_payoffs() -> void:
	for unique in [false, true]:
		var m := funded_match()
		var deck := stage_search_deck(m, ["SOR_095", "SOR_095", "SOR_095", "SOR_095", "SOR_095", "SOR_225"])
		var quarry := add_unit(m, 1, "SOR_087" if unique else "SOR_128")
		m.attach_upgrade(m._new_inst("SHD_123", 0), quarry)
		m.defeat(quarry)
		m.pump()
		check(m.pending.get("player") == 0 and m.submit_choice([0])
			and m.pending.get("options", []).size() == (6 if unique else 5),
			"Bounty Hunter's Quarry increases the search window for a unique defeated unit")
		check(m.submit_choice([deck[0].uid]) and deck[0].in_play(), "Bounty Hunter's Quarry plays the chosen unit for free")

	var posting := funded_match()
	var bounty := stage_search_deck(posting, ["SHD_123", "SOR_057"])[0] as CardInst
	var other := put_in_hand(posting, "SHD_222")
	var target := add_unit(posting, 1, "SOR_095")
	var poster := put_in_hand(posting, "SHD_228")
	check(posting.do_action({"a": "play", "uid": poster.uid}) and posting.pending.get("options", []) == [bounty.uid]
		and posting.submit_choice([bounty.uid]) and posting.pending.get("options", []) == [bounty.uid]
		and not posting.submit_choice([other.uid]), "Bounty Posting offers only the Bounty upgrade it just drew")
	check(posting.submit_choice([bounty.uid]) and posting.submit_choice([target.uid]) and bounty.attached_to == target,
		"Bounty Posting plays the selected upgrade through the normal attachment picker")

	var invisible := funded_match()
	var draw := stage_search_deck(invisible, ["SOR_059", "SOR_095"])[0] as CardInst
	var cruiser := put_in_hand(invisible, "JTL_089")
	check(invisible.do_action({"a": "play", "uid": cruiser.uid}) and invisible.submit_choice([1])
		and invisible.pending.get("options", []) == [draw.uid] and invisible.submit_choice([draw.uid]),
		"The Invisible Hand optionally searches for and draws a Droid")
	check(invisible.pending.get("options", []) == [draw.uid] and invisible.submit_choice([draw.uid]) and draw.in_play(),
		"The Invisible Hand plays the inexpensive Droid it drew")

	for defeated in [false, true]:
		var spark_match := funded_match()
		var source := add_unit(spark_match, 0, "SOR_095") if defeated else stage_discard(spark_match, "SOR_095")
		if defeated:
			spark_match.defeat(source)
		var spark := put_in_hand(spark_match, "SHD_105")
		check(spark_match.do_action({"a": "play", "uid": spark.uid}) and spark_match.submit_choice([source.uid])
			and source.zone == ("resource" if defeated else "discard"), "Spark of Hope resources only a unit defeated this phase")


func stage_discard(m: Match, id: String) -> CardInst:
	var card := m._new_inst(id, 0)
	card.zone = "discard"
	m.players[0].discard.append(card)
	return card


func stage_search_deck(m: Match, ids: Array) -> Array:
	var ps: PlayerState = m.players[0]
	for card in ps.deck:
		card.zone = "discard"
		ps.discard.append(card)
	ps.deck.clear()
	for id in ids:
		var card := m._new_inst(id, 0)
		card.zone = "deck"
		ps.deck.append(card)
	return ps.deck.duplicate()


func test_disclosure() -> void:
	var m := funded_match()
	for held in m.players[0].hand.duplicate():
		m._remove_from_zones(held)
		held.zone = "discard"
		m.players[0].discard.append(held)
	var protector := put_in_hand(m, "SOR_095")
	var ally := put_in_hand(m, "SOR_095")
	var foe := add_unit(m, 1, "SOR_225")
	var corruption := put_in_hand(m, "SEC_127")
	var guard := add_unit(m, 0, "SOR_095")
	check(m.do_action({"a": "play", "uid": corruption.uid}) and m.pending.get("kind") == "disclose", "Charged with Corruption prompts for disclosure")
	check(not m.submit_choice([protector.uid]), "One printed Command icon cannot pay for two")
	check(not m.submit_choice([protector.uid, protector.uid]), "A single card cannot be selected twice for one disclosure")
	check(m.submit_choice([protector.uid, ally.uid]) and m.pending.get("kind") == "disclosure_reveal", "Both disclosed cards are shown together to the opponent")
	check(protector.zone == "hand" and ally.zone == "hand", "Disclosure keeps revealed cards in hand")
	check(m.submit_choice([]) and guard.uid in m.pending.get("options", []), "Acknowledging the reveal resumes the capture choice")
	if guard.uid in m.pending.get("options", []):
		m.submit_choice([guard.uid])
		if foe.uid in m.pending.get("options", []):
			m.submit_choice([foe.uid])
	check(foe.zone == "captured", "Successful disclosure resolves capture")

	var decline := funded_match()
	var spy := put_in_hand(decline, "SEC_181")
	put_in_hand(decline, "SOR_095")
	put_in_hand(decline, "SOR_128")
	put_in_hand(decline, "SOR_172")
	check(decline.do_action({"a": "play", "uid": spy.uid}), "Unauthorized Investigation plays normally")
	check(decline.pending.get("kind") == "disclose" and decline.submit_choice([]), "Declining a valid disclosure is permitted")
	check(decline.players[0].units.size() == 1, "Declining disclosure keeps only the initial Spy")

	var reveal := funded_match()
	var padme := reveal._new_inst("SEC_016", 0)
	reveal.players[0].leader = padme
	padme.zone = "leader"
	var event := put_in_hand(reveal, "SOR_172")
	var agent := put_in_hand(reveal, "SOR_176")
	var target := add_unit(reveal, 1, "SOR_095")
	check(reveal.do_action({"a": "play", "uid": agent.uid}) and reveal.pending.get("options") == [event.uid],
		"ISB Agent can reveal only an event from hand")
	check(reveal.submit_choice([event.uid]) and reveal.submit_choice([]) and reveal.pending.get("kind") == "yesno",
		"Revealing the event triggers Padmé")
	check(reveal.submit_choice([1]) and reveal.submit_choice([target.uid]) and reveal.submit_choice([target.uid]),
		"Padmé and ISB Agent resolve their separate choices")
	check(padme.exhausted and target.damage == 2 and event.zone == "hand", "Both printed abilities deal damage, and the event stays in hand")


func test_next_unit_and_copy_limit() -> void:
	var m := funded_match()
	var neel := put_in_hand(m, "ASH_248")
	check(m.do_action({"a": "play", "uid": neel.uid}), "Neel's When Played queues a printed-power entry modifier")
	m.active = 0
	var marine := put_in_hand(m, "SOR_095")
	check(m.do_action({"a": "play", "uid": marine.uid}) and marine.exhausted, "Unqualified units do not consume Neel's modifier")
	m.active = 0
	var cheap := put_in_hand(m, "SOR_059")
	check(m.do_action({"a": "play", "uid": cheap.uid}) and not cheap.exhausted, "The next qualifying unit enters ready")
	m.active = 0
	cheap = put_in_hand(m, "SOR_059")
	check(m.do_action({"a": "play", "uid": cheap.uid}) and cheap.exhausted, "Only one qualifying unit enters ready")

	var deck: Array = []
	deck.resize(15)
	deck.fill("JTL_256")
	var rules := RuleSet.campaign()
	rules.deck_min = 0
	check(DeckBuilder.validate(lib, rules, "SOR_010", "HMW_028", deck).is_empty(), "Swarming Vulture Droid allows fifteen copies")
	deck.append("JTL_256")
	check(not DeckBuilder.validate(lib, rules, "SOR_010", "HMW_028", deck).is_empty(), "A sixteenth Swarming Vulture Droid exceeds the copy limit")
	var first := add_unit(m, 0, "JTL_256")
	var second := add_unit(m, 0, "JTL_256")
	add_unit(m, 1, "JTL_256")
	check(first.power() == 3 and second.power() == 3, "Vultures count friendly names and exclude themselves")
	m.defeat(second)
	check(first.power() == 2, "Vulture power updates when its ally leaves play")


func test_commanded_attacks() -> void:
	var m := funded_match()
	var ally := add_unit(m, 0, "LOF_073", false)
	ally.data = ally.data.duplicate()
	ally.data["traits"] = ["force"]
	var enemy := add_unit(m, 1, "SOR_128")
	enemy.data = {"hp": 12, "power": 0, "type": "unit"}
	var strike := put_in_hand(m, "LOF_124")
	var power := ally.power()
	check(m.do_action({"a": "play", "uid": strike.uid}) and ally.uid in m.pending.get("options", []),
		"Niman Strike offers an exhausted Force unit")
	check(m.submit_choice([ally.uid]) and m.pending.get("options") == [enemy.uid], "Niman Strike restricts the attack to units")
	check(m.submit_choice([enemy.uid]) and enemy.damage == power + 1, "Niman Strike applies the extra power to combat")
	check(ally.power() == power, "Niman Strike's buff expires after the attack")

	var trap := funded_match()
	var gunner := add_unit(trap, 0, "SOR_095")
	var blocker := add_unit(trap, 1, "SOR_028")
	blocker.data = {"hp": 7, "power": 0, "type": "unit"}
	trap.attach_token(blocker, "shield")
	var breaker := put_in_hand(trap, "TWI_224")
	check(trap.do_action({"a": "play", "uid": breaker.uid}) and trap.submit_choice([gunner.uid]) and trap.submit_choice([blocker.uid]),
		"Breaking In declares an attack using the normal choice flow")
	check(blocker.shield_count() == 0 and blocker.damage == 5 and not gunner.has_kw("saboteur"),
		"Breaking In grants both Saboteur and power for combat only")


func test_unit_departure() -> void:
	var m := funded_match()
	var boba := m._new_inst("SOR_015", 0)
	m.players[0].leader = boba
	boba.zone = "leader"
	var resource: CardInst = m.players[0].resources[0]
	resource.exhausted = true
	var bounced := add_unit(m, 1, "SOR_095")
	m.return_to_hand(bounced)
	m.pump()
	check(m.units_left_this_phase[1] == 1 and m.defeated_this_phase[1] == 0, "Bouncing leaves play without counting as defeat")
	check(m.pending.get("kind") == "yesno" and m.submit_choice([1]) and boba.exhausted and not resource.exhausted,
		"Boba Fett may exhaust to ready a resource when an enemy leaves play")

	var blue := put_in_hand(m, "JTL_096")
	m.active = 0
	check(m.do_action({"a": "play", "uid": blue.uid}) and m.pending.get("op") == "_ordered_triggers" and m.submit_choice([0])
		and m.pending.get("kind") == "yesno", "Blue Leader can resolve its optional arena move before Ambush")
	var entry := blue.entry_serial
	check(m.submit_choice([1]) and blue.zone == "ground" and blue.entry_serial == entry and blue.exhausted and blue.upgrades.size() == 2,
		"Blue Leader moves without reentering, and receives both Experience tokens")


func test_spotlight_rules() -> void:
	var m := funded_match()
	var attacker := add_unit(m, 0, "SOR_095", false)
	var target := add_unit(m, 1, "SOR_095")
	var event := m._new_inst("JTL_123", 0)
	m.push_ability(event, event.abilities_with("event")[0])
	m.pump()
	check(m.pending.get("options") == [attacker.uid], "Dogfight offers an exhausted friendly unit")
	m.submit_choice([attacker.uid])
	check(m.pending.get("options") == [target.uid], "Dogfight excludes enemy bases")
	m.submit_choice([target.uid])
	check(target.zone == "discard" and attacker.zone == "discard", "Dogfight resolves combat")

	m = funded_match()
	attacker = add_unit(m, 0, "SOR_095")
	target = add_unit(m, 1, "SOR_095")
	event = m._new_inst("SOR_217", 0)
	m.push_ability(event, event.abilities_with("event")[0])
	m.pump()
	m.submit_choice([attacker.uid])
	m.submit_choice([target.uid])
	check(target.zone == "discard" and attacker.in_play() and attacker.damage == 0, "Shoot First defeats a defender before retaliation")

	m = funded_match()
	var falcon := add_unit(m, 0, "JTL_249")
	var pilot := m._new_inst("JTL_245", 0)
	m.attach_upgrade(pilot, falcon)
	var second := m._new_inst("JTL_093", 0)
	check(falcon in Effects.upgrade_targets(m, 0, second, true), "The Spotlight Falcon accepts a second pilot")
	m.attach_upgrade(second, falcon)
	var third := m._new_inst("JTL_150", 0)
	check(falcon in Effects.upgrade_targets(m, 0, third, true), "R2-D2 gives the Falcon a third pilot slot")
	m.attach_upgrade(third, falcon)
	check(falcon not in Effects.upgrade_targets(m, 0, m._new_inst("JTL_148", 0), true), "The Falcon with R2-D2 caps at three pilots")


func test_attached_printed_rules() -> void:
	var m := funded_match()
	for data in [["LOF_101", "restore"], ["LOF_231", "raid"], ["LOF_170", "sentinel"]]:
		var host := add_unit(m, 0, data[0])
		var before := host.kw(data[1])
		var saber := put_in_hand(m, "LOF_261")
		m.active = 0
		check(m.do_action({"a": "play", "uid": saber.uid}) and m.submit_choice([host.uid]),
			"Constructed Lightsaber attaches to a Force unit")
		check(host.kw(data[1]) == before + (1 if data[1] == "sentinel" else 2),
			"Constructed Lightsaber grants the keyword for %s" % host.name())
		m.defeat(saber)
		check(host.kw(data[1]) == before, "Constructed Lightsaber's bonus ends when it leaves play")

	m = funded_match()
	var non_mandalorian := add_unit(m, 0, "SOR_095")
	var foundling := put_in_hand(m, "SHD_069")
	check(m.do_action({"a": "play", "uid": foundling.uid}) and m.submit_choice([non_mandalorian.uid])
		and non_mandalorian.has_trait("mandalorian"), "Foundling adds Mandalorian for live rules")
	m.active = 0
	var armor := put_in_hand(m, "SHD_073")
	check(m.do_action({"a": "play", "uid": armor.uid}) and m.submit_choice([non_mandalorian.uid])
		and non_mandalorian.shield_count() == 1, "Mandalorian Armor recognizes Foundling's granted trait")
	m.defeat(foundling)
	check(not non_mandalorian.has_trait("mandalorian") and non_mandalorian.shield_count() == 1,
		"The granted trait ends without removing the Shield already given")

	m = funded_match()
	var exhausted := add_unit(m, 1, "SOR_095", false)
	var shadow := put_in_hand(m, "LAW_077")
	check(m.do_action({"a": "play", "uid": shadow.uid}) and m.submit_choice([exhausted.uid]) and not exhausted.can_ready(),
		"Shadow of Stygeon Prime prevents readying the attached unit")
	m.exhaust(exhausted, false)
	Effects.exec(m, {"op": "_ready_all"}, {})
	check(exhausted.exhausted, "Shadow prevents both card-effect and regroup readying")
	Effects.exec(m, {"op": "_regroup_triggers"}, {})
	m.pump()
	check(m.players[1].base.damage == 2 and m.players[0].base.damage == 0, "Shadow damages the attached unit controller's base")
	m.defeat(shadow)
	m.exhaust(exhausted, false)
	check(not exhausted.exhausted, "Removing the upgrade restores normal readying")

	m = funded_match()
	var guarded := add_unit(m, 0, "LOF_101")
	var enemy := add_unit(m, 1, "LOF_170")
	m.attach_upgrade(m._new_inst("TWI_220", 0), guarded)
	for op in ["defeat", "bounce"]:
		m.push_frame([{"op": op, "t": {"s": "choose", "kind": "unit", "side": "enemy"}}], {"ctl": 1, "src": enemy.uid})
		m.pump()
		check(m.pending.is_empty() and guarded.in_play(), "Shadowed Intentions prevents enemy %s" % op)
	check(not m.capture(enemy, guarded), "Shadowed Intentions prevents enemy capture")
	m.deal_damage(guarded, 30, enemy, false, true)
	m.pump()
	check(guarded.zone == "discard", "Shadowed Intentions does not prevent combat damage or state-based defeat")

	m = funded_match()
	var cohort_host := add_unit(m, 0, "SOR_095")
	var cohort := put_in_hand(m, "TWI_169")
	check(m.do_action({"a": "play", "uid": cohort.uid}) and m.submit_choice([cohort_host.uid]) and cohort_host.kw("raid") == 2,
		"Clone Cohort grants Raid 2 when played")
	m.defeat(cohort_host)
	m.pump()
	check(m.players[0].units.any(func(unit): return unit.is_token and unit.name() == "Clone Trooper"),
		"Clone Cohort grants the host a defeat trigger that creates a Clone Trooper")

	m = funded_match()
	var mace := add_unit(m, 0, "HMW_128")
	var windu_saber := put_in_hand(m, "TWI_152")
	var hand_size: int = m.players[0].hand.size()
	check(m.do_action({"a": "play", "uid": windu_saber.uid}) and m.submit_choice([mace.uid])
		and m.players[0].hand.size() == hand_size + 1, "Mace Windu's Lightsaber draws two cards for any title-matching printing")


func test_reported_card_abilities() -> void:
	var m := funded_match()
	var razor := add_unit(m, 0, "ASH_172")
	var payment := put_in_hand(m, "SOR_095")
	var base: CardInst = m.players[1].base
	check(m.do_action({"a": "attack", "uid": razor.uid, "target": base.uid})
		and m.submit_choice([1]) and m.submit_choice([payment.uid]), "Razor Crest discards a selected card")
	check(base.damage == 5 and payment.zone == "discard" and razor.power() == 3,
		"Razor Crest hits for five after discard and loses the attack bonus afterwards")
	var other := funded_match()
	var ally := add_unit(other, 0, "SOR_095")
	var bd := put_in_hand(other, "LOF_191")
	check(other.do_action({"a": "play", "uid": bd.uid}) and other.submit_choice([ally.uid])
		and ally.power() == ally.printed_power() + 1 and ally.has_kw("saboteur"), "BD-1 buffs the chosen ally")
	other.return_to_hand(bd)
	check(ally.power() == ally.printed_power() and not ally.has_kw("saboteur"), "BD-1 bonus ends when it leaves")
	var force_match := funded_match()
	var qui_gon := force_match._new_inst("LOF_016", 0)
	qui_gon.zone = "leader"
	force_match.players[0].leader = qui_gon
	force_match.players[0].force_token = true
	var returned := add_unit(force_match, 0, "ASH_172")
	var cheap := put_in_hand(force_match, "SOR_095")
	var resources: int = force_match.players[0].available()
	check(force_match.do_action({"a": "ability", "uid": qui_gon.uid, "idx": 0})
		and force_match.submit_choice([returned.uid]) and returned.zone == "hand"
		and not force_match.players[0].force_token, "Qui-Gon spends the Force and returns the chosen unit")
	check(cheap.uid in force_match.pending.get("options", []) and returned.uid not in force_match.pending.get("options", [])
		and force_match.submit_choice([cheap.uid])
		and cheap.in_play() and force_match.players[0].available() == resources, "Qui-Gon plays a cheaper non-Villainy unit for free")


func test_tie_advanced() -> void:
	for target_id in ["SOR_128", "SOR_225"]:
		var m := funded_match()
		var ground := add_unit(m, 0, "SOR_128", false)
		var space := add_unit(m, 0, "SOR_225")
		var enemy := add_unit(m, 1, "SOR_225")
		var ally := add_unit(m, 0, "SOR_237")
		var token := m.create_unit_token(0, "tie_fighter")
		var tie := put_in_hand(m, "SOR_231")
		check(token != null and not token.has_trait("imperial"), "Generic TIE Fighter token has no Imperial trait")
		check(m.do_action({"a": "play", "uid": tie.uid}) and tie.in_play(), "TIE Advanced enters through normal card play")
		check(m.pending.get("options") == [ground.uid, space.uid] and m.pending.get("min") == 1,
			"TIE Advanced requires choosing another friendly Imperial in either arena")
		check(not m.submit_choice([tie.uid]) and not m.submit_choice([enemy.uid]) and not m.submit_choice([ally.uid])
			and token and not m.submit_choice([token.uid]), "TIE Advanced excludes itself, enemies and non-Imperial allies")
		var selected := ground if target_id == "SOR_128" else space
		var unselected := space if selected == ground else ground
		var power := selected.power()
		var hp := selected.max_hp()
		check(m.submit_choice([selected.uid]) and m.pending.is_empty() and m.active == 1, "TIE Advanced finishes the action after the target is chosen")
		check(selected.upgrades.size() == 2 and selected.upgrades.all(func(upgrade): return upgrade.name() == "Experience")
			and selected.power() == power + 2 and selected.max_hp() == hp + 2 and unselected.upgrades.is_empty(),
			"TIE Advanced gives the selected Imperial exactly two Experience tokens")

	var m := funded_match()
	m.create_unit_token(0, "tie_fighter")
	add_unit(m, 1, "SOR_225")
	var tie := put_in_hand(m, "SOR_231")
	check(m.do_action({"a": "play", "uid": tie.uid}) and tie.in_play() and tie.upgrades.is_empty()
		and m.pending.is_empty() and m.active == 1, "TIE Advanced enters and passes the turn with no eligible Imperial")
	check(m.log_lines.has("TIE Advanced: No other friendly Imperial unit in play."), "TIE Advanced explains the missing target")


func test_fortifications() -> void:
	var m := funded_match()
	var home: CardInst = m.players[0].base
	var shield := put_in_hand(m, "HMW_081")
	check(m.do_action({"a": "play", "uid": shield.uid}) and m.pending.get("options") == [home.uid]
		and m.submit_choice([home.uid]), "Fortify attaches through the normal play action")
	var before: int = m.players[0].hand.size()
	check(m.deal_damage(home, 4, null) == 4 and shield.zone == "upgrade", "Shield Generator ignores hits under five")
	check(m.deal_damage(home, 5, null, true) == 5 and shield.zone == "upgrade", "Unpreventable damage bypasses Shield Generator")
	check(m.deal_damage(home, 7, null) == 0 and home.damage == 9 and shield.zone == "discard"
		and m.players[0].hand.size() == before + 1, "Shield Generator prevents the full hit, defeats itself and draws")

	var ally := add_unit(m, 0, "SOR_095")
	var ship := add_unit(m, 0, "SOR_237")
	var enemy := add_unit(m, 1, "SOR_095")
	for id in ["HMW_112", "HMW_126", "HMW_271", "HMW_113", "HMW_070"]:
		m.attach_upgrade(m._new_inst(id, 0), home)
	check(ally.has_kw("overwhelm") and ally.kw("raid") == 1 and ship.power() == ship.printed_power() + 1
		and enemy.kw("raid") == 0, "Academy, Fortress and Landing Pad apply only to eligible allies")
	m.defeat(ally)
	m.pump()
	check(home.damage == 8, "War Memorial heals after a friendly unit is defeated")
	var hand_size: int = m.players[0].hand.size()
	m.push_frame([{"op": "_regroup_triggers"}], {"ctl": 0})
	m.pump()
	check(home.damage == 10 and m.players[0].hand.size() == hand_size + 1, "Dark Sanctum draws then damages its base")

	var lab := funded_match()
	var lab_base: CardInst = lab.players[0].base
	var target := add_unit(lab, 0, "SOR_095")
	target.damage = 2
	var bacta := lab._new_inst("HMW_037", 0)
	lab.attach_upgrade(bacta, lab_base)
	lab.pump()
	check(lab.submit_choice([target.uid]) and lab.submit_choice([1]) and target.damage == 1, "Bacta Tank can heal less than the maximum")
	var recover := add_unit(lab, 0, "SOR_095")
	lab.defeat(recover)
	check(lab.do_action({"a": "ability", "uid": bacta.uid, "idx": 0}) and lab.submit_choice([recover.uid])
		and lab.players[0].deck[0] == recover and bacta.zone == "discard", "Bacta Tank puts the unit on top after paying its cost")
	lab.active = 0
	var chamber := lab._new_inst("HMW_095", 0)
	lab.attach_upgrade(chamber, lab_base)
	target.exhausted = true
	check(lab.do_action({"a": "ability", "uid": chamber.uid, "idx": 0}) and lab.submit_choice([target.uid]), "Carbonite Chamber targets a non-Vehicle")
	for cycle in 2:
		lab.push_frame([{"op": "_ready_all"}], {"ctl": 0})
		lab.pump()
		check(target.exhausted == (cycle == 0), "Carbonite lasts exactly one regroup")

	var siege := funded_match()
	var siege_base: CardInst = siege.players[0].base
	var camp := siege._new_inst("HMW_216", 0)
	siege.attach_upgrade(camp, siege_base)
	var trooper := put_in_hand(siege, "SOR_095")
	check(siege.do_action({"a": "play", "uid": trooper.uid}) and siege.submit_choice([1])
		and camp.zone == "discard" and not trooper.exhausted, "Insurgent Camp sacrifices itself to ready the played unit")
	var trap := siege._new_inst("HMW_171", 0)
	siege.attach_upgrade(trap, siege_base)
	var intruder := siege.create_unit_token(1, "battle_droid")
	siege.pump()
	check(siege.submit_choice([1]) and trap.zone == "discard" and not intruder.in_play(), "Trap Field hits an entering token")

	var intel := funded_match()
	var discarded := intel._new_inst("SOR_095", 1)
	discarded.zone = "hand"
	intel.players[1].hand.append(discarded)
	intel.attach_upgrade(intel._new_inst("HMW_205", 0), intel.players[0].base)
	intel.pump()
	var deck_before: int = intel.players[1].deck.size()
	check(intel.pending.get("player") == 0 and intel.submit_choice([discarded.uid])
		and discarded.zone == "discard" and intel.players[1].deck.size() == deck_before - 1,
		"Intelligence Agency lets its controller choose the opposing discard and gives the opponent a draw")
	var arsenal := funded_match()
	var arsenal_base: CardInst = arsenal.players[0].base
	var victim := add_unit(arsenal, 1, "SOR_095")
	var cannon := arsenal._new_inst("HMW_172", 0)
	var hand_before: int = arsenal.players[0].hand.size()
	arsenal.attach_upgrade(cannon, arsenal_base)
	arsenal.pump()
	check(arsenal.players[0].hand.size() == hand_before + 1, "Heavy Ion Cannon draws when played")
	var cannon_action := {"a": "ability", "uid": arsenal_base.uid, "idx": 0}
	var ammo := put_in_hand(arsenal, "SOR_095")
	check(arsenal.do_action(cannon_action) and arsenal.submit_choice([ammo.uid])
		and arsenal.submit_choice([victim.uid]) and victim.damage == 2, "Heavy Ion Cannon grants the base a discard action")
	arsenal.active = 0
	check(cannon_action not in arsenal.legal_actions(0), "Heavy Ion Cannon is limited to once per phase")
	var doctrine := arsenal._new_inst("HMW_206", 0)
	arsenal.attach_upgrade(doctrine, arsenal_base)
	arsenal.pump()
	var lair := put_in_hand(arsenal, "HMW_147")
	check(arsenal.do_action({"a": "play", "uid": lair.uid}) and arsenal.submit_choice([arsenal_base.uid]),
		"Beast Lair attaches to its base")
	check(victim.uid in arsenal.pending.get("options", []) and arsenal.submit_choice([victim.uid]) and victim.exhausted,
		"Tarkin Doctrine reacts to a Fortification play")
	arsenal.start_action_phase()
	arsenal.pump()
	var bait := put_in_hand(arsenal, "SOR_095")
	check(arsenal.submit_choice([1]) and arsenal.submit_choice([bait.uid])
		and arsenal.players[0].units.any(func(unit): return unit.is_token and unit.name() == "Beast" and unit.exhausted),
		"Beast Lair creates an exhausted Beast after the discard")
	arsenal.attach_upgrade(arsenal._new_inst("HMW_160", 0), arsenal_base)
	var top := arsenal._new_inst("ASH_172", 0)
	arsenal.players[0].deck.push_front(top)
	arsenal.push_frame([{"op": "_regroup_triggers"}], {"ctl": 0})
	arsenal.pump()
	check(arsenal.submit_choice([victim.uid]) and victim.zone == "discard" and arsenal.players[0].deck[0] == top,
		"Noxious Refinery reveals an Aggression card and leaves it on top")


func test_upgrade_search_filters() -> void:
	for id in ["LOF_068", "SEC_072", "SHD_245", "HMW_085"]:
		var m := funded_match()
		var plans := m._new_inst("JTL_260", 0)
		var devotion := m._new_inst("SOR_070", 0)
		var pilot := m._new_inst("JTL_058", 0)
		m.players[0].deck.push_front(pilot)
		m.players[0].deck.push_front(devotion)
		m.players[0].deck.push_front(plans)
		if id == "LOF_068":
			var attacker := add_unit(m, 0, id)
			m.do_action({"a": "attack", "uid": attacker.uid, "target": m.players[1].base.uid})
		else:
			var search := put_in_hand(m, id)
			m.do_action({"a": "play", "uid": search.uid})
		var expected := [plans.uid] if id == "LOF_068" else [plans.uid, devotion.uid]
		check(m.pending.get("kind") == "search" and m.pending.get("options") == expected,
			"%s search filters out the Pilot unit and applies any Item restriction" % id)
		check(m.submit_choice([plans.uid]) and plans.zone == "hand" and pilot.zone == "deck",
			"%s draws the selected upgrade" % id)


func test_unit_control_changes() -> void:
	var m := funded_match()
	var marine := add_unit(m, 1, "SOR_095", false)
	marine.damage = 1
	m.attach_token(marine, "experience")
	var upgrade: CardInst = marine.upgrades[0]
	var event := put_in_hand(m, "SOR_224")
	check(m.do_action({"a": "play", "uid": event.uid}) and m.submit_choice([marine.uid]),
		"Change of Heart can take a non-leader unit")
	check(marine in m.players[0].units and marine not in m.players[1].units
		and marine.exhausted and marine.damage == 1 and upgrade.controller == 1 and upgrade.attached_to == marine,
		"Changing control preserves the unit's damage, exhaustion and attachments")
	var rey := add_unit(m, 1, "LAW_149")
	check(not m.take_control(rey, 0) and rey.controller == 1, "Rey resists opposing control changes")
	m.do_action({"a": "pass"})
	m.do_action({"a": "pass"})
	check(m.phase == "regroup" and marine.controller == marine.owner and marine in m.players[1].units,
		"Change of Heart returns the unit at the start of regroup")
	var takeover := funded_match()
	var target := add_unit(takeover, 1, "SOR_095")
	target.damage = 1
	var palpatine := put_in_hand(takeover, "HMW_110")
	check(takeover.do_action({"a": "play", "uid": palpatine.uid})
		and takeover.pending.get("min") == 0 and takeover.submit_choice([]) and target.controller == 1,
		"Palpatine's control effect can be declined")
	takeover.active = 0
	palpatine = put_in_hand(takeover, "HMW_110")
	check(takeover.do_action({"a": "play", "uid": palpatine.uid}) and takeover.submit_choice([target.uid])
		and target.zone == "discard" and target in takeover.players[1].discard,
		"Palpatine takes control and Weakness defeats the unit into its owner's discard")


func test_rebel_attack_sequences() -> void:
	var m := funded_match()
	var first := add_unit(m, 0, "SOR_095")
	var second := add_unit(m, 0, "SOR_237")
	first.mods.append({"abilities": [{"trigger": "on_attack",
		"effects": [{"op": "ready", "t": {"s": "self"}}]}]})
	var assault := put_in_hand(m, "SOR_103")
	var base: CardInst = m.players[1].base
	check(m.do_action({"a": "play", "uid": assault.uid}) and m.submit_choice([first.uid]),
		"Rebel Assault starts with the selected Rebel")
	check(m.submit_choice([base.uid]) and base.damage == first.printed_power() + 1,
		"The first attack resolves before the second prompt")
	check(not first.exhausted and m.pending.get("options") == [second.uid]
		and m.submit_choice([second.uid]) and m.submit_choice([base.uid]),
		"Rebel Assault requires a different Rebel even if the first readied during combat")
	check(base.damage == first.printed_power() + second.printed_power() + 2,
		"Both attacks get the printed bonus")
	for unit_id in ["SOR_095", "ASH_121"]:
		var fleet := funded_match()
		var ally := add_unit(fleet, 0, unit_id)
		var lieutenant := put_in_hand(fleet, "SOR_240")
		var opposing_base: CardInst = fleet.players[1].base
		check(fleet.do_action({"a": "play", "uid": lieutenant.uid}) and fleet.submit_choice([ally.uid])
			and fleet.submit_choice([opposing_base.uid]), "Fleet Lieutenant can choose a Rebel or a non-Rebel")
		check(opposing_base.damage == ally.printed_power() + (2 if ally.has_trait("rebel") else 0),
			"Fleet Lieutenant buffs only a Rebel attacker")


func test_upgrade_defeat_and_ready_aura() -> void:
	var m := funded_match()
	var zeb := add_unit(m, 0, "ASH_161")
	var ally := add_unit(m, 0, "SOR_095")
	var enemy := add_unit(m, 1, "SOR_095")
	var unity := put_in_hand(m, "SEC_104")
	var base: CardInst = m.players[1].base
	check(m.do_action({"a": "play", "uid": unity.uid}) and m.submit_choice([zeb.uid]),
		"Figure of Unity attaches to a unique unit")
	check(ally.has_kw("overwhelm") and ally.kw("raid") == 1 and ally.kw("restore") == 1
		and not zeb.has_kw("overwhelm") and not enemy.has_kw("overwhelm"),
		"Figure of Unity grants all three keywords to the host's other allies")
	m.exhaust(zeb)
	check(not ally.has_kw("overwhelm") and ally.kw("raid") == 0 and ally.kw("restore") == 0,
		"Figure of Unity's aura ends when the host exhausts")
	var upgrade := m._new_inst("SOR_070", 0)
	m.attach_upgrade(upgrade, enemy)
	check(upgrade.controller == 0 and enemy.kw("restore") == 2, "The upgrade stays friendly while granting the enemy its ability")
	m.return_to_hand(enemy)
	m.pump()
	check(upgrade.zone == "discard" and m.submit_choice([base.uid]) and base.damage == 1,
		"Zeb triggers when his upgrade is defeated on a bounced enemy")
	m.attach_token(ally, "shield")
	m.deal_damage(ally, 1, null)
	m.pump()
	check(ally.damage == 0 and ally.shield_count() == 0 and m.submit_choice([base.uid]) and base.damage == 2,
		"Zeb also triggers on a Shield that prevents damage")
	m.defeat(zeb)
	m.pump()
	check(unity.zone == "discard" and m.submit_choice([base.uid]) and base.damage == 3,
		"Zeb sees his own upgrade defeated as he leaves play")


func test_multi_mode_events() -> void:
	var m := funded_match()
	var unit := add_unit(m, 0, "SOR_095")
	var vigilance := put_in_hand(m, "SOR_058")
	var cards_before: int = m.players[1].deck.size()
	check(m.do_action({"a": "play", "uid": vigilance.uid}) and m.submit_choice([0]),
		"Vigilance offers its modes through the normal play action")
	check(m.players[1].deck.size() == cards_before and not m.submit_choice([0]),
		"Both distinct modes must be selected before the first resolves")
	check(m.submit_choice([3]) and m.players[1].deck.size() == cards_before - 6,
		"Vigilance discards from the opponent's deck before prompting for the selected Shield mode")
	check(m.submit_choice([unit.uid]) and unit.shield_count() == 1,
		"Vigilance grants the Shield to the selected unit")


func test_printed_event_rules() -> void:
	for event_id in ["SOR_173", "SOR_221", "SOR_043", "SOR_154"]:
		var m := funded_match()
		var friendly := add_unit(m, 0, "SOR_095")
		var enemy := add_unit(m, 1, "SOR_095")
		var ship := add_unit(m, 1, "SOR_237")
		var tactic := put_in_hand(m, event_id)
		check(m.do_action({"a": "play", "uid": tactic.uid}), "%s can be played from hand" % tactic.name())
		match event_id:
			"SOR_173":
				check(m.pending.get("labels") == ["Ground", "Space"] and m.submit_choice([0]), "Bombing Run chooses an arena")
				check(friendly.zone == "discard" and enemy.zone == "discard" and ship.damage == 0,
					"Bombing Run hits both sides of only the chosen arena")
			"SOR_221":
				check(m.submit_choice([1]) and ship.exhausted and not friendly.exhausted and not enemy.exhausted,
					"Outmaneuver exhausts only the chosen arena")
			"SOR_043":
				check(m.all_units().is_empty(), "Superlaser Blast defeats all units in both arenas")
			"SOR_154":
				check(friendly.kw("raid") == 2 and enemy.kw("raid") == 0, "Rallying Cry grants Raid 2 only to friendly units")
				m._end_action_phase()
				check(friendly.kw("raid") == 0, "Rallying Cry expires when the phase ends")

	var frozen := funded_match()
	var leader: CardInst = frozen.players[1].leader
	leader.deployed = true
	frozen._put_in_play(leader, "ground", true)
	var freeze := put_in_hand(frozen, "SOR_186")
	check(frozen.do_action({"a": "play", "uid": freeze.uid}) and frozen.submit_choice([leader.uid]),
		"No Good to Me Dead may target an already exhausted leader unit")
	frozen.exhaust(leader, false)
	Effects.exec(frozen, {"op": "_ready_all"}, {})
	check(leader.exhausted, "No Good to Me Dead blocks card effects and the regroup ready step")
	frozen.end_round()
	frozen.exhaust(leader, false)
	check(not leader.exhausted, "No Good to Me Dead expires before the next round")

	var bolt := funded_match()
	var blaster := add_unit(bolt, 0, "SOR_095", false)
	var target := add_unit(bolt, 1, "SOR_049")
	var strike := put_in_hand(bolt, "SOR_127")
	check(bolt.do_action({"a": "play", "uid": strike.uid}) and bolt.pending.get("options") == [blaster.uid]
		and bolt.submit_choice([blaster.uid]) and bolt.pending.get("options") == [target.uid]
		and bolt.submit_choice([target.uid]) and target.damage == blaster.power(),
		"Strike True uses the selected friendly unit's power as non-combat damage")
	check(blaster.damage == 0 and blaster.exhausted, "Strike True does not start an attack or ready its source")
	var lucky := funded_match()
	var wounded := add_unit(lucky, 0, "SOR_049")
	wounded.damage = 2
	var rival := add_unit(lucky, 1, "SOR_095")
	var balance := put_in_hand(lucky, "SOR_075")
	check(lucky.do_action({"a": "play", "uid": balance.uid}) and lucky.submit_choice([wounded.uid])
		and lucky.submit_choice([1]) and wounded.damage == 1 and not wounded.uid in lucky.pending.get("options", [])
		and lucky.submit_choice([rival.uid]) and rival.damage == 1, "It Binds All Things uses the amount actually healed and excludes the healed unit")

	var choke_match := funded_match()
	var victim := add_unit(choke_match, 1, "SOR_095")
	var vehicle := add_unit(choke_match, 1, "SOR_237")
	var choke := put_in_hand(choke_match, "SOR_139")
	var normal_cost := choke_match.play_cost(0, choke)
	add_unit(choke_match, 0, "SOR_049")
	var enemy_cards: int = choke_match.players[1].hand.size()
	check(choke_match.play_cost(0, choke) == normal_cost - 1, "Force Choke discounts by one for a friendly Force unit")
	check(choke_match.do_action({"a": "play", "uid": choke.uid}) and not vehicle.uid in choke_match.pending.get("options", [])
		and choke_match.submit_choice([victim.uid]) and victim.zone == "discard"
		and choke_match.players[1].hand.size() == enemy_cards + 1, "Force Choke excludes Vehicles and the target controller draws even if the unit is defeated")

	var brief := funded_match()
	var briefing := put_in_hand(brief, "SOR_171")
	var friendly_cards: int = brief.players[0].hand.size()
	enemy_cards = brief.players[1].hand.size()
	check(brief.do_action({"a": "play", "uid": briefing.uid}) and brief.submit_choice([1])
		and brief.players[0].hand.size() == friendly_cards - 1 and brief.players[1].hand.size() == enemy_cards + 2,
		"Mission Briefing draws for the chosen player")

	for refusal in [false, true]:
		var father := funded_match()
		var defender := add_unit(father, 1, "SOR_095")
		for i in 3:
			var deck_card := father._new_inst("SOR_095", 0)
			deck_card.zone = "deck"
			father.players[0].deck.append(deck_card)
		var event := put_in_hand(father, "SOR_233")
		friendly_cards = father.players[0].hand.size()
		check(father.do_action({"a": "play", "uid": event.uid}) and father.submit_choice([defender.uid])
			and father.pending.get("player") == 1 and father.submit_choice([1 if refusal else 0]),
			"I Am Your Father asks the targeted unit's controller")
		check(defender.in_play() == refusal and father.players[0].hand.size() == friendly_cards - 1 + (3 if refusal else 0),
			"I Am Your Father deals damage or lets the event player draw, according to the opponent's choice")

	var inspect := funded_match()
	var enemy_nonunit := put_in_hand(inspect, "SOR_200")
	var enemy_unit: CardInst = inspect.players[1].hand[0]
	inspect.players[0].hand.erase(enemy_nonunit)
	enemy_nonunit.owner = 1
	enemy_nonunit.controller = 1
	inspect.players[1].hand.append(enemy_nonunit)
	var scout := put_in_hand(inspect, "SOR_201")
	check(inspect.do_action({"a": "play", "uid": scout.uid}) and inspect.pending.get("player") == 0
		and enemy_unit.uid in inspect.pending.get("reveal", []) and inspect.pending.get("options") == [enemy_nonunit.uid],
		"Bodhi Rook shows the full opponent hand but only offers eligible discards")
	check(not inspect.submit_choice([enemy_unit.uid]) and inspect.submit_choice([enemy_nonunit.uid])
		and enemy_nonunit.zone == "discard", "Bodhi Rook discards the chosen non-unit")
	inspect.active = 0
	var spark := put_in_hand(inspect, "SOR_200")
	check(inspect.do_action({"a": "play", "uid": spark.uid}) and inspect.submit_choice([enemy_unit.uid])
		and enemy_unit.zone == "discard", "Spark of Rebellion allows the player to discard a unit")


func test_play_discounts() -> void:
	var m := funded_match()
	var droid := add_unit(m, 0, "SEC_110")
	var marine := put_in_hand(m, "SOR_095")
	var second_marine := put_in_hand(m, "SOR_095")
	var event := put_in_hand(m, "SOR_126")
	var full_cost := m.play_cost(0, marine)
	var event_cost := m.play_cost(0, event)
	check(m.do_action({"a": "attack", "uid": droid.uid, "target": m.players[1].base.uid})
		and m.play_cost(0, marine) == full_cost - 1 and m.play_cost(0, event) == event_cost,
		"GNK Power Droid discounts only the next unit")
	m.active = 0
	check(m.do_action({"a": "play", "uid": event.uid}) and m.play_cost(0, marine) == full_cost - 1,
		"A nonmatching play preserves the unit discount")
	m.active = 0
	check(m.do_action({"a": "play", "uid": marine.uid}) and m.play_cost(0, second_marine) == full_cost,
		"Playing a matching card consumes the discount exactly once")
	var conditional := funded_match()
	var volunteer := put_in_hand(conditional, "SOR_248")
	check(conditional.play_cost(0, volunteer) == volunteer.cost(), "Volunteer Soldier costs full price without a Trooper")
	var trooper := add_unit(conditional, 0, "SOR_095")
	check(conditional.play_cost(0, volunteer) == volunteer.cost() - 1, "A friendly Trooper discounts Volunteer Soldier")
	add_unit(conditional, 0, "SEC_064")
	var plans := put_in_hand(conditional, "JTL_260")
	var second_plans := put_in_hand(conditional, "JTL_260")
	check(conditional.play_cost(0, plans) == plans.cost() - 1
		and conditional.do_action({"a": "play", "uid": plans.uid})
		and conditional.submit_choice([trooper.uid]),
		"Congress of Malastare discounts the first upgrade before it is attached")
	check(conditional.play_cost(0, second_plans) == second_plans.cost(), "The second upgrade is full price")
	conditional.phase_serial += 1
	check(conditional.play_cost(0, second_plans) == second_plans.cost() - 1, "A new phase restores the first-upgrade discount")


func test_advantage_and_weakness() -> void:
	var m := funded_match()
	var attacker := add_unit(m, 0, "SOR_095")
	var defender := add_unit(m, 1, "SOR_095")
	m.attach_token(attacker, "advantage")
	m.attach_token(defender, "advantage")
	m.attach_token(attacker, "shield")
	m.attach_token(defender, "shield")
	check(attacker.power() == attacker.printed_power() + 1 and attacker.max_hp() == attacker.printed_hp(),
		"Advantage grants power without changing HP")
	check(m.do_action({"a": "attack", "uid": attacker.uid, "target": defender.uid})
		and attacker.power() == attacker.printed_power() and defender.power() == defender.printed_power(),
		"Advantage expires on both sides after combat")
	var weakened := add_unit(m, 1, "SOR_095")
	weakened.damage = weakened.printed_hp() - 1
	m.attach_token(weakened, "weakness")
	m.pump()
	check(weakened.zone == "discard", "Weakness can defeat a damaged unit by reducing HP")
	var token_match := funded_match()
	var axe := add_unit(token_match, 0, "ASH_169")
	token_match.draw(0, 2)
	token_match.pump()
	check(axe.power() == axe.printed_power() + 1, "Drawing two cards together grants Axe Woves one Advantage")
	var path := put_in_hand(token_match, "ASH_257")
	check(token_match.do_action({"a": "play", "uid": path.uid}) and token_match.submit_choice([1]),
		"Choose Your Path resolves its Mandalorian option")
	var created: CardInst = token_match.players[0].units.back()
	check(created.id == "ASH_T01" and created.shield_count() == 1 and created.power() == created.printed_power() + 1,
		"The newly created Mandalorian receives its Shield and the event's Advantage")


func test_ability_usage_limits() -> void:
	var m := funded_match()
	var base := m._new_inst("LOF_022", 0)
	base.zone = "base"
	m.players[0].base = base
	var action := {"a": "ability", "uid": base.uid, "idx": 0}
	for _i in 3:
		m.active = 0
		m.players[0].force_token = false
		check(m.do_action(action) and m.players[0].force_token,
			"Mystic Monastery grants the Force on an allowed use")
	m.active = 0
	m.players[0].force_token = false
	check(action not in m.legal_actions(0) and not m.do_action(action), "Mystic Monastery cannot be used a fourth time")
	var firespray := add_unit(m, 0, "JTL_157")
	var attack := {"a": "attack", "uid": firespray.uid, "target": m.players[1].base.uid}
	check(m.do_action(attack) and not firespray.exhausted, "Relentless Firespray readies on its first attack")
	m.active = 0
	check(m.do_action(attack) and firespray.exhausted, "Relentless Firespray stays exhausted after its second attack")


func test_damage_and_heal_triggers() -> void:
	var m := funded_match()
	var baze := add_unit(m, 0, "LAW_047")
	var crosshair := add_unit(m, 1, "HMW_169")
	var advisor := add_unit(m, 1, "SEC_041")
	var base: CardInst = m.players[1].base
	var hand_sizes := [m.players[0].hand.size(), m.players[1].hand.size()]
	m.attach_token(crosshair, "shield")
	m.deal_damage(crosshair, 1, baze)
	m.pump()
	check(m.players[1].hand.size() == hand_sizes[1], "Prevented damage does not trigger Crosshair")
	m.deal_damage(crosshair, 1, baze)
	m.pump()
	check(m.players[0].hand.size() == hand_sizes[0] + 1 and m.players[1].hand.size() == hand_sizes[1] + 1,
		"Both players draw after Crosshair survives damage")
	m.deal_damage(base, 1, baze)
	m.pump()
	check(not advisor.has_kw("sentinel"), "Ability damage to the base does not trigger Populist Advisor")
	check(m.do_action({"a": "attack", "uid": baze.uid, "target": base.uid}) and advisor.has_kw("sentinel"),
		"Combat damage to the base grants Sentinel")
	baze.damage = 1
	check(m.heal(baze, 2) == 1, "Healing is capped at actual damage")
	m.pump()
	check(m.submit_choice([advisor.uid]) and advisor.damage == 1, "Baze deals the amount actually healed")


func test_jabba_action_play_requirements() -> void:
	var m := funded_match()
	var jabba := add_unit(m, 0, "LAW_015")
	jabba.deployed = true
	var action := {"a": "ability", "uid": jabba.uid, "idx": 0}
	var marine := put_in_hand(m, "SOR_095")
	check(action not in m.legal_actions(0), "Jabba cannot spend a turn with no Underworld unit in hand")
	var khetanna := put_in_hand(m, "LAW_158")
	for resource in m.players[0].resources:
		resource.exhausted = true
	check(action not in m.legal_actions(0), "Jabba cannot use the action with an unaffordable Underworld unit")
	for resource in m.players[0].resources:
		resource.exhausted = false
	check(m.do_action(action) and m.pending.get("options") == [khetanna.uid],
		"Jabba offers only the affordable Underworld unit")
	check(m.submit_choice([khetanna.uid]) and khetanna.in_play() and marine.zone == "hand",
		"Jabba plays the selected unit and completes the turn")


func test_campaign_krayt_call() -> void:
	var m := funded_match()
	m.tokens = Tokens.resolve(["initiative", "krayt_call"])
	var claim := {"a": "claim", "token": "krayt_call"}
	var non_tusken := add_unit(m, 1, "SOR_095")
	check(claim not in m.legal_actions(0), "Krayt Call is unavailable without an enemy Tusken")
	var tusken := add_unit(m, 1, "HMW_224")
	check(claim in m.legal_actions(0) and m.do_action(claim), "Krayt Call can be claimed once a Tusken is in play")
	check(m.pending.get("options") == [tusken.uid] and str(m.pending.get("prompt")).begins_with("Krayt Call"),
		"Krayt Call names its effect and lists only an eligible enemy")
	check(not m.submit_choice([non_tusken.uid]) and not m.pending.is_empty(), "Invalid target keeps the choice open")
	check(m.submit_choice([tusken.uid]) and tusken.zone == "hand", "Krayt Call returns the selected Tusken to hand")
	check(m.pending.is_empty() and m.active == 1 and not m.players[0].out_of_round, "Krayt Call spends one action")
	var round_before := m.round_num
	m.do_action({"a": "pass"})
	check(claim not in m.legal_actions(0), "Krayt Call can be used only once per round")
	m.do_action({"a": "pass"})
	while not m.pending.is_empty():
		m.submit_choice(m.pending["options"].slice(0, m.pending["min"]))
	check(m.round_num == round_before + 1 and not m.players[0].out_of_round, "Krayt Call permits the following round")


func test_campaign_attack_pressure() -> void:
	var m := funded_match()
	m.rules.name = "campaign"
	m.tokens = Tokens.resolve(["initiative", "plan"])
	var sentinel := add_unit(m, 0, "SOR_095")
	sentinel.mods.append({"kw": "sentinel"})
	m.attach_token(sentinel, "shield")
	add_unit(m, 1, "SOR_095")
	add_unit(m, 1, "SOR_095")
	m.players[1].hand.clear()
	m.active = 1
	var chosen := AiBot.act(m)
	check(chosen.get("a") == "attack" and sentinel.shield_count() == 0,
		"Campaign opponent uses its swarm to break a Sentinel's shield before claiming a token")


func test_piloting() -> void:
	var m := funded_match()
	var fighter := add_unit(m, 0, "SOR_237")
	var enemy := add_unit(m, 1, "SOR_237")
	add_unit(m, 0, "SOR_095")
	var pilot := put_in_hand(m, "JTL_058")
	var action := {"a": "pilot", "uid": pilot.uid}
	check(pilot.card_type() == "unit" and action in m.legal_actions(0), "Academy Graduate has a separate Pilot action")
	check(m.do_action(action) and m.pending.get("options") == [fighter.uid], "Piloting requires a friendly Vehicle without a Pilot")
	check(not m.submit_choice([enemy.uid]) and m.submit_choice([fighter.uid]), "Only the eligible friendly Vehicle can be selected")
	check(pilot.card_type() == "upgrade" and fighter.power() == fighter.printed_power() + 1
		and fighter.max_hp() == fighter.printed_hp() + 2 and fighter.has_kw("sentinel"), "Pilot uses its printed upgrade side")
	m.active = 0
	var second := put_in_hand(m, "JTL_084")
	check({"a": "pilot", "uid": second.uid} not in m.legal_actions(0), "Ordinary Pilots cannot double up")
	var r2 := put_in_hand(m, "JTL_245")
	check(m.do_action({"a": "pilot", "uid": r2.uid}) and m.submit_choice([fighter.uid]), "R2-D2 can join a piloted Vehicle")
	m.defeat(pilot)
	m.pump()
	check(pilot.card_type() == "unit" and not fighter.has_kw("sentinel"), "Defeating a Pilot restores its off-board type and removes granted rules")
	m.active = 0
	check(m.do_action({"a": "pilot", "uid": second.uid}) and m.submit_choice([fighter.uid]), "A Pilot can fill R2-D2's additional slot")
	check(m.players[0].units.any(func(c): return c.name() == "TIE Fighter"), "Wingman Victor Two resolves its upgrade-only trigger")
	var ability_match := funded_match()
	var vehicle := add_unit(ability_match, 0, "SOR_237")
	var hand_pilot := put_in_hand(ability_match, "JTL_058")
	ability_match.push_frame([{"op": "play_from_hand", "kind": "card"}], {"ctl": 0})
	ability_match.pump()
	check(ability_match.submit_choice([hand_pilot.uid]) and ability_match.pending.get("kind") == "option",
		"An effect that plays a card offers both legal Pilot modes")
	check(ability_match.submit_choice([1]) and ability_match.submit_choice([vehicle.uid])
		and hand_pilot.attached_to == vehicle, "Choosing the Pilot mode through an effect attaches the Pilot")


func test_indirect_damage() -> void:
	var m := funded_match()
	var ship := add_unit(m, 0, "JTL_149")
	var victim := add_unit(m, 1, "SOR_095")
	victim.damage = 1
	m.attach_token(victim, "shield")
	var base: CardInst = m.players[1].base
	check(m.do_action({"a": "attack", "uid": ship.uid, "target": base.uid}), "Y-Wing starts its indirect-damage attack")
	check(m.pending.get("kind") == "damage_assignment" and m.pending.get("player") == 1, "Defending player assigns indirect damage")
	check(m.submit_choice([victim.uid]) and victim.damage == 1, "Indirect assignments are held until complete")
	check(m.submit_choice([victim.uid]) and victim.zone == "discard", "A unit can take only up to its remaining HP")
	check(base.damage == 1 + ship.power(true), "The rest goes to the base, followed by regular combat")
	check(not m.events.any(func(e): return e.get("t") == "shield_break" and e.get("uid") == victim.uid),
		"Indirect damage bypasses Shields without spending them")


func test_optional_card_choices() -> void:
	var m := funded_match()
	var unit := put_in_hand(m, "LAW_236")
	var discard := put_in_hand(m, "SOR_095")
	check(m.do_action({"a": "play", "uid": unit.uid}) and m.pending.get("kind") == "yesno",
		"Optional discard asks before paying the cost")
	var credits: int = m.players[0].credits
	check(m.submit_choice([1]) and discard.uid in m.pending.get("options", []),
		"Accepting the discard opens the hand picker")
	check(m.submit_choice([discard.uid]) and discard.zone == "discard" and m.players[0].credits == credits + 1,
		"Selecting a discard pays the cost and creates a Credit")
	var m2 := funded_match()
	unit = put_in_hand(m2, "LAW_236")
	m2.do_action({"a": "play", "uid": unit.uid})
	check(m2.submit_choice([0]) and m2.pending.is_empty() and m2.players[0].credits == 0,
		"Declining the discard skips the follow-up")

	var m3 := funded_match()
	var upgrade := m3._new_inst("SOR_215", 0)
	upgrade.zone = "discard"
	m3.players[0].discard.append(upgrade)
	var salvager := put_in_hand(m3, "SHD_044")
	check(m3.do_action({"a": "play", "uid": salvager.uid}) and m3.pending.get("min") == 0,
		"Optional recovery offers an eligible card or Skip")
	check(m3.submit_choice([upgrade.uid]) and upgrade.zone == "hand", "Optional recovery returns the selected upgrade")

	var m4 := funded_match()
	var recruit := put_in_hand(m4, "SOR_095")
	m4.push_frame([{"op": "play_from_hand", "kind": "unit"}], {"ctl": 0})
	m4.pump()
	check(not m4.submit_choice([]), "A mandatory play choice cannot be skipped")
	check(m4.submit_choice([recruit.uid]) and recruit.in_play(), "Mandatory card selection resolves normally")


func test_coordinate_triggers() -> void:
	var m := blank_match()
	var anakin := add_unit(m, 0, "TWI_147")
	var target: CardInst = m.players[1].base
	var starting_hand: int = m.players[0].hand.size()
	add_unit(m, 0, "SOR_095")
	check(m.do_action({"a": "attack", "uid": anakin.uid, "target": target.uid}), "Anakin attacks below Coordinate threshold")
	check(m.players[0].hand.size() == starting_hand, "Anakin does not draw with two units")
	add_unit(m, 0, "SOR_237")
	m.active = 0
	anakin.exhausted = false
	check(m.do_action({"a": "attack", "uid": anakin.uid, "target": target.uid}), "Anakin attacks with Coordinate")
	check(m.players[0].hand.size() == starting_hand + 1, "Anakin draws with three units across both arenas")
	var m2 := funded_match()
	var ahsoka := m2._new_inst("TWI_011", 0)
	ahsoka.zone = "leader"
	m2.players[0].leader = ahsoka
	add_unit(m2, 0, "SOR_095")
	add_unit(m2, 0, "SOR_237")
	var action := {"a": "ability", "uid": ahsoka.uid, "idx": 0}
	check(action not in m2.legal_actions(0), "Undeployed Ahsoka does not count as a unit")
	add_unit(m2, 0, "SOR_095")
	check(action in m2.legal_actions(0), "Ahsoka's Coordinate action unlocks with a third unit")


func test_card_play_triggers() -> void:
	var m := funded_match()
	var poggle := add_unit(m, 0, "TWI_080")
	var unit := put_in_hand(m, "SOR_095")
	check(m.do_action({"a": "play", "uid": unit.uid}), "Play a unit with Poggle on the board")
	check(m.pending.get("kind") == "yesno", "Poggle offers optional exhaust")
	m.submit_choice([0])
	check(not poggle.exhausted and m.players[0].units.size() == 2, "Declining Poggle skips both effects")
	m.active = 0
	unit = put_in_hand(m, "SOR_095")
	m.do_action({"a": "play", "uid": unit.uid})
	m.submit_choice([1])
	check(poggle.exhausted and m.players[0].units.size() == 4, "Accepting Poggle exhausts him and creates a Battle Droid")
	m.active = 0
	unit = put_in_hand(m, "SOR_095")
	m.do_action({"a": "play", "uid": unit.uid})
	check(m.pending.is_empty() and m.players[0].units.size() == 5, "Exhausted Poggle can't create a second Droid")

	var m2 := funded_match()
	var cobb := add_unit(m2, 0, "ASH_060")
	unit = put_in_hand(m2, "SOR_095")
	m2.do_action({"a": "play", "uid": unit.uid})
	m2.submit_choice([1])
	check(cobb.damage == 2 and unit.shield_count() == 1 and cobb.shield_count() == 0,
		"Cobb pays damage to himself and shields the played unit")

	var m3 := funded_match()
	var cassian := put_in_hand(m3, "SHD_148")
	m3.do_action({"a": "play", "uid": cassian.uid})
	check(cassian.in_play() and cassian.exhausted, "Cassian enters exhausted when played from hand")
	m3.active = 0
	var crew := m3._new_inst("SHD_113", 0)
	m3.move_to_resources(0, crew)
	check(m3.do_action({"a": "smuggle", "uid": crew.uid}), "Privateer Crew can be smuggled through the normal action")
	check(crew.in_play() and crew.upgrades.size() == 3, "Smuggled Privateer Crew gets three Experience tokens")
	m3.active = 0
	m3.defeat(cassian)
	m3.pump()
	m3.move_to_resources(0, cassian)
	check(m3.do_action({"a": "smuggle", "uid": cassian.uid}), "Cassian can be smuggled")
	check(cassian.in_play() and not cassian.exhausted, "Smuggle readies Cassian")


func test_defeat_and_deploy_triggers() -> void:
	var m := funded_match()
	add_unit(m, 0, "LOF_130")
	var ally := add_unit(m, 0, "SOR_095")
	var foe := add_unit(m, 1, "SOR_095")
	m.defeat(ally)
	m.pump()
	check(m.players[1].base.damage == 0, "HK-47 ignores friendly defeats")
	m.defeat(foe)
	m.pump()
	check(m.players[1].base.damage == 1, "HK-47 damages the defeated enemy's base")
	var base := m._new_inst("TWI_025", 0)
	base.zone = "base"
	m.players[0].base = base
	var starting_hand: int = m.players[0].hand.size()
	check(m.do_action({"a": "deploy"}), "Deploy leader through legal action")
	check(m.players[0].hand.size() == starting_hand + 1, "Shadow Collective Camp draws on friendly leader deployment")


func test_base_epic_actions() -> void:
	var m := funded_match()
	var base := m._new_inst("SOR_019", 0)
	base.zone = "base"
	m.players[0].base = base
	var unit := add_unit(m, 0, "SOR_095")
	var epic := {"a": "ability", "uid": base.uid, "idx": 0}
	check(m.do_action(epic), "Security Complex Epic Action is playable")
	m.submit_choice([unit.uid])
	check(unit.shield_count() == 1, "Security Complex grants its printed Shield token")
	m.active = 0
	check(epic not in m.legal_actions(0) and base.epic_used, "Base Epic Action is spent after one use")
	var standard := blank_match()
	var mismatched := standard._new_inst("SOR_237", 0)
	mismatched.data = mismatched.data.duplicate()
	mismatched.data["aspects"] = ["aggression", "command", "villainy"]
	check(standard.play_cost(0, mismatched, false, {"ignore_one_basic_aspect": true}) == mismatched.cost() + 4,
		"Aspect-ignoring bases waive one missing color and leave the remaining penalties")


func test_attack_timing() -> void:
	var m := funded_match()
	var attacker := add_unit(m, 0, "SOR_095")
	var defender := add_unit(m, 1, "TWI_049")
	var before: int = m.players[1].units.size()
	check(m.do_action({"a": "attack", "uid": attacker.uid, "target": defender.uid}), "Attack a unit with a defensive trigger")
	check(m.players[1].units.size() == before + 1, "Defender creates its Clone Trooper as the attack starts")
	var m2 := funded_match()
	var kit := add_unit(m2, 0, "TWI_165")
	add_unit(m2, 0, "SOR_095")
	add_unit(m2, 0, "SOR_237")
	kit.mods.append({"kw": "overwhelm", "v": 1})
	var marine := add_unit(m2, 1, "SOR_095")
	check(m2.do_action({"a": "attack", "uid": kit.uid, "target": marine.uid}), "Kit Fisto attacks with Coordinate active")
	check(m2.pending.get("op") == "_ordered_triggers" and m2.submit_choice([0]), "Kit Fisto resolves his printed trigger before Restore")
	check(m2.submit_choice([marine.uid]), "Kit Fisto uses On Attack damage on his defender")
	check(not marine.in_play() and kit.damage == 0, "Defender defeated before combat deals no retaliation damage")
	check(m2.players[1].base.damage == kit.power(true), "Overwhelm sends full combat damage to the base")


func test_play_sequence_choices() -> void:
	var m := funded_match()
	var poggle := add_unit(m, 0, "TWI_080")
	var first := put_in_hand(m, "SOR_095")
	var second := put_in_hand(m, "SOR_237")
	m.push_frame([{"op": "play_from_hand", "kind": "unit", "count": 2}], {"ctl": 0})
	m.pump()
	check(m.submit_choice([first.uid]), "First card is selected")
	check(m.pending.get("kind") == "yesno", "First card's play trigger resolves before the second selection")
	m.submit_choice([1])
	check(poggle.exhausted and m.pending.get("kind") == "hand", "Second selection follows the resolved trigger")
	check(m.submit_choice([second.uid]) and second.in_play(), "Second card resolves through the same sequence")


func funded_match() -> Match:
	var rules := RuleSet.premier()
	rules.aspect_penalties = false
	var m := blank_match(rules)
	for i in 12:
		m.move_to_resources(0, m.players[0].deck[0])
	return m


func test_resource_and_return_costs() -> void:
	var m := funded_match()
	var event := put_in_hand(m, "SOR_126")
	check(m.do_action({"a": "play", "uid": event.uid}) and event.zone == "resource" and event.exhausted,
		"Resupply enters resources exhausted")
	var technician := add_unit(m, 0, "SOR_083")
	m.defeat(technician)
	m.pump()
	check(m.pending.get("kind") == "yesno", "Defeated Superlaser Technician offers to become a resource")
	m.submit_choice([1])
	check(technician.zone == "resource" and not technician.exhausted, "Superlaser Technician readies itself as a resource")
	m.active = 0
	var protocol_droid := add_unit(m, 0, "SEC_093")
	var target := add_unit(m, 0, "SOR_095")
	check(m.do_action({"a": "ability", "uid": protocol_droid.uid, "idx": 0}), "C-3PO can pay the return-to-hand cost")
	m.submit_choice([target.uid])
	check(protocol_droid.zone == "hand" and target.power() == target.printed_power() + 2,
		"C-3PO returns to hand before granting his buff")


func put_in_hand(m: Match, id: String) -> CardInst:
	var c := m._new_inst(id, 0)
	c.zone = "hand"
	m.players[0].hand.append(c)
	return c


func test_granted_ambush_on_play() -> void:
	var m := funded_match()
	var dryden := m._new_inst("SEC_007", 0)
	dryden.zone = "leader"
	m.players[0].leader = dryden
	var cost := put_in_hand(m, "TWI_165")
	var recruit := put_in_hand(m, "SOR_095")
	var target := add_unit(m, 1, "SOR_095")
	check(m.do_action({"a": "ability", "uid": dryden.uid, "idx": 0}), "Dryden can use his printed action")
	check(m.submit_choice([cost.uid]) and cost.zone == "discard", "Dryden discards a card that costs at least six")
	check(m.submit_choice([recruit.uid]) and recruit.in_play(), "Dryden plays the eligible unit")
	check(m.pending.get("kind") == "target" and target.uid in m.pending.get("options", []),
		"The unit receives Ambush in time for its on-play attack")
	m.submit_choice([target.uid])
	check(not target.in_play(), "The Ambush attack resolves")


func test_staged_audit_cases() -> void:
	for id in ["SOR_125", "JTL_128"]:
		var m := funded_match()
		var ship := m._new_inst("SOR_237", 0)
		m.players[0].deck.push_front(ship)
		var event := put_in_hand(m, id)
		check(m.do_action({"a": "play", "uid": event.uid}), "%s Prepare for Takeoff is playable" % id)
		check(m.pending.get("options") == [ship.uid], "%s offers the eligible Vehicle" % id)
		check(m.submit_choice([ship.uid]) and ship.zone == "hand", "%s draws the revealed Vehicle" % id)

	var m := funded_match()
	var host := add_unit(m, 0, "SOR_095")
	var upgrade := put_in_hand(m, "SOR_215")
	check(m.do_action({"a": "play", "uid": upgrade.uid}), "Snapshot Reflexes is playable")
	check(m.submit_choice([host.uid]) and upgrade.attached_to == host, "Snapshot Reflexes attaches to the selected unit")
	check(host.power() == host.printed_power() + 1 and host.max_hp() == host.printed_hp() + 1,
		"Snapshot Reflexes grants its printed stats")
	check(m.pending.get("kind") == "yesno" and m.submit_choice([1]), "Snapshot Reflexes offers the attack")
	check(m.submit_choice([m.players[1].base.uid]) and m.players[1].base.damage == host.power(true),
		"Snapshot Reflexes lets its attached unit attack")
	m.active = 0
	var enemy := add_unit(m, 1, "SOR_095")
	upgrade = put_in_hand(m, "SOR_215")
	m.do_action({"a": "play", "uid": upgrade.uid})
	check(m.submit_choice([enemy.uid]) and m.pending.is_empty(), "Snapshot Reflexes cannot make an enemy unit attack")


func test_variable_printed_stats() -> void:
	var m := funded_match()
	var legion := put_in_hand(m, "SOR_118")
	var resources: int = m.players[0].resources.size()
	check(m.do_action({"a": "play", "uid": legion.uid}) and legion.in_play(),
		"97th Legion stays in play with its resource-based HP")
	check(legion.power() == resources and legion.max_hp() == resources, "97th Legion counts all friendly resources")
	m.move_to_resources(0, m.players[0].deck[0], true)
	check(legion.power() == resources + 1 and legion.max_hp() == resources + 1, "Exhausted resources also increase its stats")
	var grievous := add_unit(m, 0, "TS26_050")
	check(grievous.max_hp() == resources + 1 and grievous.has_kw("sentinel"), "General Grievous scales and has Sentinel while undamaged")
	m.deal_damage(grievous, 1, null)
	check(not grievous.has_kw("sentinel"), "General Grievous loses Sentinel after taking damage")


func test_upgrade_targets() -> void:
	var m := blank_match()
	var unit := add_unit(m, 0, "SOR_095")
	var upgrade := m._new_inst("SOR_070", 0)
	m.attach_upgrade(upgrade, unit)
	check(unit.kw("restore") == 2, "attached keyword includes printed value")
	var candidates := Effects.candidates(m, {"kind": "upgrade", "side": "any"}, {"ctl": 0})
	check(upgrade in candidates, "upgrade appears as a target")
	m.defeat(upgrade)
	check(upgrade.zone == "discard" and upgrade.attached_to == null and unit.kw("restore") == 0, "defeating upgrade removes its granted keyword")
	check(upgrade in m.players[0].discard, "upgrade goes to owner's discard")
	var targets := Effects.candidates(m, {"kind": "unit_or_base", "side": "any"}, {"ctl": 0})
	check(unit in targets and m.players[1].base in targets, "unit-or-base target includes both")


func test_continuous_rules() -> void:
	var m := blank_match()
	var ardent := add_unit(m, 0, "SOR_161")
	var printed := ardent.printed_power()
	m.initiative = 0
	check(ardent.power() == printed + 2, "initiative buff active")
	m.initiative = 1
	check(ardent.power() == printed, "initiative buff disappears immediately")
	var restore := add_unit(m, 0, "SOR_112")
	check(restore.kw("restore") == 0, "conditional keyword absent without initiative")
	m.initiative = 0
	check(restore.kw("restore") == 2, "conditional Restore activates with initiative")
	var coordinate := add_unit(m, 0, "TWI_240")
	check(coordinate.power() == coordinate.printed_power() + 1 and coordinate.max_hp() == coordinate.printed_hp() + 1, "Coordinate counts three friendly units")
	m.defeat(ardent)
	check(coordinate.power() == coordinate.printed_power() and coordinate.max_hp() == coordinate.printed_hp(), "Coordinate stops below three units")
	var krennic := m._new_inst("SOR_001", 0)
	krennic.zone = "leader"
	m.players[0].leader = krennic
	restore.damage = 1
	check(restore.power() == restore.printed_power() + 1, "undeployed leader aura affects damaged friendly unit")
	check(coordinate.power() == coordinate.printed_power(), "damaged filter excludes undamaged unit")
	var m2 := blank_match()
	var friendly := add_unit(m2, 0, "SOR_095")
	var enemy := add_unit(m2, 1, "SOR_095")
	var source := add_unit(m2, 0, "TWI_092")
	check(friendly.max_hp() == friendly.printed_hp() + 1, "Heroism aura affects another friendly unit")
	check(enemy.max_hp() == enemy.printed_hp() and source.max_hp() == source.printed_hp(), "other-friendly aura excludes itself and enemy")
	m2.defeat(source)
	check(friendly.max_hp() == friendly.printed_hp(), "source removal removes aura")


func test_capture_and_bounty() -> void:
	var m := blank_match()
	var guard := add_unit(m, 0, "SOR_095")
	var captive := add_unit(m, 1, "SHD_095")
	var upgrade := m._new_inst("SOR_070", 1)
	m.attach_upgrade(upgrade, captive)
	var drawn: int = m.players[0].hand.size()
	check(m.capture(guard, captive), "captures enemy non-leader in same arena")
	check(captive.zone == "captured" and not captive in m.all_units(), "captive leaves battlefield without being defeated")
	check(upgrade.zone == "discard" and captive.upgrades.is_empty(), "capture discards upgrades")
	m.pump()
	check(not m.pending.is_empty() and m.pending["player"] == 0, "opponent of captive's controller chooses bounty")
	m.submit_choice([0])
	check(m.players[0].hand.size() == drawn + 1, "capturing collects printed draw bounty")
	m.defeat(guard)
	check(captive.in_play() and captive.exhausted and captive.controller == captive.owner, "guard defeat rescues captive exhausted under owner")
	check(m.players[0].hand.size() == drawn + 1, "rescue does not retrigger bounty")
	var guard2 := add_unit(m, 0, "SOR_095")
	check(m.capture(guard2, captive), "rescued unit can be captured again")
	m.frames.clear()
	m.pending.clear()
	m.return_to_hand(guard2)
	check(captive.in_play() and captive.exhausted, "returning guard to hand rescues its captive")
	var leader: CardInst = m.players[1].leader
	leader.deployed = true
	m._put_in_play(leader, "ground", false)
	var legal_guard := add_unit(m, 0, "SOR_095")
	check(not m.capture(legal_guard, leader), "leaders cannot be captured")


func test_plot_and_fortify() -> void:
	var m := blank_match()
	var fortify := m._new_inst("HMW_081", 0)
	var targets := Effects.upgrade_targets(m, 0, fortify)
	check(targets == [m.players[0].base], "Fortify can only attach to own base")
	m.attach_upgrade(fortify, m.players[0].base)
	check(fortify.attached_to == m.players[0].base, "Fortify attaches to base")
	var plotted := m._new_inst("SEC_034", 0)
	m.move_to_resources(0, plotted, true)
	for i in 10:
		m.move_to_resources(0, m._new_inst("SOR_095", 0), false)
	var resource_count: int = m.players[0].resources.size()
	var deck_count: int = m.players[0].deck.size()
	m._deploy_leader(0)
	m.pump()
	check(not m.pending.is_empty() and plotted.uid in m.pending["options"], "deploying leader offers affordable Plot card")
	m.submit_choice([plotted.uid])
	for i in 12:
		if m.pending.is_empty():
			break
		m.submit_choice([] if m.pending["min"] == 0 else m.pending["options"].slice(0, m.pending["min"]))
	check(plotted.in_play() and plotted.exhausted, "Plot plays unit exhausted from resources")
	check(m.players[0].resources.size() == resource_count and m.players[0].deck.size() == deck_count - 1, "Plot replaces resource from deck")
	var m2 := blank_match()
	for resource in m2.players[0].resources.duplicate():
		m2._remove_from_zones(resource)
	var own_payment := m2._new_inst("SEC_034", 0)
	m2.move_to_resources(0, own_payment, false)
	var price := m2.play_cost(0, own_payment)
	for i in price - 1:
		m2.move_to_resources(0, m2._new_inst("SOR_095", 0), false)
	m2._deploy_leader(0)
	m2.pump()
	check(own_payment.uid in m2.pending.get("options", []), "Plot can use its own ready resource toward its cost")
	m2.submit_choice([own_payment.uid])
	check(own_payment.in_play() and m2.players[0].ready_resources() == 0, "Plot pays exact resource count and replacement is exhausted")


func test_early_combat_and_tokens() -> void:
	var m := blank_match()
	var han := add_unit(m, 0, "SOR_198")
	var defender := add_unit(m, 1, "SOR_095")
	m.attack = {"a": han.uid, "t": defender.uid}
	m.resolve_combat()
	check(not defender.in_play() and han.damage == 0, "Han defeats defender before it can deal combat damage")
	var shielded := add_unit(m, 1, "SOR_095")
	m.attach_token(shielded, "shield")
	m.attack = {"a": han.uid, "t": shielded.uid}
	m.resolve_combat()
	check(shielded.in_play() and han.damage > 0, "surviving shielded defender still deals combat damage")
	var guard := add_unit(m, 0, "SOR_095")
	var token := m.create_unit_token(1, "battle_droid")
	var uid := token.uid
	check(m.capture(guard, token), "unit token can be captured")
	check(m.card(uid) == null and guard.flags.get("captives", []).is_empty(), "captured token ceases to exist")
	m.defeat(guard)
	check(m.card(uid) == null, "captured token cannot be rescued")

	var battle := funded_match()
	var existing := battle.create_unit_token(0, "battle_droid")
	var doorstep := put_in_hand(battle, "TWI_190")
	check(battle.do_action({"a": "play", "uid": doorstep.uid}), "On the Doorstep plays as a normal event")
	var created: Array = battle.players[0].units.filter(func(unit): return unit != existing and unit.id == existing.id)
	check(created.size() == 3 and created.all(func(unit): return not unit.exhausted),
		"On the Doorstep creates and readies exactly three Battle Droids")
	check(existing.exhausted, "On the Doorstep leaves previously exhausted Battle Droids alone")


func test_multiword_traits() -> void:
	var m := funded_match()
	var enemy_first_order := add_unit(m, 1, "LOF_080")
	var first_order := add_unit(m, 0, "LOF_084")
	var trooper := add_unit(m, 0, "SOR_128")
	var phasma := put_in_hand(m, "JTL_088")
	check(m.do_action({"a": "play", "uid": phasma.uid}), "Captain Phasma plays from hand")
	var options: Array = m.pending.get("options", [])
	check(first_order.uid in options and enemy_first_order.uid in options and trooper.uid not in options and phasma.uid not in options,
		"Captain Phasma can select any other First Order unit")
	var original_power := first_order.power()
	var original_hp := first_order.max_hp()
	check(m.submit_choice([first_order.uid]) and first_order.power() == original_power + 2 and first_order.max_hp() == original_hp + 2,
		"Captain Phasma applies +2/+2 to the selected First Order unit")

	var hunt := funded_match()
	var hunter := add_unit(hunt, 0, "SOR_182", false)
	var exhausted := add_unit(hunt, 0, "SOR_128", false)
	var ventress := put_in_hand(hunt, "LAW_061")
	check(hunt.do_action({"a": "play", "uid": ventress.uid}), "Asajj Ventress plays from hand")
	check(hunt.pending.get("options", []) == [hunter.uid] and hunt.submit_choice([hunter.uid]),
		"Asajj Ventress offers the other Bounty Hunter and excludes the non-Bounty Hunter")
	check(not hunter.exhausted and exhausted.exhausted, "Asajj Ventress readies only the selected Bounty Hunter")


func test_shared_unit_triggers() -> void:
	var m := funded_match()
	var the_executor := put_in_hand(m, "JTL_090")
	var base_uid: int = m.players[1].base.uid
	check(m.do_action({"a": "play", "uid": the_executor.uid}) and m.players[0].units.size() == 4,
		"Executor creates three TIE Fighters when played")
	m.active = 0
	m.exhaust(the_executor, false)
	check(m.do_action({"a": "attack", "uid": the_executor.uid, "target": base_uid}) and m.players[0].units.size() == 7,
		"Executor creates three additional TIE Fighters when attacking")
	m.defeat(the_executor)
	m.pump()
	check(m.players[0].units.size() == 9 and m.players[0].units.all(func(unit): return unit.is_token and unit.name() == "TIE Fighter"),
		"Executor creates three additional TIE Fighters when defeated")

	var avenger_match := funded_match()
	var leader: CardInst = avenger_match.players[1].leader
	leader.deployed = true
	avenger_match._put_in_play(leader, "ground")
	var soldier := add_unit(avenger_match, 1, "SOR_128")
	var avenger := put_in_hand(avenger_match, "SOR_040")
	check(avenger_match.do_action({"a": "play", "uid": avenger.uid}) and avenger_match.pending.get("player") == 1
		and avenger_match.pending.get("options", []) == [soldier.uid], "Avenger has the opponent choose a non-leader unit")
	check(avenger_match.submit_choice([soldier.uid]) and soldier.zone == "discard" and leader.in_play(), "Avenger defeats only the chosen unit")

	var oppress_match := funded_match()
	var savage := put_in_hand(oppress_match, "LOF_137")
	oppress_match.players[0].force_token = true
	check(oppress_match.do_action({"a": "play", "uid": savage.uid}) and oppress_match.submit_choice([1])
		and not oppress_match.players[0].force_token and oppress_match.players[0].base.damage == 0,
		"Savage Opress can spend the Force to prevent the damage when played")
	oppress_match.defeat(savage)
	oppress_match.pump()
	check(oppress_match.pending.is_empty() and oppress_match.players[0].base.damage == 9,
		"Savage Opress deals 9 damage to its own base when defeated without the Force")


func test_attack_end_results() -> void:
	var m := blank_match()
	var windu := add_unit(m, 0, "SOR_149")
	var marine := add_unit(m, 1, "SOR_095")
	m.attach_token(marine, "shield")
	check(m.do_action({"a": "attack", "uid": windu.uid, "target": marine.uid}) and windu.exhausted and marine.in_play(),
		"Mace Windu stays exhausted when a Shield saves the defender")
	m.active = 0
	m.exhaust(windu, false)
	check(m.do_action({"a": "attack", "uid": windu.uid, "target": marine.uid}) and not windu.exhausted and marine.zone == "discard",
		"Mace Windu readies after defeating the defender")

	var hera_match := blank_match()
	var hera := add_unit(hera_match, 0, "ASH_031")
	var hera_base: CardInst = hera_match.players[0].base
	var enemy_base: CardInst = hera_match.players[1].base
	hera_base.damage = 8
	check(hera_match.do_action({"a": "attack", "uid": hera.uid, "target": enemy_base.uid})
		and hera_base.damage == 5 and enemy_base.damage == 3, "Hera heals the amount of combat damage dealt to the base")
	var fatal_defender := add_unit(hera_match, 1, "SOR_095")
	hera_match.active = 0
	hera.damage = 1
	hera.mods.append({"kw": "overwhelm", "dur": "phase"})
	hera_match.exhaust(hera, false)
	fatal_defender.damage = 2
	check(hera_match.do_action({"a": "attack", "uid": hera.uid, "target": fatal_defender.uid})
		and hera.zone == "discard" and hera_base.damage == 3 and enemy_base.damage == 5,
		"Hera still heals from Overwhelm when both combatants are defeated")

	var cruiser_match := blank_match()
	var cruiser := add_unit(cruiser_match, 0, "SHD_122")
	var ship := add_unit(cruiser_match, 1, "SOR_225")
	check(cruiser_match.do_action({"a": "attack", "uid": cruiser.uid, "target": ship.uid}) and ship.zone == "resource"
		and ship in cruiser_match.players[0].resources and ship.exhausted and ship.owner == 1,
		"Arquitens resources the defeated non-leader under the attacker's control")

	var hunter_match := blank_match()
	var boba: CardInst = hunter_match.players[0].leader
	boba.data = lib.get_card("LAW_007")
	var troop := add_unit(hunter_match, 0, "SOR_095")
	var trooper := add_unit(hunter_match, 1, "SOR_128")
	check(hunter_match.do_action({"a": "attack", "uid": troop.uid, "target": trooper.uid})
		and hunter_match.pending.is_empty() and hunter_match.players[0].credits == 0, "Boba Fett ignores attackers without the Bounty Hunter trait")
	hunter_match.active = 0
	var hunter := add_unit(hunter_match, 0, "SOR_182")
	var victim := add_unit(hunter_match, 1, "SOR_128")
	check(hunter_match.do_action({"a": "attack", "uid": hunter.uid, "target": victim.uid}) and hunter_match.pending.get("kind") == "yesno"
		and hunter_match.submit_choice([1]) and hunter_match.players[0].credits == 1 and boba.exhausted,
		"Boba Fett can exhaust to create a Credit after a friendly Bounty Hunter defeats a defender")


func test_support_and_recovery() -> void:
	var m := blank_match()
	var attacker := add_unit(m, 0, "SOR_095")
	var defender := add_unit(m, 1, "SOR_095")
	defender.damage = 2
	var supporter := add_unit(m, 0, "ASH_121", false)
	var base_damage: int = m.players[1].base.damage
	m._on_unit_enters(supporter, "when_played")
	m.pump()
	check(attacker.uid in m.pending.get("options", []) and not supporter.uid in m.pending.get("options", []), "Support offers another ready unit")
	m.submit_choice([attacker.uid])
	check(defender.uid in m.pending.get("options", []), "Support asks for legal attack target")
	m.submit_choice([defender.uid])
	check(m.players[1].base.damage == base_damage + 2, "Support grants Overwhelm for combat")
	check(attacker.exhausted and not attacker.has_kw("overwhelm"), "Support exhausts attacker and expires borrowed keyword")
	var m2 := blank_match()
	add_unit(m2, 1, "ASH_068")
	add_unit(m2, 0, "SOR_095")
	var blocked := add_unit(m2, 0, "ASH_121", false)
	m2._on_unit_enters(blocked, "when_played")
	m2.pump()
	check(m2.pending.is_empty() and not blocked.has_kw("support"), "Loth-Cat suppresses enemy Support")
	var returned := m2._new_inst("SOR_095", 0)
	returned.zone = "discard"
	m2.players[0].discard.append(returned)
	m2.push_frame([{"op": "recover", "kind": "unit"}], {"ctl": 0})
	m2.pump()
	check(returned.uid in m2.pending.get("options", []), "recover chooses unit from discard")
	m2.submit_choice([returned.uid])
	check(returned in m2.players[0].hand and not returned in m2.players[0].discard, "recover moves card into hand")
	var event := m2._new_inst("SOR_125", 0)
	event.zone = "discard"
	m2.players[0].discard.append(event)
	m2.push_frame([{"op": "resource_self"}], {"ctl": 0, "src": event.uid})
	m2.pump()
	check(event.zone == "resource" and event.exhausted, "event becomes an exhausted resource")
	m2.push_frame([{"op": "opponent_defeat"}], {"ctl": 0})
	m2.pump()
	check(m2.pending.get("player") == 1, "opponent chooses own unit for defeat")
	var victim: int = m2.pending["options"][0]
	m2.submit_choice([victim])
	check(m2.card(victim).zone == "discard", "opponent's chosen unit defeated")
	var m3 := blank_match()
	var marine := add_unit(m3, 0, "SOR_095")
	var messenger := add_unit(m3, 0, "ASH_189", false)
	for resource in m3.players[0].resources:
		resource.exhausted = true
	m3._on_unit_enters(messenger, "when_played")
	m3.pump()
	m3.submit_choice([marine.uid])
	m3.submit_choice([m3.players[1].base.uid])
	check(m3.players[0].ready_resources() == 1, "Support grants and resolves On Attack ability")
	check(marine.abilities_with("on_attack").is_empty(), "Support's borrowed ability expires")

func test_pilot_catalog() -> void:
	var tested := 0
	for id in lib.cards:
		var data := lib.get_card(id)
		if not data.has("pilot"):
			continue
		var m := funded_match()
		var host := add_unit(m, 0, "SOR_237")
		var enemy := add_unit(m, 1, "SOR_237")
		var pilot := put_in_hand(m, id)
		var action := "pilot"
		if pilot.is_leader():
			m.players[0].hand.erase(pilot)
			pilot.zone = "leader"
			m.players[0].leader = pilot
			action = "deploy_pilot"
		var before: int = m.players[0].available()
		var rejected := not m.do_action({"a": action, "uid": pilot.uid, "target": enemy.uid})
		check(rejected and before == m.players[0].available() and host.upgrades.is_empty(),
			"%s rejects an enemy Vehicle before paying" % id)
		check(m.do_action({"a": action, "uid": pilot.uid, "target": host.uid}) and pilot.attached_to == host
			and pilot.printed_power() == data["pilot"]["power"] and pilot.printed_hp() == data["pilot"]["hp"],
			"%s attaches directly with its upgrade stats" % id)
		_resolve_catalog_prompts(m)
		if pilot.is_leader():
			check(host.is_leader_unit() == data["pilot"]["makes_leader"], "%s leader-unit status" % id)
			m.defeat(host)
			m.pump()
			check(pilot.zone == "leader" and not pilot.deployed and pilot.exhausted
				and pilot.epic_used != data["pilot"].has("flip_cost"), "%s returns to leader zone on host defeat" % id)
		else:
			var unit_match := funded_match()
			var in_hand := put_in_hand(unit_match, id)
			check(unit_match.do_action({"a": "play", "uid": in_hand.uid}) and in_hand.in_play(),
				"%s can still be played as a unit" % id)
			_resolve_catalog_prompts(unit_match)
		check(data["implemented"] == "full", "%s has no uncompiled Pilot text" % id)
		tested += 1
	check(tested == 49, "All 38 hand Pilots and 11 Pilot leaders are covered")

	var poe_match := funded_match()
	var poe := poe_match._new_inst("JTL_013", 0)
	poe_match.players[0].leader = poe
	poe.zone = "leader"
	var first := add_unit(poe_match, 0, "SOR_237")
	var second := add_unit(poe_match, 0, "SOR_237")
	check(poe_match.do_action({"a": "deploy_pilot", "uid": poe.uid, "target": first.uid})
		and not poe.epic_used and not first.is_leader_unit(), "Poe flips without deploying or spending his Epic Action")
	poe_match.active = 0
	var action := {"a": "ability", "uid": poe.uid, "idx": 0}
	check(poe_match.do_action(action) and poe_match.pending.get("options") == [second.uid]
		and poe_match.submit_choice([second.uid]) and poe.attached_to == second, "Poe transfers without replaying")
	poe_match.active = 0
	check(action not in poe_match.legal_actions(0), "Poe can transfer only once per round")


func _resolve_catalog_prompts(m: Match) -> void:
	for i in 30:
		if m.pending.is_empty():
			return
		var history_size := m.history.size()
		AiBot.choose(m)
		if m.history.size() == history_size:
			check(false, "Catalog prompt rejected: %s" % [m.pending])
			return
	check(false, "Catalog prompt failed to finish")


func _install_base(m: Match, id: String) -> CardInst:
	var base := m._new_inst(id, 0)
	base.zone = "base"
	m.players[0].base = base
	return base


func test_special_bases() -> void:
	var minimum := DeckBuilder.validate(lib, RuleSet.premier(), "JTL_012", "JTL_024", [])
	check("minimum is 60" in minimum[0], "Data Vault raises the required deck size")
	minimum = DeckBuilder.validate(lib, RuleSet.premier(), "JTL_012", "JTL_025", [])
	check("minimum is 45" in minimum[0], "Thermal Oscillator lowers the required deck size")
	var m := funded_match()
	var base := _install_base(m, "JTL_028")
	var hand := [put_in_hand(m, "SOR_095"), put_in_hand(m, "SOR_237"), put_in_hand(m, "SOR_083")]
	m.push_ability(base, base.abilities_with("action_start")[0])
	m.pump()
	var order: Array = [hand[2].uid, hand[0].uid, hand[1].uid]
	check(m.submit_choice(order) and m.players[0].deck.slice(-3) == [hand[2], hand[0], hand[1]], "Nabat keeps the player's chosen bottom order")
	base = _install_base(m, "LOF_025")
	var attacker := add_unit(m, 0, "SOR_095")
	check(m.do_action({"a": "attack", "uid": attacker.uid, "target": m.players[1].base.uid})
		and m.players[0].force_token, "Temple of Destruction grants Force after three combat damage")
	m = funded_match()
	base = _install_base(m, "LAW_029")
	var resource: CardInst = m.players[0].resources[0]
	var top: CardInst = m.players[0].deck[0]
	check(m.do_action({"a": "ability", "uid": base.uid, "idx": 0}) and m.submit_choice([resource.uid])
		and resource.zone == "hand" and resource not in m.players[0].resources and top.zone == "resource" and top.exhausted, "Citadel returns the selected resource and replaces it exhausted")
	m = funded_match()
	base = _install_base(m, "LAW_026")
	var milled: CardInst = m.players[0].deck[1]
	check(m.do_action({"a": "ability", "uid": base.uid, "idx": 0}) and milled.zone == "discard"
		and m.submit_choice([milled.uid]) and m.players[0].deck[0] == milled, "Shipbreaking Yard returns only a card from its own mill")
	m = funded_match()
	base = _install_base(m, "LAW_019")
	m.players[0].credits = 1
	check(m.do_action({"a": "ability", "uid": base.uid, "idx": 0}) and m.submit_choice([0])
		and m.players[0].credits == 0 and m.submit_choice([2]) and m.players[0].credits == 1,
		"Alliance Outpost can defeat a Credit and choose to create a new one")


func test_pilot_replacements() -> void:
	var m := funded_match()
	var host := add_unit(m, 0, "SOR_237")
	var droid := add_unit(m, 0, "JTL_049")
	m.attach_token(droid, "experience")
	m.deal_damage(droid, droid.max_hp(), null)
	m.pump()
	check(host.uid in m.pending.get("options", []) and m.submit_choice([host.uid])
		and droid.attached_to == host and droid.damage == 0 and droid.upgrades.is_empty(),
		"L3-37 can replace defeat by becoming a Pilot")
	m = funded_match()
	host = add_unit(m, 0, "SOR_237")
	var luke := put_in_hand(m, "JTL_094")
	check(m.do_action({"a": "pilot", "uid": luke.uid, "target": host.uid}), "A Wing Commander attaches to a Vehicle")
	m.defeat(host)
	m.pump()
	check(m.submit_choice([1]) and luke.zone == "ground" and luke.exhausted and luke.attached_to == null
		and luke not in m.players[0].discard, "Luke can survive host defeat by moving to ground")
	m = funded_match()
	var ship := add_unit(m, 0, "SOR_237")
	var poe := put_in_hand(m, "JTL_100")
	check(m.do_action({"a": "play", "uid": poe.uid}) and m.pending.get("min") == 0
		and ship.uid in m.pending.get("options", []) and m.pending.get("options", []).size() == 2,
		"Poe's unit play offers both the new X-Wing and a preexisting Vehicle")
	check(m.submit_choice([]) and poe.in_play(), "Poe may decline to become an upgrade")


func test_base_and_fortify_catalog() -> void:
	var base_count := 0
	var fort_count := 0
	for id in lib.cards:
		var data := lib.get_card(id)
		if data.get("custom", false):
			continue
		if data.get("type") == "base":
			base_count += 1
			check(data.get("implemented") == "full" and data.get("unparsed", []).is_empty(), "%s has no uncompiled base text" % id)
		if not data.get("keywords", []).any(func(kw): return kw["k"] == "fortify"):
			continue
		fort_count += 1
		var m := funded_match()
		var upgrade := put_in_hand(m, id)
		var home: CardInst = m.players[0].base
		var hostile: CardInst = m.players[1].base
		var before: int = m.players[0].available()
		check(not m.do_action({"a": "play", "uid": upgrade.uid, "target": hostile.uid})
			and m.players[0].available() == before and upgrade.zone == "hand", "%s rejects an enemy base without spending" % id)
		check(m.do_action({"a": "play", "uid": upgrade.uid, "target": home.uid}) and upgrade.attached_to == home
			and upgrade in home.upgrades and data.get("implemented") == "full", "%s attaches directly to its own base" % id)
		_resolve_catalog_prompts(m)
	check(base_count == 107 and fort_count == 15, "All 107 printed bases and 15 Fortifications are included")
