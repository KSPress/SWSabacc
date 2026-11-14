extends ScreenBase

const CardFilters = preload("res://ui/kit/card_filters.gd")
const CardScroll = preload("res://ui/kit/card_scroll.gd")

var _tools: HBoxContainer
var _packs: Button
var _filters: VBoxContainer
var _scroll: ScrollContainer
var _count: Label


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
	_filters = CardFilters.new()
	body.add_child(_filters)
	_filters.changed.connect(_refresh)
	_count = UIKit.label("", 16, Sabacc.C_DIM)
	body.add_child(_count)
	_scroll = CardScroll.new()
	body.add_child(_scroll)
	Progression.changed.connect(_on_progression_changed)
	_on_progression_changed()


func _on_progression_changed() -> void:
	_packs.text = "Card Packs (%d)" % Progression.packs().size()
	_refresh(false)


func _refresh(reset := true) -> void:
	var ids: Array = _filters.results()
	_count.text = "%d cards" % ids.size() if not ids.is_empty() else "No cards match these filters"
	_scroll.show_cards(ids, _make_tile, reset)


func _make_tile(id: String, cell: Vector2) -> Control:
	var tile := Control.new()
	var card := CardView.create(id)
	tile.add_child(card)
	CardScroll.place_card(card, cell)
	card.dim = not Progression.owns(id)
	card.tapped.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
	card.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
	return tile


func relayout(_p: bool, rect: Rect2) -> void:
	_tools.size = Vector2(rect.size.x, 56)
	_filters.position = Vector2(0, 64)
	_filters.size = Vector2(rect.size.x, 0)
	var top := _filters.position.y + _filters.get_combined_minimum_size().y + 6
	_count.position.y = top
	_scroll.position.y = top + 27
	_scroll.size = Vector2(rect.size.x, maxf(0, rect.size.y - _scroll.position.y))


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
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	badge.anchor_right = 0.49
	badge.offset_left = 12
	badge.offset_top = 10
	badge.offset_bottom = 112
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
