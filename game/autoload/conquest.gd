extends Node

signal changed

var run: ConquestRun
var _simulation: Match
var _simulation_id := ""
var _simulation_steps := 0
var _step_time := 0.0
var _save_time := 0.0
var _display_time := 0.0


func restore() -> void:
	var saved: Dictionary = Save.data.get("conquest", {})
	if run and is_same(saved, run.state):
		return
	_simulation = null
	_simulation_id = ""
	run = null if saved.is_empty() else ConquestRun.new(CardDB.lib, saved)


func start(faction: int, size: int, leader := "") -> void:
	run = ConquestRun.start(CardDB.lib, faction, size, int(randi()), leader)
	_simulation = null
	_simulation_id = ""
	persist()


func save_slot(slot: int, title: String) -> bool:
	if not run or slot not in [1, 2, 3]:
		return false
	var path := "user://conquest_%d.json" % slot
	var saved := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not saved:
		return false
	saved.store_string(JSON.stringify({"title": title.strip_edges().left(50), "date": Time.get_datetime_string_from_system(), "state": run.state}))
	saved.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK


func get_slot(slot: int) -> Dictionary:
	if slot not in [1, 2, 3]:
		return {}
	var path := "user://conquest_%d.json" % slot
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary and parsed.get("state") is Dictionary else {}


func load_slot(slot: int) -> bool:
	var saved := get_slot(slot)
	if saved.is_empty():
		return false
	Save.data["conquest"] = saved["state"]
	restore()
	persist()
	return true


func persist() -> void:
	Save.data["conquest"] = run.state
	Save.write()
	_save_time = 0.0
	changed.emit()


func play_battle(key: String) -> void:
	if not run or not run.state["battles"].has(key):
		return
	var battle: Dictionary = run.state["battles"][key]
	var world: String = battle["world"]
	Router.go("match", {"mode": "conquest", "battle": key, "title": "Battle for " + ConquestGalaxy.display_name(world),
		"battle_world": world,
		"cfg": run.battle_config(key, true)})


func finish_player_battle(key: String, match_game: Match) -> Dictionary:
	if not run:
		return {}
	var result := run.finish_battle(key, match_game, true)
	if not result.is_empty():
		persist()
	return result


func _process(delta: float) -> void:
	if not run or run.state["status"] != "active":
		return
	var screen := get_tree().current_scene
	if not screen or (screen.name != "GalacticConquest" and Router.params.get("mode") != "conquest"):
		return
	_step_time += minf(delta, 0.25)
	_save_time += delta
	_display_time += delta
	if _step_time < 0.12:
		return
	var dirty := run.tick(_step_time)
	_step_time = 0.0
	dirty = _step_bot_battle() or dirty
	if dirty or _save_time >= 3.0:
		persist()
		_display_time = 0.0
	elif _display_time >= 1.0:
		_display_time = 0.0
		changed.emit()


func _step_bot_battle() -> bool:
	if not _simulation:
		var player := int(run.state["player"])
		for key in run.state["battles"]:
			var battle: Dictionary = run.state["battles"][key]
			if player in [int(battle["attacker"]), int(battle["defender"])]:
				continue
			_simulation_id = key
			_simulation_steps = 0
			_simulation = Match.new()
			_simulation.setup(CardDB.lib, run.battle_config(key, false))
			break
	if not _simulation:
		return false
	for i in 10:
		if _simulation.winner >= 0:
			break
		_simulation_steps += 1
		if _simulation.round_num >= 25 or _simulation_steps >= 500:
			_simulation.set_winner(2, "Battle timed out")
		elif not _simulation.pending.is_empty():
			AiBot.choose(_simulation)
		else:
			AiBot.act(_simulation)
	_simulation.events.clear()
	if _simulation.winner < 0:
		return false
	run.finish_battle(_simulation_id, _simulation, false)
	_simulation = null
	_simulation_id = ""
	return true
