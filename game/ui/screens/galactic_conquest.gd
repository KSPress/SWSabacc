extends ScreenBase

const GALAXY := preload("res://engine/conquest_galaxy.gd")
const MAP_VIEW := preload("res://ui/kit/conquest_map.gd")
const FACTORY_CARD := preload("res://ui/kit/conquest_factory_card.gd")
const PLANET_VIEW := preload("res://ui/kit/conquest_planet_view.gd")

var _faction := 0
var _map_size := 8
var _starter := ""
var _fleet_index := 0
var _selected := ""
var _root := VBoxContainer.new()
var _setup: VBoxContainer
var _faction_buttons: Array[Button] = []
var _map_buttons: Array[Button] = []
var _leader_name: Label
var _leader_art: TextureRect
var _leader_picker: OptionButton
var _fleet_picker: OptionButton
var _scout: Button
var _status: Label
var _world_info: Label
var _report: Label
var _orders: Button
var _production: Button
var _battle: Button
var _fleet_deck: Button
var _map: Control
var _toolbar: HBoxContainer
var _command_panel: PanelContainer
var _command_scroll: ScrollContainer
var _commands: VBoxContainer
var _command_grid: GridContainer
var _overlay_layout_queued := false
var _planet_view: Control


func build() -> void:
	set_header("Galactic Conquest", "play")
	var saves := SabaccButton.make("Save / Load", SabaccButton.Style.GHOST)
	saves.pressed.connect(_show_saves)
	header.add_child(saves)
	bg.set_location("space")
	Conquest.restore()
	_root.add_theme_constant_override("separation", 9)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_root)
	Conquest.changed.connect(_refresh)
	if Conquest.run:
		_show_galaxy()
	else:
		_show_setup()


func request_screen_back() -> bool:
	if Conquest.run:
		Conquest.persist()
	Router.go("play", {"selected": 2})
	return true


func relayout(in_portrait: bool, rect: Rect2) -> void:
	_root.position = Vector2.ZERO
	_root.size = rect.size
	if is_instance_valid(_map):
		var top_padding := header.position.y - safe_rect().position.y
		header.position.y -= top_padding
		body.position.y -= top_padding
		body.size.y += top_padding
		_root.size = body.size
		_command_grid.columns = 2 if in_portrait else 1
		_queue_overlay_layout()
	if _setup:
		_setup.custom_minimum_size.x = minf(590, rect.size.x)
	if is_instance_valid(_planet_view):
		_planet_view.safe_area = safe_rect()
		_planet_view._layout()


func _queue_overlay_layout() -> void:
	if not _overlay_layout_queued:
		_overlay_layout_queued = true
		_layout_overlays.call_deferred()


func _layout_overlays() -> void:
	_overlay_layout_queued = false
	if not is_instance_valid(_map) or not is_instance_valid(_command_panel):
		return
	var toolbar_bottom := _toolbar.get_rect().end.y
	var available := maxf(1.0, body.size.y - toolbar_bottom - 12.0)
	var panel_width := body.size.x if portrait else clampf(body.size.x * 0.30, 310.0, 360.0)
	var panel_decoration := _command_panel.get_theme_stylebox("panel").get_minimum_size().y
	var panel_height := minf(_commands.get_combined_minimum_size().y + panel_decoration, available * (0.48 if portrait else 1.0))
	_command_panel.size = Vector2(panel_width, panel_height)
	_command_panel.position = Vector2(0.0, body.size.y - _command_panel.size.y) if portrait else Vector2(body.size.x - panel_width, toolbar_bottom + 12.0)
	var focus_start := body.position + Vector2(12.0, toolbar_bottom + 12.0)
	var focus_end := body.position + Vector2(body.size.x - 12.0, _command_panel.position.y - 16.0) if portrait \
		else body.position + Vector2(_command_panel.position.x - 16.0, body.size.y - 12.0)
	_map.set_camera_region(Rect2(focus_start, (focus_end - focus_start).max(Vector2.ONE)))


