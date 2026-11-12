class_name Match
extends RefCounted
## The SWU rules engine for one game. Pure logic (no Nodes): the board UI, the
## headless simulator and the tests all drive it through the same API:
##
##   setup(cfg)                 build players, shuffle, queue setup steps
##   pending                    non-empty => someone must answer a choice
##   submit_choice(selection)   answer it (Array of uids / indices)
##   legal_actions(p)           what player p may do now (action phase)
##   do_action(action)          perform one action
##   take_events()              drain animation events for the view
##
## Everything that happens (setup, regroup, abilities, attacks) is an op in a
## stack of frames (see Effects). A frame that needs input suspends and sets
## `pending`, which keeps the whole flow resumable and replayable.

const SIDES := ["player", "enemy"]

var lib: CardLibrary
var rules: RuleSet
var players: Array = []
var rng := RandomNumberGenerator.new()
var seed_value := 0
var round_num := 1
var phase := "setup"            # setup | action | regroup | over
var phase_serial := 0           # bumps every phase, for "this phase" durations
var active := 0
var initiative := 0
var consecutive_passes := 0
var winner := -1                # 0/1, 2 = draw
var events: Array = []
var log_lines: Array = []
var pending: Dictionary = {}
var frames: Array = []
var by_uid: Dictionary = {}
var tokens: Array = []          # claimable token definitions in this match
var tokens_claimed: Dictionary = {}
var objective: Objective
var attack: Dictionary = {}
var defeated_this_phase := [0, 0]
var attacked_with := [[], []]
var played_this_phase := [[], []]         # CardInst played this phase, per player
var defeated_cards_this_phase := [[], []]  # CardInst (controller's side) defeated this phase
var history: Array = []         # [{"a":..}, {"choice":[..]}] for deterministic replays
var _next_uid := 1
var _need_advance := false
var _last_actor := 0


# ---------------------------------------------------------------- setup

## cfg = {
##   seed, rules: RuleSet,
##   players: [{name, leader, base, deck:[ids], ai, profile, base_hp_bonus, preplaced:[{id, arena, flags}]}],
##   tokens: [token defs], objective: {type, params}
## }
func setup(p_lib: CardLibrary, cfg: Dictionary) -> void:
	lib = p_lib
	rules = cfg.get("rules", RuleSet.premier())
	seed_value = int(cfg.get("seed", randi()))
	rng.seed = seed_value
	players.clear()
	for i in 2:
		var pc: Dictionary = cfg["players"][i]
		var ps := PlayerState.new()
		ps.index = i
		ps.display_name = pc.get("name", "Player %d" % (i + 1))
		ps.is_ai = pc.get("ai", i == 1)
		ps.ai_profile = pc.get("profile", "tempo")
		ps.hero_skin = pc.get("hero_skin", "")
		players.append(ps)
		if pc.get("leader", "") != "":
			ps.leader = _new_inst(pc["leader"], i)
			ps.leader.zone = "leader"
		ps.base = _new_inst(pc.get("base", ""), i)
		ps.base.zone = "base"
		var hp_target := rules.base_hp_override if rules.base_hp_override > 0 else ps.base.printed_hp()
		if int(pc.get("base_hp", 0)) > 0:
			hp_target = int(pc["base_hp"])
		hp_target += int(pc.get("base_hp_bonus", 0))
		if hp_target != ps.base.printed_hp():
			ps.base.mods.append({"h": hp_target - ps.base.printed_hp(), "dur": "permanent"})
		for cid in pc.get("deck", []):
			if not lib.has(cid):
				push_warning("Match: unknown card id %s skipped" % cid)
				continue
			var c := _new_inst(cid, i)
			c.zone = "deck"
			ps.deck.append(c)
		_shuffle(ps.deck)
		ps.base.damage = int(pc.get("base_damage", 0))
		ps.first_unit_experience = int(pc.get("first_unit_experience", 0))
		ps.first_unit_shield = int(pc.get("first_unit_shield", 0))
		ps.card_upgrades = pc.get("card_upgrades", {})
		ps.force_token = int(pc.get("start_force", 0)) > 0
		for pre in pc.get("preplaced", []):
			if not lib.has(pre["id"]):
				continue
			var u := _new_inst(pre["id"], i)
			_put_in_play(u, pre.get("arena", u.arena()), not pre.get("ready", true))
			u.flags.merge(pre.get("flags", {}), true)
		for cid in pc.get("bonus_hand", []):
			if lib.has(cid):
				var hc := _new_inst(cid, i)
				hc.zone = "hand"
				ps.hand.append(hc)
	tokens = Tokens.resolve(cfg.get("tokens", ["initiative"]))
	objective = Objective.create(cfg.get("objective", {"type": "standard"}))
	objective.setup(self)
	initiative = int(cfg.get("first", rng.randi_range(0, 1)))
	_log("%s has the initiative." % players[initiative].display_name)
	var seq: Array = []
	var pcs: Array = cfg["players"]
	for p in [initiative, 1 - initiative]:
		seq.append({"op": "_draw", "p": p, "n": rules.starting_hand + int(pcs[p].get("extra_hand", 0))})
	if rules.allow_mulligan:
		for p in [initiative, 1 - initiative]:
			seq.append({"op": "_mulligan", "p": p})
	for p in [initiative, 1 - initiative]:
		seq.append({"op": "_setup_resources", "p": p, "n": rules.starting_resources})
		if int(pcs[p].get("extra_resources", 0)) > 0:
			seq.append({"op": "_deck_to_resources", "p": p, "n": int(pcs[p]["extra_resources"])})
	seq.append({"op": "_start_action"})
	push_frame(seq, {"ctl": initiative})
	pump()


func _new_inst(cid: String, owner_idx: int) -> CardInst:
	var data := lib.get_card(cid)
	if data.is_empty():
		data = {"id": cid, "name": cid, "type": "unit", "power": 1, "hp": 1, "cost": 1, "text": "MISSING CARD DATA", "implemented": "manual"}
	var c := CardInst.new(_next_uid, cid, data, owner_idx)
	c.battle = weakref(self)
	_next_uid += 1
	by_uid[c.uid] = c
	return c


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# ---------------------------------------------------------------- queries

func opp(p: int) -> int:
	return 1 - p


func card(uid: int) -> CardInst:
	return by_uid.get(uid)


func all_units() -> Array:
	return players[0].units + players[1].units


