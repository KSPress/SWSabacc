extends SceneTree
## Card-by-card engine audit. Every leader, base, unit, event and upgrade is put
## through the real rules engine on a staged board:
##   unit/event/upgrade : played from hand (cost paid), every choice answered by
##                        the bot, then (units) readied + attacks, uses its
##                        action abilities, and is defeated (When Defeated)
##   leader             : every action ability used, Epic Action deploy, attack
##   base               : a short bot-vs-bot game on that base
## For each card it records: script errors (attributed via "AUDIT <id>" markers
## in the log), stalls (choices that never resolve), illegal states, and for
## automated abilities whether the game state actually changed ("no-op").
## godot --headless --path game --script res://tests/card_audit.gd -- <out.json> [id-filter] [dense|duel|pressured]

var lib := CardLibrary.new()
var results: Dictionary = {}
var filler := "SOR_095"   # Battlefield Marine
var scenario := "dense"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://card_audit.json"
	var filters := Array(args[1].split(",", false)) if args.size() > 1 else []
	scenario = args[2] if args.size() > 2 else "dense"
	if scenario not in ["dense", "duel", "pressured"]:
		push_error("Unknown audit scenario: " + scenario)
		quit(2)
		return
	lib.load_file("res://ip/data/cards.json")
	lib.load_file("res://data/custom_cards.json", true)
	var ids: Array = lib.cards.keys()
	ids.sort()
	var n := 0
	for id in ids:
		if not filters.is_empty() and not filters.any(func(prefix): return str(id).begins_with(prefix)):
			continue
		var c: Dictionary = lib.cards[id]
		var t: String = c.get("type", "")
		print("AUDIT ", id)
		var r: Dictionary
		match t:
			"leader":
				r = audit_leader(id)
			"base":
				r = audit_base(id)
			"token_unit", "token_upgrade", "force_token", "credit_token":
				r = audit_token(id, t)
			_:
				r = audit_card(id)
		if c.has("pilot"):
			var pilot := audit_pilot(id, t == "leader")
			r["steps"].append_array(pilot["steps"])
			r["issues"].append_array(pilot["issues"])
			r["optional_declined"] = r.get("optional_declined", 0) + pilot.get("optional_declined", 0)
		r["type"] = t
		r["implemented"] = c.get("implemented", "")
		r["scenario"] = scenario
		results[id] = r
		n += 1
	print("AUDIT_END ", n)
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write card audit to " + out)
		quit(2)
		return
	f.store_string(JSON.stringify(results))
	quit()


func new_match(leader := "SEC_015", base := "HMW_019", seed_v := 1) -> Match:
	var m := Match.new()
	var deck: Array = []
	var pool := [filler, "SOR_237", "ASH_121", "SOR_070", "HMW_128", "SOR_172"]
	for i in 30:
		deck.append(pool[i % pool.size()])
	var rules := RuleSet.premier()
	rules.aspect_penalties = false
	m.setup(lib, {"seed": seed_v + ["dense", "duel", "pressured"].find(scenario) * 997, "rules": rules, "first": 0, "players": [
		{"leader": leader, "base": base, "deck": deck, "ai": true},
		{"leader": "SOR_017", "base": "HMW_028", "deck": deck.duplicate(), "ai": true}]})
	resolve(m)
	return m


## Answer every pending choice with the bot. Returns false if it never settles.
func resolve(m: Match, cap := 60, result := {}) -> bool:
	for i in cap:
		if m.pending.is_empty():
			return true
		if scenario == "duel" and m.pending["kind"] == "yesno":
			result["optional_declined"] = int(result.get("optional_declined", 0)) + 1
			m.submit_choice([0])
		elif scenario == "duel" and m.pending.get("min", 1) == 0:
			if not m.pending.get("options", []).is_empty():
				result["optional_declined"] = int(result.get("optional_declined", 0)) + 1
			m.submit_choice([])
		else:
			AiBot.choose(m)
	return m.pending.is_empty()


