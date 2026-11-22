extends Control

signal dismissed
signal manage_requested
signal commanders_requested
signal factory_preview_requested(id: String)
signal fleet_requested(index: int)
signal order_requested
signal scout_requested
signal battle_requested

const GALAXY := preload("res://engine/conquest_galaxy.gd")
const CATALOG_CARD := preload("res://ui/kit/conquest_factory_card.gd")
const FACILITY_GLYPHS := {
	"satellite": "coordinate", "garrison": "sentinel", "fortification": "shield", "orbital": "orbit",
	"vehicles": "ground", "fighters": "space", "droids": "gear", "troopers": "raid",
	"frigates": "support", "capital": "overwhelm", "officers": "initiative",
	"government": "objective", "armory": "smuggle", "training": "grit",
}
const PAGE_SIZE := 10

var run: ConquestRun
var world := ""
var art: Texture2D
var map_position := Vector2.ZERO
var map_diameter := 28.0
var safe_area := Rect2()
var _faction := 0
var _owner := -1
var _tint := Color.WHITE
var _focus := 0.0
var _hologram := 0.0
var _holo_tween: Tween
var _cards_open := false
var _page := 0
var _catalog: Array = []
var _local_cards := {}
var _tiles := {}
var _cards := {}
var _orbit_key := []
var _pressed_pointer := -2
var _start_pointer := Vector2.ZERO
var _heading: Label
var _summary: Label
var _treasury: HBoxContainer
var _header: HBoxContainer
var _orbit: OrbitCard
var _dock: PanelContainer
var _facilities: GridContainer
var _card_grid: GridContainer
var _empty_cards: Label
var _catalog_nav: HBoxContainer
var _prev: Button
var _next: Button
var _page_label: Label
var _build_tab: Button
var _cards_tab: Button
var _manage: Button
var _fleets: Button
var _orders: Button
var _scout: Button
var _battle: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("back_dismissible")
	_faction = int(run.state["player"])
	_build()
	resized.connect(_layout)
	refresh()
	_layout()
	create_tween().tween_method(_set_focus, 0.0, 1.0, Sabacc.anim(0.42)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build() -> void:
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 12)
	add_child(_header)
	var back := SabaccButton.make("", SabaccButton.Style.GHOST, "back")
	back.tooltip_text = "Back to galaxy"
	back.custom_minimum_size = Vector2(56, 56)
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(request_back)
	_header.add_child(back)
	var headings := VBoxContainer.new()
	headings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(headings)
	_treasury = UIKit.conquest_treasury(_faction, 0)
	_treasury.alignment = BoxContainer.ALIGNMENT_BEGIN
	headings.add_child(_treasury)
	_heading = UIKit.fit_label(UIKit.title(GALAXY.display_name(world), 28, Sabacc.C_TEXT))
	headings.add_child(_heading)
	_summary = UIKit.fit_label(UIKit.label("", 17, Sabacc.C_DIM))
	headings.add_child(_summary)
	_orbit = OrbitCard.new()
	_orbit.pressed.connect(func(): fleet_requested.emit(_orbit.index))
	_header.add_child(_orbit)
	_dock = UIKit.panel(Color("#091624D9"), Color("#446777"), 12, 10)
	add_child(_dock)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	_dock.add_child(stack)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 7)
	stack.add_child(nav)
	_build_tab = _button(nav, "Construction", "gear", func(): _show_cards(false))
	_cards_tab = _button(nav, "Cards", "deck", func(): _show_cards(true))
	_build_tab.toggle_mode = true
	_cards_tab.toggle_mode = true
	_fleets = _button(nav, "Fleets", "orbit", func(): commanders_requested.emit())
	_manage = _button(nav, "", "sliders", func(): manage_requested.emit())
	_manage.tooltip_text = "Training, reserves and commanders"
	_manage.custom_minimum_size.x = 56
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	_facilities = GridContainer.new()
	inner.add_child(_facilities)
	for id in ConquestRun.FACILITIES:
		var tile := FacilityTile.new()
		tile.title = ConquestRun.FACILITIES[id][0]
		tile.glyph = FACILITY_GLYPHS[id]
		tile.price = run.price(id)
		tile.pressed.connect(_build_facility.bind(id))
		if id in ConquestRun.FACTORIES:
			tile.held.connect(func(): factory_preview_requested.emit(id))
		_facilities.add_child(tile)
		_tiles[id] = tile
	_card_grid = GridContainer.new()
	inner.add_child(_card_grid)
	_empty_cards = UIKit.label("", 18, Sabacc.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_empty_cards.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_empty_cards)
	_catalog_nav = HBoxContainer.new()
	stack.add_child(_catalog_nav)
	_prev = _button(_catalog_nav, "Previous", "", func(): _turn_page(-1))
	_page_label = UIKit.label("", 16, Sabacc.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_catalog_nav.add_child(_page_label)
	_next = _button(_catalog_nav, "Next", "", func(): _turn_page(1))
	var actions := HBoxContainer.new()
	stack.add_child(actions)
	_orders = _button(actions, "Move fleet", "orbit", func(): order_requested.emit())
	_scout = _button(actions, "Send probe", "ambush", func(): scout_requested.emit())
	_battle = _button(actions, "Enter battle", "fight", func(): battle_requested.emit())


func _button(parent: Container, label: String, glyph: String, action: Callable) -> Button:
	var button := SabaccButton.make(label, SabaccButton.Style.GHOST, glyph)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not label.is_empty() else Control.SIZE_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _layout() -> void:
	var frame := safe_area if safe_area.has_area() else Rect2(Vector2(14, 14), size - Vector2(28, 28))
	_header.position = frame.position
	_header.size = Vector2(frame.size.x, 98)
	_dock.size = Vector2(minf(1100, frame.size.x), 0)
	var fraction := 0.56 if _cards_open else 0.39
	_dock.size.y = maxf(232.0, frame.size.y * fraction)
	_dock.position = Vector2(frame.get_center().x - _dock.size.x * 0.5, frame.end.y - _dock.size.y)
	_facilities.columns = clampi(floori((_dock.size.x - 24) / 148.0), 2, 7)
	_card_grid.columns = clampi(floori((_dock.size.x - 24) / 166.0), 2, 6)
	queue_redraw()


func refresh() -> void:
	var site: Dictionary = run.state["worlds"][world]
	_owner = int(site["owner"])
	var identity := GALAXY.territory_identity(world, _owner)
	_tint = identity["color"]
	_heading.add_theme_color_override("font_color", _tint)
	var funds: int = int(run.state["factions"][_faction]["credits"])
	var owned := _owner == _faction
	var visible := run.visible_to(_faction, world)
	_treasury.get_node("Amount").text = str(funds)
	_summary.text = ""
	if owned:
		_summary.text = "%d/2 slots · %d reserves" % [site["facilities"].size() + site["construction"].size(), site["cards"].size()]
	elif not visible:
		_summary.text = "Reconnaissance needed"
	_manage.visible = owned
	_fleets.visible = owned
	for id in _tiles:
		var tile: FacilityTile = _tiles[id]
		tile.seconds = run.construction_seconds(world, id) if visible else 0
		tile.visible = owned or (visible and (id in site["facilities"] or tile.seconds > 0))
		tile.built = id in site["facilities"]
		tile.disabled = not run.can_buy(_faction, world, id) and not (owned and run._factory(world) == id)
		tile.queue_redraw()
	_refresh_orbit(visible)
	_refresh_catalog()


func set_orders(order_label: String, can_order: bool, can_scout: bool, battle_ready: bool) -> void:
	_orders.text = order_label
	_orders.visible = can_order
	_scout.visible = can_scout
	_battle.visible = battle_ready


func _build_facility(id: String) -> void:
	if _tiles[id].hold_fired:
		return
	if run._factory(world) == id:
		_show_cards(true)
	elif run.buy(_faction, world, id):
		Conquest.persist()


func _refresh_orbit(visible: bool) -> void:
	var key := []
	for faction in GALAXY.FACTIONS.size():
		if faction != _faction and not visible:
			continue
		for index in run.fleets(faction).size():
			var fleet := run.fleet(faction, index)
			var battle: Dictionary = run.state["battles"].get(fleet["engagement"], {})
			var at: String = battle.get("world", fleet["world"])
			if at == world and fleet["route"].is_empty():
				key = [faction, index, fleet["leader"] if fleet["leader_alive"] else "", fleet["cards"].size()]
				break
		if not key.is_empty():
			break
	_orbit.visible = not key.is_empty()
	if not key.is_empty() and key != _orbit_key:
		_orbit.bind(key[2], key[3], key[1], GALAXY.FACTIONS[key[0]]["color"], key[0] == _faction)
	_orbit_key = key


func _refresh_catalog() -> void:
	_facilities.visible = not _cards_open
	_card_grid.visible = _cards_open
	_catalog_nav.visible = _cards_open
	_empty_cards.visible = false
	_build_tab.set_pressed_no_signal(not _cards_open)
	_cards_tab.set_pressed_no_signal(_cards_open)
	if not _cards_open:
		if _owner != _faction and not _tiles.values().any(func(tile): return tile.visible):
			_empty_cards.text = "Control this planet to construct facilities."
			_empty_cards.show()
		return
	var cards := run.factory_catalog(_faction, world)
	var local := run.factory_catalog(_faction, world, true)
	_local_cards.clear()
	for id in local:
		_local_cards[id] = true
		if not id in cards:
			cards.append(id)
	_page = mini(_page, maxi(0, ceili(float(cards.size()) / PAGE_SIZE) - 1))
	var shown := cards.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE)
	if _catalog != shown:
		for child in _card_grid.get_children():
			_card_grid.remove_child(child)
			child.queue_free()
		_cards.clear()
		for id in shown:
			var card := CATALOG_CARD.new()
			card.card = CardDB.card(id)
			card.credits = run.manufacture_price(id)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.pressed.connect(_manufacture.bind(id))
			_card_grid.add_child(card)
			_cards[id] = card
		_catalog = shown
	for id in _cards:
		_cards[id].disabled = not run.can_manufacture(_faction, world, id, _local_cards.has(id))
		_cards[id].queue_redraw()
	_empty_cards.text = "Build a factory to produce cards." if _owner == _faction else "Control this planet to purchase cards."
	_empty_cards.visible = shown.is_empty()
	_catalog_nav.visible = cards.size() > PAGE_SIZE
	_prev.disabled = _page == 0
	_next.disabled = (_page + 1) * PAGE_SIZE >= cards.size()
	_page_label.text = "%d / %d" % [_page + 1, maxi(1, ceili(float(cards.size()) / PAGE_SIZE))]


