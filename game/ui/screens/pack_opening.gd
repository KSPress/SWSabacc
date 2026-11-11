extends ScreenBase
## A saved pack can be left/reopened at any point without rerolls or lost flips.
var _pack: Dictionary = {}
var _foil: Control
var _hint: Label
var _done: SabaccButton
var _slots: Array = []
var _busy := false
var _drag_start := Vector2.INF
var _tear_progress := 0.0


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
			if not top:
				var badge := ProfileBadge.new()
				badge.size = Vector2(110, 110)
				badge.position = Vector2(65, 8)
				half.add_child(badge)
		_done.text = "Rip open pack"
		_done.disabled = false
	_on_resize()


func _foil_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) or event is InputEventScreenTouch:
		if event.pressed:
			_drag_start = event.position
		else:
			if _drag_start != Vector2.INF and (event.position.distance_to(_drag_start) < 14 or _tear_progress >= 0.65):
				_rip()
			_drag_start = Vector2.INF
	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and _drag_start != Vector2.INF:
		_tear_progress = clampf(absf(event.position.x - _drag_start.x) / 190, 0, 1)
		for half in _foil.get_children():
			half.progress = _tear_progress
		if _tear_progress >= 0.9:
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
	var anticipation := create_tween()
	anticipation.tween_property(_foil, "scale", Vector2.ONE * 1.06, Sabacc.anim(0.14)).set_trans(Tween.TRANS_BACK)
	await anticipation.finished
	var burst := PackBurst.new()
	burst.position = _foil.position + _foil.size / 2
	burst.color = rarity_color("Legendary" if not _pack.get("bonus", {}).is_empty() else "Rare")
	body.add_child(burst)
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
	var total: int = _pack["cards"].size() + (0 if _pack.get("bonus", {}).is_empty() else 1)
	for index in total:
		var slot := Panel.new()
		slot.set_meta("index", index)
		var rarity := _rarity(index)
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
			slot.set_meta("deal_tween", tween)
			tween.finished.connect(func(): slot.set_meta("dealing", false))
			tween.tween_property(slot, "position", destination, Sabacc.anim(0.65)).set_delay(i * 0.035).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(slot, "scale", Vector2.ONE, Sabacc.anim(0.65)).set_delay(i * 0.035)
			tween.tween_property(slot, "rotation", 0.0, Sabacc.anim(0.65)).set_delay(i * 0.035)
	_refresh_done()


static func rarity_color(rarity: String) -> Color:
	return {"common": Color("aab8ce"), "uncommon": Color("60b9ff"), "rare": Color("ba79ff"), "legendary": Color("ffbd42"), "special": Color("67edc3")}.get(rarity.to_lower(), Color("aab8ce"))


func _rarity(index: int) -> String:
	return _pack["bonus"]["rarity"] if index >= _pack["cards"].size() else str(CardDB.card(_pack["cards"][index]).get("rarity", "Common"))


func _update_slot(slot: Control) -> void:
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()
	var index: int = slot.get_meta("index")
	var bonus: bool = index >= _pack["cards"].size()
	var revealed: bool = _pack.get("bonus_revealed", false) if bonus else index in _pack["revealed"]
	var card: Control
	if bonus and revealed:
		card = Control.new()
		card.size = CardView.PORTRAIT
		var reward: Dictionary = _pack["bonus"]
		if reward["kind"] == "emblem":
			var badge := ProfileBadge.new()
			badge.emblem_id = reward["id"]
			badge.size = Vector2(230, 230)
			badge.position = Vector2(10, 35)
			card.add_child(badge)
		else:
			var scene := TextureRect.new()
			scene.texture = Art.ui_texture(reward["id"])
			scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			scene.size = Vector2(230, 270)
			scene.position = Vector2(10, 10)
			card.add_child(scene)
		var title := UIKit.label(reward["name"], 22, Sabacc.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		title.position = Vector2(5, 280)
		title.size = Vector2(240, 62)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(title)
	else:
		card = CardView.create(_pack["cards"][index] if revealed and not bonus else "")
		card.face_down = not revealed
		card.hover_lift = false
		card.draggable = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in card.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(card)
	var name := _rarity(index)
	var label := UIKit.label(name + (" · Cosmetic" if bonus else "") + (" · Unlocked" if revealed else " · Reveal"), 13, rarity_color(name), HORIZONTAL_ALIGNMENT_CENTER)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)
	_place_content(slot)


func _place_content(slot: Control) -> void:
	var card := slot.get_child(0) as Control
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
	var bonus: bool = index >= _pack["cards"].size()
	if slot.get_meta("flipping", false) or slot.get_meta("dealing", false):
		return
	if (_pack.get("bonus_revealed", false) if bonus else index in _pack["revealed"]):
		if not bonus:
			InspectOverlay.open(self, _pack["cards"][index], slot.get_global_rect())
		return
	slot.set_meta("flipping", true)
	# Persist before animating so quitting during the flip cannot lose the card.
	if bonus:
		Progression.reveal_bonus(_pack["id"])
	else:
		Progression.reveal(_pack["id"], index)
	var tween := create_tween()
	tween.tween_property(slot, "scale:x", 0.0, Sabacc.anim(0.15))
	tween.tween_callback(func(): _update_slot(slot); Sfx.play("draw"); Fx.impact(body, slot.position + slot.size / 2, rarity_color(_rarity(index)), _rarity(index) in ["Rare", "Legendary"]))
	tween.tween_property(slot, "scale:x", 1.0, Sabacc.anim(0.2)).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func(): slot.set_meta("flipping", false); _refresh_done())


