extends Node
## Placeholder sound design. If res://ip/audio/<name>.ogg exists it is used,
## otherwise a tiny synthesized blip stands in so every interaction has feedback
## without shipping copyrighted film audio (spec 8.5).

const NAMES := ["saber_on", "swing", "click", "hover", "whoosh", "play", "blaster", "saber", "hit", "shield", "defeat", "deploy", "turn", "win", "lose", "draw"]
const POOL := 6

var _streams: Dictionary = {}
var _players: Array = []
var _next := 0
var catalog: Dictionary = {"characters": {}, "effects": {}, "music": []}
var _clips := {}
var _voice: AudioStreamPlayer
var _result: AudioStreamPlayer
signal cue_played(path: String)


func _exit_tree() -> void:
	for player in _players + [_voice, _result]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_clips.clear()
	_streams.clear()


func _ready() -> void:
	var manifest := "res://ip/audio/catalog.json"
	if FileAccess.file_exists(manifest):
		catalog = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	var additions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/voice_cues.json"))
	for actor in additions["characters"]:
		var pools: Dictionary = catalog["characters"].get_or_add(actor, {})
		for event in additions["characters"][actor]:
			for path in additions["characters"][actor][event]:
				if ResourceLoader.exists(path) and path not in pools.get(event, []):
					pools.get_or_add(event, []).append(path)
	for event in additions["effects"]:
		for path in additions["effects"][event]:
			if ResourceLoader.exists(path) and path not in catalog["effects"].get(event, []):
				catalog["effects"].get_or_add(event, []).append(path)
	_voice = AudioStreamPlayer.new()
	_result = AudioStreamPlayer.new()
	add_child(_voice)
	add_child(_result)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for n in NAMES:
		var path := "res://ip/audio/%s.ogg" % n
		_streams[n] = load(path) if ResourceLoader.exists(path) else _synth(n)
	Sabacc.settings_changed.connect(_volume_changed)


func play(name: String, pitch := 1.0) -> void:
	var custom: Array = catalog.get("effects", {}).get(name, [])
	if not custom.is_empty():
		play_clip(custom.pick_random())
		return
	if not _streams.has(name):
		return
	var vol: float = Sabacc.settings.get("sfx_volume", 0.7)
	if vol <= 0.01:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[name]
	p.volume_db = linear_to_db(vol) - 8.0
	p.set_meta("gain", -8.0)
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.play()


func _volume_changed() -> void:
	var volume: float = Sabacc.settings.get("sfx_volume", 0.7)
	for player in _players + [_voice, _result]:
		player.volume_db = linear_to_db(maxf(0.0001, volume)) + player.get_meta("gain", -8.0)
		if volume <= 0.01:
			player.stop()


func play_clip(path: String, channel := "effect") -> void:
	var volume: float = Sabacc.settings.get("sfx_volume", 0.7)
	if volume <= 0.01 or not ResourceLoader.exists(path):
		return
	if not _clips.has(path):
		_clips[path] = load(path)
	var player: AudioStreamPlayer = _voice if channel == "voice" else (_result if channel == "result" else _players[_next])
	_next = (_next + 1) % POOL
	player.stream = _clips[path]
	player.pitch_scale = 1.0
	player.set_meta("gain", -8.0)
	player.volume_db = linear_to_db(volume) + player.get_meta("gain")
	player.play()
	cue_played.emit(path)
	if channel == "result":
		Music.duck_for(minf(60, player.stream.get_length()))


func character_key(data: Dictionary) -> String:
	var name: String = data.get("name", "").to_lower().replace("-", "_").replace(" ", "_")
	if name.ends_with("_base") or "'s_" in name or "’s_" in name:
		return ""
	if "ben_kenobi" in name:
		return "ben kenobi"
	if name.begins_with("chancellor_palpatine"):
		return "chancellor palpatine"
	if name == "rey":
		return "rey"
	for key in catalog.get("characters", {}):
		if key != "rey" and key.replace(" ", "_") in name:
			return key
	return ""


