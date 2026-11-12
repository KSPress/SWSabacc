class_name CombatSprite
extends Node2D

const COLUMNS := 8
const ROWS := 2
const CACHE_SIZE := 6
const EDGE_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_add;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 cell_uv = fract(UV * vec2(8.0, 2.0));
	vec2 edge = min(cell_uv, 1.0 - cell_uv);
	float feather = smoothstep(0.012, 0.10, edge.x) * smoothstep(0.012, 0.085, edge.y);
	vec3 glow = max(texture(TEXTURE, UV).rgb - vec3(0.012), vec3(0.0));
	COLOR = vec4(glow * tint.rgb, tint.a * feather);
}
"""

static var _sheets := {}
static var _material: ShaderMaterial

var sheet_name := ""
var free_on_finish := true
var first_frame := 0
var last_frame := COLUMNS * ROWS - 1
var _sheet: Texture2D
var _cell := Vector2.ZERO
var _width := 0.0
var _anchor_x := 0.5
var _duration := 0.0
var _age := 0.0


static func slash_sheet(palette: String) -> String:
	return "Slash %s %d" % [palette.capitalize(), randi_range(1, 2 if palette == "red" else 3)]


static func spawn(layer: Control, name: String, point: Vector2, width: float, duration: float,
		angle := 0.0, anchor_x := 0.5) -> CombatSprite:
	if not _sheets.has(name):
		var path := "res://Animations/%s.png" % name
		if _sheets.size() >= CACHE_SIZE:
			_sheets.erase(_sheets.keys()[0])
		_sheets[name] = load(path) if ResourceLoader.exists(path) else null
	var sprite := CombatSprite.new()
	sprite.sheet_name = name
	sprite._sheet = _sheets[name]
	if sprite._sheet:
		sprite._cell = sprite._sheet.get_size() / Vector2(COLUMNS, ROWS)
	sprite._width = width
	sprite._anchor_x = anchor_x
	sprite._duration = duration
	sprite.rotation = angle
	sprite.z_index = 25
	if _material == null:
		var shader := Shader.new()
		shader.code = EDGE_SHADER
		_material = ShaderMaterial.new()
		_material.shader = shader
	sprite.material = _material
	layer.add_child(sprite)
	sprite.global_position = point
	return sprite


func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		if free_on_finish:
			queue_free()
		else:
			set_process(false)
	else:
		queue_redraw()


func _draw() -> void:
	if not _sheet or _duration <= 0.0:
		return
	var frame := mini(last_frame, first_frame + int(_age / _duration * (last_frame - first_frame + 1)))
	var source := Rect2(Vector2(frame % COLUMNS, floori(float(frame) / COLUMNS)) * _cell, _cell)
	var size_px := Vector2(_width, _width * _cell.y / _cell.x)
	var destination := Rect2(-size_px * Vector2(_anchor_x, 0.5), size_px)
	draw_texture_rect_region(_sheet, destination, source)
