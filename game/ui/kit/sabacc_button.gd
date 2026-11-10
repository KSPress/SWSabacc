class_name SabaccButton
extends Button
## Animated HUD button: hover glow + lift, press squash, release bounce,
## optional idle "breathing" glow for primary calls to action, optional icon glyph.

enum Style { PRIMARY, REBEL, EMPIRE, GOLD, GHOST }

var style := Style.REBEL
var breathe := false
var glyph := ""
var _icon: IconGlyph
var _tw: Tween
var _breath_t := 0.0


static func make(text: String, p_style := Style.REBEL, p_glyph := "", p_breathe := false) -> SabaccButton:
	var b := SabaccButton.new()
	b.text = text
	b.style = p_style
	b.glyph = p_glyph
	b.breathe = p_breathe
	return b


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size.y = maxf(custom_minimum_size.y, 56)
	add_theme_font_size_override("font_size", 22)
	_apply_style()
	Appearance.changed.connect(_apply_style)
	if glyph != "":
		_icon = IconGlyph.new()
		_icon.glyph = glyph
		_icon.color = _accent().lightened(0.2)
		_icon.custom_minimum_size = Vector2(28, 28)
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)
		alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_theme_constant_override("h_separation", 8)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	resized.connect(_on_resized)
	_on_resized()


func _apply_style() -> void:
	var col := _accent()
	var pad := 50 if glyph != "" else 16
	# Buttons with a set width (or that stretch) wrap long labels onto more lines;
	# buttons sized by their text keep their natural width so nothing is cut.
	var sized := custom_minimum_size.x >= 120.0 or size_flags_horizontal & Control.SIZE_EXPAND != 0
	if sized and autowrap_mode == TextServer.AUTOWRAP_OFF:
		autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for st in [["normal", UIKit.chamfer(Color(Sabacc.C_PANEL, 0.95), col, 10, 2, 6, Color(col, 0.35))],
			["hover", UIKit.chamfer(Sabacc.C_PANEL_HI, col.lightened(0.25), 10, 2, 14, Color(col, 0.6))],
			["pressed", UIKit.chamfer(Color(col, 0.25), col.lightened(0.4), 10, 3, 18, Color(col, 0.8))],
			["disabled", UIKit.chamfer(Color(Sabacc.C_PANEL, 0.5), Color(Sabacc.C_LINE, 0.5), 10, 2)]]:
		var sb: StyleBoxFlat = st[1]
		sb.content_margin_left = pad
		sb.content_margin_right = pad
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		add_theme_stylebox_override(st[0], sb)
	if _icon:
		_icon.color = col.lightened(0.2)


func _accent() -> Color:
	match style:
		Style.PRIMARY:
			return Appearance.color_at(0)
		Style.EMPIRE:
			return Sabacc.C_EMPIRE
		Style.GOLD:
			return Appearance.color_at(2)
		Style.GHOST:
			return Appearance.color_at(1).darkened(0.2)
	return Appearance.color_at(1)


func _on_resized() -> void:
	pivot_offset = size / 2.0
	if _icon:
		var x := 14.0 if text != "" else (size.x - 28) / 2.0
		_icon.position = Vector2(x, (size.y - 28) / 2.0)
		_icon.size = Vector2(28, 28)


func _process(dt: float) -> void:
	if breathe and not disabled:
		_breath_t += dt
		var k := 0.5 + 0.5 * sin(_breath_t * 3.0)
		self_modulate = Color(1, 1, 1).lerp(Color(1.25, 1.25, 1.35), k * 0.6)


func _anim_scale(target: Vector2, dur: float, trans := Tween.TRANS_QUAD) -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "scale", target, Sabacc.anim(dur)).set_trans(trans).set_ease(Tween.EASE_OUT)


func _on_hover(on: bool) -> void:
	if disabled:
		return
	if on:
		Sfx.play("hover")
	_anim_scale(Vector2(1.05, 1.05) if on else Vector2.ONE, 0.12)
	if _icon:
		_icon.spin = on


func _on_down() -> void:
	_anim_scale(Vector2(0.93, 0.93), 0.06)
	Sfx.play("click")


func _on_up() -> void:
	_anim_scale(Vector2.ONE, 0.35, Tween.TRANS_ELASTIC)