func character_paths(data: Dictionary, event: String) -> Array:
	event = event.to_lower()
	if event == "die":
		event = "lose"
	var key := character_key(data)
	var voices: Dictionary = catalog.get("characters", {})
	var paths: Array = voices.get(key, {}).get(event, [])
	if key == "ben kenobi":
		return paths + voices.get("obi_wan kenobi", {}).get(event, [])
	if key == "chancellor palpatine":
		return paths + voices.get("palpatine", {}).get(event, [])
	return paths


func _group_paths(group: String, event: String) -> Array:
	return catalog["characters"].get("@" + group, {}).get(event, [])


func entry_paths(data: Dictionary, roll: float, opponents := []) -> Array:
	var traits: Array = data.get("traits", [])
	var key := character_key(data)
	var other := "qui_gon jinn" if key == "maul" else "maul"
	if roll < 0.05:
		if key in ["maul", "qui_gon jinn"] and opponents.any(func(unit): return character_key(unit.data) == other):
			return _group_paths("maul_quigon", "played_rare")
		var rare := character_paths(data, "played_rare")
		if not rare.is_empty():
			return rare
		for unit_trait in ["undead", "creature"]:
			if unit_trait in traits:
				return _group_paths(unit_trait, "played_rare")
	var paths := character_paths(data, "played")
	if not paths.is_empty():
		return paths
	if "separatist" in traits and "droid" in traits:
		var droids := _group_paths("separatist_droid", "played")
		if str(data.get("name", "")).to_lower().begins_with("b1 "):
			return droids + catalog["effects"].get("b1_enter", [])
		return droids
	return _group_paths("jawa", "played") if "jawa" in traits else []


func is_tie(data: Dictionary) -> bool:
	var name: String = data.get("name", "").to_lower()
	return name.begins_with("tie ") or name.begins_with("tie/") or name.begins_with("tie-")


func entered(data: Dictionary, opponents := []) -> void:
	if not data.get("type", "unit") in ["unit", "token_unit", "leader"]:
		return
	var paths := entry_paths(data, randf(), opponents)
	if not paths.is_empty():
		play_clip(paths.pick_random(), "voice")
	if is_tie(data):
		play_effect("tie_enter")
	elif paths.is_empty() and str(data.get("name", "")).to_lower().begins_with("b1 "):
		play_effect("b1_enter")


func play_effect(key: String, channel := "effect") -> void:
	var paths: Array = catalog.get("effects", {}).get(key, [])
	if not paths.is_empty():
		play_clip(paths.pick_random(), channel)


func shield_cue(broken: bool, roll: float) -> String:
	return "shield_break" if broken else ("shield_rare" if roll < 0.05 else "shield_gain")


func shield_sound(broken := false) -> void:
	var key := shield_cue(broken, randf())
	if catalog.get("effects", {}).get(key, []).is_empty():
		key = "shield_gain" if key == "shield_rare" else "shield"
	if catalog.get("effects", {}).get(key, []).is_empty():
		key = "shield"
	play(key)


func defeat_paths(data: Dictionary, roll: float) -> Array:
	if not data.get("type", "") in ["unit", "token_unit", "leader"]:
		return []
	var traits: Array = data.get("traits", [])
	if "vehicle" in traits and roll < 0.05:
		return catalog.get("effects", {}).get("vehicle_easter_egg", [])
	if data.get("arena", "ground") == "ground" and not "vehicle" in traits and not "creature" in traits and roll < 0.05:
		return catalog.get("effects", {}).get("wilhelm", [])
	if roll >= 0.05 and roll < 0.10 and "trooper" in traits and "stormtrooper" in str(data.get("name", "")).to_lower():
		return _group_paths("stormtrooper", "lose_rare")
	var paths := character_paths(data, "lose")
	if not paths.is_empty():
		return paths
	if "clone" in traits:
		return _group_paths("clone", "lose")
	if "separatist" in traits and "droid" in traits:
		return _group_paths("separatist_droid", "lose")
	return []


