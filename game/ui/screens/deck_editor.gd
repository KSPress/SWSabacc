extends ScreenBase

const CardFilters = preload("res://ui/kit/card_filters.gd")
const CardScroll = preload("res://ui/kit/card_scroll.gd")
## Deck editor: leader + base (radial pickers), name, icon, favourite mark and
## the deck's aspect icons on top; card pool on one side, the deck list with
## curve and legality on the other (tabs in portrait, split in landscape).
## Tap a pool card to add it (max 3), tap -/+ in the list to adjust.

var deck: Dictionary
var dirty := false

var _ident: HBoxContainer
var _leader_slot: SlotCard
var _base_slot: SlotCard
var _name_edit: LineEdit
var _icon_btn: SabaccButton
var _mark_btn: SabaccButton
var _aspect_box: HBoxContainer
var _tabs: HBoxContainer
var _tab_pool: SabaccButton
var _tab_deck: SabaccButton
var _pool: Control
var _deck_panel: Control
var _pool_filters: VBoxContainer
var _pool_scroll: ScrollContainer
var _pool_count: Label
var _list_box: VBoxContainer
var _summary: Label
var _curve: CurveBars
var _problems: Label
var _save_btn: SabaccButton
var _show_pool := true


func build() -> void:
	var id: String = Router.params.get("deck_id", "")
	deck = Save.get_deck(id).duplicate(true) if id != "" else {}
	if deck.is_empty():
		deck = {"id": "", "name": "New deck", "icon": "star", "marked": false, "leader": "", "base": "", "cards": {}}
	set_header("Deck Editor", "decks")
	# identity row
	_ident = HBoxContainer.new()
	_ident.add_theme_constant_override("separation", 10)
	body.add_child(_ident)
	_leader_slot = SlotCard.new()
	_leader_slot.kind = "leader"
	_leader_slot.pressed.connect(func(): _pick("leader"))
	_ident.add_child(_leader_slot)
	_base_slot = SlotCard.new()
	_base_slot.kind = "base"
	_base_slot.pressed.connect(func(): _pick("base"))
	_ident.add_child(_base_slot)
	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 6)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ident.add_child(meta)
	_name_edit = LineEdit.new()
	_name_edit.text = deck.get("name", "")
	_name_edit.placeholder_text = "Deck name"
	_name_edit.custom_minimum_size.y = 48
	_name_edit.text_changed.connect(func(t): deck["name"] = t; dirty = true)
	meta.add_child(_name_edit)
	var row := HBoxContainer.new()
	row.name = "MetaRow"
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	_icon_btn = SabaccButton.make("", SabaccButton.Style.GHOST, deck.get("icon", "star"))
	_icon_btn.custom_minimum_size = Vector2(56, 52)
	_icon_btn.tooltip_text = "Deck icon"
	_icon_btn.pressed.connect(_pick_icon)
	row.add_child(_icon_btn)
	_mark_btn = SabaccButton.make("", SabaccButton.Style.GOLD if deck.get("marked", false) else SabaccButton.Style.GHOST, "star")
	_mark_btn.custom_minimum_size = Vector2(56, 52)
	_mark_btn.tooltip_text = "Mark as favourite"
	_mark_btn.pressed.connect(_toggle_mark)
	row.add_child(_mark_btn)
	_aspect_box = HBoxContainer.new()
	_aspect_box.add_theme_constant_override("separation", 4)
	row.add_child(_aspect_box)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_save_btn = SabaccButton.make("Save", SabaccButton.Style.PRIMARY, "", true)
	_save_btn.custom_minimum_size = Vector2(110, 52)
	_save_btn.pressed.connect(_save)
	row.add_child(_save_btn)
	# tabs (portrait)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_tab_pool = SabaccButton.make("Cards", SabaccButton.Style.PRIMARY)
	_tab_pool.pressed.connect(func(): _show_pool = true; _on_resize())
	_tab_deck = SabaccButton.make("Deck", SabaccButton.Style.GHOST)
	_tab_deck.pressed.connect(func(): _show_pool = false; _on_resize())
	_tab_pool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_tab_pool)
	_tabs.add_child(_tab_deck)
	body.add_child(_tabs)
	_build_pool()
	_build_deck_panel()
	_refresh_identity()
	_refresh_pool()
	_refresh_list()