func _manufacture(id: String) -> void:
	if _cards[id].hold_fired:
		return
	if run.manufacture(_faction, world, id, _local_cards.has(id)):
		Conquest.persist()


func _turn_page(delta: int) -> void:
	_page = maxi(0, _page + delta)
	_refresh_catalog()


func _show_cards(show_cards: bool) -> void:
	if _cards_open == show_cards:
		_build_tab.set_pressed_no_signal(not show_cards)
		_cards_tab.set_pressed_no_signal(show_cards)
		return
	_cards_open = show_cards
	_dock.add_theme_stylebox_override("panel", UIKit.chamfer(
		Color("#091624AE") if show_cards else Color("#091624EE"), Color("#446777"), 12, 1, 10))
	if _holo_tween:
		_holo_tween.kill()
	_holo_tween = create_tween()
	_holo_tween.tween_method(_set_hologram, _hologram, 1.0 if show_cards else 0.0, Sabacc.anim(0.26))
	_refresh_catalog()
	_layout()


func _set_focus(value: float) -> void:
	_focus = value
	queue_redraw()


func _set_hologram(value: float) -> void:
	_hologram = value
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.014, 0.028, 0.051, _focus * 0.94))
	var center := map_position.lerp(size * 0.5, _focus)
	var radius := lerpf(map_diameter / 2.0, minf(size.x, size.y) * 0.35, _focus)
	if radius <= 0.0:
		return
	var cyan := Color("#86e9ff")
	var diameter := radius * 2.0
	if art:
		var dimensions := art.get_size() * (diameter / maxf(art.get_width(), art.get_height()))
		draw_texture_rect(art, Rect2(center - dimensions * 0.5, dimensions), false,
			Color.WHITE.lerp(Color(cyan, 0.28), _hologram))
	else:
		draw_circle(center, radius, Color("#1C384A").lerp(Color(cyan, 0.17), _hologram), true, -1, true)
	draw_arc(center, radius + 6, 0, TAU, 96, Color(_tint.lerp(cyan, _hologram), 0.27 * _focus), 1.5, true)
	if _hologram > 0.0:
		for offset in range(-int(radius) + 4, int(radius), 7):
			var chord := sqrt(maxf(0.0, radius * radius - offset * offset))
			var y := center.y + offset
			draw_line(Vector2(center.x - chord, y), Vector2(center.x + chord, y), Color(cyan, 0.14 * _hologram), 1.0)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_track_swipe(event.position, event.index, event.pressed, event.canceled)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		_track_swipe(event.position, -1, event.pressed)