func stage(m: Match) -> void:
	# a board with something to hit and something to help, plenty of resources
	for p in 2:
		var ps: PlayerState = m.players[p]
		while ps.resources.size() < 16 and not ps.deck.is_empty():
			m.move_to_resources(p, ps.deck.pop_front())
		for r in ps.resources:
			r.exhausted = false
		# trooper, fighter, creature, droid, 3 officials, underworld transport,
		# force unit, 1-HP fighter, a 7-power beast
		var field := ["SOR_095", "SOR_237", "ASH_121", "ASH_252", "ASH_076", "ASH_076", "ASH_076", "ASH_173", "HMW_128", "ASH_141", "ASH_131"]
		if scenario == "duel":
			field = ["SOR_095", "SOR_237"]
		elif scenario == "pressured" and p == 0:
			field = ["SOR_237", "HMW_128", "ASH_121", "ASH_173"]
		for id in field:
			var u := m._new_inst(id, p)
			m._put_in_play(u, u.arena(), false)
		if scenario == "duel":
			continue
		var hurt := m._new_inst("SOR_046", p)   # damaged + shielded + exhausted
		m._put_in_play(hurt, hurt.arena(), true)
		hurt.damage = 2
		m.attach_token(hurt, "shield")
		var tok := m.create_unit_token(p, "battle_droid")
		if tok:
			tok.exhausted = false
		for u in ps.units:
			if u.id in ["SOR_237", "HMW_128"]:
				u.exhausted = true      # something to ready
			if u.id == "ASH_121":
				u.damage = 1            # a damaged unit that can still attack
		ps.base.damage = ps.base.max_hp() - 8 if scenario == "pressured" and p == 0 else 5
		ps.credits = 2
	# a varied hand for "play a ___ from your hand" effects
	for id in ["SOR_172", "HMW_128", "HMW_140", "HMW_106", "ASH_069", "ASH_121", "SOR_073", "LOF_215", "SOR_095", "SOR_237", "TWI_151"]:
		var hc := m._new_inst(id, 0)
		hc.zone = "hand"
		m.players[0].hand.append(hc)
	m.players[0].force_token = true
	m.defeated_cards_this_phase[0].append(m._new_inst("SOR_095", 0))
	m.take_events()


func snapshot(m: Match, played: CardInst = null, play_cost := -1) -> String:
	var parts: Array = []
	for ps in m.players:
		var ready := 0
		for r in ps.resources:
			if not r.exhausted:
				ready += 1
		var hand: int = ps.hand.size()
		var discard: int = ps.discard.size()
		var ready_payment := 0
		var credit_payment := 0
		if played and played.owner == ps.index:
			if played in ps.hand:
				hand -= 1
				ready_payment = mini(ready, play_cost)
				credit_payment = play_cost - ready_payment
			if played in ps.discard:
				discard -= 1
		parts.append("B%d H%d D%d X%d R%d/%d F%s C%d" % [ps.base.damage, hand, ps.deck.size(), discard, ready - ready_payment, ps.resources.size(), ps.force_token, ps.credits - credit_payment])
		var us: Array = []
		for u in ps.units + [ps.base]:
			var attached: Array = []
			for upgrade in u.upgrades:
				if upgrade != played:
					attached.append(upgrade.uid)
			# Ignore entering the arena and attaching the played card itself. Track
			# extra attachments, damage and modifiers even on a just-played unit.
			if u == played and attached.is_empty() and u.damage == 0 and u.mods.is_empty():
				continue
			us.append("%s:%d:%s:%s:%s:%s" % [u.uid, u.damage, u.exhausted, str(attached), str(u.mods), str(u.flags)])
		us.sort()
		parts.append(",".join(us))
		parts.append(str(ps.next_play_discounts))
	return "|".join(parts)


