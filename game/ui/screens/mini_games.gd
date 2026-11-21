extends ScreenBase

const War := preload("res://engine/cantina_war.gd")

var _options: VBoxContainer


func build() -> void:
	set_header("Mini Games", "play")
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 16)
	body.add_child(_options)

	var image := TextureRect.new()
	var sheet := AtlasTexture.new()
	sheet.atlas = preload("res://assets/branding/cantina_war.png")
	sheet.region = Rect2(1491, 35, 168, 243)
	image.texture = sheet
	var key := ShaderMaterial.new()
	key.shader = preload("res://ui/kit/cantina_war_art.gdshader")
	image.material = key
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size.y = 218
	_options.add_child(image)

	var unlocked: bool = War.UNLOCK_CHAPTER in Save.data["campaign"]["cleared"]
	var prompt := "Play for account credits at the Cantina." if unlocked else "Clear Episode I, Chapter 1 · The Invasion of Naboo to unlock."
	var hint := UIKit.label(prompt, 21, Sabacc.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options.add_child(hint)
	var play := SabaccButton.make("Sabacc War", SabaccButton.Style.GOLD, "play", true)
	play.disabled = not unlocked
	play.pressed.connect(func(): Router.go("sabacc_war"))
	_options.add_child(play)


func relayout(_portrait: bool, rect: Rect2) -> void:
	var width := minf(rect.size.x, 500.0)
	_options.size = Vector2(width, 0)
	_options.position = Vector2((rect.size.x - width) * 0.5, maxf(0, (rect.size.y - _options.size.y) * 0.45))


func request_screen_back() -> bool:
	Router.go("play", {"selected": 3})
	return true
