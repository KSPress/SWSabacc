class_name AttackStyle
extends RefCounted
## Decides how a unit's attack is animated, from its card data:
##   saber   — Jedi/Sith/Inquisitors and known saber wielders: target-centered slash
##   claw    — Creature units: white claws
##   blaster — troopers, officials, scoundrels, droids…: rapid bolts
##   heavy   — ground vehicles (walkers, tanks, speeders): big cannon bolts
##   ship    — space units: strafing run with twin lasers
##   melee   — Tuskens, Ewoks, astromechs…: the card lunges into contact
## Bolt colours follow the user's rule: Heroism fires RED, Villainy fires GREEN,
## unaligned cards fire yellow. Named saber wielders keep their own palette;
## space units retain ship attacks. Style corrections live in data/attack_styles.json.

const SABER_TRAITS := ["jedi", "sith", "inquisitor"]
const SABER_NAMES := ["luke skywalker", "darth vader", "kylo ren", "rey", "ahsoka tano", "obi-wan kenobi",
	"ben kenobi", "yoda", "anakin skywalker", "darth maul", "maul", "count dooku", "ezra bridger",
	"kanan jarrus", "cal kestis", "cere junda", "mace windu", "qui-gon jinn", "general grievous",
	"darth sidious", "emperor palpatine", "asajj ventress", "savage opress", "the grand inquisitor",
	"second sister", "third sister", "fifth brother", "seventh sister", "eighth brother", "starkiller",
	"ben solo", "baylan skoll", "shin hati", "marrok", "plo koon", "kit fisto", "aayla secura",
	"ki-adi-mundi", "luminara unduli", "barriss offee", "quinlan vos", "darth tyranus", "trilla suduri"]
const MELEE_TRAITS := ["creature", "ewok", "tusken", "gungan", "night", "undead"]
const MELEE_NAMES := ["r2-d2", "c-3po", "bb-8", "chopper", "k-2so", "d-o", "bd-1", "gonk", "jabba the hutt", "wampa", "rancor"]
const HEAVY_TRAITS := ["walker", "tank", "speeder"]
const SPACE_TRAITS := ["fighter", "capital ship", "transport"]
const BLUE_NAMES := ["obi wan", "ben kenobi", "anakin", "luke", "kanan", "mace windu"]
const GREEN_NAMES := ["yoda", "ahsoka", "qui gon", "general grievous"]

static var _overrides: Dictionary = {}
static var _loaded := false


static func _load_overrides() -> void:
	_loaded = true
	var path := "res://data/attack_styles.json"
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) == TYPE_DICTIONARY:
			_overrides = d.get("cards", {})


## The palette key is shared by a shot and its impact.
static func of(c: CardInst) -> Dictionary:
	if not _loaded:
		_load_overrides()
	var data := c.data
	var name := str(data.get("name", "")).to_lower()
	var traits: Array = data.get("traits", [])
	var aspects: Array = data.get("aspects", [])
	var style := ""
	var ov: Dictionary = _overrides.get(c.id, {})
	if "creature" in traits:
		style = "claw"
	elif c.zone == "space" or data.get("arena") == "space" or (_any(traits, SPACE_TRAITS) and data.get("arena") != "ground"):
		style = "ship"
	elif "vehicle" in traits:
		style = "heavy"
	elif "force" in traits or name == "general grievous":
		style = "saber"
	elif ov.has("style"):
		style = ov["style"]
	elif _any(traits, SABER_TRAITS) or (name in SABER_NAMES and not _blaster_era(data)):
		style = "saber"
	elif _any(traits, HEAVY_TRAITS) or (traits.has("vehicle") and c.zone == "ground"):
		style = "heavy"
	elif _any(traits, MELEE_TRAITS) or name in MELEE_NAMES:
		style = "melee"
	else:
		style = "blaster"
	var palette := "green" if "villainy" in aspects else ("red" if "heroism" in aspects else "yellow")
	if style == "saber":
		palette = _saber_palette(name, aspects)
	return {"style": style, "palette": palette}


static func _saber_palette(name: String, aspects: Array) -> String:
	var normalized := name.replace("-", " ").replace("–", " ")
	if GREEN_NAMES.any(func(character): return normalized.begins_with(character)):
		return "green"
	if BLUE_NAMES.any(func(character): return normalized.begins_with(character)):
		return "blue"
	if "villainy" in aspects:
		return "red"
	return "blue"


## Early-life versions of saber wielders that carry blasters instead
## (e.g. Luke, Dreaming Farmboy / A Hero's Beginning).
static func _blaster_era(data: Dictionary) -> bool:
	var sub := str(data.get("subtitle", "")).to_lower()
	for k in ["farmboy", "hero's beginning", "scavenger", "rebel pilot", "you still with me", "hero of yavin"]:
		if sub.find(k) >= 0:
			return true
	var traits: Array = data.get("traits", [])
	return not ("force" in traits)


static func _any(have: Array, want: Array) -> bool:
	for w in want:
		if w in have:
			return true
	return false
