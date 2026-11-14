class_name CardLibrary
extends RefCounted
## Read-only card database. Pure data, no Node dependencies, so the rules
## engine and the headless simulator can share it.
##
## Real cards come from the importer (ip/data/cards.json, git-ignored).
## Campaign-only custom cards (data/custom_cards.json, namespace "KYB_") are
## merged in with `custom = true` so the vault / PvP can exclude them.

const BOOSTER_SETS := ["SOR", "SHD", "TWI", "JTL", "LOF", "SEC", "LAW", "ASH", "HMW"]
const SET_NAMES := {
	"SOR": "Spark of Rebellion",
	"SHD": "Shadows of the Galaxy",
	"TWI": "Twilight of the Republic",
	"JTL": "Jump to Lightspeed",
	"LOF": "Legends of the Force",
	"SEC": "Secrets of Power",
	"LAW": "A Lawless Time",
	"ASH": "Ashes of the Empire",
	"HMW": "Homeworlds",
	"IBH": "Intro Battle: Hoth",
	"TS26": "Twin Suns 2026",
	"IC27": "Icons 2027",
}


static func expansion_title(code: String) -> String:
	return SET_NAMES.get(code, code)


const TOKEN_NAMES := {
	"shield": "Shield", "experience": "Experience", "battle_droid": "Battle Droid",
	"clone_trooper": "Clone Trooper", "tie_fighter": "TIE Fighter", "x_wing": "X-Wing",
	"spy": "Spy", "mandalorian": "Mandalorian", "beast": "Beast", "credit": "Credit",
	"force": "The Force", "advantage": "Advantage", "weakness": "Weakness",
}

var cards: Dictionary = {}
var token_ids: Dictionary = {}   # token key -> card id


func load_file(path: String, custom := false) -> int:
	if not FileAccess.file_exists(path):
		push_warning("CardLibrary: missing %s" % path)
		return 0
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CardLibrary: bad json in %s" % path)
		return 0
	var src: Dictionary = parsed.get("cards", parsed)
	var n := 0
	for id in src:
		var c: Dictionary = src[id]
		if custom:
			c["custom"] = true
			c["implemented"] = c.get("implemented", "full")
		_fill_defaults(c)
		cards[id] = c
		n += 1
	_index_tokens()
	return n


func _fill_defaults(c: Dictionary) -> void:
	for k in ["keywords", "abilities", "aspects", "traits", "unparsed"]:
		if not c.has(k):
			c[k] = []
	for k in ["cost", "power", "hp"]:
		if c.get(k) == null:
			c[k] = 0
	if not c.has("text"):
		c["text"] = ""
	if not c.has("art"):
		c["art"] = c.get("id", "")


func _index_tokens() -> void:
	# Prefer the newest printing of each token (higher set order doesn't matter, any works).
	for id in cards:
		var c: Dictionary = cards[id]
		var t: String = c.get("type", "")
		if not (t.begins_with("token") or t.ends_with("_token")):
			continue
		for key in TOKEN_NAMES:
			if c.get("name", "") == TOKEN_NAMES[key] and not token_ids.has(key):
				token_ids[key] = id


func has(id: String) -> bool:
	return cards.has(id)


func get_card(id: String) -> Dictionary:
	return cards.get(id, {})


func token_id(key: String) -> String:
	return token_ids.get(key, "")


## Search helper for the collection vault and tooling.
static func keyword_names(card: Dictionary) -> Array:
	var names: Array = []
	for face in [card, card.get("leader_unit", {})]:
		for entry in face.get("keywords", []):
			var keyword: String = entry.get("k", "")
			if not keyword.is_empty() and keyword not in names:
				names.append(keyword)
	return names


func query(text := "", filters := {}) -> Array:
	var out: Array = []
	var q := text.strip_edges().to_lower()
	var selected_aspects: Array = filters.get("aspects", [])
	var owned := {}
	if filters.has("ids"):
		for id in filters["ids"]:
			owned[id] = true
	for id in cards:
		var c: Dictionary = cards[id]
		if c.get("custom", false) and not filters.get("include_custom", false):
			continue
		var t: String = c.get("type", "")
		if t.begins_with("token") or t.ends_with("_token"):
			continue
		if filters.has("type") and filters["type"] != "" and t != filters["type"]:
			continue
		if filters.has("aspect") and filters["aspect"] != "" and not (filters["aspect"] in c.get("aspects", [])):
			continue
		if not selected_aspects.all(func(a): return a in c.get("aspects", [])):
			continue
		if filters.get("keyword", "") != "" and filters["keyword"] not in keyword_names(c):
			continue
		if filters.get("trait", "") != "" and filters["trait"] not in c.get("traits", []):
			continue
		if filters.get("rarity", "") != "" and filters["rarity"] != c.get("rarity", ""):
			continue
		if filters.get("arena", "") != "" and filters["arena"] != c.get("arena", c.get("leader_unit", {}).get("arena")):
			continue
		if filters.has("set") and filters["set"] != "" and c.get("set", "") != filters["set"]:
			continue
		if filters.has("ids") and not owned.has(id):
			continue
		if q != "":
			var hay := ("%s %s %s %s" % [c.get("name", ""), c.get("subtitle", ""), " ".join(c.get("traits", [])), c.get("text", "")]).to_lower()
			if hay.find(q) < 0:
				continue
		out.append(id)
	var set_order := SET_NAMES.keys()
	out.sort_custom(func(a, b):
		var ca: Dictionary = cards[a]
		var cb: Dictionary = cards[b]
		if ca.get("set", "") != cb.get("set", ""):
			var first := set_order.find(ca.get("set", ""))
			var second := set_order.find(cb.get("set", ""))
			return first < second if first != second else ca.get("set", "") < cb.get("set", "")
		return a < b)
	return out
