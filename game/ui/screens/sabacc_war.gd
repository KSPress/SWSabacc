extends ScreenBase

const War := preload("res://engine/cantina_war.gd")
const Sheet := preload("res://assets/branding/cantina_war.png")
const CantinaTrack := "res://ip/audio/custom/cantina_band.mp3"
const Cantina := "saga_cantina"

var _chapter_id := ""
var _node_id := ""
var _run: Dictionary
var _table_state: Dictionary
var _allowed := false
var _dealing := false
var _playing_track := false
var _table: ColorRect
var _cards: Array[TextureRect] = []
var _burned: Array[TextureRect] = []
var _decks: Array = [[], []]
var _deck_labels: Array[Label] = []
var _remaining: Array = [War.DECK_SIZE, War.DECK_SIZE]
var _card_material := ShaderMaterial.new()
var _card_size := Vector2.ZERO
var _face_centers: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _deck_centers: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _house: Label
var _wallet: HBoxContainer
var _amount: Label
var _delta: Label
var _status: Label
var _deal: Button
var _back: Button
var _rules: Button


func build() -> void:
	_chapter_id = Router.params.get("chapter_id", "")
	_node_id = Router.params.get("node_id", "")
	_run = Save.run() if not _chapter_id.is_empty() else {}
	_allowed = _can_enter()
	_table_state = _run.get("war_table", {}) if not _chapter_id.is_empty() else Progression.sabacc_war_table()
	if _table_state.has("decks"):
		_remaining = _table_state["decks"].map(func(deck): return deck.size())
	bg.set_location(Cantina)
	_account_credit.hide()
	set_header("Sabacc War")
	_back = header.get_child(0)
	_rules = SabaccButton.make("Rules", SabaccButton.Style.GHOST)
	_rules.pressed.connect(_show_rules)
	header.add_child(_rules)
	_card_material.shader = preload("res://ui/kit/cantina_war_art.gdshader")
	_table = ColorRect.new()
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var table_material := ShaderMaterial.new()
	table_material.shader = preload("res://ui/screens/sabacc_war_table.gdshader")
	_table.material = table_material
	body.add_child(_table)
	for side in 2:
		for layer in War.DECK_SIZE:
			var card := _make_card(side, War.BACK)
			card.modulate = Color(0.69, 0.58, 0.52) if layer < War.DECK_SIZE - 1 else Color.WHITE
			_decks[side].append(card)
		var count := _label("", 18, Sabacc.C_TEXT)
		_deck_labels.append(count)
	for side in 2:
		_cards.append(_make_card(side, War.BACK))
		_cards[side].hide()
	_house = _label("Cantina gambler", 21, Sabacc.C_TEXT)
	_wallet = UIKit.credit_label(str(_credit_total()))
	_wallet.alignment = BoxContainer.ALIGNMENT_BEGIN
	_wallet.move_child(_wallet.get_node("Amount"), 0)
	_amount = _wallet.get_node("Amount")
	_amount.add_theme_font_override("font", Sabacc.font_title)
	_amount.add_theme_font_size_override("font_size", 44)
	_wallet.get_child(1).custom_minimum_size = Vector2(36, 38)
	body.add_child(_wallet)
	_delta = _label("", 28, Sabacc.C_GOLD)
	_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status = _label("Place your stake." if _allowed else "This table is locked.", 20, Sabacc.C_TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deal = SabaccButton.make("", SabaccButton.Style.GOLD, "play", true)
	_deal.pressed.connect(_play_hand)
	body.add_child(_deal)
	_update_deal_button()
	if _allowed:
		Music.set_scene_track(CantinaTrack)
		_playing_track = true


func _exit_tree() -> void:
	if _playing_track:
		Music.set_scene_track("")


func _can_enter() -> bool:
	if _chapter_id.is_empty():
		return War.UNLOCK_CHAPTER in Save.data["campaign"]["cleared"]
	if _run.get("chapter", "") != _chapter_id or _run.get("status", "") != "active" or _node_id != "cantina_war":
		return false
	var route := CampaignRun.route(CardDB.chapter(_chapter_id), _run)
	return _node_id in CampaignRun.available_nodes(_run, route)


func _make_card(side: int, value: int) -> TextureRect:
	var card := TextureRect.new()
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.material = _card_material
	card.texture = _face(side, value)
	body.add_child(card)
	return card


func _face(side: int, value: int) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = Sheet
	texture.region = Rect2(roundf(15 + 184.5 * (value - 1)), 35 + 267 * side, 168, 243)
	texture.filter_clip = true
	return texture


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := UIKit.label(value, font_size, color, HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.02, 0.01, 0.95))
	label.add_theme_constant_override("shadow_offset_y", 2)
	body.add_child(label)
	return label


