extends Control

signal world_selected(world: String)

const GALAXY := preload("res://engine/conquest_galaxy.gd")
const MAP := preload("res://assets/branding/galactic_map.jpg")

var run: ConquestRun
var selected := ""
var fleet_index := 0
const INITIAL_ZOOM := 1.6
const ZOOM_MIN := 0.5
const ZOOM_MAX := 3.6
const DRAG_THRESHOLD := 7.0
const MARKER_TEXTURE_SIZE := 128
const PLANET_ICON_SIZE := 30.0
const FLEET_FACE_SCALE := 0.45
const MAP_BACKGROUND := Color("#07111e")
const MAP_IMAGE_INSET := 6.0
const MAP_EDGE_FADE := 36.0

var zoom := INITIAL_ZOOM
var camera_offset := Vector2.ZERO
var _previous_size := Vector2.ZERO
var _camera_region := Rect2()
var _world_bounds := Rect2()
var _clock := 0.0
var _pointer_down := false
var _moved := false
var _pointer_origin := Vector2.ZERO
var _pan_origin := Vector2.ZERO
var _touches := {}
var _leaders := {}
var _planet_art := {}
var _symbols := {}
var _planet_icon_centers := {}
var _marker := UnitEffects.new()


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	resized.connect(_resize_camera)
	_resize_camera()
	add_child(_marker)
	_marker.set_status(true, false, false)
	_marker.z_index = 2
	_world_bounds = Rect2(GALAXY.WORLDS[run.state["worlds"].keys()[0]], Vector2.ZERO)
	for world in run.state["worlds"]:
		_world_bounds = _world_bounds.expand(GALAXY.WORLDS[world])
		var planet := GALAXY.supplied_planet(world)
		if not planet and GALAXY.LEGACY_ORBITAL_ART.has(world):
			planet = Art.ui_texture("planets/" + GALAXY.LEGACY_ORBITAL_ART[world])
		if planet:
			var sprite := planet.get_image()
			var scale_factor := float(MARKER_TEXTURE_SIZE) / maxi(sprite.get_width(), sprite.get_height())
			if scale_factor < 1.0:
				var dimensions := Vector2i(Vector2(sprite.get_size()) * scale_factor)
				sprite.resize(dimensions.x, dimensions.y, Image.INTERPOLATE_LANCZOS)
			sprite.generate_mipmaps()
			_planet_art[world] = ImageTexture.create_from_image(sprite)
	_arrange_planet_icons()


func _arrange_planet_icons() -> void:
	var occupied: Array[Rect2] = []
	for world in run.state["worlds"]:
		var at: Vector2 = GALAXY.WORLDS[world]
		var radius := _planet_radius(world)
		occupied.append(Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0).grow(2))
		occupied.append(_world_label_rect(world).grow(2))
	for world in run.state["worlds"]:
		if GALAXY.planet_icon(world, -1).is_empty():
			continue
		var at: Vector2 = GALAXY.WORLDS[world]
		var center := at - Vector2(0, _planet_radius(world) + 7.0 + PLANET_ICON_SIZE / 2.0)
		var border := Vector2.ONE * (PLANET_ICON_SIZE + 6.0)
		var badge := Rect2(center - border / 2.0, border)
		for offset in [0.0, 24.0, -24.0, 42.0, -42.0]:
			badge.position.x = center.x + offset - border.x / 2.0
			if not occupied.any(func(rect): return rect.intersects(badge)):
				break
		_planet_icon_centers[world] = badge.get_center()
		occupied.append(badge)
		_world_bounds = _world_bounds.merge(badge)


func _planet_radius(world: String) -> float:
	return 14.0 if _planet_art.has(world) else 6.0


func _process(delta: float) -> void:
	_clock += delta
	_marker.visible = not selected.is_empty()
	if _marker.visible:
		_marker.scale = Vector2.ONE * 0.42 * zoom
		_marker.position = world_position(selected) + Vector2(-35, -25) * zoom
	queue_redraw()


