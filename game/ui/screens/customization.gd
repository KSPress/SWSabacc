extends ScreenBase

var _scroll: ScrollContainer
var _grid: GridContainer
var _kind := "emblem"
var _filter: OptionButton
var _info: Label
var _canvas: Control
const LOCK_SHADER := "shader_type canvas_item; void fragment(){ vec4 c=texture(TEXTURE,UV)*COLOR; float g=dot(c.rgb,vec3(0.299,0.587,0.114)); COLOR=vec4(vec3(0.18+g*0.62),c.a*0.85); }"


func build() -> void:
	set_header("Profile & Cosmetics")
	_filter = OptionButton.new()
	for text in ["Profile emblems", "Player card backs", "Backgrounds"]:
		_filter.add_item(text)
	_filter.custom_minimum_size.y = 56
	_filter.item_selected.connect(func(i):
		_kind = ["emblem", "cardback", "background"][i]
		_scroll.scroll_vertical = 0
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
	var old_offset := _scroll.scroll_vertical
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var items: Array = Cosmetics.all_items().filter(func(item): return item["kind"] == _kind)
	if _kind == "background":
		items.insert(1, {"id": "emblem", "key": "background:emblem", "name": "Equipped emblem hologram", "kind": "background"})
	items.sort_custom(func(a, b):
		var a_rank := 2 if Cosmetics.equipped(_kind) == a["id"] else (1 if Cosmetics.unlocked(a["key"]) else 0)
		var b_rank := 2 if Cosmetics.equipped(_kind) == b["id"] else (1 if Cosmetics.unlocked(b["key"]) else 0)
		return a_rank > b_rank if a_rank != b_rank else str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	var count := 0
	for item in items:
		if Cosmetics.unlocked(item["key"]):
			count += 1
	_info.text = "%d / %d available · %s" % [count, items.size(), "GM grants access to every cosmetic. Your earned collection is preserved." if Cosmetics.state()["gm"] else "Win games and open packs to unlock more. Grey previews are still locked."]
	for item in items:
		var owned := Cosmetics.unlocked(item["key"])
		var selected: bool = Cosmetics.equipped(_kind) == item["id"]
		var box := CosmeticTile.new()
		box.selected = selected
		box.owned = owned
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		box.custom_minimum_size.x = 190
		box.add_theme_constant_override("separation", 6)
		_grid.add_child(box)
		if _kind == "background" and item["id"] in ["emblem", "datapad"]:
			var preview := DatapadBackground.new()
			preview.custom_minimum_size = Vector2(190, 150)
			preview.clip_contents = true
			preview.force_datapad = item["id"] == "datapad"
			preview.emblem_override = Cosmetics.equipped("emblem") if item["id"] == "emblem" else ""
			box.add_child(preview)
		elif _kind == "emblem":
			var badge := ProfileBadge.new()
			badge.draw_disc = owned
			badge.emblem_id = item["id"] if _kind == "emblem" else Cosmetics.equipped("emblem")
			badge.custom_minimum_size = Vector2(190, 150)
			badge.modulate.a = 1.0
			box.add_child(badge)
		elif _kind == "cardback":
			var image := TextureRect.new()
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			image.texture = Cosmetics.texture("cardback", item["id"])
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.custom_minimum_size = Vector2(190, 220)
			image.modulate.a = 1.0
			box.add_child(image)
		else:
			if item["id"] == "datapad":
				var preview := UIKit.label("DATAPAD", 24, Appearance.color_at(), HORIZONTAL_ALIGNMENT_CENTER)
				preview.custom_minimum_size = Vector2(190, 100)
				box.add_child(preview)
			else:
				var scene := TextureRect.new()
				scene.clip_contents = true
				scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
				scene.texture = Art.ui_texture(item["id"])
				scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				scene.custom_minimum_size = Vector2(190, 130)
				scene.modulate.a = 1.0
				box.add_child(scene)
		if not owned:
			var material := ShaderMaterial.new()
			var shader := Shader.new()
			shader.code = LOCK_SHADER
			material.shader = shader
			box.get_child(0).material = material
		var state_label := UIKit.label("EQUIPPED" if selected else ("UNLOCKED" if owned else "LOCKED · Earn through play"), 13, Appearance.color_at() if owned else Sabacc.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		box.add_child(state_label)
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
	_restore_scroll.call_deferred(old_offset)


func _restore_scroll(offset: int) -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = offset


class CosmeticTile extends VBoxContainer:
	var selected := false
	var owned := false
	func _draw() -> void:
		var border := Appearance.color_at() if selected else (Sabacc.C_LINE if owned else Color("343a43"))
		draw_style_box(UIKit.chamfer(Color(Sabacc.C_PANEL, 0.9), border, 10, 2, 8 if selected else 0), Rect2(Vector2.ZERO, size))


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