# ---------------------------------------------------------------- pool

func _build_pool() -> void:
	_pool = Control.new()
	body.add_child(_pool)
	_pool_filters = CardFilters.new()
	_pool_filters.available_types = ["unit", "event", "upgrade"]
	_pool_filters.deck_mode = true
	_pool_filters.unlocked_only = true
	_pool.add_child(_pool_filters)
	_pool_filters.changed.connect(_refresh_pool)
	_pool_count = UIKit.label("", 16, Sabacc.C_DIM)
	_pool.add_child(_pool_count)
	_pool_scroll = CardScroll.new()
	_pool.add_child(_pool_scroll)


func _deck_aspects() -> Array:
	var out: Array = []
	for id in [deck.get("leader", ""), deck.get("base", "")]:
		out.append_array(CardDB.card(id).get("aspects", []))
	return out


func _refresh_pool() -> void:
	var aspects := _deck_aspects()
	var results: Array = _pool_filters.results().filter(func(id):
		var card := CardDB.card(id)
		if card.get("type", "") not in _pool_filters.available_types:
			return false
		if _pool_filters.deck_aspects_only and not aspects.is_empty():
			return card.get("aspects", []).all(func(aspect): return aspect in aspects)
		return true)
	_pool_count.text = "%d cards" % results.size() if not results.is_empty() else "No cards match these filters"
	_pool_scroll.show_cards(results, _make_pool_tile)


## Effective cost with aspect penalties (+2 per icon the leader/base don't cover).
func _cost_with_penalty(c: Dictionary) -> int:
	var pool := _deck_aspects()
	var cost := int(c.get("cost", 0))
	for a in c.get("aspects", []):
		var i := pool.find(a)
		if i >= 0:
			pool.remove_at(i)
		else:
			cost += 2
	return cost


func _make_pool_tile(id: String, cell: Vector2) -> Control:
	var tile := Control.new()
	var card := CardView.create(id)
	tile.add_child(card)
	CardScroll.place_card(card, cell)
	card.dim = not Progression.owns(id)
	if deck.get("leader", "") != "":
		card.cost_override = _cost_with_penalty(CardDB.card(id))
	card.tapped.connect(func(c): _add(id, c))
	card.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
	var badge := CountBadge.new()
	badge.count = int(deck["cards"].get(id, 0))
	badge.position = cell - Vector2(34, 34)
	badge.name = "Badge"
	tile.add_child(badge)
	return tile


func _update_badge(id: String) -> void:
	var tile: Control = _pool_scroll.tile_for(id)
	if tile:
		(tile.get_node("Badge") as CountBadge).count = int(deck["cards"].get(id, 0))


func _add(id: String, cv: CardView) -> void:
	if not Progression.owns(id):
		Fx.float_text(self, cv.get_global_rect().get_center(), "Unlock in card packs", Sabacc.C_GOLD, 23)
		return
	var n := int(deck["cards"].get(id, 0))
	if n >= 3:
		Fx.float_text(self, cv.get_global_rect().get_center(), "Max 3", Sabacc.C_EMPIRE, 26)
		return
	deck["cards"][id] = n + 1
	dirty = true
	Sfx.play("draw", 1.2)
	# little fly-to-deck flourish
	var ghost := CardView.create(id)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ghost)
	ghost.pivot_offset = Vector2.ZERO
	ghost.global_position = cv.global_position
	ghost.scale = cv.scale
	var target := _tab_deck.get_global_rect().get_center() if portrait else _deck_panel.get_global_rect().get_center()
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "global_position", target, Sabacc.anim(0.3)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "scale", cv.scale * 0.2, Sabacc.anim(0.3))
	tw.chain().tween_callback(ghost.queue_free)
	_update_badge(id)
	_refresh_list()