func _draw() -> void:
	if not run:
		return
	draw_rect(Rect2(Vector2.ZERO, size), MAP_BACKGROUND)
	draw_set_transform(camera_offset, 0.0, Vector2.ONE * zoom)
	var map_area := Rect2(Vector2.ZERO, MAP.get_size()).grow(-MAP_IMAGE_INSET)
	draw_texture_rect_region(MAP, map_area, map_area)
	draw_rect(map_area, Color(0.015, 0.032, 0.068, 0.62))
	_fade_chart_edge(map_area.position, Vector2(map_area.end.x, map_area.position.y), Vector2.DOWN)
	_fade_chart_edge(Vector2(map_area.position.x, map_area.end.y), map_area.end, Vector2.UP)
	_fade_chart_edge(map_area.position, Vector2(map_area.position.x, map_area.end.y), Vector2.RIGHT)
	_fade_chart_edge(Vector2(map_area.end.x, map_area.position.y), map_area.end, Vector2.LEFT)
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
			var owner := int(worlds[lane[0]]["owner"])
			var controlled := owner >= 0 and owner == int(worlds[lane[1]]["owner"])
			var tint: Color = GALAXY.FACTIONS[owner]["color"] if controlled else Color("#7297b5")
			if active and not controlled:
				tint = GALAXY.FACTIONS[faction]["color"]
			if controlled or active:
				draw_polyline(points, Color(tint, 0.12), 11.0, true)
				draw_polyline(points, Color(tint, 0.26), 6.2, true)
				draw_polyline(points, Color(tint, 0.90), 2.9 if active else 2.1, true)
				if active:
					draw_polyline(points, tint.lerp(Color.WHITE, 0.56), 1.0, true)
			else:
				draw_polyline(points, Color("#071721"), 3.4, true)
				draw_polyline(points, Color(tint, 0.52), 1.5, true)
	for name in worlds:
		_draw_world(name, worlds[name])
	for name in _planet_icon_centers:
		var owner := int(worlds[name]["owner"])
		var identity := GALAXY.territory_identity(name, owner)
		var center: Vector2 = _planet_icon_centers[name]
		var planet: Vector2 = GALAXY.WORLDS[name]
		var direction := planet.direction_to(center)
		var tint: Color = identity["color"]
		var border := PLANET_ICON_SIZE / 2.0 + 2.0
		draw_line(planet + direction * (_planet_radius(name) + 2), center - direction * border, Color(tint, 0.7), 1.5, true)
		draw_circle(center, border, Color("#091723"), true, -1.0, true)
		draw_arc(center, border, 0, TAU, 32, Color(tint, 0.5), 1.0, true)
		_draw_symbol(GALAXY.planet_icon(name, owner), center, tint, _icon_phase(planet), PLANET_ICON_SIZE)
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
	for world in worlds:
		_draw_world_label(world)


func _fade_chart_edge(start: Vector2, end: Vector2, direction: Vector2) -> void:
	var fade := direction * MAP_EDGE_FADE
	var clear := Color(MAP_BACKGROUND, 0.0)
	draw_polygon(PackedVector2Array([start, end, end + fade, start + fade]),
		PackedColorArray([MAP_BACKGROUND, MAP_BACKGROUND, clear, clear]))


func _draw_world(name: String, world: Dictionary) -> void:
	var at: Vector2 = GALAXY.WORLDS[name]
	var owner := int(world["owner"])
	var identity := GALAXY.territory_identity(name, owner)
	var tint: Color = identity["color"]
	var art: Texture2D = _planet_art.get(name)
	var radius := _planet_radius(name)
	draw_circle(at, radius + 4, Color(tint, 0.24 if selected == name else 0.11), true, -1.0, true)
	if art:
		var dimensions := art.get_size() * (radius * 2.0 / maxf(art.get_width(), art.get_height()))
		draw_texture_rect(art, Rect2(at - dimensions * 0.5, dimensions), false)
	else:
		draw_circle(at, 5, Color("#071723"))
		draw_circle(at, 2.5, Color("#edfaff"))
	draw_arc(at, radius + 1.0, 0, TAU, 28, tint, 1.4, true)
	var symbol_id := GALAXY.territory_icon(name, owner)
	if symbol_id.is_empty() or _planet_icon_centers.has(name):
		return
	var phase := _icon_phase(at)
	var orbit_radius := radius + 8.0
	var orbit := at + Vector2.from_angle(phase) * orbit_radius
	draw_arc(at, orbit_radius, 0, TAU, 28, Color(tint, 0.32), 1.0, true)
	draw_circle(orbit, 10, Color("#091723"))
	_draw_symbol(symbol_id, orbit, tint, phase, 16.0)


