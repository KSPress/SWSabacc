extends Button
## Title-screen navigation in the style of a backlit datapad.

var glyph := ""
var pale := false
var accent := Color.WHITE
var _icon: IconGlyph
var _caption: Label


func _ready() -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	# Keep native Button text available to accessibility and UI navigation.
	add_theme_font_size_override("font_size", 1)
	_icon = IconGlyph.new()
	_icon.glyph = glyph
	add_child(_icon)
	_caption = UIKit.label(text.to_upper(), 24, Color("fff5eb"))
	_caption.add_theme_font_override("font", Sabacc.font_title)
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	Appearance.changed.connect(_retheme)
	resized.connect(_layout)
	mouse_entered.connect(_hovered)
	mouse_exited.connect(_refresh)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	button_down.connect(_pressed_down)
	button_up.connect(_refresh)
	_retheme()
	_layout()


func _retheme() -> void:
	var tint: Color = Appearance.preset()["accent"]
	accent = Color("fff5e3").lerp(tint, 0.15) if pale else tint.lightened(0.14)
	_icon.color = accent
	queue_redraw()


func _layout() -> void:
	var icon_size := size.y * 0.58
	_icon.size = Vector2.ONE * icon_size
	_icon.position = Vector2(size.y * 0.67 - icon_size / 2.0, (size.y - icon_size) / 2.0)
	var left := size.y * 1.44
	var available := maxf(1.0, size.x - left - size.y * 0.48)
	var font_size := mini(30, floori(size.y * 0.37))
	while font_size > 11 and Sabacc.font_title.get_string_size(_caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available:
		font_size -= 1
	_caption.add_theme_font_size_override("font_size", font_size)
	_caption.position = Vector2(left, 0)
	_caption.size = Vector2(available, size.y)
	queue_redraw()


func _hovered() -> void:
	if not disabled:
		Sfx.play("hover")
	_refresh()


func _pressed_down() -> void:
	Sfx.play("click")
	_refresh()


func _refresh() -> void:
	queue_redraw()


func _outline(inset: float, cut: float) -> PackedVector2Array:
	var right := size.x - inset
	var bottom := size.y - inset
	return PackedVector2Array([
		Vector2(inset + cut, inset), Vector2(right - cut, inset),
		Vector2(right, inset + cut), Vector2(right, bottom - cut),
		Vector2(right - cut, bottom), Vector2(inset + cut, bottom),
		Vector2(inset, bottom - cut), Vector2(inset, inset + cut),
	])


func _draw() -> void:
	if size.x < 30.0 or size.y < 24.0:
		return
	var active := is_hovered() or has_focus()
	var hue := accent.lightened(0.25) if active else accent
	var inset := 5.0
	var cut := minf(17.0, size.y * 0.2)
	var frame := _outline(inset, cut)
	var panel := Color("090e14").lerp(accent, 0.19 if button_pressed else (0.09 if active else 0.03))
	draw_colored_polygon(frame, panel)
	frame.append(frame[0])
	for width in [14.0, 8.0, 4.5]:
		draw_polyline(frame, Color(hue, (0.95 if active else 0.57) / width), width, true)
	draw_polyline(frame, hue, 2.0, true)
	var inner := _outline(inset + 5.0, cut - 3.0)
	inner.append(inner[0])
	draw_polyline(inner, Color(hue, 0.25), 1.0, true)
	var divider := size.y * 1.17
	draw_line(Vector2(divider, size.y * 0.25), Vector2(divider, size.y * 0.75), Color(hue, 0.8), 1.5, true)
	for i in 3:
		var point := Vector2(size.x - inset - 19.0 - i * 7.0, size.y - inset - 12.0)
		draw_line(point, point + Vector2(6, -6), Color(hue, 0.85), 2.4, true)
