class_name UnitEffects
extends Node2D
## Additive sprite layers share the unit transform and can run independently.

const SHEETS := {
	"heal": Vector2i(53, 208),
	"coordinate": Vector2i(49, 161),
	"sentinel": Vector2i(4, 57),
	"shield": Vector2i(19, 193),
	"shield_break": Vector2i(9, 205),
}
const FRAME_COUNT := 16
const FPS := 20.0
const PLAY_TIME := FRAME_COUNT / FPS
const FADE_TIME := 0.18
const SHIELD_RECT := Rect2(-21, -17, 174, 150)

static var _textures := {}
static var _blend: CanvasItemMaterial
var _time := 0.0
var _active := {"sentinel": false, "coordinate": false, "shield": false}
var _opacity := {"sentinel": 0.0, "coordinate": 0.0, "shield": 0.0}
var _heal_age := PLAY_TIME
var _break_age := PLAY_TIME


static func sheet(key: String) -> Texture2D:
	if not _textures.has(key):
		var path := "res://ip/ui/board_effects/%s.jpg" % key
		_textures[key] = load(path) if ResourceLoader.exists(path) else null
	return _textures[key]


func _ready() -> void:
	if _blend == null:
		_blend = CanvasItemMaterial.new()
		_blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = _blend
	set_process(false)


func set_status(sentinel: bool, coordinate: bool, shield: bool) -> void:
	_active["sentinel"] = sentinel
	_active["coordinate"] = coordinate
	_active["shield"] = shield
	set_process(true)


func heal() -> void:
	_heal_age = 0.0
	set_process(true)


func break_shield(remaining: bool) -> void:
	_active["shield"] = remaining
	_opacity["shield"] = 0.0
	_break_age = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	_heal_age += delta / Sabacc.anim(1.0)
	_break_age += delta / Sabacc.anim(1.0)
	var visible_effect := _heal_age < PLAY_TIME or _break_age < PLAY_TIME
	for key in _active:
		var show_effect: bool = _active[key]
		if key == "shield" and _break_age < PLAY_TIME:
			show_effect = false
		_opacity[key] = move_toward(_opacity[key], 1.0 if show_effect else 0.0, delta / FADE_TIME)
		visible_effect = visible_effect or _opacity[key] > 0.0
	queue_redraw()
	set_process(visible_effect)


func _draw() -> void:
	var loop_frame := 7 if Sabacc.perf() else int(_time * 12.0) % FRAME_COUNT
	_draw_frame("shield", loop_frame, SHIELD_RECT, _opacity["shield"] * 0.84)
	_draw_frame("coordinate", loop_frame, Rect2(-16, 6, 164, 105), _opacity["coordinate"] * 0.78)
	_draw_frame("sentinel", loop_frame, Rect2(12, -32, 108, 35), _opacity["sentinel"])
	_draw_one_shot("shield_break", _break_age, SHIELD_RECT)
	_draw_one_shot("heal", _heal_age, Rect2(-12, 18, 156, 103))


func _draw_one_shot(key: String, age: float, area: Rect2) -> void:
	if age < PLAY_TIME:
		var fade := minf(1.0, (PLAY_TIME - age) / FADE_TIME)
		_draw_frame(key, int(age * FPS), area, fade)


func _draw_frame(key: String, frame: int, area: Rect2, opacity: float) -> void:
	if opacity <= 0.0:
		return
	var texture := sheet(key)
	if texture == null:
		return
	var crop: Vector2i = SHEETS[key]
	var row_start := 213 if frame >= 8 else 0
	var region := Rect2(3 + (frame % 8) * 160, row_start + crop.x, 154, crop.y - crop.x)
	draw_texture_rect_region(texture, area, region, Color(1, 1, 1, opacity))