func trigger_sources() -> Array:
	var result := all_units()
	for player in players:
		result.append(player.base)
		if player.leader and not player.leader.deployed:
			result.append(player.leader)
	for instance in by_uid.values():
		if instance.zone == "upgrade":
			result.append(instance)
	return result


func is_over() -> bool:
	return winner >= 0


func can_act(p: int) -> bool:
	return phase == "action" and winner < 0 and pending.is_empty() and frames.is_empty() and active == p


## Cost to play `c` for player p, including aspect penalties (+2 per missing icon).
func play_cost(p: int, c: CardInst, smuggle := false, opts := {}) -> int:
	if opts.get("free", false):
		return 0
	var cost := c.cost()
	var needed: Array = c.aspects()
	if smuggle:
		var sm := _kw_entry(c, "smuggle")
		cost = int(sm.get("v", cost))
		needed = sm.get("aspects", needed)
	elif opts.get("piloting", false):
		cost = int(c.data["pilot"]["cost"])
		needed = c.data["pilot"]["aspects"]
	if rules.aspect_penalties and not opts.get("ignore_aspects", false):
		var pool: Array = players[p].aspect_pool().duplicate()
		var ignore_one: bool = opts.get("ignore_one_basic_aspect", false)
		for a in needed:
			var i := pool.find(a)
			if i >= 0:
				pool.remove_at(i)
			elif ignore_one and a in ["vigilance", "command", "aggression", "cunning"]:
				ignore_one = false
			else:
				cost += 2
	return maxi(0, cost - int(opts.get("discount", 0)) - _play_discount(p, c, needed, opts))


func _play_discount(p: int, c: CardInst, aspects: Array, opts: Dictionary) -> int:
	var ps: PlayerState = players[p]
	var kind: String = "upgrade" if opts.get("piloting", false) else c.card_type()
	var record := {"kind": kind, "aspects": aspects, "traits": c.traits()}
	var total := 0
	var ctx := {"ctl": p, "src": c.uid}
	if not opts.get("piloting", false):
		for rule in c.abilities_with("own_discount"):
			if not Effects.condition(self, rule.get("condition", {}), ctx):
				continue
			var count := 1
			if rule.has("targets"):
				count = Effects.candidates(self, rule["targets"], ctx).size()
			elif rule.get("played", false):
				count = played_this_phase[p].size()
			elif rule.has("base_damage_divisor"):
				count = floori(float(ps.base.damage) / float(rule["base_damage_divisor"]))
			total += int(rule["n"]) * count
	var sources: Array = ps.units + [ps.base]
	if ps.leader and not ps.leader.deployed:
		sources.append(ps.leader)
	for source in sources:
		for rule in source.abilities_with("play_discount"):
			if not _matches_play(record, rule["filter"]):
				continue
			var first: String = rule.get("first", "")
			if first != "" and ps.played_for_cost.any(func(play):
				return (first == "round" or play["phase"] == phase_serial) and _matches_play(play, rule["filter"])):
				continue
			total += int(rule["n"])
	for rule in ps.next_play_discounts:
		if rule["phase"] == phase_serial and _matches_play(record, rule["filter"]):
			total += int(rule["n"])
	return total


static func _matches_play(record: Dictionary, filter: Dictionary) -> bool:
	return (filter["kind"] in ["card", record["kind"]]
		and (not filter.has("trait") or filter["trait"] in record["traits"])
		and (not filter.has("aspect") or filter["aspect"] in record["aspects"])
		and not filter.get("exclude_aspects", []).any(func(aspect): return aspect in record["aspects"]))


## Exploit X: defeat up to X friendly units, each lowers the cost by 2.
func exploit_discount(p: int, c: CardInst) -> int:
	var x := c.kw("exploit")
	if x <= 0:
		return 0
	var n := 0
	for u in players[p].units:
		if not u.is_leader():
			n += 1
	return 2 * mini(x, n)


func _kw_entry(c: CardInst, k: String) -> Dictionary:
	for e in c.data.get("keywords", []):
		if e.get("k", "") == k:
			return e
	return {}


func attack_targets(u: CardInst) -> Array:
	var out: Array = []
	if not u.in_play() or u.exhausted or u.flags.get("cannot_attack", false):
		return out
	for ability in u.abilities_with("constant"):
		if ability.get("flag") == "cannot_attack":
			return out
	var p := u.controller
	var enemies: Array = players[opp(p)].units_in(u.zone)
	var sab := u.has_kw("saboteur")
	var sentinels: Array = []
	if not sab:
		for e in enemies:
			if e.has_kw("sentinel"):
				sentinels.append(e)
	var pool := sentinels if sentinels.size() > 0 else enemies
	for e in pool:
		if e.has_kw("hidden") and e.entered_phase == phase_serial:
			continue
		if e.flags.get("untargetable", false):
			continue
		out.append(e.uid)
	var no_base := false
	for a in u.abilities_with("constant"):
		if a.get("flag", "") == "no_base_attack":
			no_base = true
	if sentinels.is_empty() and not no_base:
		out.append(players[opp(p)].base.uid)
	return out


func _has_upgrade_target(p: int, c: CardInst) -> bool:
	return Effects.upgrade_targets(self, p, c).size() > 0


