class_name UnitToken
extends Control
## Arena card with a Sabacc silhouette and a stacked attachment preview.

signal pressed(tok: UnitToken)
signal inspect_requested(tok: UnitToken)
signal drag_started(tok: UnitToken)
signal drag_moved(tok: UnitToken, global_pos: Vector2)
signal drag_released(tok: UnitToken, global_pos: Vector2)

const SIZE := Vector2(158, 164)
const FACE := Rect2(8, 22, 142, 94)
const FACE_CENTER := FACE.position + FACE.size / 2.0
const MAX_VISIBLE_ATTACHMENTS := 3
const ART_UV := Rect2(0.12, 0.13, 0.76, 0.46)        # art window on a portrait card render
const ATTACHMENT_ART_UV := Rect2(0.17, 0.16, 0.69, 0.37)  # Stop above the printed rules and pilot stats.
const LONG_PRESS := 0.42

enum Hi { NONE, CAN_ACT, TARGET, SELECTED, HOSTILE_TARGET }

var inst: CardInst
var highlight := Hi.NONE:
	set(v):
		highlight = v
		queue_redraw()
var home_pos := Vector2.ZERO
var _tex: Texture2D
var _t := 0.0
var _flash := 0.0
var _flash_col := Color.WHITE
var _badges: HBoxContainer
var _attachments: Array[CardInst] = []
var _attachment_art: Dictionary = {}
var _attachment_drop: Dictionary = {}
var effects: UnitEffects
var _press := false
var _press_t := 0.0
var _press_pos := Vector2.ZERO
var _long := false
var _dragging := false
var _dying := false
var _light := 0.0
var _light_col := Color.WHITE
var _light_from := Vector2.ZERO


static func create(p_inst: CardInst) -> UnitToken:
	var t := UnitToken.new()
	t.inst = p_inst
	return t


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = FACE_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	effects = UnitEffects.new()
	add_child(effects)
	_badges = HBoxContainer.new()
	_badges.add_theme_constant_override("separation", 1)
	_badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badges.position = Vector2(8, 10)
	add_child(_badges)
	_load_art()
	refresh()


func _load_art() -> void:
	var art: String = inst.data.get("art", inst.id)
	var t := Art.request(art, func(tx): _tex = tx; queue_redraw(), inst.deployed)
	if t:
		_tex = t


func refresh() -> void:
	if not is_instance_valid(_badges):
		return
	for c in _badges.get_children():
		c.queue_free()
	var kws := inst.keyword_list()
	_attachments.clear()
	for upgrade in inst.upgrades:
		if not upgrade.is_token:
			_attachments.append(upgrade)
	for upgrade: CardInst in _attachments.slice(maxi(0, _attachments.size() - MAX_VISIBLE_ATTACHMENTS)):
		if _attachment_art.has(upgrade.uid):
			continue
		var uid := upgrade.uid
		_attachment_art[uid] = Art.request(upgrade.data.get("art", upgrade.id), func(tx):
			_attachment_art[uid] = tx
			queue_redraw())
	var coordinate_active := false
	if inst.has_kw("coordinate") and inst.battle:
		var battle: Match = inst.battle.get_ref()
		coordinate_active = battle != null and battle.players[inst.controller].units.size() >= 3
	effects.set_status(inst.has_kw("sentinel"), coordinate_active, inst.shield_count() > 0)
	for k in kws.slice(0, 3):
		var ic := IconGlyph.new()
		ic.glyph = k["k"]
		ic.frame = true
		ic.color = Sabacc.C_GOLD if k["k"] == "sentinel" else Appearance.color_at(0)
		ic.custom_minimum_size = Vector2(18, 18)
		ic.pulse = k["k"] == "sentinel"
		ic.tooltip_text = k["k"].capitalize()
		_badges.add_child(ic)
	var target_rot := -0.14 if inst.exhausted else 0.0
	if not is_equal_approx(rotation, target_rot) and not _dying:
		create_tween().tween_property(self, "rotation", target_rot, Sabacc.anim(0.25)).set_trans(Tween.TRANS_BACK)
	queue_redraw()


