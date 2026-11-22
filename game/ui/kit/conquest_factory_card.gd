extends Button
## Selectable Sabacc card in a planet's production catalog.

var card: Dictionary
var credits: int
var _art: Texture2D
var _name_label: Label
var _price_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(158, 151)
	for key in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(key, StyleBoxEmpty.new())
	tooltip_text = "%s · %d credits to build · %d resources to play" % [card["name"], credits, card["cost"]]
	if card.get("implemented") in ["partial", "manual"]:
		tooltip_text += "\nSome printed abilities are pending implementation."
	_art = Art.request(card.get("art", card["id"]), func(texture):
		_art = texture
		queue_redraw())
	_name_label = UIKit.label(card["name"], 17, Sabacc.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.max_lines_visible = 2
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_name_label)
	_price_label = UIKit.label("%d credits" % credits, 16, Sabacc.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_price_label)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_name_label.position = Vector2(3, 86)
	_name_label.size = Vector2(size.x - 6, 47)
	_price_label.position = Vector2(3, 133)
	_price_label.size = Vector2(size.x - 6, 18)
	queue_redraw()


func _draw() -> void:
	if card.is_empty():
		return
	var face := Rect2(12, 4, size.x - 24, 75)
	var aspects: Array = card.get("aspects", [])
	var accent := UnitToken.frame_color(aspects)
	for depth in [8.0, 4.0]:
		var layer := UnitToken.silhouette(Rect2(face.position + Vector2(0, depth), face.size))
		draw_colored_polygon(layer, Color("#0c1722"))
		UnitToken.draw_outline(self, layer, Color(accent, 0.30), 1.4)
	var outline := UnitToken.silhouette(face)
	UnitToken.draw_alignment_edge(self, outline, aspects, 0.75)
	UnitToken.draw_art(self, face, outline, _art, Color("#8994a7") if disabled else Color.WHITE, UnitToken.ART_UV)
	UnitToken.draw_face_frame(self, outline, Sabacc.C_GOLD if is_hovered() and not disabled else accent, 0.85)
	var badge := face.position + Vector2(8, 13)
	draw_circle(badge, 12, Color("#101b28"), true, -1.0, true)
	draw_arc(badge, 12, 0, TAU, 20, Sabacc.C_GOLD, 1.3, true)
	UIKit.draw_fit(self, Sabacc.font_title, badge + Vector2(-11, 5), str(int(card["cost"])), HORIZONTAL_ALIGNMENT_CENTER, 22, 15, Sabacc.C_TEXT)
