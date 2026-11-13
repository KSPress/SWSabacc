extends ScreenBase
## Collection Vault: browse every imported card (or only unlocked ones), search,
## filter by type/aspect/set, inspect, and drag cards around for fun.

const PAGE_PORTRAIT := 12
const PAGE_LANDSCAPE := 18

var _search: LineEdit
var _filters: HBoxContainer
var _aspects: HBoxContainer
var _set_opt: OptionButton
var _grid: GridContainer
var _pager: HBoxContainer
var _page_label: Label
var _results: Array = []
var _page := 0
var _type := ""
var _aspect := ""
var _set := ""
var _unlocked_only := false
var _count: Label
var _tools: HBoxContainer
var _set_filters: HBoxContainer
var _packs: Button


func build() -> void:
	set_header("Collection Vault")
	_tools = HBoxContainer.new()
	_tools.alignment = BoxContainer.ALIGNMENT_CENTER
	_tools.add_theme_constant_override("separation", 10)
	body.add_child(_tools)
	var decks := SabaccButton.make("Deck Builder", SabaccButton.Style.GHOST)
	decks.pressed.connect(func(): Router.go("decks"))
	_tools.add_child(decks)
	_packs = SabaccButton.make("", SabaccButton.Style.GOLD)
	_packs.pressed.connect(_pack_shop)
	_tools.add_child(_packs)
	Progression.changed.connect(_update_pack_count)
	_update_pack_count()
	_search = LineEdit.new()
	_search.placeholder_text = "Search name, trait or text…"
	_search.custom_minimum_size.y = 52
	_search.text_changed.connect(func(_t): _page = 0; _refresh())
	body.add_child(_search)
	_filters = HBoxContainer.new()
	_filters.add_theme_constant_override("separation", 6)
	body.add_child(_filters)
	for t in [["All", ""], ["Units", "unit"], ["Events", "event"], ["Upgrades", "upgrade"], ["Leaders", "leader"], ["Bases", "base"]]:
		var b := SabaccButton.make(t[0], SabaccButton.Style.GHOST)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 16)
		b.button_pressed = t[1] == _type
		var val: String = t[1]
		b.pressed.connect(func(): _type = val; _page = 0; _sync_toggles(); _refresh())
		b.set_meta("val", val)
		_filters.add_child(b)
	_aspects = HBoxContainer.new()
	_aspects.add_theme_constant_override("separation", 6)
	body.add_child(_aspects)
	for a in ["vigilance", "command", "aggression", "cunning", "heroism", "villainy"]:
		var chip := AspectChip.new()
		chip.aspect = a
		chip.custom_minimum_size = Vector2(46, 46)
		chip.pressed.connect(func():
			_aspect = "" if _aspect == a else a
			for c in _aspects.get_children():
				if c is AspectChip:
					c.on = c.aspect == _aspect
			_page = 0
			_refresh())
		_aspects.add_child(chip)
	_set_filters = HBoxContainer.new()
	_set_filters.add_theme_constant_override("separation", 8)
	body.add_child(_set_filters)
	_set_opt = OptionButton.new()
	_set_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_opt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_opt.add_item("All sets")
	_set_opt.set_item_metadata(0, "")
	var sets := {}
	for card in CardDB.lib.cards.values():
		if not card.get("custom", false) and card.get("set", "") != "":
			sets[card["set"]] = true
	for code in CardLibrary.SET_NAMES:
		if sets.erase(code):
			_add_set_option(_set_opt, code)
	for code in sets:
		_add_set_option(_set_opt, code)
	_set_opt.item_selected.connect(func(i):
		_set = _set_opt.get_item_metadata(i)
		_page = 0
		_refresh())
	_set_filters.add_child(_set_opt)
	var unl := SabaccButton.make("Unlocked only", SabaccButton.Style.GOLD)
	unl.toggle_mode = true
	unl.custom_minimum_size = Vector2(0, 46)
	unl.add_theme_font_size_override("font_size", 16)
	unl.toggled.connect(func(on): _unlocked_only = on; _page = 0; _refresh())
	_set_filters.add_child(unl)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	body.add_child(_grid)
	_pager = HBoxContainer.new()
	_pager.alignment = BoxContainer.ALIGNMENT_CENTER
	_pager.add_theme_constant_override("separation", 16)
	var prev := SabaccButton.make("‹ Prev", SabaccButton.Style.GHOST)
	prev.pressed.connect(func(): _page = maxi(0, _page - 1); _show_page())
	var nxt := SabaccButton.make("Next ›", SabaccButton.Style.GHOST)
	nxt.pressed.connect(func(): _page = mini(_pages() - 1, _page + 1); _show_page())
	_page_label = UIKit.label("", 18, Sabacc.C_DIM)
	_pager.add_child(prev)
	_pager.add_child(_page_label)
	_pager.add_child(nxt)
	body.add_child(_pager)
	_count = UIKit.label("", 15, Sabacc.C_DIM)
	body.add_child(_count)
	_refresh()