func animate_attachment(card: CardInst) -> void:
	if card == null or card.is_token or card.attached_to != inst:
		return
	refresh()
	if card not in _attachments.slice(maxi(0, _attachments.size() - MAX_VISIBLE_ATTACHMENTS)):
		return
	var uid := card.uid
	_attachment_drop[uid] = 0.0
	var slide := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	slide.tween_method(func(progress: float):
		_attachment_drop[uid] = progress
		queue_redraw(), 0.0, 1.0, Sabacc.anim(0.32))
	await slide.finished
	_attachment_drop.erase(uid)
	queue_redraw()


## Reflected light from bolts/impacts (see Fx.light_at).
func apply_light(col: Color, amount: float, from: Vector2) -> void:
	if amount > _light:
		_light = minf(amount, 1.2)
		_light_col = col
		_light_from = from
	queue_redraw()


## Hit reaction: knocked back away from the source, squashed, springs back.
func hit_punch(from: Vector2) -> void:
	if _dying:
		return
	var dir := (center_global() - from).normalized() if from != Vector2.INF else Vector2(0, 1)
	var s0 := scale
	var tw := create_tween()
	tw.tween_property(self, "position", home_pos + dir * 16.0, 0.05).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", s0 * Vector2(1.12, 0.86), 0.05)
	tw.tween_property(self, "position", home_pos, 0.32).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", s0, 0.32).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _process(dt: float) -> void:
	_t += dt
	if _light > 0.0:
		_light = maxf(0.0, _light - dt * 4.5)
		queue_redraw()
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 3.0)
	if highlight != Hi.NONE or _flash > 0.0 or inst.shield_count() > 0:
		queue_redraw()
	if _press and not _dragging and not _long:
		_press_t += dt
		if _press_t > LONG_PRESS:
			_long = true
			inspect_requested.emit(self)


func _silhouette(rect: Rect2) -> PackedVector2Array:
	var corners := PackedVector2Array([
		Vector2(0.5, 0), Vector2(1, 0.24), Vector2(1, 0.76),
		Vector2(0.5, 1), Vector2(0, 0.76), Vector2(0, 0.24),
	])
	var outline := PackedVector2Array()
	for i in corners.size():
		var point := corners[i]
		var before := point.lerp(corners[posmod(i - 1, corners.size())], 0.14)
		var after := point.lerp(corners[(i + 1) % corners.size()], 0.14)
		for step in 5:
			var progress := step / 4.0
			var curved := before.lerp(point, progress).lerp(point.lerp(after, progress), progress)
			outline.append(rect.position + curved * rect.size)
	return outline


func center_global() -> Vector2:
	return get_global_transform() * FACE_CENTER


func _draw() -> void:
	var pts := _silhouette(FACE)
	var aspects := inst.aspects()
	var frame_col := _frame_color(aspects)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	_draw_attachments(frame_col)
	_draw_alignment_edge(pts, aspects)
	var highlight_color := Color.TRANSPARENT
	match highlight:
		Hi.CAN_ACT:
			highlight_color = Color(Sabacc.C_GOOD, 0.35 + 0.35 * pulse)
		Hi.TARGET:
			highlight_color = Color(Sabacc.C_GOLD, 0.45 + 0.4 * pulse)
		Hi.HOSTILE_TARGET:
			highlight_color = Color(Sabacc.C_EMPIRE, 0.45 + 0.45 * pulse)
		Hi.SELECTED:
			highlight_color = Color(Appearance.color_at(0), 0.9)
	if highlight_color.a > 0.0:
		for i in 3:
			_outline(_silhouette(FACE.grow(3.0 + i * 3.0)), Color(highlight_color, highlight_color.a * (0.9 - i * 0.28)), 3.0)

	var tint := Color("a6a9b6") if inst.exhausted else Color.WHITE
	_draw_art(FACE, pts, _tex, tint, ART_UV)
	if _flash > 0.0:
		draw_colored_polygon(pts, Color(_flash_col, _flash * 0.62))
	if _light > 0.01:
		draw_colored_polygon(pts, Color(_light_col.lightened(0.2), 0.3 * minf(_light, 1.0)))
		var local_from := get_global_transform().affine_inverse() * _light_from
		var direction := FACE_CENTER.direction_to(local_from)
		var edge := FACE_CENTER + direction * FACE.size * 0.4
		draw_circle(edge, 24.0, Color(_light_col.lightened(0.5), 0.22 * _light))
		_outline(pts, Color(_light_col.lightened(0.4), 0.8 * minf(_light, 1.0)), 8.0)
	_outline(pts, Color("101620"), 5.0)
	_outline(pts, frame_col, 2.8)

	_stat(Vector2(17, 89), str(inst.power()), false, inst.power() != inst.printed_power())
	_stat(Vector2(141, 89), str(inst.remaining_hp()), true, inst.max_hp() != inst.printed_hp(), inst.damage > 0)
	_draw_token_markers(pulse)
	if inst.exhausted:
		draw_rect(Rect2(33, 62, 92, 15), Color(0.04, 0.06, 0.09, 0.8))
		UIKit.draw_fit(self, Sabacc.font_title, Vector2(33, 73), "EXHAUSTED", HORIZONTAL_ALIGNMENT_CENTER, 92, 11, Sabacc.C_TEXT)
	if inst.flags.get("protected", false):
		UIKit.draw_fit(self, Sabacc.font_title, Vector2(32, 89), "PROTECT", HORIZONTAL_ALIGNMENT_CENTER, 94, 11, Sabacc.C_GOLD)


