extends Control

signal world_selected(world: String)

const GALAXY := preload("res://engine/conquest_galaxy.gd")
const MAP := preload("res://assets/branding/galactic_map.jpg")

var run: ConquestRun
var selected := ""
var fleet_index := 0
var zoom := 1.15
var _clock := 0.0
var _pointer_down := false
var _moved := false
var _pointer_origin := Vector2.ZERO
var _scroll_origin := Vector2.ZERO
var _emblems: Array[Texture2D] = []
var _leaders := {}
var _marker := UnitEffects.new()


func _ready() -> void:
	custom_minimum_size = MAP.get_size() * zoom
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	add_child(_marker)
	_marker.set_status(true, false, false)
	_marker.z_index = 2
	for faction in GALAXY.FACTIONS:
		_emblems.append(Cosmetics.texture("emblem", faction["emblem"]))
		var id: String = faction["leader"]
		var texture := Art.request(CardDB.card(id).get("art", id), func(loaded): _leaders[id] = loaded)
		if texture:
			_leaders[id] = texture


func _process(delta: float) -> void:
	_clock += delta
	_marker.visible = not selected.is_empty()
	if _marker.visible:
		_marker.scale = Vector2.ONE * 0.42 * zoom
		_marker.position = GALAXY.WORLDS[selected] * zoom + Vector2(-33, -17) * zoom
	queue_redraw()


func _draw() -> void:
	if not run:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * zoom)
	var map_area := Rect2(Vector2.ZERO, MAP.get_size())
	draw_texture_rect(MAP, map_area, false)
	draw_rect(map_area, Color(0.015, 0.032, 0.068, 0.43))
	var worlds: Dictionary = run.state["worlds"]
	var faction := int(run.state["player"])
	var planner := run.fleet(faction, fleet_index)
	var preview := run.path(faction, planner["world"], selected) if run.idle(planner) else []
	var active_edges := {}
	var previous: String = planner["world"]
	for world in planner["route"] if not planner["route"].is_empty() else preview:
		active_edges[[previous, world]] = true
		active_edges[[world, previous]] = true
		previous = world
	for lane in GALAXY.LANES:
		if worlds.has(lane[0]) and worlds.has(lane[1]):
			var active: bool = active_edges.has(lane.slice(0, 2))
			var points := GALAXY.lane_points(lane)
			draw_polyline(points, Color("#071721"), 5.0 if active else 3.4, true)
			draw_polyline(points, Color("#ffe2a0") if active else Color(0.44, 0.78, 0.93, 0.6), 2.6 if active else 1.5, true)
	for name in worlds:
		_draw_world(name, worlds[name])
	for owner in GALAXY.FACTIONS.size():
		for index in run.fleets(owner).size():
			var task := run.fleet(owner, index)
			if not task["world"].is_empty() and (owner == faction or run.visible_to(faction, task["world"]) \
				or (not task["route"].is_empty() and run.visible_to(faction, task["route"][0]))):
				_draw_fleet(owner, task, index)
	for shipment in run.state["shipments"]:
		if int(shipment["faction"]) != faction and not run.visible_to(faction, shipment["world"]):
			continue
		var at := _traveler_at(shipment)
		var color: Color = GALAXY.FACTIONS[int(shipment["faction"])]["color"]
		draw_circle(at, 6.0, Color("#081821"))
		draw_circle(at, 3.5, color)
		draw_arc(at, 7.0, 0, TAU, 12, color, 1, true)
	for probe in run.state["probes"]:
		if int(probe["faction"]) == faction:
			var at := _traveler_at(probe)
			draw_arc(at, 6.0, 0, TAU, 8, Color("#b8ffe6"), 1.5, true)


