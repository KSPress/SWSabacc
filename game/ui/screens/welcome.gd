extends ScreenBase

const Collection := preload("res://ui/screens/collection.gd")
var _scroll: ScrollContainer


func build() -> void:
	set_header("Welcome to SWU Sabacc", "")
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	body.add_child(layout)
	UIKit.fill_rect(layout)
	var explanation := UIKit.label("Choose a starting set. You’ll unlock both of its official decks, three boosters from that set, and 1,000 credits.", 23, Sabacc.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(explanation)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_scroll)
	var sets := VBoxContainer.new()
	sets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sets.add_theme_constant_override("separation", 12)
	_scroll.add_child(sets)
	for code in Progression.starting_sets():
		var title := CardLibrary.expansion_title(code)
		var pair := CardDB.official_pair(code)
		var leaders := "%s and %s" % [pair[0]["name"], pair[1]["name"]]
		var tile := Collection.set_banner(code, title, UIKit.label("Select", 20, Sabacc.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		tile.tooltip_text = leaders
		tile.pressed.connect(func(): _confirm(code, title, leaders))
		sets.add_child(tile)


func _confirm(code: String, title: String, leaders: String) -> void:
	var panel := ModalPanel.open(self, 580.0, Sabacc.C_GOLD)
	panel.text(title, 28, Sabacc.C_GOLD)
	panel.text(leaders + "\n3 booster packs and 1,000 credits", 20)
	var select := SabaccButton.make("Choose this set", SabaccButton.Style.PRIMARY)
	select.pressed.connect(func():
		if Progression.claim_starting_set(code):
			panel.close()
			Router.go("menu"))
	panel.add_action(select)
	var back := SabaccButton.make("Back", SabaccButton.Style.GHOST)
	back.pressed.connect(panel.close)
	panel.add_action(back)