func sane(m: Match) -> String:
	var attached := {}
	var seen := {}
	for ps in m.players:
		var zones := {"board": ps.units, "hand": ps.hand, "deck": ps.deck, "discard": ps.discard, "resource": ps.resources}
		for zone in zones:
			for card in zones[zone]:
				if seen.has(card.uid):
					return "%s appears in more than one zone list" % card.id
				seen[card.uid] = true
				if (zone == "board" and not card.in_play()) or (zone != "board" and card.zone != zone):
					return "%s listed in %s but zone=%s" % [card.id, zone, card.zone]
				if card.damage < 0:
					return "negative damage"
		for host in ps.units + [ps.base]:
			for upgrade in host.upgrades:
				if upgrade.zone != "upgrade" or upgrade.attached_to != host or seen.has(upgrade.uid) or attached.has(upgrade.uid):
					return "%s has inconsistent attachment state" % upgrade.id
				attached[upgrade.uid] = true
	for card in m.by_uid.values():
		if card.zone == "upgrade" and not attached.has(card.uid):
			return "%s is in the upgrade zone without a host" % card.id
	if not m.frames.is_empty() and m.pending.is_empty() and not m.is_over():
		return "frames left unresolved"
	return ""


func has_trigger(c: Dictionary, trig: Array) -> bool:
	for a in c.get("abilities", []):
		if a.get("trigger", "") in trig and not a.get("effects", []).is_empty():
			return true
	return false


func audit_pilot(id: String, leader: bool) -> Dictionary:
	var result := {"steps": [], "issues": []}
	var m := new_match(id) if leader else new_match()
	stage(m)
	var pilot: CardInst = m.players[0].leader if leader else give_card(m, id)
	var action := {"a": "deploy_pilot" if leader else "pilot", "uid": pilot.uid}
	var hosts := Effects.upgrade_targets(m, 0, pilot, true)
	if action not in m.legal_actions(0) or hosts.is_empty():
		result["issues"].append("Pilot action unavailable")
		return result
	# The duel deliberately declines optional prompts elsewhere. Here the
	# harness chooses a known legal host so it exercises piloting in all cases.
	action["target"] = hosts[0].uid
	if not m.do_action(action) or not resolve(m, 60, result):
		result["issues"].append("Pilot action unavailable or unresolved")
		return result
	if pilot.zone != "upgrade" or pilot.attached_to == null:
		result["issues"].append("Pilot failed to attach")
		return result
	result["steps"].append("piloted")
	if not audit_actions(m, pilot, result, "Pilot"):
		return result
	m.defeat(pilot)
	m.pump()
	if not resolve(m, 60, result):
		result["issues"].append("stuck after Pilot defeat")
	elif leader and pilot.zone != "leader":
		result["issues"].append("defeated Pilot leader did not return to leader zone")
	elif not leader and pilot.zone != "discard" and not pilot.in_play():
		result["issues"].append("defeated Pilot did not return to discard or enter play")
	return result


func give_card(m: Match, id: String) -> CardInst:
	var card := m._new_inst(id, 0)
	card.zone = "hand"
	m.players[0].hand.append(card)
	return card


func audit_actions(m: Match, card: CardInst, r: Dictionary, label: String) -> bool:
	for index in card.abilities_with("action").size():
		if card.zone not in ["leader", "base", "ground", "space", "upgrade"] or m.is_over():
			break
		var player := card.controller
		card.exhausted = false
		for resource in m.players[player].resources:
			resource.exhausted = false
		m.active = player
		var action := {"a": "ability", "uid": card.uid, "idx": index}
		if action not in m.legal_actions(player):
			r["issues"].append("%s action %d not usable" % [label, index])
			continue
		if not m.do_action(action) or not resolve(m, 60, r):
			r["issues"].append("stuck after %s action %d" % [label, index])
			return false
		r["steps"].append("%s action %d" % [label, index])
	return true