func _draw_world(name: String, world: Dictionary) -> void:
	var at: Vector2 = GALAXY.WORLDS[name]
	var owner := int(world["owner"])
	var tint: Color = GALAXY.FACTIONS[owner]["color"] if owner >= 0 else Color("#b6cadd")
	draw_circle(at, 12 if selected == name else 8, Color(tint, 0.22))
	draw_circle(at, 5, Color("#071723"))
	draw_arc(at, 6.8, 0, TAU, 18, tint, 1.8, true)
	draw_circle(at, 2.5, Color("#edfaff"))
	var font := Sabacc.font_body
	var label := GALAXY.display_name(name)
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var rect := Rect2(at + Vector2(-label_width * 0.5 - 4, 9), Vector2(label_width + 8, 16))
	draw_rect(rect, Color(0.03, 0.07, 0.12, 0.9))
	draw_string(font, rect.position + Vector2(4, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#eff8fc"))
	if owner < 0:
		return
	var phase := at.x * 0.05 + (0.0 if Sabacc.perf() else _clock * 0.86)
	var orbit := at + Vector2.from_angle(phase) * 14
	var light := 0.72 + 0.24 * sin(phase * 8.0)
	draw_arc(at, 14, 0, TAU, 24, Color(tint, 0.32), 1.0, true)
	draw_circle(orbit, 8, Color("#091723"))
	if _emblems[owner]:
		draw_texture_rect(_emblems[owner], Rect2(orbit - Vector2(7, 7), Vector2(14, 14)), false, Color(1, 1, 1, light))
	else:
		draw_arc(orbit, 5, 0, TAU, 8, Color(tint, light), 2, true)


func _traveler_at(task: Dictionary) -> Vector2:
	if not task["route"].is_empty():
		return GALAXY.travel_position(task["world"], task["route"][0], run.travel_progress(task))
	return GALAXY.WORLDS[task["world"]]


func _draw_fleet(faction: int, task: Dictionary, index: int) -> void:
	var node := _traveler_at(task)
	if not task["engagement"].is_empty():
		var battle: Dictionary = run.state["battles"].get(task["engagement"], {})
		if not battle.is_empty():
			node = GALAXY.WORLDS[battle["world"]]
	var offset := Vector2(-47 if faction != 2 else 47, -25 - index * 31)
	var center := node + offset
	var color: Color = GALAXY.FACTIONS[faction]["color"]
	draw_line(node, center, Color(color, 0.62), 1.2, true)
	var shape := PackedVector2Array()
	var uv := PackedVector2Array([Vector2(0, 0.5), Vector2(0.18, 0), Vector2(0.82, 0),
		Vector2(1, 0.5), Vector2(0.82, 1), Vector2(0.18, 1)])
	for point in uv:
		shape.append(center + (point - Vector2(0.5, 0.5)) * Vector2(52, 33))
	var id: String = task["leader"]
	var leader: Texture2D = _leaders.get(id)
	if not _leaders.has(id) and not id.is_empty():
		_leaders[id] = Art.request(CardDB.card(id).get("art", id), func(loaded): _leaders[id] = loaded)
	if leader and task["leader_alive"]:
		var crop := PackedVector2Array()
		for point in uv:
			crop.append(Vector2(0.07, 0.18) + point * Vector2(0.38, 0.55))
		draw_polygon(shape, PackedColorArray([Color.WHITE]), crop, leader)
	else:
		draw_colored_polygon(shape, Color("#223241"))
	var outline := shape.duplicate()
	outline.append(shape[0])
	draw_polyline(outline, color, 1.8, true)
	draw_circle(center + Vector2(21, 12), 9.5, Color("#0a1928"))
	draw_string(Sabacc.font_body, center + Vector2(14, 16), "%d" % task["cards"].size(), HORIZONTAL_ALIGNMENT_CENTER, 14, 10, color)


func _gui_input(event: InputEvent) -> void:
	var view := get_parent() as ScrollContainer
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_down = true
			_moved = false
			_pointer_origin = event.global_position
			_scroll_origin = Vector2(view.scroll_horizontal, view.scroll_vertical)
		elif _pointer_down:
			_pointer_down = false
			if not _moved:
				_pick(event.position / zoom)
		accept_event()
	elif event is InputEventMouseMotion and _pointer_down:
		var movement: Vector2 = event.global_position - _pointer_origin
		_moved = _moved or movement.length() > 7
		if _moved:
			view.scroll_horizontal = int(_scroll_origin.x - movement.x)
			view.scroll_vertical = int(_scroll_origin.y - movement.y)
		accept_event()


func _pick(point: Vector2) -> void:
	var closest := ""
	var best := 23.0
	for name in run.state["worlds"]:
		var distance := point.distance_to(GALAXY.WORLDS[name])
		if distance < best:
			closest = name
			best = distance
	if not closest.is_empty():
		world_selected.emit(closest)
