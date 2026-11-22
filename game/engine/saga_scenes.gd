class_name SagaScenes
extends RefCounted

const FILM := preload("res://ui/kit/datapad_film.gdshader")
static var _scenes: Dictionary = {}


static func catalog() -> Dictionary:
	if _scenes.is_empty():
		_scenes = JSON.parse_string(FileAccess.get_file_as_string("res://data/saga_scenes.json"))
	return _scenes


static func film_layer() -> TextureRect:
	var overlay := TextureRect.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var material := ShaderMaterial.new()
	material.shader = FILM
	material.set_shader_parameter("animated", not Sabacc.perf())
	overlay.material = material
	return overlay


static func set_film_photo(layer: TextureRect, photo: Texture2D, enabled: bool) -> void:
	layer.texture = photo if enabled else null
	layer.visible = layer.texture != null
	(layer.material as ShaderMaterial).set_shader_parameter("animated", not Sabacc.perf())
