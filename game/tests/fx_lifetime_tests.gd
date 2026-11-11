extends Node
## A stalled frame must not leave expired effects drawing invalid geometry.
var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)


func _pixels() -> PackedByteArray:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image().get_data()


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("081020")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var baseline := await _pixels()
	var cases := [[Fx.FxImpact, "_t", 0.5], [Fx.FxMuzzle, "_t", 0.12], [Fx.FxShockwave, "_t", 0.6], [Fx.FxSlash, "age", 1.0], [Fx.FxPunch, "_t", 0.6]]
	for fixture in cases:
		var effect: Node2D = fixture[0].new()
		effect.position = get_viewport().get_visible_rect().size / 2
		add_child(effect)
		effect.set_process(false)
		effect.set(fixture[1], fixture[2] * 0.3)
		effect.queue_redraw()
		var alive := await _pixels()
		check(alive != baseline, "live effect visible " + str(fixture[0]))
		effect.set(fixture[1], fixture[2] + 0.25)
		effect.queue_redraw()
		var expired := await _pixels()
		check(expired == baseline, "expired effect leaves no pixels " + str(fixture[0]))
		effect.queue_free()
		await get_tree().process_frame
	print("FX LIFETIME: %d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures else 0)
