extends RefCounted

const STAKE := 10
const BOOST := 7
const TRUMP := 8
const BACK := 9
const DECK_SIZE := 8
const UNLOCK_CHAPTER := "ep1_ch1_naboo"


static func deal(seed_value: int) -> Dictionary:
	var decks := shuffle_decks(seed_value)
	return resolve(decks[0], decks[1])


static func shuffle_decks(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var decks := [range(1, DECK_SIZE + 1), range(1, DECK_SIZE + 1)]
	for deck in decks:
		for i in range(deck.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var value: int = deck[i]
			deck[i] = deck[j]
			deck[j] = value
	return decks


static func resolve(player: Array, gambler: Array) -> Dictionary:
	var decks := [player.duplicate(), gambler.duplicate()]
	var reveals: Array = []
	while not decks[0].is_empty() and not decks[1].is_empty():
		var cards := [int(decks[0].pop_front()), int(decks[1].pop_front())]
		reveals.append(_reveal(decks, cards, "Reveal"))
		if BOOST in cards and TRUMP in cards:
			reveals.back()["caption"] = "Face-card clash · War"
			if decks[0].size() < 4 or decks[1].size() < 4:
				return _result(decks, reveals, 0, "Too few cards for War")
			for i in 3:
				decks[0].pop_front()
				decks[1].pop_front()
				reveals.append(_reveal(decks, [BACK, BACK], "War · Face-down card %d of 3" % (i + 1)))
			continue
		var totals := cards.duplicate()
		var additional := [0, 0]
		for side in 2:
			if cards[side] != BOOST:
				continue
			if decks[side].is_empty():
				return _result(decks, reveals, 0, "No card left to boost")
			additional[side] = int(decks[side].pop_front())
			var next: int = additional[side]
			totals[side] = 100 if next == TRUMP else next + 3
		if BOOST in cards:
			reveals.append(_reveal(decks, additional, "Boost · Add 3 to the next numbered card"))
		for side in 2:
			if cards[side] == TRUMP:
				totals[side] = 100
		var delta := STAKE * signi(totals[0] - totals[1])
		var summary := "%s vs %s" % [_score(totals[0]), _score(totals[1])]
		return _result(decks, reveals, delta, summary)
	return _result(decks, reveals, 0, "Tie")


static func _reveal(decks: Array, cards: Array, caption: String) -> Dictionary:
	return {"cards": cards, "caption": caption, "remaining": [decks[0].size(), decks[1].size()]}


static func _result(decks: Array, reveals: Array, delta: int, summary: String) -> Dictionary:
	return {"delta": delta, "reveals": reveals, "result": summary, "decks": decks}


static func _score(value: int) -> String:
	return "Trump" if value == 100 else str(value)
