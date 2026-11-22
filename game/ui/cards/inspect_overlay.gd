class_name InspectOverlay
extends Control
## Skirmish-inspired radial dossiers, screen blur and reversible card flight.

signal closed

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float amount = 0.0;
void fragment() {
	vec3 acc = vec3(0.0);
	vec2 radial = SCREEN_UV - vec2(0.5);
	for (int i = 0; i < 20; i++) {
		float t = (float(i) + 0.5) / 20.0;
		float a = float(i) * 2.39996323;
		vec2 disc = vec2(cos(a), sin(a)) * sqrt(t) * 14.0 * SCREEN_PIXEL_SIZE;
		acc += texture(screen_tex, SCREEN_UV + (disc + radial * (t - 0.5) * 0.05) * amount).rgb;
	}
	COLOR = vec4(mix(acc / 20.0, vec3(0.012, 0.018, 0.028), amount * 0.64), 1.0);
}
"""
const ATTACHMENT_SHADER := """
shader_type canvas_item;
void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	float scan = 0.72 + 0.28 * sin(UV.y * 330.0 + TIME * 1.25);
	float luminance = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(pixel.rgb, vec3(0.26, 0.69, 0.94) * (0.48 + luminance * 0.55), 0.52), pixel.a * scan * 0.65);
}
"""

var _card: CardView
var _panels: Array[PanelContainer] = []
var _back := false
var _id := ""
var _inst: CardInst
var _scale := 1.0
var _origin := Rect2()
var _blur: ShaderMaterial
var _chrome: OrbitChrome
var _heading: Label
var _actions: HBoxContainer
var _flip_button: Button
var _attachment_picker: OptionButton
var _stack: Array[CardInst] = []
var _stack_index := 0
var _carousel_previews: Array[TextureRect] = []
var _carousel_arrows: Array[Button] = []
var _carousel_origin := Vector2.ZERO
var _carousel_pointer := -2
var _carousel_over_card := false
var _carousel_drag := false
var _flight: Tween
var _closing := false
var _time := 0.0
var _expanded: ModalPanel

const ASPECT_HELP := {
	"vigilance": "Vigilance: defensive tactics, endurance and protecting your board.",
	"command": "Command: leadership, resource development and coordinated forces.",
	"aggression": "Aggression: direct damage, pressure and decisive attacks.",
	"cunning": "Cunning: tricks, tempo, evasion and disrupting an opponent.",
	"heroism": "Heroism is an alignment aspect. Its icon is still required when paying aspect penalties.",
	"villainy": "Villainy is an alignment aspect. Its icon is still required when paying aspect penalties.",
}


func _accent(index: int = 0) -> Color:
	var aspects: Array = _inst.aspects() if _inst else CardDB.card(_id).get("aspects", [])
	if aspects.is_empty():
		return Color("c9ba95")
	var aspect: String = aspects[posmod(index, aspects.size())]
	return Color("a9afbd") if aspect == "villainy" else Sabacc.aspect_color(aspect).lightened(0.12)


static func open(host: Node, id: String, from_rect := Rect2(), p_inst: CardInst = null) -> InspectOverlay:
	var overlay := InspectOverlay.new()
	overlay._id = id
	overlay._inst = p_inst
	overlay._back = p_inst != null and p_inst.deployed
	var layer := CanvasLayer.new()
	layer.layer = 50
	host.add_child(layer)
	layer.add_child(overlay)
	overlay._build(from_rect)
	return overlay


func _build(from_rect: Rect2) -> void:
	theme = UIKit.build_theme()
	UIKit.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("back_dismissible")
	_origin = from_rect
	var backdrop := ColorRect.new()
	UIKit.fill_rect(backdrop)
	backdrop.color = Color(0.01, 0.02, 0.03, 0.9) if Sabacc.perf() else Color.WHITE
	backdrop.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			close_overlay())
	add_child(backdrop)
	if not Sabacc.perf():
		var shader := Shader.new()
		shader.code = BLUR_SHADER
		_blur = ShaderMaterial.new()
		_blur.shader = shader
		backdrop.material = _blur
		create_tween().tween_method(_set_blur, 0.0, 1.0, Sabacc.anim(0.3))
	_chrome = OrbitChrome.new()
	_chrome.overlay = self
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.fill_rect(_chrome)
	add_child(_chrome)
	_heading = UIKit.label(_card_data().get("name", _id).to_upper(), 26, _accent(), HORIZONTAL_ALIGNMENT_CENTER)
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_heading.clip_text = true
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_heading)
	_add_attachment_picker()
	_actions = HBoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("separation", 16)
	add_child(_actions)
	_flip_button = SabaccButton.make("Flip leader", SabaccButton.Style.GOLD)
	_flip_button.visible = _can_flip()
	_flip_button.pressed.connect(_flip)
	_actions.add_child(_flip_button)
	var close := SabaccButton.make("Close", SabaccButton.Style.GHOST)
	close.custom_minimum_size.x = 160
	close.pressed.connect(close_overlay)
	_actions.add_child(close)
	_add_live_actions()
	_make_card()
	_make_panels()
	_layout()
	_animate_in()
	get_viewport().size_changed.connect(_resize)
	Sfx.play("whoosh", 1.5)


func _set_blur(value: float) -> void:
	if _blur:
		_blur.set_shader_parameter("amount", value)


func _card_data() -> Dictionary:
	return _inst.data if _inst else CardDB.card(_id)


func _can_flip() -> bool:
	return _card_data().get("type") == "leader" and not (_inst and _inst.is_pilot_upgrade())


func _add_attachment_picker() -> void:
	if _inst == null:
		return
	var host := _inst.attached_to if _inst.attached_to else _inst
	if host.upgrades.is_empty():
		return
	_stack.append(host)
	_stack.append_array(host.upgrades)
	_stack_index = _stack.find(_inst)
	var shader := Shader.new()
	shader.code = ATTACHMENT_SHADER
	var hologram := ShaderMaterial.new()
	hologram.shader = shader
	for direction in [-1, 1]:
		var preview := TextureRect.new()
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.material = hologram
		add_child(preview)
		_carousel_previews.append(preview)
		var arrow := SabaccButton.make("‹" if direction < 0 else "›", SabaccButton.Style.GHOST)
		arrow.custom_minimum_size = Vector2(46, 46)
		arrow.tooltip_text = "Previous card" if direction < 0 else "Next card"
		arrow.pressed.connect(_step_attachment.bind(direction))
		add_child(arrow)
		_carousel_arrows.append(arrow)
	_attachment_picker = OptionButton.new()
	_attachment_picker.fit_to_longest_item = false
	_attachment_picker.clip_text = true
	_attachment_picker.tooltip_text = "Choose the host card or an attachment to inspect"
	_attachment_picker.add_item("Host · " + host.name())
	for upgrade in host.upgrades:
		var role := "Pilot" if upgrade.is_pilot_upgrade() else ("Token" if upgrade.is_token else "Upgrade")
		_attachment_picker.add_item(role + " · " + upgrade.name())
	_attachment_picker.select(_stack_index)
	_attachment_picker.item_selected.connect(_inspect_attachment)
	add_child(_attachment_picker)


func _inspect_attachment(index: int) -> void:
	if _closing or index < 0 or index >= _stack.size() or index == _stack_index:
		return
	if _flight and _flight.is_valid():
		_flight.kill()
	_stack_index = index
	_attachment_picker.select(index)
	_inst = _stack[_stack_index]
	_id = _inst.id
	_back = _inst.deployed
	_heading.text = _inst.name().to_upper()
	_heading.add_theme_color_override("font_color", _accent())
	_flip_button.visible = _can_flip()
	_make_card()
	_make_panels()
	_layout()
	Sfx.play("whoosh", 1.5)


func _step_attachment(direction: int) -> void:
	var next := posmod(_stack_index + direction, _stack.size())
	_inspect_attachment(next)
	if not _closing and not Sabacc.perf():
		_card.position.x += 64 * direction
		_card.modulate.a = 0.72
		_flight = create_tween().set_parallel()
		_flight.tween_property(_card, "position", _card.home_pos, Sabacc.anim(0.24)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_flight.tween_property(_card, "modulate:a", 1.0, Sabacc.anim(0.2))


func _layout_attachment_previews(view: Vector2, shown: Vector2) -> void:
	for slot in _carousel_previews.size():
		var direction := slot * 2 - 1
		var index := posmod(_stack_index + direction, _stack.size())
		var card := _stack[index]
		var preview := _carousel_previews[slot]
		preview.visible = _stack.size() > 2 or direction == 1
		var art_id: String = card.data.get("art", card.id)
		var back := card.deployed
		var art_key := art_id + str(back)
		if preview.get_meta("art_key", "") != art_key:
			preview.set_meta("art_key", art_key)
			preview.texture = Art.request(art_id, func(texture):
				if is_instance_valid(preview) and preview.get_meta("art_key", "") == art_key:
					preview.texture = texture, back)
		preview.size = shown * 0.86
		preview.pivot_offset = preview.size * 0.5
		preview.position = (view - preview.size) * 0.5 + Vector2(direction * shown.x * 0.31, 8)
		preview.rotation_degrees = direction * 9


func _input(event: InputEvent) -> void:
	if _stack.size() < 2 or _closing or is_instance_valid(_expanded) or _card == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _carousel_pointer < 0:
			_begin_carousel_swipe(event.index, event.position)
		elif not event.pressed and event.index == _carousel_pointer:
			_finish_carousel_swipe(event.position, event.canceled)
	elif event is InputEventScreenDrag and event.index == _carousel_pointer:
		_track_carousel_swipe(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _carousel_pointer >= 0:
			# Accept the native finger as the gesture owner even when Android also emits a mouse event.
			if not _carousel_over_card or _carousel_drag:
				get_viewport().set_input_as_handled()
		elif event.pressed:
			_begin_carousel_swipe(-1, event.position)
		elif _carousel_pointer == -1:
			_finish_carousel_swipe(event.position)
	elif event is InputEventMouseMotion and _carousel_pointer == -1:
		_track_carousel_swipe(event.position)


func _begin_carousel_swipe(pointer: int, at: Vector2) -> void:
	var card_rect := _card.get_global_rect()
	_carousel_over_card = card_rect.has_point(at)
	var over_preview := _carousel_previews.any(func(preview):
		return preview.visible and Rect2(Vector2.ZERO, preview.size).has_point(preview.get_global_transform_with_canvas().affine_inverse() * at))
	if not _carousel_over_card and not over_preview:
		return
	_carousel_origin = at
	_carousel_pointer = pointer
	_carousel_drag = false
	if not _carousel_over_card:
		get_viewport().set_input_as_handled()


func _horizontal_swipe(at: Vector2) -> bool:
	var delta := at - _carousel_origin
	return absf(delta.x) >= 36.0 and absf(delta.x) > absf(delta.y) * 1.25


func _track_carousel_swipe(at: Vector2) -> void:
	_carousel_drag = _carousel_drag or _horizontal_swipe(at)
	if _carousel_drag:
		_card._press = false
		get_viewport().set_input_as_handled()


func _finish_carousel_swipe(at: Vector2, canceled := false) -> void:
	_carousel_pointer = -2
	var navigate := not canceled and _horizontal_swipe(at)
	if navigate or canceled or _carousel_drag or not _carousel_over_card:
		_card._press = false
		get_viewport().set_input_as_handled()
	_carousel_drag = false
	if navigate:
		_step_attachment.call_deferred(-1 if at.x > _carousel_origin.x else 1)


func _add_live_actions() -> void:
	if _inst == null or _inst.battle == null:
		return
	var match_state: Match = _inst.battle.get_ref()
	var host := get_parent().get_parent()
	if match_state == null or not host.has_method("_act") or _inst.controller != 0:
		return
	var ids: Array = [_inst.uid]
	for upgrade in _inst.upgrades:
		ids.append(upgrade.uid)
	var available: Array = []
	for action in match_state.legal_actions(0):
		if action["a"] == "ability" and action["uid"] in ids:
			available.append(action)
	if available.is_empty():
		return
	var options := OptionButton.new()
	options.add_item("Card actions…")
	options.custom_minimum_size = Vector2(190, 56)
	for action in available:
		var source := match_state.card(action["uid"])
		options.add_item(source.name() + " · Action %d" % (int(action["idx"]) + 1))
	options.item_selected.connect(func(i):
		if i > 0:
			await close_overlay()
			if is_instance_valid(host):
				host._act(available[i - 1]))
	_actions.add_child(options)


func _make_card() -> void:
	if is_instance_valid(_card):
		remove_child(_card)
		_card.queue_free()
	_card = CardView.new()
	_card.show_back_side = _back
	_card.set_card(_id)
	_card.data = _card_data()
	_card.draggable = false
	_card.hover_lift = false
	_card.tapped.connect(func(_view): _expand_panel(0))
	_card.tooltip_text = "Tap to expand aspects and card anatomy"
	_card.pivot_offset = Vector2.ZERO
	add_child(_card)
	_card._tex = Art.get_now(_card.data.get("art", _id), _back)


func _panel(title: String, index: int) -> VBoxContainer:
	var panel := UIKit.panel(Color(Sabacc.C_PANEL, 0.96), Color(_accent(index), 0.75), 12, 5)
	panel.name = "Dossier" + str(index)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	_panels.append(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var header := HBoxContainer.new()
	var label := UIKit.label(title.to_upper(), 18, _accent(index))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var expand := SabaccButton.make("+", SabaccButton.Style.GHOST)
	expand.custom_minimum_size = Vector2(42, 42)
	expand.add_theme_font_size_override("font_size", 18)
	expand.tooltip_text = "Expand " + title
	expand.pressed.connect(_expand_panel.bind(_panels.size() - 1))
	header.add_child(expand)
	box.add_child(header)
	return box


func _expand_panel(index: int) -> void:
	if _closing or is_instance_valid(_expanded) or index >= _panels.size():
		return
	var source: VBoxContainer = _panels[index].get_child(0).get_child(0)
	_expanded = ModalPanel.open(self, 880, _accent(index))
	_expanded._layer.layer = 70
	_expanded.dismiss_on_backdrop = true
	_expanded.text(source.get_child(0).get_child(0).text, 28, _accent(index))
	for child in source.get_children().slice(1):
		var copy := child.duplicate() as Control
		if child.has_meta("aspects"):
			copy.free()
			copy = HBoxContainer.new()
			copy.add_theme_constant_override("separation", 8)
			for aspect in child.get_meta("aspects"):
				copy.add_child(AspectIcon.make(aspect, 40))
		if copy is Label:
			copy.add_theme_font_size_override("font_size", 22)
		_expanded.add(copy)
	var back := SabaccButton.make("Back to card", SabaccButton.Style.PRIMARY)
	back.pressed.connect(_expanded.close)
	_expanded.add_action(back)
	_expanded.closed.connect(func(): _expanded = null)


func _text(box: VBoxContainer, text: String, color := Sabacc.C_TEXT) -> void:
	var label := UIKit.label(text, 17, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)


func _make_panels() -> void:
	for panel in _panels:
		remove_child(panel)
		panel.queue_free()
	_panels.clear()
	var d := _card_data()
	var pilot := _inst != null and _inst.is_pilot_upgrade()
	var commander := _inst != null and _inst.is_commander()
	var face: Dictionary = d["pilot"] if pilot else (d.get("leader_unit", {}) if _back else d)
	var kind: String = "upgrade" if pilot else d.get("type", "")
	var aspects: Array = _inst.aspects() if _inst else d.get("aspects", [])
	var profile := _panel("Aspects & anatomy", 0)
	_text(profile, d.get("name", _id))
	if d.get("subtitle", "") != "":
		_text(profile, d["subtitle"], Sabacc.C_DIM)
	var role := "Commander · Leader and base" if commander else ("Pilot upgrade" if pilot else UIKit.type_label(kind))
	_text(profile, "%s · %s" % [role, ", ".join(d.get("traits", [])).capitalize()])
	_text(profile, "Aspects: " + ", ".join(aspects).capitalize())
	var icons := HBoxContainer.new()
	icons.set_meta("aspects", aspects)
	icons.add_theme_constant_override("separation", 6)
	for aspect in aspects:
		icons.add_child(AspectIcon.make(aspect, 34))
	profile.add_child(icons)
	for aspect in aspects:
		_text(profile, ASPECT_HELP.get(aspect, aspect.capitalize()), Sabacc.C_DIM)
	_text(profile, "Your leader and base supply aspect icons. Each unmatched printed icon adds 2 resources to this card's cost in traditional battles.")
	var stats: Array[String] = []
	var cost: Dictionary = face if pilot else d
	if cost.has("cost") and not commander:
		stats.append(("Deploy threshold %d" if kind == "leader" else "Cost %d") % int(cost["cost"]))
	if face.has("power"):
		stats.append(("Power %+d" if kind == "upgrade" else "Power %d") % int(face["power"]))
	if face.has("hp"):
		stats.append(("HP %+d" if kind == "upgrade" else "HP %d") % int(face["hp"]))
	_text(profile, " · ".join(stats), _accent(1))
	if cost.has("cost") and not commander:
		_text(profile, "Deployment threshold: control this many resources to meet the leader's Epic Action requirement. The threshold does not spend those resources; check any printed additional costs." if kind == "leader" else "Cost: resources exhausted to play the card, before applicable discounts or aspect penalties.", Sabacc.C_DIM)
	if face.has("power"):
		_text(profile, "Power modifier: added to the attached unit's combat power." if kind == "upgrade" else "Power: combat damage dealt when attacking or defending.", Sabacc.C_DIM)
	if face.has("hp"):
		_text(profile, "HP modifier: added to the attached unit's HP; the upgrade does not take damage itself." if kind == "upgrade" else ("HP: damage this base can sustain before you lose." if kind == "base" else "HP: damage capacity. A unit with damage equal to or above its current HP is defeated."), Sabacc.C_DIM)
	if commander:
		_text(profile, "Deployed from the start. Defeating this commander wins the battle.")
	elif kind == "leader":
		_text(profile, "Leader deployment: its Epic Action can be used once per game when you meet its resource threshold (%d). Flip to inspect the unit side." % int(d.get("epic_cost", d.get("cost", 0))))
	if kind == "unit" or kind == "leader":
		_text(profile, "Arena: " + str(face.get("arena", d.get("arena", "Not an arena unit"))).capitalize() + ". Ground and space units normally attack in their own arena.", Sabacc.C_DIM)
	_text(profile, "Traits and uniqueness: traits enable card synergies; a unique title is subject to the uniqueness rule. Traits do not grant abilities by themselves.", Sabacc.C_DIM)
	_text(profile, "Unique title: the diamond identifies a unique card; control of matching unique titles is restricted by the uniqueness rule." if d.get("unique", false) else "Non-unique card: no uniqueness marker. Deck copy limits still apply.", Sabacc.C_DIM)
	_text(profile, "%s · %s" % [d.get("set", ""), d.get("number", "")], Sabacc.C_DIM)
	var rules := _panel("Printed ability", 1)
	var printed: String = face.get("text", d.get("text", "") if pilot else "")
	_text(rules, printed if printed != "" else "No printed ability on this side.")
	if commander and _back and d.get("text", "") != "":
		_text(rules, "Leader side")
		_text(rules, str(d["text"]))
	var glossary := _panel("Keywords & timing", 2)
	var keywords: Array = _inst.keyword_list() if _inst else face.get("keywords", [])
	for keyword in keywords:
		var key: String = keyword["k"]
		_text(glossary, "%s%s — %s" % [key.capitalize(), " %s" % keyword["v"] if keyword.has("v") else "", UIKit.KEYWORD_HELP.get(key, "See the printed card for this ability.")])
	# Conditional/granted keywords belong in the glossary even though they must
	# not be granted unconditionally by the rules engine.
	for key in UIKit.KEYWORD_HELP:
		var printed_keyword := RegEx.create_from_string("(?i)\\b" + key + "\\b").search(printed)
		if printed_keyword and not keywords.any(func(entry): return entry["k"] == key):
			_text(glossary, key.capitalize() + " (conditional / referenced) — " + UIKit.KEYWORD_HELP[key])
	for entry in [["Shield token", "Defeat one Shield token to prevent the next damage that would be dealt to its attached unit."], ["Experience token", "Each Experience upgrade grants +1 power and +1 HP to its attached unit."], ["Force", "The Force token is a player resource: abilities can grant it or require you to use it. Using it spends the token."], ["Exhaust", "Turn the card sideways. Exhausted units normally cannot attack; ready them during regroup unless a rule says otherwise."]]:
		if entry[0].to_lower() in printed.to_lower():
			_text(glossary, entry[0] + " — " + entry[1])
	for trigger in [["When Played", "Resolves when this card is played, before the next normal action."], ["On Attack", "Resolves when this unit attacks, before combat damage."], ["When Defeated", "Resolves when this card is defeated."], ["Epic Action", "A once-per-game action. Meet its printed requirement first."], ["Action", "Uses your action for the turn and requires its printed costs."]]:
		if trigger[0] in printed and not (trigger[0] == "Action" and "Epic Action" in printed):
			_text(glossary, trigger[0] + " — " + trigger[1])
	if glossary.get_child_count() == 1:
		_text(glossary, "No keywords or timing triggers on this side.", Sabacc.C_DIM)
	var status := _panel("Live state & support", 0)
	if _inst:
		_text(status, "Zone: %s · %s" % [_inst.zone.capitalize(), "Exhausted" if _inst.exhausted else "Ready"])
		if _inst.attached_to:
			_text(status, "Attached to " + _inst.attached_to.name())
		if not _inst.upgrades.is_empty():
			_text(status, "Attached upgrades / tokens: %d" % _inst.upgrades.size())
		if _inst.in_play():
			_text(status, "Power %d · HP %d / %d · Damage %d" % [_inst.power(), _inst.remaining_hp(), _inst.max_hp(), _inst.damage])
			var held: Array = _inst.flags.get("captives", [])
			if not held.is_empty():
				_text(status, "Guarding %d captured unit(s). They return exhausted when this guard leaves play." % held.size())
	else:
		_text(status, "Collection preview. Live match modifiers appear here during a battle.", Sabacc.C_DIM)
	var support: String = d.get("implemented", "manual")
	var coverage := "Rules coverage unavailable"
	match support:
		"full": coverage = "Rules coverage: all printed lines mapped"
		"partial": coverage = "Rules coverage: some printed lines mapped"
		"manual": coverage = "Rules coverage: manual effects"
	_text(status, coverage, Sabacc.C_GOOD if support == "full" else Sabacc.C_GOLD)
	for line in d.get("unparsed", []):
		_text(status, "Not automated: " + line, Sabacc.C_DIM)
	if support != "full":
		_text(status, "Some printed effects still need engine support. The reference text above remains visible.", Sabacc.C_DIM)


func _resize() -> void:
	if _closing:
		return
	if _flight and _flight.is_valid():
		_flight.kill()
	for panel in _panels:
		panel.modulate.a = 1.0
	_layout()


func _layout() -> void:
	if not is_instance_valid(_card) or _panels.size() != 4:
		return
	var view := get_viewport_rect().size
	var portrait := view.y >= view.x
	var card_size := _card.base_size()
	var available := Vector2(view.x * 0.63, view.y * 0.36) if portrait else Vector2(view.x * 0.33, view.y * 0.67)
	if _attachment_picker and not portrait:
		available.y = minf(available.y, maxf(64.0, view.y - 220.0))
	_scale = minf(available.x / card_size.x, available.y / card_size.y)
	var shown := card_size * _scale
	_card.home_pos = (view - shown) / 2.0
	_card.home_scale = Vector2.ONE * _scale
	_card.scale = _card.home_scale
	_card.position = _card.home_pos
	_heading.position = Vector2(26, 14)
	_heading.size = Vector2(view.x - 52, 42)
	var top := 64.0
	if _attachment_picker:
		var picker_width := minf(view.x - 124, 420)
		_attachment_picker.size = Vector2(picker_width, 46)
		_attachment_picker.position = Vector2((view.x - picker_width) / 2.0, 56)
		_carousel_arrows[0].position = _attachment_picker.position - Vector2(52, 0)
		_carousel_arrows[1].position = _attachment_picker.position + Vector2(picker_width + 6, 0)
		for arrow in _carousel_arrows:
			arrow.size = Vector2(46, 46)
		_layout_attachment_previews(view, shown)
		top = 116.0
	_actions.position = Vector2(20, view.y - 76)
	_actions.size = Vector2(view.x - 40, 56)
	var margin := 22.0
	var gap := 16.0
	if portrait:
		var width := (view.x - margin * 2.0 - gap) / 2.0
		var top_height := maxf(70, _card.home_pos.y - top - 18)
		var lower_y := _card.home_pos.y + shown.y + 22
		var lower_height := maxf(70, view.y - 92 - lower_y)
		for i in 4:
			_panels[i].position = Vector2(margin + (i % 2) * (width + gap), top if i < 2 else lower_y)
			_panels[i].size = Vector2(width, top_height if i < 2 else lower_height)
	else:
		var width := maxf(100, _card.home_pos.x - margin - 26)
		var height := (view.y - top - 116) / 2.0
		for i in 4:
			_panels[i].position = Vector2(margin if i % 2 == 0 else view.x - margin - width, top + 6 + (i / 2) * (height + gap))
			_panels[i].size = Vector2(width, height)
	_chrome.queue_redraw()


func _animate_in() -> void:
	var target := _card.home_pos
	if _origin.size.x > 0:
		_card.position = _origin.position
		_card.scale = Vector2.ONE * (_origin.size.x / _card.size.x)
	else:
		_card.scale *= 0.8
	_flight = create_tween().set_parallel()
	_flight.tween_property(_card, "position", target, Sabacc.anim(0.34)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_flight.tween_property(_card, "scale", _card.home_scale, Sabacc.anim(0.34)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for panel in _panels:
		panel.modulate.a = 0
		_flight.tween_property(panel, "modulate:a", 1.0, Sabacc.anim(0.25)).set_delay(Sabacc.anim(0.15))


func _flip() -> void:
	if _closing or not _can_flip():
		return
	if _flight and _flight.is_valid():
		_flight.kill()
	_back = not _back
	_make_card()
	_make_panels()
	_layout()
	_animate_in()
	Sfx.play("deploy", 1.4)


func _process(delta: float) -> void:
	if not Sabacc.perf():
		_time += delta
		if _chrome:
			_chrome.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		request_back()


func request_back() -> void:
	if is_instance_valid(_expanded):
		_expanded.close()
	else:
		close_overlay()


func close_overlay() -> void:
	if _closing:
		return
	_closing = true
	if _flight and _flight.is_valid():
		_flight.kill()
	var tween := create_tween().set_parallel()
	tween.tween_method(_set_blur, 1.0, 0.0, Sabacc.anim(0.22))
	for panel in _panels:
		tween.tween_property(panel, "modulate:a", 0.0, Sabacc.anim(0.15))
	tween.tween_property(_chrome, "modulate:a", 0.0, Sabacc.anim(0.15))
	if _origin.size.x > 0:
		tween.tween_property(_card, "position", _origin.position, Sabacc.anim(0.22))
		tween.tween_property(_card, "scale", Vector2.ONE * (_origin.size.x / _card.size.x), Sabacc.anim(0.22))
	else:
		tween.tween_property(_card, "modulate:a", 0.0, Sabacc.anim(0.22))
	await tween.finished
	closed.emit()
	get_parent().queue_free()


class OrbitChrome extends Control:
	var overlay: InspectOverlay

	func _draw() -> void:
		if not is_instance_valid(overlay._card):
			return
		var center := size / 2.0
		var shown := overlay._card.base_size() * overlay._scale
		var radius := maxf(shown.x, shown.y) * 0.57
		for i in 3:
			var col := overlay._accent(i)
			var angle := overlay._time * (0.12 if i % 2 == 0 else -0.1) + i * 2
			draw_arc(center, radius + i * 9, angle, angle + PI * 1.25, 90, Color(col, 0.28), 1.4, true)
		for i in 48:
			var dir := Vector2.from_angle(i * TAU / 48 + overlay._time * 0.04)
			draw_line(center + dir * radius, center + dir * (radius + (10 if i % 4 == 0 else 4)), Color(overlay._accent(i), 0.3), 1.0, true)
		for i in overlay._panels.size():
			var panel := overlay._panels[i]
			var end := panel.position + panel.size / 2.0
			var dir := (end - center).normalized()
			var start := center + dir * radius
			var elbow := Vector2(end.x, start.y)
			draw_polyline(PackedVector2Array([start, elbow, end]), Color(overlay._accent(i), 0.32), 1.3, true)
			draw_circle(start, 3.0, overlay._accent(i))