func _clear() -> void:
	_close_planet()
	for overlay in [_map, _command_panel]:
		if is_instance_valid(overlay):
			overlay.get_parent().remove_child(overlay)
			overlay.queue_free()
	for node in _root.get_children():
		_root.remove_child(node)
		node.queue_free()
	_map = null
	_command_panel = null
	_toolbar = null
	_setup = null
	_status = null


func _show_setup() -> void:
	_clear()
	_account_credit.show()
	_faction_buttons.clear()
	_map_buttons.clear()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_setup = VBoxContainer.new()
	_setup.add_theme_constant_override("separation", 16)
	center.add_child(_setup)
	_setup.add_child(UIKit.title("Choose your faction", 31, Sabacc.C_TEXT))
	var choices := HBoxContainer.new()
	_setup.add_child(choices)
	for i in GALAXY.FACTIONS.size():
		var side: Dictionary = GALAXY.FACTIONS[i]
		var button := SabaccButton.make(side["name"], SabaccButton.Style.PRIMARY)
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			if _faction != i:
				_starter = ""
			_faction = i
			_update_setup())
		choices.add_child(button)
		_faction_buttons.append(button)
	_leader_art = TextureRect.new()
	_leader_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_leader_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_leader_art.custom_minimum_size.y = 165
	_setup.add_child(_leader_art)
	_leader_name = UIKit.label("", 21, Sabacc.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_setup.add_child(_leader_name)
	_leader_picker = OptionButton.new()
	_leader_picker.fit_to_longest_item = false
	_leader_picker.custom_minimum_size.y = 46
	_leader_picker.item_selected.connect(func(index: int):
		_starter = _leader_picker.get_item_metadata(index)
		_update_setup())
	_setup.add_child(_leader_picker)
	_setup.add_child(UIKit.title("Galaxy size", 24, Sabacc.C_TEXT))
	var sizes := HBoxContainer.new()
	_setup.add_child(sizes)
	for count in ConquestRun.SIZES:
		var button := SabaccButton.make("%d planets" % count, SabaccButton.Style.GHOST)
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			_map_size = count
			_update_setup())
		sizes.add_child(button)
		_map_buttons.append(button)
	var launch := SabaccButton.make("Start conquest", SabaccButton.Style.GOLD, "play", true)
	launch.pressed.connect(func():
		Conquest.start(_faction, _map_size, _starter)
		_fleet_index = 0
		_selected = ""
		_show_galaxy())
	_setup.add_child(launch)
	if Conquest.run:
		var resume := SabaccButton.make("Return to saved galaxy", SabaccButton.Style.GHOST)
		resume.pressed.connect(_show_galaxy)
		_setup.add_child(resume)
	_update_setup()
	_on_resize()


func _update_setup() -> void:
	for index in _faction_buttons.size():
		_faction_buttons[index].set_pressed_no_signal(index == _faction)
	for index in _map_buttons.size():
		_map_buttons[index].set_pressed_no_signal(ConquestRun.SIZES[index] == _map_size)
	var side: Dictionary = GALAXY.FACTIONS[_faction]
	var variants: Array = GALAXY.leader_variants(CardDB.lib, _faction, "", true)
	if not _starter in variants:
		_starter = side["leader"]
	_leader_picker.clear()
	for id in variants:
		_leader_picker.add_item(CardDB.card(id).get("subtitle", id))
		_leader_picker.set_item_metadata(_leader_picker.item_count - 1, id)
	_leader_picker.select(variants.find(_starter))
	var leader := CardDB.card(_starter)
	_leader_art.texture = Art.get_now(leader.get("art", _starter))
	_leader_name.text = "%s · %s" % [leader.get("name", ""), GALAXY.display_name(side["home"])]