func legal_actions(p: int) -> Array:
	var out: Array = []
	if not can_act(p):
		return out
	var ps: PlayerState = players[p]
	var res := ps.available()
	for c in ps.hand:
		if c.data.has("pilot") and play_cost(p, c, false, {"piloting": true}) <= res and not Effects.upgrade_targets(self, p, c, true).is_empty():
			out.append({"a": "pilot", "uid": c.uid})
		var t: String = c.card_type()
		if t == "unit" and not (arena_for(c) in rules.arenas):
			continue
		if t == "upgrade" and not _has_upgrade_target(p, c):
			continue
		if play_cost(p, c) - exploit_discount(p, c) <= res:
			out.append({"a": "play", "uid": c.uid})
	for r in ps.resources:
		if r.has_kw("smuggle") and play_cost(p, r, true) <= res:
			if r.card_type() == "unit" and not (arena_for(r) in rules.arenas):
				continue
			if r.card_type() == "upgrade" and not _has_upgrade_target(p, r):
				continue
			out.append({"a": "smuggle", "uid": r.uid})
	for u in ps.units:
		for t in attack_targets(u):
			out.append({"a": "attack", "uid": u.uid, "target": t})
		var acts: Array = u.abilities_with("action")
		for i in acts.size():
			if _can_pay_action(p, u, acts[i]):
				out.append({"a": "ability", "uid": u.uid, "idx": i})
	for source in trigger_sources():
		if source.controller != p or source.zone not in ["base", "upgrade"]:
			continue
		var actions: Array = source.abilities_with("action")
		for i in actions.size():
			if _can_pay_action(p, source, actions[i]):
				out.append({"a": "ability", "uid": source.uid, "idx": i})
	if ps.leader and not ps.leader.deployed:
		var acts := ps.leader.abilities_with("action")
		for i in acts.size():
			if _can_pay_action(p, ps.leader, acts[i]):
				out.append({"a": "ability", "uid": ps.leader.uid, "idx": i})
		# double-sided leaders with no unit side (e.g. Chancellor Palpatine // Darth Sidious) never deploy
		var has_unit_side := int(ps.leader.data.get("leader_unit", {}).get("hp", 0)) > 0
		if has_unit_side and not ps.leader.epic_used and ps.resources.size() >= int(ps.leader.data.get("epic_cost", 99)):
			out.append({"a": "deploy"})
	for tk in tokens:
		if _token_claimable(p, tk):
			out.append({"a": "claim", "token": tk["id"]})
	out.append({"a": "pass"})
	return out


func _can_pay_action(p: int, c: CardInst, ab: Dictionary) -> bool:
	if not _ability_available(c, ab) or (ab.get("epic", false) and c.epic_used):
		return false
	var cost: Dictionary = ab.get("cost", {})
	if cost.get("exhaust", false) and c.exhausted:
		return false
	if cost.has("other"):
		# Only costs the engine can actually pay are offered; others would make the action free.
		var extra := Effects.extra_cost(self, p, c, str(cost["other"]))
		if not extra.get("ok", false):
			return false
	var resources := int(cost.get("resources", 0))
	var effects: Array = ab.get("effects", [])
	if players[p].available() < resources or effects.is_empty():
		return false
	if not ab.get("epic", false) and resources == 0 and not cost.get("exhaust", false) and not cost.has("other"):
		var first: Dictionary = effects[0]
		if first.get("op") == "play_from_hand":
			return Effects.has_hand_play(self, p, first)
		if first.get("op") == "attack_with" and first["t"].get("can_attack", false) and not first.has("if"):
			return not Effects.candidates(self, first["t"], {"ctl": p, "src": c.uid}).is_empty()
	return true


func _token_claimable(p: int, tk: Dictionary) -> bool:
	if players[p].out_of_round or tokens_claimed.has(tk["id"]):
		return false
	var side: String = tk.get("side_claimable", "both")
	if side != "both" and side != SIDES[p]:
		return false
	if tk.get("target_required", false):
		for effect in tk.get("effects", []):
			if effect.has("t") and Effects.candidates(self, effect["t"], {"ctl": p}).is_empty():
				return false
	return true


# ---------------------------------------------------------------- actions

func do_action(a: Dictionary) -> bool:
	var p := active
	if not can_act(p):
		return false
	var legal := false
	for l in legal_actions(p):
		if _same_action(l, a):
			legal = true
			break
	if not legal:
		push_warning("illegal action %s" % [a])
		return false
	history.append({"p": p, "a": a})
	_last_actor = p
	var ps: PlayerState = players[p]
	match a["a"]:
		"pass":
			consecutive_passes += 1
			_log("%s passes." % ps.display_name)
			events.append({"t": "pass", "p": p})
			if rules.turn_mode == RuleSet.TurnMode.BURST:
				ps.turn_done = true
		"play":
			consecutive_passes = 0
			var pc := card(a["uid"])
			if exploit_discount(p, pc) > 0:
				push_frame([{"op": "_exploit", "uid": pc.uid}], {"ctl": p, "src": pc.uid, "name": pc.name(), "text": "Exploit"})
			else:
				_play_card(p, pc, false)
		"smuggle":
			consecutive_passes = 0
			_play_card(p, card(a["uid"]), true)
		"pilot":
			consecutive_passes = 0
			_play_card(p, card(a["uid"]), false, {"piloting": true})
		"attack":
			consecutive_passes = 0
			begin_attack(card(a["uid"]), card(a["target"]))
		"ability":
			consecutive_passes = 0
			_use_action_ability(p, card(a["uid"]), int(a["idx"]))
		"deploy":
			consecutive_passes = 0
			_deploy_leader(p)
		"claim":
			consecutive_passes = 0
			_claim_token(p, a["token"])
	_need_advance = true
	pump()
	return true


func _same_action(l: Dictionary, a: Dictionary) -> bool:
	for k in l:
		if not a.has(k) or str(a[k]) != str(l[k]):
			return false
	return true


func submit_choice(sel: Array) -> bool:
	if pending.is_empty():
		return false
	var opts: Array = pending.get("options", [])
	if sel.size() < int(pending.get("min", 0)) or sel.size() > int(pending.get("max", 1)):
		return false
	var seen := {}
	for s in sel:
		if s in seen or not (s in opts):
			return false
		seen[s] = true
	history.append({"choice": sel.duplicate()})
	var frame: Dictionary = frames.back()
	frame["ctx"]["_choice"] = sel.duplicate()
	pending = {}
	pump()
	return true


func take_events() -> Array:
	var e := events
	events = []
	return e


# ---------------------------------------------------------------- frames

func push_frame(effects: Array, ctx: Dictionary) -> void:
	frames.append({"effects": effects, "i": 0, "ctx": ctx})


func push_ability(src: CardInst, ab: Dictionary, extra := {}) -> void:
	if ab.get("effects", []).is_empty() or not _ability_available(src, ab):
		return
	var ctx := {"src": src.uid, "ctl": src.controller, "text": ab.get("text", ""), "name": src.name()}
	ctx.merge(extra, true)
	_record_ability_use(src, ab)
	push_frame(ab["effects"], ctx)


func _ability_available(source: CardInst, ability: Dictionary) -> bool:
	if ability.get("requires_coordinate", false) and players[source.controller].units.size() < 3:
		return false
	if not ability.has("limit"):
		return true
	var key := _ability_limit_key(ability)
	var use: Dictionary = source.ability_uses.get(key, {})
	return use.get("period", -1) != _ability_limit_period(ability) or use["count"] < int(ability["limit"])


