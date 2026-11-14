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
var _friendly: Array[String] = []
var _enemy: Array[String] = []
var _enemy_mix := 0.0
var _fade: Tween


func preset() -> Dictionary:
	var background := Cosmetics.background()
	if background in ["datapad", "emblem"]:
		var accent := Cosmetics.emblem_color() if background == "emblem" else Color("9fdcff")
		return {"name": "Emblem hologram" if background == "emblem" else "Datapad", "kind": "datapad", "accent": accent, "base": accent.darkened(0.95), "emblem": background == "emblem"}
	if background.begins_with("set_"):
		return {"name": CardLibrary.expansion_title(background.trim_prefix("set_").to_upper()), "kind": "planet",
			"art": background, "accent": Color("9fdcff"), "base": Color("060a13")}
	return PRESETS.get("planet_" + background, PRESETS["datapad_republic"])


func _ready() -> void:
	Sabacc.settings_changed.connect(func(): changed.emit())
	Cosmetics.changed.connect(func(): changed.emit())


func color_at(index: int = 0) -> Color:
	if deck_aspects.is_empty():
		return preset()["accent"]
	return _aspect_color(deck_aspects[posmod(index, deck_aspects.size())])


func _aspect_color(aspect: String) -> Color:
	# Black-on-black outlines vanish. Lift only the decorative Villainy tint;
	# the printed black aspect icon remains untouched.
	return Color("9ca4b6") if aspect == "villainy" else Sabacc.aspect_color(aspect).lightened(0.12)


func line_color(index: int = 0) -> Color:
	var friendly := color_at(index)
	if _enemy.is_empty():
		return friendly
	return friendly.lerp(_aspect_color(_enemy[posmod(index, _enemy.size())]), _enemy_mix)


func backdrop_color(index: int = 0) -> Color:
	return Cosmetics.emblem_color("", index) if Cosmetics.background() == "emblem" else line_color(index)


func begin_match(players: Array) -> void:
	_friendly = aspects_for([CardDB.card(players[0].get("leader", "")), CardDB.card(players[0].get("base", ""))])
	_enemy = aspects_for([CardDB.card(players[1].get("leader", "")), CardDB.card(players[1].get("base", ""))])
	deck_aspects = _friendly.duplicate()
	_enemy_mix = 0.0
	changed.emit()


func set_acting_player(player: int) -> void:
	var target := 1.0 if player == 1 else 0.0
	if _fade and _fade.is_valid() and _fade.get_meta("side", -1) == player:
		return
	if Sabacc.perf():
		_enemy_mix = target
		changed.emit()
		return
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.set_meta("side", player)
	_fade.tween_property(self, "_enemy_mix", target, Sabacc.anim(0.45)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func end_match() -> void:
	if _fade and _fade.is_valid():
		_fade.kill()
	_enemy.clear()
	_enemy_mix = 0.0


func set_deck(leader: String, base: String, cards: Array = []) -> void:
	var definitions: Array = [CardDB.card(leader), CardDB.card(base)]
	# Match and datapad identity is defined by the leader and base, never by
	# an off-aspect card that happens to be in the deck.
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
