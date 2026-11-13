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
	var bar := Control.new()
	bar.custom_minimum_size.y = 22
	bar.resized.connect(bar.queue_redraw)
	bar.draw.connect(func():
		var total := wins + losses
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color("243140"))
		if total > 0:
			var split := bar.size.x * float(wins) / total
			bar.draw_rect(Rect2(0, 0, split, bar.size.y), Color("4289e8"))
			bar.draw_rect(Rect2(split, 0, bar.size.x - split, bar.size.y), Color("d34c59")))
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

	var aspect := _favorite(stats["aspects"], ["vigilance", "command", "aggression", "cunning"])
	var alignment := _favorite(stats["aspects"], ["heroism", "villainy"])
	var leader := _favorite(stats["leaders"], stats["leaders"].keys())
	var leader_card := CardDB.card(leader)
	var leader_name: String = leader_card.get("name", leader)
	var subtitle: String = leader_card.get("subtitle", "")
	if not subtitle.is_empty():
		leader_name += " · " + subtitle
	var expansion := _favorite(stats["boosters"], CardLibrary.BOOSTER_SETS)
	var packs_bought := 0
	for count in stats["boosters"].values():
		packs_bought += int(count)
	_add_stat(content, "Favorite Aspect", aspect.capitalize())
	_add_stat(content, "Hero or Villain", alignment.capitalize())
	_add_stat(content, "Favorite Leader", leader_name)
	_add_stat(content, "Total Credits Earned", str(int(stats["credits_earned"])))
	_add_stat(content, "Total Games Played", str(int(stats["matches"])))
	_add_stat(content, "Favorite Set", CardLibrary.expansion_title(expansion))
	_add_stat(content, "Total Boosters Purchased", str(packs_bought))


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