func _track_swipe(point: Vector2, pointer: int, pressed: bool, canceled := false) -> void:
	if pressed:
		if _pressed_pointer != -2 or point.y <= _header.get_rect().end.y:
			return
		for overlay in get_tree().get_nodes_in_group("back_dismissible"):
			var layer := overlay.get_parent() as CanvasLayer
			if overlay.is_visible_in_tree() and layer and layer.layer > 20:
				return
		_pressed_pointer = pointer
		_start_pointer = point
	elif pointer == _pressed_pointer:
		_pressed_pointer = -2
		var delta := point - _start_pointer
		if not canceled and absf(delta.x) > 58.0 and absf(delta.x) > absf(delta.y) * 1.3:
			_show_cards(delta.x < 0.0)
			get_viewport().set_input_as_handled()


func request_back() -> void:
	dismissed.emit()


class FacilityTile extends "res://ui/kit/conquest_hold_button.gd":
	var title := ""
	var glyph := ""
	var price := 0
	var built := false
	var seconds := 0

	func _ready() -> void:
		super._ready()
		custom_minimum_size = Vector2(132, 106)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for style in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(style, StyleBoxEmpty.new())
		tooltip_text = title + " · Hold to preview" if held.has_connections() else title
		var icon := IconGlyph.new()
		icon.glyph = glyph
		icon.color = Color("#84D5F2")
		icon.size = Vector2(36, 36)
		add_child(icon)
		var layout := func():
			icon.position = Vector2((size.x - icon.size.x) * 0.5, 8)
			queue_redraw()
		resized.connect(layout)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		layout.call()

	func _draw() -> void:
		var accent := Color("#75D6AD") if built else Color("#65B7DF")
		draw_style_box(UIKit.chamfer(Color("#142A3B") if is_hovered() else Color("#0A1C2C"),
			Color(accent, 0.42 if disabled and not built else 0.9), 9, 1), Rect2(Vector2.ZERO, size).grow(-2))
		UIKit.draw_fit(self, Sabacc.font_body, Vector2(6, 68), title,
			HORIZONTAL_ALIGNMENT_CENTER, size.x - 12, 17, Sabacc.C_TEXT)
		var baseline := Vector2(0, size.y - 10)
		if seconds > 0:
			draw_rect(Rect2(4, size.y - 4, (size.x - 8) * (1.0 - seconds / ConquestRun.CONSTRUCTION_TIME), 2), Sabacc.C_GOLD)
			draw_string(Sabacc.font_body, baseline, "%d:%02d" % [seconds / 60, seconds % 60],
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Sabacc.C_GOLD)
		elif built:
			draw_string(Sabacc.font_body, baseline, "Built", HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, accent)
		else:
			var amount := str(price)
			var width := Sabacc.font_body.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			baseline.x = (size.x - width - 20) * 0.5
			draw_string(Sabacc.font_body, baseline, amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Sabacc.C_GOLD)
			draw_texture_rect(UIKit.CREDIT_SYMBOL, Rect2(baseline + Vector2(width + 4, -13), Vector2(16, 16)), false)