func relayout(in_portrait: bool, rect: Rect2) -> void:
	var width := minf(rect.size.x, rect.size.y * (0.99 if in_portrait else 1.72))
	var field := Rect2(Vector2((rect.size.x - width) * 0.5, 0), Vector2(width, rect.size.y))
	_table.position = Vector2(field.position.x - width * 0.13, -field.size.y * 0.025)
	_table.size = Vector2(width * 1.26, field.size.y * 0.98)
	var height := minf(width * (0.32 if in_portrait else 0.23), field.size.y * 0.36)
	_card_size = Vector2(height * 168.0 / 243.0, height)
	_face_centers[1] = _point(field, 0.30, 0.30)
	_face_centers[0] = _point(field, 0.55, 0.59)
	_deck_centers[1] = _point(field, 0.82, 0.27)
	_deck_centers[0] = _point(field, 0.82, 0.65)
	for side in 2:
		var face := _cards[side]
		face.size = _card_size
		face.pivot_offset = _card_size / 2.0
		face.position = _face_centers[side] - _card_size / 2.0
		_place_label(_deck_labels[side], _deck_centers[side] + Vector2(0, height * 0.52), 126, 28)
	_layout_decks()
	for i in _burned.size():
		_place_burn(_burned[i], i)
	_place_label(_house, _point(field, 0.27, 0.075), 210, 34)
	_wallet.position = _point(field, 0.02, 0.77)
	_delta.position = _wallet.position - Vector2(0, 27)
	_place_label(_status, _point(field, 0.56, 0.81), width * 0.65, 52)
	var deal_width := minf(width * 0.94, 420.0)
	_deal.size = Vector2(deal_width, 58)
	_deal.position = _point(field, 0.5, 1.0) - Vector2(deal_width / 2.0, 63)


func _point(field: Rect2, x: float, y: float) -> Vector2:
	return field.position + field.size * Vector2(x, y)


func _place_label(label: Label, center_top: Vector2, width: float, height: float) -> void:
	label.position = center_top - Vector2(width * 0.5, 0)
	label.size = Vector2(width, height)


func _layout_decks() -> void:
	for side in 2:
		var layers: Array = _decks[side]
		var visible_count := int(_remaining[side])
		for i in layers.size():
			var card: TextureRect = layers[i]
			card.visible = i < visible_count
			card.modulate = Color.WHITE if i == visible_count - 1 else Color(0.69, 0.58, 0.52)
			card.size = _card_size * 0.83
			card.position = _deck_centers[side] - card.size / 2.0 - Vector2(1.8, 3.1) * i
		_deck_labels[side].text = "%d left" % visible_count


func _place_burn(card: TextureRect, index: int) -> void:
	card.size = _card_size * 0.29
	card.rotation = deg_to_rad((index - 2.5) * 6.0)
	card.position = _face_centers[0].lerp(_face_centers[1], 0.5) + Vector2(-_card_size.x * 1.35 + index * 12.0, 4.0)


func _show_rules() -> void:
	var info := ModalPanel.open(self, 540, Sabacc.C_GOLD)
	info.text("Sabacc War", 30, Sabacc.C_GOLD)
	info.text("Stake 10 credits. Higher numbers win. The circle beats any numbered card, and the three lines add 3 to the next card you draw.", 20)
	info.text("If the circle and lines meet, each side deals three cards face down and flips the fourth. The winner takes the stake. Ties and hands without enough cards return your stake.", 20)
	var dismiss := SabaccButton.make("Back to the table", SabaccButton.Style.PRIMARY)
	dismiss.pressed.connect(info.close)
	info.add_action(dismiss)


func _credit_total() -> int:
	return Progression.credits() if _chapter_id.is_empty() else int(_run.get("credits", 0))


