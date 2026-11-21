extends PanelContainer

const YES := preload("res://assets/branding/event_yes.png")
const NO := preload("res://assets/branding/event_no.png")
const BACKS := preload("res://assets/branding/cantina_war.png")
const KEY := preload("res://ui/kit/cantina_war_art.gdshader")

var _row := HBoxContainer.new()
var _choices: Array[Dictionary] = []
var _dealt := false

func _init() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var wood := ColorRect.new()
	var surface := ShaderMaterial.new()
	surface.shader = preload("res://ui/screens/sabacc_war_table.gdshader")
	surface.set_shader_parameter("octagonal", true)
	wood.material = surface
	wood.resized.connect(func():
		surface.set_shader_parameter("table_size", wood.size.max(Vector2.ONE)))
	wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wood)
	var padding := MarginContainer.new()
	padding.add_theme_constant_override("margin_top", 38)
	padding.add_theme_constant_override("margin_bottom", 38)
	padding.add_theme_constant_override("margin_left", 30)
	padding.add_theme_constant_override("margin_right", 30)
	_row.add_theme_constant_override("separation", 14)
	padding.add_child(_row)
	add_child(padding)


func add_choice(answer: String, caption: String, disabled: bool, choose: Callable) -> void:
	var slot := VBoxContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(slot)
	var face := AtlasTexture.new()
	face.atlas = YES if answer == "yes" else NO
	face.region = Rect2(275, 289, 1012, 1375)
	var card := TextureButton.new()
	card.name = answer.capitalize() + "Card"
	card.texture_normal = face
	card.ignore_texture_size = true
	card.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	card.custom_minimum_size.y = 160
	card.tooltip_text = caption
	card.accessibility_name = "%s · %s" % [answer.capitalize(), caption]
	card.disabled = disabled
	card.modulate.a = 0.42 if disabled else 1.0
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not disabled else Control.CURSOR_ARROW
	slot.add_child(card)
	var label := UIKit.label("%s · %s" % [answer.capitalize(), caption], 18, Sabacc.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate.a = card.modulate.a
	slot.add_child(label)
	_choices.append({"card": card, "label": label, "face": face, "disabled": disabled})
	card.mouse_entered.connect(func():
		if not card.disabled:
			card.self_modulate = Color(1.15, 1.15, 1.15))
	card.mouse_exited.connect(func(): card.self_modulate = Color.WHITE)
	card.pressed.connect(func():
		Sfx.play("click")
		choose.call())


func _ready() -> void:
	_deal.call_deferred()


func _deal() -> void:
	if _dealt or Sabacc.perf():
		return
	_dealt = true
	for entry in _choices:
		entry["card"].disabled = true
		entry["card"].modulate.a = 0.0
		entry["label"].modulate.a = 0.0
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var back := AtlasTexture.new()
	back.atlas = BACKS
	back.region = Rect2(1491, 35, 168, 243)
	back.filter_clip = true
	var key := ShaderMaterial.new()
	key.shader = KEY
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var motion := create_tween().set_parallel()
	for i in range(_choices.size() - 1, -1, -1):
		var entry := _choices[i]
		var card: TextureButton = entry["card"]
		var label: Label = entry["label"]
		var art := TextureRect.new()
		art.texture = back
		art.material = key
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(art)
		art.size = Vector2(minf(card.size.x, card.size.y * 0.74), card.size.y)
		art.pivot_offset = art.size / 2.0
		var center := card.get_global_rect().get_center() - global_position
		var start := Vector2(size.x * 0.5, center.y)
		art.position = start - art.pivot_offset + Vector2(3, 2) * i
		var delay := Sabacc.anim(0.12 * i)
		var slide := Sabacc.anim(0.32)
		var half_flip := Sabacc.anim(0.105)
		motion.tween_property(art, "position", center - art.pivot_offset, slide).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
		motion.tween_property(art, "scale:x", 0.0, half_flip).set_delay(delay + slide)
		motion.tween_callback(func():
			art.texture = entry["face"]
			art.material = null).set_delay(delay + slide + half_flip)
		motion.tween_property(art, "scale:x", 1.0, half_flip).from(0.0).set_delay(delay + slide + half_flip)
		motion.tween_property(label, "modulate:a", 0.42 if entry["disabled"] else 1.0, half_flip).set_delay(delay + slide + half_flip)
		motion.tween_callback(func():
			card.modulate.a = 0.42 if entry["disabled"] else 1.0
			card.disabled = entry["disabled"]
			art.queue_free()).set_delay(delay + slide + half_flip * 2.0)
	motion.finished.connect(overlay.queue_free)