func _draw_attachments(frame_col: Color) -> void:
	var count := mini(_attachments.size(), MAX_VISIBLE_ATTACHMENTS)
	for depth in range(count - 1, -1, -1):
		var card := _attachments[_attachments.size() - 1 - depth]
		var rect := Rect2(28, 78 + depth * 13, 102, 60)
		rect.position.y = lerpf(FACE_CENTER.y - rect.size.y * 0.5, rect.position.y, _attachment_drop.get(card.uid, 1.0))
		var pts := _silhouette(rect)
		var aspects := card.aspects()
		_draw_alignment_edge(pts, aspects)
		_draw_art(rect, pts, _attachment_art.get(card.uid), Color("dce5ef"), ATTACHMENT_ART_UV)
		_outline(pts, Color("0b131d"), 4.0)
		_outline(pts, _frame_color(aspects), 2.2)
	if _attachments.size() > count:
		var badge := Rect2(16, 139, 28, 15)
		draw_rect(badge, Color("102031"))
		draw_rect(badge, frame_col, false, 1.0)
		UIKit.draw_fit(self, Sabacc.font_title, badge.position + Vector2(0, 11), "+%d" % (_attachments.size() - count),
			HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 10, frame_col)


static func _frame_color(aspects: Array) -> Color:
	for aspect in aspects:
		if aspect not in ["heroism", "villainy"]:
			return Sabacc.aspect_color(aspect).lightened(0.16)
	return Sabacc.aspect_color(aspects[0]).lightened(0.24) if not aspects.is_empty() else Sabacc.C_DIM


func _draw_alignment_edge(points: PackedVector2Array, aspects: Array) -> void:
	if "villainy" in aspects:
		var bottom := points.slice(10, 25)
		for i in bottom.size():
			bottom[i].y += 4.0
		draw_polyline(bottom, Color(0, 0, 0, 0.26), 9.0, true)
		draw_polyline(bottom, Color(0, 0, 0, 0.42), 5.0, true)
	if "heroism" in aspects:
		var top := points.slice(25)
		top.append_array(points.slice(0, 10))
		draw_polyline(top, Color(1, 1, 1, 0.10), 10.0, true)
		draw_polyline(top, Color(1, 1, 1, 0.22), 6.0, true)


func _draw_art(rect: Rect2, pts: PackedVector2Array, texture: Texture2D, tint: Color, crop: Rect2) -> void:
	draw_colored_polygon(pts, Color("1a2636"))
	if not texture or texture == Art.placeholder:
		return
	var uv := PackedVector2Array()
	for point in pts:
		uv.append(crop.position + (point - rect.position) / rect.size * crop.size)
	draw_colored_polygon(pts, tint, uv, texture)


func _outline(points: PackedVector2Array, color: Color, width: float) -> void:
	var line := points.duplicate()
	line.append(points[0])
	draw_polyline(line, color, width, true)