func _show_galaxy() -> void:
	_clear()
	var run := Conquest.run
	var faction := int(run.state["player"])
	_fleet_index = mini(_fleet_index, run.fleets(faction).size() - 1)
	if not run.state["worlds"].has(_selected):
		_selected = run.fleet(faction)["world"]
		if _selected.is_empty():
			_selected = GALAXY.FACTIONS[faction]["home"]
	_account_credit.hide()
	_toolbar = HBoxContainer.new()
	_toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toolbar.add_theme_constant_override("separation", 10)
	_root.add_child(_toolbar)
	_toolbar.resized.connect(_queue_overlay_layout)
	_status = UIKit.label("", 20, Sabacc.C_GOLD)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toolbar.add_child(_status)
	for factor in [1.0 / 1.2, 1.2]:
		var zoom := SabaccButton.make("−" if factor < 1.0 else "+", SabaccButton.Style.GHOST)
		zoom.tooltip_text = "Zoom out" if factor < 1.0 else "Zoom in"
		zoom.custom_minimum_size.x = 48
		zoom.pressed.connect(func():
			var anchor: Vector2 = _map.camera_center()
			_map.zoom_at(factor, anchor, anchor))
		_toolbar.add_child(zoom)
	var center := SabaccButton.make("Locate fleet", SabaccButton.Style.GHOST)
	center.pressed.connect(func():
		var world: String = run.fleet(faction, _fleet_index)["world"]
		_map.center_on(world if not world.is_empty() else _selected))
	_toolbar.add_child(center)
	_map = MAP_VIEW.new()
	_map.run = run
	_map.fleet_index = _fleet_index
	_map.selected = _selected
	_map.world_selected.connect(func(world: String):
		_selected = world
		_map.selected = world
		_open_planet())
	add_child(_map)
	move_child(_map, body.get_index())
	UIKit.fill_rect(_map)
	_command_panel = UIKit.panel(Color("#0c1925"), Color("#416c84"), 12, 10)
	_command_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(_command_panel)
	_command_scroll = ScrollContainer.new()
	_command_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_command_panel.add_child(_command_scroll)
	_commands = VBoxContainer.new()
	_commands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_scroll.add_child(_commands)
	_commands.minimum_size_changed.connect(_queue_overlay_layout)
	_world_info = UIKit.label("", 21, Sabacc.C_TEXT)
	_world_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_commands.add_child(_world_info)
	_report = UIKit.label("", 17, Sabacc.C_DIM)
	_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_commands.add_child(_report)
	_fleet_picker = OptionButton.new()
	_fleet_picker.fit_to_longest_item = false
	_fleet_picker.custom_minimum_size.y = 44
	_fleet_picker.item_selected.connect(func(index: int):
		_fleet_index = index
		_map.fleet_index = index
		_refresh())
	_commands.add_child(_fleet_picker)
	_command_grid = GridContainer.new()
	_commands.add_child(_command_grid)
	_orders = _button(_command_grid, "", func():
		if run.order(faction, _selected, _fleet_index):
			Conquest.persist())
	_production = _button(_command_grid, "Planet production", _show_production)
	_scout = _button(_command_grid, "Send probe", _show_probe_origins)
	_fleet_deck = _button(_command_grid, "Inspect fleet deck", _show_fleet)
	_battle = _button(_command_grid, "Enter battle", func(): Conquest.play_battle(run.player_battle()))
	var change := _button(_command_grid, "New conquest…", _confirm_new)
	change.add_theme_color_override("font_color", Sabacc.C_DIM)
	for button in _command_grid.get_children():
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_on_resize()
	_refresh()
	await get_tree().process_frame
	_layout_overlays()
	_map.center_on(_selected)


