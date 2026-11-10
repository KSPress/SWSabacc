extends ScreenBase
## A saved pack can be left/reopened at any point without rerolls or lost flips.
var _pack: Dictionary = {}
var _foil: Control
var _hint: Label
var _done: SabaccButton
var _slots: Array = []
var _busy := false
var _drag_start := Vector2.INF


func build() -> void:
	set_header("Card Packs")
	_hint = UIKit.label("", 20, Sabacc.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_hint)
	_done = SabaccButton.make("", SabaccButton.Style.PRIMARY, "star")
	_done.pressed.connect(_advance)
	body.add_child(_done)
	_load_pack()


func _load_pack() -> void:
	for slot in _slots:
		slot.queue_free()
	_slots.clear()
	if is_instance_valid(_foil):
		_foil.queue_free()
	_pack = Progression.packs()[0] if not Progression.packs().is_empty() else {}
	if _pack.is_empty():
		_hint.text = "No unopened packs. Complete an Episode, finish a Spotlight run with a battle win, or play two traditional battles."
		_done.text = "Back to collection"
		_done.disabled = false
	elif _pack["torn"]:
		_deal(false)
	else:
		_hint.text = "%s · %d pack(s) waiting\nDrag across the seal or tap to rip it open" % [_pack["source"], Progression.packs().size()]
		_foil = Control.new()
		_foil.custom_minimum_size = Vector2(240, 360)
		_foil.size = Vector2(240, 360)
		_foil.mouse_filter = Control.MOUSE_FILTER_STOP
		_foil.gui_input.connect(_foil_input)
		body.add_child(_foil)
		for top in [true, false]:
			var half := Foil.new()
			half.top = top
			half.position.y = 0 if top else 140
			half.size = Vector2(240, 140 if top else 220)
			half.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_foil.add_child(half)
		_done.text = "Rip open pack"
		_done.disabled = false
	_on_resize()


func _foil_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start = event.position
		else:
			_rip()
	elif event is InputEventMouseMotion and _drag_start != Vector2.INF and absf(event.position.x - _drag_start.x) > 70:
		_rip()


func _advance() -> void:
	if _busy:
		return
	if _pack.is_empty():
		Router.go("collection")
	elif not _pack["torn"]:
		_rip()
	elif _pack["revealed"].size() == _pack["cards"].size():
		Progression.finish(_pack["id"])
		_load_pack()


func _rip() -> void:
	if _busy or _pack.is_empty() or _pack["torn"]:
		return
	_busy = true
	_done.disabled = true
	Progression.tear(_pack["id"])
	Sfx.play("deploy")
	Fx.impact(body, _foil.position + _foil.size / 2, Sabacc.C_GOLD, true)
	Fx.shockwave(body, _foil.position + _foil.size / 2)
	var animation := create_tween().set_parallel(true)
	for half in _foil.get_children():
		animation.tween_property(half, "position", half.position + Vector2(130 if half.top else -80, -200 if half.top else 160), Sabacc.anim(0.5)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		animation.tween_property(half, "rotation", 0.5 if half.top else -0.35, Sabacc.anim(0.5))
		animation.tween_property(half, "modulate:a", 0.0, Sabacc.anim(0.5))
	await animation.finished
	_foil.queue_free()
	_deal(true)
	_busy = false


func _deal(animated: bool) -> void:
	_hint.text = "Tap cards to reveal · tap revealed cards to inspect\nEach unlock grants a legal playset for your decks"
	for index in _pack["cards"].size():
		var slot := Panel.new()
		slot.set_meta("index", index)
		var rarity := str(CardDB.card(_pack["cards"][index]).get("rarity", "Common"))
		var color := rarity_color(rarity)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("08121e")
		style.border_color = color
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		style.shadow_color = Color(color, 0.4)
		style.shadow_size = 12 if rarity.to_lower() in ["rare", "legendary"] else 4
		slot.add_theme_stylebox_override("panel", style)
		body.add_child(slot)
		_slots.append(slot)
		_update_slot(slot)
		slot.gui_input.connect(func(event):
			if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_flip(slot))
	_on_resize()
	if animated:
		for i in _slots.size():
			var slot: Control = _slots[i]
			var destination := slot.position
			slot.position = body.size / 2 - slot.size / 2
			slot.rotation = (i - 4.5) * 0.18
			slot.scale = Vector2.ONE * 0.1
			var tween := create_tween().set_parallel(true)
			slot.set_meta("dealing", true)
			tween.finished.connect(func(): slot.set_meta("dealing", false))
			tween.tween_property(slot, "position", destination, Sabacc.anim(0.65)).set_delay(i * 0.035).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(slot, "scale", Vector2.ONE, Sabacc.anim(0.65)).set_delay(i * 0.035)
			tween.tween_property(slot, "rotation", 0.0, Sabacc.anim(0.65)).set_delay(i * 0.035)
	_refresh_done()


static func rarity_color(rarity: String) -> Color:
	return {"common": Color("aab8ce"), "uncommon": Color("60b9ff"), "rare": Color("ba79ff"), "legendary": Color("ffbd42"), "special": Color("67edc3")}.get(rarity.to_lower(), Color("aab8ce"))


func _update_slot(slot: Control) -> void:
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()
	var index: int = slot.get_meta("index")
	var revealed: bool = index in _pack["revealed"]
	var card := CardView.create(_pack["cards"][index] if revealed else "")
	card.face_down = not revealed
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.hover_lift = false
	card.draggable = false
	slot.add_child(card)
	var name := str(CardDB.card(_pack["cards"][index]).get("rarity", "Common"))
	var label := UIKit.label(name + (" · Unlocked" if revealed else " · Reveal"), 13, rarity_color(name), HORIZONTAL_ALIGNMENT_CENTER)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)
	_place_content(slot)


