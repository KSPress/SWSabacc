class_name Objective
extends RefCounted
## Node objectives (spec 5.5) as plug-ins. Player 0 is always the human/hero side.
## Subclasses override the hooks they need; check() returns the winner index or -1.

var type := "standard"
var params: Dictionary = {}


static func create(cfg: Dictionary) -> Objective:
	var o: Objective
	match cfg.get("type", "standard"):
		"survive_n":
			o = SurviveRounds.new()
		"defend_unit":
			o = DefendUnit.new()
		"duel":
			o = Duel.new()
		"hunt":
			o = Hunt.new()
		"reinforcement_hunt":
			o = ReinforcementHunt.new()
		"hangar_duel":
			o = HangarDuel.new()
		"attrition":
			o = Attrition.new()
		_:
			o = Objective.new()
	o.type = cfg.get("type", "standard")
	o.params = cfg.get("params", {})
	return o


func setup(_m: Match) -> void:
	pass


func on_action_start(_m: Match) -> void:
	pass


func on_round_end(_m: Match) -> void:
	pass


func on_protected_lost(_m: Match, _u: CardInst) -> void:
	pass


func check(_m: Match) -> int:
	return -1


func enemy_base_damage_allowed() -> bool:
	return not params.get("objective_only", false)


func describe() -> String:
	return "Destroy the enemy base."


func tracker(_m: Match) -> String:
	return "Destroy the enemy base"


func reward_multiplier() -> float:
	return float(params.get("reward_mult", 1.0))


class SurviveRounds extends Objective:
	func on_action_start(m: Match) -> void:
		for wave in params.get("reinforcements", []):
			if int(wave["round"]) == m.round_num:
				m._log("Imperial reinforcements arrive.")
				for id in wave["cards"]:
					if m.lib.has(id):
						var unit := m._new_inst(id, 1)
						m._put_in_play(unit, unit.arena(), not wave.get("ready", false))

	func on_round_end(m: Match) -> void:
		if m.round_num >= int(params.get("rounds", 4)) and m.players[0].base_remaining() > 0:
			m.set_winner(0, "survived")

	func describe() -> String:
		return "Survive %d rounds." % int(params.get("rounds", 4))

	func tracker(m: Match) -> String:
		return "Survive: round %d / %d" % [m.round_num, int(params.get("rounds", 4))]


class DefendUnit extends Objective:
	var lost := false
	var protected_unit: CardInst

	func setup(m: Match) -> void:
		var id: String = params.get("protect_unit", "")
		if id == "":
			return
		for ally in m.players[0].units:
			if ally.id == id:
				protected_unit = ally
				break
		if not protected_unit:
			protected_unit = m._new_inst(id, 0)
			m._put_in_play(protected_unit, protected_unit.arena(), true)
		protected_unit.flags.merge({"protected": true, "cannot_attack": true, "cannot_ready": true}, true)
		protected_unit.exhausted = true
		if params.has("protect_hp"):
			protected_unit.mods.append({"h": int(params["protect_hp"]) - protected_unit.printed_hp(), "dur": "permanent"})

	func on_protected_lost(_m: Match, _u: CardInst) -> void:
		lost = true

	func on_action_start(m: Match) -> void:
		# The protected unit stays unconscious (exhausted) — it can't help.
		for u in m.players[0].units:
			if u.flags.get("protected", false):
				u.exhausted = true

	func on_round_end(m: Match) -> void:
		if check(m) < 0 and m.players[0].base_remaining() > 0 and m.round_num >= int(params.get("rounds", 3)):
			m.set_winner(0, "protected unit survived")

	func check(_m: Match) -> int:
		if lost or not protected_unit or not protected_unit.in_play():
			return 1
		return 1 if protected_unit.controller != 0 or protected_unit.remaining_hp() <= 0 else -1

	func describe() -> String:
		return "Keep %s alive for %d rounds." % [params.get("name", "the protected unit"), int(params.get("rounds", 3))]

	func tracker(m: Match) -> String:
		return "Protect %s · Round %d/%d" % [params.get("name", "ally"), m.round_num, int(params.get("rounds", 3))]