func _open_planet() -> void:
	_close_planet()
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var view := PLANET_VIEW.new()
	_planet_view = view
	view.run = Conquest.run
	view.world = _selected
	view.art = GALAXY.supplied_planet(_selected)
	if not view.art:
		view.art = _map._planet_art.get(_selected)
	view.map_position = _map.get_global_transform() * _map.world_position(_selected)
	view.map_diameter = 28.0 * _map.zoom if view.art else 12.0 * _map.zoom
	view.safe_area = safe_rect()
	view.dismissed.connect(_close_planet)
	view.manage_requested.connect(_show_production)
	view.fleet_requested.connect(_show_fleet)
	view.order_requested.connect(func():
		_orders.pressed.emit()
		_close_planet())
	view.scout_requested.connect(_show_probe_origins)
	view.battle_requested.connect(func(): _battle.pressed.emit())
	layer.add_child(view)
	UIKit.fill_rect(view)
	header.hide()
	body.hide()
	_refresh()


func _close_planet() -> void:
	if is_instance_valid(_planet_view):
		_planet_view.hide()
		_planet_view.set_process_input(false)
		_planet_view.get_parent().queue_free()
		header.show()
		body.show()
	_planet_view = null


func _button(parent: Container, text: String, call: Callable) -> Button:
	var button := SabaccButton.make(text, SabaccButton.Style.GHOST)
	button.pressed.connect(call)
	parent.add_child(button)
	return button


func _refresh() -> void:
	if not _status or not Conquest.run:
		return
	var run := Conquest.run
	var faction := int(run.state["player"])
	var side: Dictionary = run.state["factions"][faction]
	var sites: Dictionary = run.state["worlds"]
	if not sites.has(_selected):
		return
	var world: Dictionary = sites[_selected]
	var holder := int(world["owner"])
	var territory := GALAXY.territory_identity(_selected, holder)
	var held := sites.values().filter(func(site): return int(site["owner"]) == faction).size()
	_status.text = "%d credits   ·   %d/%d planets" % [side["credits"], held, sites.size()]
	_status.tooltip_text = "+%d credits every %ds from held planets" % [held * ConquestRun.INCOME_PER_WORLD, ConquestRun.INCOME_PERIOD]
	var specialty: String = GALAXY.SPECIALTIES.get(_selected, "")
	var visible := run.visible_to(faction, _selected)
	var detail := "Reconnaissance needed"
	if visible:
		var structures: Array = world["facilities"].map(func(item): return ConquestRun.FACILITIES[item][0])
		detail = "%d reserve cards%s" % [world["cards"].size(), " · " + ", ".join(structures) if not structures.is_empty() else ""]
		if not world["orbital_cards"].is_empty():
			detail += "\n%d orbital defenders" % world["orbital_cards"].size()
	_world_info.text = "%s · %s%s\n%s" % [GALAXY.display_name(_selected), territory["name"],
		" · " + specialty.capitalize() if not specialty.is_empty() else "", detail]
	_world_info.add_theme_color_override("font_color", territory["color"])
	if not _fleet_picker.get_popup().visible:
		_fleet_picker.clear()
		for task in run.fleets(faction):
			var name: String = CardDB.card(task["leader"]).get("name", "Fleet") if task["leader_alive"] else "Defense-only fleet"
			_fleet_picker.add_item("%s · %d cards" % [name, task["cards"].size()])
		_fleet_picker.select(_fleet_index)
	_fleet_picker.visible = _fleet_picker.item_count > 1
	var fleet := run.fleet(faction, _fleet_index)
	var route := run.path(faction, fleet["world"], _selected) if run.idle(fleet) else []
	var pending := run.player_battle()
	var active: bool = run.state["status"] == "active"
	_orders.disabled = not active or route.is_empty() or not fleet["leader_alive"] or fleet["cards"].is_empty()
	_orders.text = "Attack planet" if holder != faction else "Move fleet"
	_production.disabled = not active or holder != faction
	_scout.visible = active and holder != faction
	_fleet_deck.disabled = fleet["cards"].is_empty()
	_battle.visible = not pending.is_empty()
	if not pending.is_empty():
		_battle.text = "Battle for " + str(run.state["battles"][pending]["world"])
	var report: String = run.state["report"]
	if not fleet["route"].is_empty():
		report = "%s to %s · %ds" % ["Retreating" if fleet["retreating"] else "Fleet",
			GALAXY.display_name(fleet["route"][0]), ceili(maxf(0.0, float(fleet["arrival"]) - float(run.state["time"])))]
	elif not fleet["leader_alive"] and not fleet["world"].is_empty() and pending.is_empty():
		report = "Defense only at %s. Build and send a replacement commander from Production." % GALAXY.display_name(fleet["world"])
	elif fleet["leader_alive"] and int(fleet["command_damage"]) > 0 and pending.is_empty():
		var hp := run.command_max_hp(fleet)
		report = "Commander at %d/%d HP · restores 10 HP every minute outside battle" % [hp - int(fleet["command_damage"]), hp]
	elif not fleet["world"].is_empty() and route.is_empty() and fleet["world"] != _selected and pending.is_empty():
		report = "Select a planet connected through friendly territory."
	elif fleet["world"].is_empty() and pending.is_empty():
		report = "Commission a fleet from a planet with at least %d reserve cards." % ConquestRun.MIN_FLEET
	if not active:
		report = "The galaxy is yours." if run.state["status"] == "won" else "Your faction has been defeated."
	_report.text = report
	if is_instance_valid(_planet_view):
		_planet_view.set_orders(_orders.text, not _orders.disabled, _scout.visible, _battle.visible)
		_planet_view.refresh()


