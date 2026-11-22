extends VBoxContainer

signal changed

const SET_ART = preload("res://ui/kit/set_art.gd")
const TYPES := {"unit": "Units", "event": "Events", "upgrade": "Upgrades", "leader": "Leaders", "base": "Bases"}

var available_types: Array = TYPES.keys()
var deck_mode := false
var unlocked_only := false
var deck_aspects_only := true
var scope := {}
var modal_layer := 30
var search: LineEdit
var filters := {"aspects": []}
var _set_button: Button
var _set_logo: TextureRect
var _more: Button
var _aspects: HBoxContainer
var _options := {}


func _ready() -> void:
	add_theme_constant_override("separation", 7)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	search = LineEdit.new()
	search.placeholder_text = "Search cards"
	search.custom_minimum_size.y = 46
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_text): changed.emit())
	top.add_child(search)
	_more = Button.new()
	_more.pressed.connect(_open_filters)
	top.add_child(_more)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_set_button = Button.new()
	_set_button.custom_minimum_size = Vector2(105, 44)
	_set_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_button.pressed.connect(_open_sets)
	row.add_child(_set_button)
	_set_logo = _logo("", Vector2.ZERO)
	_set_logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_set_logo.offset_left = 7
	_set_logo.offset_right = -7
	_set_logo.offset_top = 5
	_set_logo.offset_bottom = -5
	_set_button.add_child(_set_logo)
	_aspects = HBoxContainer.new()
	_aspects.add_theme_constant_override("separation", 5)
	row.add_child(_aspects)
	for aspect in AspectIcon.ORDER:
		var icon := AspectIcon.make(aspect, 35.0, true)
		icon.pressed.connect(func(id):
			var selected: Array = filters["aspects"]
			if id in selected:
				selected.erase(id)
			else:
				selected.append(id)
			_notify())
		_aspects.add_child(icon)
	_sync()


func results() -> Array:
	var query_filters := scope.duplicate()
	query_filters.merge(filters, true)
	if unlocked_only:
		query_filters["ids"] = Progression.owned_ids()
	return CardDB.lib.query(search.text, query_filters)


func _sync() -> void:
	var code: String = filters.get("set", "")
	var caption := "All sets" if code.is_empty() else CardLibrary.expansion_title(code)
	_set_logo.texture = SET_ART.texture(code, "logo")
	_set_logo.visible = _set_logo.texture != null
	_set_button.text = "" if _set_logo.visible else caption
	_set_button.tooltip_text = caption
	var count := 0
	for key in ["type", "keyword", "trait", "rarity", "arena"]:
		count += int(not str(filters.get(key, "")).is_empty())
	_more.text = "Filters (%d)" % count if count else "Filters"


func _notify() -> void:
	_sync()
	changed.emit()


func _logo(code: String, minimum: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = SET_ART.texture(code, "logo")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = minimum
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _open_sets() -> void:
	var panel := ModalPanel.open(self, 520.0)
	panel._layer.layer = modal_layer
	panel.dismiss_on_backdrop = true
	panel.text("Release Set", 26)
	var sets := {}
	for card in CardDB.lib.cards.values():
		if not card.get("custom", false):
			var code: String = card.get("set", "")
			if not code.is_empty():
				sets[code] = true
	var order := CardLibrary.SET_NAMES.keys()
	for code in sets:
		if code not in order:
			order.append(code)
	for code in [""] + order:
		if not code.is_empty() and not sets.has(code):
			continue
		var button := Button.new()
		button.custom_minimum_size.y = 60
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 12)
		UIKit.fill_rect(row)
		row.offset_left = 12
		row.offset_right = -12
		if SET_ART.texture(code, "logo"):
			row.add_child(_logo(code, Vector2(115, 46)))
		var name := UIKit.fit_label(UIKit.label("All sets" if code.is_empty() else CardLibrary.expansion_title(code), 18))
		name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		button.add_child(row)
		button.pressed.connect(func():
			filters["set"] = code
			_notify()
			panel.close())
		panel.add(button)


func _open_filters() -> void:
	var panel := ModalPanel.open(self, 520.0)
	panel._layer.layer = modal_layer
	panel.dismiss_on_backdrop = true
	panel.text("Card Filters", 26)
	_collect_options()
	if available_types.size() > 1:
		_add_options(panel, "type", "Card type", available_types, TYPES)
	_add_options(panel, "keyword", "Keyword", _options["keyword"])
	_add_options(panel, "trait", "Trait", _options["trait"])
	_add_options(panel, "rarity", "Rarity", _options["rarity"])
	_add_options(panel, "arena", "Arena", ["ground", "space"])
	var owned := CheckButton.new()
	owned.text = "Unlocked only"
	owned.button_pressed = unlocked_only
	owned.toggled.connect(func(on): unlocked_only = on; changed.emit())
	panel.add(owned)
	if deck_mode:
		var matching := CheckButton.new()
		matching.text = "In my deck’s aspects"
		matching.button_pressed = deck_aspects_only
		matching.toggled.connect(func(on): deck_aspects_only = on; changed.emit())
		panel.add(matching)
	var reset := SabaccButton.make("Clear filters", SabaccButton.Style.GHOST)
	reset.pressed.connect(func():
		filters = {"aspects": []}
		for icon in _aspects.get_children():
			icon.on = false
		search.clear()
		_notify()
		panel.close())
	panel.add(reset)
	var done := SabaccButton.make("Done", SabaccButton.Style.GOLD)
	done.pressed.connect(panel.close)
	panel.add_action(done)


func _add_options(panel: ModalPanel, key: String, title: String, options: Array, labels := {}) -> void:
	panel.add(UIKit.label(title, 17, Sabacc.C_DIM))
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 46
	for value in [""] + options:
		picker.add_item("Any" if value.is_empty() else labels.get(value, value.capitalize()))
		var index := picker.item_count - 1
		picker.set_item_metadata(index, value)
		if value == filters.get(key, ""):
			picker.select(index)
	picker.item_selected.connect(func(index):
		filters[key] = picker.get_item_metadata(index)
		_notify())
	panel.add(picker)


func _collect_options() -> void:
	if not _options.is_empty():
		return
	var values := {"keyword": {}, "trait": {}, "rarity": {}}
	for card in CardDB.lib.cards.values():
		if card.get("custom", false) or card.get("type", "") not in available_types:
			continue
		for keyword in CardLibrary.keyword_names(card):
			values["keyword"][keyword] = true
		for trait_name in card.get("traits", []):
			values["trait"][trait_name] = true
		var rarity: String = card.get("rarity", "")
		if not rarity.is_empty():
			values["rarity"][rarity] = true
	for key in values:
		_options[key] = values[key].keys()
		_options[key].sort()
