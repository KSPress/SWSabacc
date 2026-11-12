extends "res://tests/run_tests.gd"


func _init() -> void:
	lib.load_file("res://ip/data/cards.json")
	lib.load_file("res://data/custom_cards.json", true)
	test_upgrade_targets()
	test_continuous_rules()
	test_capture_and_bounty()
	test_plot_and_fortify()
	test_fortifications()
	test_reported_card_abilities()
	test_early_combat_and_tokens()
	test_support_and_recovery()
	test_coordinate_triggers()
	test_card_play_triggers()
	test_defeat_and_deploy_triggers()
	test_base_epic_actions()
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
	test_indirect_damage()
	test_multi_mode_events()
	test_play_discounts()
	test_advantage_and_weakness()
	test_ability_usage_limits()
	test_damage_and_heal_triggers()
	test_jabba_action_play_requirements()
	test_rebel_attack_sequences()
	test_upgrade_defeat_and_ready_aura()
	test_unit_control_changes()
	test_upgrade_search_filters()
	print("EXTENDED RULES: %d passed, %d failed" % [passes, failures])
	quit(1 if failures else 0)


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
	check(m.submit_choice([tusken.uid]) and tusken.zone == "discard", "Krayt Call defeats the selected Tusken")
	check(m.pending.is_empty() and m.active == 1 and m.players[0].out_of_round, "Enemy takes its turn after Krayt Call")
	var round_before := m.round_num
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