func _remove(id: String) -> void:
	var n := int(deck["cards"].get(id, 0))
	if n <= 1:
		deck["cards"].erase(id)
	else:
		deck["cards"][id] = n - 1
	dirty = true
	Sfx.play("click")
	_update_badge(id)
	_refresh_list()


# ---------------------------------------------------------------- deck list

func _build_deck_panel() -> void:
	_deck_panel = UIKit.panel(Color(Sabacc.C_PANEL, 0.92), Sabacc.C_LINE, 12, 0)
	body.add_child(_deck_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_deck_panel.add_child(v)
	_summary = UIKit.label("", 18, Sabacc.C_TEXT)
	v.add_child(_summary)
	_curve = CurveBars.new()
	_curve.custom_minimum_size = Vector2(0, 70)
	v.add_child(_curve)
	_problems = UIKit.label("", 14, Sabacc.C_GOLD)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_problems)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_list_box)


func _refresh_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	var ids: Array = deck["cards"].keys()
	ids.sort_custom(func(a, b):
		var ca := CardDB.card(a)
		var cb := CardDB.card(b)
		if int(ca.get("cost", 0)) != int(cb.get("cost", 0)):
			return int(ca.get("cost", 0)) < int(cb.get("cost", 0))
		return ca.get("name", "") < cb.get("name", ""))
	var counts := {"unit": 0, "event": 0, "upgrade": 0}
	var curve := [0, 0, 0, 0, 0, 0, 0, 0]
	var total := 0
	for id in ids:
		var c := CardDB.card(id)
		var n := int(deck["cards"][id])
		total += n
		var t: String = c.get("type", "")
		counts[t] = int(counts.get(t, 0)) + n
		curve[mini(int(c.get("cost", 0)), 7)] += n
		_list_box.add_child(_row(id, c, n))
	_summary.text = "%d / 50 cards   ·   %d units · %d events · %d upgrades" % [total, counts["unit"], counts["event"], counts["upgrade"]]
	_summary.add_theme_color_override("font_color", Sabacc.C_GOOD if total >= 50 else Sabacc.C_TEXT)
	_curve.values = curve
	_curve.queue_redraw()
	var errs: Array = []
	if deck.get("leader", "") == "":
		errs.append("Choose a leader.")
	if deck.get("base", "") == "":
		errs.append("Choose a base.")
	if errs.is_empty():
		errs = DeckBuilder.validate(CardDB.lib, RuleSet.premier(), deck["leader"], deck["base"], Save.deck_list(deck))
	_problems.text = "✓ Legal Premier deck" if errs.is_empty() else "\n".join(errs.slice(0, 4))
	_problems.add_theme_color_override("font_color", Sabacc.C_GOOD if errs.is_empty() else Sabacc.C_GOLD)
	_tab_deck.text = "Deck (%d)" % total


func _row(id: String, c: Dictionary, n: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var cost := UIKit.label(str(int(c.get("cost", 0))), 18, Sabacc.C_COST, HORIZONTAL_ALIGNMENT_CENTER)
	cost.custom_minimum_size.x = 28
	h.add_child(cost)
	for a in c.get("aspects", []):
		h.add_child(AspectIcon.make(a, 20.0))
	var nm := UIKit.label(c.get("name", id) + (" — " + c.get("subtitle", "") if c.get("subtitle", "") != "" else ""), 16, Sabacc.C_TEXT)
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.mouse_filter = Control.MOUSE_FILTER_STOP
	nm.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			InspectOverlay.open(self, id, nm.get_global_rect()))
	h.add_child(nm)
	var cnt := UIKit.label("×%d" % n, 18, Sabacc.C_ACCENT)
	h.add_child(cnt)
	var minus := SabaccButton.make("−", SabaccButton.Style.GHOST)
	minus.custom_minimum_size = Vector2(44, 40)
	minus.pressed.connect(func(): _remove(id))
	h.add_child(minus)
	var plus := SabaccButton.make("+", SabaccButton.Style.GHOST)
	plus.custom_minimum_size = Vector2(44, 40)
	plus.pressed.connect(func():
		if int(deck["cards"].get(id, 0)) < 3:
			deck["cards"][id] = int(deck["cards"].get(id, 0)) + 1
			dirty = true
			Sfx.play("draw", 1.2)
			_refresh_list()
			_update_badge(id))
	h.add_child(plus)
	return h