func _ability_limit_period(ability: Dictionary) -> int:
	match ability["limit_period"]:
		"phase": return phase_serial
		"round": return round_num
	return 0


func _ability_limit_key(ability: Dictionary) -> String:
	return "%s/%s/%s" % [ability["limit_period"], ability.get("grant_source", 0), ability["text"]]


func _record_ability_use(source: CardInst, ability: Dictionary) -> void:
	if not ability.has("limit"):
		return
	var key := _ability_limit_key(ability)
	var period := _ability_limit_period(ability)
	var previous: Dictionary = source.ability_uses.get(key, {})
	var count := int(previous.get("count", 0)) if previous.get("period") == period else 0
	source.ability_uses[key] = {"period": period, "count": count + 1}


func player_trigger(p: int, trigger: String, extra := {}) -> void:
	for source in trigger_sources():
		if source.controller == p:
			for ability in source.abilities_with(trigger):
				push_ability(source, ability, extra)


## Runs queued work until a choice is needed or nothing is left.
func pump() -> void:
	var guard := 0
	while winner < 0 and pending.is_empty():
		guard += 1
		if guard > 5000:
			push_error("Match.pump: runaway loop")
			return
		if not frames.is_empty():
			var fr: Dictionary = frames.back()
			if fr["i"] >= fr["effects"].size():
				frames.pop_back()
				continue
			var eff: Dictionary = fr["effects"][fr["i"]]
			var r := Effects.exec(self, eff, fr["ctx"])
			if r == Effects.SUSPEND:
				return
			fr["i"] += 1
			continue
		if _state_based():
			continue
		if _need_advance:
			_need_advance = false
			_advance()
			continue
		return


# ---------------------------------------------------------------- flow

func _advance() -> void:
	if phase != "action":
		return
	if rules.turn_mode == RuleSet.TurnMode.BURST:
		var p := _last_actor
		if players[p].out_of_round:
			players[p].turn_done = true
		if players[0].turn_done and players[1].turn_done:
			_end_action_phase()
		elif players[p].turn_done:
			active = opp(p)
		return
	var nxt := opp(_last_actor)
	for _i in 4:
		if consecutive_passes >= 2:
			_end_action_phase()
			return
		if players[nxt].out_of_round:
			consecutive_passes += 1
			events.append({"t": "pass", "p": nxt, "auto": true})
			nxt = opp(nxt)
			continue
		active = nxt
		events.append({"t": "turn", "p": active})
		return
	_end_action_phase()


func start_action_phase() -> void:
	phase = "action"
	phase_serial += 1
	active = initiative
	consecutive_passes = 0
	defeated_this_phase = [0, 0]
	attacked_with = [[], []]
	played_this_phase = [[], []]
	defeated_cards_this_phase = [[], []]
	for ps in players:
		ps.out_of_round = false
		ps.turn_done = false
	tokens_claimed.clear()
	events.append({"t": "phase", "phase": "action", "round": round_num})
	_log("— Round %d: action phase —" % round_num)
	objective.on_action_start(self)
	for u in trigger_sources():
		for ab in u.abilities_with("action_start"):
			push_ability(u, ab)
	events.append({"t": "turn", "p": active})


func _end_action_phase() -> void:
	_expire("phase")
	phase = "regroup"
	phase_serial += 1
	events.append({"t": "phase", "phase": "regroup", "round": round_num})
	_log("— Regroup phase —")
	var seq: Array = []
	seq.append({"op": "_regroup_triggers"})
	for p in [initiative, opp(initiative)]:
		seq.append({"op": "_draw", "p": p, "n": rules.regroup_draw})
	for p in [initiative, opp(initiative)]:
		for _i in rules.regroup_resource:
			seq.append({"op": "_regroup_resource", "p": p})
	seq.append({"op": "_ready_all"})
	seq.append({"op": "_new_round"})
	push_frame(seq, {"ctl": initiative})


func end_round() -> void:
	_expire("phase")
	_expire("round")
	objective.on_round_end(self)
	if winner >= 0:
		return
	round_num += 1
	for ps in players:
		ps.played_for_cost.clear()
	start_action_phase()


func _expire(dur: String) -> void:
	for u in all_units() + [players[0].base, players[1].base]:
		var keep: Array = []
		for m in u.mods:
			if m.get("dur", "") != dur:
				keep.append(m)
		u.mods = keep


func _state_based() -> bool:
	var acted := false
	for u in all_units():
		if u.in_play() and u.damage >= u.max_hp():
			defeat(u)
			acted = true
	var dead := [players[0].base_remaining() <= 0, players[1].base_remaining() <= 0]
	if dead[0] or dead[1]:
		set_winner(2 if dead[0] and dead[1] else (1 if dead[0] else 0), "base destroyed")
		return true
	var w := objective.check(self)
	if w >= 0:
		set_winner(w, objective.describe())
		return true
	return acted


func set_winner(w: int, why := "") -> void:
	if winner >= 0:
		return
	winner = w
	phase = "over"
	pending = {}
	frames.clear()
	events.append({"t": "win", "p": w, "why": why})
	_log("Game over: %s (%s)" % ["draw" if w == 2 else (players[w].display_name + (" win" if players[w].display_name == "You" else " wins")), why])


# ---------------------------------------------------------------- zones

func draw(p: int, n: int) -> void:
	var ps: PlayerState = players[p]
	var drawn := 0
	for _i in n:
		if ps.deck.is_empty():
			if rules.deck_out_damage > 0:
				_log("%s cannot draw and takes %d damage." % [ps.display_name, rules.deck_out_damage])
				deal_damage(ps.base, rules.deck_out_damage, null)
			continue
		var c: CardInst = ps.deck.pop_front()
		c.zone = "hand"
		ps.hand.append(c)
		events.append({"t": "draw", "p": p, "uid": c.uid})
		drawn += 1
	if drawn > 0:
		on_cards_drawn(p)


func on_cards_drawn(p: int) -> void:
	player_trigger(p, "cards_drawn")
	if phase == "action":
		player_trigger(p, "action_cards_drawn")


func move_to_resources(p: int, c: CardInst, exhausted := false) -> void:
	_remove_from_zones(c)
	c.zone = "resource"
	c.exhausted = exhausted
	c.controller = p
	players[p].resources.append(c)
	events.append({"t": "resource", "p": p, "uid": c.uid})