func _update_deal_button() -> void:
	var enough := _credit_total() >= War.STAKE
	_deal.text = "Deal · %d credits" % War.STAKE if enough else "You need %d credits to deal" % War.STAKE
	_deal.disabled = _dealing or not _allowed or not enough


func _play_hand() -> void:
	var before := _credit_total()
	if _dealing or not _allowed or before < War.STAKE:
		return
	_dealing = true
	_back.disabled = true
	_rules.disabled = true
	_update_deal_button()
	_delta.text = ""
	for burned in _burned:
		burned.queue_free()
	_burned.clear()
	for face in _cards:
		face.hide()
	var decks: Array = _table_state.get("decks", [[], []])
	var shuffle := int(_table_state.get("shuffle", 0))
	if decks[0].is_empty() or decks[1].is_empty():
		var seed_value := int(_run.get("node_seed", randi()))
		decks = War.shuffle_decks(seed_value + shuffle * 7919)
		shuffle += 1
		_remaining = [War.DECK_SIZE, War.DECK_SIZE]
		_layout_decks()
	var hand := War.resolve(decks[0], decks[1])
	var change := int(hand["delta"])
	_table_state = {"decks": hand["decks"], "shuffle": shuffle}
	if _chapter_id.is_empty():
		Progression.settle_sabacc_war(change, _table_state)
	else:
		_run["credits"] = before + change
		_run["war_table"] = _table_state
		Save.set_run(_run)
	for reveal in hand["reveals"]:
		_status.text = reveal["caption"]
		await _draw_cards(reveal)
		await get_tree().create_timer(Sabacc.anim(0.32)).timeout
	var result := "You win" if change > 0 else ("Gambler wins" if change < 0 else "Stake returned")
	_status.text = "%s · %s" % [hand["result"], result]
	if change != 0:
		_delta.text = "%+d" % change
		_delta.modulate = Color(0.65, 1.0, 0.76) if change > 0 else Color(1.0, 0.62, 0.55)
		var count := create_tween()
		count.tween_method(func(value: float): _amount.text = str(roundi(value)), float(before), float(before + change), Sabacc.anim(0.52))
		await count.finished
	_dealing = false
	_back.disabled = false
	_rules.disabled = false
	_update_deal_button()


func _draw_cards(reveal: Dictionary) -> void:
	var dealt: Array = reveal["cards"]
	var slide := create_tween().set_parallel()
	var face_down: Array[int] = []
	for side in 2:
		if dealt[side] == 0:
			continue
		var card := _cards[side]
		if dealt[side] == War.BACK:
			card = _make_card(side, War.BACK)
			_burned.append(card)
			_place_burn(card, _burned.size() - 1)
			face_down.append(side)
		else:
			card.texture = _face(side, War.BACK)
			card.show()
		var destination := card.position if dealt[side] == War.BACK else _face_centers[side] - card.size / 2.0
		card.position = _deck_centers[side] - card.size / 2.0 - Vector2(1.8, 3.1) * float(_remaining[side] - 1)
		slide.tween_property(card, "position", destination, Sabacc.anim(0.23)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_remaining = reveal["remaining"]
	_layout_decks()
	Sfx.play("draw")
	await slide.finished
	if not face_down.is_empty():
		return
	var flip := create_tween().set_parallel()
	for side in 2:
		if dealt[side] != 0:
			flip.tween_property(_cards[side], "scale:x", 0.0, Sabacc.anim(0.14)).set_trans(Tween.TRANS_SINE)
	await flip.finished
	flip = create_tween().set_parallel()
	for side in 2:
		if dealt[side] != 0:
			_cards[side].texture = _face(side, dealt[side])
			flip.tween_property(_cards[side], "scale:x", 1.0, Sabacc.anim(0.18)).set_trans(Tween.TRANS_CUBIC)
	await flip.finished


func request_screen_back() -> bool:
	if _dealing:
		return true
	if _chapter_id.is_empty():
		Router.go("mini_games")
	else:
		if _allowed:
			CampaignRun.complete_node(_run, _node_id)
			_run.erase("war_table")
			Save.set_run(_run)
		Router.go("chapter", {"chapter_id": _chapter_id})
	return true
