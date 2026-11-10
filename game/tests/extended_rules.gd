extends "res://tests/run_tests.gd"


func _init() -> void:
	lib.load_file("res://ip/data/cards.json")
	lib.load_file("res://data/custom_cards.json", true)
	test_upgrade_targets()
	test_continuous_rules()
	test_capture_and_bounty()
	test_plot_and_fortify()
	test_early_combat_and_tokens()
	print("EXTENDED RULES: %d passed, %d failed" % [passes, failures])
	quit(1 if failures else 0)


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