func _update_pack_count() -> void:
	_packs.text = "Card Packs (%d)" % Progression.packs().size()


func _add_set_option(options: OptionButton, code: String) -> void:
	options.add_item(CardLibrary.expansion_title(code))
	options.set_item_metadata(options.item_count - 1, code)


func _pack_shop() -> void:
	var panel := ModalPanel.open(self, 790.0, Sabacc.C_GOLD)
	panel.dismiss_on_backdrop = true
	panel.text("Card Packs", 30, Sabacc.C_GOLD)
	panel.add(UIKit.credit_label(str(Progression.credits())))
	var waiting := OptionButton.new()
	waiting.custom_minimum_size.y = 50
	for pack in Progression.packs():
		var code: String = pack.get("set", "")
		var title := "Mixed set rewards" if code.is_empty() else CardLibrary.expansion_title(code)
		waiting.add_item(title)
		waiting.set_item_metadata(waiting.item_count - 1, pack["id"])
	if waiting.item_count > 0:
		panel.add(waiting)
		var open := SabaccButton.make("Open packs (%d)" % waiting.item_count, SabaccButton.Style.PRIMARY)
		open.pressed.connect(func(): Router.go("packs", {"pack_id": waiting.get_selected_metadata()}))
		panel.add(open)
	var art := preload("res://ui/kit/set_art.gd")
	for code in art.SETS:
		var button := _booster_button(code, art.texture(code, "art"), art.texture(code, "logo"))
		button.pressed.connect(func():
			if Router._busy:
				return
			var id := Progression.buy_pack(code)
			if not id.is_empty():
				Router.go("packs", {"pack_id": id}))
		panel.add(button)
	var close := SabaccButton.make("Back", SabaccButton.Style.GHOST)
	close.pressed.connect(panel.close)
	panel.add_action(close)


func _booster_button(code: String, picture: Texture2D, logo: Texture2D) -> Button:
	var button := Button.new()
	button.text = "Buy pack · " + CardLibrary.expansion_title(code)
	button.tooltip_text = button.text
	button.custom_minimum_size.y = 230
	button.clip_contents = true
	button.disabled = Progression.credits() < Progression.PACK_PRICE
	button.add_theme_color_override("font_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_focus_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_disabled_color", Color.TRANSPARENT)
	var art := TextureRect.new()
	art.texture = picture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.fill_rect(art)
	button.add_child(art)
	var badge := TextureRect.new()
	badge.texture = logo
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.position = Vector2(12, 10)
	badge.size = Vector2(172, 66)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(badge)
	var price := UIKit.panel(Color("171522"), Sabacc.C_GOLD)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	price.offset_left = -158
	price.offset_top = -54
	price.offset_right = -10
	price.offset_bottom = -9
	var amount := UIKit.credit_label("1,000")
	price.add_child(amount)
	button.add_child(price)
	button.mouse_entered.connect(func(): price.modulate = Color("ffe5a4") if not button.disabled else Color.WHITE)
	button.mouse_exited.connect(func(): price.modulate = Color.WHITE)
	if button.disabled:
		art.modulate = Color(0.55, 0.55, 0.55)
	return button


func _sync_toggles() -> void:
	for c in _filters.get_children():
		(c as Button).button_pressed = c.get_meta("val") == _type


var _rows := 3
var _cols := 4


func _per_page() -> int:
	return _rows * _cols


func _pages() -> int:
	return maxi(1, ceili(_results.size() / float(_per_page())))


func _refresh() -> void:
	var f := {"type": _type, "aspect": _aspect, "set": _set}
	if _unlocked_only:
		f["ids"] = Progression.owned_ids()
	_results = CardDB.lib.query(_search.text if _search else "", f)
	_show_page()