func _remove_from_zones(c: CardInst) -> void:
	for ps in players:
		for arr in [ps.hand, ps.deck, ps.discard, ps.resources, ps.units]:
			arr.erase(c)


func pay(p: int, amount: int) -> void:
	var left := amount
	# Spend smuggle-able resources last so they stay available.
	var order: Array = players[p].resources.duplicate()
	order.sort_custom(func(a, b): return int(a.has_kw("smuggle")) < int(b.has_kw("smuggle")))
	for r in order:
		if left <= 0:
			break
		if not r.exhausted:
			r.exhausted = true
			left -= 1
	if left > 0 and players[p].credits > 0:
		var spent := mini(left, players[p].credits)
		players[p].credits -= spent
		left -= spent
		events.append({"t": "credits", "p": p, "n": -spent})
	if amount > 0:
		events.append({"t": "pay", "p": p, "n": amount})


## Where a card's unit enters play under this ruleset. In One Lane every unit
## (ground or space) fights in the single shared lane.
func arena_for(c: CardInst, printed := "") -> String:
	var a := printed if printed != "" or c == null else c.arena()
	if rules.single_lane:
		return str(rules.arenas[0])
	return a


func _put_in_play(u: CardInst, arena: String, exhausted := true) -> void:
	arena = arena_for(u, arena)
	_remove_from_zones(u)
	u.flags.erase("return_control_at_regroup")
	u.flags.erase("skip_regroup_ready")
	u.entry_serial += 1
	u.zone = arena
	u.exhausted = exhausted
	u.entered_phase = phase_serial
	u.damage = 0 if not u.deployed else u.damage
	players[u.controller].units.append(u)
	events.append({"t": "enter", "uid": u.uid, "p": u.controller})
	if phase != "setup" and u.arena() == "ground" and not u.is_leader():
		for source in trigger_sources():
			for ability in source.abilities_with("nonleader_ground_enters"):
				push_ability(source, ability, {"subject": u.uid})


## opts (from abilities like "Play a unit from your hand. It costs 1 less."):
##   discount, ignore_aspects, ready, gain_kw
func _play_card(p: int, c: CardInst, smuggle: bool, opts := {}) -> void:
	var cost := play_cost(p, c, smuggle, opts)
	var ps: PlayerState = players[p]
	var piloting: bool = opts.get("piloting", false)
	var record := {"kind": "upgrade" if piloting else c.card_type(), "traits": c.traits(),
		"aspects": c.data["pilot"]["aspects"] if piloting else (_kw_entry(c, "smuggle").get("aspects", c.aspects()) if smuggle else c.aspects()),
		"phase": phase_serial}
	ps.played_for_cost.append(record)
	for rule in ps.next_play_discounts:
		if rule["phase"] == phase_serial and _matches_play(record, rule["filter"]):
			rule["uses"] -= 1
	ps.next_play_discounts = ps.next_play_discounts.filter(func(rule):
		return rule["phase"] == phase_serial and rule["uses"] > 0)
	played_this_phase[p].append(c)
	var from_resource: bool = smuggle or opts.get("from_resource", false)
	# A ready resource being played may pay for itself before leaving the zone.
	if from_resource and not c.exhausted and cost > 0:
		c.exhausted = true
		pay(p, cost - 1)
	else:
		pay(p, cost)
	if from_resource:
		ps.resources.erase(c)
		if not ps.deck.is_empty():
			move_to_resources(p, ps.deck.pop_front(), true)
	else:
		ps.hand.erase(c)
	events.append({"t": "play", "p": p, "uid": c.uid})
	_log("%s plays %s." % [ps.display_name, c.title()])
	if opts.get("piloting", false) or c.card_type() == "upgrade":
		c.zone = "limbo"
		push_frame([{"op": "_attach", "uid": c.uid}], {"src": c.uid, "ctl": p,
			"played": true, "smuggle": smuggle, "from_resource": from_resource,
			"piloting": opts.get("piloting", false)})
		return
	match c.card_type():
		"unit":
			_enforce_unique(p, c)
			_put_in_play(c, c.arena(), not opts.get("ready", false))
			if opts.has("gain_kw"):
				c.mods.append({"kw": opts["gain_kw"], "v": 1, "dur": "phase"})
			_on_card_played(p, c, smuggle, from_resource)
			_on_unit_enters(c, "when_played")
		"event":
			c.zone = "discard"
			ps.discard.append(c)
			_on_card_played(p, c, smuggle, from_resource)
			for ab in c.abilities():
				if ab.get("trigger", "") in ["event", "when_played"]:
					push_ability(c, ab)
		_:
			c.zone = "discard"
			ps.discard.append(c)


func _on_card_played(p: int, played: CardInst, smuggle: bool, from_resource: bool) -> void:
	var ctx := {"subject": played.uid, "it": played.uid}
	if played.card_type() == "event":
		player_trigger(opp(p), "opponent_event", {"subject_player": p, "subject": played.uid})
	for source in trigger_sources():
		if source.controller != p:
			continue
		for ability in source.abilities_with("friendly_card_played"):
			var filter: Dictionary = ability["filter"]
			var kind: String = filter["kind"]
			if kind != "card" and kind != played.card_type():
				continue
			if filter.get("other", false) and played == source:
				continue
			if (filter.get("smuggle", false) and not smuggle) or (filter.get("from_resource", false) and not from_resource):
				continue
			if not Effects.matches(self, played, filter, {"ctl": p, "src": source.uid}):
				continue
			push_ability(source, ability, ctx)
	if smuggle:
		for ability in played.abilities_with("when_smuggled"):
			push_ability(played, ability, {"ctl": p})


func _enforce_unique(p: int, c: CardInst) -> void:
	if not c.unique():
		return
	for u in trigger_sources():
		if u.controller != p or (not u.in_play() and u.zone != "upgrade"):
			continue
		if u.flags.get("protected", false):
			continue  # scenario units (e.g. unconscious Luke) are outside the unique rule
		if u.id == c.id or (u.unique() and u.title() == c.title()):
			_log("Unique rule: %s is defeated." % u.title())
			defeat(u)


