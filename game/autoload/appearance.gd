extends Node
## Shared theme selection and the human deck's visual identity. Gameplay values
## and aspect symbols keep their meaning; only decorative accents are tinted.

signal changed

const PRESETS := {
	"space_deep": {"name": "Space · Deep orbit", "kind": "space", "accent": Color("66cfff"), "base": Color("040810")},
	"space_nebula": {"name": "Space · Violet nebula", "kind": "space", "accent": Color("be9aff"), "base": Color("10091d")},
	"space_hyperspace": {"name": "Space · Hyperspace", "kind": "space", "accent": Color("69f3e3"), "base": Color("030d17")},
	"planet_tatooine": {"name": "Planet · Tatooine", "kind": "planet", "art": "tatooine", "accent": Color("efba72"), "base": Color("130d08")},
	"planet_dathomir": {"name": "Planet · Dathomir", "kind": "planet", "art": "dathomir", "accent": Color("e47e86"), "base": Color("14090f")},
	"planet_coruscant": {"name": "Planet · Coruscant", "kind": "planet", "art": "coruscant", "accent": Color("a6baff"), "base": Color("080d19")},
	"planet_deathstar": {"name": "Planet · Death Star", "kind": "planet", "art": "deathstar", "accent": Color("a3d8bb"), "base": Color("080e0e")},
	"datapad_imperial": {"name": "Datapad · Imperial", "kind": "datapad", "accent": Color("ed4d58"), "base": Color("0d0d10")},
	"datapad_republic": {"name": "Datapad · Republic", "kind": "datapad", "accent": Color("9fdcff"), "base": Color("061728")},
	"datapad_outer_rim": {"name": "Datapad · Outer Rim", "kind": "datapad", "accent": Color("35e7b2"), "base": Color("060e0c")},
}

var deck_aspects: Array[String] = []


func preset() -> Dictionary:
	return PRESETS.get(Sabacc.settings.get("theme", "space_deep"), PRESETS["space_deep"])


func _ready() -> void:
	Sabacc.settings_changed.connect(func(): changed.emit())


func color_at(index: int = 0) -> Color:
	if deck_aspects.is_empty():
		return preset()["accent"]
	var aspect := deck_aspects[posmod(index, deck_aspects.size())]
	# Black-on-black outlines vanish. Lift only the decorative Villainy tint;
	# the printed black aspect icon remains untouched.
	return Color("9ca4b6") if aspect == "villainy" else Sabacc.aspect_color(aspect).lightened(0.12)


func set_deck(leader: String, base: String, cards: Array = []) -> void:
	var definitions: Array = [CardDB.card(leader), CardDB.card(base)]
	for id in cards:
		definitions.append(CardDB.card(str(id)))
	var next := aspects_for(definitions)
	if next != deck_aspects:
		deck_aspects = next
		changed.emit()


func clear_deck() -> void:
	deck_aspects.clear()
	changed.emit()


static func aspects_for(definitions: Array) -> Array[String]:
	var colors: Array[String] = []
	var alignments: Array[String] = []
	for d in definitions:
		for aspect in d.get("aspects", []):
			if not Sabacc.ASPECT_COLORS.has(aspect):
				continue
			var dest := alignments if aspect in ["heroism", "villainy"] else colors
			if not aspect in dest:
				dest.append(aspect)
	# Two gameplay aspects plus alignment is the usual three-colour identity.
	var result: Array[String] = []
	for aspect in colors.slice(0, 2) + alignments.slice(0, 1):
		result.append(aspect)
	if result.size() < 3:
		for aspect in colors.slice(2) + alignments.slice(1):
			if result.size() < 3:
				result.append(aspect)
	return result
