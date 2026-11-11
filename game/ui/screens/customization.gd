extends ScreenBase

var _scroll: ScrollContainer
var _grid: GridContainer
var _kind := "emblem"
var _filter: OptionButton
var _info: Label
var _canvas: Control


func build() -> void:
	set_header("Profile & Cosmetics")
	_filter = OptionButton.new()
	for text in ["Profile emblems", "Player card backs", "Backgrounds"]:
		_filter.add_item(text)
	_filter.custom_minimum_size.y = 56
	_filter.item_selected.connect(func(i):
		_kind = ["emblem", "cardback", "background"][i]
		_populate())
	body.add_child(_filter)
	_info = UIKit.label("Win a match to earn one random new cosmetic. Emblems include their matching holographic background.", 18, Sabacc.C_DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_info)
	_scroll = TouchScroll.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_canvas)
	_canvas.add_child(_grid)
	Cosmetics.changed.connect(_populate)
	_populate()


func _populate() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var items: Array = Cosmetics.all_items().filter(func(item): return item["kind"] == _kind)
	if _kind == "background":
		items.insert(1, {"id": "emblem", "key": "background:emblem", "name": "Equipped emblem hologram", "kind": "background"})
	for item in items:
		var owned := Cosmetics.unlocked(item["key"])
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		box.custom_minimum_size.x = 190
		box.add_theme_constant_override("separation", 6)
		_grid.add_child(box)
		if _kind == "emblem" or item["id"] == "emblem":
			var badge := ProfileBadge.new()
			badge.emblem_id = item["id"] if _kind == "emblem" else Cosmetics.equipped("emblem")
			badge.custom_minimum_size = Vector2(190, 150)
			badge.modulate.a = 1.0 if owned else 0.35
			box.add_child(badge)
		elif _kind == "cardback":
			var image := TextureRect.new()
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			image.texture = Cosmetics.texture("cardback", item["id"])
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.custom_minimum_size = Vector2(190, 220)
			image.modulate.a = 1.0 if owned else 0.35
			box.add_child(image)
		else:
			if item["id"] == "datapad":
				var preview := UIKit.label("DATAPAD", 24, Appearance.color_at(), HORIZONTAL_ALIGNMENT_CENTER)
				preview.custom_minimum_size = Vector2(190, 100)
				box.add_child(preview)
			else:
				var scene := TextureRect.new()
				scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
				scene.texture = Art.ui_texture(item["id"])
				scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				scene.custom_minimum_size = Vector2(190, 130)
				scene.modulate.a = 1.0 if owned else 0.35
				box.add_child(scene)
		var selected: bool = Cosmetics.equipped(_kind) == item["id"]
		var button := SabaccButton.make(("Equipped · " if selected else ("Locked · " if not owned else "")) + item["name"], SabaccButton.Style.PRIMARY if selected else SabaccButton.Style.GHOST)
		button.custom_minimum_size = Vector2(190, 68)
		button.add_theme_font_size_override("font_size", 17)
		button.disabled = not owned
		button.pressed.connect(func(): Cosmetics.equip(_kind, item["id"]))
		box.add_child(button)
	if _kind == "background":
		var future := UIKit.label("Play mats · Future unlockable category", 18, Sabacc.C_DIM)
		future.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		future.custom_minimum_size.x = 190
		_grid.add_child(future)
	_on_resize()


func relayout(p: bool, rect: Rect2) -> void:
	_filter.position = Vector2.ZERO
	_filter.size = Vector2(rect.size.x, 56)
	_info.position = Vector2(0, 66)
	_info.size = Vector2(rect.size.x, 65)
	_scroll.position = Vector2(0, 140)
	_scroll.size = Vector2(rect.size.x, maxf(100, rect.size.y - 140))
	_grid.columns = maxi(1, int(rect.size.x / 210))
	_center_grid.call_deferred()


func _center_grid() -> void:
	var extent := _grid.get_combined_minimum_size()
	_canvas.custom_minimum_size = Vector2(maxf(0, _scroll.size.x - 16), extent.y)
	_grid.size = extent
	_grid.position = Vector2(maxf(0, (_canvas.custom_minimum_size.x - extent.x) / 2), 0)