func _on_unit_enters(u: CardInst, trigger: String) -> void:
	for ability in u.abilities_with("constant"):
		if ability.get("flag") == "enters_ready":
			u.exhausted = false
	if u.has_kw("shielded"):
		attach_token(u, "shield")
	var ps: PlayerState = players[u.controller]
	if ps.first_unit_experience > 0 and trigger == "when_played":
		ps.first_unit_experience -= 1
		attach_token(u, "experience")
	if ps.first_unit_shield > 0 and trigger == "when_played":
		ps.first_unit_shield -= 1
		attach_token(u, "shield")
	for kind in ps.card_upgrades.get(u.id, []):
		attach_token(u, kind)
	# Ambush is pushed first so When Played resolves before the ambush attack.
	if u.has_kw("support"):
		push_frame([{"op": "support", "t": {"s": "choose", "kind": "unit", "side": "friendly", "other": true, "ready": true, "can_attack": true, "opt": true}, "support_abilities": u.abilities().duplicate(true), "support_keywords": u.keyword_list().duplicate(true)}], {"src": u.uid, "ctl": u.controller})
	if u.has_kw("ambush") and trigger == "when_played":
		push_frame([{"op": "_ambush", "uid": u.uid}], {"src": u.uid, "ctl": u.controller})
	for ab in u.abilities_with(trigger):
		push_ability(u, ab)
	for other in players[u.controller].units:
		if other != u:
			for ab in other.abilities_with("friendly_unit_played"):
				push_ability(other, ab, {"it": u.uid})


func attach_upgrade(up: CardInst, target: CardInst, play_ctx := {}) -> void:
	if play_ctx.get("played", false):
		_enforce_unique(play_ctx.get("ctl", up.controller), up)
	_remove_from_zones(up)
	up.zone = "upgrade"
	up.attached_to = target
	up.controller = play_ctx.get("ctl", up.controller)
	target.upgrades.append(up)
	events.append({"t": "upgrade", "uid": up.uid, "on": target.uid})
	if play_ctx.get("played", false):
		_on_card_played(play_ctx["ctl"], up, play_ctx["smuggle"], play_ctx["from_resource"])
		if target.controller == play_ctx["ctl"]:
			for ability in target.abilities_with("upgrade_played_here"):
				push_ability(target, ability, {"subject": up.uid})
	var ctx := {"ctl": play_ctx.get("ctl", up.controller), "subject": target.uid, "it": target.uid}
	for ab in up.abilities_with("when_attached"):
		push_ability(up, ab, ctx)
	var trigger := "when_played_upgrade" if up.is_pilot_upgrade() else "when_played"
	for ab in up.abilities_with(trigger):
		push_ability(up, ab, ctx)


func attach_token(target: CardInst, key: String) -> void:
	if not target.in_play():
		return
	var tid := lib.token_id(key)
	var t := _new_inst(tid, target.controller) if tid != "" else _new_inst("TOKEN_" + key, target.controller)
	if tid == "":
		t.data = {"name": key.capitalize(), "type": "token_upgrade", "power": 1 if key == "experience" else 0, "hp": 1 if key == "experience" else 0}
	t.is_token = true
	t.zone = "upgrade"
	t.attached_to = target
	target.upgrades.append(t)
	events.append({"t": "token", "kind": key, "on": target.uid})


func create_unit_token(p: int, key: String) -> CardInst:
	var tid := lib.token_id(key)
	if tid == "":
		return null
	var tok_arena = lib.get_card(tid).get("arena")
	var arena: String = tok_arena if tok_arena else "ground"
	if not (arena_for(null, arena) in rules.arenas):
		return null  # e.g. a TIE Fighter token in a ground-only Quick game
	var t := _new_inst(tid, p)
	t.is_token = true
	_put_in_play(t, arena, true)
	if t.has_kw("shielded"):
		attach_token(t, "shield")
	return t


func summon(p: int, cid: String, ready := false) -> CardInst:
	var u := _new_inst(cid, p)
	_put_in_play(u, u.arena(), not ready)
	_on_unit_enters(u, "when_played")
	return u


func deal_damage(target: CardInst, n: int, source: CardInst, unpreventable := false) -> int:
	if n <= 0 or target == null:
		return 0
	if target.in_play():
		for up in target.upgrades:
			if not unpreventable and up.data.get("name", "") == "Shield":
				defeat(up)
				return 0
	elif target.zone != "base":
		return 0
	elif not unpreventable and n >= 5:
		for up in target.upgrades:
			if up.abilities_with("constant").any(func(a): return a.get("flag") == "base_damage_shield"):
				defeat(up)
				draw(up.controller, 1)
				events.append({"t": "shield_break", "uid": target.uid, "remaining": 0})
				return 0
	target.damage += n
	events.append({"t": "damage", "uid": target.uid, "n": n, "src": source.uid if source else 0})
	if target.zone == "base":
		player_trigger(target.controller, "own_base_damaged")
	elif target.remaining_hp() > 0:
		for ability in target.abilities_with("survived_damage"):
			push_ability(target, ability, {"trigger_amount": n})
	return n


func heal(target: CardInst, n: int) -> int:
	var h := mini(n, target.damage)
	if h > 0:
		target.damage -= h
		events.append({"t": "heal", "uid": target.uid, "n": h})
		if target.in_play():
			for ability in target.abilities_with("unit_healed"):
				push_ability(target, ability, {"trigger_amount": h})
	return h


func defeat(u: CardInst, departing_host := false) -> void:
	if u.zone == "upgrade":
		var host := u.attached_to
		var defeated_abilities := u.abilities_with("when_defeated")
		if host:
			host.upgrades.erase(u)
			if not departing_host:
				if u.data.get("name", "") == "Shield":
					events.append({"t": "shield_break", "uid": host.uid, "remaining": host.shield_count()})
				events.append({"t": "buff", "uid": host.uid})
		u.attached_to = null
		u.zone = "removed" if u.is_token else "discard"
		if u.is_token:
			by_uid.erase(u.uid)
		else:
			players[u.owner].discard.append(u)
		for ability in defeated_abilities:
			push_ability(u, ability)
		player_trigger(u.controller, "friendly_upgrade_defeated")
		return
	if not u.in_play():
		return
	var bounties := u.abilities_with("bounty")
	var abil := u.abilities_with("when_defeated")
	_defeat_attached_upgrades(u)
	_rescue_captives(u)
	var p := u.controller
	var ps: PlayerState = players[p]
	if attack.get("t", 0) == u.uid:
		attack["defender_defeated"] = true
	ps.units.erase(u)
	defeated_this_phase[p] += 1
	defeated_cards_this_phase[p].append(u)
	events.append({"t": "defeat", "uid": u.uid, "p": p})
	_log("%s is defeated." % u.title())
	u.mods.clear()
	if u.is_leader():
		u.deployed = false
		u.zone = "leader"
		u.exhausted = true
		u.damage = 0
	elif u.is_token:
		u.zone = "removed"
	else:
		u.zone = "discard"
		u.damage = 0
		players[u.owner].discard.append(u)
	if u.flags.get("protected", false):
		objective.on_protected_lost(self, u)
	for source in trigger_sources():
		if source.controller == opp(p):
			for ability in source.abilities_with("enemy_unit_defeated"):
				push_ability(source, ability, {"subject_player": p})
		else:
			for ability in source.abilities_with("friendly_unit_defeated"):
				push_ability(source, ability, {"subject": u.uid})
	for ab in abil:
		push_ability(u, ab, {"lki_arena": u.arena()})
	for bounty in bounties:
		push_ability(u, bounty, {"ctl": opp(p)})


