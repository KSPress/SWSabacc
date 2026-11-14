extends Node
## Quiet random soundtrack. A shuffle bag avoids repeats between tracks.
var player: AudioStreamPlayer
var _bag: Array = []
var _last := ""
var _duck_until := 0
var current_path := ""


func _ready() -> void:
	player = AudioStreamPlayer.new()
	add_child(player)
	player.finished.connect(_next_track)
	Sabacc.settings_changed.connect(_apply)
	if DisplayServer.get_name() != "headless":
		_apply.call_deferred()


func _exit_tree() -> void:
	player.stop()
	player.stream = null


func _process(_delta: float) -> void:
	if player.playing:
		_set_volume()


func _set_volume() -> void:
	var volume: float = Sabacc.settings.get("music_volume", 0.5)
	player.volume_db = linear_to_db(maxf(volume, 0.0001)) - 24.0 - (12.0 if Time.get_ticks_msec() < _duck_until else 0.0)


func _apply() -> void:
	_set_volume()
	if not Sabacc.settings.get("music_enabled", true) or float(Sabacc.settings.get("music_volume", 0.5)) <= 0.01:
		player.stop()
	elif not player.playing:
		_next_track()


func _next_track() -> void:
	if not Sabacc.settings.get("music_enabled", true) or float(Sabacc.settings.get("music_volume", 0.5)) <= 0.01:
		return
	if _bag.is_empty():
		_bag = Sfx.catalog.get("music", []).duplicate()
		_bag.shuffle()
		if _bag.size() > 1 and _bag.back() == _last:
			var swap = _bag[0]
			_bag[0] = _bag.back()
			_bag[_bag.size() - 1] = swap
	if _bag.is_empty():
		return
	current_path = _bag.pop_back()
	_last = current_path
	player.stream = load(current_path)
	_set_volume()
	player.play()


func duck_for(seconds: float) -> void:
	_duck_until = Time.get_ticks_msec() + int(seconds * 1000)