func _draw_token_markers(pulse: float) -> void:
	var shields := inst.shield_count()
	if shields > 0 and UnitEffects.sheet("shield") == null:
		draw_arc(FACE_CENTER, 67, 0, TAU, 40, Color(0.45, 0.85, 1.0, 0.35 + 0.2 * pulse), 4.0, true)
	if shields > 1:
		UIKit.draw_fit(self, Sabacc.font_title, Vector2(127, 54), "×%d" % shields, HORIZONTAL_ALIGNMENT_CENTER, 28, 11, Color("acebff"))
	var pips := 0
	for token in inst.upgrades:
		if token.is_token and token.name() != "Shield":
			var at := Vector2(22 + pips * 9, 47)
			var shape := PackedVector2Array([at + Vector2(0, -4), at + Vector2(4, 0), at + Vector2(0, 4), at + Vector2(-4, 0)])
			draw_colored_polygon(shape, Sabacc.C_GOLD if token.name() == "Experience" else Appearance.color_at(0))
			pips += 1
			if pips == 5:
				break


func _stat(at: Vector2, value: String, health: bool, modified: bool, damaged := false) -> void:
	var silhouette: PackedVector2Array
	if health:
		silhouette = PackedVector2Array([Vector2(-13, -7), Vector2(-8, -13), Vector2(8, -13), Vector2(13, -7), Vector2(13, 8), Vector2(8, 14), Vector2(-8, 14), Vector2(-13, 8)])
	else:
		silhouette = PackedVector2Array([Vector2(-13, -7), Vector2(-6, -12), Vector2(0, -11), Vector2(6, -12), Vector2(13, -7), Vector2(13, 10), Vector2(0, 15), Vector2(-13, 10)])
	draw_set_transform(at)
	var color := Color("2477b4") if health else Color("bd2c27")
	draw_colored_polygon(silhouette, color.darkened(0.24))
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -6), Vector2(10, -6), Vector2(10, 0), Vector2(-10, 0)]), color.lightened(0.13))
	_outline(silhouette, Color("121b25"), 4.0)
	_outline(silhouette, Sabacc.C_GOLD if modified else color.lightened(0.75), 1.6)
	UIKit.draw_fit(self, Sabacc.font_title, Vector2(-12, 7), value, HORIZONTAL_ALIGNMENT_CENTER, 24, 19,
		Color("ffcec7") if damaged else Color.WHITE)
	draw_set_transform(Vector2.ZERO)

# ---------------------------------------------------------------- input

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			inspect_requested.emit(self)
			accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if mb.double_click:
				inspect_requested.emit(self)
				return
			_press = true
			_press_t = 0.0
			_long = false
			_press_pos = mb.global_position
		else:
			if _dragging:
				_dragging = false
				drag_released.emit(self, mb.global_position)
			elif _press and not _long:
				pressed.emit(self)
			_press = false
		accept_event()
	elif ev is InputEventMouseMotion and _press:
		var mm := ev as InputEventMouseMotion
		if not _dragging and not _long and mm.global_position.distance_to(_press_pos) > 16.0:
			_dragging = true
			drag_started.emit(self)
		if _dragging:
			drag_moved.emit(self, mm.global_position)
		accept_event()


# ---------------------------------------------------------------- animation

func flash(col: Color) -> void:
	_flash = 1.0
	_flash_col = col
	queue_redraw()


func pop_in() -> void:
	scale = Vector2(0.2, 0.2)
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, Sabacc.anim(0.4)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, Sabacc.anim(0.2))
	flash(Appearance.color_at(0))


func shake(amount := 8.0) -> void:
	var tw := create_tween()
	var base := position
	for i in 4:
		tw.tween_property(self, "position", base + Vector2(randf_range(-amount, amount), randf_range(-amount, amount) * 0.5), 0.04)
	tw.tween_property(self, "position", home_pos, 0.06)


func lunge(to_global: Vector2) -> void:
	z_index = 20
	var start := position
	var delta := (to_global - center_global()) * 0.78
	var tw := create_tween()
	tw.tween_property(self, "position", start - delta.normalized() * 14.0, Sabacc.anim(0.1)).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "position", start + delta, Sabacc.anim(0.16)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await tw.finished


func lunge_back() -> void:
	var tw := create_tween()
	tw.tween_property(self, "position", home_pos, Sabacc.anim(0.3)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	z_index = 0


func die() -> void:
	_dying = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash(Color(1, 0.4, 0.2))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.25, 0.2), Sabacc.anim(0.35)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate", Color(2.0, 1.2, 0.8, 0.0), Sabacc.anim(0.35))
	tw.tween_property(self, "rotation", randf_range(-0.4, 0.4), Sabacc.anim(0.35))
	await tw.finished
	queue_free()
