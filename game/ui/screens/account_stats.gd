extends ScreenBase

var _scroll: ScrollContainer


func build() -> void:
	set_header("Account Stats")
	var stats := Progression.account_stats()
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	_scroll.add_child(content)

	var wins := int(stats["wins"])
	var draws := int(stats["draws"])
	var losses := maxi(0, int(stats["matches"]) - wins - draws)
	var results := UIKit.panel(Sabacc.C_PANEL, Sabacc.C_LINE)
	var chart := VBoxContainer.new()
	chart.add_theme_constant_override("separation", 10)
	chart.add_child(UIKit.label("Win / Loss Ratio", 24))
	var bar := SaberRatio.new()
	bar.wins = wins
	bar.losses = losses
	bar.custom_minimum_size.y = 32
	chart.add_child(bar)
	var counts := HBoxContainer.new()
	var win_label := UIKit.label("%d wins" % wins, 18, Color("74b4ff"))
	win_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	counts.add_child(win_label)
	counts.add_child(UIKit.label("%d losses" % losses, 18, Color("ff8792")))
	chart.add_child(counts)
	if draws > 0:
		chart.add_child(UIKit.label("%d draws" % draws, 16, Sabacc.C_DIM))
	results.add_child(chart)
	content.add_child(results)

	var aspect := _favorite(stats["played_aspects"], ["vigilance", "command", "aggression", "cunning"])
	var alignment := _favorite(stats["aspects"], ["heroism", "villainy"])
	var leader := _favorite(stats["leaders"], stats["leaders"].keys())
	var art := preload("res://ui/kit/set_art.gd")
	var expansion := _favorite(stats["boosters"], art.SETS)
	var packs_bought := 0
	for count in stats["boosters"].values():
		packs_bought += int(count)
	if aspect.is_empty():
		_add_stat(content, "Favorite Aspect", "")
	else:
		_center_item(content, "Favorite Aspect", AspectIcon.make(aspect, 65))
	if alignment.is_empty():
		_add_stat(content, "Hero or Villain", "")
	else:
		var alignment_box := VBoxContainer.new()
		alignment_box.alignment = BoxContainer.ALIGNMENT_CENTER
		var word := UIKit.aurebesh(alignment, 30, Color("fff0ae") if alignment == "heroism" else Color("de83ff"))
		word.visible = true
		word.tooltip_text = alignment.capitalize()
		alignment_box.add_child(word)
		var symbol := AspectIcon.make(alignment, 65)
		symbol.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		alignment_box.add_child(symbol)
		_center_item(content, "Hero or Villain", alignment_box)
	if leader.is_empty():
		_add_stat(content, "Favorite Leader", "")
	else:
		var tile := Control.new()
		var card := CardView.create(leader)
		tile.custom_minimum_size = CardView.LANDSCAPE * 0.82
		card.pivot_offset = Vector2.ZERO
		card.scale = Vector2.ONE * 0.82
		card.draggable = false
		card.hover_lift = false
		card.tapped.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		card.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		tile.add_child(card)
		_center_item(content, "Favorite Leader", tile)
	_center_item(content, "Total Credits Earned", UIKit.credit_label(str(int(stats["credits_earned"]))))
	_add_stat(content, "Total Games Played", str(int(stats["matches"])))
	var logo := art.texture(expansion, "logo")
	if logo:
		var image := TextureRect.new()
		image.texture = logo
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = Vector2(240, 86)
		image.tooltip_text = CardLibrary.expansion_title(expansion)
		_center_item(content, "Favorite Set", image)
	else:
		_add_stat(content, "Favorite Set", CardLibrary.expansion_title(expansion))
	_add_stat(content, "Total Boosters Purchased", str(packs_bought))


func _center_item(content: VBoxContainer, caption: String, item: Control) -> void:
	var panel := UIKit.panel(Sabacc.C_PANEL, Sabacc.C_LINE)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.add_child(UIKit.label(caption, 19, Sabacc.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(item)
	panel.add_child(column)
	content.add_child(panel)


func _favorite(counts: Dictionary, candidates: Array) -> String:
	var best := ""
	var most := 0
	for id in candidates:
		var count := int(counts.get(id, 0))
		if count > most or (count == most and count > 0 and str(id) < best):
			most = count
			best = str(id)
	return best


func _add_stat(content: VBoxContainer, caption: String, value: String) -> void:
	var panel := UIKit.panel(Sabacc.C_PANEL, Sabacc.C_LINE)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := UIKit.label(caption, 19, Sabacc.C_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var amount := UIKit.label("—" if value.is_empty() else value, 20, Sabacc.C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	amount.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(amount)
	panel.add_child(row)
	content.add_child(panel)


func relayout(_p: bool, rect: Rect2) -> void:
	var width := minf(760.0, rect.size.x)
	_scroll.position.x = (rect.size.x - width) * 0.5
	_scroll.size = Vector2(width, rect.size.y)

class SaberRatio extends Control:
	var wins := 0
	var losses := 0
	var time := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _process(delta: float) -> void:
		if not Sabacc.perf() and wins + losses > 0:
			time += delta
			queue_redraw()

	func _draw() -> void:
		var total := wins + losses
		var center := size.y / 2
		draw_line(Vector2(0, center), Vector2(size.x, center), Color("243140"), 4, true)
		if total == 0:
			return
		var split := size.x * float(wins) / total
		_blade(0.0, split, Color("458cff"), time)
		_blade(split, size.x, Color("ff404d"), time + 1.2)

	func _blade(start: float, finish: float, tint: Color, phase: float) -> void:
		if finish <= start:
			return
		var intensity := 0.78 + 0.14 * sin(phase * 17) + 0.08 * sin(phase * 37)
		var from := Vector2(start, size.y / 2)
		var to := Vector2(finish, size.y / 2)
		for width in [27.0, 18.0, 11.0]:
			draw_line(from, to, Color(tint, intensity * 2.7 / width), width, true)
		draw_line(from, to, Color(tint, intensity), 7.0, true)
		draw_line(from, to, tint.lerp(Color.WHITE, intensity * 0.85), 2.5, true)