class Duel extends Objective:
	var ally: CardInst
	var opponent: CardInst
	var lost := false
	var target_defeated := false

	func setup(m: Match) -> void:
		for unit in m.players[0].units:
			if unit.id == params.get("ally"):
				ally = unit
				ally.flags["protected"] = true
				break
		for unit in m.players[1].units:
			if unit.id == params.get("target"):
				opponent = unit
				opponent.flags["objective_target"] = true
				break

	func on_protected_lost(_m: Match, unit: CardInst) -> void:
		if unit == ally:
			lost = true
		elif unit == opponent:
			target_defeated = true

	func check(_m: Match) -> int:
		if lost or not ally or not ally.in_play() or ally.controller != 0:
			return 1
		return 0 if target_defeated else -1

	func describe() -> String:
		return "Keep Han Solo in play and defeat Greedo."

	func tracker(_m: Match) -> String:
		return "Protect Han · Defeat Greedo"


class Hunt extends Objective:
	var killed := false

	func check(m: Match) -> int:
		var id: String = params.get("target", "")
		for c in m.players[1].discard:
			if c.id == id:
				return 0
		return -1

	func describe() -> String:
		return "Hunt down %s when it appears." % params.get("target_name", "the target")

	func tracker(_m: Match) -> String:
		return "Hunt: %s" % params.get("target_name", "target")


class ReinforcementHunt extends Objective:
	var target: CardInst
	var defeated := false

	func on_action_start(m: Match) -> void:
		if target or m.round_num < int(params["rounds"]):
			return
		target = m._new_inst(params["target"], 1)
		target.flags["objective_target"] = true
		target.mods.append({"h": int(params["target_hp"]) - target.printed_hp(), "p": int(params["target_power_bonus"]), "dur": "permanent"})
		m._put_in_play(target, "ground", true)
		m._log("The Filthy Dianoga surfaces!")

	func on_protected_lost(_m: Match, unit: CardInst) -> void:
		if unit == target:
			defeated = true

	func check(_m: Match) -> int:
		return 0 if defeated else -1

	func describe() -> String:
		return "Defeat the Filthy Dianoga after it surfaces in round %d." % int(params["rounds"])

	func tracker(m: Match) -> String:
		return "Defeat the Filthy Dianoga" if target else "Dianoga surfaces in round %d · Round %d" % [params["rounds"], m.round_num]


class HangarDuel extends SurviveRounds:
	var obi_wan: CardInst
	var vader: CardInst

	func setup(m: Match) -> void:
		obi_wan = _duelist(m, params["obi_wan"], 0, int(params["rounds"]) * 2)
		vader = _duelist(m, params["vader"], 1, 18)

	func _duelist(m: Match, id: String, player: int, hp: int) -> CardInst:
		var card := m._new_inst(id, player)
		card.flags.merge({"story_duelist": true, "cannot_attack": true, "objective_target": true})
		card.mods.append({"h": hp - card.printed_hp(), "dur": "permanent"})
		m._put_in_play(card, "space", false, false)
		return card

	func on_round_end(m: Match) -> void:
		if not obi_wan.in_play() or m.players[0].base_remaining() <= 0:
			return
		var last := m.round_num >= int(params["rounds"])
		m.events.append({"t": "attack", "a": vader.uid, "target": obi_wan.uid})
		m.deal_damage(obi_wan, obi_wan.remaining_hp() if last else 2, vader, true, true)
		if last:
			m.defeat(obi_wan)
			m._log("Obi-Wan sacrifices himself. The Millennium Falcon escapes.")
			m.set_winner(0, "Millennium Falcon escaped")
			return
		m.events.append({"t": "attack", "a": obi_wan.uid, "target": vader.uid})
		m.deal_damage(vader, 1, obi_wan, true, true)

	func check(_m: Match) -> int:
		return 1 if not obi_wan.in_play() or obi_wan.remaining_hp() <= 0 else -1

	func describe() -> String:
		return "Keep the Hangar base standing while Obi-Wan holds Vader off for %d rounds." % int(params["rounds"])

	func tracker(m: Match) -> String:
		return "Obi-Wan vs Vader · Round %d/%d" % [m.round_num, params["rounds"]]


class Attrition extends Objective:
	## Each regroup the enemy base takes 1 damage per `per` cards left in their deck.
	func on_round_end(m: Match) -> void:
		var per := int(params.get("per", 4))
		var n := int(ceil(m.players[1].deck.size() / float(per)))
		if n > 0:
			m.deal_damage(m.players[1].base, n, null)

	func describe() -> String:
		return "Attrition: the enemy base burns every round based on their remaining deck."

	func tracker(m: Match) -> String:
		return "Attrition: %d cards in enemy deck" % m.players[1].deck.size()