func _defeat_attached_upgrades(host: CardInst) -> void:
	for upgrade in host.upgrades.duplicate():
		defeat(upgrade, true)


func take_control(unit: CardInst, player: int) -> bool:
	if not unit.in_play() or unit.is_leader() or unit.controller == player:
		return false
	if unit.abilities_with("constant").any(func(a): return a.get("flag") == "cannot_take_control"):
		return false
	players[unit.controller].units.erase(unit)
	unit.controller = player
	_enforce_unique(player, unit)
	players[player].units.append(unit)
	if attack.get("a", 0) == unit.uid or attack.get("t", 0) == unit.uid:
		attack["combat_cancelled"] = true
	events.append({"t": "control", "uid": unit.uid, "p": player})
	return true


func return_to_hand(u: CardInst) -> void:
	if u.is_leader() or u.is_token:
		defeat(u)
		return
	_rescue_captives(u)
	if u.attached_to:
		u.attached_to.upgrades.erase(u)
		u.attached_to = null
	_defeat_attached_upgrades(u)
	var ps: PlayerState = players[u.controller]
	ps.units.erase(u)
	u.mods.clear()
	u.damage = 0
	u.exhausted = false
	u.zone = "hand"
	u.controller = u.owner
	players[u.owner].hand.append(u)
	events.append({"t": "bounce", "uid": u.uid})


func capture(guard: CardInst, captive: CardInst) -> bool:
	if not guard or not captive or not guard.in_play() or not captive.in_play() or captive.is_leader() or guard.controller == captive.controller or guard.zone != captive.zone:
		return false
	var controller := captive.controller
	var bounties := captive.abilities_with("bounty")
	_defeat_attached_upgrades(captive)
	_rescue_captives(captive)
	_remove_from_zones(captive)
	captive.mods.clear()
	captive.damage = 0
	if captive.is_token:
		captive.zone = "removed"
		by_uid.erase(captive.uid)
		events.append({"t": "bounce", "uid": captive.uid})
		for bounty in bounties:
			push_ability(captive, bounty, {"ctl": opp(controller)})
		return true
	captive.zone = "captured"
	captive.flags["guard"] = guard.uid
	var held: Array = guard.flags.get("captives", [])
	held.append(captive.uid)
	guard.flags["captives"] = held
	events.append({"t": "bounce", "uid": captive.uid})
	_log("%s captures %s." % [guard.name(), captive.name()])
	for bounty in bounties:
		push_ability(captive, bounty, {"ctl": opp(controller)})
	return true


func _rescue_captives(guard: CardInst) -> void:
	var held: Array = guard.flags.get("captives", []).duplicate()
	guard.flags.erase("captives")
	for uid in held:
		var captive := card(uid)
		if not captive or captive.zone != "captured":
			continue
		captive.flags.erase("guard")
		captive.controller = captive.owner
		_put_in_play(captive, captive.arena(), true)
		_log("%s is rescued." % captive.name())


func exhaust(u: CardInst, v := true) -> void:
	if u.exhausted != v:
		u.exhausted = v
		events.append({"t": "exhaust" if v else "ready", "uid": u.uid})


# ---------------------------------------------------------------- combat

func begin_attack(a: CardInst, t: CardInst) -> void:
	var p := a.controller
	exhaust(a)
	attack = {"a": a.uid, "t": t.uid}
	attacked_with[p].append(a.uid)
	_log("%s attacks %s." % [a.title(), t.title() if t.zone != "base" else "the enemy base"])
	push_frame([{"op": "_before_combat"}, {"op": "_combat"}, {"op": "_attack_end"}], {"src": a.uid, "ctl": p})
	for ability in t.abilities_with("when_attacked"):
		push_ability(t, ability, {"it": a.uid})
	# "When a friendly <Trait> unit attacks" on the attacker's base and other units
	for src in [players[p].base] + players[p].units:
		for ab in src.abilities_with("friendly_attack"):
			if a.has_trait(str(ab.get("trait", ""))):
				push_ability(src, ab, {"it": a.uid})
	var restore := a.kw("restore")
	if restore > 0:
		heal(players[p].base, restore)
	for ab in a.abilities_with("on_attack"):
		push_ability(a, ab, {"attack": true})


func resolve_combat() -> void:
	if attack.is_empty() or attack.get("combat_cancelled", false):
		return
	var a := card(attack["a"])
	var t := card(attack["t"])
	if a == null or not a.in_play():
		return
	if t:
		events.append({"t": "attack", "a": a.uid, "target": t.uid})
	if attack.get("defender_defeated", false):
		_overwhelm(a, a.power(true), events.size())
		return
	if t == null:
		return
	if t.zone == "base":
		var n := deal_damage(t, a.power(true), a)
		if n > 0:
			player_trigger(t.controller, "enemy_combat_damage_to_base")
			for ab in a.abilities_with("base_damage"):
				push_ability(a, ab)
		return
	if not t.in_play():
		return
	if a.has_kw("saboteur"):
		for up in t.upgrades.duplicate():
			if up.data.get("name", "") == "Shield":
				defeat(up)
	var ap := a.power(true)
	var dp := t.power(false)
	var t_rem := t.remaining_hp()
	var t_shielded := t.shield_count() > 0
	deal_damage(t, ap, a)
	var follow_through_index := events.size()
	var early_damage := false
	for ability in a.abilities_with("constant"):
		if ability.get("flag") == "first_strike":
			early_damage = true
	if early_damage and t.damage >= t.max_hp():
		defeat(t)
	else:
		deal_damage(a, dp, t)
	if not t_shielded:
		_overwhelm(a, ap - t_rem, follow_through_index)


