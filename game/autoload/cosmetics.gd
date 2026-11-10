extends Node
## Offline account cosmetics. GM grants access, never writes items into earned.

signal changed

var catalog: Dictionary = {"emblems": [], "cardbacks": [], "scenes": []}
var _texture_cache: Dictionary = {}


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://ip/cosmetics/catalog.json"))
	if parsed is Dictionary:
		catalog = parsed
	_normalize()


func _normalize() -> void:
	var defaults := default_state()
	if not Save.data.get("cosmetics") is Dictionary:
		Save.data["cosmetics"] = defaults
	for key in defaults:
		if not Save.data["cosmetics"].has(key):
			Save.data["cosmetics"][key] = defaults[key]


static func default_state() -> Dictionary:
	return {"earned": ["emblem:sabacc", "cardback:default", "background:datapad"],
		"equipped": {"emblem": "sabacc", "cardback": "default", "background": "datapad"},
		"gm": false, "gm_equipped": {}, "recorded": []}


func state() -> Dictionary:
	_normalize()
	return Save.data["cosmetics"]


func all_items() -> Array:
	var items: Array = [{"key": "cardback:default", "id": "default", "kind": "cardback", "name": "Classic card back"},
		{"key": "background:datapad", "id": "datapad", "kind": "background", "name": "Datapad · Deck aspects"}]
	for entry in catalog.get("emblems", []):
		items.append({"key": "emblem:" + entry["id"], "id": entry["id"], "kind": "emblem", "name": entry["name"]})
	for entry in catalog.get("cardbacks", []):
		items.append({"key": "cardback:" + entry["id"], "id": entry["id"], "kind": "cardback", "name": entry["name"] + " card back"})
	for entry in catalog.get("scenes", []):
		items.append({"key": "background:" + entry["id"], "id": entry["id"], "kind": "background", "name": entry["name"] + " scene"})
	return items


func known(key: String) -> bool:
	if key == "background:emblem":
		return true
	for item in all_items():
		if item["key"] == key:
			return true
	return false


func unlocked(key: String) -> bool:
	if not known(key):
		return false
	var s := state()
	if s["gm"]:
		return true
	if key == "background:emblem":
		return unlocked("emblem:" + equipped("emblem"))
	return key in s["earned"]


func equipped(kind: String) -> String:
	var fallback: String = {"emblem": "sabacc", "cardback": "default", "background": "datapad"}.get(kind, "")
	var s := state()
	var loadout: Dictionary = s["gm_equipped"] if s["gm"] else s["equipped"]
	var id: String = loadout.get(kind, fallback)
	if kind == "background" and id == "emblem":
		return id
	return id if unlocked(kind + ":" + id) else fallback


func equip(kind: String, id: String) -> bool:
	if not unlocked(kind + ":" + id):
		return false
	var loadout: Dictionary = state()["gm_equipped"] if state()["gm"] else state()["equipped"]
	loadout[kind] = id
	Save.write()
	changed.emit()
	return true


func set_gm(enabled: bool) -> void:
	if enabled and state()["gm_equipped"].is_empty():
		state()["gm_equipped"] = state()["equipped"].duplicate()
	state()["gm"] = enabled
	Save.write()
	changed.emit()


func record_match(won: bool, identity: String) -> Dictionary:
	var s := state()
	if identity.is_empty() or identity in s["recorded"]:
		return {}
	s["recorded"].append(identity)
	if s["recorded"].size() > 256:
		s["recorded"].pop_front()
	Save.data["stats"]["matches"] += 1
	var reward: Dictionary = {}
	if won:
		Save.data["stats"]["wins"] += 1
		if not s["gm"]:
			var pool: Array = all_items().filter(func(item): return not item["key"] in s["earned"])
			if not pool.is_empty():
				reward = pool.pick_random().duplicate()
				s["earned"].append(reward["key"])
	Save.write()
	changed.emit()
	return reward


func texture(kind: String, id: String = "") -> Texture2D:
	if id.is_empty():
		id = equipped(kind)
	if kind == "cardback" and id == "default":
		return Art.card_back
	var folder := "emblems" if kind == "emblem" else "cardbacks"
	var path := "res://ip/cosmetics/%s/%s.webp" % [folder, id]
	if not _texture_cache.has(path):
		_texture_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _texture_cache[path]


func background() -> String:
	return equipped("background")