func _show_fleet(index := -1) -> void:
	var run := Conquest.run
	var faction := int(run.state["player"])
	var fleet := run.fleet(faction, _fleet_index if index < 0 else index)
	var modal := ModalPanel.open(self, 500, Sabacc.C_GOLD)
	modal.text("Fleet deck · %d cards" % fleet["cards"].size(), 26)
	modal.text("Up to 3 copies per card · 1 for unique cards", 16, Sabacc.C_DIM)
	var leader := CardDB.card(fleet["leader"])
	if fleet["leader_alive"]:
		var hp := run.command_max_hp(fleet)
		modal.text("%s · %d/%d HP" % [leader["name"], hp - int(fleet["command_damage"]), hp], 19)
	else:
		modal.text("Defense only until a replacement commander arrives", 19)
	for id in _counts(fleet["cards"]):
		modal.text("%d× %s" % [fleet["cards"].count(id), CardDB.card(id)["name"]], 18, Sabacc.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	modal.add_action(SabaccButton.make("Back", SabaccButton.Style.GHOST)).pressed.connect(modal.close)


func _counts(cards: Array) -> Array:
	var unique := []
	for id in cards:
		if not id in unique:
			unique.append(id)
	unique.sort_custom(func(a, b): return CardDB.card(a)["name"] < CardDB.card(b)["name"])
	return unique


func _show_production() -> void:
	var run := Conquest.run
	var faction := int(run.state["player"])
	var world := _selected
	var planet: Dictionary = run.state["worlds"][world]
	var modal := ModalPanel.open(self, 550, Sabacc.C_GOLD)
	modal.text(GALAXY.display_name(world) + " · Production", 26)
	var info := modal.text("", 19)
	var items := {}
	var local_recruits := GALAXY.native_recruits(world, faction)
	for id in local_recruits:
		items[id] = "Recruit " + str(local_recruits[id])
	for id in ConquestRun.FACILITIES:
		if not id in planet["facilities"]:
			items[id] = "Build " + str(ConquestRun.FACILITIES[id][0]).to_lower()
	var catalog := _button(modal.box, "Factory catalog", func():
		modal.close()
		_show_factory(world))
	if not local_recruits.is_empty():
		_button(modal.box, "Local card catalog", func():
			modal.close()
			_show_factory(world, 0, true))
	if "garrison" in planet["facilities"]:
		items["troops"] = "Replenish garrison"
	if "orbital" in planet["facilities"]:
		items["repair_orbit"] = "Replenish defense fleet"
	items["probe"] = "Build probe droid"
	if run.fleet(faction)["world"].is_empty():
		items["commission"] = "Recommission primary fleet"
	var replacement := _button(modal.box, "Build replacement commander · %d credits" % run.price("commission"), func():
		modal.close()
		_show_commanders(world, true))
	var training := _button(modal.box, "Train selected fleet", func():
		modal.close()
		_show_training(world))
	var milestone := run.available_milestone(faction)
	if milestone > 0:
		var hire := _button(modal.box, "%d planets · commission leader" % milestone, func():
			modal.close()
			_show_commanders(world))
		hire.disabled = run.commissioning_cards(world).size() < ConquestRun.MIN_FLEET or int(run.state["factions"][faction]["credits"]) < run.price("commission")
		modal.text("New fleets require 8 eligible reserve cards and %d credits." % run.price("commission"), 16)
	var options := {}
	for item in items:
		var button := _button(modal.box, "%s · %d credits" % [items[item], run.price(item)], func():
			if run.buy(faction, world, item):
				Conquest.persist()
				modal.close()
				_show_production())
		options[item] = button
	var transfers := VBoxContainer.new()
	modal.add(transfers)
	var transfer_buttons := {}
	for id in _counts(planet["cards"]):
		var button := _button(transfers, "Send %s · %d in reserve" % [CardDB.card(id)["name"], planet["cards"].count(id)], func():
			if run.transfer(faction, world, [id], _fleet_index):
				Conquest.persist()
				modal.close()
				_show_production())
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		transfer_buttons[id] = button
	var refresh := func():
		info.text = "%d credits · %d reserves · %d probes\n%d / 2 building slots · 1 factory maximum" % [
			run.state["factions"][faction]["credits"], planet["cards"].size(), planet["probes"], planet["facilities"].size()]
		for item in options:
			options[item].disabled = not run.can_buy(faction, world, item)
		catalog.visible = not run._factory(world).is_empty()
		catalog.disabled = not run._can_manage(faction, world)
		var task := run.fleet(faction, _fleet_index)
		replacement.visible = not task["leader_alive"] and not task["world"].is_empty()
		replacement.disabled = not run.can_send_replacement(faction, world, _fleet_index)
		training.visible = "training" in planet["facilities"]
		training.disabled = not run.idle(task) or task["world"] != world or int(planet["owner"]) != faction or run._contested(world)
		var reachable: bool = run.idle(task) and (task["world"] == world or not run.path(faction, world, task["world"], true).is_empty())
		var eligible := run.transfer_candidates(faction, _fleet_index, planet["cards"])
		for id in transfer_buttons:
			var button: Button = transfer_buttons[id]
			button.disabled = not reachable or not id in eligible or int(planet["owner"]) != faction or run._contested(world)
			button.tooltip_text = "Fleet or card copy limit reached" if not id in eligible else ""
	Conquest.changed.connect(refresh)
	modal.tree_exiting.connect(func():
		if Conquest.changed.is_connected(refresh):
			Conquest.changed.disconnect(refresh))
	refresh.call()
	modal.add_action(SabaccButton.make("Back", SabaccButton.Style.GHOST)).pressed.connect(modal.close)


func _show_factory(world: String, page := 0, local := false) -> void:
	var run := Conquest.run
	var faction := int(run.state["player"])
	var cards := run.factory_catalog(faction, world, local)
	var factory := run._factory(world)
	var modal := ModalPanel.open(self, 650, Sabacc.C_GOLD)
	var factory_name: String = ConquestRun.FACILITIES[factory][0] if not factory.is_empty() else "Factory"
	if local:
		factory_name = "Local card catalog"
	modal.text("%s · %s" % [GALAXY.display_name(world), factory_name], 25)
	var info := modal.text("", 17)
	if cards.is_empty():
		modal.text("No cards available to manufacture.", 17)
	var buttons := {}
	var offset := page * 10
	for count in [2, 3, 2, 3]:
		if offset >= cards.size():
			break
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		modal.add(row)
		for id in cards.slice(offset, offset + count):
			var preview := FACTORY_CARD.new()
			preview.card = CardDB.card(id)
			preview.credits = run.manufacture_price(id)
			preview.pressed.connect(func():
				if run.manufacture(faction, world, id, local):
					Conquest.persist())
			row.add_child(preview)
			buttons[id] = preview
		offset += count
	var refresh := func():
		info.text = "%d credits · %d/%d reserves · Tap a card to manufacture" % [
			run.state["factions"][faction]["credits"], run.state["worlds"][world]["cards"].size(), ConquestRun.RESERVE_LIMIT]
		for id in buttons:
			buttons[id].disabled = not run.can_manufacture(faction, world, id, local)
			buttons[id].queue_redraw()
	Conquest.changed.connect(refresh)
	modal.tree_exiting.connect(func():
		if Conquest.changed.is_connected(refresh):
			Conquest.changed.disconnect(refresh))
	refresh.call()
	var navigation := HBoxContainer.new()
	modal.add_action(navigation)
	for delta in [-1, 1]:
		var button := _button(navigation, "Previous" if delta < 0 else "Next", func():
			modal.close()
			_show_factory(world, page + delta, local))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = page + delta < 0 or (page + delta) * 10 >= cards.size()
	var back := _button(navigation, "Back", func():
		modal.close()
		_show_production())
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _show_training(world: String, perk := "", unit_id := "") -> void:
	var run := Conquest.run
	var faction := int(run.state["player"])
	var task := run.fleet(faction, _fleet_index)
	var modal := ModalPanel.open(self, 550, Sabacc.C_GOLD)
	modal.text("Training Center · " + GALAXY.display_name(world), 26)
	modal.text("%d credits available" % run.state["factions"][faction]["credits"], 18)
	if perk.is_empty():
		for key in ConquestRun.TRAINING:
			var item: Array = ConquestRun.TRAINING[key]
			var cost := run.price(key)
			if key in ["experience", "shield", "opening", "equipment"]:
				_button(modal.box, "%s · %d credits" % [item[0], cost], func():
					modal.close()
					_show_training(world, key)).disabled = run.training_rank(task, key) >= int(item[2])
			else:
				_button(modal.box, "%s · %d/%d · %d credits" % [item[0], run.training_rank(task, key), item[2], cost], func():
					if run.train(faction, world, _fleet_index, key):
						Conquest.persist()
						modal.close()
						_show_training(world)).disabled = not run.can_train(faction, world, _fleet_index, key)
	elif perk == "equipment" and not unit_id.is_empty():
		modal.text("Equipment for " + str(CardDB.card(unit_id)["name"]), 19)
		for id in run.equipment_for(unit_id):
			var equipment := CardDB.card(id)
			_button(modal.box, "%s · %+d power · %+d HP" % [equipment["name"], equipment.get("power", 0), equipment.get("hp", 0)], func():
				if run.train(faction, world, _fleet_index, perk, unit_id, id):
					Conquest.persist()
					modal.close()
					_show_training(world)).disabled = not run.can_train(faction, world, _fleet_index, perk, unit_id)
	else:
		modal.text(str(ConquestRun.TRAINING[perk][0]), 19)
		for id in _counts(task["cards"]):
			var card := CardDB.card(id)
			if card.get("type") != "unit":
				continue
			_button(modal.box, str(card["name"]) + " · " + str(card.get("subtitle", card.get("arena", ""))), func():
				if perk == "equipment":
					modal.close()
					_show_training(world, perk, id)
				elif run.train(faction, world, _fleet_index, perk, id):
					Conquest.persist()
					modal.close()
					_show_training(world)).disabled = not run.can_train(faction, world, _fleet_index, perk, id)
	modal.add_action(SabaccButton.make("Back", SabaccButton.Style.GHOST)).pressed.connect(func():
		modal.close()
		if perk.is_empty():
			_show_production()
		elif not unit_id.is_empty():
			_show_training(world, perk)
		else:
			_show_training(world))


func _show_commanders(world: String, replacing := false) -> void:
	var run := Conquest.run
	var faction := int(run.state["player"])
	var modal := ModalPanel.open(self, 620, Sabacc.C_GOLD)
	modal.text(("Build a replacement at " if replacing else "Commission a fleet at ") + GALAXY.display_name(world), 26)
	for id in run.eligible_commanders(faction, world):
		var leader := CardDB.card(id)
		var label := "%s · %s" % [leader["name"], leader.get("subtitle", "")]
		if leader.get("custom", false):
			label += " (Conquest)"
		var button := _button(modal.box, label, func():
			var built := run.send_replacement(faction, world, _fleet_index, id) if replacing else run.build_commander(faction, world, id)
			if built:
				if not replacing:
					_fleet_index = run.fleets(faction).size() - 1
				_map.fleet_index = _fleet_index
				Conquest.persist()
				modal.close())
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal.add_action(SabaccButton.make("Back", SabaccButton.Style.GHOST)).pressed.connect(modal.close)


func _show_probe_origins() -> void:
	var run := Conquest.run
	var faction := int(run.state["player"])
	var goal := _selected
	var modal := ModalPanel.open(self, 510, Sabacc.C_GOLD)
	modal.text("Reconnaissance · " + GALAXY.display_name(goal), 24)
	var offered := false
	for world in run.state["worlds"]:
		var site: Dictionary = run.state["worlds"][world]
		if int(site["owner"]) != faction or int(site["probes"]) <= 0 or run.path(faction, world, goal).is_empty():
			continue
		offered = true
		_button(modal.box, "Launch from " + GALAXY.display_name(world), func():
			if run.launch_probe(faction, world, goal):
				Conquest.persist()
				modal.close())
	if not offered:
		modal.text("Build a probe droid on a connected friendly planet first.", 19)
	modal.add_action(SabaccButton.make("Back", SabaccButton.Style.GHOST)).pressed.connect(modal.close)


func _show_saves() -> void:
	var modal := ModalPanel.open(self, 550, Sabacc.C_GOLD)
	modal.text("Conquest saves", 28)
	var title := LineEdit.new()
	title.placeholder_text = "Save name"
	title.max_length = 50
	modal.add(title)
	var status := modal.text("Choose a slot to save or load.", 18)
	for slot in [1, 2, 3]:
		var saved := Conquest.get_slot(slot)
		var caption := modal.text("Slot %d · %s" % [slot, saved.get("title", "Empty")], 19)
		var row := HBoxContainer.new()
		modal.add(row)
		var load_button := _button(row, "Load slot %d" % slot, func():
			modal.close()
			if Conquest.load_slot(slot):
				_selected = ""
				_fleet_index = 0
				_show_galaxy())
		load_button.disabled = saved.is_empty()
		var save_button := _button(row, "Save to slot %d" % slot, func():
			var label := title.text.strip_edges()
			if label.is_empty():
				label = "Conquest %d" % slot
			if Conquest.save_slot(slot, label):
				caption.text = "Slot %d · %s" % [slot, label]
				load_button.disabled = false
				status.text = "Saved to slot %d." % slot
			else:
				status.text = "The save could not be written.")
		save_button.disabled = Conquest.run == null
	modal.add_action(SabaccButton.make("Back", SabaccButton.Style.GHOST)).pressed.connect(modal.close)


func _confirm_new() -> void:
	var modal := ModalPanel.open(self, 510, Sabacc.C_GOLD)
	modal.text("Start another conquest?", 26)
	modal.text("Launching a new galaxy replaces this campaign save.", 19)
	var yes := SabaccButton.make("Choose a new faction", SabaccButton.Style.PRIMARY)
	yes.pressed.connect(func():
		modal.close()
		_show_setup())
	modal.add(yes)
	modal.add_action(SabaccButton.make("Cancel", SabaccButton.Style.GHOST)).pressed.connect(modal.close)