func _refresh_done() -> void:
	var total: int = _pack["cards"].size() + (0 if _pack.get("bonus", {}).is_empty() else 1)
	var revealed: int = _pack["revealed"].size() + (1 if _pack.get("bonus_revealed", false) else 0)
	_done.text = "Collect & continue" if revealed == total else "Reveal rewards · %d / %d" % [revealed, total]
	_done.disabled = revealed != total


func relayout(p: bool, rect: Rect2) -> void:
	_hint.position = Vector2.ZERO
	_hint.size = Vector2(rect.size.x, 140 if _pack.is_empty() else 72)
	_done.position = Vector2(maxf(0, (rect.size.x - 320) / 2), rect.size.y - 62)
	_done.size = Vector2(minf(320, rect.size.x), 56)
	if is_instance_valid(_foil):
		var foil_scale := minf(1.0, (rect.size.y - 160) / 360)
		_foil.scale = Vector2.ONE * foil_scale
		_foil.position = (rect.size - _foil.size * foil_scale) / 2
		_foil.pivot_offset = Vector2.ZERO
	var columns := 3 if p else (6 if _slots.size() > 10 else 5)
	var rows := maxi(1, ceili(_slots.size() / float(columns)))
	var cell := Vector2((rect.size.x - (columns - 1) * 14) / columns, (rect.size.y - 152 - (rows - 1) * 12) / rows)
	for i in _slots.size():
		var slot: Control = _slots[i]
		var flight = slot.get_meta("deal_tween") if slot.has_meta("deal_tween") else null
		if flight is Tween and flight.is_valid():
			flight.kill()
			slot.scale = Vector2.ONE
			slot.rotation = 0
			slot.set_meta("dealing", false)
		var row := i / columns
		var count_in_row := mini(columns, _slots.size() - row * columns)
		var offset := (rect.size.x - (count_in_row * cell.x + (count_in_row - 1) * 14)) / 2
		slot.position = Vector2(offset + (i % columns) * (cell.x + 14), 80 + row * (cell.y + 12))
		slot.size = cell
		slot.pivot_offset = cell / 2
		_place_content(slot)


class Foil extends Control:
	var top := true
	var progress := 0.0
	var _time := 0.0
	func _process(delta: float) -> void:
		if not Sabacc.perf():
			_time += delta
			queue_redraw()
	func _draw() -> void:
		for i in 40:
			var band := Rect2(0, i * size.y / 40, size.x, size.y / 40 + 1)
			var sheen := pow(maxf(0, sin(i * 0.10 - _time * 0.7)), 12)
			draw_rect(band, Color("101a2a").lerp(Cosmetics.emblem_color().darkened(0.3), sheen * 0.6))
		draw_rect(Rect2(Vector2.ZERO, size), Sabacc.C_GOLD, false, 2)
		for i in 12:
			var x := i * 22.0
			if x < size.x:
				draw_line(Vector2(x, 0), Vector2(minf(x + 90, size.x), size.y), Color(Cosmetics.emblem_color("", 1), 0.25), 1.2, true)
		for i in 20:
			var x := i * 12.0
			var y := size.y - 4 if top else 4.0
			draw_line(Vector2(x, y), Vector2(x + 6, y - 5 if top else y + 5), Color("fff0b5") if i / 20.0 < progress else Sabacc.C_GOLD, 3 if i / 20.0 < progress else 1)
		if top:
			draw_string(Sabacc.font_title, Vector2(18, 72), "SABACC", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Sabacc.C_GOLD)
			draw_string(Sabacc.font_title, Vector2(18, 104), "SEALED ARCHIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Sabacc.C_TEXT)
		if not top:
			draw_string(Sabacc.font_title, Vector2(18, 164), "10 CARDS", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Sabacc.C_TEXT)
			draw_string(Sabacc.font_title, Vector2(18, 196), "RARE COSMETIC CHANCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Sabacc.C_GOLD)


class PackBurst extends Control:
	var color := Sabacc.C_GOLD
	var _age := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta: float) -> void:
		_age += delta
		if _age > 1.3:
			queue_free()
		queue_redraw()
	func _draw() -> void:
		var fade := maxf(0, 1 - _age / 1.3)
		draw_circle(Vector2.ZERO, 35 + _age * 95, Color(color, fade * 0.10))
		for i in 48:
			var direction := Vector2.from_angle(i * TAU / 48 + i * 0.08)
			var distance := 20 + _age * (130 + (i % 7) * 28)
			draw_line(direction * distance, direction * (distance + 12 * fade), Color(color, fade * 0.8), 1.6, true)
		for i in 3:
			draw_arc(Vector2.ZERO, 25 + _age * (180 + i * 40), 0, TAU, 96, Color(color, fade * 0.28), 2.2, true)
