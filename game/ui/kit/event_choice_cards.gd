extends HBoxContainer

const YES := preload("res://assets/branding/event_yes.png")
const NO := preload("res://assets/branding/event_no.png")

func _ready() -> void:
	var wood := ColorRect.new()
	var surface := ShaderMaterial.new()
	surface.shader = preload("res://ui/screens/sabacc_war_table.gdshader")
	wood.material = surface
	wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wood, false, Node.INTERNAL_MODE_BACK)
	resized.connect(func(): wood.size = size + Vector2(14, 16))
	wood.position = Vector2(-7, -8)
	wood.size = size + Vector2(14, 16)


func add_choice(answer: String, caption: String, disabled: bool, choose: Callable) -> void:
	var slot := VBoxContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(slot)
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
	card.mouse_entered.connect(func():
		if not card.disabled:
			card.self_modulate = Color(1.15, 1.15, 1.15))
	card.mouse_exited.connect(func(): card.self_modulate = Color.WHITE)
	card.pressed.connect(func():
		Sfx.play("click")
		choose.call())