func audit_token(id: String, type: String) -> Dictionary:
	var result := {"steps": [], "issues": []}
	var m := new_match()
	stage(m)
	var token := m._new_inst(id, 0)
	match type:
		"token_unit":
			m._put_in_play(token, token.arena(), false)
			var targets := m.attack_targets(token)
			if not targets.is_empty():
				m.do_action({"a": "attack", "uid": token.uid, "target": targets[0]})
				resolve(m)
				result["steps"].append("attacked")
			m.defeat(token)
			m.pump()
			resolve(m)
			if token.zone != "removed":
				result["issues"].append("defeated token unit remained in play")
		"token_upgrade":
			var host: CardInst = m.players[0].units[0]
			m.attach_upgrade(token, host)
			m.pump()
			resolve(m)
			if token not in host.upgrades:
				result["issues"].append("token upgrade failed to attach")
			m.defeat(token)
			m.pump()
			resolve(m)
			if token.zone != "removed" or token in host.upgrades:
				result["issues"].append("defeated token upgrade remained attached")
		"force_token":
			m.players[0].force_token = false
			m.push_frame([{"op": "force_token"}], {"ctl": 0})
			m.pump()
			if not m.players[0].force_token:
				result["issues"].append("Force token was not acquired")
			m.push_frame([{"op": "use_force"}], {"ctl": 0})
			m.pump()
			if m.players[0].force_token:
				result["issues"].append("Force token was not spent")
		"credit_token":
			var credits: int = m.players[0].credits
			m.push_frame([{"op": "token", "name": "credit"}], {"ctl": 0})
			m.pump()
			if m.players[0].credits != credits + 1:
				result["issues"].append("Credit token was not acquired")
	result["steps"].append("token exercised")
	var problem := sane(m)
	if not problem.is_empty():
		result["issues"].append(problem)
	return result


func audit_card(id: String) -> Dictionary:
	var r := {"steps": [], "issues": []}
	var m := new_match()
	stage(m)
	var ps: PlayerState = m.players[0]
	if id in ["LOF_068", "SEC_072", "SHD_245", "HMW_085"]:
		ps.deck.push_front(m._new_inst("JTL_260", 0))
		ps.deck.push_front(m._new_inst("JTL_058", 0))
	var c := give_card(m, id)
	var data: Dictionary = c.data
	var t := c.card_type()
	# --- play it
	if t == "unit" and not (m.arena_for(c) in m.rules.arenas):
		r["issues"].append("unit arena not in rules")
		return r
	var legal := false
	for a in m.legal_actions(0):
		if a["a"] == "play" and a["uid"] == c.uid:
			legal = true
	if not legal:
		r["issues"].append("play unavailable with %d resources ready, cost %d, %d attachment targets" % [
			ps.available(), m.play_cost(0, c), Effects.upgrade_targets(m, 0, c).size() if t == "upgrade" else 0])
		return r
	# give the Force token unless the card is what grants it (so either use is observable)
	m.players[0].force_token = str(data.get("text", "")).to_lower().find("the force is with you") < 0
	var cost := m.play_cost(0, c)
	var before := snapshot(m, c, cost)
	m.do_action({"a": "play", "uid": c.uid})
	if not resolve(m, 60, r):
		r["issues"].append("stuck after play (pending %s)" % m.pending.get("kind", ""))
		return r
	var after := snapshot(m, c, cost)
	r["steps"].append("played")
	if has_trigger(data, ["when_played", "event"]):
		var changed := before != after or m.events.any(func(e): return e.get("t") in ["draw", "discard", "bounce", "reveal"])
		if not changed and not r.get("optional_declined", 0):
			r["issues"].append("no-op: no observable change beyond playing the card")
	var s := sane(m)
	if s != "":
		r["issues"].append(s)
	if t == "upgrade" and c.zone == "upgrade":
		if not audit_actions(m, c, r, "Upgrade"):
			return r
		if c.zone == "upgrade":
			m.defeat(c)
			m.pump()
			if not resolve(m, 60, r):
				r["issues"].append("stuck after upgrade defeat")
			elif c.zone == "upgrade":
				r["issues"].append("defeated upgrade remained attached")
			else:
				r["steps"].append("upgrade defeated")
		return r
	if t != "unit" or not c.in_play():
		return r
	# --- attack
	c.exhausted = false
	m.active = c.controller
	var tgts := m.attack_targets(c)
	if tgts.is_empty():
		var cannot_attack := c.abilities_with("constant").any(func(a): return a.get("flag") == "cannot_attack")
		if not cannot_attack:
			r["issues"].append("no attack targets on staged board")
	else:
		var b2 := snapshot(m)
		if not m.do_action({"a": "attack", "uid": c.uid, "target": tgts[0]}):
			r["issues"].append("staged attack was rejected")
			return r
		if not resolve(m, 60, r):
			r["issues"].append("stuck after attack (pending %s)" % m.pending.get("kind", ""))
			return r
		r["steps"].append("attacked")
		if snapshot(m) == b2:
			r["issues"].append("attack changed nothing")
	# --- action abilities
	if c.in_play() and not audit_actions(m, c, r, "Unit"):
		return r
	# --- defeat
	if c.in_play():
		m.defeat(c)
		m.pump()
		if not resolve(m, 60, r):
			r["issues"].append("stuck after defeat")
			return r
		r["steps"].append("defeated")
	s = sane(m)
	if s != "":
		r["issues"].append(s)
	return r