# ---------------------------------------------------------------- identity

func _refresh_identity() -> void:
	Appearance.set_deck(deck.get("leader", ""), deck.get("base", ""), Save.deck_list(deck))
	_leader_slot.set_card(deck.get("leader", ""))
	_base_slot.set_card(deck.get("base", ""))
	for c in _aspect_box.get_children():
		c.queue_free()
	var row := AspectIcon.row_for(deck.get("leader", ""), deck.get("base", ""), 34.0)
	for c in row.get_children():
		row.remove_child(c)
		_aspect_box.add_child(c)
		UIKit.pop_in(c)
	row.queue_free()


func _pick(kind: String) -> void:
	var slot: Control = _leader_slot if kind == "leader" else _base_slot
	var picker := CardPicker.open(self, kind, slot.get_global_rect(), {"ids": Progression.owned_ids(), "browse_filters": true})
	picker.picked.connect(func(id: String):
		deck[kind] = id
		if kind == "leader" and deck.get("name", "") in ["", "New deck"]:
			deck["name"] = CardDB.card(id).get("name", "Deck")
			_name_edit.text = deck["name"]
		dirty = true
		_refresh_identity()
		_refresh_pool()
		_refresh_list())


func _pick_icon() -> void:
	var mp := ModalPanel.open(self, 520.0, Sabacc.C_ACCENT)
	mp.dismiss_on_backdrop = true
	mp.text("DECK ICON", 24, Sabacc.C_ACCENT)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	mp.add(grid)
	for g in Sabacc.DECK_ICONS:
		var b := SabaccButton.make("", SabaccButton.Style.GOLD if g == deck.get("icon", "") else SabaccButton.Style.GHOST, g)
		b.custom_minimum_size = Vector2(64, 60)
		b.tooltip_text = g.capitalize()
		b.pressed.connect(func():
			deck["icon"] = g
			dirty = true
			_icon_btn.glyph = g
			if _icon_btn._icon:
				_icon_btn._icon.glyph = g
			mp.close())
		grid.add_child(b)


func _toggle_mark() -> void:
	deck["marked"] = not deck.get("marked", false)
	dirty = true
	if _mark_btn._icon:
		_mark_btn._icon.color = Sabacc.C_GOLD if deck["marked"] else Sabacc.C_LINE.lightened(0.3)
	Fx.float_text(self, _mark_btn.get_global_rect().get_center(), "Marked" if deck["marked"] else "Unmarked", Sabacc.C_GOLD, 22)


func _save() -> void:
	if not Progression.deck_owned(deck):
		Fx.float_text(self, _save_btn.get_global_rect().get_center(), "Deck contains locked cards", Sabacc.C_EMPIRE, 23)
		return
	if deck.get("name", "").strip_edges() == "":
		deck["name"] = "Untitled deck"
	Save.save_deck(deck)
	dirty = false
	Sfx.play("deploy", 1.2)
	Fx.float_text(self, _save_btn.get_global_rect().get_center(), "Saved", Sabacc.C_GOOD, 26)


# ---------------------------------------------------------------- layout