func _overwhelm(attacker: CardInst, excess: int, event_index: int) -> void:
	if excess <= 0 or not attacker.has_kw("overwhelm"):
		return
	var base: CardInst = players[opp(attacker.controller)].base
	# Animate the follow-through before the attacker's retaliation reaction.
	events.insert(event_index, {"t": "overwhelm", "a": attacker.uid, "target": base.uid})
	deal_damage(base, excess, attacker)


func end_attack() -> void:
	if attack.is_empty():
		return
	var a := card(attack["a"])
	var defender := card(attack["t"])
	var end_abilities: Array = a.abilities_with("attack_end") if a and a.in_play() else []
	attack = {}
	_expire("attack")
	if a and a.in_play():
		for ab in end_abilities:
			push_ability(a, ab)
	for participant in [a, defender]:
		if participant and participant.in_play():
			for upgrade in participant.upgrades:
				for ability in upgrade.abilities_with("host_combat_end"):
					push_ability(upgrade, ability)


func keyword_suppressed(target: CardInst, keyword: String) -> bool:
	for source in players[opp(target.controller)].units:
		for ability in source.abilities_with("constant"):
			if keyword in ability.get("suppress_keywords", []):
				return true
	return false


# ---------------------------------------------------------------- leaders, abilities, tokens

func _use_action_ability(p: int, c: CardInst, idx: int) -> void:
	var ab: Dictionary = c.abilities_with("action")[idx]
	var cost: Dictionary = ab.get("cost", {})
	if ab.get("epic", false):
		c.epic_used = true
	if cost.get("exhaust", false):
		exhaust(c)
	pay(p, int(cost.get("resources", 0)))
	var other := str(cost.get("other", ""))
	events.append({"t": "ability", "uid": c.uid})
	_log("%s uses %s's action." % [players[p].display_name, c.name()])
	if other != "":
		_record_ability_use(c, ab)
		var extra := Effects.extra_cost(self, p, c, other)
		var seq: Array = extra.get("ops", []).duplicate()
		seq.append({"op": "_reset_ctx"})
		seq.append_array(ab.get("effects", []))
		push_frame(seq, {"src": c.uid, "ctl": p, "text": ab.get("text", ""), "name": c.name()})
		return
	push_ability(c, ab)


func _deploy_leader(p: int) -> void:
	var l: CardInst = players[p].leader
	l.deployed = true
	l.epic_used = true
	var was_exhausted := l.exhausted
	# Scenario stand-in until Piloting is automated: a leader whose printed arena
	# isn't used by this node (e.g. Luke, Hero of Yavin in the all-space trench run)
	# deploys into the node's first arena.
	var arena := l.arena() if l.arena() in rules.arenas else str(rules.arenas[0])
	_put_in_play(l, arena, was_exhausted)
	events.append({"t": "deploy", "uid": l.uid, "p": p})
	_log("%s deploys %s!" % [players[p].display_name, l.title()])
	for source in trigger_sources():
		if source.controller == p:
			for ability in source.abilities_with("friendly_leader_deployed"):
				push_ability(source, ability, {"subject": l.uid, "it": l.uid})
	_on_unit_enters(l, "when_deployed")
	var plots: Array = []
	for resource in players[p].resources:
		if resource.has_kw("plot"):
			plots.append(resource.uid)
	if not plots.is_empty():
		push_frame([{"op": "_plot", "ids": plots}], {"ctl": p})


func _claim_token(p: int, token_id: String) -> void:
	var tk: Dictionary = {}
	for t in tokens:
		if t["id"] == token_id:
			tk = t
	tokens_claimed[token_id] = p
	players[p].out_of_round = true
	if token_id == "initiative":
		initiative = p
		for source in trigger_sources():
			if source.controller == p:
				for ability in source.abilities_with("when_claiming_initiative"):
					push_ability(source, ability)
	events.append({"t": "claim", "p": p, "token": token_id})
	_log("%s claims %s." % [players[p].display_name, tk.get("name", token_id)])
	if not tk.get("effects", []).is_empty():
		push_frame(tk["effects"], {"ctl": p, "text": tk.get("name", ""), "src": players[p].base.uid})


func _log(s: String) -> void:
	log_lines.append(s)
	events.append({"t": "log", "text": s})


func continuous_bonus(target: CardInst, field: String, keyword: String) -> int:
	var total := 0
	var sources := all_units()
	for player in players:
		if player.leader and not player.leader.deployed:
			sources.append(player.leader)
		sources.append(player.base)
	for source in sources:
		for ability in source.abilities_with("continuous"):
			if ability.get("target", "self") == "self":
				if source != target:
					continue
			elif source.controller != target.controller:
				continue
			if ability.get("other", false) and source == target:
				continue
			var filter_trait: String = ability.get("trait", "")
			match filter_trait:
				"damaged":
					if target.damage <= 0:
						continue
				"unique":
					if not target.unique():
						continue
				"leader":
					if not target.is_leader():
						continue
				"token":
					if not target.is_token:
						continue
				"upgraded":
					if target.upgrades.is_empty():
						continue
				"ground", "space":
					if target.arena() != filter_trait:
						continue
				_:
					if filter_trait != "" and not target.has_trait(filter_trait) and not filter_trait in target.aspects():
						continue
			var condition: Dictionary = ability.get("condition", {})
			if condition.get("initiative", false) and initiative != source.controller:
				continue
			if condition.get("upgraded", false) and source.upgrades.is_empty():
				continue
			if condition.get("damaged", false) and source.damage <= 0:
				continue
			if condition.get("undamaged", false) and source.damage > 0:
				continue
			if condition.get("ready", false) and source.exhausted:
				continue
			var ps: PlayerState = players[source.controller]
			if ps.resources.size() < int(condition.get("resources_min", 0)):
				continue
			if ps.units.size() < int(condition.get("units_min", 0)):
				continue
			if field == "kw":
				if ability.get("kw") == keyword:
					total += int(ability.get("v", 1))
				total += int(ability.get("keywords", {}).get(keyword, 0))
			else:
				var multiplier := 1
				match ability.get("scale_by", ""):
					"resources": multiplier = ps.resources.size()
					"hand": multiplier = ps.hand.size()
				total += int(ability.get(field, 0)) * multiplier
	return total