func audit_leader(id: String) -> Dictionary:
	var r := {"steps": [], "issues": []}
	var m := new_match(id)
	stage(m)
	var ps: PlayerState = m.players[0]
	var l: CardInst = ps.leader
	ps.force_token = str(l.data.get("text", "")).to_lower().find("the force is with you") < 0
	if not audit_actions(m, l, r, "Leader"):
		return r
	l.exhausted = false
	m.active = 0
	var dep := false
	for a in m.legal_actions(0):
		if a["a"] == "deploy":
			dep = true
	if not dep:
		if int(l.data.get("leader_unit", {}).get("hp", 0)) == 0:
			r["steps"].append("no unit side (flips between leader sides)")
			return r
		r["issues"].append("cannot deploy with 16 resources")
		return r
	m.do_action({"a": "deploy"})
	if not resolve(m, 60, r):
		r["issues"].append("stuck after deploy")
		return r
	r["steps"].append("deployed")
	if not l.in_play():
		r["issues"].append("deployed leader not in play")
		return r
	l.exhausted = false
	m.active = 0
	var tg := m.attack_targets(l)
	if not tg.is_empty():
		var b2 := snapshot(m)
		m.do_action({"a": "attack", "uid": l.uid, "target": tg[0]})
		if not resolve(m, 60, r):
			r["issues"].append("stuck after leader attack")
			return r
		r["steps"].append("attacked")
		if snapshot(m) == b2:
			r["issues"].append("leader attack changed nothing")
	if l.in_play() and not audit_actions(m, l, r, "Deployed leader"):
		return r
	if l.in_play():
		m.defeat(l)
		m.pump()
		resolve(m, 60, r)
	if l.zone != "leader":
		r["issues"].append("defeated leader did not return to leader zone")
	var s := sane(m)
	if s != "":
		r["issues"].append(s)
	return r


func audit_base(id: String) -> Dictionary:
	var r := {"steps": [], "issues": []}
	var staged := new_match("SEC_015", id)
	stage(staged)
	audit_actions(staged, staged.players[0].base, r, "Base")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id + scenario)
	var m := Match.new()
	var deck := DeckBuilder.auto_deck(lib, "SEC_015", id, 30, rng)
	m.setup(lib, {"seed": hash(id + scenario), "first": 1 if scenario == "pressured" else 0,
		"rules": RuleSet.quick_mode("traditional"), "players": [
		{"leader": "SEC_015", "base": id, "deck": deck, "ai": true},
		{"leader": "SOR_017", "base": "HMW_028", "deck": deck.duplicate(), "ai": true}]})
	var steps := 0
	while not m.is_over() and steps < 3000:
		steps += 1
		if not m.pending.is_empty():
			AiBot.choose(m)
		elif m.phase == "action":
			AiBot.act(m)
		else:
			break
	if not m.is_over():
		r["issues"].append("bot game did not finish")
	r["steps"].append("game %d rounds" % m.round_num)
	return r
