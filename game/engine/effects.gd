class_name Effects
extends RefCounted
## Interpreter for the effect DSL produced by tools/import_cards.py.
##
## An effect is a Dictionary: {"op": "damage", "n": 3, "t": <selector>, "optional": bool,
## "if": <condition>, "if_did": bool}. Ops prefixed "_" are engine-internal steps
## (setup, regroup, combat...). exec() returns DONE or SUSPEND; on SUSPEND,
## Match.pending describes the choice and the same effect re-runs once
## Match.submit_choice() stores the answer in ctx["_choice"].

const DONE := 0
const SUSPEND := 1
const HOSTILE_OPS := ["damage", "damage_from_it", "defeat", "exhaust", "bounce", "lose_kw", "opponent_defeat", "take_control"]


static func exec(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var result := _exec(m, e, ctx)
	if result == DONE:
		ctx.erase("_optional_accepted")
	return result


static func _exec(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var op: String = e.get("op", "")
	if e.get("if_did", false) and not ctx.get("did", false):
		return DONE
	if e.has("if") and not ctx.has("_choice") and not condition(m, e["if"], ctx):
		ctx["did"] = false
		return DONE
	if op.begins_with("_"):
		return _system(m, e, ctx)
	if op == "choose_one":
		return _choose_one(m, e, ctx)
	if op == "play_from_hand":
		return _play_from_hand(m, e, ctx)
	if op == "capture":
		return _capture(m, e, ctx)
	if op == "split_unit_damage":
		return _split_unit_damage(m, e, ctx)
	if op == "heal_up_to":
		return _heal_up_to(m, e, ctx)
	if op == "use_force" and not m.players[ctx.get("ctl", 0)].force_token:
		ctx["did"] = false
		return DONE
	if op == "pay_resources" and m.players[ctx.get("ctl", 0)].available() < int(e["n"]):
		ctx["did"] = false
		return DONE
	# Optional effect with no target to pick => ask yes/no first.
	var chooses_target: bool = e.has("t") and e["t"].get("s", "choose") == "choose"
	if op == "attack_with" and not chooses_target and not ctx.has("_attacker"):
		var attackers: Array = _targets(m, e, ctx)
		if attackers.is_empty() or attackers[0].controller != ctx["ctl"] or m.attack_targets(attackers[0]).is_empty():
			ctx["did"] = false
			return DONE
	if e.get("optional", false) and op != "recover" and not e.has("chooser") and not chooses_target and not ctx.get("_optional_accepted", false):
		if op == "exhaust":
			var source := m.card(ctx.get("src", 0))
			if source == null or source.exhausted:
				ctx["did"] = false
				return DONE
		if not ctx.has("_choice"):
			_ask(m, ctx, "yesno", "Use: %s?" % _label(ctx, e), [1, 0], 1, 1, e)
			return SUSPEND
		var yes: bool = ctx["_choice"][0] == 1
		ctx.erase("_choice")
		if not yes:
			ctx["did"] = false
			return DONE
		ctx["_optional_accepted"] = true
	var targets: Array = []
	if e.has("t") and not ctx.has("_attacker"):
		var r = _targets(m, e, ctx)
		if r == null:
			return SUSPEND
		targets = r
		if targets.is_empty() and op not in ["token", "draw"]:
			ctx["did"] = false
			return DONE
	var ctl: int = ctx.get("ctl", 0)
	var src: CardInst = m.card(ctx.get("src", 0))
	var n: int = int(ctx.get("trigger_amount", 0)) if e.get("use_trigger_amount", false) else int(e.get("n", 1))
	match op:
		"damage":
			if not targets.is_empty():
				ctx["it_arena"] = targets[0].arena()
			for t in targets:
				m.deal_damage(t, n, src)
		"select":
			pass
		"damage_from_it":
			var dealer := m.card(ctx.get("it", 0))
			if dealer and dealer.in_play():
				for t in targets:
					m.deal_damage(t, dealer.power(), dealer)
		"heal":
			for t in targets:
				m.heal(t, n)
		"draw":
			m.draw(m.opp(ctl) if e.get("who") == "opponent" else ctl, n)
			if e.get("who") == "all":
				m.draw(m.opp(ctl), n)
		"pay_resources":
			m.pay(ctl, n)
		"discount_next":
			m.players[ctl].next_play_discounts.append({"phase": m.phase_serial,
				"filter": e["filter"], "n": n, "uses": e.get("uses", 1)})
		"indirect_damage":
			return _indirect_damage(m, e, ctx)
		"mill":
			var player := m.opp(ctl) if e.get("who") == "opponent" else ctl
			var deck: Array = m.players[player].deck
			ctx["did"] = not deck.is_empty()
			for i in mini(n, deck.size()):
				var discarded: CardInst = deck.pop_front()
				discarded.zone = "discard"
				m.players[player].discard.append(discarded)
				m.events.append({"t": "discard", "uid": discarded.uid, "p": player})
			return DONE
		"recover", "reveal_hand", "opponent_defeat":
			return _zone_choice(m, e, ctx)
		"resource_self":
			ctx["did"] = src != null and src.zone == "discard"
			if src and src.zone == "discard":
				m.move_to_resources(ctl, src, not e.get("ready", false))
			return DONE
		"resource_top":
			var deck: Array = m.players[ctl].deck
			ctx["did"] = not deck.is_empty()
			if not deck.is_empty():
				m.move_to_resources(ctl, deck[0], not e.get("ready", false))
			return DONE
		"discard":
			return _discard(m, e, ctx)
		"shield", "experience", "advantage", "weakness":
			for t in targets:
				for _i in n:
					m.attach_token(t, op)
		"exhaust":
			ctx["did"] = false
			for t in targets:
				if not t.exhausted:
					m.exhaust(t, true)
					ctx["did"] = true
			if not targets.is_empty():
				ctx["it"] = targets[0].uid
			return DONE
		"ready":
			for t in targets:
				m.exhaust(t, false)
		"defeat":
			for t in targets:
				if not _enemy_effect_immune(t, ctl, op):
					m.defeat(t)
		"bounce":
			for t in targets:
				if not _enemy_effect_immune(t, ctl, op):
					m.return_to_hand(t)
		"linked_bonus":
			for t in targets:
				t.mods.append({"p": e["p"], "kw": e["kw"], "while_source": src.uid, "source_entry": src.entry_serial})
		"skip_regroup_ready":
			for t in targets:
				t.flags["skip_regroup_ready"] = true
		"reveal_top":
			var deck: Array = m.players[ctl].deck
			if not deck.is_empty():
				ctx["revealed"] = deck[0].uid
				m.events.append({"t": "reveal_top", "uid": deck[0].uid})
		"take_control":
			var target: CardInst = targets[0]
			var controller := m.opp(ctl) if e.get("who") == "opponent" else ctl
			ctx["it"] = target.uid
			ctx["did"] = m.take_control(target, controller)
			if target.controller == controller:
				if e.get("regroup_return", false):
					target.flags["return_control_at_regroup"] = true
				if e.get("ready", false):
					m.exhaust(target, false)
			return DONE
		"buff":
			for t in targets:
				t.mods.append({"p": int(e.get("p", 0)), "h": int(e.get("h", 0)), "dur": e.get("dur", "phase")})
				m.events.append({"t": "buff", "uid": t.uid, "p": int(e.get("p", 0)), "h": int(e.get("h", 0))})
		"gain_kw":
			for t in targets:
				t.mods.append({"kw": e["kw"], "v": int(e.get("v", 1)), "dur": e.get("dur", "phase")})
				m.events.append({"t": "buff", "uid": t.uid, "kw": e["kw"]})
		"blank_abilities":
			for t in targets:
				t.mods.append({"blank_abilities": true, "dur": "round"})
		"extra_action":
			m._extra_action = true
		"lose_kw":
			for t in targets:
				t.mods.append({"lose_kw": e["kw"], "dur": e.get("dur", "phase")})
		"token":
			if e.get("name", "") == "credit":
				m.players[ctl].credits += n
				m.events.append({"t": "credits", "p": ctl, "n": n})
			else:
				ctx.erase("it")
				ctx["did"] = false
				for _i in n:
					var created := m.create_unit_token(ctl, e.get("name", "battle_droid"))
					if created:
						ctx["it"] = created.uid
						ctx["did"] = true
				return DONE
		"summon":
			for _i in n:
				m.summon(ctl, e["id"], e.get("ready", false))
		"force_token":
			if not m.players[ctl].force_token:
				m.players[ctl].force_token = true
				m.events.append({"t": "force", "p": ctl})
		"use_force":
			if not m.players[ctl].force_token:
				ctx["did"] = false
				return DONE
			m.players[ctl].force_token = false
			m.events.append({"t": "force_used", "p": ctl})
			m.player_trigger(ctl, "force_used")
		"ready_resource":
			var left := n
			if e.get("amount") == "odd_permanent":
				left = m.trigger_sources().filter(func(c):
					return c.controller == ctl and (c.in_play() or c.zone == "upgrade") and c.cost() % 2 == 1).size()
			for r in m.players[ctl].resources:
				if left > 0 and r.exhausted:
					r.exhausted = false
					left -= 1
		"scry":
			return _scry(m, e, ctx)
		"search":
			return _search(m, e, ctx)
		"attack_with", "support":
			return _attack_with(m, e, ctx, targets)
		"base_damage":
			m.deal_damage(m.players[m.opp(ctl)].base, n, src)
		_:
			push_warning("Effects: unknown op %s" % op)
	ctx["did"] = true
	if not targets.is_empty():
		ctx["it"] = targets[0].uid
	return DONE


# ---------------------------------------------------------------- targeting

static func _zone_choice(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var ctl: int = ctx.get("ctl", 0)
	var op: String = e["op"]
	if ctx.has("_choice"):
		var selection: Array = ctx["_choice"]
		ctx.erase("_choice")
		for uid in selection:
			var card := m.card(uid)
			if card == null:
				continue
			if op == "recover" and card.zone == "discard":
				m._remove_from_zones(card)
				card.zone = e.get("destination", "hand")
				if card.zone == "deck":
					m.players[ctl].deck.push_front(card)
				else:
					m.players[ctl].hand.append(card)
			elif op == "opponent_defeat" and card.in_play():
				m.defeat(card)
		ctx["did"] = not selection.is_empty() or op == "reveal_hand"
		return DONE
	var pool: Array = m.players[ctl].discard if op == "recover" else (m.players[m.opp(ctl)].units if op == "opponent_defeat" else m.players[m.opp(ctl)].hand)
	var options: Array = []
	for card in pool:
		if op == "recover":
			if e.get("kind", "card") != "card" and card.card_type() != e["kind"]:
				continue
			if e.get("trait", "") != "" and not card.has_trait(e["trait"]):
				continue
			if e.has("not_trait") and card.has_trait(e["not_trait"]):
				continue
		options.append(card.uid)
	if options.is_empty():
		ctx["did"] = false
		return DONE
	var chooser: int = m.opp(ctl) if op == "opponent_defeat" else ctl
	var saved_ctl: int = ctx.get("ctl", 0)
	ctx["ctl"] = chooser
	var prompt := "Opponent's hand · Continue" if op == "reveal_hand" else ("Choose a unit to defeat" if op == "opponent_defeat" else "Recover a card from your discard pile")
	_ask(m, ctx, "search" if op != "opponent_defeat" else "target", prompt, options, 0 if op == "reveal_hand" or e.get("optional", false) else 1, 0 if op == "reveal_hand" else 1, e)
	ctx["ctl"] = saved_ctl
	if op == "reveal_hand":
		m.pending["reveal"] = options
	return SUSPEND


static func _heal_up_to(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	if ctx.has("_heal_target"):
		var target := m.card(ctx["_heal_target"])
		m.heal(target, ctx["_choice"][0])
		ctx.erase("_heal_target")
		ctx.erase("_choice")
		return DONE
	var targets = _targets(m, e, ctx)
	if targets == null:
		return SUSPEND
	if targets.is_empty() or targets[0].damage == 0:
		return DONE
	var target: CardInst = targets[0]
	ctx["_heal_target"] = target.uid
	var amounts := range(mini(target.damage, int(e["n"])), -1, -1)
	_ask(m, ctx, "option", "Choose how much damage to heal", amounts, 1, 1, e)
	m.pending["labels"] = amounts.map(func(amount): return "Heal %d" % amount)
	return SUSPEND

## Returns Array[CardInst], or null when the controller must choose (pending set).
static func _targets(m: Match, e: Dictionary, ctx: Dictionary):
	var t: Dictionary = e["t"]
	var s: String = t.get("s", "choose")
	var ctl: int = ctx.get("ctl", 0)
	var src: CardInst = m.card(ctx.get("src", 0))
	match s:
		"self":
			return [src] if src and (src.in_play() or src.zone in ["leader", "upgrade", "base"]) else []
		"it":
			var it := m.card(ctx.get("it", 0))
			return [it] if it and (it.in_play() or it.zone == "base") else []
		"subject":
			var subject := m.card(ctx.get("subject", 0))
			return [subject] if subject and subject.in_play() else []
		"subject_base":
			var subject_player: int = ctx.get("subject_player", -1)
			return [m.players[subject_player].base] if subject_player >= 0 else []
		"indirect_units":
			return ctx.get("indirect_units", []).filter(func(unit): return unit.in_play())
		"own_base":
			return [m.players[ctl].base]
		"enemy_base":
			return [m.players[m.opp(ctl)].base]
		"defender":
			var d := m.card(m.attack.get("t", 0))
			return [d] if d and d.in_play() else []
		"attacker":
			var a := m.card(m.attack.get("a", 0))
			return [a] if a and a.in_play() else []
		"attached":
			if src and src.zone == "upgrade" and src.attached_to:
				return [src.attached_to]
			return [src] if src and src.in_play() else []
		"each":
			return candidates(m, t, ctx)
	# choose
	if ctx.has("_choice"):
		var picked: Array = []
		for uid in ctx["_choice"]:
			var c := m.card(uid)
			if c:
				picked.append(c)
		ctx.erase("_choice")
		return picked
	var cands := candidates(m, t, ctx)
	if e.get("op") in ["defeat", "bounce"]:
		cands = cands.filter(func(c): return not _enemy_effect_immune(c, ctl, e["op"]))
	if cands.is_empty():
		return []
	var count := int(t.get("count", 1))
	if t.get("random", false):
		var pick: Array = []
		for _i in mini(count, cands.size()):
			var c: CardInst = cands[m.rng.randi_range(0, cands.size() - 1)]
			cands.erase(c)
			pick.append(c)
		return pick
	var optional: bool = e.get("optional", false) or t.get("opt", false) or t.get("upto", false)
	var mx := mini(count, cands.size())
	var mn := 0 if optional else mx
	var uids: Array = []
	for c in cands:
		uids.append(c.uid)
	if not optional and cands.size() == mx and m.players[ctl].is_ai:
		return cands
	_ask(m, ctx, "target", e.get("prompt", _label(ctx, e)), uids, mn, mx, e)
	return null


static func _capture(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var controller: int = ctx.get("ctl", 0)
	if not ctx.has("_captor"):
		if ctx.has("_choice"):
			var selection: Array = ctx["_choice"]
			ctx.erase("_choice")
			if selection.is_empty():
				ctx["did"] = false
				return DONE
			ctx["_captor"] = selection[0]
		else:
			var hosts: Array = []
			for unit in m.players[controller].units:
				for enemy in m.players[m.opp(controller)].units:
					if not enemy.is_leader_unit() and enemy.zone == unit.zone:
						hosts.append(unit.uid)
						break
			if hosts.is_empty():
				ctx["did"] = false
				return DONE
			_ask(m, ctx, "target", "Choose the friendly guarding unit", hosts, 0 if e.get("optional", false) else 1, 1, e)
			return SUSPEND
	var host := m.card(ctx["_captor"])
	if ctx.has("_choice"):
		var enemy := m.card(ctx["_choice"][0])
		ctx.erase("_choice")
		ctx.erase("_captor")
		ctx["did"] = m.capture(host, enemy)
		return DONE
	var targets: Array = []
	for enemy in m.players[m.opp(controller)].units:
		if not enemy.is_leader_unit() and enemy.zone == host.zone:
			targets.append(enemy.uid)
	if targets.is_empty():
		ctx.erase("_captor")
		ctx["did"] = false
		return DONE
	_ask(m, ctx, "target", "Choose the enemy unit to capture", targets, 1, 1, {"op": "defeat"})
	return SUSPEND


static func candidates(m: Match, t: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var pool: Array = []
	var kind: String = t.get("kind", "unit")
	if kind == "unit" or kind == "unit_or_base":
		pool.append_array(m.all_units())
	if kind == "base" or kind == "unit_or_base":
		pool.append(m.players[0].base)
		pool.append(m.players[1].base)
	if kind == "upgrade":
		for instance in m.by_uid.values():
			if instance.zone == "upgrade":
				pool.append(instance)
	for c in pool:
		if matches(m, c, t, ctx):
			out.append(c)
	return out


static func matches(m: Match, c: CardInst, t: Dictionary, ctx: Dictionary) -> bool:
	var ctl: int = ctx.get("ctl", 0)
	var src: CardInst = m.card(ctx.get("src", 0))
	var side: String = t.get("side", "any")
	if side == "enemy" and c.controller == ctl:
		return false
	if side == "friendly" and c.controller != ctl:
		return false
	if c.zone == "base":
		return true
	if c.flags.get("untargetable", false) and side != "friendly":
		return false
	if t.get("other", false) and src and (c == src or (src.is_pilot_upgrade() and c == src.attached_to)):
		return false
	if t.has("arena") and c.zone != t["arena"]:
		return false
	if t.get("arena_of_it", false):
		var previous := m.card(ctx.get("it", 0))
		if not previous or c.arena() != ctx.get("it_arena", previous.arena()):
			return false
	if t.get("same_arena", false) and src and c.arena() != src.arena():
		return false
	if t.get("different_arena", false) and src and c.arena() == src.arena():
		return false
	if t.get("nonleader", false) and c.is_leader() and c.zone == "upgrade":
		return false
	if t.get("nonleader", false) and c.is_leader_unit():
		return false
	if t.get("leader", false) and not c.is_leader_unit():
		return false
	if t.get("damaged", false) and c.damage <= 0:
		return false
	if t.get("exhausted", false) and not c.exhausted:
		return false
	if t.get("ready", false) and c.exhausted:
		return false
	if t.get("can_attack", false) and m.attack_targets(c).is_empty():
		return false
	if t.has("max_hp") and c.remaining_hp() > int(t["max_hp"]):
		return false
	if t.has("max_power") and c.power() > int(t["max_power"]):
		return false
	if t.has("max_cost") and c.cost() > int(t["max_cost"]):
		return false
	if t.has("trait") and not c.has_trait(t["trait"]):
		return false
	if t.has("traits_any"):
		var any_ok := false
		for tr in t["traits_any"]:
			if c.has_trait(tr):
				any_ok = true
		if not any_ok:
			return false
	if t.get("token", false) and not c.is_token:
		return false
	if t.get("upgraded", false) and c.upgrades.is_empty():
		return false
	if t.get("different", false) and ctx.has("it") and c.uid == int(ctx["it"]):
		return false
	if t.has("min_hp") and c.remaining_hp() < int(t["min_hp"]):
		return false
	if t.has("min_power") and c.power() < int(t["min_power"]):
		return false
	if t.has("without_token"):
		for up in c.upgrades:
			if str(up.data.get("name", "")).to_lower() == t["without_token"]:
				return false
	if t.has("with_token") and not c.upgrades.any(func(up):
		return up.is_token and up.name().to_lower() == t["with_token"]):
		return false
	if t.has("not_trait") and c.has_trait(t["not_trait"]):
		return false
	if t.has("aspect") and not (t["aspect"] in c.aspects()):
		return false
	if t.has("unique") and c.unique() != t["unique"]:
		return false
	return true


static func condition(m: Match, cond: Dictionary, ctx: Dictionary) -> bool:
	var ctl: int = ctx.get("ctl", 0)
	if cond.has("controls_name"):
		return m.trigger_sources().any(func(card): return card.controller == ctl and card.name() == cond["controls_name"])
	if cond.has("revealed_aspect"):
		var revealed := m.card(ctx.get("revealed", 0))
		return revealed != null and cond["revealed_aspect"] in revealed.aspects()
	if cond.has("control"):
		return candidates(m, cond["control"], ctx).size() >= int(cond.get("min", 1))
	if cond.get("enemy_defeated_this_phase", false):
		return m.defeated_this_phase[m.opp(ctl)] > 0
	if cond.get("has_initiative", false):
		return m.initiative == ctl
	if cond.has("resource_count"):
		return m.players[ctl].resources.size() >= int(cond["resource_count"])
	if cond.get("indirect_base_hit", false):
		return ctx.get("indirect_base_hit", false)
	if cond.get("fewer_resources", false):
		return m.players[ctl].resources.size() < m.players[m.opp(ctl)].resources.size()
	if cond.get("fewer_hand_cards", false):
		return m.players[ctl].hand.size() < m.players[m.opp(ctl)].hand.size()
	if cond.get("both_arenas", false):
		return m.players[ctl].units.any(func(u): return u.zone == "ground") and m.players[ctl].units.any(func(u): return u.zone == "space")
	if cond.has("attacked_trait"):
		var tr: String = cond["attacked_trait"]
		for uid in m.attacked_with[ctl]:
			var a := m.card(uid)
			if a and (tr == "" or a.has_trait(tr)) and (not cond.get("attacked_non_token", false) or not a.is_token):
				return true
		return false
	if cond.has("played_trait"):
		var tr2: String = cond["played_trait"]
		for c in m.played_this_phase[ctl]:
			if tr2 == "" or c.has_trait(tr2) or tr2 in c.aspects() or (tr2 == "non-unit force" and c.card_type() != "unit" and c.has_trait("force")):
				return true
		return false
	if cond.has("friendly_defeated_trait"):
		var tr3: String = cond["friendly_defeated_trait"]
		for c in m.defeated_cards_this_phase[ctl]:
			if tr3 == "" or c.has_trait(tr3) or tr3 in c.aspects():
				return true
		return false
	if cond.has("friendly_defeated_min"):
		return m.defeated_cards_this_phase[ctl].size() >= int(cond["friendly_defeated_min"])
	if cond.get("self_damaged", false):
		var src := m.card(ctx.get("src", 0))
		return src != null and src.damage > 0
	if cond.has("selected_trait") or cond.get("selected_damaged", false):
		var selected := m.card(ctx.get("it", 0))
		if not selected:
			return false
		if cond.has("selected_trait"):
			return selected.has_trait(cond["selected_trait"])
		return selected.damage > 0
	return true


static func upgrade_targets(m: Match, p: int, up: CardInst, piloting := false) -> Array:
	var out: Array = []
	if piloting:
		for unit in m.players[p].units:
			if not unit.has_trait("vehicle"):
				continue
			var pilots := 0
			var slots := 1 + int(up.data["pilot"].get("extra_slot", false))
			for attached in unit.upgrades:
				if attached.has_trait("pilot"):
					pilots += 1
					slots += int(attached.data.get("pilot", {}).get("extra_slot", false))
			if up.data["pilot"].has("flip_cost") and pilots > 0:
				continue
			if pilots < slots:
				out.append(unit)
		return out
	if up.has_kw("fortify"):
		return [m.players[p].base]
	var txt: String = up.data.get("text", "").to_lower()
	for u in m.all_units():
		var eligible := true
		for restriction in up.data.get("abilities", []):
			if restriction.get("trigger") == "attach_restriction" and not matches(m, u, restriction["target"], {"ctl": p, "src": up.uid}):
				eligible = false
		if not eligible:
			continue
		if txt.find("attach to a non-vehicle unit") >= 0 and u.has_trait("vehicle"):
			continue
		if txt.find("attach to a vehicle unit") >= 0 and not u.has_trait("vehicle"):
			continue
		if txt.find("attach to a friendly unit") >= 0 and u.controller != p:
			continue
		if txt.find("attach to a non-leader unit") >= 0 and u.is_leader_unit():
			continue
		if u.flags.get("untargetable", false) and u.controller != p:
			continue
		out.append(u)
	return out


static func _ask(m: Match, ctx: Dictionary, kind: String, prompt: String, options: Array, mn: int, mx: int, e := {}, who := -1) -> void:
	var op: String = e.get("op", "")
	var hostile := op in HOSTILE_OPS or (op == "buff" and (int(e.get("p", 0)) < 0 or int(e.get("h", 0)) < 0))
	m.pending = {
		"player": ctx.get("ctl", 0) if who < 0 else who, "kind": kind, "prompt": prompt,
		"options": options, "min": mn, "max": mx, "src": ctx.get("src", 0),
		"op": op, "hostile": hostile, "effect": e,
	}


static func _label(ctx: Dictionary, e: Dictionary) -> String:
	var txt: String = ctx.get("text", "")
	if txt != "":
		return ("%s — %s" % [ctx.get("name", ""), txt]) if ctx.has("name") else txt
	return str(e.get("op", "choose")).capitalize()


# ---------------------------------------------------------------- composite ops

static func _indirect_damage(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var ctl: int = ctx.get("ctl", 0)
	var src := m.card(ctx.get("src", 0))
	if not ctx.has("_indirect"):
		var recipient := m.opp(ctl)
		match e.get("player", "opponent"):
			"choose":
				if not ctx.has("_choice"):
					_ask(m, ctx, "option", "Choose who receives indirect damage", [0, 1], 1, 1, e)
					m.pending["labels"] = [m.players[recipient].display_name, m.players[ctl].display_name]
					return SUSPEND
				if int(ctx["_choice"][0]) == 1:
					recipient = ctl
				ctx.erase("_choice")
			"defender":
				var defender := m.card(m.attack.get("t", 0))
				if defender:
					recipient = defender.controller
		var amount := int(e.get("n", 0))
		if e.get("underworld_bonus", false) and src and src.has_trait("underworld"):
			amount += 1
		match e.get("amount", ""):
			"source_power":
				amount = src.power(m.attack.get("a", 0) == src.uid) if src else 0
			"friendly_vehicles":
				amount = m.players[ctl].units.filter(func(unit): return unit.has_trait("vehicle")).size()
		var chooser := recipient
		if src and src.abilities_with("constant").any(func(a): return a.get("flag") == "assign_unit_indirect"):
			chooser = ctl
		if recipient != ctl:
			for card in m.trigger_sources():
				if card.controller != ctl:
					continue
				for ability in card.abilities_with("constant"):
					match ability.get("flag", ""):
						"assign_indirect": chooser = ctl
						"increase_indirect": amount += 1
		ctx["_indirect"] = {"remaining": amount, "recipient": recipient, "chooser": chooser, "assigned": {}}
	var state: Dictionary = ctx["_indirect"]
	var assigned: Dictionary = state["assigned"]
	if ctx.has("_choice"):
		var uid: int = ctx["_choice"][0]
		assigned[uid] = int(assigned.get(uid, 0)) + 1
		state["remaining"] -= 1
		ctx.erase("_choice")
	var ps: PlayerState = m.players[state["recipient"]]
	if state["remaining"] > 0:
		var options := [ps.base.uid]
		for unit in ps.units:
			if unit.remaining_hp() > int(assigned.get(unit.uid, 0)):
				options.append(unit.uid)
		if options.size() > 1:
			var allocations := PackedStringArray()
			for uid in assigned:
				allocations.append("%s %d" % [m.card(uid).name(), assigned[uid]])
			var prompt := "Assign indirect damage · %d left" % state["remaining"]
			if not allocations.is_empty():
				prompt += "\n" + ", ".join(allocations)
			_ask(m, ctx, "damage_assignment", prompt, options, 1, 1, e, state["chooser"])
			m.pending["hostile"] = state["chooser"] != state["recipient"]
			m.pending["assigned"] = assigned.duplicate()
			return SUSPEND
		assigned[ps.base.uid] = int(assigned.get(ps.base.uid, 0)) + int(state["remaining"])
	ctx["indirect_base_hit"] = false
	ctx["indirect_units"] = []
	for uid in assigned:
		var target := m.card(uid)
		if m.deal_damage(target, assigned[uid], src, true) > 0:
			if target.zone == "base":
				ctx["indirect_base_hit"] = true
			else:
				ctx["indirect_units"].append(target)
	ctx["did"] = not assigned.is_empty()
	ctx.erase("_indirect")
	return DONE


static func _discard(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var ctl: int = ctx.get("ctl", 0)
	var who: int = ctl if e.get("who", "self") == "self" else m.opp(ctl)
	var ps: PlayerState = m.players[who]
	if e.get("random", false):
		ctx["did"] = not ps.hand.is_empty()
		for i in mini(int(e.get("n", 1)), ps.hand.size()):
			var card: CardInst = ps.hand.pop_at(m.rng.randi_range(0, ps.hand.size() - 1))
			card.zone = "discard"
			ps.discard.append(card)
			m.events.append({"t": "discard", "uid": card.uid, "p": who})
		return DONE
	if ctx.has("_choice"):
		var selected: Array = ctx["_choice"]
		for uid in selected:
			var c := m.card(uid)
			ps.hand.erase(c)
			c.zone = "discard"
			ps.discard.append(c)
			m.events.append({"t": "discard", "uid": uid, "p": who})
		ctx.erase("_choice")
		ctx["did"] = not selected.is_empty()
		return DONE
	if ps.hand.is_empty():
		ctx["did"] = false
		return DONE
	var uids: Array = []
	for c in ps.hand:
		if c.cost() >= int(e.get("min_cost", 0)) and (not e.get("unit_only", false) or c.card_type() == "unit"):
			uids.append(c.uid)
	if uids.is_empty():
		ctx["did"] = false
		return DONE
	var n := mini(int(e.get("n", 1)), uids.size())
	var chooser := ctl if e.get("chooser") == "self" else who
	_ask(m, ctx, "hand", "Discard %d card(s)" % n, uids, 0 if e.get("chooser") == "self" and e.get("optional", false) else n, n, e, chooser)
	return SUSPEND


static func _scry(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var ps: PlayerState = m.players[ctx.get("ctl", 0)]
	if ctx.has("_choice"):
		for uid in ctx["_choice"]:
			var c := m.card(uid)
			ps.deck.erase(c)
			ps.deck.append(c)
		ctx.erase("_choice")
		ctx["did"] = true
		return DONE
	if ps.deck.is_empty():
		return DONE
	var top: Array = []
	for i in mini(int(e.get("n", 1)), ps.deck.size()):
		top.append(ps.deck[i].uid)
	_ask(m, ctx, "scry", "Choose cards to put on the bottom of your deck", top, 0, top.size(), e)
	m.pending["reveal"] = top
	return SUSPEND


static func _search(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var ps: PlayerState = m.players[ctx.get("ctl", 0)]
	var n := mini(int(e.get("n", 5)), ps.deck.size())
	var top: Array = ps.deck.slice(0, n)
	if ctx.has("_choice"):
		var drew: bool = not ctx["_choice"].is_empty()
		for uid in ctx["_choice"]:
			var c := m.card(uid)
			ps.deck.erase(c)
			c.zone = "hand"
			ps.hand.append(c)
			m.events.append({"t": "draw", "p": ps.index, "uid": uid, "reveal": true})
		var remaining := top.filter(func(c): return c.zone == "deck")
		for c in remaining:
			ps.deck.erase(c)
		m._shuffle(remaining)
		ps.deck.append_array(remaining)
		ctx.erase("_choice")
		if drew:
			m.on_cards_drawn(ps.index)
		ctx["did"] = true
		return DONE
	var f: Dictionary = e.get("filter", {})
	var ok: Array = []
	var kind: String = f.get("kind", "card")
	for c in top:
		if kind != "card" and c.card_type() != kind:
			continue
		if f.has("trait") and not c.has_trait(f["trait"]):
			continue
		if f.has("aspect") and not (f["aspect"] in c.aspects()):
			continue
		if f.has("max_cost") and c.cost() > int(f["max_cost"]):
			continue
		ok.append(c.uid)
	var reveal: Array = []
	for c in top:
		reveal.append(c.uid)
	_ask(m, ctx, "search", "Search: choose up to %d" % int(e.get("count", 1)), ok, 0, mini(int(e.get("count", 1)), ok.size()), e)
	m.pending["reveal"] = reveal
	return SUSPEND


static func _attack_with(m: Match, e: Dictionary, ctx: Dictionary, attackers: Array) -> int:
	# Step 2: pick the target for the chosen attacker.
	if ctx.has("_attacker"):
		var a := m.card(ctx["_attacker"])
		if ctx.has("_choice"):
			var tgt := m.card(ctx["_choice"][0])
			ctx.erase("_choice")
			ctx.erase("_attacker")
			ctx["it"] = a.uid
			if e.get("op") == "support":
				a.mods.append({"abilities": e.get("support_abilities", []), "dur": "attack"})
				for keyword in e.get("support_keywords", []):
					if keyword["k"] != "support":
						a.mods.append({"kw": keyword["k"], "v": keyword.get("v", 1), "dur": "attack"})
			for pre in e.get("pre", []):
				if not condition(m, pre.get("if", {}), ctx):
					continue
				if pre.get("op") == "buff":
					a.mods.append({"p": int(pre.get("p", 0)), "h": int(pre.get("h", 0)), "dur": "attack"})
				elif pre.get("op") == "gain_kw":
					a.mods.append({"kw": pre["kw"], "v": int(pre.get("v", 1)), "dur": "attack"})
			if e.get("different_odd_power", false):
				var revealed := m.card(ctx.get("revealed", 0))
				if revealed and revealed.cost() % 2 == 1 and a.cost() % 2 == 1 and revealed.cost() != a.cost():
					a.mods.append({"p": 1, "dur": "attack"})
			if e.get("falcon_first_strike", false) and a.name() == "Millennium Falcon":
				a.mods.append({"abilities": [{"trigger": "constant", "flag": "first_strike"}], "dur": "attack"})
			m.begin_attack(a, tgt)
			ctx["did"] = true
			return DONE
	if attackers.is_empty():
		ctx["did"] = false
		return DONE
	var a: CardInst = attackers[0]
	var tg := m.attack_targets(a)
	if tg.is_empty():
		ctx["did"] = false
		return DONE
	ctx["_attacker"] = a.uid
	_ask(m, ctx, "attack_target", "Choose a target for %s" % a.name(), tg, 1, 1, {"op": "damage"})
	return SUSPEND


# ---------------------------------------------------------------- system ops

static func _system(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var op: String = e["op"]
	match op:
		"_bottom_opening_hand":
			var ps: PlayerState = m.players[ctx["ctl"]]
			if m.round_num != 1:
				return DONE
			if ctx.has("_choice"):
				for uid in ctx["_choice"]:
					var c := m.card(uid)
					ps.hand.erase(c)
					c.zone = "deck"
					ps.deck.append(c)
				ctx.erase("_choice")
				return DONE
			var amount := mini(ps.hand.size(), int(e["n"]))
			if amount == 0:
				return DONE
			_ask(m, ctx, "hand", "Choose %d cards for the bottom of your deck, in order" % amount, ps.hand.map(func(c): return c.uid), amount, amount)
			return SUSPEND
		"_recycle_resource", "_choose_defeat_resource", "_sundari_resource", "_defeat_friendly_token":
			var ps: PlayerState = m.players[ctx["ctl"]]
			if ctx.has("_choice"):
				var selected: Array = ctx["_choice"]
				ctx.erase("_choice")
				if selected.is_empty():
					return DONE
				var c := m.card(int(selected[0]))
				match op:
					"_recycle_resource":
						m.return_to_hand(c)
						if not ps.deck.is_empty():
							m.move_to_resources(ps.index, ps.deck[0], true)
					"_choose_defeat_resource":
						ps.resources.erase(c)
						c.zone = "discard"
						m.players[c.owner].discard.append(c)
						m.events.append({"t": "resource", "p": ps.index, "uid": c.uid})
					"_sundari_resource":
						m.move_to_resources(ps.index, c, false)
						ps.base.flags["sundari_resources"] = int(ps.base.flags.get("sundari_resources", 0)) + 1
					"_defeat_friendly_token":
						if selected[0] == 0:
							ps.credits -= 1
							m.events.append({"t": "credits", "p": ps.index, "n": -1})
						else:
							m.defeat(c)
				return DONE
			var options: Array
			var prompt := "Choose a resource"
			var kind := "resource"
			if op == "_sundari_resource":
				options = ps.hand.map(func(c): return c.uid)
				kind = "hand"
				prompt = "You may resource a card ready"
			elif op == "_defeat_friendly_token":
				options = _friendly_tokens(m, ps.index)
				kind = "option"
				prompt = "Choose a friendly token to defeat"
			else:
				options = ps.resources.map(func(c): return c.uid)
			if options.is_empty():
				return DONE
			_ask(m, ctx, kind, prompt, options, 0 if op == "_sundari_resource" else 1, 1)
			if op == "_defeat_friendly_token":
				m.pending["labels"] = options.map(func(uid): return "Credit" if uid == 0 else m.card(uid).name())
			return SUSPEND
		"_search_named", "_mill_recover_top":
			var ps: PlayerState = m.players[ctx["ctl"]]
			if ctx.has("_choice"):
				var selected: Array = ctx["_choice"]
				ctx.erase("_choice")
				if op == "_search_named":
					if not selected.is_empty():
						var c := m.card(int(selected[0]))
						ps.deck.erase(c)
						c.zone = "hand"
						ps.hand.append(c)
						m.events.append({"t": "draw", "uid": c.uid, "p": ps.index, "reveal": true})
						m.on_cards_drawn(ps.index)
					m._shuffle(ps.deck)
				elif not selected.is_empty():
					var c := m.card(int(selected[0]))
					ps.discard.erase(c)
					c.zone = "deck"
					ps.deck.push_front(c)
				return DONE
			var options: Array = []
			if op == "_search_named":
				for c in ps.deck:
					if c.name() == e["name"]:
						options.append(c.uid)
				if options.is_empty():
					m._shuffle(ps.deck)
					return DONE
			else:
				for i in mini(ps.deck.size(), int(e["n"])):
					var c: CardInst = ps.deck.pop_front()
					c.zone = "discard"
					ps.discard.append(c)
					options.append(c.uid)
					m.events.append({"t": "discard", "uid": c.uid, "p": ps.index})
			if options.is_empty():
				return DONE
			_ask(m, ctx, "search", "Choose a card to draw" if op == "_search_named" else "You may return a discarded card to the top of your deck", options, 0, 1)
			m.pending["reveal"] = options
			return SUSPEND
		"_per_leader", "_sundari":
			var seq: Array = []
			for unit in m.players[ctx["ctl"]].units:
				if unit.is_leader_unit():
					seq.append_array(e.get("effects", [{"op": "_sundari_resource"}]))
			m.push_frame(seq, ctx.duplicate())
		"_unit_into_pilot", "_pilot_into_unit":
			return _pilot_transition(m, e, ctx)
		"_pilot_boba_damage":
			var pilot := m.card(ctx["src"])
			var host := pilot.attached_to
			if not host:
				return DONE
			if host.has_trait("transport") and not ctx.has("_pilot_boba_amount"):
				if not ctx.has("_choice"):
					_ask(m, ctx, "option", "Choose how much damage to deal", [1, 2], 0, 1)
					m.pending["labels"] = ["Deal 1 damage", "Deal 2 damage"]
					return SUSPEND
				var selected: Array = ctx["_choice"]
				ctx.erase("_choice")
				if selected.is_empty():
					return DONE
				ctx["_pilot_boba_amount"] = selected[0]
			return _exec(m, {"op": "damage", "n": ctx.get("_pilot_boba_amount", 1), "t": {"s": "choose", "kind": "unit", "opt": true}}, ctx)
		"_mill_return_odd", "_mill_defender_draw":
			var p: int = ctx["ctl"]
			var who := m.opp(p) if op == "_mill_defender_draw" else p
			var from: PlayerState = m.players[who]
			for i in mini(int(e.get("n", 1)), from.deck.size()):
				var c: CardInst = from.deck.pop_front()
				c.zone = "discard"
				from.discard.append(c)
				m.events.append({"t": "discard", "uid": c.uid, "p": who})
				if op == "_mill_return_odd" and c.cost() % 2 == 1:
					m.return_to_hand(c)
				elif op == "_mill_defender_draw" and c.cost() <= 3:
					m.draw(p, 1)
		"_vader_pilot_damage":
			var result: Variant = _targets(m, e, ctx)
			if result == null:
				return SUSPEND
			var targets: Array = result
			if not targets.is_empty():
				var unit: CardInst = targets[0]
				m.deal_damage(unit, 1, m.card(ctx["src"]))
				if unit.damage >= unit.max_hp():
					m.defeat(unit)
					if not unit.in_play():
						m.push_frame([{"op": "damage", "n": 1, "t": {"s": "choose", "kind": "unit_or_base", "opt": true}}], ctx.duplicate())
		"_plot":
			var controller: int = ctx["ctl"]
			if ctx.has("_choice"):
				var choice: Array = ctx["_choice"]
				ctx.erase("_choice")
				if not choice.is_empty():
					var plotted := m.card(choice[0])
					m._play_card(controller, plotted, false, {"from_resource": true})
					var left: Array = e["ids"].duplicate()
					left.erase(plotted.uid)
					m.push_frame([{"op": "_plot", "ids": left}], {"ctl": controller})
				return DONE
			var options: Array = []
			for uid in e["ids"]:
				var candidate := m.card(uid)
				if candidate == null or candidate.zone != "resource":
					continue
				if candidate.card_type() == "upgrade" and upgrade_targets(m, controller, candidate).is_empty():
					continue
				if candidate.card_type() == "unit" and not m.arena_for(candidate) in m.rules.arenas:
					continue
				if m.play_cost(controller, candidate) <= m.players[controller].available():
					options.append(uid)
			if options.is_empty():
				return DONE
			_ask(m, ctx, "hand", "Plot: play a card from resources after deploying your leader, or skip", options, 0, 1)
			return SUSPEND
		"_draw":
			m.draw(int(e["p"]), int(e["n"]))
		"_mulligan":
			var p := int(e["p"])
			if ctx.has("_choice"):
				var yes: bool = ctx["_choice"][0] == 1
				ctx.erase("_choice")
				if yes:
					var ps: PlayerState = m.players[p]
					var n := ps.hand.size()
					for c in ps.hand:
						c.zone = "deck"
						ps.deck.append(c)
					ps.hand.clear()
					m._shuffle(ps.deck)
					m.draw(p, n)
					m._log("%s mulligans." % ps.display_name)
				return DONE
			_ask(m, {"ctl": p}, "mulligan", "Mulligan your opening hand?", [1, 0], 1, 1)
			return SUSPEND
		"_setup_resources", "_regroup_resource":
			var p := int(e["p"])
			var ps: PlayerState = m.players[p]
			if ctx.has("_choice"):
				for uid in ctx["_choice"]:
					m.move_to_resources(p, m.card(uid), false)
				ctx.erase("_choice")
				return DONE
			if ps.hand.is_empty():
				return DONE
			var uids: Array = []
			for c in ps.hand:
				uids.append(c.uid)
			if op == "_setup_resources":
				var n := mini(int(e.get("n", 2)), uids.size())
				if n <= 0:
					return DONE
				_ask(m, {"ctl": p}, "resource", "Choose %d card(s) to put into your resources" % n, uids, n, n)
			else:
				_ask(m, {"ctl": p}, "resource", "Resource up to 1 card", uids, 0, 1)
			return SUSPEND
		"_reset_ctx":
			ctx.erase("it")
			ctx.erase("did")
		"_mill":
			var mp := int(e.get("p", ctx.get("ctl", 0)))
			for _i in int(e.get("n", 1)):
				if not m.players[mp].deck.is_empty():
					var top: CardInst = m.players[mp].deck.pop_front()
					top.zone = "discard"
					m.players[mp].discard.append(top)
		"_defeat_resource":
			var rp: int = ctx.get("ctl", 0)
			var rs: Array = m.players[rp].resources
			if not rs.is_empty():
				var pick: CardInst = rs[0]
				for r in rs:
					if r.exhausted:
						pick = r
				rs.erase(pick)
				pick.zone = "discard"
				m.players[pick.owner].discard.append(pick)
				m.events.append({"t": "resource", "p": rp, "uid": pick.uid})
		"_defeat_upgrade":
			var up_p: int = ctx.get("ctl", 0)
			if ctx.has("_choice"):
				var host := m.card(ctx["_choice"][0])
				ctx.erase("_choice")
				for up in host.upgrades:
					if up.controller == up_p or host.controller == up_p:
						host.upgrades.erase(up)
						if not up.is_token:
							up.zone = "discard"
							m.players[up.owner].discard.append(up)
						m.events.append({"t": "token", "kind": "upgrade", "on": host.uid})
						break
				return DONE
			var hosts: Array = []
			for u in m.all_units():
				if u.controller == up_p and not u.upgrades.is_empty():
					hosts.append(u.uid)
			if hosts.is_empty():
				return DONE
			_ask(m, ctx, "target", "Cost: defeat a friendly upgrade (choose the unit)", hosts, 1, 1, {"op": "defeat"})
			return SUSPEND
		"_exploit":
			var c := m.card(int(e["uid"]))
			var xp: int = ctx.get("ctl", 0)
			var units: Array = []
			for u in m.players[xp].units:
				if not u.is_leader_unit():
					units.append(u.uid)
			var full := m.play_cost(xp, c)
			var need := maxi(0, ceili((full - m.players[xp].available()) / 2.0))
			var mx := mini(c.kw("exploit"), units.size())
			if ctx.has("_choice"):
				var sel: Array = ctx["_choice"]
				ctx.erase("_choice")
				for uid in sel:
					m.defeat(m.card(uid))
				m._play_card(xp, c, false, {"discount": 2 * sel.size()})
				return DONE
			if mx <= 0:
				m._play_card(xp, c, false)
				return DONE
			_ask(m, ctx, "target", "Exploit %d: defeat friendly units to reduce the cost by 2 each (need %d)" % [c.kw("exploit"), need], units, need, mx, {"op": "defeat"})
			m.pending["hostile"] = false
			return SUSPEND
		"_deck_to_resources":
			var p := int(e["p"])
			for _i in int(e.get("n", 1)):
				if not m.players[p].deck.is_empty():
					m.move_to_resources(p, m.players[p].deck.pop_front(), false)
		"_start_action":
			m.phase = "action"
			m.start_action_phase()
		"_regroup_triggers":
			for p in [m.initiative, m.opp(m.initiative)]:
				var base: CardInst = m.players[p].base
				var owed := int(base.flags.get("sundari_resources", 0))
				if owed > 0:
					base.flags.erase("sundari_resources")
					var seq: Array = []
					for i in owed:
						seq.append({"op": "_choose_defeat_resource"})
					m.push_frame(seq, {"ctl": p, "src": base.uid})
			for u in m.trigger_sources():
				for ab in u.abilities_with("regroup_start"):
					m.push_ability(u, ab)
			for unit in m.all_units():
				if unit.flags.erase("return_control_at_regroup"):
					m.take_control(unit, unit.owner)
		"_ready_all":
			for ps in m.players:
				for u in ps.units:
					if not u.flags.erase("skip_regroup_ready") and not u.flags.get("cannot_ready", false):
						u.exhausted = false
				for r in ps.resources:
					r.exhausted = false
				if ps.leader:
					ps.leader.exhausted = false
			m.events.append({"t": "ready_all"})
		"_new_round":
			m.end_round()
		"_combat":
			m.resolve_combat()
		"_before_combat":
			m._state_based()
		"_attack_end":
			m.end_attack()
		"_deploy_pilot", "_reattach_pilot":
			var leader := m.card(int(ctx["src"]))
			var p: int = ctx["ctl"]
			if ctx.has("_choice"):
				var host := m.card(int(ctx["_choice"][0]))
				ctx.erase("_choice")
				if op == "_deploy_pilot":
					m._deploy_pilot(p, host)
				else:
					var old := leader.attached_to
					old.upgrades.erase(leader)
					leader.attached_to = host
					host.upgrades.append(leader)
					m.events.append({"t": "upgrade", "uid": leader.uid, "on": host.uid})
				return DONE
			var opts: Array = upgrade_targets(m, p, leader, true).map(func(u): return u.uid)
			if opts.is_empty():
				return DONE
			_ask(m, ctx, "target", "Choose a Vehicle for %s" % leader.name(), opts, 1, 1, {"op": "attach"})
			return SUSPEND
		"_attach":
			var up := m.card(int(e["uid"]))
			var p: int = ctx.get("ctl", 0)
			if ctx.has("_choice"):
				var tgt := m.card(ctx["_choice"][0])
				ctx.erase("_choice")
				m.attach_upgrade(up, tgt, ctx)
				return DONE
			var opts: Array = []
			for u in upgrade_targets(m, p, up, ctx.get("piloting", false)):
				opts.append(u.uid)
			if opts.is_empty():
				up.zone = "discard"
				m.players[up.owner].discard.append(up)
				return DONE
			_ask(m, {"ctl": p, "src": up.uid}, "target", "Attach %s" % up.name(), opts, 1, 1, {"op": "attach"})
			m.pending["hostile"] = int(up.data.get("power", 0)) < 0
			return SUSPEND
		"_ambush":
			var u := m.card(int(e["uid"]))
			if u == null or not u.in_play():
				return DONE
			if ctx.has("_choice"):
				var sel: Array = ctx["_choice"]
				ctx.erase("_choice")
				if sel.is_empty():
					return DONE
				m.exhaust(u, false)
				m.begin_attack(u, m.card(sel[0]))
				return DONE
			var opts: Array = []
			var was := u.exhausted
			u.exhausted = false
			for t in m.attack_targets(u):
				if m.card(t).zone != "base":
					opts.append(t)
			u.exhausted = was
			if opts.is_empty():
				return DONE
			_ask(m, {"ctl": u.controller, "src": u.uid}, "target", "Ambush: %s may attack an enemy unit" % u.name(), opts, 0, 1, {"op": "damage"})
			return SUSPEND
		"_bottom_from_hand":
			var p: int = ctx.get("ctl", 0)
			var ps: PlayerState = m.players[p]
			if ctx.has("_choice"):
				for uid in ctx["_choice"]:
					var c := m.card(uid)
					ps.hand.erase(c)
					c.zone = "deck"
					ps.deck.append(c)
				ctx.erase("_choice")
				return DONE
			if ps.hand.is_empty():
				return DONE
			var uids: Array = []
			for c in ps.hand:
				uids.append(c.uid)
			_ask(m, {"ctl": p}, "hand", "Put a card from your hand on the bottom of your deck", uids, 1, 1)
			return SUSPEND
		_:
			push_warning("Effects: unknown system op %s" % op)
	return DONE


## "Choose one:" / "Either A or B" / "An opponent chooses one:" — the right
## player picks an option; its effects then resolve for the card's controller.
static func _choose_one(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var opts: Array = e.get("options", [])
	if opts.is_empty():
		return DONE
	var selected: Array = ctx.get("_selected_modes", [])
	var count := int(e.get("count", 1))
	if ctx.has("_choice"):
		var sel: Array = ctx["_choice"]
		ctx.erase("_choice")
		if sel.is_empty():
			ctx.erase("_selected_modes")
			ctx["did"] = false
			return DONE
		selected.append(int(sel[0]))
		if selected.size() == count:
			ctx.erase("_selected_modes")
			# Frames resolve last-in first-out. Each option keeps its own targets.
			for i in range(selected.size() - 1, -1, -1):
				var pick: Dictionary = opts[selected[i]]
				m.push_frame(pick.get("effects", []), ctx.duplicate())
			for index in selected:
				m._log("Chose: %s" % opts[index].get("label", ""))
			ctx["did"] = true
			return DONE
		ctx["_selected_modes"] = selected
	var idx: Array = []
	var labels: Array = []
	for i in opts.size():
		if i in selected:
			continue
		idx.append(i)
		labels.append(opts[i].get("label", "Option %d" % (i + 1)))
	var ctl: int = ctx.get("ctl", 0)
	var who := m.opp(ctl) if e.get("who", "self") == "opponent" else ctl
	var mn := 0 if e.get("optional", false) and selected.is_empty() else 1
	var prompt := _label(ctx, e)
	if count > 1:
		prompt = "Choose option %d of %d. Effects resolve in the order you choose." % [selected.size() + 1, count]
	_ask(m, ctx, "option", prompt, idx, mn, 1, e, who)
	m.pending["labels"] = labels
	return SUSPEND


## "Play a [trait] unit/event/card from your hand [It costs N less / enters ready /
## ignoring aspect penalties / give it Ambush]". The player picks an affordable
## card (or skips); it is played immediately as part of this ability.
static func _hand_play_options(e: Dictionary) -> Dictionary:
	var opts := {"discount": int(e.get("discount", 0)), "ignore_aspects": e.get("ignore_aspects", false),
		"free": e.get("free", false),
		"ignore_one_basic_aspect": e.get("ignore_one_basic_aspect", false),
		"ready": e.get("ready", false)}
	if e.has("gain_kw"):
		opts["gain_kw"] = e["gain_kw"]
	return opts


static func has_hand_play(m: Match, p: int, effect: Dictionary) -> bool:
	var opts := _hand_play_options(effect)
	if effect.get("discount_by_leaders", false):
		opts["discount"] = m.players[p].units.filter(func(u): return u.is_leader_unit()).size()
	return m.players[p].hand.any(func(c): return not _hand_play_modes(m, p, c, effect, opts).is_empty())


static func _play_from_hand(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var p: int = ctx.get("ctl", 0)
	var ps: PlayerState = m.players[p]
	if e.get("cheaper_than_returned", false):
		var returned := m.card(ctx.get("it", 0))
		if not returned or returned.zone != "hand":
			return DONE
		e = e.duplicate()
		e["max_cost"] = returned.cost() - 1
	var opts := _hand_play_options(e)
	if e.get("discount_by_leaders", false):
		opts["discount"] = m.players[p].units.filter(func(u): return u.is_leader_unit()).size()
	var selected: CardInst
	if ctx.has("_play_mode_card"):
		selected = m.card(ctx["_play_mode_card"])
		ctx.erase("_play_mode_card")
		opts["piloting"] = ctx["_choice"][0] == 1
		ctx.erase("_choice")
	if ctx.has("_choice"):
		var sel: Array = ctx["_choice"]
		ctx.erase("_choice")
		if sel.is_empty():
			ctx["did"] = false
			return DONE
		selected = m.card(sel[0])
		var modes := _hand_play_modes(m, p, selected, e, opts)
		if modes.size() == 2:
			ctx["_play_mode_card"] = selected.uid
			_ask(m, ctx, "option", "Choose how to play %s" % selected.name(), [0, 1], 1, 1, e)
			var pilot_opts := opts.duplicate()
			pilot_opts["piloting"] = true
			m.pending["labels"] = ["Play as unit (%d)" % m.play_cost(p, selected, false, opts),
				"Play as Pilot (%d)" % m.play_cost(p, selected, false, pilot_opts)]
			return SUSPEND
		opts["piloting"] = true in modes
	if selected:
		ctx["did"] = true
		ctx["it"] = selected.uid
		var left := int(e.get("count", 1)) - 1
		if left > 0:
			var next := e.duplicate()
			next["count"] = left
			m.push_frame([next], ctx.duplicate())
		m._play_card(p, selected, false, opts)
		return DONE
	var cands: Array = []
	for c in ps.hand:
		if not _hand_play_modes(m, p, c, e, opts).is_empty():
			cands.append(c.uid)
	if cands.is_empty():
		ctx["did"] = false
		return DONE
	_ask(m, ctx, "hand", _label(ctx, e) + "\nChoose a card to play", cands, 0 if e.get("optional", false) else 1, 1, e)
	return SUSPEND


static func _hand_play_modes(m: Match, p: int, card: CardInst, e: Dictionary, opts: Dictionary) -> Array:
	var modes: Array = []
	if card == null or card.zone != "hand":
		return modes
	if e.has("traits_any") and not e["traits_any"].any(func(tag): return card.has_trait(tag)):
		return modes
	for piloting in [false, true]:
		if not piloting and e.get("pilot_only", false):
			continue
		if piloting and not card.data.has("pilot"):
			continue
		var t := "upgrade" if piloting else card.card_type()
		var kind: String = e.get("kind", "card")
		if kind != "card" and kind != t and not (kind == "non-unit" and t != "unit"):
			continue
		if t == "unit" and not (m.arena_for(card) in m.rules.arenas):
			continue
		if t == "upgrade" and upgrade_targets(m, p, card, piloting).is_empty():
			continue
		var pilot: Dictionary = card.data.get("pilot", {})
		var aspects: Array = pilot["aspects"] if piloting else card.aspects()
		var cost := int(pilot["cost"]) if piloting else card.cost()
		if e.has("aspect") and e["aspect"] not in aspects:
			continue
		if e.has("exclude_aspect") and e["exclude_aspect"] in aspects:
			continue
		if cost > int(e.get("max_cost", 999)):
			continue
		if e.has("max_power") and (t != "unit" or card.printed_power() > int(e["max_power"])):
			continue
		var play_opts := opts.duplicate()
		play_opts["piloting"] = piloting
		if m.play_cost(p, card, false, play_opts) <= m.players[p].available():
			modes.append(piloting)
	return modes



## Extra Action costs ("Action [Exhaust, defeat a friendly unit]: ..."):
## returns {"ok": can it be paid now, "ops": effects that pay it}.
static func extra_cost(m: Match, p: int, src: CardInst, other: String) -> Dictionary:
	var o := other.to_lower().strip_edges()
	var ps: PlayerState = m.players[p]
	var friendly := {"s": "choose", "kind": "unit", "side": "friendly"}
	var ctx := {"ctl": p, "src": src.uid}
	if o.begins_with("use the force"):
		return {"ok": ps.force_token, "ops": [{"op": "use_force"}]}
	if o == "exhaust a friendly unit":
		var t := friendly.duplicate()
		t["ready"] = true
		t["other"] = true
		return {"ok": not candidates(m, t, ctx).is_empty(), "ops": [{"op": "exhaust", "t": t}]}
	if o == "ready an exhausted enemy unit":
		var target := {"s": "choose", "kind": "unit", "side": "enemy", "exhausted": true}
		return {"ok": not candidates(m, target, ctx).is_empty(), "ops": [{"op": "ready", "t": target}]}
	if o == "defeat a friendly unit":
		var t2 := friendly.duplicate()
		t2["nonleader"] = true
		return {"ok": not candidates(m, t2, ctx).is_empty(), "ops": [{"op": "defeat", "t": t2}]}
	if o == "defeat a friendly token":
		return {"ok": not _friendly_tokens(m, p).is_empty(), "ops": [{"op": "_defeat_friendly_token"}]}
	if o == "defeat a friendly upgrade":
		var t := {"s": "choose", "kind": "upgrade", "side": "friendly"}
		return {"ok": not candidates(m, t, ctx).is_empty(), "ops": [{"op": "defeat", "t": t}]}
	if o == "discard a unit from your hand":
		return {"ok": ps.hand.any(func(c): return c.card_type() == "unit"),
			"ops": [{"op": "discard", "n": 1, "unit_only": true}]}
	if o == "defeat a friendly resource":
		return {"ok": ps.resources.size() > 1, "ops": [{"op": "_defeat_resource"}]}
	if o == "discard a card from your hand":
		return {"ok": not ps.hand.is_empty(), "ops": [{"op": "discard", "n": 1, "who": "self"}]}
	if o == "defeat this upgrade":
		return {"ok": src.zone == "upgrade", "ops": [{"op": "defeat", "t": {"s": "self"}}]}
	var mc := RegEx.create_from_string("^discard a card that costs (\\d+) or more from your hand$").search(o)
	if mc:
		var need := int(mc.get_string(1))
		for c in ps.hand:
			if c.cost() >= need:
				return {"ok": true, "ops": [{"op": "discard", "n": 1, "who": "self", "min_cost": need}]}
		return {"ok": false}
	if o == "discard a card from your deck":
		return {"ok": not ps.deck.is_empty(), "ops": [{"op": "_mill", "n": 1, "p": p}]}
	if o in ["return this unit to its owner's hand", "return this unit to his owner's hand"]:
		return {"ok": src.in_play() and not src.is_leader() and not src.is_token,
			"ops": [{"op": "bounce", "t": {"s": "self"}}]}
	var md := RegEx.create_from_string("^deal (\\d+) damage to a friendly unit$").search(o)
	if md:
		return {"ok": not candidates(m, friendly, ctx).is_empty(), "ops": [{"op": "damage", "n": int(md.get_string(1)), "t": friendly.duplicate()}]}
	var mb := RegEx.create_from_string("^deal (\\d+) damage to your base$").search(o)
	if mb:
		return {"ok": true, "ops": [{"op": "damage", "n": int(mb.get_string(1)), "t": {"s": "own_base"}}]}
	var mr := RegEx.create_from_string("^return a friendly (\\w+) unit to its owner's hand$").search(o)
	if mr:
		var t4 := friendly.duplicate()
		t4["trait"] = mr.get_string(1)
		t4["nonleader"] = true
		return {"ok": not candidates(m, t4, ctx).is_empty(), "ops": [{"op": "bounce", "t": t4}]}
	return {"ok": false}

static func _friendly_tokens(m: Match, p: int) -> Array:
	var options := m.trigger_sources().filter(func(c): return c.controller == p and c.is_token).map(func(c): return c.uid)
	if m.players[p].credits > 0:
		options.append(0)
	return options


static func _split_unit_damage(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var assigned: Dictionary = ctx.get("_split_damage", {})
	var finished := false
	if ctx.has("_choice"):
		var selected: Array = ctx["_choice"]
		ctx.erase("_choice")
		finished = selected.is_empty()
		if not finished:
			var uid := int(selected[0])
			assigned[uid] = int(assigned.get(uid, 0)) + 1
	var heals: bool = e.get("heal", false)
	var options := candidates(m, {"kind": "unit"}, ctx).filter(func(c):
		return not heals or c.damage > int(assigned.get(c.uid, 0))).map(func(c): return c.uid)
	var remaining := int(e["n"])
	for uid in assigned:
		remaining -= int(assigned[uid])
	if finished or remaining <= 0 or options.is_empty():
		for uid in assigned:
			if heals:
				m.heal(m.card(uid), assigned[uid])
			else:
				m.deal_damage(m.card(uid), assigned[uid], m.card(ctx["src"]))
		ctx.erase("_split_damage")
		return DONE
	ctx["_split_damage"] = assigned
	_ask(m, ctx, "damage_assignment", "%s · %d left" % ["Choose damage to heal" if heals else "Assign damage to units", remaining], options, 0, 1, {"op": "heal" if heals else "damage"})
	m.pending["assigned"] = assigned.duplicate()
	return SUSPEND

static func _enemy_effect_immune(c: CardInst, ctl: int, op: String) -> bool:
	if op == "bounce" and c.flags.get("objective_target", false):
		return true
	return c.controller != ctl and c.abilities_with("constant").any(func(ab):
		return ab.get("flag") == "enemy_defeat_bounce_immune" or (op == "defeat" and ab.get("flag") == "enemy_defeat_immune"))


static func _pilot_transition(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var source := m.card(int(ctx["src"]))
	if not source:
		return DONE
	var p := source.controller
	var into_unit: bool = e["op"] == "_pilot_into_unit"
	var options: Array = []
	if into_unit:
		if "ground" in m.rules.arenas:
			options = [1, 0]
	elif source.in_play():
		options = upgrade_targets(m, p, source, true).filter(func(host):
			return host != source and not host.upgrades.any(func(up): return up.has_trait("pilot"))).map(func(host): return host.uid)
	if not ctx.has("_choice") and not options.is_empty():
		if into_unit:
			_ask(m, ctx, "yesno", "Move %s to ground exhausted instead of defeating the upgrade?" % source.name(), options, 1, 1)
		else:
			_ask(m, ctx, "target", "You may attach %s as a Pilot" % source.name(), options, 0, 1)
		return SUSPEND
	var selected: Array = ctx.get("_choice", [])
	ctx.erase("_choice")
	source.flags.erase("pilot_replacement_pending")
	if not selected.is_empty() and selected[0] in options and selected[0] != 0:
		if into_unit:
			source.attached_to.upgrades.erase(source)
			source.attached_to = null
			m._put_in_play(source, "ground", true)
		else:
			var host := m.card(selected[0])
			m._defeat_attached_upgrades(source)
			m._rescue_captives(source)
			source.damage = 0
			source.mods.clear()
			if m.attack.get("t", 0) == source.uid and m.attack.get("a", 0) != 0:
				m.attack["defender_defeated"] = true
			m.attach_upgrade(source, host)
	elif e.get("replace", false):
		m.defeat(source, e.get("departing_host", false), true)
	return DONE
