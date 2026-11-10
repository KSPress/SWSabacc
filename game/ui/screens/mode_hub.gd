extends ScreenBase
var _box: VBoxContainer


func build() -> void:
	var campaigns: bool = Router.params.get("section", "campaigns") == "campaigns"
	set_header("Campaigns" if campaigns else "Battles")
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 18)
	body.add_child(_box)
	var entries := [
		["Saga Campaign", "Story episodes, branching encounters and treasures", "episodes", {}],
		["Spotlight Roguelike", "Build a deck through an endless run of sectors", "spotlight", {}],
	] if campaigns else [
		["Traditional Battle", "Standard Star Wars: Unlimited · one pack every two completed games", "quick", {"format": 0}],
		["Custom Battle", "One Lane, Ground, Space and other quick formats", "quick", {"format": 1}],
		["My Decks", "Build and edit decks using your unlocked collection", "decks", {}],
	]
	for entry in entries:
		var button := SabaccButton.make(entry[0], SabaccButton.Style.PRIMARY, "star" if campaigns else "fight")
		button.custom_minimum_size.y = 80
		button.pressed.connect(func(): Router.go(entry[2], entry[3]))
		_box.add_child(button)
		var text := UIKit.label(entry[1], 19, Sabacc.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(text)


func relayout(_p: bool, rect: Rect2) -> void:
	var width := minf(rect.size.x, 760)
	_box.position = Vector2((rect.size.x - width) / 2, 30)
	_box.size = Vector2(width, rect.size.y - 30)