func _icon_phase(at: Vector2) -> float:
	return at.x * 0.05 + (0.0 if Sabacc.perf() else _clock * 0.86)


func _draw_symbol(symbol_id: String, center: Vector2, tint: Color, phase: float, extent: float) -> void:
	if not _symbols.has(symbol_id):
		var asset := "res://assets/conquest/icons/%s.png" % symbol_id
		_symbols[symbol_id] = load(asset) as Texture2D
	var symbol: Texture2D = _symbols[symbol_id]
	if not symbol:
		return
	var image_size := symbol.get_size()
	var dimensions := image_size * (extent / maxf(image_size.x, image_size.y))
	var rect := Rect2(center - dimensions * 0.5, dimensions)
	var light := 0.86 if Sabacc.perf() else 0.83 + 0.12 * sin(phase * 19.0)
	draw_texture_rect(symbol, rect, false, Color(tint, light))
	if Sabacc.perf():
		return
	var band := 0.13
	var scan := fposmod(phase * 0.7, 1.0 - band)
	var source := Rect2(0, image_size.y * scan, image_size.x, image_size.y * band)
	var overlay := Rect2(rect.position + Vector2(sin(phase * 23.0) * 1.2, rect.size.y * scan),
		Vector2(rect.size.x, rect.size.y * band))
	draw_texture_rect_region(symbol, overlay, source, Color(tint.lerp(Color.WHITE, 0.5), 0.58))


func _world_label_rect(world: String) -> Rect2:
	var label := GALAXY.display_name(world)
	var label_width := Sabacc.font_body.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	return Rect2(GALAXY.WORLDS[world] + Vector2(-label_width * 0.5 - 4, _planet_radius(world) + 3), Vector2(label_width + 8, 16))


func _draw_world_label(world: String) -> void:
	var rect := _world_label_rect(world)
	var identity := GALAXY.territory_identity(world, int(run.state["worlds"][world]["owner"]))
	draw_rect(rect, Color(0.03, 0.07, 0.12, 0.9))
	draw_string(Sabacc.font_body, rect.position + Vector2(4, 12), GALAXY.display_name(world), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, identity["color"])


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
	var offset := Vector2(-56 if faction != 2 else 56, -29 - index * 44)
	if not task["engagement"].is_empty():
		# Separate the fleets when they share an attack site.
		offset = [Vector2(56, -28), Vector2(-56, -28), Vector2(0, -62)][faction]
	var center := node + offset
	var color: Color = GALAXY.FACTIONS[faction]["color"]
	draw_line(node, center, Color(color, 0.62), 1.2, true)
	var dimensions := UnitToken.FACE.size * FLEET_FACE_SCALE
	var face := Rect2(center - dimensions * 0.5, dimensions)
	var shape := UnitToken.silhouette(face)
	var id: String = task["leader"] if task["leader_alive"] else ""
	var aspects: Array = CardDB.card(id).get("aspects", [])
	UnitToken.draw_alignment_edge(self, shape, aspects, FLEET_FACE_SCALE)
	UnitToken.draw_art(self, face, shape, _deployed_leader_art(id), Color.WHITE, UnitToken.ART_UV)
	UnitToken.draw_face_frame(self, shape, color, FLEET_FACE_SCALE)
	var badge_side := -1.0 if offset.x < 0.0 else 1.0
	var badge := center + Vector2(dimensions.x * 0.44 * badge_side, dimensions.y * 0.30)
	draw_circle(badge, 9.5, Color("#0a1928"))
	draw_arc(badge, 9.5, 0.0, TAU, 20, color, 1.0, true)
	draw_string(Sabacc.font_body, badge + Vector2(-8, 4), "%d" % task["cards"].size(), HORIZONTAL_ALIGNMENT_CENTER, 16, 10, color)


func _deployed_leader_art(id: String) -> Texture2D:
	if id.is_empty():
		return null
	if not _leaders.has(id):
		var art: String = CardDB.card(id).get("art", id)
		_leaders[id] = Art.request(art, func(loaded): _leaders[id] = loaded, Art.has_art(art, true))
	return _leaders[id]


func world_position(world: String) -> Vector2:
	return GALAXY.WORLDS[world] * zoom + camera_offset


