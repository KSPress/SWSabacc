extends Control
## The Music autoload supplies the soundtrack across scenes.

const EMBLEM := preload("res://assets/branding/startup_emblem.png")
const HOLOGRAM := preload("res://ui/screens/startup_hologram.gdshader")
const INTRO_SECONDS := 3.6

var _leaving := false
var _emblem: TextureRect
var _material: ShaderMaterial
var _elapsed := 0.0


func _ready() -> void:
	theme = UIKit.build_theme()
	var backdrop := ColorRect.new()
	backdrop.color = Color("#050c14")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.fill_rect(backdrop)
	add_child(backdrop)

	_emblem = TextureRect.new()
	_emblem.texture = EMBLEM
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_material = ShaderMaterial.new()
	_material.shader = HOLOGRAM
	var animated := not Sabacc.perf()
	_material.set_shader_parameter("animated", animated)
	_emblem.material = _material
	add_child(_emblem)

	var hint := UIKit.label("Click or tap to skip", 20, Color("#a7bccc"), HORIZONTAL_ALIGNMENT_CENTER)
	if not CardDB.loaded:
		hint.text = "No card database found. See the README for import instructions."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_left = 24.0
	hint.offset_right = -24.0
	hint.offset_top = -88.0
	hint.offset_bottom = -28.0
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	resized.connect(_layout_emblem)
	_layout_emblem()
	set_process(animated)

	if CardDB.loaded:
		get_tree().create_timer(INTRO_SECONDS).timeout.connect(_show_menu)


func _layout_emblem() -> void:
	var side := minf(minf(size.x, size.y) * 0.78, 640.0)
	_emblem.size = Vector2.ONE * side
	_emblem.position = (size - _emblem.size) * 0.5


func _process(delta: float) -> void:
	_elapsed += delta
	_material.set_shader_parameter("elapsed", _elapsed)


func _input(event: InputEvent) -> void:
	if not CardDB.loaded:
		return
	var click: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	if event.is_pressed() and (click or event is InputEventScreenTouch or event.is_action_pressed("ui_accept")):
		get_viewport().set_input_as_handled()
		_show_menu()


func _show_menu() -> void:
	if _leaving:
		return
	_leaving = true
	Router.go("welcome" if Progression.needs_welcome() else "menu")