func _place_content(slot: Control) -> void:
	var card := slot.get_child(0) as CardView
	var area := slot.size - Vector2(12, 30)
	var scale_factor := minf(area.x / card.size.x, area.y / card.size.y)
	card.pivot_offset = Vector2.ZERO
	card.scale = Vector2.ONE * scale_factor
	card.position = Vector2(6, 4) + (area - card.size * scale_factor) / 2
	var label := slot.get_child(1) as Label
	label.position = Vector2(2, slot.size.y - 24)
	label.size = Vector2(slot.size.x - 4, 22)


func _flip(slot: Control) -> void:
	var index: int = slot.get_meta("index")
	if slot.get_meta("flipping", false) or slot.get_meta("dealing", false):
		return
	if index in _pack["revealed"]:
		InspectOverlay.open(self, _pack["cards"][index], slot.get_global_rect())
		return
	slot.set_meta("flipping", true)
	# Persist before animating so quitting during the flip cannot lose the card.
	Progression.reveal(_pack["id"], index)
	var tween := create_tween()
	tween.tween_property(slot, "scale:x", 0.0, Sabacc.anim(0.15))
	tween.tween_callback(func(): _update_slot(slot); Sfx.play("draw"); Fx.impact(body, slot.position + slot.size / 2, rarity_color(CardDB.card(_pack["cards"][index]).get("rarity", "Common"))))
	tween.tween_property(slot, "scale:x", 1.0, Sabacc.anim(0.2)).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func(): slot.set_meta("flipping", false); _refresh_done())


func _refresh_done() -> void:
	var revealed: int = _pack["revealed"].size()
	_done.text = "Collect & continue" if revealed == 10 else "Reveal cards · %d / 10" % revealed
	_done.disabled = revealed != 10


func relayout(p: bool, rect: Rect2) -> void:
	_hint.position = Vector2.ZERO
	_hint.size = Vector2(rect.size.x, 72)
	_done.position = Vector2(maxf(0, (rect.size.x - 320) / 2), rect.size.y - 62)
	_done.size = Vector2(minf(320, rect.size.x), 56)
	if is_instance_valid(_foil):
		_foil.position = Vector2((rect.size.x - 240) / 2, maxf(80, (rect.size.y - 360) / 2))
	var columns := 2 if p else 5
	var rows := 5 if p else 2
	var cell := Vector2((rect.size.x - (columns - 1) * 14) / columns, (rect.size.y - 152 - (rows - 1) * 12) / rows)
	for i in _slots.size():
		var slot: Control = _slots[i]
		slot.position = Vector2((i % columns) * (cell.x + 14), 80 + (i / columns) * (cell.y + 12))
		slot.size = cell
		slot.pivot_offset = cell / 2
		_place_content(slot)


class Foil extends Control:
	var top := true
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("132b42"))
		draw_rect(Rect2(Vector2.ZERO, size), Sabacc.C_GOLD, false, 2)
		for i in 12:
			var x := i * 22.0
			draw_line(Vector2(x, 0), Vector2(x + 90, size.y), Color("326780"), 1.2, true)
		for i in 20:
			var x := i * 12.0
			var y := size.y - 4 if top else 4.0
			draw_line(Vector2(x, y), Vector2(x + 6, y - 5 if top else y + 5), Sabacc.C_GOLD, 2)
		draw_string(Sabacc.font_title, Vector2(18, 72), "SABACC" if top else "ARCHIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Sabacc.C_GOLD)
		if not top:
			draw_string(Sabacc.font_title, Vector2(18, 130), "10 CARDS", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Sabacc.C_TEXT)