func center_on(world: String) -> void:
	var point: Vector2 = GALAXY.WORLDS[world] * zoom
	var chart_bounds := _chart_pan_bounds()
	var offset := (camera_center() - point).clamp(chart_bounds.position, chart_bounds.end)
	var safe_region := _camera_clearance()
	if safe_region.has_area():
		offset = (point + offset).clamp(safe_region.position, safe_region.end) - point
	_set_offset(offset)


func camera_center() -> Vector2:
	return _camera_region.get_center() if _camera_region.has_area() else size * 0.5


func set_camera_region(region: Rect2) -> void:
	if region.is_equal_approx(_camera_region):
		return
	var previous := camera_center()
	_camera_region = region
	_set_offset(camera_offset + (camera_center() - previous))


func _resize_camera() -> void:
	if not _camera_region.has_area():
		_set_offset(camera_offset + (size - _previous_size) * 0.5)
	_previous_size = size


func _chart_pan_bounds() -> Rect2:
	var gap := size - MAP.get_size() * zoom
	var rest := gap.max(Vector2.ZERO) * 0.5
	return Rect2(gap.min(Vector2.ZERO) + rest, (-gap).max(Vector2.ZERO))


func _camera_clearance() -> Rect2:
	var padding := minf(32.0 * zoom, minf(_camera_region.size.x, _camera_region.size.y) * 0.25)
	return _camera_region.grow(-padding)


func _set_offset(offset: Vector2) -> void:
	var chart_bounds := _chart_pan_bounds()
	var lower := chart_bounds.position
	var upper := chart_bounds.end
	if _camera_region.has_area() and _world_bounds.has_area():
		# Let edge worlds pan clear of the controls floating over the map.
		var clearance := _camera_clearance()
		lower = lower.min(clearance.end - _world_bounds.end * zoom)
		upper = upper.max(clearance.position - _world_bounds.position * zoom)
	camera_offset = offset.clamp(lower, upper)
	queue_redraw()


func zoom_at(factor: float, anchor: Vector2, next_anchor: Vector2) -> void:
	var previous := zoom
	zoom = clampf(previous * factor, ZOOM_MIN, ZOOM_MAX)
	_set_offset(next_anchor - (anchor - camera_offset) * (zoom / previous))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch(event)
		accept_event()
		return
	if event is InputEventScreenDrag:
		_touch_drag(event.index, event.position)
		accept_event()
		return
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMagnifyGesture:
		zoom_at(event.factor, event.position, event.position)
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var factor := pow(1.15, maxf(1.0, event.factor))
		zoom_at(factor if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / factor, event.position, event.position)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_down = true
			_moved = false
			_pointer_origin = event.position
			_pan_origin = camera_offset
			mouse_default_cursor_shape = Control.CURSOR_MOVE
		elif _pointer_down:
			_pointer_down = false
			mouse_default_cursor_shape = Control.CURSOR_DRAG
			if not _moved:
				_pick((event.position - camera_offset) / zoom)
		accept_event()
	elif event is InputEventMouseMotion and _pointer_down:
		_pan_pointer(event.position)
		accept_event()


func _pan_pointer(point: Vector2) -> void:
	var movement := point - _pointer_origin
	_moved = _moved or movement.length() > DRAG_THRESHOLD
	if _moved:
		_set_offset(_pan_origin + movement)


func _touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_pointer_origin = event.position
			_pan_origin = camera_offset
			_moved = false
		else:
			_moved = true
	elif _touches.erase(event.index):
		if _touches.is_empty() and not _moved and not event.canceled:
			_pick((event.position - camera_offset) / zoom)
		elif _touches.size() == 1:
			_pointer_origin = _touches.values()[0]
			_pan_origin = camera_offset


func _touch_drag(index: int, point: Vector2) -> void:
	if not _touches.has(index):
		return
	var old: Vector2 = _touches[index]
	_touches[index] = point
	if _touches.size() == 1:
		_pan_pointer(point)
		return
	var fingers := _touches.keys()
	if not index in fingers.slice(0, 2):
		return
	var other: Vector2 = _touches[fingers[1] if fingers[0] == index else fingers[0]]
	var distance := old.distance_to(other)
	if distance > 1.0:
		zoom_at(point.distance_to(other) / distance, (old + other) * 0.5, (point + other) * 0.5)


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