func defeated(data: Dictionary, arena := "") -> void:
	var definition := data.duplicate()
	if not arena.is_empty():
		definition["arena"] = arena
	var paths := defeat_paths(definition, randf())
	if not paths.is_empty():
		play_clip(paths.pick_random(), "voice")
	elif "vehicle" in data.get("traits", []):
		play_effect("explosion")


func acted(data: Dictionary) -> void:
	if not data.get("type", "") in ["unit", "token_unit", "leader"]:
		return
	var paths := character_paths(data, "action")
	if not paths.is_empty():
		play_clip(paths.pick_random(), "voice")


func unit_kill(data: Dictionary) -> void:
	var paths := character_paths(data, "kill")
	if not paths.is_empty():
		play_clip(paths.pick_random())


func attack_sound(data: Dictionary, style: String) -> String:
	if is_tie(data):
		return "tie_shoot"
	if style == "saber":
		return "swing"
	if style == "melee":
		return "melee"
	if character_key(data) == "boba fett":
		return "boba_shoot"
	if "clone" in data.get("traits", []):
		return "clone_shoot"
	if style == "heavy" and "vehicle" in data.get("traits", []):
		return "walker_shoot" if "walker" in data.get("traits", []) else "heavy_missile"
	return "blaster"


func result_cues(winner: CardInst, loser: CardInst, player_won: bool, deck_aspects: Array = []) -> void:
	if player_won:
		var aspects: Array = winner.data.get("aspects", [])
		if not ("heroism" in aspects or "villainy" in aspects):
			aspects = deck_aspects
		var paths: Array = catalog.get("effects", {}).get("villain_win" if "villainy" in aspects else ("hero_win" if "heroism" in aspects else ""), [])
		if not paths.is_empty():
			play_clip(paths.pick_random(), "result")
	var loss := character_paths(loser.data, "lose")
	if not loss.is_empty():
		play_clip(loss.pick_random(), "voice")


## Generates a short 16-bit mono WAV: frequency sweep + noise, shaped by an envelope.
func _synth(name: String) -> AudioStreamWAV:
	var spec := {
		"saber_on": [0.45, 70.0, 160.0, 0.08], "swing": [0.3, 220.0, 110.0, 0.25],
		"click": [0.05, 1400.0, 900.0, 0.0], "hover": [0.03, 2200.0, 2400.0, 0.0],
		"whoosh": [0.30, 300.0, 90.0, 0.8], "play": [0.16, 520.0, 880.0, 0.1],
		"blaster": [0.22, 1900.0, 260.0, 0.05], "saber": [0.40, 140.0, 95.0, 0.15],
		"hit": [0.14, 160.0, 60.0, 0.6], "shield": [0.25, 900.0, 1500.0, 0.1],
		"defeat": [0.45, 220.0, 40.0, 0.7], "deploy": [0.5, 180.0, 440.0, 0.2],
		"turn": [0.12, 660.0, 990.0, 0.0], "win": [0.8, 440.0, 880.0, 0.0],
		"lose": [0.8, 330.0, 110.0, 0.1], "draw": [0.08, 1200.0, 1600.0, 0.3],
	}
	var s: Array = spec.get(name, [0.1, 800.0, 800.0, 0.0])
	var rate := 22050
	var n: int = int(s[0] * rate)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f: float = lerpf(s[1], s[2], t)
		phase += TAU * f / rate
		var env := minf(t * 30.0, 1.0) * pow(1.0 - t, 2.0)
		var v: float = sin(phase) * (1.0 - s[3]) + randf_range(-1.0, 1.0) * s[3]
		if name in ["saber", "saber_on", "swing"]:
			v = sin(phase) * 0.6 + sin(phase * 2.01) * 0.3 + randf_range(-1, 1) * 0.1
		bytes.encode_s16(i * 2, int(clampf(v * env, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = bytes
	return w