class OrbitCard extends Button:
	var index := 0
	var _portrait: Texture2D
	var _name := ""
	var _count := 0
	var _color := Color.WHITE

	func _ready() -> void:
		custom_minimum_size = Vector2(155, 92)
		size_flags_horizontal = Control.SIZE_SHRINK_END
		for style in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(style, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func bind(id: String, count: int, fleet_index: int, color: Color, friendly: bool) -> void:
		index = fleet_index
		_count = count
		_color = color
		_name = CardDB.card(id).get("name", "Defense fleet")
		tooltip_text = "%s · %d cards in orbit" % [_name, _count]
		disabled = not friendly
		var art_key: String = CardDB.card(id).get("art", id)
		_portrait = Art.request(art_key, func(texture): _portrait = texture; queue_redraw(), Art.has_art(art_key, true))
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2(6, 0), Vector2(size.x - 12, 65))
		var shape := UnitToken.silhouette(rect)
		draw_colored_polygon(shape, Color("#101F2A"))
		UnitToken.draw_art(self, rect, shape, _portrait, Color.WHITE, UnitToken.ART_UV)
		UnitToken.draw_face_frame(self, shape, _color.lightened(0.25) if is_hovered() else _color, 0.75)
		UIKit.draw_fit(self, Sabacc.font_body, Vector2(3, 85), "%s · %d" % [_name, _count],
			HORIZONTAL_ALIGNMENT_CENTER, size.x - 6, 15, _color)
