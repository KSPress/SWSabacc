extends ScreenBase

const MODES := ["Campaigns", "Battles", "Galactic Conquest", "Mini Games"]
const DESCRIPTIONS := [
	"Story episodes and branching Saga encounters",
	"Traditional SWU and Quick Match variants",
	"Command fleets and capture planets in real time",
	"Play Sabacc War for credits",
]
const ART := [
	preload("res://assets/branding/play_campaigns.png"),
	preload("res://assets/branding/play_battles.png"),
	preload("res://assets/branding/play_conquest.png"),
	preload("res://assets/branding/play_mini_games.png"),
]
const HOLOGRAM := preload("res://ui/screens/play_hologram.gdshader")

var selected := 0
var _stage: Control
var _cards: Array[TextureRect] = []
var _details: VBoxContainer
var _description: Label
var _open: Button
var _press := Vector2.ZERO
var _held := false
var _hologram := ShaderMaterial.new()
var _motion: Tween


func build() -> void:
	set_header("Play")
	selected = clampi(int(Router.params.get("selected", 0)), 0, MODES.size() - 1)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.gui_input.connect(_on_stage_input)
	body.add_child(_stage)
	_hologram.shader = HOLOGRAM
	_hologram.set_shader_parameter("animated", not Sabacc.perf())
	for texture in ART:
		var card := TextureRect.new()
		card.texture = texture
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_stage.add_child(card)
		_cards.append(card)
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 12)
	body.add_child(_details)
	_description = UIKit.label("", 21, Sabacc.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_details.add_child(_description)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	_details.add_child(controls)
	var previous := SabaccButton.make("‹", SabaccButton.Style.GHOST)
	previous.tooltip_text = "Previous mode"
	previous.custom_minimum_size = Vector2(60, 64)
	previous.pressed.connect(func(): cycle(-1))
	controls.add_child(previous)
	_open = SabaccButton.make("", SabaccButton.Style.PRIMARY)
	_open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open.pressed.connect(_activate)
	controls.add_child(_open)
	var next := SabaccButton.make("›", SabaccButton.Style.GHOST)
	next.tooltip_text = "Next mode"
	next.custom_minimum_size = previous.custom_minimum_size
	next.pressed.connect(func(): cycle(1))
	controls.add_child(next)
	_update_selection()


func relayout(_portrait: bool, rect: Rect2) -> void:
	var width := minf(rect.size.x, 920.0)
	var height := minf(rect.size.y, 820.0)
	var origin := (rect.size - Vector2(width, height)) / 2.0
	_stage.position = origin
	_stage.size = Vector2(width, maxf(120.0, height - 116.0))
	var controls_width := minf(width, 540.0)
	_details.position = origin + Vector2((width - controls_width) / 2.0, _stage.size.y + 4.0)
	_details.size.x = controls_width
	_layout_cards(false)


func cycle(direction: int) -> void:
	selected = posmod(selected + direction, MODES.size())
	_update_selection()
	_layout_cards(true)


func _update_selection() -> void:
	_open.text = MODES[selected]
	_description.text = DESCRIPTIONS[selected]


func _layout_cards(animate: bool) -> void:
	if _motion:
		_motion.kill()
	_motion = create_tween().set_parallel(true) if animate and not Sabacc.perf() else null
	var card_height := minf(_stage.size.y * 1.23, _stage.size.x * 0.9)
	for i in _cards.size():
		var card := _cards[i]
		var slot := posmod(i - selected + 1, MODES.size()) - 1
		var height := card_height * (1.0 if slot == 0 else 0.76)
		var target_size := Vector2(height * 0.78, height)
		var target_position := _stage.size * Vector2(0.5 + slot * 0.30, 0.5) - target_size / 2.0
		card.material = null if slot == 0 else _hologram
		card.visible = abs(slot) <= 1
		card.z_index = 1 if slot == 0 else 0
		if _motion:
			_motion.tween_property(card, "position", target_position, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_motion.tween_property(card, "size", target_size, 0.24)
		else:
			card.position = target_position
			card.size = target_size


func _on_stage_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press = event.position
		_held = true
	elif _held:
		_held = false
		var delta: Vector2 = event.position - _press
		if absf(delta.x) >= 42.0 and absf(delta.x) > absf(delta.y):
			cycle(1 if delta.x < 0.0 else -1)
		elif delta.length() < 20.0:
			var x: float = event.position.x / _stage.size.x
			if x < 0.33 or x > 0.67:
				cycle(-1 if x < 0.33 else 1)
			else:
				_activate()
	_stage.accept_event()


func _activate() -> void:
	match selected:
		0: Router.go("episodes")
		1: Router.go("hub", {"section": "battles"})
		2: Router.go("conquest")
		3: Router.go("mini_games")