func relayout(p: bool, r: Rect2) -> void:
	var ident_h := 96.0 if p else 120.0
	_ident.position = Vector2.ZERO
	_ident.size = Vector2(r.size.x, ident_h)
	_leader_slot.custom_minimum_size = Vector2(ident_h * 1.4, ident_h)
	_base_slot.custom_minimum_size = Vector2(ident_h * 1.4, ident_h)
	var meta_row: Control = body.get_node("MetaRow")
	meta_row.position = Vector2(0, ident_h + 8)
	meta_row.size = Vector2(r.size.x, 52)
	var top := ident_h + 70
	if p:
		_tabs.visible = true
		_tabs.position = Vector2(0, top)
		_tabs.size = Vector2(r.size.x, 52)
		top += 60
		_pool.visible = _show_pool
		_deck_panel.visible = not _show_pool
		_pool.position = Vector2(0, top)
		_pool.size = Vector2(r.size.x, r.size.y - top)
		_deck_panel.position = Vector2(0, top)
		_deck_panel.size = Vector2(r.size.x, r.size.y - top)
	else:
		_tabs.visible = false
		_pool.visible = true
		_deck_panel.visible = true
		var pw := r.size.x * 0.6
		_pool.position = Vector2(0, top)
		_pool.size = Vector2(pw - 10, r.size.y - top)
		_deck_panel.position = Vector2(pw, top)
		_deck_panel.size = Vector2(r.size.x - pw, r.size.y - top)
	_pool_filters.size = Vector2(_pool.size.x, 0)
	var filter_height := _pool_filters.get_combined_minimum_size().y
	_pool_count.position.y = filter_height + 4
	_pool_scroll.position.y = filter_height + 28
	_pool_scroll.size = Vector2(_pool.size.x, maxf(0, _pool.size.y - _pool_scroll.position.y))
	_tab_pool.style = SabaccButton.Style.PRIMARY if _show_pool else SabaccButton.Style.GHOST


## Leader/base slot: shows the chosen card (or an empty dashed frame).
class SlotCard extends Control:
	signal pressed
	var kind := "leader"
	var _tex: Texture2D
	var _id := ""
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_card(id: String) -> void:
		_id = id
		_tex = null
		if id != "":
			var t := Art.request(CardDB.card(id).get("art", id), func(tx): _tex = tx; queue_redraw())
			if t:
				_tex = t
		queue_redraw()

	func _process(dt: float) -> void:
		if _id == "":
			_t += dt
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if _tex and _tex != Art.placeholder:
			draw_texture_rect(_tex, r, false)
		else:
			var k := 0.5 + 0.5 * sin(_t * 3.0)
			draw_rect(r, Color(0.04, 0.07, 0.1, 0.9))
			draw_rect(r, Color(Sabacc.C_ACCENT, 0.4 + 0.4 * k), false, 2.0)
			UIKit.draw_fit(self, Sabacc.font_title, Vector2(0, size.y / 2.0 + 8), "+ " + kind.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Sabacc.C_ACCENT)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("click")
			pressed.emit()
			accept_event()


## Small "×N" pip over pool cards already in the deck.
class CountBadge extends Control:
	var count := 0:
		set(v):
			count = v
			visible = v > 0
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(30, 30)
		visible = count > 0

	func _draw() -> void:
		draw_circle(Vector2(15, 15), 15, Sabacc.C_ACCENT)
		UIKit.draw_fit(self, Sabacc.font_title, Vector2(0, 22), "×%d" % count, HORIZONTAL_ALIGNMENT_CENTER, 30, 16, Color.BLACK)


## Mana-curve bars 0..7+.
class CurveBars extends Control:
	var values: Array = [0, 0, 0, 0, 0, 0, 0, 0]

	func _draw() -> void:
		var mx := 1
		for v in values:
			mx = maxi(mx, int(v))
		var w := size.x / values.size()
		for i in values.size():
			var h := (size.y - 18) * float(values[i]) / mx
			draw_rect(Rect2(Vector2(i * w + 4, size.y - 18 - h), Vector2(w - 8, h)), Sabacc.C_COST)
			UIKit.draw_fit(self, Sabacc.font_title, Vector2(i * w, size.y - 2), str(i) + ("+" if i == 7 else ""), HORIZONTAL_ALIGNMENT_CENTER, w, 13, Sabacc.C_DIM)
			if values[i] > 0:
				UIKit.draw_fit(self, Sabacc.font_title, Vector2(i * w, size.y - 22 - h), str(values[i]), HORIZONTAL_ALIGNMENT_CENTER, w, 12, Sabacc.C_TEXT)