func _show_page() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var per := _per_page()
	var start := _page * per
	var cols := _cols
	var rows := _rows
	var avail_w := body.size.x - (cols - 1) * 10
	var avail_h := maxf(48, body.size.y - _grid.position.y - 96)
	var sc := minf(avail_w / cols / CardView.PORTRAIT.x, (avail_h - (rows - 1) * 10) / rows / CardView.PORTRAIT.y)
	var i := 0
	for id in _results.slice(start, start + per):
		var slot := Control.new()
		slot.custom_minimum_size = CardView.PORTRAIT * sc
		var cv := CardView.create(id)
		var land := cv.is_landscape()
		var csc := sc * (CardView.PORTRAIT.x / CardView.LANDSCAPE.x) if land else sc
		cv.pivot_offset = Vector2.ZERO
		cv.home_scale = Vector2(csc, csc)
		cv.scale = cv.home_scale
		cv.home_pos = Vector2(0, (CardView.PORTRAIT.y * sc - cv.size.y * csc) / 2.0) if land else Vector2.ZERO
		cv.position = cv.home_pos
		cv.hover_lift = false
		cv.drag_released.connect(func(c, _p): c.spring_home())
		cv.tapped.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		cv.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		if not Progression.owns(id):
			cv.modulate = Color(0.4, 0.4, 0.5)
		slot.add_child(cv)
		_grid.add_child(slot)
		UIKit.pop_in(cv, i * 0.02)
		i += 1
	_page_label.text = "Page %d / %d" % [_page + 1, _pages()]
	_count.text = "%d cards · %d unlocked in vault" % [_results.size(), Save.data.get("vault", []).size()]
	_center_grid.call_deferred()


func _center_grid() -> void:
	_grid.size.x = _grid.get_combined_minimum_size().x
	_grid.position.x = maxf(0, (body.size.x - _grid.size.x) / 2)


func relayout(p: bool, r: Rect2) -> void:
	var top := 296.0
	_tools.position = Vector2.ZERO
	_tools.size = Vector2(r.size.x, 56)
	if p:
		_search.position = Vector2(0, 64)
		_search.size = Vector2(r.size.x, 52)
		_filters.position = Vector2(0, 124)
		_filters.size = Vector2(r.size.x, 46)
		_aspects.position = Vector2(0, 186)
		_aspects.size = Vector2(r.size.x, 46)
	else:
		# one compact row: search | type filters, then aspects/sets
		var sw := r.size.x * 0.32
		_search.position = Vector2(0, 64)
		_search.size = Vector2(sw, 52)
		_filters.position = Vector2(sw + 12, 64)
		_filters.size = Vector2(r.size.x - sw - 12, 46)
		_aspects.position = Vector2(0, 124)
		_aspects.size = Vector2(r.size.x, 46)
		top = 174.0
	_set_filters.position = Vector2(0 if p else 300, 240 if p else 124)
	_set_filters.size = Vector2(r.size.x - (0 if p else 300), 46)
	_grid.position = Vector2(0, top)
	# as many readable cards (>= ~230 px tall) as fit
	var avail_h := maxf(48, r.size.y - top - 96)
	_rows = clampi(int(avail_h / 180.0), 1, 3)
	var card_h := (avail_h - (_rows - 1) * 10) / _rows
	var card_w := card_h * CardView.PORTRAIT.x / CardView.PORTRAIT.y
	_cols = clampi(int((r.size.x + 10) / (card_w + 10)), 2, 8)
	_grid.columns = _cols
	_grid.size = Vector2(r.size.x, avail_h)
	_pager.position = Vector2(0, r.size.y - 60)
	_pager.size = Vector2(r.size.x, 56)
	_count.position = Vector2(0, r.size.y - 86)
	_page = mini(_page, _pages() - 1)
	if _results.size() > 0:
		_show_page()


class AspectChip extends Control:
	signal pressed
	var aspect := ""
	var on := false:
		set(v):
			on = v
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = aspect.capitalize()

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var box := Rect2((size - Vector2(s * 0.91, s)) / 2.0, Vector2(s * 0.91, s))
		var tex := AspectIcon.texture(aspect)
		if on:
			draw_rect(box.grow(3), Color(Sabacc.C_GOLD, 0.8), false, 3.0)
		if tex:
			draw_texture_rect(tex, box, false, Color.WHITE if on else Color(0.5, 0.5, 0.55, 0.6))

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("click")
			pressed.emit()
			accept_event()
